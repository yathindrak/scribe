defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceTokenRefresher
  alias SocialScribe.Accounts

  import SocialScribe.AccountsFixtures
  import Tesla.Mock

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

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end
  end

  describe "ensure_valid_token/1 when token is expired" do
    test "attempts refresh and returns error when HTTP call fails" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      mock(fn %{method: :post, url: "https://login.salesforce.com/services/oauth2/token"} ->
        {:ok, %Tesla.Env{status: 400, body: %{"error" => "invalid_client_id"}}}
      end)

      assert {:error, _reason} = SalesforceTokenRefresher.ensure_valid_token(credential)
    end

    test "refreshes token successfully and updates credential" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      mock(fn %{method: :post, url: "https://login.salesforce.com/services/oauth2/token"} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "access_token" => "new_sf_token",
             "instance_url" => "https://new.salesforce.com",
             "expires_in" => 7200
           }
         }}
      end)

      {:ok, updated} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert updated.token == "new_sf_token"
      assert updated.instance_url == "https://new.salesforce.com"
      assert updated.id == credential.id
    end

    test "keeps existing instance_url when not returned in refresh response" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second),
          instance_url: "https://original.salesforce.com"
        })

      mock(fn %{method: :post, url: "https://login.salesforce.com/services/oauth2/token"} ->
        {:ok, %Tesla.Env{status: 200, body: %{"access_token" => "new_token"}}}
      end)

      {:ok, updated} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert updated.instance_url == "https://original.salesforce.com"
    end
  end
end
