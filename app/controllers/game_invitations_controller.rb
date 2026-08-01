class GameInvitationsController < ApplicationController
  before_action :set_game
  before_action :authorize_manage_game!

  def create
    handles = invite_handles
    return redirect_to @game, alert: "Enter at least one Telegram username." if handles.empty?

    result = send_invitations(handles)
    if result[:sent].any?
      current_user.remember_invite_handles(handles)
      redirect_to @game, notice: invitation_notice(result)
    else
      redirect_to @game, alert: invitation_notice(result)
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def authorize_manage_game!
    head :forbidden unless can_manage?(@game)
  end

  def invite_handles
    params[:usernames].to_s.scan(/@?[A-Za-z0-9_]{5,32}/).map { |handle| handle.delete_prefix("@").downcase }.uniq
  end

  def send_invitations(handles)
    result = { sent: [], not_found: [], skipped_self: [], no_telegram: [], failed: [] }
    resolve_users_by_handles(handles).each do |handle, user|
      if user.blank?
        result[:not_found] << "@#{handle}"
        next
      end

      if user.id == current_user.id
        result[:skipped_self] << "@#{handle}"
        next
      end

      response = deliver_invitation(user)
      if response == false || (response.is_a?(Hash) && response["ok"] == false)
        result[:failed] << "@#{handle}"
      else
        result[:sent] << "@#{handle}"
      end
    end
    result
  end

  def invitation_payload(user)
    locale = Telegram::I18n.locale_for(user)
    t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
    lines = [
      t.(:invitation_title),
      Telegram::Handlers::GamesHandler.game_label(@game, owner: current_user, locale: locale)
    ]

    {
      chat_id: user.telegram_chat_id.to_s,
      text: "#{lines.compact.join("\n")}\n\n#{invitation_game_url(@game)}",
      reply_markup: {
        inline_keyboard: [ [
          { text: t.(:invitation_join, game_id: @game.id), callback_data: "game:join_invited:#{@game.id}" },
          { text: t.(:invitation_decline, game_id: @game.id), callback_data: "game:invite_decline:#{@game.id}" }
        ] ]
      }
    }
  end

  def deliver_invitation(user)
    payload = invitation_payload(user)
    subject, body, action_label = I18n.with_locale(NotificationDelivery.email_locale(user)) do
      [
        I18n.t("user_mailer.notification.game_invitation_subject", game_id: @game.id),
        I18n.t("user_mailer.notification.game_invitation_body", name: current_user.name.presence || current_user.email),
        I18n.t("user_mailer.notification.view_game")
      ]
    end

    NotificationDelivery.deliver(
      user: user,
      telegram_text: payload[:text],
      email_subject: subject,
      email_body: body,
      actions: [ { label: action_label, url: invitation_game_url(@game) } ],
      telegram_buttons: payload.dig(:reply_markup, :inline_keyboard)
    )
  end

  def invitation_game_url(game)
    Rails.application.routes.url_helpers.game_url(game, host: request.host_with_port, protocol: request.protocol)
  end

  def invitation_notice(result)
    parts = []
    parts << "Sent: #{result[:sent].join(', ')}" if result[:sent].any?
    parts << "Not found: #{result[:not_found].join(', ')}" if result[:not_found].any?
    parts << "Skipped self: #{result[:skipped_self].join(', ')}" if result[:skipped_self].any?
    parts << "No Telegram chat: #{result[:no_telegram].join(', ')}" if result[:no_telegram].any?
    parts << "Failed: #{result[:failed].join(', ')}" if result[:failed].any?
    parts.presence&.join(". ") || "No invitations sent."
  end

  def resolve_users_by_handles(handles)
    users_by_handle = {}
    db_handles = handles + handles.map { |handle| "@#{handle}" }
    username_scopes(db_handles).each do |scope, column|
      scope.find_each do |user|
        value = user.public_send(column).to_s.delete_prefix("@").downcase
        users_by_handle[value] = user if value.present?
      end
    end
    User.where(telegram_chat_id: handles).find_each do |user|
      users_by_handle[user.telegram_chat_id.to_s] = user
    end

    handles.index_with { |handle| users_by_handle[handle] }
  end

  def username_scopes(handles)
    [
      [ users_matching_telegram_usernames(handles), :telegram_username ],
      [ users_matching_usernames(handles), :username ]
    ]
  end

  def users_matching_telegram_usernames(handles)
    users_matching_lowered_column(:telegram_username, handles)
  end

  def users_matching_usernames(handles)
    return User.none unless User.column_names.include?("username")

    users_matching_lowered_column(:username, handles)
  end

  def users_matching_lowered_column(column, handles)
    lowered_column = Arel::Nodes::NamedFunction.new("LOWER", [ User.arel_table[column] ])
    User.where(lowered_column.in(handles))
  end
end
