class City < ApplicationRecord
  scope :by_name, ->(q) { where("lower(name) LIKE ?", "%#{q.to_s.downcase}%") }
end
