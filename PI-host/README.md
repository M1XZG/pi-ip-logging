# Instructions coming soon... 

### log-my-ip.sh

This script is run on the Pi/linux machine and it will send the hostname, internal IP, external IP and the date/time of the Pi.

```
chmod +x log-my-ip.sh
```

To use telegram you will need to create a bot (or use an existing one) and you'll also need the chat / group / channel ID for the bot to receive messages and display them.  There are many guides to figure out how to get the chat id's and such, but check out:
https://www.home-assistant.io/components/telegram/


### log-my-ip.CRONTAB

This should be placed in /etc/cron.d/  it will run at boot time as well whatever time(s) you set (midnight by default).

```
cp log-my-ip.CRONTAB /etc/cron.d/log-my-ip
chmod 644 /etc/cron.d/log-my-ip
chown root.root /etc/cron.d/log-my-ip
```
---
