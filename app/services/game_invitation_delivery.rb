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
      body: lambda do |locale|
        title_key = coach_invitation ? :coach_invitation_title : :invitation_title
        lines = [
          Telegram::I18n.t(title_key, locale: locale),
          Telegram::Handlers::GamesHandler.game_label(game, owner: inviter, locale: locale),
          Telegram::I18n.t(:game_invitation_from, locale: locale, name: inviter.name.presence || inviter.email)
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
