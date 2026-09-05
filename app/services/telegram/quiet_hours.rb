module Telegram
  # Ночью бот пишет молча: сообщение приходит сразу, но без звука и вибрации.
  # Ночь считаем по часовому поясу получателя, а не сервера: рассылки ходят по
  # расписанию сервера, и «полдень» крона — это четыре утра у человека.
  module QuietHours
    # Часы, когда бот вправе звенеть: с 10:00 до 22:00. В 21:59 ещё со звуком,
    # в 22:00 уже без.
    LOUD_HOURS = (10...22).freeze
    # Тот же пояс, что у User#timezone_or_default: у чата без хозяина (например
    # админского) своего пояса нет, а молчать ночью он должен так же.
    DEFAULT_ZONE = "Asia/Yekaterinburg"

    class << self
      # silent: явное решение вызывающего — true всегда молча, false всегда со
      # звуком (так уходит сообщение участника в чате игры: его ждут и ночью),
      # nil — решаем по времени получателя.
      def apply(params, silent: nil, at: Time.current)
        silent = silent?(params["chat_id"] || params[:chat_id], at: at) if silent.nil?
        return params unless silent

        params.merge("disable_notification" => "true")
      end

      def silent?(chat_id, at: Time.current)
        return false if chat_id.blank?

        !LOUD_HOURS.cover?(at.in_time_zone(zone_for(chat_id)).hour)
      end

      private

      # Пояс берём у получателя, но не доверяем ему вслепую: в колонке лежит
      # строка, а незнакомое имя пояса уронило бы отправку целиком.
      def zone_for(chat_id)
        zone = Telegram::Helpers::UserLookup.find_user(chat_id)&.timezone_or_default
        ActiveSupport::TimeZone[zone.to_s] ? zone : DEFAULT_ZONE
      end
    end
  end
end
