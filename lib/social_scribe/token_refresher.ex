defmodule SocialScribe.TokenRefresher do
  @moduledoc """
  Refreshes Google tokens.
  """

  @google_token_url "https://oauth2.googleapis.com/token"

  @behaviour SocialScribe.TokenRefresherApi

  def client do
    middlewares = [
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
    ]

    Tesla.client(middlewares)
  end

  def refresh_token(refresh_token_string) do
    client_id = Application.fetch_env!(:ueberauth, Ueberauth.Strategy.Google.OAuth)[:client_id]

    client_secret =
      Application.fetch_env!(:ueberauth, Ueberauth.Strategy.Google.OAuth)[:client_secret]

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token_string,
      grant_type: "refresh_token"
    }

    # Use Tesla to make the POST request
    case Tesla.post(client(), @google_token_url, body, opts: [form_urlencoded: true]) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
