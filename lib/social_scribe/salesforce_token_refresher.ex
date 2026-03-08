defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Refreshes Salesforce OAuth tokens.
  """

  @salesforce_token_url "https://login.salesforce.com/services/oauth2/token"

  def client do
    Tesla.client([
      {Tesla.Middleware.FormUrlencoded,
       encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1},
      Tesla.Middleware.JSON,
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
  Refreshes a Salesforce access token using the refresh token.
  Returns {:ok, response_body} with new access_token and instance_url.
  Note: Salesforce refresh tokens do not expire unless revoked.
  """
  def refresh_token(refresh_token_string) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    client_id = config[:client_id]
    client_secret = config[:client_secret]

    body = %{
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token_string
    }

    case Tesla.post(client(), @salesforce_token_url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes the token for a Salesforce credential and updates it in the database.
  Also updates instance_url if returned in the refresh response.
  """
  def refresh_credential(credential) do
    alias SocialScribe.Accounts

    case refresh_token(credential.refresh_token) do
      {:ok, response} ->
        attrs = %{
          token: response["access_token"],
          # Salesforce refresh responses include instance_url; keep existing if absent
          instance_url: response["instance_url"] || credential.instance_url,
          expires_at: DateTime.add(DateTime.utc_now(), response["expires_in"] || 7200, :second)
        }

        Accounts.update_user_credential(credential, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ensures a credential has a valid (non-expired) token.
  Refreshes if expired or about to expire (within 5 minutes).
  """
  def ensure_valid_token(credential) do
    buffer_seconds = 300

    if DateTime.compare(
         credential.expires_at,
         DateTime.add(DateTime.utc_now(), buffer_seconds, :second)
       ) == :lt do
      refresh_credential(credential)
    else
      {:ok, credential}
    end
  end
end
