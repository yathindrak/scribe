defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce Strategy for Ueberauth.

  The Salesforce OAuth token response includes `instance_url` (the tenant-specific
  API base URL) and `id` (an identity URL for fetching user info). Both are stored
  in `extra.raw_info` so the auth controller can persist them.
  """

  use Ueberauth.Strategy,
    uid_field: :user_id,
    default_scope: "api refresh_token",
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @doc """
  Handles initial request for Salesforce authentication.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    code_verifier = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    code_challenge = :crypto.hash(:sha256, code_verifier) |> Base.url_encode64(padding: false)

    opts =
      [
        scope: scopes,
        redirect_uri: callback_url(conn),
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      ]
      |> with_state_param(conn)

    conn
    |> Plug.Conn.put_session(:salesforce_code_verifier, code_verifier)
    |> redirect!(Ueberauth.Strategy.Salesforce.OAuth.authorize_url!(opts))
  end

  @doc """
  Handles the callback from Salesforce.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    code_verifier = Plug.Conn.get_session(conn, :salesforce_code_verifier)
    opts = [redirect_uri: callback_url(conn)]
    params = [code: code] ++ if(code_verifier, do: [code_verifier: code_verifier], else: [])

    case Ueberauth.Strategy.Salesforce.OAuth.get_access_token(params, opts) do
      {:ok, token} ->
        fetch_user(conn, token)

      {:error, {error_code, error_description}} ->
        set_errors!(conn, [error(error_code, error_description)])
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  Cleans up the private area of the connection.
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:salesforce_token, nil)
    |> put_private(:salesforce_user, nil)
  end

  @doc """
  Fetches the uid field (Salesforce user ID) from the response.
  """
  def uid(conn) do
    conn.private.salesforce_user["user_id"]
  end

  @doc """
  Includes the credentials from the Salesforce response.
  """
  def credentials(conn) do
    token = conn.private.salesforce_token

    %Credentials{
      expires: true,
      expires_at: token.expires_at,
      scopes: [option(conn, :default_scope)],
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: token.token_type
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.salesforce_user

    %Info{
      email: user["email"],
      name: user["display_name"]
    }
  end

  @doc """
  Stores the raw information obtained from the Salesforce callback.
  The `instance_url` is available at `extra.raw_info.instance_url`.
  """
  def extra(conn) do
    token = conn.private.salesforce_token

    %Extra{
      raw_info: %{
        token: token,
        user: conn.private.salesforce_user,
        instance_url: token.other_params["instance_url"]
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :salesforce_token, token)
    identity_url = token.other_params["id"]

    case Ueberauth.Strategy.Salesforce.OAuth.get_user_info(token.access_token, identity_url) do
      {:ok, user} ->
        put_private(conn, :salesforce_user, user)

      {:error, reason} ->
        set_errors!(conn, [error("user_info_error", reason)])
    end
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
