# MCP Server Setup for Claude Code

This guide explains how to connect Claude Code (on your laptop/desktop) to the notify-bot MCP server running on your home server via Tailscale.

## Architecture

```
┌─────────────────┐         Tailscale VPN         ┌──────────────────┐
│  Claude Code    │◄──────────────────────────────►│  Home Server     │
│  (your laptop)  │  HTTP + Bearer Token Auth      │  (notify-bot)    │
└─────────────────┘                                └──────────────────┘
```

## Prerequisites

1. **Home Server Setup** (completed on 2026-09-21):
   - `notify-bot` running on home server (via systemd or Docker)
   - Tailscale installed and authenticated
   - `MCP_AUTH_TOKEN` set in `.env`

2. **Your Machine** (laptop/desktop):
   - Tailscale client installed and authenticated
   - Claude Code CLI installed
   - `.claude/projects/<path>/mcp_settings.json` configured

## Step 1: Get Home Server Tailscale IP

On your home server, run:

```bash
sudo tailscale ip -4
```

This returns something like: `100.64.x.x`

Keep this for the next step.

## Step 2: Configure Claude Code MCP Settings

Edit (or create) `.claude/projects/<your-project-path>/mcp_settings.json`:

```json
{
  "mcpServers": {
    "notify-bot": {
      "command": "curl",
      "args": [
        "-X", "POST",
        "http://100.64.x.x:5000/tools/send_telegram_message",
        "-H", "Authorization: Bearer YOUR_MCP_AUTH_TOKEN",
        "-H", "Content-Type: application/json",
        "-d", "@-"
      ],
      "env": {
        "MCP_SERVER_URL": "http://100.64.x.x:5000",
        "MCP_AUTH_TOKEN": "YOUR_MCP_AUTH_TOKEN"
      }
    }
  }
}
```

**Replace:**
- `100.64.x.x` with your home server's Tailscale IP (from Step 1)
- `YOUR_MCP_AUTH_TOKEN` with the token from home server `.env` (`MCP_AUTH_TOKEN=...`)

## Step 3: Test Connection

Verify Tailscale connectivity:

```bash
# Ping home server Tailscale IP
ping 100.64.x.x

# Or directly test the MCP server
curl -X GET http://100.64.x.x:5000/health \
  -H "Authorization: Bearer YOUR_MCP_AUTH_TOKEN"
```

You should get:
```json
{"status": "ok"}
```

## Step 4: Use in Claude Code

Once configured, Claude Code will expose a tool `send_telegram_message` in your MCP context.

**Example usage in a Claude Code session:**

```bash
# Claude Code will see the MCP server and its tools
/mcp list

# You can now use the tool in conversations
```

## Configuration Options

### Option A: Direct HTTP (Recommended for Home Network)

Simplest: just HTTP over Tailscale (already encrypted).

```json
{
  "mcpServers": {
    "notify-bot": {
      "url": "http://100.64.x.x:5000",
      "auth": "Bearer YOUR_MCP_AUTH_TOKEN"
    }
  }
}
```

### Option B: Unix Socket (If Home Server Runs Locally)

For local-only connections (no Tailscale):

```json
{
  "mcpServers": {
    "notify-bot": {
      "socket": "/var/run/notify-bot/mcp.sock"
    }
  }
}
```

*Requires systemd service to expose socket.*

### Option C: Environment Variable Only

Store token in your shell profile:

```bash
export NOTIFY_BOT_URL="http://100.64.x.x:5000"
export NOTIFY_BOT_TOKEN="YOUR_MCP_AUTH_TOKEN"
```

Then in `mcp_settings.json`:

```json
{
  "mcpServers": {
    "notify-bot": {
      "url": "${NOTIFY_BOT_URL}",
      "auth": "Bearer ${NOTIFY_BOT_TOKEN}"
    }
  }
}
```

## Troubleshooting

### Connection Refused

1. Verify Tailscale is running on both machines:
   ```bash
   tailscale status
   ```

2. Check firewall on home server:
   ```bash
   sudo ufw status
   ```
   If enabled, allow the MCP port:
   ```bash
   sudo ufw allow 5000/tcp
   ```

### Authentication Failed

1. Double-check `MCP_AUTH_TOKEN` matches in both places
2. Verify token format (no extra spaces):
   ```bash
   grep MCP_AUTH_TOKEN /opt/notify-bot/.env
   ```

### Service Not Running

On home server:
```bash
systemctl status notify-bot.service
journalctl -u notify-bot -f
```

### Slow Responses

Check latency to home server:
```bash
ping 100.64.x.x
```

If Tailscale relay is used (high latency), you can improve by:
- Ensuring both devices have direct Tailscale routes
- Running Tailscale in derp-mode=false (if safe for your network)

## Security Notes

1. **Token Rotation**: Change `MCP_AUTH_TOKEN` periodically
2. **Tailscale Private**: Only accessible within your Tailscale network
3. **No Public Exposure**: Home server listens on `127.0.0.1:5000` (internal only)
4. **Rate Limit & Dedup**: All guardrails enforced server-side

## Example: Sending a Message from Claude Code

Once the MCP server is connected, you can use it like:

```bash
# In a Claude Code session, ask Claude to send a notification
"Send me a Telegram reminder: 'Server backup complete'"
```

Claude Code will:
1. Call the MCP server
2. Authenticate with the Bearer token
3. Send the message through Telegram
4. Respect all guardrails (rate limit, dedup, DRY_RUN mode)

## Advanced: Custom MCP Transport

If you want to use a custom transport (e.g., gRPC, Unix socket), see:
- [MCP Protocol Spec](https://spec.modelcontextprotocol.org/)
- `mcp_server.py` source for HTTP/SSE implementation

## Support

For issues or questions:
1. Check logs: `journalctl -u notify-bot -f`
2. Test connectivity: `curl http://100.64.x.x:5000/health`
3. Review `.env` configuration on home server
