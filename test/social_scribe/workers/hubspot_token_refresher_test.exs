defmodule SocialScribe.Workers.HubspotTokenRefresherTest do
  use SocialScribe.DataCase

  import SocialScribe.AccountsFixtures
  import Tesla.Mock

  alias SocialScribe.Workers.HubspotTokenRefresher

  describe "perform/1" do
    test "returns :ok when there are no expiring HubSpot credentials" do
      user = user_fixture()

      # Credential with expiry well in the future — should not be picked up
      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      assert :ok = HubspotTokenRefresher.perform(%Oban.Job{})
    end

    test "returns :ok and attempts refresh when credentials are expiring soon" do
      user = user_fixture()

      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

      mock(fn %{method: :post, url: "https://api.hubapi.com/oauth/v1/token"} ->
        {:ok, %Tesla.Env{status: 400, body: %{"error" => "invalid_request"}}}
      end)

      assert :ok = HubspotTokenRefresher.perform(%Oban.Job{})
    end

    test "returns :ok and attempts refresh for already-expired credentials" do
      user = user_fixture()

      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

      mock(fn %{method: :post, url: "https://api.hubapi.com/oauth/v1/token"} ->
        {:ok, %Tesla.Env{status: 400, body: %{"error" => "invalid_request"}}}
      end)

      assert :ok = HubspotTokenRefresher.perform(%Oban.Job{})
    end

    test "only refreshes hubspot credentials, not other providers" do
      user = user_fixture()

      {:ok, _} =
        SocialScribe.Accounts.create_user_credential(%{
          user_id: user.id,
          provider: "google",
          token: "google_token",
          refresh_token: "google_refresh",
          uid: "google_uid_#{System.unique_integer([:positive])}",
          email: "user@example.com",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      # No HubSpot credentials — no Tesla calls made
      assert :ok = HubspotTokenRefresher.perform(%Oban.Job{})
    end
  end
end
