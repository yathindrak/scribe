defmodule SocialScribeWeb.MeetingLive.ShowTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures

  defp build_meeting_for_user(user) do
    credential = user_credential_fixture(%{user_id: user.id})
    calendar_event = calendar_event_fixture(%{user_id: user.id, user_credential_id: credential.id})
    meeting_fixture(%{calendar_event_id: calendar_event.id})
  end

  describe "Show" do
    test "redirects to login when not authenticated", %{conn: conn} do
      user = user_fixture()
      meeting = build_meeting_for_user(user)
      result = live(conn, ~p"/dashboard/meetings/#{meeting.id}")
      assert {:error, {:redirect, %{to: path}}} = result
      assert path =~ "/users/log_in"
    end

    test "renders meeting details for the owner", %{conn: conn} do
      user = user_fixture()
      meeting = build_meeting_for_user(user)
      conn = log_in_user(conn, user)

      {:ok, _live, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ meeting.title
      assert html =~ "Meeting Transcript"
    end

    test "redirects when user does not own the meeting", %{conn: conn} do
      owner = user_fixture()
      visitor = user_fixture()
      meeting = build_meeting_for_user(owner)
      conn = log_in_user(conn, visitor)

      assert {:error, {:redirect, %{to: "/dashboard/meetings"}}} =
               live(conn, ~p"/dashboard/meetings/#{meeting.id}")
    end

    test "shows meeting duration", %{conn: conn} do
      user = user_fixture()
      meeting = build_meeting_for_user(user)
      conn = log_in_user(conn, user)

      {:ok, _live, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      # duration_seconds is 42 by default in fixture
      assert html =~ "sec" or html =~ "min"
    end
  end
end
