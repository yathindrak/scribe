defmodule SocialScribeWeb.AuthControllerTest do
  use SocialScribeWeb.ConnCase

  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  # Prepare a conn with session and flash initialized (needed when calling actions directly)
  defp prepare(conn) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Phoenix.Controller.fetch_flash([])
  end

  defp build_google_auth(opts \\ []) do
    uid = Keyword.get(opts, :uid, "google_#{System.unique_integer([:positive])}")
    email = Keyword.get(opts, :email, "user_#{System.unique_integer([:positive])}@example.com")

    %Ueberauth.Auth{
      provider: :google,
      uid: uid,
      info: %Ueberauth.Auth.Info{email: email, name: "Test User"},
      credentials: %Ueberauth.Auth.Credentials{
        token: "g_token",
        refresh_token: "g_refresh",
        expires_at: nil,
        expires: false,
        other: %{}
      },
      extra: %Ueberauth.Auth.Extra{raw_info: %{}}
    }
  end

  defp build_linkedin_auth(opts \\ []) do
    sub = Keyword.get(opts, :sub, "li_#{System.unique_integer([:positive])}")
    email = Keyword.get(opts, :email, "user_#{System.unique_integer([:positive])}@example.com")

    %Ueberauth.Auth{
      provider: :linkedin,
      uid: sub,
      info: %Ueberauth.Auth.Info{email: email, name: "Test User"},
      credentials: %Ueberauth.Auth.Credentials{
        token: "li_token",
        refresh_token: "li_refresh",
        expires_at: nil,
        expires: false,
        other: %{}
      },
      extra: %Ueberauth.Auth.Extra{raw_info: %{user: %{"sub" => sub}}}
    }
  end

  defp build_facebook_auth(opts \\ []) do
    uid = Keyword.get(opts, :uid, "fb_#{System.unique_integer([:positive])}")
    email = Keyword.get(opts, :email, "user_#{System.unique_integer([:positive])}@example.com")

    %Ueberauth.Auth{
      provider: :facebook,
      uid: uid,
      info: %Ueberauth.Auth.Info{email: email, name: "Test User"},
      credentials: %Ueberauth.Auth.Credentials{
        token: "fb_token",
        refresh_token: "fb_token",
        expires_at: nil,
        expires: false,
        other: %{}
      },
      extra: %Ueberauth.Auth.Extra{raw_info: %{}}
    }
  end

  describe "callback/2 - Google (connecting account to existing user)" do
    test "redirects to settings with success flash", %{conn: conn} do
      user = user_fixture()
      auth = build_google_auth()

      conn =
        conn
        |> prepare()
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "google"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Google account added successfully"
    end
  end

  describe "callback/2 - LinkedIn (connecting account to existing user)" do
    test "redirects to settings with success flash", %{conn: conn} do
      user = user_fixture()
      auth = build_linkedin_auth()

      conn =
        conn
        |> prepare()
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "linkedin"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "LinkedIn account added successfully"
    end
  end

  describe "callback/2 - Facebook (connecting account to existing user)" do
    test "redirects to facebook pages settings and links pages", %{conn: conn} do
      user = user_fixture()
      auth = build_facebook_auth()

      SocialScribe.FacebookApiMock
      |> expect(:fetch_user_pages, fn _uid, _token ->
        {:ok, []}
      end)

      conn =
        conn
        |> prepare()
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "facebook"})

      assert redirected_to(conn) == ~p"/dashboard/settings/facebook_pages"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Facebook account added successfully"
    end

    test "still redirects when fetch_user_pages returns error", %{conn: conn} do
      user = user_fixture()
      auth = build_facebook_auth()

      SocialScribe.FacebookApiMock
      |> expect(:fetch_user_pages, fn _uid, _token ->
        {:error, "API error"}
      end)

      conn =
        conn
        |> prepare()
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "facebook"})

      assert redirected_to(conn) == ~p"/dashboard/settings/facebook_pages"
    end
  end

  describe "callback/2 - HubSpot (connecting account to existing user)" do
    test "redirects to settings with success flash", %{conn: conn} do
      user = user_fixture()

      auth = %Ueberauth.Auth{
        provider: :hubspot,
        uid: System.unique_integer([:positive]),
        info: %Ueberauth.Auth.Info{email: "user@hubspot.com", name: "HubSpot User"},
        credentials: %Ueberauth.Auth.Credentials{
          token: "hub_token",
          refresh_token: "hub_refresh",
          expires_at: nil,
          expires: false,
          other: %{}
        },
        extra: %Ueberauth.Auth.Extra{raw_info: %{}}
      }

      conn =
        conn
        |> prepare()
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "hubspot"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "HubSpot account connected"
    end
  end

  describe "callback/2 - Salesforce (connecting account to existing user)" do
    test "redirects to settings with success flash", %{conn: conn} do
      user = user_fixture()

      auth = %Ueberauth.Auth{
        provider: :salesforce,
        uid: "005_#{System.unique_integer([:positive])}",
        info: %Ueberauth.Auth.Info{email: "user@salesforce.com", name: "SF User"},
        credentials: %Ueberauth.Auth.Credentials{
          token: "sf_token",
          refresh_token: "sf_refresh",
          expires_at: nil,
          expires: false,
          other: %{}
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{instance_url: "https://test.salesforce.com"}
        }
      }

      conn =
        conn
        |> prepare()
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = SocialScribeWeb.AuthController.callback(conn, %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Salesforce account connected"
    end
  end

  describe "callback/2 - initial sign-in via Google (no current_user)" do
    test "logs user in and redirects to dashboard", %{conn: conn} do
      auth = build_google_auth()

      conn =
        conn
        |> prepare()
        |> assign(:ueberauth_auth, auth)

      conn = SocialScribeWeb.AuthController.callback(conn, %{})

      assert redirected_to(conn) == ~p"/dashboard"
    end
  end

  describe "callback/2 - ueberauth_failure" do
    test "redirects to root with error flash", %{conn: conn} do
      failure = %Ueberauth.Failure{
        provider: :google,
        strategy: Ueberauth.Strategy.Google,
        errors: [
          %Ueberauth.Failure.Error{message_key: "access_denied", message: "access_denied"}
        ]
      }

      conn =
        conn
        |> prepare()
        |> assign(:ueberauth_failure, failure)

      conn = SocialScribeWeb.AuthController.callback(conn, %{})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "error signing you in"
    end
  end

  describe "callback/2 - fallback (no ueberauth assigns)" do
    test "redirects to root with error flash", %{conn: conn} do
      conn =
        conn
        |> prepare()

      conn = SocialScribeWeb.AuthController.callback(conn, %{})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "error signing you in"
    end
  end
end
