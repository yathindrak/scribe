defmodule SocialScribe.HubspotApiTest do
  use SocialScribe.DataCase

  import Tesla.Mock
  import SocialScribe.AccountsFixtures

  alias SocialScribe.HubspotApi

  defp valid_credential(user_id) do
    hubspot_credential_fixture(%{
      user_id: user_id,
      token: "valid_hs_token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    })
  end

  describe "search_contacts/2" do
    test "returns formatted contacts on success" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :post, url: url} ->
        assert String.contains?(url, "/crm/v3/objects/contacts/search")

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "results" => [
               %{
                 "id" => "1",
                 "properties" => %{
                   "firstname" => "Alice",
                   "lastname" => "Smith",
                   "email" => "alice@example.com",
                   "phone" => "555-1234",
                   "mobilephone" => nil,
                   "company" => "Acme",
                   "jobtitle" => "Engineer",
                   "address" => nil,
                   "city" => nil,
                   "state" => nil,
                   "zip" => nil,
                   "country" => nil,
                   "website" => nil,
                   "hs_linkedin_url" => nil,
                   "twitterhandle" => nil
                 }
               }
             ]
           }
         }}
      end)

      assert {:ok, [contact]} = HubspotApi.search_contacts(credential, "Alice")
      assert contact.id == "1"
      assert contact.firstname == "Alice"
      assert contact.display_name == "Alice Smith"
    end

    test "uses email as display_name when name is blank" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "results" => [
               %{
                 "id" => "2",
                 "properties" => %{
                   "firstname" => "",
                   "lastname" => "",
                   "email" => "no-name@example.com",
                   "phone" => nil,
                   "mobilephone" => nil,
                   "company" => nil,
                   "jobtitle" => nil,
                   "address" => nil,
                   "city" => nil,
                   "state" => nil,
                   "zip" => nil,
                   "country" => nil,
                   "website" => nil,
                   "hs_linkedin_url" => nil,
                   "twitterhandle" => nil
                 }
               }
             ]
           }
         }}
      end)

      assert {:ok, [contact]} = HubspotApi.search_contacts(credential, "no-name")
      assert contact.display_name == "no-name@example.com"
    end

    test "returns {:error, {:api_error, status, body}} on non-200" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 403, body: %{"message" => "Forbidden"}}}
      end)

      assert {:error, {:api_error, 403, _}} = HubspotApi.search_contacts(credential, "query")
    end

    test "returns {:error, {:http_error, reason}} on connection failure" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :post} -> {:error, :econnrefused} end)

      assert {:error, {:http_error, :econnrefused}} =
               HubspotApi.search_contacts(credential, "query")
    end
  end

  describe "get_contact/2" do
    test "returns formatted contact on success" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :get, url: url} ->
        assert String.contains?(url, "/crm/v3/objects/contacts/abc123")

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "id" => "abc123",
             "properties" => %{
               "firstname" => "Bob",
               "lastname" => "Jones",
               "email" => "bob@example.com",
               "phone" => nil,
               "mobilephone" => nil,
               "company" => nil,
               "jobtitle" => nil,
               "address" => nil,
               "city" => nil,
               "state" => nil,
               "zip" => nil,
               "country" => nil,
               "website" => nil,
               "hs_linkedin_url" => nil,
               "twitterhandle" => nil
             }
           }
         }}
      end)

      assert {:ok, contact} = HubspotApi.get_contact(credential, "abc123")
      assert contact.id == "abc123"
      assert contact.firstname == "Bob"
    end

    test "returns {:error, :not_found} on 404" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 404, body: %{"message" => "Not found"}}}
      end)

      assert {:error, :not_found} = HubspotApi.get_contact(credential, "missing")
    end

    test "returns {:error, {:api_error, status, body}} on other errors" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 500, body: %{"message" => "Internal error"}}}
      end)

      assert {:error, {:api_error, 500, _}} = HubspotApi.get_contact(credential, "id")
    end
  end

  describe "update_contact/3" do
    test "returns formatted contact on success" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :patch, url: url} ->
        assert String.contains?(url, "/crm/v3/objects/contacts/c1")

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "id" => "c1",
             "properties" => %{
               "firstname" => "Alice",
               "lastname" => "Updated",
               "email" => "alice@example.com",
               "phone" => "999-0000",
               "mobilephone" => nil,
               "company" => nil,
               "jobtitle" => nil,
               "address" => nil,
               "city" => nil,
               "state" => nil,
               "zip" => nil,
               "country" => nil,
               "website" => nil,
               "hs_linkedin_url" => nil,
               "twitterhandle" => nil
             }
           }
         }}
      end)

      assert {:ok, contact} = HubspotApi.update_contact(credential, "c1", %{"phone" => "999-0000"})
      assert contact.phone == "999-0000"
    end

    test "returns {:error, :not_found} on 404" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :patch} ->
        {:ok, %Tesla.Env{status: 404, body: %{}}}
      end)

      assert {:error, :not_found} =
               HubspotApi.update_contact(credential, "missing", %{"phone" => "123"})
    end
  end

  describe "apply_updates/3" do
    test "returns {:ok, :no_updates} when list is empty" do
      user = user_fixture()
      credential = valid_credential(user.id)

      assert {:ok, :no_updates} = HubspotApi.apply_updates(credential, "123", [])
    end

    test "returns {:ok, :no_updates} when all updates have apply: false" do
      user = user_fixture()
      credential = valid_credential(user.id)

      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]

      assert {:ok, :no_updates} = HubspotApi.apply_updates(credential, "123", updates)
    end

    test "calls update_contact for updates with apply: true" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :patch} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "id" => "c99",
             "properties" => %{
               "firstname" => nil,
               "lastname" => nil,
               "email" => "new@example.com",
               "phone" => nil,
               "mobilephone" => nil,
               "company" => nil,
               "jobtitle" => nil,
               "address" => nil,
               "city" => nil,
               "state" => nil,
               "zip" => nil,
               "country" => nil,
               "website" => nil,
               "hs_linkedin_url" => nil,
               "twitterhandle" => nil
             }
           }
         }}
      end)

      updates = [
        %{field: "email", new_value: "new@example.com", apply: true},
        %{field: "phone", new_value: "555", apply: false}
      ]

      assert {:ok, contact} = HubspotApi.apply_updates(credential, "c99", updates)
      assert contact.email == "new@example.com"
    end
  end

  describe "token refresh retry logic" do
    test "retries after BAD_CLIENT_ID error and returns token_refresh_failed when refresh fails" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn env ->
        cond do
          String.contains?(env.url, "/crm/v3/objects/contacts/search") ->
            {:ok,
             %Tesla.Env{
               status: 400,
               body: %{"status" => "BAD_CLIENT_ID", "message" => "bad client id"}
             }}

          String.contains?(env.url, "/oauth/v1/token") ->
            {:ok, %Tesla.Env{status: 400, body: %{"error" => "invalid_client"}}}

          true ->
            {:error, :unexpected_url}
        end
      end)

      assert {:error, {:token_refresh_failed, _}} =
               HubspotApi.search_contacts(credential, "test")
    end

    test "does not retry on non-token 403 errors" do
      user = user_fixture()
      credential = valid_credential(user.id)

      mock(fn %{method: :post, url: url} ->
        assert String.contains?(url, "/crm/v3/objects/contacts/search")
        {:ok, %Tesla.Env{status: 403, body: %{"message" => "Access denied"}}}
      end)

      assert {:error, {:api_error, 403, _}} = HubspotApi.search_contacts(credential, "test")
    end
  end
end
