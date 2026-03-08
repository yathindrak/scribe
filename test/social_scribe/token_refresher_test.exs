defmodule SocialScribe.TokenRefresherTest do
  use ExUnit.Case, async: false

  import Tesla.Mock

  alias SocialScribe.TokenRefresher

  describe "refresh_token/1" do
    test "returns {:ok, response_body} on success" do
      mock(fn %{method: :post, url: "https://oauth2.googleapis.com/token"} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{"access_token" => "new_google_token", "expires_in" => 3600}
         }}
      end)

      assert {:ok, %{"access_token" => "new_google_token"}} =
               TokenRefresher.refresh_token("my_refresh_token")
    end

    test "returns {:error, {status, body}} on non-200 status" do
      mock(fn %{method: :post, url: "https://oauth2.googleapis.com/token"} ->
        {:ok,
         %Tesla.Env{
           status: 400,
           body: %{"error" => "invalid_grant"}
         }}
      end)

      assert {:error, {400, %{"error" => "invalid_grant"}}} =
               TokenRefresher.refresh_token("expired_refresh_token")
    end

    test "returns {:error, reason} on connection failure" do
      mock(fn %{method: :post} ->
        {:error, :econnrefused}
      end)

      assert {:error, :econnrefused} = TokenRefresher.refresh_token("my_refresh_token")
    end
  end
end
