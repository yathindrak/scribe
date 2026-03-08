defmodule SocialScribeWeb.MeetingLive.IndexTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures

  defp create_user_with_meeting(_context) do
    user = user_fixture()
    credential = user_credential_fixture(%{user_id: user.id})
    calendar_event = calendar_event_fixture(%{user_id: user.id, user_credential_id: credential.id})
    meeting = meeting_fixture(%{calendar_event_id: calendar_event.id})
    %{user: user, meeting: meeting}
  end

  describe "Index" do
    setup [:create_user_with_meeting]

    test "redirects to login when not authenticated", %{conn: conn} do
      result = live(conn, ~p"/dashboard/meetings")
      assert {:error, {:redirect, %{to: path}}} = result
      assert path =~ "/users/log_in"
    end

    test "lists meetings for authenticated user", %{conn: conn, user: user, meeting: meeting} do
      conn = log_in_user(conn, user)
      {:ok, _live, html} = live(conn, ~p"/dashboard/meetings")

      assert html =~ "Past Meetings"
      assert html =~ meeting.title
    end

    test "shows empty state when user has no meetings", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {:ok, _live, html} = live(conn, ~p"/dashboard/meetings")

      assert html =~ "Past Meetings"
    end
  end
end
