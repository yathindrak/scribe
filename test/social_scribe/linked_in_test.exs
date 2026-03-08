defmodule SocialScribe.LinkedInTest do
  use ExUnit.Case, async: false

  import Tesla.Mock

  alias SocialScribe.LinkedIn

  describe "post_text_share/3" do
    test "returns {:ok, response_body} on 201 Created" do
      mock(fn %{method: :post, url: "https://api.linkedin.com/v2/ugcPosts"} ->
        {:ok, %Tesla.Env{status: 201, body: %{"id" => "urn:li:share:12345"}}}
      end)

      assert {:ok, %{"id" => "urn:li:share:12345"}} =
               LinkedIn.post_text_share("li_token", "urn:li:person:abc", "Hello LinkedIn!")
    end

    test "returns {:error, ...} on non-201 status" do
      mock(fn %{method: :post, url: "https://api.linkedin.com/v2/ugcPosts"} ->
        {:ok,
         %Tesla.Env{
           status: 401,
           body: %{"message" => "Unauthorized", "status" => 401}
         }}
      end)

      assert {:error, {:api_error, 401, "Unauthorized", _}} =
               LinkedIn.post_text_share("bad_token", "urn:li:person:abc", "Hello!")
    end

    test "returns {:error, {:http_error, reason}} on connection failure" do
      mock(fn %{method: :post} ->
        {:error, :econnrefused}
      end)

      assert {:error, {:http_error, :econnrefused}} =
               LinkedIn.post_text_share("token", "urn:li:person:abc", "Hello!")
    end

    test "uses 'Unknown API error' when message is missing from error body" do
      mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 403, body: %{}}}
      end)

      assert {:error, {:api_error, 403, "Unknown API error", _}} =
               LinkedIn.post_text_share("token", "urn:li:person:abc", "Hello!")
    end

    test "includes authorization header with token" do
      token = "my_li_access_token"

      mock(fn %{method: :post, headers: headers} ->
        auth = Enum.find(headers, fn {k, _} -> k == "Authorization" end)
        assert auth == {"Authorization", "Bearer #{token}"}
        {:ok, %Tesla.Env{status: 201, body: %{"id" => "urn:li:share:1"}}}
      end)

      assert {:ok, _} = LinkedIn.post_text_share(token, "urn:li:person:abc", "Hello!")
    end
  end
end
