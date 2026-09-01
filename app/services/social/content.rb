module Social
  module Content
    KINDS = SocialPost::KINDS

    # Джоба получает ключи, а не объект, поэтому контент пересобирается здесь.
    # nil означает «материал исчез» — игру удалили, срочный поиск выключили.
    def self.build(kind, dedup_key)
      case kind.to_s
      when "welcome" then Welcome.new
      when "urgent" then UrgentSearch.from_key(dedup_key)
      when "daily" then Daily.from_key(dedup_key)
      end
    end
  end
end
