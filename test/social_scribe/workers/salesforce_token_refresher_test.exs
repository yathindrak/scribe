defmodule SocialScribe.Workers.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  import SocialScribe.AccountsFixtures
  import Tesla.Mock

  alias SocialScribe.Workers.SalesforceTokenRefresher
  alias SocialScribe.Accounts

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

  describe "perform/1" do
    test "returns :ok when there are no expiring Salesforce credentials" do
      user = user_fixture()

      # Credential with expiry well in the future — should not be picked up
      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      assert :ok = SalesforceTokenRefresher.perform(%Oban.Job{})
    end

    test "returns :ok and attempts refresh when credentials are expiring soon" do
      user = user_fixture()

      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

      mock(fn %{method: :post, url: "https://login.salesforce.com/services/oauth2/token"} ->
        {:ok, %Tesla.Env{status: 400, body: %{"error" => "invalid_client_id"}}}
      end)

      assert :ok = SalesforceTokenRefresher.perform(%Oban.Job{})
    end

    test "returns :ok and attempts refresh for already-expired credentials" do
      user = user_fixture()

      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

      mock(fn %{method: :post, url: "https://login.salesforce.com/services/oauth2/token"} ->
        {:ok, %Tesla.Env{status: 400, body: %{"error" => "invalid_client_id"}}}
      end)

      assert :ok = SalesforceTokenRefresher.perform(%Oban.Job{})
    end

    test "only refreshes salesforce credentials, not other providers" do
      user = user_fixture()

      # Insert an expiring HubSpot credential — should not be touched
      {:ok, _} =
        Accounts.create_user_credential(%{
          user_id: user.id,
          provider: "hubspot",
          token: "hs_token",
          refresh_token: "hs_refresh",
          uid: "hub_#{System.unique_integer([:positive])}",
          email: "user@example.com",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      # No Salesforce credentials — should take the empty branch
      assert :ok = SalesforceTokenRefresher.perform(%Oban.Job{})
    end
  end
end
