#!/usr/bin/env bash
#
# migrate-log-my-ip-ini.sh
#
# Safely updates an existing /usr/local/etc/log-my-ip.ini by adding new Discord-related
# configuration keys (non-destructive), or optionally rebuilding from a template while
# preserving your existing values.
#
# Usage:
#   ./migrate-log-my-ip-ini.sh [-n|--dry-run] [--from-template] [--template-path PATH] [path-to-ini]
#
# - If no path is provided, defaults to /usr/local/etc/log-my-ip.ini
# - Creates a timestamped backup before making changes (skipped in dry run)
# - Default behavior: Append missing Discord keys only (non-destructive)
# - --from-template: Rebuild the INI using the repo template's ordering/comments while preserving existing values
#   • Template default: PI-host/log-my-ip.ini (relative to this script)
#   • Override template with --template-path PATH
# - Also fixes an old header comment path if it references log-my-up.ini

set -euo pipefail

err() { echo "[ERROR] $*" >&2; }
info() { echo "[INFO]  $*"; }

DRY_RUN=0
FROM_TEMPLATE=0
TEMPLATE_PATH=""
INI_PATH=""

# Argument parsing
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    --from-template)
      FROM_TEMPLATE=1
      shift
      ;;
    --template-path)
      shift
      TEMPLATE_PATH="${1:-}"
      [ -z "$TEMPLATE_PATH" ] && err "--template-path requires a value" && exit 2
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      err "Unknown option: $1"; exit 2
      ;;
    *)
      if [ -z "$INI_PATH" ]; then
        INI_PATH="$1"
      else
        err "Unexpected extra argument: $1"; exit 2
      fi
      shift
      ;;
  esac
done

INI_PATH="${INI_PATH:-/usr/local/etc/log-my-ip.ini}"

# Resolve default template path if needed
if [ "$FROM_TEMPLATE" -eq 1 ] && [ -z "$TEMPLATE_PATH" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEMPLATE_PATH="${SCRIPT_DIR}/log-my-ip.ini"
fi

if [ ! -f "$INI_PATH" ]; then
  err "INI file not found: $INI_PATH"
  err "Provide the path to your existing log-my-ip.ini or create one from PI-host/log-my-ip.ini"
  exit 1
fi

has_key() {
  local key="$1"
  grep -Eq "^[[:space:]]*${key}=" "$INI_PATH"
}

append_line() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "[DRY RUN] + $1"
  else
    echo "$1" >> "$INI_PATH"
  fi
}

append_blank_if_needed() {
  local last
  last=$(tail -n 1 "$INI_PATH" || true)
  if [ -n "$last" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '%s\n' "[DRY RUN] +"  # blank line
    else
      echo >> "$INI_PATH"
    fi
  fi
}

wrote_header=0
write_header_once() {
  if [ "$wrote_header" -eq 0 ]; then
    append_blank_if_needed
    append_line "########################################"
    append_line "# Discord settings (added by migration)"
    wrote_header=1
  fi
}

add_key_if_missing() {
  local key="$1" value="$2" comment="$3"
  if has_key "$key"; then
    info "Key exists: $key (preserved)"
  else
    write_header_once
    [ -n "$comment" ] && append_line "$comment"
    append_line "${key}=${value}"
    info "Added key: $key"
  fi
}

# Fix legacy header comment path if present
fix_legacy_header_comment() {
  if grep -q "log-my-up.ini" "$INI_PATH"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      info "[DRY RUN] Would update header comment to reference log-my-ip.ini"
    else
      sed -i 's|log-my-up.ini|log-my-ip.ini|g' "$INI_PATH"
      info "Updated header comment to reference log-my-ip.ini"
    fi
  fi
}

merge_from_template() {
  local template="$1" dest="$2" out_tmp
  if [ ! -f "$template" ]; then
    err "Template not found: $template"
    exit 1
  fi

  out_tmp="$(mktemp /tmp/log-my-ip.ini.merge.XXXXXX)"
  local seen_keys_tmp
  seen_keys_tmp="$(mktemp /tmp/log-my-ip.ini.seen.XXXXXX)"

  while IFS= read -r line || [ -n "$line" ]; do
    if echo "$line" | grep -Eq '^[[:space:]]*#'; then
      echo "$line" >> "$out_tmp"; continue
    fi
    if echo "$line" | grep -Eq '^[[:space:]]*$'; then
      echo "$line" >> "$out_tmp"; continue
    fi
    if echo "$line" | grep -Eq '^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*='; then
      local key template_value existing_line value
      key="$(echo "$line" | sed -n 's/^[[:space:]]*\([A-Za-z0-9_][A-Za-z0-9_]*\)[[:space:]]*=.*$/\1/p')"
      template_value="$(printf '%s' "$line" | sed 's/^[^=]*=//')"
      existing_line="$(grep -E "^[[:space:]]*${key}=" "$dest" | tail -n1 || true)"
      if [ -n "$existing_line" ]; then
        value="${existing_line#*=}"
      else
        value="$template_value"
      fi
      printf '%s=%s\n' "$key" "$value" >> "$out_tmp"
      printf '%s\n' "$key" >> "$seen_keys_tmp"
    else
      echo "$line" >> "$out_tmp"
    fi
  done < "$template"

  local appended_any=0
  while IFS= read -r kline; do
    local dkey dval
    dkey="$(echo "$kline" | sed -n 's/^[[:space:]]*\([A-Za-z0-9_][A-Za-z0-9_]*\)[[:space:]]*=.*$/\1/p')"
    [ -z "$dkey" ] && continue
    if ! grep -Fxq "$dkey" "$seen_keys_tmp"; then
      if [ "$appended_any" -eq 0 ]; then
        echo >> "$out_tmp"
        echo "########################################" >> "$out_tmp"
        echo "# Preserved additional settings (not present in template)" >> "$out_tmp"
        appended_any=1
      fi
      dval="${kline#*=}"
      printf '%s=%s\n' "$dkey" "$dval" >> "$out_tmp"
    fi
  done < <(grep -E '^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*=' "$dest" | sed 's/[[:space:]]*#.*$//')

  rm -f "$seen_keys_tmp"

  if [ "$DRY_RUN" -eq 1 ]; then
    local preview
    preview="$(mktemp /tmp/log-my-ip.ini.preview.XXXXXX)"
    mv "$out_tmp" "$preview"
    info "[DRY RUN] Built merged preview at: $preview"
    info "[DRY RUN] Original INI unchanged: $dest"
  else
    mv "$out_tmp" "$dest"
    info "INI rebuilt from template with preserved values: $dest"
  fi
}

# Main
ts=$(date +%Y%m%d-%H%M%S)
backup_path="${INI_PATH}.bak.${ts}"

if [ "$FROM_TEMPLATE" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    info "[DRY RUN] Would create backup: $backup_path"
  else
    cp -p "$INI_PATH" "$backup_path"
    info "Backup created: $backup_path"
  fi
  merge_from_template "$TEMPLATE_PATH" "$INI_PATH"
  if [ "$DRY_RUN" -eq 1 ]; then
    info "Dry run complete for: $INI_PATH"
    info "No changes were made."
  fi
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  info "[DRY RUN] Would create backup: $backup_path"
else
  cp -p "$INI_PATH" "$backup_path"
  info "Backup created: $backup_path"
fi

# Ensure trailing newline
if tail -c1 "$INI_PATH" | read -r _; then :; else
  if [ "$DRY_RUN" -eq 1 ]; then
    info "[DRY RUN] Would append trailing newline to $INI_PATH"
  else
    echo >> "$INI_PATH"
  fi
fi

fix_legacy_header_comment

# Add Discord-related keys if missing
add_key_if_missing "DISCORD_WEBHOOK_URL" '""' "# Discord Incoming web hook URL (leave blank to disable)"
add_key_if_missing "DISCORD_USERNAME" '"Pi IP Logger"' "# Optional: override the sender name shown in Discord"
add_key_if_missing "DISCORD_AVATAR_URL" '""' "# Optional: avatar URL for the message"
add_key_if_missing "DISCORD_EMBED_COLOR" "3066993" "# Optional: embed color integer (RGB decimal)"
add_key_if_missing "DISCORD_USE_EMBEDS" "YES" "# Use rich embeds (YES/NO)"

# Add state-related keys if missing
add_key_if_missing "STATE_DIR" '"/var/lib/log-my-ip"' "# Base directory for writable state (used to track last reboot)"
add_key_if_missing "LAST_REBOOT_FILE" '""' "# Optional explicit file for last reboot timestamp (overrides STATE_DIR)"

if [ "$DRY_RUN" -eq 1 ]; then
  info "Dry run complete for: $INI_PATH"
  info "No changes were made."
else
  info "Migration complete for: $INI_PATH"
  info "Existing values preserved. Backup at: $backup_path"
fi
