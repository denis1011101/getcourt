require "test_helper"

class TennisLifeMenuHandlerTest < ActiveSupport::TestCase
  def setup
    @chat_id = 123
    @fixed_time = Time.zone.parse("2026-03-07 15:11:10")
  end

  test "sends tennis life menu with refresh button and updated timestamp" do
    sent = nil

    stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :ru) do
      stub_singleton(TennisScoreboard::Fetcher, :telegram_text, "Live scoreboard") do
        stub_singleton(Time, :current, @fixed_time) do
          stub_singleton(Telegram::Api, :send_with_buttons, ->(*args) { sent = args }) do
            Telegram::Handlers::TennisLifeMenuHandler.show(@chat_id)
          end
        end
      end
    end

    assert sent.present?
    assert_equal @chat_id, sent[0]
    assert_includes sent[1], "Обновлено: 15:11:10"
    assert_includes sent[1], "Live scoreboard"
    assert_equal [ { text: "Обновить", callback_data: "menu:tennis_life" } ], sent[2][0]
    assert_equal [ { text: "Главное меню", callback_data: "menu:main" } ], sent[2][1]
    assert_nil sent[3][:parse_mode]
  end

  test "shows random gist post in feed when no db posts exist" do
    sent = nil
    gist_post = {
      "channel_name" => "Теннисология",
      "channel_url" => "https://t.me/tennisologia",
      "text" => "Джокович вернулся!",
      "url" => "https://t.me/tennisologia/99",
      "published_at" => "2024-06-01T12:00:00Z"
    }

    stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :ru) do
      stub_singleton(TennisScoreboard::Fetcher, :telegram_text, nil) do
        stub_singleton(Time, :current, @fixed_time) do
          stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, gist_post) do
            stub_singleton(Telegram::Api, :send_with_buttons, ->(*args) { sent = args }) do
              handler = Telegram::Handlers::TennisLifeMenuHandler
              stub_singleton(handler, :fetch_recent_posts, []) do
                handler.show(@chat_id)
              end
            end
          end
        end
      end
    end

    assert sent.present?
    assert_includes sent[1], "Теннисология:"
    assert_includes sent[1], "Джокович вернулся!"
    assert_includes sent[1], "https://t.me/tennisologia/99"
  end

  test "shows no_posts text when both db posts and gist post are absent" do
    sent = nil

    stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :ru) do
      stub_singleton(TennisScoreboard::Fetcher, :telegram_text, nil) do
        stub_singleton(Time, :current, @fixed_time) do
          stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, nil) do
            stub_singleton(Telegram::Api, :send_with_buttons, ->(*args) { sent = args }) do
              handler = Telegram::Handlers::TennisLifeMenuHandler
              stub_singleton(handler, :fetch_recent_posts, []) do
                handler.show(@chat_id)
              end
            end
          end
        end
      end
    end

    assert sent.present?
    assert_includes sent[1], "Пока постов нет"
  end

  test "does not include channels section" do
    sent = nil

    stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :ru) do
      stub_singleton(TennisScoreboard::Fetcher, :telegram_text, nil) do
        stub_singleton(Time, :current, @fixed_time) do
          stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, nil) do
            stub_singleton(Telegram::Api, :send_with_buttons, ->(*args) { sent = args }) do
              Telegram::Handlers::TennisLifeMenuHandler.show(@chat_id)
            end
          end
        end
      end
    end

    assert sent.present?
    assert_not_includes sent[1], "Каналы:"
  end

  test "edits existing tennis life menu when message id is provided" do
    edited = nil

    stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :en) do
      stub_singleton(TennisScoreboard::Fetcher, :telegram_text, nil) do
        stub_singleton(Time, :current, @fixed_time) do
          stub_singleton(Telegram::Api, :edit_message_with_buttons, ->(*args) { edited = args }) do
            Telegram::Handlers::TennisLifeMenuHandler.show(@chat_id, message_id: 555)
          end
        end
      end
    end

    assert edited.present?
    assert_equal @chat_id, edited[0]
    assert_equal 555, edited[1]
    assert_includes edited[2], "Updated: 15:11:10"
    assert_equal [ { text: "Refresh", callback_data: "menu:tennis_life" } ], edited[3][0]
    assert_equal [ { text: "Main menu", callback_data: "menu:main" } ], edited[3][1]
    assert_nil edited[4][:parse_mode]
  end
end
