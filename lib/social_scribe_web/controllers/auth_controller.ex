defmodule SocialScribeWeb.AuthController do
  use SocialScribeWeb, :controller

  alias SocialScribe.FacebookApi
  alias SocialScribe.Accounts
  alias SocialScribeWeb.UserAuth
  plug Ueberauth

  require Logger

  @doc """
  Handles the initial request to the provider (e.g., Google).
  Ueberauth's plug will redirect the user to the provider's consent page.
  """
  def request(conn, _params) do
    render(conn, :request)
  end

  @doc """
  Handles the callback from the provider after the user has granted consent.
  """
  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "google"
      })
      when not is_nil(user) do
    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, _credential} ->
        Logger.info("Google account connected for user #{user.id}")

        conn
        |> put_flash(:info, "Google account added successfully.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error("Failed to connect Google account for user #{user.id}: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not add Google account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "linkedin"
      })
      when not is_nil(user) do
    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, _credential} ->
        Logger.info("LinkedIn account connected for user #{user.id}")

        conn
        |> put_flash(:info, "LinkedIn account added successfully.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error("Failed to connect LinkedIn account for user #{user.id}: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not add LinkedIn account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "facebook"
      })
      when not is_nil(user) do
    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, credential} ->
        case FacebookApi.fetch_user_pages(credential.uid, credential.token) do
          {:ok, facebook_pages} ->
            Enum.each(facebook_pages, fn page ->
              Accounts.link_facebook_page(user, credential, page)
            end)

          _ ->
            :ok
        end

        Logger.info("Facebook account connected for user #{user.id}")

        conn
        |> put_flash(
          :info,
          "Facebook account added successfully. Please select a page to connect."
        )
        |> redirect(to: ~p"/dashboard/settings/facebook_pages")

      {:error, reason} ->
        Logger.error("Failed to connect Facebook account for user #{user.id}: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not add Facebook account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "hubspot"
      })
      when not is_nil(user) do
    hub_id = to_string(auth.uid)

    credential_attrs = %{
      user_id: user.id,
      provider: "hubspot",
      uid: hub_id,
      token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }

    case Accounts.find_or_create_hubspot_credential(user, credential_attrs) do
      {:ok, _credential} ->
        Logger.info("HubSpot account connected for user #{user.id}, hub_id: #{hub_id}")

        conn
        |> put_flash(:info, "HubSpot account connected successfully!")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error("Failed to save HubSpot credential: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not connect HubSpot account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "salesforce"
      })
      when not is_nil(user) do
    instance_url = auth.extra.raw_info.instance_url

    credential_attrs = %{
      user_id: user.id,
      provider: "salesforce",
      uid: to_string(auth.uid),
      token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 7200, :second),
      email: auth.info.email,
      instance_url: instance_url
    }

    case Accounts.find_or_create_salesforce_credential(user, credential_attrs) do
      {:ok, _credential} ->
        Logger.info("Salesforce account connected for user #{user.id}")

        conn
        |> put_flash(:info, "Salesforce account connected successfully!")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error("Failed to save Salesforce credential: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not connect Salesforce account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  # Handles initial sign-in via Google OAuth (user not yet logged in)
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.find_or_create_user_from_oauth(auth) do
      {:ok, user} ->
        Logger.info("User #{user.id} signed in via #{auth.provider}")
        UserAuth.log_in_user(conn, user)

      {:error, reason} ->
        Logger.error("OAuth sign-in failed (provider: #{auth.provider}): #{inspect(reason)}")

        conn
        |> put_flash(:error, "There was an error signing you in.")
        |> redirect(to: ~p"/")
    end
  end

  # Fallback: Ueberauth returned an error for a logged-in user (e.g., connecting a social account)
  def callback(
        %{assigns: %{ueberauth_failure: failure, current_user: user}} = conn,
        %{"provider" => provider}
      )
      when not is_nil(user) do
    Logger.warning("OAuth failure for #{provider} (user #{user.id}): #{inspect(failure, pretty: true)}")

    conn
    |> put_flash(:error, "Could not connect #{provider} account. Please try again.")
    |> redirect(to: ~p"/dashboard/settings")
  end

  # Fallback: Ueberauth returned an error (e.g., user denied access during sign-in)
  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    Logger.warning("OAuth failure: #{inspect(failure)}")

    conn
    |> put_flash(:error, "There was an error signing you in. Please try again.")
    |> redirect(to: ~p"/")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "There was an error signing you in. Please try again.")
    |> redirect(to: ~p"/")
  end
end
