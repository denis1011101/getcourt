require_relative "seeds/famous_courts"

users = [
  { email: 'test@test.tt', name: 'Test', admin: true },
  { email: 'test@test1.tt', name: 'Test1', admin: false }
]
users.map! do |attrs|
  u = User.find_or_initialize_by(email: attrs[:email])
  u.assign_attributes(attrs)
  u.save!
  u
end

