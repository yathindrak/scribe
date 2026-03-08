defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  import Mox
  import SocialScribe.AccountsFixtures

  alias SocialScribe.SalesforceSuggestions
  alias SocialScribe.Accounts

  setup :verify_on_exit!

  defp salesforce_credential_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || user_fixture().id

    {:ok, credential} =
      attrs
      |> Enum.into(%{
        user_id: user_id,
        expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
        provider: "salesforce",
        refresh_token: "sf_refresh_#{System.unique_integer([:positive])}",
        token: "sf_token_#{System.unique_integer([:positive])}",
        uid: "005_#{System.unique_integer([:positive])}",
        email: "sf_user@example.com",
        instance_url: "https://test.salesforce.com"
      })
      |> Accounts.create_user_credential()

    credential
  end

  describe "generate_suggestions/3" do
    test "returns filtered suggestions with contact data merged" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock_contact = %{
        id: "003ABC",
        firstname: "Jane",
        lastname: "Smith",
        email: "jane@example.com",
        phone: nil,
        title: "VP of Sales"
      }

      ai_suggestions = [
        %{field: "Phone", value: "555-9876", context: "Gave number", timestamp: "01:00"},
        %{field: "Title", value: "VP of Sales", context: "Already VP", timestamp: "00:30"}
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "003ABC"
        {:ok, mock_contact}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok, ai_suggestions}
      end)

      meeting = %{id: 1, transcript: "some transcript"}

      {:ok, %{contact: contact, suggestions: suggestions}} =
        SalesforceSuggestions.generate_suggestions(credential, "003ABC", meeting)

      assert contact.id == "003ABC"
      # Phone is new (nil -> "555-9876"), Title already matches — filtered out
      assert length(suggestions) == 1
      assert hd(suggestions).field == "Phone"
      assert hd(suggestions).new_value == "555-9876"
      assert hd(suggestions).label == "Phone"
      assert hd(suggestions).apply == true
    end

    test "returns error when get_contact fails" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, _contact_id ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} =
               SalesforceSuggestions.generate_suggestions(credential, "003FAIL", %{id: 1})
    end

    test "returns error when AI suggestions fail" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, _contact_id ->
        {:ok, %{id: "003ABC", email: "jane@example.com"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:error, :ai_unavailable}
      end)

      assert {:error, :ai_unavailable} =
               SalesforceSuggestions.generate_suggestions(credential, "003ABC", %{id: 1})
    end
  end

  describe "generate_suggestions_from_meeting/1" do
    test "returns suggestions without contact data" do
      ai_suggestions = [
        %{field: "Title", value: "CTO", context: "Introduced as CTO", timestamp: "00:10"}
      ]

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok, ai_suggestions}
      end)

      {:ok, suggestions} = SalesforceSuggestions.generate_suggestions_from_meeting(%{id: 1})

      assert length(suggestions) == 1
      suggestion = hd(suggestions)
      assert suggestion.field == "Title"
      assert suggestion.label == "Job Title"
      assert suggestion.new_value == "CTO"
      assert suggestion.current_value == nil
      assert suggestion.apply == true
      assert suggestion.has_change == true
    end

    test "returns error when AI call fails" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               SalesforceSuggestions.generate_suggestions_from_meeting(%{id: 1})
    end

    test "unknown field uses field name as label" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok, [%{field: "CustomField__c", value: "val", context: "ctx", timestamp: nil}]}
      end)

      {:ok, [suggestion]} = SalesforceSuggestions.generate_suggestions_from_meeting(%{id: 1})

      assert suggestion.label == "CustomField__c"
    end
  end

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          timestamp: "01:23",
          apply: false,
          has_change: true
        },
        %{
          field: "Title",
          label: "Job Title",
          current_value: nil,
          new_value: "VP of Sales",
          context: "Introduced as VP of Sales",
          timestamp: "00:45",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003ABC",
        phone: nil,
        title: "VP of Sales",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      # Only phone should remain since title already matches
      assert length(result) == 1
      assert hd(result).field == "Phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "Email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          timestamp: "01:00",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003ABC",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "003ABC", email: "test@example.com"}

      result = SalesforceSuggestions.merge_with_contact([], contact)

      assert result == []
    end

    test "sets apply: true for all merged suggestions" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          timestamp: "01:23",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "003ABC", phone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert length(result) == 1
      assert hd(result).apply == true
    end
  end

  describe "field labels" do
    test "Salesforce fields have human-readable labels" do
      suggestions = [
        %{
          field: "MobilePhone",
          label: "Mobile Phone",
          current_value: nil,
          new_value: "555-9876",
          context: "Gave mobile number",
          timestamp: "02:30",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "003ABC", mobile_phone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Mobile Phone"
    end
  end

  describe "field mapping" do
    test "correctly maps Salesforce API field names to contact struct atoms" do
      suggestions = [
        %{field: "MailingCity", label: "Mailing City", current_value: nil, new_value: "Denver", context: "Lives in Denver", timestamp: "03:00", apply: false, has_change: true}
      ]

      # Contact with mailing_city already set to "Denver" — should filter out
      contact = %{id: "003ABC", mailing_city: "Denver"}
      assert SalesforceSuggestions.merge_with_contact(suggestions, contact) == []

      # Contact with different mailing_city — should keep the suggestion
      contact2 = %{id: "003ABC", mailing_city: "Boulder"}
      result = SalesforceSuggestions.merge_with_contact(suggestions, contact2)
      assert length(result) == 1
      assert hd(result).current_value == "Boulder"
    end
  end
end
