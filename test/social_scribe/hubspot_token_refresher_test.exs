defmodule SocialScribe.HubspotTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.HubspotTokenRefresher

  import SocialScribe.AccountsFixtures
  import Tesla.Mock

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = HubspotTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = HubspotTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end
  end

  describe "ensure_valid_token/1 when token is expired" do
    test "attempts refresh and returns error when HTTP call fails" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      mock(fn %{method: :post, url: "https://api.hubapi.com/oauth/v1/token"} ->
        {:ok, %Tesla.Env{status: 400, body: %{"error" => "invalid_request"}}}
      end)

      assert {:error, _reason} = HubspotTokenRefresher.ensure_valid_token(credential)
    end

    test "refreshes token successfully and updates credential" do
      user = user_fixture()

      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      mock(fn %{method: :post, url: "https://api.hubapi.com/oauth/v1/token"} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "access_token" => "new_access_token",
             "refresh_token" => "new_refresh_token",
             "expires_in" => 3600
           }
         }}
      end)

      {:ok, updated} = HubspotTokenRefresher.ensure_valid_token(credential)

      assert updated.token == "new_access_token"
      assert updated.refresh_token == "new_refresh_token"
      assert updated.id == credential.id
    end
  end
end
