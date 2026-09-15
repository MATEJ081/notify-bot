# notify-bot: Telegram Notifications with Guardrails

Send messages to a Telegram chat with built-in rate limiting, deduplication, and dry-run mode.

## Features

- **Rate limiting**: Max 5 messages/minute (configurable)
- **Deduplication**: Ignores duplicate messages within 5-min window (configurable)
- **Dry-run mode** (default): No real Telegram API calls until explicitly enabled
- **Secure logging**: Never logs tokens, chat IDs, or full message text
- **Two modes**: CLI script (`notify.py`) + MCP server (`mcp_server.py`)

## Setup

### 1. Prerequisites

- Python 3.8+
- Telegram bot token (create via [@BotFather](https://t.me/botfather))
- Telegram chat ID (destination for messages)

### 2. Configuration

```bash
# Copy the example file
cp .env.example .env

# Edit .env and set:
# BOT_TOKEN=your_token
# TELEGRAM_CHAT_ID=your_chat_id
# DRY_RUN=true (default; change to false to actually send)

# Lock permissions (important!)
chmod 600 .env
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

## Usage

### CLI Mode

Send a message from the command line:

```bash
python3 notify.py "Hello from notify-bot!"
```

Check logs:

```bash
tail -f logs/notify.log
```

### MCP Server Mode

Start the HTTP/SSE server:

```bash
python3 mcp_server.py
```

Server listens on `http://127.0.0.1:5000` (configurable via `.env`).

#### Endpoints

- **GET `/health`** — Health check (no auth required)
- **GET `/tools`** — List available tools (requires Bearer token)
- **POST `/tools/send_telegram_message`** — Send message (requires Bearer token)
- **POST `/sse`** — SSE stream endpoint for MCP transport

#### Example Request

```bash
# Set auth token in .env first: MCP_AUTH_TOKEN=your_secret

curl -X POST http://127.0.0.1:5000/tools/send_telegram_message \
  -H "Authorization: Bearer your_secret" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello from MCP!"}'
```

## Security Notes

1. **DRY_RUN=true by default** — Prevents accidental live sends
2. **Fixed chat ID** — Messages can only go to one configured recipient
3. **No incoming messages** — Server never polls or receives; only sends
4. **.env not in git** — Credentials are protected by `.gitignore`
5. **Rate limit & dedup** — Both server-side, cannot be bypassed

## State File

The server persists state in `state/state.json` (permissions: 0o600):

```json
{
  "sent_timestamps": [timestamp, timestamp, ...],
  "last_message": {"hash": "sha256(message)", "ts": timestamp}
}
```

This enables rate limiting and deduplication across restarts.

## Deployment

### Docker

```bash
docker build -t notify-bot .
docker run -d --env-file .env -p 5000:5000 notify-bot python3 mcp_server.py
```

### Systemd

```ini
[Unit]
Description=notify-bot MCP Server
After=network.target

[Service]
Type=simple
User=notifybot
WorkingDirectory=/opt/notify-bot
Environment="PATH=/opt/notify-bot/venv/bin"
ExecStart=/opt/notify-bot/venv/bin/python3 mcp_server.py
Restart=on-failure
EnvironmentFile=/opt/notify-bot/.env

[Install]
WantedBy=multi-user.target
```

### Tailscale (Home Server)

1. Join home server to Tailscale
2. Point `MCP_HOST=127.0.0.1` (loopback; accessible only via Tailscale)
3. Set `MCP_AUTH_TOKEN` to a strong secret
4. Claude Code connects via Tailscale IP (e.g., `http://100.x.x.x:5000`)

## Logs

- CLI: `logs/notify.log`
- MCP Server: `logs/mcp_server.log`

Example log line:
```
2026-09-15 10:30:45,123 INFO event=send outcome=ok
```

No tokens, chat IDs, or message text are ever logged.

## License

MIT
