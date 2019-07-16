# IP Logging for Pi's

Firstly, these scripts work for me and may or may not work for you.  Basically, the php script in Simple-Serverside runs on a small server listening for connections
from the log-my-ip.sh script which is just pushing some data to the php script, this is then logged in a CSV format.  Mostly this is just for some historical value,
I don't currently use this for anything specific but I suppose you could.

---

## PI-host/

### log-my-ip.sh

This script is run on the Pi/linux machine and it will send the hostname, internal IP, external IP and the date/time of the Pi.

```
chmod +x log-my-ip.sh
```

### log-my-ip.CRONTAB

This should be placed in /etc/cron.d/  it will run at boot time as well whatever time(s) you set (midnight by default).

```
cp log-my-ip.CRONTAB /etc/cron.d/log-my-ip
chmod 644 /etc/cron.d/log-my-ip
chown root.root /etc/cron.d/log-my-ip
```
---

## Simple-Serverside/ 

### log-ips.php

This script runs on the web server and is hit by a POST to store the info. Edit the PHP and change the filename variable if you want a different logging file.

