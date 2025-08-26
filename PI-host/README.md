# Important - Dependencies required

The script doesn't rely on too much, however you must have the following installed for it to operate:

* curl
* lsb_release (out of box for Ubuntu, but needs `redhat-lsb-core` for CentOS/RHEL)
* dig (install `dnsutils` on DEB systems and `bind-utils` on RPM systems)

---

# How to use this script and supporting files

The way I operate this script is to clone the repo into a folder somewhere, such as in `/root/`, so my folder structure will look like

`/root/pi-ip-logging/...`

I do this only because the CRONTAB I've created has directive to run the script `@REBOOT`, this can only be done if the script is run as root. Another reason to run as root is it will attempt to install any dependencies using `apt-get`, at this time the only real dependency is `dnsutils`, most other commands called are stock and found in typical installs.

## Self Updating Script

If you want to use the self-updating function of the script (it's disabled out of the box), then you need to run the script from the cloned repo folder so the GIT data is intact. 

## Setting up

I install using the process similar to

```
cd /root
git clone https://github.com/M1XZG/pi-ip-logging.git
chmod +x /root/pi-ip-logging/PI-host/log-my-ip.sh
cp /root/pi-ip-logging/PI-host/log-my-ip.CRONTAB /etc/cron.d/log-my-ip
chmod 644 /etc/cron.d/log-my-ip
chown root.root /etc/cron.d/log-my-ip
```

At this point you should double check `/etc/cron.d/log-my-ip` to make sure the paths to the script are correct, if you've left the repo cloned in `/root/` then it will be.

### log-my-ip.ini

This file isn't required if you want to just customize the varibles in the script, however, that will prevent you from using the self-updating part as your changes will be lost to the script. The INI file just contains all the variables required by the script, the default location for this is `/usr/local/etc/log-my-ip.ini`, again, changing this could break. _(I have a future plan to allow the updating of the INI file from perhaps your private webserver or something, GitHub would be bad for this as it will contain secrets you don't want anyone to get)_

### log-my-ip.sh

This script is run on the Debian linux machines, like the [Raspberry Pi](https://www.raspberrypi.org/) and it will send the hostname, internal IP, external IP and the date/time of the Pi.

To use telegram you will need to create a telegram bot (or use an existing one) and you'll also need the chat / group / channel ID for the bot to receive messages and display them.  There are many guides to figure out how to get the chat id's and such, but check out:
https://www.home-assistant.io/components/telegram/

The `log-my-ip.sh` script requires no arguements, but whatever you supply will be used as the note that's sent to your or logged. If you look in `/etc/cron.d/log-my-ip` you'll see on reboot the script is called with *REBOOT* and nightly at midnight when I run my daily checkpoint it uses *SCHEDULED*, you can of course change these. If you want to use more than ONE word, just wrap the words in double quotes.

![Example Telegram Message](../media/telegram-sample.jpg)

This is a run of the script where changes to the repo were found, these are pulled down and the script is run again with the updated version. The `log-my-ip.sh` ins't updated in this run, but other files where, so these are brought down. To have ONLY the script update it would need to be in it's own repo or even a branch of it's own.

```
## Using Discord instead of Telegram

If you prefer Discord notifications, use `log-my-ip-discord.sh` which posts to a Discord channel via an Incoming web hook.

Setup steps:

1) Create a Discord Incoming web hook for your target channel and copy its URL.
2) Edit or create `/usr/local/etc/log-my-ip.ini` and set:

   - `DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/…"`
   - Optionally `DISCORD_USERNAME` and `DISCORD_AVATAR_URL`.

3) Make the script executable and install the CRON file:

   - `chmod +x /root/pi-ip-logging/PI-host/log-my-ip-discord.sh`
   - `cp /root/pi-ip-logging/PI-host/log-my-ip-discord.CRONTAB /etc/cron.d/log-my-ip-discord`
   # PI-host scripts

   Host-side scripts for sending IP and system info via Telegram or Discord.

   ## Dependencies

   Install the following on the host:

   - curl
   - lsb_release (built-in on Ubuntu; use `redhat-lsb-core` for CentOS/RHEL)
   - dig (install `dnsutils` on DEB systems and `bind-utils` on RPM systems)

   ## Setup

   Clone and install cron entries (example paths assume `/root/pi-ip-logging`):

   ```sh
   cd /root
   git clone https://github.com/M1XZG/pi-ip-logging.git
   chmod +x /root/pi-ip-logging/PI-host/log-my-ip.sh
   cp /root/pi-ip-logging/PI-host/log-my-ip.CRONTAB /etc/cron.d/log-my-ip
   chmod 644 /etc/cron.d/log-my-ip
   chown root.root /etc/cron.d/log-my-ip

   # Discord (optional)
   chmod +x /root/pi-ip-logging/PI-host/log-my-ip-discord.sh
   cp /root/pi-ip-logging/PI-host/log-my-ip-discord.CRONTAB /etc/cron.d/log-my-ip-discord
   chmod 644 /etc/cron.d/log-my-ip-discord
   chown root.root /etc/cron.d/log-my-ip-discord
   ```

   Adjust paths in `/etc/cron.d/*` if your clone location differs.

   ## Configuration (log-my-ip.ini)

   Default path is `/usr/local/etc/log-my-ip.ini`. If not present, scripts use built-in defaults.

   Telegram settings:

   - `TGTOKEN` – Bot token
   - `TGCHATID` – Direct chat ID
   - `TGGRPID` – Group/channel ID

   Discord settings:

   - `DISCORD_WEBHOOK_URL` – Required for Discord notifications
   - `DISCORD_USERNAME` – Optional sender name
   - `DISCORD_AVATAR_URL` – Optional avatar URL
   - `DISCORD_EMBED_COLOR` – Integer RGB (e.g., 3066993)
   - `DISCORD_USE_EMBEDS` – YES/NO (default YES)

   Network wait behavior:

   - `_my_network_range` – Prefix to detect local LAN, e.g., `192.168.0` or `172.16.29`
     - Set to `ANY` or leave empty to accept any non-empty IP (useful on hosted servers)
   - `NETWORK_WAIT_MAX_ATTEMPTS` – Attempts waiting for a LAN match (5s per attempt), default 24 (~2 minutes)

   Other:

   - `USE_SELFUPATE` – Enable self-update when running from a git clone
   - `GIT_BRANCH` – Branch to check for updates

   Migration helper:

   - Use `PI-host/migrate-log-my-ip-ini.sh` to safely add new keys without overwriting existing values
     - `--dry-run` to preview changes
     - `--from-template` [--template-path /path/to/template] to rebuild from template while preserving known values

   ## Usage

   Telegram script: `log-my-ip.sh`

   - Sends hostname, internal IP, external IP, and date/time via Telegram
   - Optional post to your server (if configured)
   - Arguments are used as the note; examples used by cron:
     - `REBOOT` at startup
     - `SCHEDULED` nightly

   Discord script: `log-my-ip-discord.sh`

   - Posts to a Discord channel via Incoming Webhook
   - Rich embeds by default showing: Hostname, Internal IP, External IP, OS, Kernel, Uptime
   - Accepts notes via positional args or flags: `--reboot`, `--scheduled`, `-m|--note "message"`

  ### Enabling self-update from CLI

  Both scripts can enable self-update by updating `/usr/local/etc/log-my-ip.ini`:

  ```sh
  # Requires root
  ./log-my-ip.sh --enable-self-update
  ./log-my-ip-discord.sh --enable-self-update
  ```

  This sets `USE_SELFUPATE=YES` and `GIT_BRANCH="main"` in the INI (creating it if missing).

   ## External IP detection

   Both scripts now resolve the external IPv4 using multiple strategies:

   1) DNS (if `dig` is available):
      - Google DNS TXT: `o-o.myaddr.l.google.com @ns1.google.com`
      - OpenDNS A record: `myip.opendns.com @resolver1.opendns.com`
   2) HTTPS fallbacks (via `curl`): ipify, ifconfig.me, icanhazip, checkip.amazonaws.com, ipinfo.io

   If all methods fail, `External IP` is set to `Unknown`.

   ## Cron & environment notes

   - Colors/tput are disabled when no TTY (cron-safe)
   - Scripts wait for network; on non-LAN hosts set `_my_network_range=ANY` to avoid delays

   ## Screenshots

   ![Example Telegram Message](../media/telegram-sample.jpg)
   ![Example Telegram Message 2](../media/telegram-sample-2.jpg)
