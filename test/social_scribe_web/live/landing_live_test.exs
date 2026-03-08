defmodule SocialScribeWeb.LandingLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "landing page" do
    test "renders landing page", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/")

      assert html =~ "Turn Meetings into"
      assert html =~ "Get Started for Free"
      assert html =~ "Connect your Google Calendar"
    end

    test "contains link to Google auth", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/")

      assert html =~ "/auth/google"
    end
  end
end
