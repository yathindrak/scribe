defmodule SocialScribe.HubspotSuggestionsTest do
  use SocialScribe.DataCase

  import Mox
  import SocialScribe.AccountsFixtures

  alias SocialScribe.HubspotSuggestions

  setup :verify_on_exit!

  describe "generate_suggestions/3" do
    test "returns filtered suggestions with contact data merged" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      mock_contact = %{
        id: "123",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil,
        company: "Acme Corp"
      }

      ai_suggestions = [
        %{field: "phone", value: "555-1234", context: "Mentioned on call"},
        %{field: "company", value: "Acme Corp", context: "Works at Acme"}
      ]

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "123"
        {:ok, mock_contact}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok, ai_suggestions}
      end)

      meeting = %{id: 1, transcript: "some transcript"}

      {:ok, %{contact: contact, suggestions: suggestions}} =
        HubspotSuggestions.generate_suggestions(credential, "123", meeting)

      assert contact.id == "123"
      # phone is new (nil -> "555-1234"), company already matches — filtered out
      assert length(suggestions) == 1
      assert hd(suggestions).field == "phone"
      assert hd(suggestions).new_value == "555-1234"
      assert hd(suggestions).current_value == nil
      assert hd(suggestions).label == "Phone"
      assert hd(suggestions).apply == true
    end

    test "returns error when get_contact fails" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _contact_id ->
        {:error, :not_found}
      end)

      meeting = %{id: 1}

      assert {:error, :not_found} =
               HubspotSuggestions.generate_suggestions(credential, "999", meeting)
    end

    test "returns error when AI suggestions fail" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _contact_id ->
        {:ok, %{id: "123", email: "john@example.com"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:error, :ai_unavailable}
      end)

      meeting = %{id: 1}

      assert {:error, :ai_unavailable} =
               HubspotSuggestions.generate_suggestions(credential, "123", meeting)
    end
  end

  describe "generate_suggestions_from_meeting/1" do
    test "returns suggestions without contact data" do
      ai_suggestions = [
        %{field: "jobtitle", value: "CEO", context: "Introduced as CEO", timestamp: "00:05"}
      ]

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok, ai_suggestions}
      end)

      meeting = %{id: 1, transcript: "some transcript"}

      {:ok, suggestions} = HubspotSuggestions.generate_suggestions_from_meeting(meeting)

      assert length(suggestions) == 1
      suggestion = hd(suggestions)
      assert suggestion.field == "jobtitle"
      assert suggestion.label == "Job Title"
      assert suggestion.new_value == "CEO"
      assert suggestion.current_value == nil
      assert suggestion.apply == true
      assert suggestion.has_change == true
    end

    test "returns error when AI call fails" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               HubspotSuggestions.generate_suggestions_from_meeting(%{id: 1})
    end

    test "unknown field uses field name as label" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok, [%{field: "custom_field", value: "some value", context: "ctx", timestamp: nil}]}
      end)

      {:ok, [suggestion]} = HubspotSuggestions.generate_suggestions_from_meeting(%{id: 1})

      assert suggestion.label == "custom_field"
    end
  end

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "company",
          label: "Company",
          current_value: nil,
          new_value: "Acme Corp",
          context: "Works at Acme",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        phone: nil,
        company: "Acme Corp",
        email: "test@example.com"
      }

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      # Only phone should remain since company already matches
      assert length(result) == 1
      assert hd(result).field == "phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        email: "test@example.com"
      }

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "123", email: "test@example.com"}

      result = HubspotSuggestions.merge_with_contact([], contact)

      assert result == []
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", phone: nil}

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Phone"
    end
  end
end
