#!/usr/bin/env python3
"""
Auto-patch a log-my-ip.ini file with newly introduced options.

Behavior:
- Preserves existing values exactly; only appends missing keys near the end.
- Adds safe defaults or commented placeholders for new options.
- Backs up the original file to <path>.bak-YYYYmmddHHMMSS
- Supports --dry-run to preview changes without writing.

Usage:
  ./update_log_my_ip_ini.py --ini /usr/local/etc/log-my-ip.ini [--dry-run]
"""
import argparse
import os
import shutil
import sys
from datetime import datetime
from typing import Optional, Dict


def read_file(path: str) -> Optional[str]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return None


def write_file(path: str, data: str, mode: int = 0o644) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)
    os.chmod(path, mode)


def parse_ini_simple(txt: str) -> Dict[str, str]:
    cfg: Dict[str, str] = {}
    for raw in txt.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        cfg[key.strip()] = val.strip()
    return cfg


def build_missing_lines(existing: Dict[str, str]) -> list:
    # Define known keys with recommended defaults or commented placeholders.
    # Keys marked with None will be added as commented-out placeholders.
    defaults: Dict[str, Optional[str]] = {
        # Core
        "USE_SELFUPATE": "NO",
        "GIT_BRANCH": '"main"',
        "_my_network_range": '"ANY"',  # Accept any IP by default
        "NETWORK_WAIT_MAX_ATTEMPTS": None,  # comment-only, default is 24 in code

        # Telegram
        "TGTOKEN": '""',
        "TGCHATID": '""',
        "TGGRPID": '""',
        "ENABLE_TELEGRAM": None,  # inferred if omitted

        # Discord
        "DISCORD_WEBHOOK_URL": '""',
        "DISCORD_USERNAME": '"Pi IP Logger"',
        "DISCORD_AVATAR_URL": '""',
        "DISCORD_EMBED_COLOR": "3066993",
        "DISCORD_USE_EMBEDS": "YES",
        "DISCORD_OS_LOGO_CODE": None,  # comment-only
        "DISCORD_THREAD_ID": None,     # comment-only
        "DISCORD_WAIT": None,          # comment-only
        "ENABLE_DISCORD": None,        # inferred if omitted
    }

    lines: list = []
    for key, val in defaults.items():
        if key in existing:
            continue
        if val is None:
            # Commented placeholder
            lines.append(f"#{key}=")
        else:
            lines.append(f"{key}={val}")
    return lines


def main() -> int:
    ap = argparse.ArgumentParser(description="Auto-patch log-my-ip.ini with new options")
    ap.add_argument("--ini", required=True, help="Path to log-my-ip.ini to update")
    ap.add_argument("--dry-run", action="store_true", help="Show changes without writing")
    args = ap.parse_args()

    ini_path = os.path.expanduser(args.ini)
    txt = read_file(ini_path)
    if txt is None:
        print(f"Error: INI not found: {ini_path}", file=sys.stderr)
        return 2

    existing = parse_ini_simple(txt)
    missing_lines = build_missing_lines(existing)

    if not missing_lines:
        print("No changes needed — your INI already contains all known keys.")
        return 0

    # Prepare output
    banner = [
        "",
        f"## Added by update_log_my_ip_ini.py on {datetime.now().isoformat(timespec='seconds')}",
        "# The following keys were missing and have been appended.",
        "# Note: commented entries are optional and safe to ignore.",
    ]
    new_txt = txt.rstrip("\n") + "\n" + "\n".join(banner + missing_lines) + "\n"

    if args.dry_run:
        print("--- BEGIN NEW CONTENT (preview) ---")
        print("\n".join(missing_lines))
        print("--- END NEW CONTENT (preview) ---")
        return 0

    # Backup and write
    backup_path = f"{ini_path}.bak-{datetime.now().strftime('%Y%m%d%H%M%S')}"
    try:
        shutil.copy2(ini_path, backup_path)
        print(f"Backup written: {backup_path}")
    except Exception as e:
        print(f"Warning: failed to create backup: {e}")
    write_file(ini_path, new_txt)
    print(f"Updated: {ini_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
