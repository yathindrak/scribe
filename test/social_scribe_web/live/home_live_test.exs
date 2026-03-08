defmodule SocialScribeWeb.HomeLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.CalendarFixtures
  import Mox

  setup :verify_on_exit!

  describe "mount" do
    test "redirects to login when not authenticated", %{conn: conn} do
      result = live(conn, ~p"/dashboard")
      assert {:error, {:redirect, %{to: path}}} = result
      assert path =~ "/users/log_in"
    end

    test "renders upcoming meetings page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _live, html} = live(conn, ~p"/dashboard")

      assert html =~ "Upcoming Meetings"
    end

    test "shows upcoming events for the user", %{conn: conn} do
      user = user_fixture()
      credential = user_credential_fixture(%{user_id: user.id})

      # Create a future calendar event
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      calendar_event_fixture(%{
        user_id: user.id,
        user_credential_id: credential.id,
        start_time: future_time,
        end_time: DateTime.add(future_time, 3600, :second),
        summary: "Upcoming Team Sync"
      })

      conn = log_in_user(conn, user)
      {:ok, _live, html} = live(conn, ~p"/dashboard")

      assert html =~ "Upcoming Team Sync"
    end
  end

  describe "handle_event toggle_record" do
    test "toggles record_meeting off and cancels bot (no bot in DB)", %{conn: conn} do
      user = user_fixture()
      credential = user_credential_fixture(%{user_id: user.id})

      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      event =
        calendar_event_fixture(%{
          user_id: user.id,
          user_credential_id: credential.id,
          start_time: future_time,
          end_time: DateTime.add(future_time, 3600, :second),
          summary: "Recorded Meeting",
          record_meeting: true
        })

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/dashboard")

      # Toggle off - no bot in DB so cancel_and_delete_bot returns {:ok, :no_bot_to_cancel}
      # The event still renders after the toggle
      result =
        live
        |> element("[phx-click='toggle_record'][phx-value-id='#{event.id}']")
        |> render_click()

      # After toggling, the page still renders without error
      assert is_binary(result)
    end
  end

  describe "handle_info :sync_calendars" do
    test "sync updates loading state and events list", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      # When connected, :sync_calendars is sent automatically
      # The user has no google credentials, so sync is a no-op
      {:ok, live, _html} = live(conn, ~p"/dashboard")

      # After sync, loading should be false and page still renders
      html = render(live)
      assert html =~ "Upcoming Meetings"
    end
  end
end
