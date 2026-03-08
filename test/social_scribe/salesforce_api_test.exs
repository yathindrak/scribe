defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  import Tesla.Mock
  import SocialScribe.AccountsFixtures

  alias SocialScribe.SalesforceApi

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
      |> SocialScribe.Accounts.create_user_credential()

    credential
  end

  describe "search_contacts/2" do
    test "returns formatted contacts on success" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :get, url: url} ->
        assert String.contains?(url, "/query")

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "records" => [
               %{
                 "Id" => "003ABC",
                 "FirstName" => "Jane",
                 "LastName" => "Doe",
                 "Email" => "jane@example.com",
                 "Phone" => "555-9876",
                 "MobilePhone" => nil,
                 "Title" => "Director",
                 "Department" => "Sales",
                 "Account" => %{"Name" => "BigCorp"},
                 "MailingStreet" => nil,
                 "MailingCity" => nil,
                 "MailingState" => nil,
                 "MailingPostalCode" => nil,
                 "MailingCountry" => nil,
                 "Description" => nil
               }
             ]
           }
         }}
      end)

      assert {:ok, [contact]} = SalesforceApi.search_contacts(credential, "Jane")
      assert contact.id == "003ABC"
      assert contact.firstname == "Jane"
      assert contact.company == "BigCorp"
      assert contact.display_name == "Jane Doe"
    end

    test "uses email as display_name when name is blank" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :get} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "records" => [
               %{
                 "Id" => "003XYZ",
                 "FirstName" => nil,
                 "LastName" => nil,
                 "Email" => "noname@corp.com",
                 "Phone" => nil,
                 "MobilePhone" => nil,
                 "Title" => nil,
                 "Department" => nil,
                 "Account" => nil,
                 "MailingStreet" => nil,
                 "MailingCity" => nil,
                 "MailingState" => nil,
                 "MailingPostalCode" => nil,
                 "MailingCountry" => nil,
                 "Description" => nil
               }
             ]
           }
         }}
      end)

      assert {:ok, [contact]} = SalesforceApi.search_contacts(credential, "noname")
      assert contact.display_name == "noname@corp.com"
    end

    test "returns {:error, {:api_error, status, body}} on non-200" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 400, body: %{"message" => "Bad request"}}}
      end)

      assert {:error, {:api_error, 400, _}} = SalesforceApi.search_contacts(credential, "query")
    end

    test "returns {:error, {:http_error, reason}} on connection failure" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :get} -> {:error, :timeout} end)

      assert {:error, {:http_error, :timeout}} =
               SalesforceApi.search_contacts(credential, "query")
    end
  end

  describe "get_contact/2" do
    test "returns formatted contact on success" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :get, url: url} ->
        assert String.contains?(url, "/sobjects/Contact/003ABC")

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "Id" => "003ABC",
             "FirstName" => "Alice",
             "LastName" => "Smith",
             "Email" => "alice@sf.com",
             "Phone" => "555-0000",
             "MobilePhone" => nil,
             "Title" => "VP",
             "Department" => nil,
             "Account" => nil,
             "MailingStreet" => nil,
             "MailingCity" => nil,
             "MailingState" => nil,
             "MailingPostalCode" => nil,
             "MailingCountry" => nil,
             "Description" => nil
           }
         }}
      end)

      assert {:ok, contact} = SalesforceApi.get_contact(credential, "003ABC")
      assert contact.id == "003ABC"
      assert contact.title == "VP"
    end

    test "returns {:error, :not_found} on 404" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 404, body: %{}}}
      end)

      assert {:error, :not_found} = SalesforceApi.get_contact(credential, "missing")
    end

    test "returns {:error, {:api_error, status, body}} on other errors" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 500, body: %{"message" => "Server error"}}}
      end)

      assert {:error, {:api_error, 500, _}} = SalesforceApi.get_contact(credential, "id")
    end
  end

  describe "update_contact/3" do
    test "returns {:ok, :updated} on 204" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :patch, url: url} ->
        assert String.contains?(url, "/sobjects/Contact/003ABC")
        {:ok, %Tesla.Env{status: 204, body: ""}}
      end)

      assert {:ok, :updated} =
               SalesforceApi.update_contact(credential, "003ABC", %{"Phone" => "555-9999"})
    end

    test "returns {:ok, :updated} on 200" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :patch} ->
        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      assert {:ok, :updated} =
               SalesforceApi.update_contact(credential, "003ABC", %{"Title" => "Manager"})
    end

    test "returns {:error, :not_found} on 404" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :patch} ->
        {:ok, %Tesla.Env{status: 404, body: %{}}}
      end)

      assert {:error, :not_found} =
               SalesforceApi.update_contact(credential, "missing", %{"Phone" => "123"})
    end
  end

  describe "apply_updates/3" do
    test "returns :no_updates when updates list is empty" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003ABC", [])
    end

    test "returns :no_updates when no updates have apply: true" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "Phone", new_value: "555-1234", apply: false},
        %{field: "Email", new_value: "test@example.com", apply: false}
      ]

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003ABC", updates)
    end

    test "calls update_contact for updates with apply: true" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :patch} ->
        {:ok, %Tesla.Env{status: 204, body: ""}}
      end)

      updates = [
        %{field: "Phone", new_value: "555-9999", apply: true},
        %{field: "Email", new_value: "skip@example.com", apply: false}
      ]

      assert {:ok, :updated} = SalesforceApi.apply_updates(credential, "003ABC", updates)
    end
  end

  describe "token refresh retry logic" do
    test "retries on 401 INVALID_SESSION_ID and returns token_refresh_failed when refresh fails" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn env ->
        cond do
          String.contains?(env.url, "/query") ->
            {:ok,
             %Tesla.Env{
               status: 401,
               body: [%{"errorCode" => "INVALID_SESSION_ID", "message" => "Session expired"}]
             }}

          String.contains?(env.url, "login.salesforce.com") ->
            {:ok, %Tesla.Env{status: 400, body: %{"error" => "invalid_client"}}}

          true ->
            {:error, :unexpected_url}
        end
      end)

      assert {:error, {:token_refresh_failed, _}} =
               SalesforceApi.search_contacts(credential, "test")
    end

    test "does not retry on 401 without token error code" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock(fn %{method: :get} ->
        {:ok,
         %Tesla.Env{
           status: 401,
           body: [%{"errorCode" => "INSUFFICIENT_ACCESS", "message" => "Access denied"}]
         }}
      end)

      assert {:error, {:api_error, 401, _}} = SalesforceApi.search_contacts(credential, "test")
    end
  end
end
