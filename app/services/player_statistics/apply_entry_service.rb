module PlayerStatistics
  class ApplyEntryService
    def initialize(user:, game:, actor:, data:, source: "telegram", recorded_at: Time.current)
      @user = user
      @game = game
      @actor = actor
      @data = (data || {}).stringify_keys # важно: nil значения тоже сохраняем как намерение "удалить"
      @source = source.to_s
      @recorded_at = recorded_at
    end

    def call
      allowed = StatisticsPresenter.allowed_keys
      patch = @data.slice(*allowed) # НЕ compact — nil нужен, чтобы уметь "снимать" значение

      PlayerStatisticEntry.transaction do
        entry =
          PlayerStatisticEntry.lock.find_or_initialize_by(
            user: @user,
            game: @game,
            source: @source
          )

        old_data = (entry.persisted? ? (entry.data || {}) : {}).stringify_keys
        new_data = old_data.merge(patch)
        new_data.delete_if { |_k, v| v.nil? } # nil = удалить ключ из source of truth

        entry.actor = @actor
        entry.data = new_data
        entry.recorded_at = @recorded_at
        entry.save!

        ps = @user.player_statistic || @user.create_player_statistic

        ps.with_lock do
          allowed.each do |key|
            old_v = old_data[key]
            new_v = new_data[key]
            next if old_v == new_v

            if PlayerStatistic.numeric_field_type(key) == :float
              delta = new_v.to_f - old_v.to_f
              ps[key] = (ps[key] || 0).to_f + delta
            else
              delta = new_v.to_i - old_v.to_i
              ps[key] = (ps[key] || 0).to_i + delta
            end
          end

          ps.save!
        end

        entry
      end
    end
  end
end
