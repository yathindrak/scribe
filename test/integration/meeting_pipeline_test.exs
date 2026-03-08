defmodule SocialScribe.Integration.MeetingPipelineTest do
  @moduledoc """
  Pipeline integration tests for the full meeting flow.

  These tests span multiple modules and workers to verify that the pieces
  wire together correctly and produce the right DB state.  External APIs
  (Google Calendar, Recall.ai, Gemini, Salesforce, HubSpot) are replaced
  with Mox mocks — no network calls, no real meeting required.

  Covered flows
  -------------
  1. Recording pipeline
     Google Calendar sync → Recall.ai bot dispatch → BotStatusPoller
     (transcript + participants) → AIContentGenerationWorker (email draft)

  2. Salesforce CRM
     Contact search → AI suggestions from transcript → merge with contact
     data → apply updates back to Salesforce

  3. HubSpot CRM
     Same flow as Salesforce, exercising the HubSpot-specific modules

  NOT covered here — LinkedIn & Facebook
  ---------------------------------------
  LinkedIn and Facebook are used exclusively for posting automation-generated
  content to social media (via `SocialScribe.Poster`).  That is a separate,
  user-triggered action that has nothing to do with the recording pipeline or
  CRM contact enrichment — it only fires after a user explicitly clicks
  "Post" on an automation result in the UI.  Those integrations belong in a
  dedicated social-posting integration test, not here.
  """

  use SocialScribe.DataCase, async: true

  import Mox
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingInfoExample
  import SocialScribe.MeetingTranscriptExample
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.BotsFixtures

  alias SocialScribe.CalendarSyncronizer
  alias SocialScribe.Bots
  alias SocialScribe.Meetings
  alias SocialScribe.Workers.BotStatusPoller
  alias SocialScribe.Workers.AIContentGenerationWorker

  alias SocialScribe.GoogleCalendarApiMock
  alias SocialScribe.RecallApiMock
  alias SocialScribe.AIContentGeneratorMock
  alias SocialScribe.SalesforceApiMock
  alias SocialScribe.HubspotApiMock

  # ---------------------------------------------------------------------------
  # Shared fixture data
  # ---------------------------------------------------------------------------

  @google_meet_event %{
    "id" => "pipeline-meet-event-001",
    "summary" => "Pipeline Test Meeting",
    "hangoutLink" => "https://meet.google.com/pipeline-test-abc",
    "start" => %{"dateTime" => "2026-03-08T14:00:00Z"},
    "end" => %{"dateTime" => "2026-03-08T15:00:00Z"},
    "status" => "confirmed",
    "htmlLink" => "https://calendar.google.com/calendar/event?eid=pipeline-meet-event-001"
  }

  @recall_bot_id "pipeline-recall-bot-001"

  @mock_bot_create_response %{
    id: @recall_bot_id,
    status_changes: [%{code: "ready"}]
  }

  @mock_bot_done meeting_info_example(%{id: @recall_bot_id})
  @mock_transcript meeting_transcript_example()

  @mock_participants [
    %{id: 100, name: "Alice", is_host: true},
    %{id: 101, name: "Bob", is_host: false}
  ]

  @generated_email "Subject: Follow-up\n\nHi Team, great chat!"

  # ---------------------------------------------------------------------------
  # 1. Recording pipeline
  # ---------------------------------------------------------------------------

  describe "recording pipeline" do
    setup :verify_on_exit!

    setup do
      stub_with(GoogleCalendarApiMock, SocialScribe.GoogleCalendar)
      stub_with(SocialScribe.TokenRefresherMock, SocialScribe.TokenRefresher)
      stub_with(RecallApiMock, SocialScribe.Recall)
      stub_with(AIContentGeneratorMock, SocialScribe.AIContentGenerator)
      :ok
    end

    test "syncs calendar → dispatches bot → processes recording → generates AI content" do
      # --- Seed ---
      user = user_fixture()

      user_credential_fixture(%{
        user_id: user.id,
        provider: "google",
        token: "valid-google-token",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      # --- Step 1: Calendar sync ---
      expect(GoogleCalendarApiMock, :list_events, fn _token, _start, _end, "primary" ->
        {:ok, %{"items" => [@google_meet_event]}}
      end)

      assert {:ok, :sync_complete} = CalendarSyncronizer.sync_events_for_user(user)

      calendar_event =
        Repo.get_by!(SocialScribe.Calendar.CalendarEvent,
          google_event_id: "pipeline-meet-event-001"
        )

      assert calendar_event.summary == "Pipeline Test Meeting"
      assert calendar_event.hangout_link == "https://meet.google.com/pipeline-test-abc"

      # --- Step 2: Bot dispatch (user toggles "Record") ---
      expect(RecallApiMock, :create_bot, fn _meeting_url, _join_at ->
        {:ok, %{status: 200, body: @mock_bot_create_response}}
      end)

      assert {:ok, bot_record} = Bots.create_and_dispatch_bot(user, calendar_event)
      assert bot_record.recall_bot_id == @recall_bot_id
      assert bot_record.status == "ready"

      # --- Step 3: BotStatusPoller detects "done", creates Meeting ---
      expect(RecallApiMock, :get_bot, fn @recall_bot_id ->
        {:ok, %Tesla.Env{body: @mock_bot_done}}
      end)

      expect(RecallApiMock, :get_bot_transcript, fn @recall_bot_id ->
        {:ok, %Tesla.Env{body: @mock_transcript}}
      end)

      expect(RecallApiMock, :get_bot_participants, fn @recall_bot_id ->
        {:ok, %Tesla.Env{body: @mock_participants}}
      end)

      assert BotStatusPoller.perform(%Oban.Job{}) == :ok

      meeting = Meetings.get_meeting_by_recall_bot_id(bot_record.id)
      assert meeting != nil
      assert meeting.title == "Pipeline Test Meeting"

      transcript = Repo.get_by!(Meetings.MeetingTranscript, meeting_id: meeting.id)
      assert transcript.content["data"] == @mock_transcript |> Jason.encode!() |> Jason.decode!()

      participants =
        Repo.all(from p in Meetings.MeetingParticipant, where: p.meeting_id == ^meeting.id)

      assert length(participants) == 2
      assert Enum.any?(participants, &(&1.name == "Alice" and &1.is_host == true))
      assert Enum.any?(participants, &(&1.name == "Bob" and &1.is_host == false))

      assert_enqueued(worker: AIContentGenerationWorker, args: %{"meeting_id" => meeting.id})

      # --- Step 4: AI content generation ---
      expect(AIContentGeneratorMock, :generate_follow_up_email, fn _meeting ->
        {:ok, @generated_email}
      end)

      assert AIContentGenerationWorker.perform(%Oban.Job{args: %{"meeting_id" => meeting.id}}) ==
               :ok

      updated_meeting = Meetings.get_meeting_with_details(meeting.id)
      assert updated_meeting.follow_up_email == @generated_email
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Salesforce CRM flow
  # User-triggered from the meeting show page:
  #   search contacts → AI suggestions → merge with contact → apply updates
  # ---------------------------------------------------------------------------

  @mock_sf_contact %{
    id: "003SALESFORCE001",
    firstname: "Alice",
    lastname: "Smith",
    email: "alice@example.com",
    phone: nil,
    mobile_phone: nil,
    title: nil,
    department: nil,
    mailing_street: nil,
    mailing_city: nil,
    mailing_state: nil,
    mailing_postal_code: nil,
    mailing_country: nil
  }

  @mock_sf_ai_suggestions [
    %{
      field: "Phone",
      value: "+1-555-0100",
      context: "Alice said her number is +1-555-0100",
      timestamp: 15.0
    },
    %{
      field: "Title",
      value: "VP of Engineering",
      context: "Alice introduced herself as VP of Engineering",
      timestamp: 42.0
    }
  ]

  describe "salesforce crm flow" do
    setup :verify_on_exit!

    setup do
      stub_with(AIContentGeneratorMock, SocialScribe.AIContentGenerator)
      stub_with(SalesforceApiMock, SocialScribe.SalesforceApi)
      :ok
    end

    test "search → suggestions → merge → apply updates" do
      user = user_fixture()

      salesforce_credential =
        user_credential_fixture(%{
          user_id: user.id,
          provider: "salesforce",
          token: "sf-access-token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      calendar_event = calendar_event_fixture(%{user_id: user.id})
      recall_bot = recall_bot_fixture(%{calendar_event_id: calendar_event.id, user_id: user.id})

      meeting =
        meeting_fixture(%{
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id,
          title: "Product Sync with Alice"
        })

      meeting = Meetings.get_meeting_with_details(meeting.id)

      # Step 1: Search contacts
      expect(SalesforceApiMock, :search_contacts, fn _credential, "Alice Smith" ->
        {:ok, [@mock_sf_contact]}
      end)

      {:ok, contacts} =
        SocialScribe.SalesforceApiBehaviour.search_contacts(salesforce_credential, "Alice Smith")

      assert length(contacts) == 1
      contact = List.first(contacts)
      assert contact.email == "alice@example.com"

      # Step 2: Generate AI suggestions from transcript
      expect(AIContentGeneratorMock, :generate_salesforce_suggestions, fn _meeting ->
        {:ok, @mock_sf_ai_suggestions}
      end)

      {:ok, suggestions} =
        SocialScribe.SalesforceSuggestions.generate_suggestions_from_meeting(meeting)

      assert length(suggestions) == 2
      assert Enum.any?(suggestions, &(&1.field == "Phone" and &1.new_value == "+1-555-0100"))
      assert Enum.any?(suggestions, &(&1.field == "Title" and &1.new_value == "VP of Engineering"))

      # Step 3: Merge — contact had nil for both fields, so both survive
      merged = SocialScribe.SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert length(merged) == 2
      phone = Enum.find(merged, &(&1.field == "Phone"))
      assert phone.current_value == nil
      assert phone.new_value == "+1-555-0100"
      assert phone.apply == true

      # Step 4: Apply updates
      updates = %{"Phone" => "+1-555-0100", "Title" => "VP of Engineering"}

      expect(SalesforceApiMock, :update_contact, fn _credential, "003SALESFORCE001", ^updates ->
        {:ok, %{}}
      end)

      assert {:ok, _} =
               SocialScribe.SalesforceApiBehaviour.update_contact(
                 salesforce_credential,
                 contact.id,
                 updates
               )
    end

    test "merge drops suggestions where contact already has the same value" do
      contact_with_phone = Map.put(@mock_sf_contact, :phone, "+1-555-0100")

      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "+1-555-0100",
          context: "...",
          timestamp: 1.0,
          apply: true,
          has_change: true
        },
        %{
          field: "Title",
          label: "Job Title",
          current_value: nil,
          new_value: "VP of Engineering",
          context: "...",
          timestamp: 2.0,
          apply: true,
          has_change: true
        }
      ]

      merged = SocialScribe.SalesforceSuggestions.merge_with_contact(suggestions, contact_with_phone)

      assert length(merged) == 1
      assert List.first(merged).field == "Title"
    end
  end

  # ---------------------------------------------------------------------------
  # 3. HubSpot CRM flow
  # Same user-triggered path as Salesforce but through HubSpot modules.
  # ---------------------------------------------------------------------------

  @mock_hs_contact %{
    id: "hs-contact-001",
    firstname: "Bob",
    lastname: "Jones",
    email: "bob@example.com",
    phone: nil,
    jobtitle: nil,
    company: "Acme Corp"
  }

  @mock_hs_ai_suggestions [
    %{
      field: "phone",
      value: "+1-555-0200",
      context: "Bob mentioned his direct line",
      timestamp: 10.0
    },
    %{
      field: "jobtitle",
      value: "Director of Sales",
      context: "Bob introduced himself as Director of Sales",
      timestamp: 30.0
    }
  ]

  describe "hubspot crm flow" do
    setup :verify_on_exit!

    setup do
      stub_with(AIContentGeneratorMock, SocialScribe.AIContentGenerator)
      stub_with(HubspotApiMock, SocialScribe.HubspotApi)
      :ok
    end

    test "search → suggestions → merge → apply updates" do
      user = user_fixture()

      hubspot_credential =
        user_credential_fixture(%{
          user_id: user.id,
          provider: "hubspot",
          token: "hs-access-token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      calendar_event = calendar_event_fixture(%{user_id: user.id})
      recall_bot = recall_bot_fixture(%{calendar_event_id: calendar_event.id, user_id: user.id})

      meeting =
        meeting_fixture(%{
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id,
          title: "Sales Call with Bob"
        })

      meeting = Meetings.get_meeting_with_details(meeting.id)

      # Step 1: Search contacts
      expect(HubspotApiMock, :search_contacts, fn _credential, "Bob Jones" ->
        {:ok, [@mock_hs_contact]}
      end)

      {:ok, contacts} =
        SocialScribe.HubspotApiBehaviour.search_contacts(hubspot_credential, "Bob Jones")

      assert length(contacts) == 1
      contact = List.first(contacts)
      assert contact.email == "bob@example.com"

      # Step 2: Generate AI suggestions from transcript
      expect(AIContentGeneratorMock, :generate_hubspot_suggestions, fn _meeting ->
        {:ok, @mock_hs_ai_suggestions}
      end)

      {:ok, suggestions} =
        SocialScribe.HubspotSuggestions.generate_suggestions_from_meeting(meeting)

      assert length(suggestions) == 2
      assert Enum.any?(suggestions, &(&1.field == "phone" and &1.new_value == "+1-555-0200"))
      assert Enum.any?(suggestions, &(&1.field == "jobtitle" and &1.new_value == "Director of Sales"))

      # Step 3: Merge — contact had nil for phone and jobtitle, so both survive
      merged = SocialScribe.HubspotSuggestions.merge_with_contact(suggestions, contact)

      assert length(merged) == 2
      phone = Enum.find(merged, &(&1.field == "phone"))
      assert phone.current_value == nil
      assert phone.new_value == "+1-555-0200"

      # Step 4: Apply updates
      updates = %{"phone" => "+1-555-0200", "jobtitle" => "Director of Sales"}

      expect(HubspotApiMock, :update_contact, fn _credential, "hs-contact-001", ^updates ->
        {:ok, %{}}
      end)

      assert {:ok, _} =
               SocialScribe.HubspotApiBehaviour.update_contact(
                 hubspot_credential,
                 contact.id,
                 updates
               )
    end

    test "merge drops suggestions where contact already has the same value" do
      contact_with_phone = Map.put(@mock_hs_contact, :phone, "+1-555-0200")

      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "+1-555-0200",
          context: "...",
          timestamp: 1.0,
          apply: true,
          has_change: true
        },
        %{
          field: "jobtitle",
          label: "Job Title",
          current_value: nil,
          new_value: "Director of Sales",
          context: "...",
          timestamp: 2.0,
          apply: true,
          has_change: true
        }
      ]

      merged = SocialScribe.HubspotSuggestions.merge_with_contact(suggestions, contact_with_phone)

      assert length(merged) == 1
      assert List.first(merged).field == "jobtitle"
    end
  end
end
