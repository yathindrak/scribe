defmodule SocialScribe.AIContentGeneratorTest do
  use SocialScribe.DataCase

  import Tesla.Mock
  import SocialScribe.MeetingsFixtures
  import SocialScribe.AutomationsFixtures
  import SocialScribe.AccountsFixtures

  alias SocialScribe.AIContentGenerator
  alias SocialScribe.Meetings

  setup do
    Application.put_env(:social_scribe, :gemini_api_key, "test_gemini_key")
    on_exit(fn -> Application.delete_env(:social_scribe, :gemini_api_key) end)
    :ok
  end

  defp full_meeting_fixture do
    meeting = meeting_fixture()
    meeting_participant_fixture(%{meeting_id: meeting.id, name: "Alice"})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{"speaker" => "Alice", "words" => [%{"text" => "Hello"}, %{"text" => "world"}]}
        ]
      }
    })

    Meetings.get_meeting_with_details(meeting.id)
  end

  describe "generate_follow_up_email/1" do
    test "returns {:error, :no_participants} when meeting has no participants" do
      # meeting_fixture creates a meeting with no participants by default
      meeting = meeting_fixture()
      loaded = Meetings.get_meeting_with_details(meeting.id)

      assert {:error, :no_participants} = AIContentGenerator.generate_follow_up_email(loaded)
    end

    test "returns {:error, {:config_error, _}} when API key is missing" do
      Application.delete_env(:social_scribe, :gemini_api_key)
      meeting = full_meeting_fixture()

      assert {:error, {:config_error, _}} = AIContentGenerator.generate_follow_up_email(meeting)
    end

    test "returns {:ok, text} on success" do
      meeting = full_meeting_fixture()

      mock(fn %{method: :post, url: url} ->
        assert String.contains?(url, "generativelanguage.googleapis.com")

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "candidates" => [
               %{
                 "content" => %{
                   "parts" => [%{"text" => "Dear Team, ..."}]
                 }
               }
             ]
           }
         }}
      end)

      assert {:ok, text} = AIContentGenerator.generate_follow_up_email(meeting)
      assert text == "Dear Team, ..."
    end

    test "returns {:error, {:api_error, status, body}} on non-200 from Gemini" do
      meeting = full_meeting_fixture()

      mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 429, body: %{"error" => %{"message" => "Rate limit exceeded"}}}}
      end)

      assert {:error, {:api_error, 429, _}} = AIContentGenerator.generate_follow_up_email(meeting)
    end

    test "returns {:error, {:http_error, reason}} on connection failure" do
      meeting = full_meeting_fixture()

      mock(fn %{method: :post} -> {:error, :econnrefused} end)

      assert {:error, {:http_error, :econnrefused}} =
               AIContentGenerator.generate_follow_up_email(meeting)
    end

    test "returns {:error, {:parsing_error, _, _}} when Gemini response has no text" do
      meeting = full_meeting_fixture()

      mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{"candidates" => [%{"content" => %{"parts" => []}}]}
         }}
      end)

      assert {:error, {:parsing_error, _, _}} =
               AIContentGenerator.generate_follow_up_email(meeting)
    end
  end

  describe "generate_hubspot_suggestions/1" do
    test "returns {:error, :no_participants} when meeting has no participants" do
      meeting = meeting_fixture()
      loaded = Meetings.get_meeting_with_details(meeting.id)

      assert {:error, :no_participants} = AIContentGenerator.generate_hubspot_suggestions(loaded)
    end

    test "parses valid JSON array from Gemini response" do
      meeting = full_meeting_fixture()

      json_response = """
      [{"field": "phone", "value": "555-1234", "context": "mentioned phone", "timestamp": "01:00"}]
      """

      mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "candidates" => [
               %{"content" => %{"parts" => [%{"text" => json_response}]}}
             ]
           }
         }}
      end)

      assert {:ok, suggestions} = AIContentGenerator.generate_hubspot_suggestions(meeting)
      assert [%{field: "phone", value: "555-1234"}] = suggestions
    end

    test "returns {:ok, []} when Gemini returns empty JSON array" do
      meeting = full_meeting_fixture()

      mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "candidates" => [
               %{"content" => %{"parts" => [%{"text" => "[]"}]}}
             ]
           }
         }}
      end)

      assert {:ok, []} = AIContentGenerator.generate_hubspot_suggestions(meeting)
    end

    test "returns {:ok, []} when Gemini returns invalid JSON" do
      meeting = full_meeting_fixture()

      mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "candidates" => [
               %{"content" => %{"parts" => [%{"text" => "not valid json"}]}}
             ]
           }
         }}
      end)

      assert {:ok, []} = AIContentGenerator.generate_hubspot_suggestions(meeting)
    end

    test "strips markdown code fences from Gemini response" do
      meeting = full_meeting_fixture()

      json_with_fences = """
      ```json
      [{"field": "email", "value": "test@example.com", "context": "email mentioned", "timestamp": "02:00"}]
      ```
      """

      mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "candidates" => [
               %{"content" => %{"parts" => [%{"text" => json_with_fences}]}}
             ]
           }
         }}
      end)

      assert {:ok, [suggestion]} = AIContentGenerator.generate_hubspot_suggestions(meeting)
      assert suggestion.field == "email"
      assert suggestion.value == "test@example.com"
    end
  end

  describe "generate_salesforce_suggestions/1" do
    test "returns {:error, :no_participants} when meeting has no participants" do
      meeting = meeting_fixture()
      loaded = Meetings.get_meeting_with_details(meeting.id)

      assert {:error, :no_participants} =
               AIContentGenerator.generate_salesforce_suggestions(loaded)
    end

    test "parses valid JSON array with Salesforce field names" do
      meeting = full_meeting_fixture()

      json_response = """
      [{"field": "MobilePhone", "value": "555-9999", "context": "mobile mentioned", "timestamp": "03:00"}]
      """

      mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "candidates" => [
               %{"content" => %{"parts" => [%{"text" => json_response}]}}
             ]
           }
         }}
      end)

      assert {:ok, [suggestion]} = AIContentGenerator.generate_salesforce_suggestions(meeting)
      assert suggestion.field == "MobilePhone"
      assert suggestion.value == "555-9999"
    end
  end

  describe "generate_automation/2" do
    test "returns {:error, :no_participants} when meeting has no participants" do
      user = user_fixture()
      automation = automation_fixture(%{user_id: user.id})
      meeting = meeting_fixture()
      loaded = Meetings.get_meeting_with_details(meeting.id)

      assert {:error, :no_participants} =
               AIContentGenerator.generate_automation(automation, loaded)
    end

    test "returns {:ok, text} on success" do
      user = user_fixture()
      automation = automation_fixture(%{user_id: user.id})
      meeting = full_meeting_fixture()

      mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "candidates" => [
               %{"content" => %{"parts" => [%{"text" => "Great insights from today's meeting!"}]}}
             ]
           }
         }}
      end)

      assert {:ok, "Great insights from today's meeting!"} =
               AIContentGenerator.generate_automation(automation, meeting)
    end
  end
end
