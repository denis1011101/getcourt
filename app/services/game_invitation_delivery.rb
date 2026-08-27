class GameInvitationDelivery
  def initialize(game:, inviter:, game_url:)
    @game = game
    @inviter = inviter
    @game_url = game_url
  end

  def deliver(user:, role: :player)
    NotificationDelivery.deliver(
      user: user,
      notification: notification_for(role)
    )
  end

  private

  attr_reader :game, :inviter, :game_url

  def notification_for(role)
    coach_invitation = role.to_sym == :coach

    NotificationDelivery::Notification.new(
      subject: lambda do |locale|
        key = coach_invitation ? "coach_invitation_subject" : "game_invitation_subject"
        I18n.t("user_mailer.notification.#{key}", locale: locale, game_id: game.id)
      end,
      body: lambda do |locale, channel|
        lines = [
          Telegram::I18n.t(title_key(coach_invitation), locale: locale),
          Telegram::Handlers::GamesHandler.game_label(game, owner: inviter, locale: locale, coach_names: true, channel: channel),
          court_line(locale),
          program_line(locale),
          Telegram::I18n.t(:game_invitation_from, locale: locale, name: inviter_name(locale, channel))
        ]
        "#{lines.compact.join("\n")}\n\n#{game_url}"
      end,
      actions: lambda do |locale|
        if coach_invitation
          coach_actions(locale)
        else
          player_actions(locale)
        end
      end
    )
  end

  # Шапка сразу говорит, куда зовут: в игру, на тренировку или тренером на неё.
  def title_key(coach_invitation)
    if coach_invitation
      :coach_invitation_title
    elsif game.training?
      :training_invitation_title
    else
      :invitation_title
    end
  end

  # Куда ехать — вопрос, который задают первым. В напоминании корт назван, а в
  # приглашении его не было вовсе: человек шёл за ним по ссылке.
  def court_line(locale)
    name = game.court&.name.to_s.strip

    Telegram::I18n.t(:court_label, locale: locale, name: name) if name.present?
  end

  # План занятия — самое важное в приглашении на тренировку после времени и корта.
  def program_line(locale)
    program = Telegram::Helpers::GameFormatting.training_program(game, locale: locale)

    Telegram::I18n.t(:program_label, locale: locale, items: program) if program.present?
  end

  def inviter_name(locale, channel)
    Telegram::Helpers::UserLookup.display_name(
      inviter,
      fallback: Telegram::I18n.t(:user_fallback, locale: locale),
      channel: channel
    )
  end

  def player_actions(locale)
    [
      {
        label: Telegram::I18n.t(:invitation_join, locale: locale, game_id: game.id),
        callback_data: "game:join_invited:#{game.id}",
        row: 0,
        url: game_url
      },
      {
        label: Telegram::I18n.t(:invitation_decline, locale: locale, game_id: game.id),
        callback_data: "game:invite_decline:#{game.id}",
        row: 0
      }
    ]
  end

  def coach_actions(locale)
    [
      {
        label: Telegram::I18n.t(:coach_invitation_accept, locale: locale, game_id: game.id),
        callback_data: "game:coach_accept:#{game.id}",
        row: 0,
        url: game_url
      },
      {
        label: Telegram::I18n.t(:coach_invitation_decline, locale: locale, game_id: game.id),
        callback_data: "game:coach_decline:#{game.id}",
        row: 0
      }
    ]
  end
end
