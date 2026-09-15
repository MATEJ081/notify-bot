#!/usr/bin/env python3
"""CLI wrapper for Telegram notifications.

Uso:
    python3 notify.py "testo del messaggio"

Legge configurazione da .env (BOT_TOKEN, TELEGRAM_CHAT_ID, DRY_RUN, etc.)
Usa TelegramNotifier per inviare con guardrail (rate limit, dedup, dry-run).
"""

import logging
import os
import sys
from pathlib import Path

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
    logger = logging.getLogger("notify-bot")
    logger.setLevel(logging.INFO)
    handler = logging.FileHandler(LOG_DIR / "notify.log")
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    )
    logger.addHandler(handler)
    logger.addHandler(logging.StreamHandler(sys.stdout))
    return logger


def main() -> int:
    if len(sys.argv) != 2:
        print("Uso: python3 notify.py \"testo del messaggio\"", file=sys.stderr)
        return 2

    message = sys.argv[1]
    load_env_file(ENV_FILE)
    logger = setup_logging()

    bot_token = os.environ.get("BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "")
    dry_run = os.environ.get("DRY_RUN", "true").strip().lower() != "false"
    rate_limit = int(os.environ.get("RATE_LIMIT_PER_MINUTE", "5"))
    dedup_window = int(os.environ.get("DEDUP_WINDOW_SECONDS", "300"))

    if not bot_token or not chat_id:
        logger.error("event=config_missing outcome=aborted")
        print("Errore: BOT_TOKEN o TELEGRAM_CHAT_ID mancanti in .env", file=sys.stderr)
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

    try:
        sent = notifier.send(message)
        if dry_run:
            print("[DRY RUN] Messaggio non inviato realmente. Imposta DRY_RUN=false in .env per l'invio reale.")
        return 0 if sent else 1
    except Exception as exc:
        logger.error("event=send outcome=error type=%s msg=%s", type(exc).__name__, str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
