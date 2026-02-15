# GetCourt

## Status

![CI](https://github.com/denis1011101/getcourt/actions/workflows/ci.yml/badge.svg?branch=main)
![Ruby](https://img.shields.io/badge/ruby-3.4-red)
![Rails](https://img.shields.io/badge/rails-8.1-red)

Website: https://getcourt.co/

GetCourt is a simple app to bring together the community of people who play tennis.  
Create and join court games, manage courts, invite players, and receive Telegram reminders and notifications.

Main features
- Create and manage recurring or one-off games
- Discover and open new local courts
- Collect match statistics and calculate overall player ratings
- Search for coaches and launch urgent player searches
- Find suitable opponents with AI-based matching
- Telegram bot integration for notifications and registration tokens
- Mobile-friendly UI with map integration and simple search

Main technologies
- Ruby 3.4 / Ruby on Rails 8.0
- Hotwire (Turbo + Stimulus) for interactivity
- Tailwind CSS for styling
- SQLite for development and production
- Background jobs for notifications (ActiveJob / queue adapter)
- Google / Nominatim geocoding for addresses

## Tests and coverage

```bash
bundle exec rails test
```

Coverage is generated during Minitest runs and saved to `coverage/summary.txt`.

## License

This project is licensed under the **Apache License 2.0**.  
See the [LICENSE](LICENSE) file for details.

**Note on Trademarks:**  
The "GetCourt" name, logo, and associated branding are trademarks of the project author. 
While the code is open source, this license **does not** grant permission to use these trademarks 
to endorse or promote products derived from this software without prior written permission.
