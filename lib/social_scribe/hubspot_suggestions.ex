defmodule SocialScribe.HubspotSuggestions do
  @moduledoc """
  Generates and formats HubSpot contact update suggestions by combining
  AI-extracted data with existing HubSpot contact information.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.HubspotApiBehaviour
  alias SocialScribe.Accounts.UserCredential

  @field_labels %{
    "firstname" => "First Name",
    "lastname" => "Last Name",
    "email" => "Email",
    "phone" => "Phone",
    "mobilephone" => "Mobile Phone",
    "company" => "Company",
    "jobtitle" => "Job Title",
    "address" => "Address",
    "city" => "City",
    "state" => "State",
    "zip" => "ZIP Code",
    "country" => "Country",
    "website" => "Website",
    "linkedin_url" => "LinkedIn",
    "twitter_handle" => "Twitter"
  }

  @doc """
  Generates suggested updates for a HubSpot contact based on a meeting transcript.

  Returns a list of suggestion maps, each containing:
  - field: the HubSpot field name
  - label: human-readable field label
  - current_value: the existing value in HubSpot (or nil)
  - new_value: the AI-suggested value
  - context: explanation of where this was found in the transcript
  - apply: boolean indicating whether to apply this update (default false)
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    with {:ok, contact} <- HubspotApiBehaviour.get_contact(credential, contact_id),
         {:ok, ai_suggestions} <- AIContentGeneratorApi.generate_hubspot_suggestions(meeting) do
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
  Useful when contact hasn't been selected yet.
  """
  def generate_suggestions_from_meeting(meeting) do
    case AIContentGeneratorApi.generate_hubspot_suggestions(meeting) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.map(fn suggestion ->
            %{
              field: suggestion.field,
              label: Map.get(@field_labels, suggestion.field, suggestion.field),
              current_value: nil,
              new_value: suggestion.value,
              context: Map.get(suggestion, :context),
              timestamp: Map.get(suggestion, :timestamp),
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
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    Enum.map(suggestions, fn suggestion ->
      current_value = get_contact_field(contact, suggestion.field)

      %{suggestion | current_value: current_value, has_change: values_differ?(current_value, suggestion.new_value), apply: true}
    end)
    |> Enum.filter(fn s -> s.has_change end)
  end

  @field_to_atom %{
    "firstname" => :firstname,
    "lastname" => :lastname,
    "email" => :email,
    "phone" => :phone,
    "mobilephone" => :mobilephone,
    "company" => :company,
    "jobtitle" => :jobtitle,
    "address" => :address,
    "city" => :city,
    "state" => :state,
    "zip" => :zip,
    "country" => :country,
    "website" => :website,
    "linkedin_url" => :linkedin_url,
    "twitter_handle" => :twitter_handle
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
