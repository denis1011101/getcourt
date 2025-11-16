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

courts = Court.create([
  { name: 'Central Park Court', coordinates: '40.785091,-73.968285' },
  { name: 'Brooklyn Bridge Park Court', coordinates: '40.703277,-73.996285' },
  { name: 'Prospect Park Court', coordinates: '40.661291,-73.969510' },
  { name: 'Riverside Park Court', coordinates: '40.800676,-73.970833' },
  { name: 'гринвич академ', coordinates: '56.776735, 60.522912' }
])

Game.create!([
  { date: '2023-10-15', time: '10:00', court_id: courts[0].id, user_id: users[0].id },
  { date: '2023-10-16', time: '14:00', court_id: courts[1].id, user_id: users[1].id },
  { date: '2023-10-17', time: '16:00', court_id: courts[2].id, user_id: users[0].id }
])
