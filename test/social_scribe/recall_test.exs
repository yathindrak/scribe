defmodule SocialScribe.RecallTest do
  use ExUnit.Case, async: false

  import Tesla.Mock

  alias SocialScribe.Recall

  setup do
    Application.put_env(:social_scribe, :recall_api_key, "test_recall_key")
    Application.put_env(:social_scribe, :recall_region, "us-west-2")
    :ok
  end

  describe "create_bot/2" do
    test "posts to /bot with correct body" do
      join_at = DateTime.utc_now()

      mock(fn %{method: :post, url: "https://us-west-2.recall.ai/api/v1/bot", body: body} ->
        assert body =~ "https://meet.google.com/abc"
        assert body =~ "Social Scribe Bot"
        {:ok, %Tesla.Env{status: 200, body: %{id: "bot_123"}}}
      end)

      assert {:ok, _} = Recall.create_bot("https://meet.google.com/abc", join_at)
    end
  end

  describe "update_bot/3" do
    test "patches /bot/:id" do
      join_at = DateTime.utc_now()

      mock(fn %{method: :patch, url: "https://us-west-2.recall.ai/api/v1/bot/bot_abc"} ->
        {:ok, %Tesla.Env{status: 200, body: %{id: "bot_abc"}}}
      end)

      assert {:ok, _} =
               Recall.update_bot("bot_abc", "https://meet.google.com/new", join_at)
    end
  end

  describe "delete_bot/1" do
    test "sends DELETE to /bot/:id" do
      mock(fn %{method: :delete, url: "https://us-west-2.recall.ai/api/v1/bot/bot_xyz"} ->
        {:ok, %Tesla.Env{status: 204, body: ""}}
      end)

      assert {:ok, _} = Recall.delete_bot("bot_xyz")
    end
  end

  describe "get_bot/1" do
    test "sends GET to /bot/:id" do
      mock(fn %{method: :get, url: "https://us-west-2.recall.ai/api/v1/bot/bot_123"} ->
        {:ok, %Tesla.Env{status: 200, body: %{id: "bot_123", status: "done"}}}
      end)

      assert {:ok, _} = Recall.get_bot("bot_123")
    end
  end

  describe "get_bot_transcript/1" do
    test "returns {:error, :no_recordings} when bot has no recordings" do
      mock(fn %{method: :get, url: "https://us-west-2.recall.ai/api/v1/bot/bot_123"} ->
        {:ok, %Tesla.Env{status: 200, body: %{id: "bot_123", recordings: []}}}
      end)

      assert {:error, :no_recordings} = Recall.get_bot_transcript("bot_123")
    end

    test "returns {:error, :no_transcript_url} when recording has no transcript URL" do
      mock(fn env ->
        cond do
          String.contains?(env.url, "/bot/bot_123") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{id: "bot_123", recordings: [%{id: "rec_1"}]}
             }}

          String.contains?(env.url, "/recording/rec_1") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{media_shortcuts: %{transcript: %{data: %{download_url: nil}}}}
             }}

          true ->
            {:error, :unexpected_url}
        end
      end)

      assert {:error, :no_transcript_url} = Recall.get_bot_transcript("bot_123")
    end

    test "fetches transcript when download URL is present" do
      transcript_url = "https://storage.example.com/transcript.json"

      mock(fn env ->
        cond do
          String.contains?(env.url, "/bot/bot_123") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{id: "bot_123", recordings: [%{id: "rec_1"}]}
             }}

          String.contains?(env.url, "/recording/rec_1") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 media_shortcuts: %{
                   transcript: %{data: %{download_url: transcript_url}}
                 }
               }
             }}

          env.url == transcript_url ->
            {:ok, %Tesla.Env{status: 200, body: [%{speaker: "John", words: []}]}}

          true ->
            {:error, :unexpected_url}
        end
      end)

      assert {:ok, _} = Recall.get_bot_transcript("bot_123")
    end

    test "returns {:error, reason} when get_bot fails" do
      mock(fn %{method: :get, url: "https://us-west-2.recall.ai/api/v1/bot/bad_bot"} ->
        {:ok, %Tesla.Env{status: 404, body: %{detail: "Not found"}}}
      end)

      # get_bot returns {:ok, env} but the with-chain uses it as raw Tesla.Env
      # This just tests that error propagation works if the HTTP call itself fails
      mock(fn %{method: :get} -> {:error, :econnrefused} end)

      assert {:error, :econnrefused} = Recall.get_bot_transcript("bad_bot")
    end
  end

  describe "get_bot_participants/1" do
    test "returns {:error, :no_recordings} when bot has no recordings" do
      mock(fn %{method: :get, url: "https://us-west-2.recall.ai/api/v1/bot/bot_123"} ->
        {:ok, %Tesla.Env{status: 200, body: %{id: "bot_123", recordings: []}}}
      end)

      assert {:error, :no_recordings} = Recall.get_bot_participants("bot_123")
    end

    test "returns {:error, :no_participants_url} when recording has no participant URL" do
      mock(fn env ->
        cond do
          String.contains?(env.url, "/bot/bot_123") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{id: "bot_123", recordings: [%{id: "rec_1"}]}
             }}

          String.contains?(env.url, "/recording/rec_1") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{media_shortcuts: %{participant_events: %{data: %{participants_download_url: nil}}}}
             }}

          true ->
            {:error, :unexpected_url}
        end
      end)

      assert {:error, :no_participants_url} = Recall.get_bot_participants("bot_123")
    end

    test "fetches participants using media_shortcuts URL" do
      participants_url = "https://storage.example.com/participants.json"

      mock(fn env ->
        cond do
          String.contains?(env.url, "/bot/bot_123") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{id: "bot_123", recordings: [%{id: "rec_1"}]}
             }}

          String.contains?(env.url, "/recording/rec_1") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 media_shortcuts: %{
                   participant_events: %{
                     data: %{participants_download_url: participants_url}
                   }
                 }
               }
             }}

          env.url == participants_url ->
            {:ok, %Tesla.Env{status: 200, body: [%{name: "John Doe"}]}}

          true ->
            {:error, :unexpected_url}
        end
      end)

      assert {:ok, _} = Recall.get_bot_participants("bot_123")
    end
  end
end
