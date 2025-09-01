# PI-host scripts

Host-side scripts for sending IP and system info via Telegram or Discord.

## Important - Dependencies required

The script doesn't rely on too much, however you must have the following installed for it to operate:

* python3
* curl
* lsb_release (out of box for Ubuntu, but needs `redhat-lsb-core` for CentOS/RHEL)
* dig (install `dnsutils` on DEB systems and `bind-utils` on RPM systems)

---

# How to use this script and supporting files

Clone the repo into a folder somewhere, such as in `/root/`, so your folder structure looks like

`/root/pi-ip-logging/...`

Cron entries use `@reboot` which run as root. Adjust paths if you clone elsewhere.

## Self Updating Script

If you want to use the self-updating function (disabled by default), run from the cloned repo so git metadata is intact.

## Setting up

### Install (example)

Install with cron entries for the Python script:

```
cd /root
git clone https://github.com/M1XZG/pi-ip-logging.git
chmod +x /root/pi-ip-logging/PI-host/log_my_ip.py
cp /root/pi-ip-logging/PI-host/log-my-ip.CRONTAB /etc/cron.d/log-my-ip
chmod 644 /etc/cron.d/log-my-ip
chown root.root /etc/cron.d/log-my-ip
```

At this point you should double check `/etc/cron.d/log-my-ip` to make sure the paths to the script are correct, if you've left the repo cloned in `/root/` then it will be.

### log-my-ip.ini

This file contains all variables required by the script. Default search order:

1) `/etc/log-my-ip.ini`
2) `$HOME/.log-my-ip.ini`
3) `/usr/local/etc/log-my-ip.ini`

Override with `--ini /path/to/file`.

### Python script (preferred): `log_my_ip.py`

Unified notifier for Discord and/or Telegram.

- ENABLE flags: `ENABLE_DISCORD`, `ENABLE_TELEGRAM` (optional; inferred from config if missing)
- CLI:
  - `--reboot` sets note to REBOOT and skips self-update
  - `--scheduled` sets note to SCHEDULED
  - `-m|--note "custom message"`
  - `--enable-self-update` writes `USE_SELFUPATE=YES` and `GIT_BRANCH="main"` to the INI and exits
  - `--ini /path/to/log-my-ip.ini` to override search
  - `-n|--dry-run` to print without sending

Discord logos: The script picks an OS icon by reading `/etc/os-release` and mapping ID/ID_LIKE to the official alpha-3 codes used by the logos repo. You can override via `DISCORD_OS_LOGO_CODE=UBT` etc. See the repo’s preview list for available codes.

Discord extras:
- `DISCORD_THREAD_ID` (optional): If your webhook targets a Forum/Thread channel, set the thread ID here so messages go into that thread.
- `DISCORD_WAIT=YES` (optional): Adds `wait=true` to the webhook call so Discord returns a response; useful behind proxies/WAFs.
- On HTTP 400/401/403 errors with embeds, the script automatically retries with a content-only message. It also prints the HTTP error body to help troubleshoot issues like “Unknown Webhook” (invalid/rotated URL) or permission problems.

#### Common OS logo codes

Reference repository: https://github.com/M1XZG/operating-system-logos (see README “Preview List”)

| Code | Name           |
| ---- | -------------- |
| UBT  | Ubuntu         |
| DEB  | Debian         |
| RHT  | Red Hat (RHEL) |
| CES  | CentOS         |
| FED  | Fedora         |
| ARL  | Arch Linux     |
| SSE  | SUSE/openSUSE  |
| RAS  | Raspberry Pi   |
| MIN  | Linux Mint     |
| BSD  | FreeBSD        |
| NBS  | NetBSD         |
| OBS  | OpenBSD        |
| WIN  | Windows        |
| MAC  | Mac            |
| AND  | Android        |
| LIN  | GNU/Linux      |

### Legacy bash (still available): `log-my-ip.sh` and `log-my-ip-discord.sh`

This script is run on the Debian linux machines, like the [Raspberry Pi](https://www.raspberrypi.org/) and it will send the hostname, internal IP, external IP and the date/time of the Pi.

To use telegram you will need to create a telegram bot (or use an existing one) and you'll also need the chat / group / channel ID for the bot to receive messages and display them.  There are many guides to figure out how to get the chat id's and such, but check out:
https://www.home-assistant.io/components/telegram/

Arguments behave like the Python script: pass a note, or use flags shown above.

![Example Telegram Message](../media/telegram-sample.jpg)

This is a run of the script where changes to the repo were found, these are pulled down and the script is run again with the updated version. The `log-my-ip.sh` ins't updated in this run, but other files where, so these are brought down. To have ONLY the script update it would need to be in it's own repo or even a branch of it's own.

## Enabling self-update from CLI

Enable self-update by updating `/usr/local/etc/log-my-ip.ini` (requires root):

```sh
/root/pi-ip-logging/PI-host/log_my_ip.py --enable-self-update
```

## External IP detection

The Python script resolves external IPv4 using multiple strategies:

1) DNS (if `dig` is available):
  - Google DNS TXT: `o-o.myaddr.l.google.com @ns1.google.com`
  - OpenDNS A record: `myip.opendns.com @resolver1.opendns.com`
2) HTTPS fallbacks: ipify, ifconfig.me, icanhazip, checkip.amazonaws.com, ipinfo.io

If all methods fail, `External IP` is set to `Unknown`.

## Cron & environment notes

- Colors/tput are disabled when no TTY (cron-safe)
- Scripts wait for network; on non-LAN hosts set `_my_network_range=ANY` to avoid delays

## Screenshots

![Example Telegram Message](../media/telegram-sample.jpg)
![Example Telegram Message 2](../media/telegram-sample-2.jpg)
