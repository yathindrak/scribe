defmodule SocialScribe.GoogleCalendarTest do
  use ExUnit.Case, async: false

  import Tesla.Mock

  alias SocialScribe.GoogleCalendar

  describe "list_events/4" do
    test "returns {:ok, body} on success" do
      events_body = %{
        "items" => [
          %{"id" => "event_1", "summary" => "Team Meeting"}
        ]
      }

      mock(fn %{method: :get, url: url} ->
        assert String.contains?(url, "/calendars/primary/events")
        {:ok, %Tesla.Env{status: 200, body: events_body}}
      end)

      start_time = DateTime.utc_now()
      end_time = DateTime.add(start_time, 7200, :second)

      assert {:ok, ^events_body} =
               GoogleCalendar.list_events("g_token", start_time, end_time, "primary")
    end

    test "returns {:error, {status, body}} on non-200 status" do
      mock(fn %{method: :get} ->
        {:ok, %Tesla.Env{status: 401, body: %{"error" => "unauthorized"}}}
      end)

      start_time = DateTime.utc_now()
      end_time = DateTime.add(start_time, 3600, :second)

      assert {:error, {401, %{"error" => "unauthorized"}}} =
               GoogleCalendar.list_events("bad_token", start_time, end_time, "primary")
    end

    test "returns {:error, reason} on connection failure" do
      mock(fn %{method: :get} ->
        {:error, :timeout}
      end)

      start_time = DateTime.utc_now()
      end_time = DateTime.add(start_time, 3600, :second)

      assert {:error, :timeout} =
               GoogleCalendar.list_events("token", start_time, end_time, "primary")
    end

    test "includes authorization header" do
      mock(fn %{method: :get, headers: headers} ->
        auth = Enum.find(headers, fn {k, _} -> k == "Authorization" end)
        assert auth == {"Authorization", "Bearer my_google_token"}
        {:ok, %Tesla.Env{status: 200, body: %{"items" => []}}}
      end)

      start_time = DateTime.utc_now()
      end_time = DateTime.add(start_time, 3600, :second)

      assert {:ok, _} =
               GoogleCalendar.list_events("my_google_token", start_time, end_time, "primary")
    end
  end
end
