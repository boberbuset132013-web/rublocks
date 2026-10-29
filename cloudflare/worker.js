const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,PUT,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
  "Content-Type": "application/json; charset=utf-8"
};

const reply = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: CORS });
const fail = (error, status = 400) => reply({ ok: false, error }, status);
const now = () => Math.floor(Date.now() / 1000);
const bytesHex = (length = 24) => Array.from(crypto.getRandomValues(new Uint8Array(length)), b => b.toString(16).padStart(2, "0")).join("");

async function digest(value) {
  const raw = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(raw), b => b.toString(16).padStart(2, "0")).join("");
}

async function passwordHash(password, salt) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: new TextEncoder().encode(salt), iterations: 120000 }, key, 256);
  return Array.from(new Uint8Array(bits), b => b.toString(16).padStart(2, "0")).join("");
}

async function currentUser(request, env) {
  const token = (request.headers.get("Authorization") || "").match(/^Bearer ([a-f0-9]{48,128})$/i)?.[1];
  if (!token) return null;
  return await env.DB.prepare("SELECT users.id, users.username FROM sessions JOIN users ON users.id = sessions.user_id WHERE sessions.token_hash = ? AND sessions.expires_at > ?")
    .bind(await digest(token), now()).first();
}

async function newSession(env, userId) {
  const token = bytesHex(32);
  await env.DB.prepare("INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)")
    .bind(await digest(token), userId, now() + 60 * 60 * 24 * 30).run();
  return token;
}

async function handler(request, env) {
  const url = new URL(request.url);
  const path = url.pathname;
  const method = request.method;

  if (method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (path === "/" || path === "/api/health") {
    return reply({ ok: true, name: "RUblocks API", apiVersion: "1.0.0", databaseConfigured: Boolean(env.DB), multiplayerConfigured: Boolean(env.ROOMS) });
  }
  if (!env.DB) return fail("D1 binding DB is not configured.", 503);

  if (path === "/api/register" && method === "POST") {
    let body;
    try { body = await request.json(); } catch { return fail("Invalid JSON."); }
    const username = body?.username;
    const password = body?.password;
    if (typeof username !== "string" || !/^[a-zA-Z0-9_]{3,20}$/.test(username)) return fail("Username must be 3-20 letters, numbers or underscores.");
    if (typeof password !== "string" || password.length < 8 || password.length > 128) return fail("Password must contain 8-128 characters.");
    const exists = await env.DB.prepare("SELECT id FROM users WHERE username = ?").bind(username).first();
    if (exists) return fail("Username is already taken.", 409);
    const id = crypto.randomUUID();
    const salt = bytesHex(16);
    await env.DB.prepare("INSERT INTO users (id, username, password_salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?)")
      .bind(id, username, salt, await passwordHash(password, salt), now()).run();
    const token = await newSession(env, id);
    return reply({ ok: true, user: { id, username }, token }, 201);
  }

  if (path === "/api/login" && method === "POST") {
    let body;
    try { body = await request.json(); } catch { return fail("Invalid JSON."); }
    if (typeof body?.username !== "string" || typeof body?.password !== "string") return fail("Enter username and password.");
    const user = await env.DB.prepare("SELECT id, username, password_salt, password_hash FROM users WHERE username = ?").bind(body.username).first();
    if (!user || await passwordHash(body.password, user.password_salt) !== user.password_hash) return fail("Incorrect username or password.", 401);
    const token = await newSession(env, user.id);
    return reply({ ok: true, user: { id: user.id, username: user.username }, token });
  }

  if (path === "/api/me" && method === "GET") {
    const user = await currentUser(request, env);
    return user ? reply({ ok: true, user }) : fail("Login required.", 401);
  }

  if (path === "/api/places" && method === "GET") {
    const result = await env.DB.prepare("SELECT id, title, description, owner_username, published, created_at, updated_at FROM places WHERE published = 1 ORDER BY updated_at DESC LIMIT 100").all();
    return reply({ ok: true, places: result.results || [] });
  }

  if (path === "/api/places" && method === "POST") {
    const user = await currentUser(request, env);
    if (!user) return fail("Login required.", 401);
    let body;
    try { body = await request.json(); } catch { return fail("Invalid JSON."); }
    if (typeof body?.title !== "string" || body.title.trim().length < 1 || body.title.length > 80) return fail("Title must be 1-80 characters.");
    const description = body.description ?? "";
    if (typeof description !== "string" || description.length > 2000) return fail("Description is too long.");
    const project = JSON.stringify(body.project ?? {});
    if (project.length > 200000) return fail("Project data exceeds 200 KB.");
    const id = crypto.randomUUID();
    await env.DB.prepare("INSERT INTO places (id, owner_id, owner_username, title, description, project_json, published, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)")
      .bind(id, user.id, user.username, body.title.trim(), description, project, now(), now()).run();
    return reply({ ok: true, place: { id, title: body.title.trim(), published: false, version: 1 } }, 201);
  }

  const placeMatch = path.match(/^\/api\/places\/([a-f0-9-]+)$/i);
  if (placeMatch && method === "GET") {
    const place = await env.DB.prepare("SELECT id, owner_id, owner_username, title, description, project_json, published, updated_at FROM places WHERE id = ?")
      .bind(placeMatch[1]).first();
    if (!place) return fail("Place not found.", 404);
    if (!place.published) {
      const user = await currentUser(request, env);
      if (!user || user.id !== place.owner_id) return fail("This place is private.", 403);
    }
    let project = {};
    try { project = JSON.parse(place.project_json || "{}"); } catch { return fail("Stored project data is invalid.", 500); }
    return reply({ ok: true, place: {
      id: place.id,
      title: place.title,
      description: place.description,
      owner_username: place.owner_username,
      published: Boolean(place.published),
      version: Number(place.updated_at),
      project
    } });
  }

  if (placeMatch && method === "PUT") {
    const user = await currentUser(request, env);
    if (!user) return fail("Login required.", 401);
    let body;
    try { body = await request.json(); } catch { return fail("Invalid JSON."); }
    const existing = await env.DB.prepare("SELECT id, owner_id, updated_at FROM places WHERE id = ?").bind(placeMatch[1]).first();
    if (!existing) return fail("Place not found.", 404);
    if (existing.owner_id !== user.id) return fail("Not your place.", 403);
    const updates = [];
    const values = [];
    if (body.title !== undefined) {
      if (typeof body.title !== "string" || body.title.trim().length < 1 || body.title.length > 80) return fail("Invalid title.");
      updates.push("title = ?"); values.push(body.title.trim());
    }
    if (body.description !== undefined) {
      if (typeof body.description !== "string" || body.description.length > 2000) return fail("Invalid description.");
      updates.push("description = ?"); values.push(body.description);
    }
    if (body.project !== undefined) {
      const project = JSON.stringify(body.project);
      if (project.length > 200000) return fail("Project data exceeds 200 KB.");
      updates.push("project_json = ?"); values.push(project);
    }
    if (body.published !== undefined) {
      if (typeof body.published !== "boolean") return fail("published must be boolean.");
      updates.push("published = ?"); values.push(body.published ? 1 : 0);
    }
    if (!updates.length) return fail("No changes provided.");
    updates.push("updated_at = ?");
    values.push(now(), existing.id);
    await env.DB.prepare("UPDATE places SET " + updates.join(", ") + " WHERE id = ?").bind(...values).run();
    const nextVersion = now();
    if (env.ROOMS) {
      const room = env.ROOMS.get(env.ROOMS.idFromName(existing.id));
      await room.fetch("https://room.internal/broadcast", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type: "place_updated", version: nextVersion, message: "Плейс обновлён. Переподключитесь к новой версии." })
      });
    }
    return reply({ ok: true, id: existing.id, version: nextVersion, playersNotified: Boolean(env.ROOMS) });
  }

  const roomMatch = path.match(/^\/api\/rooms\/([a-zA-Z0-9_-]{1,80})\/ws$/);
  if (roomMatch && method === "GET") {
    if (!env.ROOMS) return fail("Durable Objects binding ROOMS is not configured.", 503);
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return fail("WebSocket upgrade required.", 426);
    const user = await currentUser(request, env);
    if (!user) return fail("Login required.", 401);
    const room = env.ROOMS.get(env.ROOMS.idFromName(roomMatch[1]));
    const headers = new Headers(request.headers);
    headers.set("X-RUblocks-User-Id", user.id);
    headers.set("X-RUblocks-Username", user.username);
    return room.fetch(new Request(request, { headers }));
  }
  return fail("Route not found.", 404);
}

export default {
  async fetch(request, env) {
    try { return await handler(request, env); }
    catch (error) {
      console.error("RUblocks API error", error?.stack || error);
      return fail("Internal server error.", 500);
    }
  }
};

export class GameRoom {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/broadcast" && request.method === "POST") {
      let data;
      try { data = await request.json(); } catch { return new Response("Bad JSON", { status: 400 }); }
      this.broadcast(data);
      return new Response("ok");
    }
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return new Response("WebSocket required", { status: 426 });
    const userId = request.headers.get("X-RUblocks-User-Id");
    const username = request.headers.get("X-RUblocks-Username");
    if (!userId || !username) return new Response("Unauthorized", { status: 401 });
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    const existingPlayers = this.ctx.getWebSockets()
      .map(socket => socket.deserializeAttachment() || {})
      .filter(player => player.userId && player.username);
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ userId, username });
    server.send(JSON.stringify({ type: "connected", userId, username, players: existingPlayers }));
    this.broadcast({ type: "player_joined", userId, username }, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  broadcast(data, except = null) {
    const message = JSON.stringify(data);
    for (const socket of this.ctx.getWebSockets()) {
      if (socket === except) continue;
      try { socket.send(message); } catch {}
    }
  }

  async webSocketMessage(socket, message) {
    if (typeof message !== "string" || message.length > 16000) {
      socket.close(1009, "Message too large");
      return;
    }
    let data;
    try { data = JSON.parse(message); } catch {
      socket.send(JSON.stringify({ type: "error", error: "Invalid JSON" }));
      return;
    }
    const user = socket.deserializeAttachment() || {};
    if (data.type === "chat") {
      if (typeof data.text !== "string" || !data.text.trim() || data.text.length > 300) {
        socket.send(JSON.stringify({ type: "error", error: "Invalid chat message" }));
        return;
      }
      this.broadcast({ type: "chat", userId: user.userId, username: user.username, text: data.text.trim(), time: Date.now() });
      return;
    }
    if (data.type === "move") {
      const p = data.position;
      if (!p || !["x", "y", "z"].every(key => Number.isFinite(p[key]) && Math.abs(p[key]) <= 100000)) {
        socket.send(JSON.stringify({ type: "error", error: "Invalid position" }));
        return;
      }
    }
    if (["move", "action"].includes(data.type)) {
      this.broadcast({ ...data, userId: user.userId, username: user.username, time: Date.now() }, socket);
      return;
    }
    socket.send(JSON.stringify({ type: "error", error: "Unknown message type" }));
  }

  async webSocketClose(socket) {
    const user = socket.deserializeAttachment() || {};
    this.broadcast({ type: "player_left", userId: user.userId, username: user.username });
  }

  async webSocketError(socket) {
    try { socket.close(1011, "Socket error"); } catch {}
  }
}
