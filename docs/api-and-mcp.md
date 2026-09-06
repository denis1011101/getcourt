# Public API and MCP server

GetCourt exposes upcoming games twice: as a plain JSON API for any client, and as an
[MCP](https://modelcontextprotocol.io) server so an assistant can search for games itself
instead of reading pages. Both are read-only and return exactly what a game page already
shows in public — never anything about participants.

Games on courts that are still waiting for moderation are excluded from both.

## JSON API

Public, no key and no session.

```
GET /api/v1/games
GET /api/v1/games/:id
```

| Parameter | Meaning |
| --- | --- |
| `city` | City name as stored on the court, e.g. `Belgrade`. Repeatable (`city[]=A&city[]=B`). |
| `sport` | Sport name, e.g. `Tennis`, `Padel`, `Squash`. |
| `skill_level` | Skill level, e.g. `Beginner`. |
| `with_spots` | `true` — only games that still have a free spot. |
| `urgent` | `true` — only games with an urgent player search. |
| `from`, `to` | Date bounds, ISO 8601 (`YYYY-MM-DD`). |
| `upcoming` | `false` — include games already played. Upcoming only by default. |
| `limit` | 1–100, 25 by default (`Games::Search::DEFAULT_LIMIT` / `MAX_LIMIT`). |

Recurring games always pass the date filters: their next occurrence is computed on the fly
rather than stored in a column.

```bash
curl "https://getcourt.co/api/v1/games?city=Belgrade&sport=Tennis&with_spots=true&limit=2"
```

```json
{
  "games": [
    {
      "id": 1042,
      "date": "2026-09-12",
      "time": "19:00",
      "duration_minutes": 90,
      "recurring": false,
      "sport": "Tennis",
      "skill_level": "Intermediate",
      "surface": "Hard",
      "environment": "outdoor",
      "kind": "game",
      "with_coach": false,
      "urgent_player_search": true,
      "comment": "Doubles, bring a spare ball",
      "players": { "taken": 3, "total": 4, "spots_left": 1 },
      "court": {
        "id": 17,
        "name": "Tennis Club Ada",
        "city": "Belgrade",
        "country_code": "RS",
        "latitude": 44.79,
        "longitude": 20.41,
        "indoor": false,
        "outdoor": true,
        "free": false,
        "url": "https://getcourt.co/courts/17"
      },
      "url": "https://getcourt.co/games/1042"
    }
  ]
}
```

A missing game answers `404` with `{"error":"not_found"}`.

## MCP server

```
POST /mcp
Content-Type: application/json
Authorization: Bearer <token>
```

Streamable HTTP: the client posts a JSON-RPC 2.0 message (or a batch — an array) and gets
JSON back. A batch of nothing but notifications answers `202` with an empty body, per spec.

- Protocol versions: `2025-06-18` (default), `2025-03-26`, `2024-11-05`.
- Methods: `initialize`, `ping`, `tools/list`, `tools/call`.
- Capabilities: `tools` only, `listChanged: false`.

### Authorisation

Two kinds of token are accepted:

- **personal**, from the `api_tokens` table — a signed-in user issues one in
  *Account → Security*, once their email is verified or Telegram is linked;
- **shared**, from the `MCP_TOKEN` environment variable — for our own scripts.

Until at least one of them exists, every request answers `404`: a forgotten environment
variable must not silently open the endpoint. A missing or wrong `Authorization` header
answers `401`.

The tools only read public data, but the endpoint stays closed so it is not called at random.

### Issuing a token

| Route | What it does |
| --- | --- |
| `POST /account/api_token` | Issues a token, revoking the caller's previous one. `.json` returns `{ token, expires_at, last_used_at, endpoint }`. |
| `GET /account/api_token.json` | The caller's active token, or `404` if there is none. |
| `DELETE /account/api_token` | Revokes it. |

All three run inside the normal session — they are the account page's own buttons, so a
script cannot call them with the MCP token alone. That is deliberate: a credential that
mints credentials is the thing worth protecting, and here the only proof of identity we
have is the account itself.

Unverified accounts are turned away with `403 verification_required`: without a verified
email or a linked Telegram there is nobody to revoke a token from — a fresh account takes a
minute to make.

### Expiry

A token lasts **six months from its last request**, not from the day it was issued
(`ApiToken::LIFETIME`). Every authenticated call pushes the date out, at most once a day
(`REFRESH_AFTER`), so a token that is in use never expires, while an abandoned one dies on
its own six months later.

The sliding window is the point: the token lives in an MCP client's config file, where no
refresh flow exists. A fixed deadline would eventually break a working integration with a
`401` that nobody sees.

One active token per user. Issuing a new one revokes the old, and `revoked_at` takes a
token out immediately.

### Tools

| Tool | Arguments |
| --- | --- |
| `search_games` | `city`, `sport`, `skill_level`, `with_spots`, `urgent`, `from`, `to`, `limit` — the JSON API filters, always restricted to upcoming games. |
| `get_game` | `id` (required, integer). |

Both answer with a single text content block holding the same JSON the API returns —
text is understood by every client, `structuredContent` is not.

Write tools (create a game, join one) are deliberately absent: they immediately raise the
question of acting on behalf of a user, and the token here is shared by everyone.

### Client configuration

```json
{
  "mcpServers": {
    "getcourt": {
      "type": "http",
      "url": "https://getcourt.co/mcp",
      "headers": { "Authorization": "Bearer YOUR_TOKEN" }
    }
  }
}
```

Or by hand:

```bash
curl -X POST https://getcourt.co/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"search_games","arguments":{"city":"Belgrade","with_spots":true}}}'
```

## Rate limits

Rack::Attack, per IP (`config/initializers/rack_attack.rb`):

- `/api/**` — 60 requests per minute;
- `/mcp` — 120 requests per minute, because one question from an MCP client costs several calls.

## Environment

| Variable | Purpose |
| --- | --- |
| `MCP_TOKEN` | Shared bearer token for `/mcp`, for our own scripts. Unset and no personal tokens issued → the endpoint is off and answers `404`. |
| `APP_HOST` | Host used to build the `url` fields, `https://getcourt.co` by default. |

## Where the code lives

- `app/controllers/api/v1/games_controller.rb` — the JSON endpoints
- `app/controllers/mcp_controller.rb` — transport and authorisation for `/mcp`
- `app/models/api_token.rb` — personal tokens, the sliding expiry and revocation
- `app/controllers/api_tokens_controller.rb` — issuing and revoking from the account page
- `app/services/mcp/server.rb` — the JSON-RPC layer and the tool definitions
- `app/services/games/search.rb` — filters shared with the games page, so site and API cannot drift
- `app/services/games/serializer.rb` — the public shape of a game
- `app/views/pages/api_and_mcp.html.erb` — the same documentation for users, at `/api-and-mcp`

Adding or renaming a tool means touching `Mcp::Server::TOOLS`, the page and this file together.
