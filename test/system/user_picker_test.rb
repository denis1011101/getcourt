require "application_system_test_case"

# Поле выбора игрока живёт в JS: подсказки приходят с сервера по первым буквам,
# а выбор либо отправляет форму (предзапись), либо становится галкой (статистика).
class UserPickerTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  setup do
    @owner = User.create!(email: "picker_owner@example.com", name: "Picker Owner")
    @player = User.create!(email: "picker_player@example.com", name: "Ирина Подсказка", telegram_username: "irina_tg")
    User.create!(email: "picker_other@example.com", name: "Someone Else")
  end

  test "organizer books a player into a prebooking slot by typing a name" do
    game = Game.create!(court: courts(:one), user: @owner, date: Date.current.next_occurring(:monday),
                        recurring: true, prebooking_enabled: true, players_count: 2)
    sign_in @owner

    visit game_path(game)
    within("[data-testid=prebooking-day]", match: :first) do
      find("[data-testid=user-picker] input[type=text]").fill_in with: "ири"
      assert_selector "[role=option]", text: "Ирина Подсказка (@irina_tg)", count: 1
      assert_no_selector "[role=option]", text: "Someone Else"
      find("[role=option]", text: "Ирина Подсказка").click
    end

    assert_selector "[data-testid=prebooking-day]", text: "Ирина Подсказка", wait: 5
    assert_equal @player, game.prebookings.order(:date, :slot_index).first.reload.user
  end

  # Между правкой текста и ответом сервера проходит 200 мс, и прежние подсказки
  # в это время не должны отвечать на Enter — иначе форма ушла бы не с тем.
  test "enter right after retyping does not pick a suggestion for the old text" do
    igor = User.create!(email: "picker_igor@example.com", name: "Игорь Иванов")
    game = Game.create!(court: courts(:one), user: @owner, date: Date.current.next_occurring(:monday),
                        recurring: true, prebooking_enabled: true, players_count: 2)
    sign_in @owner

    visit game_path(game)
    within("[data-testid=prebooking-day]", match: :first) do
      find("[data-testid=user-picker] input[type=text]").fill_in with: "иго"
      assert_selector "[role=option]", text: "Игорь Иванов", count: 1

      # Ввод и Enter одним скриптом — так между ними точно не успеет прийти
      # ответ на новый текст.
      page.execute_script(<<~JS, find("[data-testid=user-picker] input[type=text]").native)
        const input = arguments[0]
        input.value = "ири"
        input.dispatchEvent(new Event("input", { bubbles: true }))
        input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
      JS

      assert_no_selector "[role=option]", text: "Игорь Иванов"
      assert_selector "[role=option]", text: "Ирина Подсказка (@irina_tg)", count: 1
      assert_equal "", find("[data-testid=user-picker] input[name=user_id]", visible: false).value
    end

    assert_nil game.prebookings.order(:date, :slot_index).first.reload.user
    assert_not_equal igor, game.prebookings.find_by(user: igor)&.user
  end

  test "stats form turns a picked player into a checked team checkbox" do
    game = Game.create!(court: courts(:one), user: @owner, date: Date.yesterday, time: "10:00", with_coach: false)
    sign_in @owner

    visit game_path(game)
    within("[data-stats-match-block]", match: :first) do
      pickers = all("[data-controller=team-players]")
      within(pickers.first) do
        input = find("[data-testid=user-picker] input[type=text]")
        input.fill_in with: "@iri"
        assert_selector "[role=option]", text: "Ирина Подсказка (@irina_tg)"
        # Первый вариант уже подсвечен — Enter берёт его без мыши.
        input.send_keys(:enter)

        assert_selector "input[type=checkbox][name='matches[0][team_a_user_ids][]'][value='#{@player.id}']"
        assert find("input[type=checkbox][value='#{@player.id}']").checked?
        assert_selector "label", text: "Ирина Подсказка (@irina_tg)"
        # Поле очистилось под следующего.
        assert_equal "", input.value
      end
    end
  end

  private

  def sign_in(user)
    visit new_session_path
    fill_in "Email", with: user.email
    # Настоящий браузер не даст отправить форму без обязательных галок.
    check "privacy_consent"
    check "age_consent"
    click_on "Enter"
    # Дальше идём только после редиректа: иначе visit уходит без сессии.
    assert_text "Signed in as #{user.email}"
  end
end
