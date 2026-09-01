module Telegram
  module Presenters
    class ProfilePresenter
      def initialize(user)
        @user = user
      end

      def email_label
        @user.respond_to?(:email) ? (@user.email.to_s.presence || "—") : "—"
      end

      def sports_label
        if @user.respond_to?(:preferred_sports) && @user.preferred_sports.present?
          arr = @user.preferred_sports
          arr.is_a?(Array) ? arr.join(", ") : arr.to_s
        elsif @user.respond_to?(:sports) && @user.sports.present?
          @user.sports.to_s
        else
          "—"
        end
      end

      def level_label
        if @user.respond_to?(:skill_level) && @user.skill_level.present?
          @user.skill_level.to_s
        elsif @user.respond_to?(:level) && @user.level.present?
          @user.level.to_s
        else
          "—"
        end
      end

      def city_label
        val =
          if @user.respond_to?(:city_name) && @user.city_name.present?
            @user.city_name
          elsif @user.respond_to?(:city) && @user.city.present?
            @user.city
          elsif @user.respond_to?(:location) && @user.location.present?
            @user.location
          else
            nil
          end
        val.presence || "—"
      end

      def coach_label
        return "—" unless @user.respond_to?(:coach)
        case @user.coach
        when true  then "Yes"
        when false then "No"
        else "—"
        end
      end

      def about_me_label
        @user.respond_to?(:about_me) ? (@user.about_me.to_s.presence || "—") : "—"
      end

      def favorite_courts_label
        return "—" unless @user.respond_to?(:favorite_courts)

        names = @user.favorite_courts.map(&:name).reject(&:blank?)
        names.any? ? names.join(", ") : "—"
      end

      def court_note_label
        @user.respond_to?(:court_preferences_note) ? (@user.court_preferences_note.to_s.presence || "—") : "—"
      end

      def notify_label
        if @user.respond_to?(:notify_nearby)
          @user.notify_nearby ? "Yes" : "No"
        else
          "—"
        end
      end

      # return raw/current value for given field (used by FieldFlow)
      def current_value_for(field)
        case field.to_s
        when "email"
          @user.respond_to?(:email) ? @user.email.to_s : ""
        when "sports"
          if @user.respond_to?(:preferred_sports) && @user.preferred_sports.present?
            arr = @user.preferred_sports
            arr.is_a?(Array) ? arr.join(", ") : arr.to_s
          elsif @user.respond_to?(:sports) && @user.sports.present?
            @user.sports.to_s
          else
            ""
          end
        when "city"
          if @user.respond_to?(:city_name) && @user.city_name.present?
            @user.city_name.to_s
          elsif @user.respond_to?(:city) && @user.city.present?
            @user.city.to_s
          elsif @user.respond_to?(:location) && @user.location.present?
            @user.location.to_s
          else
            ""
          end
        when "coach"
          return "" unless @user.respond_to?(:coach)
          case @user.coach
          when true  then "Yes"
          when false then "No"
          else ""
          end
        when "favorite_courts"
          @user.respond_to?(:favorite_courts) ? favorite_courts_label : ""
        when "court_note"
          @user.respond_to?(:court_preferences_note) ? @user.court_preferences_note.to_s : ""
        when "notify"
          @user.respond_to?(:notify_nearby) ? (@user.notify_nearby ? "Yes" : "No") : ""
        else
          if @user.respond_to?(field)
            v = @user.public_send(field)
            v.nil? ? "" : v.to_s
          else
            ""
          end
        end
      end
    end
  end
end
