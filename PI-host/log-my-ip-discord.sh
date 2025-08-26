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
_RESTORE='\033[0m'
_BOLD=$(tput bold)
_RED='\033[00;31m'
_GREEN='\033[00;32m'
_YELLOW='\033[00;33m'

########################################################################################################
# PATH and args
PATH=${PATH}:/usr/sbin:/usr/bin:/sbin:/bin
ARGS="$@"

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
    "fields":[
      {"name":"Hostname","value":"${esc_hostname}","inline":true},
      {"name":"Internal IP","value":"${esc_intip}","inline":true},
      {"name":"External IP","value":"${esc_extip}","inline":true}
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

if [ -z "$ARGS" ]; then
    note="Manual Update"
else
    note="$ARGS"
fi

send_message_to_discord "$note"
exit $?
