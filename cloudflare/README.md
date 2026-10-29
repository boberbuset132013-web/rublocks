# RUblocks Cloudflare API

This is the server source for the RUblocks desktop client. It is separate from the Godot client.

## Bindings

Create a D1 database named rublocks-db and run schema.sql in its SQL console. In Worker settings configure a D1 binding named DB and a Durable Objects binding named ROOMS with class GameRoom.

The wrangler.toml file includes a placeholder database ID. Replace it before deploying with Wrangler. Do not commit passwords or API tokens.

## Routes

- GET /api/health — API and binding health.
- POST /api/register — register username and password.
- POST /api/login — create a login session.
- GET /api/me — return current account.
- GET /api/places — list public places.
- POST /api/places — create a private place.
- PUT /api/places/:id — publish or update an owned place.
- GET /api/rooms/:id/ws — WebSocket room for chat/events.

Before public launch, add rate limiting, account recovery, moderation controls, and server-side room rules. The current runtime sends a place-update notice to room sockets; it does not force-close every client by itself.
