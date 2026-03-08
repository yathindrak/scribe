defmodule SocialScribe.PosterTest do
  use SocialScribe.DataCase

  import Mox
  import SocialScribe.AccountsFixtures

  alias SocialScribe.Poster

  setup :verify_on_exit!

  describe "post_on_social_media/3 - LinkedIn" do
    test "posts to LinkedIn when credential exists" do
      user = user_fixture()

      {:ok, linkedin_credential} =
        SocialScribe.Accounts.create_user_credential(%{
          user_id: user.id,
          provider: "linkedin",
          token: "li_token",
          refresh_token: "li_refresh",
          uid: "urn:li:person:abc123",
          email: "user@example.com",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      SocialScribe.LinkedInApiMock
      |> expect(:post_text_share, fn token, author_urn, content ->
        assert token == linkedin_credential.token
        assert author_urn == linkedin_credential.uid
        assert content == "Hello LinkedIn!"
        {:ok, %{"id" => "urn:li:share:123"}}
      end)

      assert {:ok, %{"id" => "urn:li:share:123"}} =
               Poster.post_on_social_media(:linkedin, "Hello LinkedIn!", user)
    end

    test "returns error when LinkedIn credential does not exist" do
      user = user_fixture()

      assert {:error, "LinkedIn credential not found"} =
               Poster.post_on_social_media(:linkedin, "Hello LinkedIn!", user)
    end

    test "propagates LinkedIn API error" do
      user = user_fixture()

      {:ok, _} =
        SocialScribe.Accounts.create_user_credential(%{
          user_id: user.id,
          provider: "linkedin",
          token: "li_token",
          refresh_token: "li_refresh",
          uid: "urn:li:person:abc123",
          email: "user@example.com",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      SocialScribe.LinkedInApiMock
      |> expect(:post_text_share, fn _token, _urn, _content ->
        {:error, {:api_error, 401, "Unauthorized", %{}}}
      end)

      assert {:error, {:api_error, 401, "Unauthorized", %{}}} =
               Poster.post_on_social_media(:linkedin, "Hello!", user)
    end
  end

  describe "post_on_social_media/3 - Facebook" do
    test "posts to Facebook when selected page credential exists" do
      user = user_fixture()
      user_credential = user_credential_fixture(%{user_id: user.id})

      {:ok, _page_cred} =
        SocialScribe.Accounts.create_facebook_page_credential(%{
          user_id: user.id,
          user_credential_id: user_credential.id,
          facebook_page_id: "page_123",
          page_access_token: "page_token",
          page_name: "My Page",
          category: "Business",
          selected: true
        })

      SocialScribe.FacebookApiMock
      |> expect(:post_message_to_page, fn page_id, page_token, content ->
        assert page_id == "page_123"
        assert page_token == "page_token"
        assert content == "Hello Facebook!"
        {:ok, %{"id" => "post_456"}}
      end)

      assert {:ok, %{"id" => "post_456"}} =
               Poster.post_on_social_media(:facebook, "Hello Facebook!", user)
    end

    test "returns error when no selected Facebook page credential exists" do
      user = user_fixture()

      assert {:error, "Facebook page credential not found"} =
               Poster.post_on_social_media(:facebook, "Hello Facebook!", user)
    end

    test "propagates Facebook API error" do
      user = user_fixture()
      user_credential = user_credential_fixture(%{user_id: user.id})

      {:ok, _} =
        SocialScribe.Accounts.create_facebook_page_credential(%{
          user_id: user.id,
          user_credential_id: user_credential.id,
          facebook_page_id: "page_123",
          page_access_token: "page_token",
          page_name: "My Page",
          category: "Business",
          selected: true
        })

      SocialScribe.FacebookApiMock
      |> expect(:post_message_to_page, fn _page_id, _token, _content ->
        {:error, {:api_error_posting, 403, "Forbidden", %{}}}
      end)

      assert {:error, {:api_error_posting, 403, "Forbidden", %{}}} =
               Poster.post_on_social_media(:facebook, "Hello!", user)
    end
  end

  describe "post_on_social_media/3 - unsupported platform" do
    test "returns error for unsupported platform" do
      user = user_fixture()

      assert {:error, "Unsupported platform"} =
               Poster.post_on_social_media(:twitter, "Hello!", user)
    end
  end
end
