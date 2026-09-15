#!/usr/bin/env python3
"""MCP Server for Telegram notifications via HTTP/SSE.

Exposes tool: send_telegram_message
Transport: HTTP POST + Server-Sent Events (SSE)
Auth: Bearer token from Authorization header
Security: rate limit, dedup, DRY_RUN guardrails all server-side
"""

import json
import logging
import os
import sys
from pathlib import Path
from typing import Optional

try:
    from flask import Flask, request, Response
except ImportError:
    print("Error: Flask is required. Install with: pip install flask", file=sys.stderr)
    sys.exit(1)

from telegram_notifier import TelegramNotifier

BASE_DIR = Path(__file__).resolve().parent
STATE_FILE = BASE_DIR / "state" / "state.json"
LOG_DIR = BASE_DIR / "logs"
ENV_FILE = BASE_DIR / ".env"


def load_env_file(path: Path) -> None:
    """Load .env variables without overwriting existing exports."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if key and key not in os.environ:
            os.environ[key] = value


def setup_logging() -> logging.Logger:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("mcp-telegram")
    logger.setLevel(logging.INFO)
    handler = logging.FileHandler(LOG_DIR / "mcp_server.log")
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    )
    logger.addHandler(handler)
    logger.addHandler(logging.StreamHandler(sys.stdout))
    return logger


def create_app(logger: logging.Logger, notifier: TelegramNotifier) -> Flask:
    """Create Flask app for MCP server."""
    app = Flask(__name__)

    # Expected token from env
    mcp_token = os.environ.get("MCP_AUTH_TOKEN", "")
    if not mcp_token:
        logger.warning("MCP_AUTH_TOKEN not set; server is unauthenticated")

    def check_auth() -> Optional[str]:
        """Check Authorization header. Returns error message if invalid, None if OK."""
        if not mcp_token:
            return None  # No auth required if token not configured

        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return "Missing or invalid Authorization header"

        token = auth_header[7:]
        if token != mcp_token:
            return "Invalid token"

        return None

    @app.route("/health", methods=["GET"])
    def health() -> dict:
        """Health check endpoint (no auth required)."""
        return {"status": "ok"}, 200

    @app.route("/tools", methods=["GET"])
    def list_tools():
        """List available tools (MCP protocol)."""
        auth_err = check_auth()
        if auth_err:
            return {"error": auth_err}, 401

        return {
            "tools": [
                {
                    "name": "send_telegram_message",
                    "description": "Send a message to Telegram (with rate limit, dedup, DRY_RUN guardrails)",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "message": {
                                "type": "string",
                                "description": "The message text to send",
                            }
                        },
                        "required": ["message"],
                    },
                }
            ]
        }, 200

    @app.route("/tools/send_telegram_message", methods=["POST"])
    def send_message():
        """Send a Telegram message. Supports SSE streaming for MCP."""
        auth_err = check_auth()
        if auth_err:
            return {"error": auth_err}, 401

        data = request.get_json() or {}
        message = data.get("message", "").strip()

        if not message:
            return {"error": "message is required"}, 400

        logger.info("event=send_request message_length=%d", len(message))

        try:
            sent = notifier.send(message)
            result = {
                "sent": sent,
                "dry_run": notifier.dry_run,
                "message": "[dry-run] Message simulated" if notifier.dry_run else "Message sent",
            }
            return result, 200
        except Exception as exc:
            logger.error("event=send_error type=%s", type(exc).__name__)
            return {"error": f"Failed to send: {type(exc).__name__}"}, 500

    @app.route("/sse", methods=["POST"])
    def sse_handler():
        """SSE endpoint for MCP (Server-Sent Events transport)."""
        auth_err = check_auth()
        if auth_err:
            return {"error": auth_err}, 401

        data = request.get_json() or {}
        tool_name = data.get("tool", "")
        tool_input = data.get("input", {})

        if tool_name == "send_telegram_message":
            message = tool_input.get("message", "").strip()
            if not message:
                yield "data: " + json.dumps({"error": "message is required"}) + "\n\n"
                return

            try:
                sent = notifier.send(message)
                result = {
                    "status": "ok",
                    "sent": sent,
                    "dry_run": notifier.dry_run,
                }
                yield "data: " + json.dumps(result) + "\n\n"
            except Exception as exc:
                error = {"status": "error", "type": type(exc).__name__}
                yield "data: " + json.dumps(error) + "\n\n"
        else:
            yield "data: " + json.dumps({"error": f"Unknown tool: {tool_name}"}) + "\n\n"

    return app


def main():
    load_env_file(ENV_FILE)
    logger = setup_logging()

    bot_token = os.environ.get("BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "")
    dry_run = os.environ.get("DRY_RUN", "true").strip().lower() != "false"
    rate_limit = int(os.environ.get("RATE_LIMIT_PER_MINUTE", "5"))
    dedup_window = int(os.environ.get("DEDUP_WINDOW_SECONDS", "300"))
    mcp_host = os.environ.get("MCP_HOST", "127.0.0.1")
    mcp_port = int(os.environ.get("MCP_PORT", "5000"))

    if not bot_token or not chat_id:
        logger.error("event=startup outcome=failed reason=missing_config")
        print("Error: BOT_TOKEN or TELEGRAM_CHAT_ID missing in .env", file=sys.stderr)
        return 1

    notifier = TelegramNotifier(
        bot_token=bot_token,
        chat_id=chat_id,
        state_file=STATE_FILE,
        logger=logger,
        dry_run=dry_run,
        rate_limit_per_minute=rate_limit,
        dedup_window_seconds=dedup_window,
    )

    app = create_app(logger, notifier)

    logger.info("event=startup outcome=ok host=%s port=%d dry_run=%s", mcp_host, mcp_port, dry_run)
    app.run(host=mcp_host, port=mcp_port, debug=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
