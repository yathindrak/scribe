defmodule SocialScribe.FacebookTest do
  use ExUnit.Case, async: false

  import Tesla.Mock

  alias SocialScribe.Facebook

  describe "post_message_to_page/3" do
    test "returns {:ok, response_body} on success" do
      mock(fn %{method: :post, url: "https://graph.facebook.com/v22.0/page_123/feed"} ->
        {:ok, %Tesla.Env{status: 200, body: %{"id" => "post_456"}}}
      end)

      assert {:ok, %{"id" => "post_456"}} =
               Facebook.post_message_to_page("page_123", "token_abc", "Hello Facebook!")
    end

    test "returns {:error, ...} on non-200 status" do
      mock(fn %{method: :post, url: "https://graph.facebook.com/v22.0/page_123/feed"} ->
        {:ok,
         %Tesla.Env{
           status: 403,
           body: %{"error" => %{"message" => "Permission denied"}}
         }}
      end)

      assert {:error, {:api_error_posting, 403, "Permission denied", _}} =
               Facebook.post_message_to_page("page_123", "bad_token", "Hello!")
    end

    test "returns {:error, {:http_error_posting, reason}} on connection failure" do
      mock(fn %{method: :post} ->
        {:error, :econnrefused}
      end)

      assert {:error, {:http_error_posting, :econnrefused}} =
               Facebook.post_message_to_page("page_123", "token", "Hello!")
    end

    test "uses 'Unknown API error' when error message is missing" do
      mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 400, body: %{"error" => %{}}}}
      end)

      assert {:error, {:api_error_posting, 400, "Unknown API error", _}} =
               Facebook.post_message_to_page("page_123", "token", "Hello!")
    end
  end

  describe "fetch_user_pages/2" do
    test "returns filtered pages with CREATE_CONTENT permission" do
      pages_data = [
        %{
          "id" => "page_1",
          "name" => "Allowed Page",
          "category" => "Business",
          "access_token" => "page_token_1",
          "tasks" => ["CREATE_CONTENT", "ADVERTISE"]
        },
        %{
          "id" => "page_2",
          "name" => "Manage Page",
          "category" => "Brand",
          "access_token" => "page_token_2",
          "tasks" => ["MANAGE"]
        },
        %{
          "id" => "page_3",
          "name" => "No Permission Page",
          "category" => "Other",
          "access_token" => "page_token_3",
          "tasks" => ["ADVERTISE"]
        }
      ]

      mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 200, body: %{"data" => pages_data}}}
      end)

      {:ok, pages} = Facebook.fetch_user_pages("user_123", "user_token")

      assert length(pages) == 2
      page_ids = Enum.map(pages, & &1.id)
      assert "page_1" in page_ids
      assert "page_2" in page_ids
      refute "page_3" in page_ids
    end

    test "returns empty list when no pages have required permissions" do
      mock(fn %{method: :get} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "data" => [
               %{"id" => "p1", "name" => "Page", "tasks" => ["ADVERTISE"], "access_token" => "t"}
             ]
           }
         }}
      end)

      {:ok, pages} = Facebook.fetch_user_pages("user_123", "user_token")
      assert pages == []
    end

    test "handles pages with nil tasks" do
      mock(fn %{method: :get} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{"data" => [%{"id" => "p1", "name" => "Page", "access_token" => "t"}]}
         }}
      end)

      {:ok, pages} = Facebook.fetch_user_pages("user_123", "user_token")
      assert pages == []
    end

    test "returns error on non-200 status" do
      mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 401, body: "Unauthorized"}}
      end)

      assert {:error, _} = Facebook.fetch_user_pages("user_123", "bad_token")
    end

    test "maps page fields correctly" do
      mock(fn %{method: :get} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "data" => [
               %{
                 "id" => "page_99",
                 "name" => "My Business",
                 "category" => "Technology",
                 "access_token" => "page_tok",
                 "tasks" => ["CREATE_CONTENT"]
               }
             ]
           }
         }}
      end)

      {:ok, [page]} = Facebook.fetch_user_pages("user_123", "user_token")

      assert page.id == "page_99"
      assert page.name == "My Business"
      assert page.category == "Technology"
      assert page.page_access_token == "page_tok"
    end
  end
end
