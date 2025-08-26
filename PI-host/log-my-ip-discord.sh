#!/usr/bin/env bash
########################################################################################################
# Author            : "Robert McKenzie" <rmckenzi@rpmdp.com>
# Script Name       : log-my-ip-discord.sh
# Description       : Send a message to a Discord channel via webhook at boot/schedule with hostname,
#			internal and external IPs, and an optional note.
#
# Date              : 26/08/2025
#
# Notes             :
# - Configure DISCORD_WEBHOOK_URL in /usr/local/etc/log-my-ip.ini (or edit defaults below).
# - Optional: DISCORD_USERNAME, DISCORD_AVATAR_URL, DISCORD_EMBED_COLOR (int RGB like 3066993).
# - Waits until an IP in _my_network_range is assigned before proceeding.
# - Requires: curl, lsb_release, dig
########################################################################################################

#set -x
# Exit on error (uncomment to enable strict mode)
# set -o errexit
# set -o pipefail

########################################################################################################
# Colours
_RESTORE='\\033[0m'
_BOLD=''
_RED='\\033[00;31m'
_GREEN='\\033[00;32m'
_YELLOW='\\033[00;33m'

########################################################################################################
# Disable colors and tput in non-interactive environments (e.g., cron)
if [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ] && [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    _BOLD=$(tput bold 2>/dev/null || printf '')
else
    _RESTORE=''
    _RED=''
    _GREEN=''
    _YELLOW=''
fi

########################################################################################################
# PATH and args
PATH=${PATH}:/usr/sbin:/usr/bin:/sbin:/bin

# Capture raw args for note handling (supports flags and positional usage)
RAW_ARGS=("$@")

########################################################################################################
# Config
########################################################################################################
# If an INI file exists, source it; otherwise set sensible defaults here.
if [ -f /usr/local/etc/log-my-ip.ini ]; then
    # shellcheck disable=SC1091
    source /usr/local/etc/log-my-ip.ini
else
    # Defaults if no INI provided
    DISCORD_WEBHOOK_URL=""              # e.g. https://discord.com/api/webhooks/.....
    DISCORD_USERNAME="Pi IP Logger"
    DISCORD_AVATAR_URL=""               # optional
    DISCORD_EMBED_COLOR=3066993          # optional (teal)
    DISCORD_USE_EMBEDS="YES"            # YES/NO (use rich embeds by default)
    _my_network_range="192.168.0"
fi

hostname="$(hostname)"
intip=""
mydate="$(date)"

########################################################################################################
# Functions
########################################################################################################

check_for_deps() {
    which dig &>/dev/null; _HAVE_DIG=$?
    which lsb_release &>/dev/null; _HAVE_LSB=$?
    which curl &>/dev/null; _HAVE_CURL=$?

    if [ ${_HAVE_DIG} -ne 0 ] || [ ${_HAVE_LSB} -ne 0 ] || [ ${_HAVE_CURL} -ne 0 ]; then
        echo -e "${_RED}Missing dependencies detected.${_RESTORE}"
        [ ${_HAVE_DIG} -ne 0 ] && echo -e " - Install ${_GREEN}dnsutils${_RESTORE} (DEB) or ${_GREEN}bind-utils${_RESTORE} (RPM) for 'dig'"
        [ ${_HAVE_LSB} -ne 0 ] && echo -e " - Install ${_GREEN}redhat-lsb-core${_RESTORE} for 'lsb_release' on RHEL/CentOS"
        [ ${_HAVE_CURL} -ne 0 ] && echo -e " - Install ${_GREEN}curl${_RESTORE}"
        exit 1
    fi
}

wait_for_internal_ip() {
    local intipres="1"
    while [ "$intipres" = "1" ]; do
        intip="$(hostname -I | awk '{print $1}')"
        echo "$intip" | grep -q "${_my_network_range}"
        intipres=$?
        [ "$intipres" = "1" ] && sleep 5
    done
}

get_external_ip() {
    extip="$(dig +short myip.opendns.com @resolver1.opendns.com)"
}

json_escape() {
    # Escapes a string for safe JSON inclusion (basic: backslash, quote, newline -> \n)
    # Usage: json_escape "string"
    echo -n "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g' | tr '\n' '\\n'
}

# Additional system info helpers
get_os_info() {
    if command -v lsb_release >/dev/null 2>&1; then
        os_name="$(lsb_release -ds 2>/dev/null | sed 's/"//g')"
    elif [ -f /etc/os-release ]; then
        os_name="$(. /etc/os-release; echo "$PRETTY_NAME")"
    else
        os_name="Unknown"
    fi
}

get_kernel_info() {
    kernel_ver="$(uname -r 2>/dev/null || echo Unknown)"
}

get_uptime_pretty() {
    if command -v uptime >/dev/null 2>&1; then
        uptime_pretty="$(uptime -p 2>/dev/null || true)"
        [ -z "$uptime_pretty" ] && uptime_pretty="Unknown"
    else
        uptime_pretty="Unknown"
    fi
}

get_last_boot_time() {
    if command -v who >/dev/null 2>&1; then
        last_boot="$(who -b 2>/dev/null | awk '{print $3" "$4}' | head -n1)"
        [ -z "$last_boot" ] && last_boot="Unknown"
    else
        last_boot="Unknown"
    fi
}

# State handling for last recorded reboot
resolve_state_file() {
    local candidate
    if [ -n "${LAST_REBOOT_FILE:-}" ]; then
        candidate="$LAST_REBOOT_FILE"
    else
        local base_dir
        base_dir="${STATE_DIR:-/var/lib/log-my-ip}"
        candidate="$base_dir/last_reboot.txt"
    fi
    local dir
    dir="$(dirname "$candidate")"
    if mkdir -p "$dir" 2>/dev/null; then
        state_file="$candidate"
    else
        mkdir -p /tmp/log-my-ip 2>/dev/null || true
        state_file="/tmp/log-my-ip/last_reboot.txt"
    fi
}

read_last_reboot_recorded() {
    last_reboot_recorded="Unknown"
    [ -f "$state_file" ] && last_reboot_recorded="$(cat "$state_file" 2>/dev/null)"
}

write_last_reboot_recorded_if_needed() {
    if [ "${note^^}" = "REBOOT" ]; then
        date -u +"%Y-%m-%dT%H:%M:%SZ" > "$state_file" 2>/dev/null || true
    fi
}

send_message_to_discord() {
    if [ -z "${DISCORD_WEBHOOK_URL}" ]; then
        echo -e "${_YELLOW}DISCORD_WEBHOOK_URL not set. Skipping Discord notification.${_RESTORE}"
        return 0
    fi

    local note="$1"
    local esc_username esc_avatar esc_note esc_hostname esc_intip esc_extip
    esc_username=$(json_escape "${DISCORD_USERNAME:-Pi IP Logger}")
    esc_avatar=$(json_escape "${DISCORD_AVATAR_URL}")
    esc_note=$(json_escape "$note")
    esc_hostname=$(json_escape "$hostname")
    esc_intip=$(json_escape "$intip")
    esc_extip=$(json_escape "$extip")
    # Extra fields
    local esc_os esc_kernel esc_uptime esc_lboot esc_lreboot
    esc_os=$(json_escape "${os_name:-}")
    esc_kernel=$(json_escape "${kernel_ver:-}")
    esc_uptime=$(json_escape "${uptime_pretty:-}")
    esc_lboot=$(json_escape "${last_boot:-}")
    esc_lreboot=$(json_escape "${last_reboot_recorded:-}")

    local tmpfile
    tmpfile=$(mktemp /tmp/discord.XXXXXXX)

    # Use embeds by default; allow opt-out via DISCORD_USE_EMBEDS=NO
        if [ "${DISCORD_USE_EMBEDS^^}" != "NO" ]; then
        local color iso
        color=${DISCORD_EMBED_COLOR:-3066993}
        iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        cat >"$tmpfile" <<EOF
{"username":"${esc_username}",
 "avatar_url":"${esc_avatar}",
 "embeds":[
     {"title":"System Update",
        "description":"${esc_note}",
    "color":${color},
    "timestamp":"${iso}",
        "author": {"name": "${esc_hostname}"},
        "footer": {"text": "log-my-ip • Discord"},
        "fields":[
            {"name":"Hostname","value":"${esc_hostname}","inline":true},
            {"name":"Internal IP","value":"${esc_intip}","inline":true},
            {"name":"External IP","value":"${esc_extip}","inline":true},
            {"name":"OS","value":"${esc_os}","inline":true},
            {"name":"Kernel","value":"${esc_kernel}","inline":true},
            {"name":"Uptime","value":"${esc_uptime}","inline":true},
            {"name":"Last Boot","value":"${esc_lboot}","inline":true},
            {"name":"Last Reboot Recorded","value":"${esc_lreboot}","inline":true}
        ]
   }
 ]
}
EOF
    else
        # Plain content fallback
        local content esc_content
        content=$(printf '**System Update**: %s\n**Date**: %s\n**Hostname**: %s\n**Internal IP**: %s\n**External IP**: %s' \
            "$note" "$mydate" "$hostname" "$intip" "$extip")
        esc_content=$(json_escape "$content")
        cat >"$tmpfile" <<EOF
{"username":"${esc_username}","avatar_url":"${esc_avatar}","content":"${esc_content}"}
EOF
    fi

    # Send
    curl -sS -H 'Content-Type: application/json' \
        -X POST -d @"${tmpfile}" "${DISCORD_WEBHOOK_URL}" >/dev/null 2>&1
    local rc=$?
    rm -f "$tmpfile"
    return $rc
}

########################################################################################################
# Main
########################################################################################################

check_for_deps
wait_for_internal_ip
get_external_ip
get_os_info
get_kernel_info
get_uptime_pretty
get_last_boot_time
resolve_state_file
read_last_reboot_recorded

# Parse arguments for note. Support:
#   --reboot | --scheduled | -m|--note "message" | positional words
parse_note() {
    local note_flag="" pos=()
    local i=0
    while [ $i -lt ${#RAW_ARGS[@]} ]; do
        arg="${RAW_ARGS[$i]}"
        case "$arg" in
            --reboot)
                note_flag="REBOOT"; i=$((i+1));;
            --scheduled)
                note_flag="SCHEDULED"; i=$((i+1));;
            -m|--note)
                i=$((i+1));
                note_flag="${RAW_ARGS[$i]:-}"; i=$((i+1));;
            --)
                i=$((i+1));
                while [ $i -lt ${#RAW_ARGS[@]} ]; do pos+=("${RAW_ARGS[$i]}"); i=$((i+1)); done;;
            *)
                pos+=("$arg"); i=$((i+1));;
        esac
    done
    if [ -n "$note_flag" ]; then
        note="$note_flag"
    elif [ ${#pos[@]} -gt 0 ]; then
        note="${pos[*]}"
    else
        note="Manual Update"
    fi
}

parse_note

send_message_to_discord "$note"
write_last_reboot_recorded_if_needed
exit $?
