# IP Logging for Pi's

These scripts will let Raspberry Pi's (or any linux system really) log it's IP to a simple PHP system for me.  This is run at boot and once day by cron

## log-ips.php

This script runs on the web server and is hit by a POST to store the info

## log-my-ip.sh

This script is run on the Pi/linux machine and it will send the hostname, internal IP, external IP and the date/time of the Pi.

## log-my-ip.CRONTAB

This should be placed in /etc/cron.d/  it will run at boot time as well whatever time(s) you set.

cp log-my-ip.CRONTAB /etc/cron.d/log-my-ip
chmod 644 /etc/cron.d/log-my-ip
chown root.root /etc/cron.d/log-my-ip


