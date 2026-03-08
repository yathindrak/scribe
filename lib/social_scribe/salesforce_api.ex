defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contact operations.

  Uses the Salesforce REST API v59.0. All requests are scoped to the user's
  Salesforce org via the `instance_url` stored on the credential.

  Implements automatic token refresh on 401 errors and retries once.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @api_version "v59.0"

  # Standard Contact fields to fetch and suggest updates for
  @contact_fields [
    "Id",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Title",
    "Department",
    "Account.Name",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry",
    "Description"
  ]

  # Fields used in SOQL SELECT (Account.Name requires a join which is fine in SOQL)
  @soql_fields Enum.join(@contact_fields, ", ")

  defp client(instance_url, access_token) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "#{instance_url}/services/data/#{@api_version}"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]},
      {Tesla.Middleware.Retry,
       delay: 500,
       max_retries: 3,
       max_delay: 10_000,
       use_retry_after_header: true,
       should_retry: fn
         {:ok, %Tesla.Env{status: status}}, _env, _ctx when status in [429, 503] -> true
         {:ok, _}, _env, _ctx -> false
         {:error, _}, _env, _ctx -> true
       end}
    ])
  end

  @doc """
  Searches for contacts by name or email.
  Returns up to 10 matching contacts with standard fields.
  Automatically refreshes token on 401 errors and retries once.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      safe_query = String.replace(query, "'", "\\'")

      soql =
        "SELECT #{@soql_fields} FROM Contact " <>
          "WHERE Name LIKE '%#{safe_query}%' OR Email LIKE '%#{safe_query}%' " <>
          "LIMIT 10"

      url = "/query?q=#{URI.encode(soql)}"

      case Tesla.get(client(cred.instance_url, cred.token), url) do
        {:ok, %Tesla.Env{status: 200, body: %{"records" => records}}} ->
          contacts = Enum.map(records, &format_contact/1)
          {:ok, contacts}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Gets a single contact by Salesforce ID with all standard fields.
  Automatically refreshes token on 401 errors and retries once.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      fields_param = URI.encode(Enum.join(@contact_fields, ","))
      url = "/sobjects/Contact/#{contact_id}?fields=#{fields_param}"

      case Tesla.get(client(cred.instance_url, cred.token), url) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          {:ok, format_contact(body)}

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Updates a contact's fields.
  `updates` should be a map of Salesforce field API names to new values.
  Returns {:ok, :updated} on success (Salesforce PATCH returns 204 No Content).
  Automatically refreshes token on 401 errors and retries once.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      url = "/sobjects/Contact/#{contact_id}"

      case Tesla.patch(client(cred.instance_url, cred.token), url, updates) do
        {:ok, %Tesla.Env{status: status}} when status in [200, 204] ->
          {:ok, :updated}

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Applies a list of suggested updates to a Salesforce contact.
  Only applies updates where `apply: true`.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, update.field, update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  # Format a Salesforce Contact record into a normalized structure
  defp format_contact(%{"Id" => id} = record) do
    %{
      id: id,
      firstname: record["FirstName"],
      lastname: record["LastName"],
      email: record["Email"],
      phone: record["Phone"],
      mobile_phone: record["MobilePhone"],
      title: record["Title"],
      department: record["Department"],
      company: get_in(record, ["Account", "Name"]),
      mailing_street: record["MailingStreet"],
      mailing_city: record["MailingCity"],
      mailing_state: record["MailingState"],
      mailing_postal_code: record["MailingPostalCode"],
      mailing_country: record["MailingCountry"],
      description: record["Description"],
      display_name: format_display_name(record)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(record) do
    firstname = record["FirstName"] || ""
    lastname = record["LastName"] || ""
    email = record["Email"] || ""
    name = String.trim("#{firstname} #{lastname}")
    if name == "", do: email, else: name
  end

  # Wrapper that handles token refresh on auth errors
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, 401, body}} ->
          Logger.info("Salesforce token expired, refreshing and retrying...")
          retry_with_fresh_token(credential, api_call, body)

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call, original_error_body) do
    if is_token_error?(original_error_body) do
      case SalesforceTokenRefresher.refresh_credential(credential) do
        {:ok, refreshed_credential} ->
          case api_call.(refreshed_credential) do
            {:error, {:api_error, status, body}} ->
              Logger.error("Salesforce API error after refresh: #{status} - #{inspect(body)}")
              {:error, {:api_error, status, body}}

            {:error, {:http_error, reason}} ->
              Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
              {:error, {:http_error, reason}}

            success ->
              success
          end

        {:error, refresh_error} ->
          Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
          {:error, {:token_refresh_failed, refresh_error}}
      end
    else
      {:error, {:api_error, 401, original_error_body}}
    end
  end

  defp is_token_error?(body) when is_list(body) do
    Enum.any?(body, fn
      %{"errorCode" => code} when code in ["INVALID_SESSION_ID", "SESSION_EXPIRED"] -> true
      _ -> false
    end)
  end

  defp is_token_error?(_), do: false
end
