# IP Logging for Pi's

## FORK ME!

If you intend to use this, please be sure to fork this to your account. I may make changes to the script in the future and this could break your usage if you're cloning my repo. 
----

## What?

There are two parts to this project. The main part is the script `PI-host/log-my-ip.sh`, this will send messages to you on telegram and/or connect to the simple php script `Simple-Serverside/log-ips.php` and dump some basic info in CSV format. 

## Why?

I have a number of headless PI's distributed about for different purposes and like to know they're still alive or if they reboot. Sure, there are any number of monitoring solutions for these, but I wanted more simple. Mostly my devices have reserved IP's so I know what they will be but sometimes I have devices I travel with that are headless and will get dynamic IP's so I want a way to know what that IP is. This script will do that for me.

## How?

Firstly, these scripts work for me and may or may not work for you.  The script `PI-host/log-my-ip.sh` has 2 functions, one is to connect to webserver and dump some CSV and/or send that info via Telegram to me. The `Simple-Serverside` runs on a small server listening for connections from the `log-my-ip.sh` script which is just pushing some data to the php script, this is then logged in a CSV format.  Mostly this is just for some historical value, I don't currently use this for anything specific but I suppose you could. This really doesn't work super well as I've not put much effort all into this, for me the Telegram notifications are far more useful.

# Important - Dependencies required

The script doesn't rely on too much, however you must have the following installed for it to operate:

* curl
* lsb_release (out of box for Ubuntu, but needs `redhat-lsb-core` for CentOS/RHEL)
* dig (install `dnsutils` on DEB systems and `bind-utils` on RPM systems)

---

# More information

## PI-host/

See the [README.md](PI-host/README.md) for more usage information.

---
