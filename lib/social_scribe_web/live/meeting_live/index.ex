defmodule SocialScribeWeb.MeetingLive.Index do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo

  alias SocialScribe.Meetings

  @impl true
  def mount(_params, _session, socket) do
    meetings = Meetings.list_user_meetings(socket.assigns.current_user)
    timezone = get_connect_params(socket)["timezone"] || "UTC"

    socket =
      socket
      |> assign(:page_title, "Past Meetings")
      |> assign(:meetings, meetings)
      |> assign(:timezone, timezone)

    {:ok, socket}
  end

  defp format_recorded_at(nil, _tz), do: "N/A"

  defp format_recorded_at(dt, timezone) do
    case Timex.Timezone.convert(dt, timezone) do
      {:error, _} -> Timex.format!(dt, "{Mshort} {D}, {YYYY} {h12}:{m}{AM} UTC")
      local -> Timex.format!(local, "{Mshort} {D}, {YYYY} {h12}:{m}{AM}")
    end
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    "#{minutes} min"
  end
end
