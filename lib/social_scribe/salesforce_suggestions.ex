defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Generates and formats Salesforce contact update suggestions by combining
  AI-extracted data with existing Salesforce contact information.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.SalesforceApiBehaviour
  alias SocialScribe.Accounts.UserCredential

  @field_labels %{
    "Phone" => "Phone",
    "MobilePhone" => "Mobile Phone",
    "Email" => "Email",
    "Title" => "Job Title",
    "Department" => "Department",
    "MailingStreet" => "Mailing Street",
    "MailingCity" => "Mailing City",
    "MailingState" => "Mailing State",
    "MailingPostalCode" => "Mailing Postal Code",
    "MailingCountry" => "Mailing Country"
  }

  @doc """
  Generates suggested updates for a Salesforce contact based on a meeting transcript.

  Returns a list of suggestion maps, each containing:
  - field: the Salesforce field API name
  - label: human-readable field label
  - current_value: the existing value in Salesforce (or nil)
  - new_value: the AI-suggested value
  - context: explanation of where this was found in the transcript
  - apply: boolean indicating whether to apply this update (default true)
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    with {:ok, contact} <- SalesforceApiBehaviour.get_contact(credential, contact_id),
         {:ok, ai_suggestions} <- AIContentGeneratorApi.generate_salesforce_suggestions(meeting) do
      suggestions =
        ai_suggestions
        |> Enum.map(fn suggestion ->
          field = suggestion.field
          current_value = get_contact_field(contact, field)

          %{
            field: field,
            label: Map.get(@field_labels, field, field),
            current_value: current_value,
            new_value: suggestion.value,
            context: suggestion.context,
            timestamp: suggestion.timestamp,
            apply: true,
            has_change: values_differ?(current_value, suggestion.value)
          }
        end)
        |> Enum.filter(fn s -> s.has_change end)

      {:ok, %{contact: contact, suggestions: suggestions}}
    end
  end

  @doc """
  Generates suggestions without fetching contact data.
  Useful when a contact has not been selected yet.
  """
  def generate_suggestions_from_meeting(meeting) do
    case AIContentGeneratorApi.generate_salesforce_suggestions(meeting) do
      {:ok, ai_suggestions} ->
        suggestions =
          Enum.map(ai_suggestions, fn suggestion ->
            %{
              field: suggestion.field,
              label: Map.get(@field_labels, suggestion.field, suggestion.field),
              current_value: nil,
              new_value: suggestion.value,
              context: suggestion.context,
              timestamp: suggestion.timestamp,
              apply: true,
              has_change: true
            }
          end)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.
  Filters out suggestions where the current value already matches the suggestion.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    suggestions
    |> Enum.map(fn suggestion ->
      current_value = get_contact_field(contact, suggestion.field)
      %{suggestion | current_value: current_value, has_change: values_differ?(current_value, suggestion.new_value), apply: true}
    end)
    |> Enum.filter(fn s -> s.has_change end)
  end

  # Map Salesforce field API name to the atom key used in the formatted contact struct
  @field_to_atom %{
    "FirstName" => :firstname,
    "LastName" => :lastname,
    "Phone" => :phone,
    "MobilePhone" => :mobile_phone,
    "Email" => :email,
    "Title" => :title,
    "Department" => :department,
    "MailingStreet" => :mailing_street,
    "MailingCity" => :mailing_city,
    "MailingState" => :mailing_state,
    "MailingPostalCode" => :mailing_postal_code,
    "MailingCountry" => :mailing_country,
    "Description" => :description
  }

  defp get_contact_field(contact, field) when is_map(contact) do
    case Map.get(@field_to_atom, field) do
      nil -> nil
      atom -> Map.get(contact, atom)
    end
  end

  defp get_contact_field(_, _), do: nil

  defp values_differ?(a, b) when is_binary(a) and is_binary(b) do
    String.downcase(String.trim(a)) != String.downcase(String.trim(b))
  end

  defp values_differ?(a, b), do: a != b
end
