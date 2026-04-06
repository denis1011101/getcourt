require_relative "seeds/famous_courts"

users = [
  {
    email: "test@test.tt",
    name: "Feature Player",
    admin: true,
    city_name: "London",
    preferred_sports: [ "tennis" ],
    telegram_chat_id: "700001",
    telegram_username: "feature_player"
  },
  {
    email: "test@test1.tt",
    name: "Feature Host",
    admin: false,
    city_name: "Paris",
    preferred_sports: [ "tennis" ],
    telegram_chat_id: "700002",
    telegram_username: "feature_host"
  },
  {
    email: "coach.overlap@getcourt.test",
    name: "Coach Overlap",
    coach: true,
    city_name: "London",
    about_me: "Prefers central London courts and evening sessions.",
    preferred_sports: [ "tennis" ],
    telegram_chat_id: "700003",
    telegram_username: "coach_overlap"
  },
  {
    email: "coach.note@getcourt.test",
    name: "Coach Note",
    coach: true,
    city_name: "Dubai",
    about_me: "Happy to travel for private sessions.",
    preferred_sports: [ "tennis" ],
    court_preferences_note: "Indoor courts preferred, especially with parking and good lighting.",
    telegram_chat_id: "700004",
    telegram_username: "coach_note"
  }
]
users.map! do |attrs|
  u = User.find_or_initialize_by(email: attrs[:email])
  u.assign_attributes(attrs)
  u.save!
  u
end

users_by_email = users.index_by(&:email)

courts_by_name = Court.where(
  name: [
    "Centre Court – All England Club",
    "Court No. 1 – All England Club",
    "Court Philippe Chatrier – Roland Garros"
  ]
).index_by(&:name)

player = users_by_email.fetch("test@test.tt")
host = users_by_email.fetch("test@test1.tt")
coach_overlap = users_by_email.fetch("coach.overlap@getcourt.test")
coach_note = users_by_email.fetch("coach.note@getcourt.test")

player.update!(
  court_preferences_note: nil,
  favorite_court_ids: [
    courts_by_name.fetch("Centre Court – All England Club").id,
    courts_by_name.fetch("Court No. 1 – All England Club").id
  ]
)

coach_overlap.update!(
  court_preferences_note: nil,
  favorite_court_ids: [
    courts_by_name.fetch("Centre Court – All England Club").id
  ]
)

coach_note.update!(favorite_court_ids: [])

[
  {
    name: "Urgent favorite-court game",
    court: courts_by_name.fetch("Centre Court – All England Club"),
    date: Date.current + 3.days,
    time: "19:00"
  },
  {
    name: "Urgent other-court game",
    court: courts_by_name.fetch("Court Philippe Chatrier – Roland Garros"),
    date: Date.current + 1.day,
    time: "18:00"
  }
].each do |attrs|
  game = Game.find_or_initialize_by(
    user: host,
    court: attrs[:court],
    date: attrs[:date]
  )
  game.assign_attributes(
    time: attrs[:time],
    sport: "tennis",
    players_count: 4,
    urgent_player_search: true,
    recurring: false
  )
  game.save!
end

puts "Feature demo data ready:"
puts "- player: #{player.email} (favorite courts mode)"
puts "- coach: #{coach_overlap.email} (overlapping favorite court)"
puts "- coach: #{coach_note.email} (court note mode)"
puts "- urgent games host: #{host.email}"
