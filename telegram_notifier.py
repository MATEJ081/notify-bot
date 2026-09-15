"""Core logic for Telegram notifications with guardrails.

Provides TelegramNotifier class that handles:
- Rate limiting (per-minute cap)
- Deduplication (hash-based, time-windowed)
- DRY_RUN mode (default: enabled, no real API calls)
- Secure logging (no tokens, chat IDs, or full messages)
- State persistence (JSON file with 0o600 perms)
"""

import hashlib
import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Optional


class TelegramNotifier:
    """Send Telegram messages with rate limit, dedup, and dry-run guardrails."""

    def __init__(
        self,
        bot_token: str,
        chat_id: str,
        state_file: Path,
        logger: Optional[logging.Logger] = None,
        dry_run: bool = True,
        rate_limit_per_minute: int = 5,
        dedup_window_seconds: int = 300,
    ):
        """
        Args:
            bot_token: Telegram bot token (from environment)
            chat_id: Telegram chat ID (fixed, not user input)
            state_file: Path to state.json for rate limit / dedup tracking
            logger: Logger instance (optional, creates default if None)
            dry_run: If True, don't actually call Telegram API (default: True)
            rate_limit_per_minute: Max messages per minute
            dedup_window_seconds: Dedup window for message hashes
        """
        self.bot_token = bot_token
        self.chat_id = chat_id
        self.state_file = state_file
        self.dry_run = dry_run
        self.rate_limit_per_minute = rate_limit_per_minute
        self.dedup_window_seconds = dedup_window_seconds

        if logger is None:
            logger = logging.getLogger("TelegramNotifier")
        self.logger = logger

    def _load_state(self) -> dict:
        """Load state.json if it exists, else return empty dict."""
        if self.state_file.exists():
            try:
                return json.loads(self.state_file.read_text())
            except json.JSONDecodeError:
                return {}
        return {}

    def _save_state(self, state: dict) -> None:
        """Save state.json with restricted permissions."""
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.state_file.write_text(json.dumps(state))
        self.state_file.chmod(0o600)

    def _check_rate_limit(self, state: dict, now: float) -> bool:
        """True if send is allowed, False if rate limit exceeded."""
        timestamps = [
            t for t in state.get("sent_timestamps", [])
            if now - t < 60
        ]
        state["sent_timestamps"] = timestamps
        allowed = len(timestamps) < self.rate_limit_per_minute
        if not allowed:
            self.logger.info("event=send_blocked reason=rate_limit")
        return allowed

    def _check_dedup(self, state: dict, message: str, now: float) -> bool:
        """True if message is new (should send), False if it's a duplicate."""
        digest = hashlib.sha256(message.encode("utf-8")).hexdigest()
        last = state.get("last_message")
        if last and last.get("hash") == digest and now - last.get("ts", 0) < self.dedup_window_seconds:
            self.logger.info("event=send_blocked reason=duplicate")
            return False
        return True

    def _send_via_api(self, message: str) -> None:
        """Call actual Telegram API. Raises on error."""
        url = f"https://api.telegram.org/bot{self.bot_token}/sendMessage"
        data = urllib.parse.urlencode(
            {"chat_id": self.chat_id, "text": message}
        ).encode()
        req = urllib.request.Request(url, data=data, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status != 200:
                raise RuntimeError(f"Telegram API returned {resp.status}")

    def send(self, message: str) -> bool:
        """
        Send a message (or simulate if dry_run=True).

        Args:
            message: The text to send

        Returns:
            True if sent (or simulated), False if blocked (rate limit / dedup)

        Raises:
            RuntimeError: If Telegram API fails (only if not in dry_run)
        """
        now = time.time()
        state = self._load_state()

        if not self._check_dedup(state, message, now):
            return False

        if not self._check_rate_limit(state, now):
            return False

        # Record the send attempt (before API call, in case it fails)
        state.setdefault("sent_timestamps", []).append(now)
        state["last_message"] = {
            "hash": hashlib.sha256(message.encode("utf-8")).hexdigest(),
            "ts": now,
        }

        if self.dry_run:
            self.logger.info("event=send_simulated outcome=ok mode=dry_run")
        else:
            try:
                self._send_via_api(message)
                self.logger.info("event=send outcome=ok")
            except (urllib.error.URLError, RuntimeError) as exc:
                self.logger.error("event=send outcome=error type=%s", type(exc).__name__)
                # Don't save state if send failed (let user retry)
                return False

        self._save_state(state)
        return True
