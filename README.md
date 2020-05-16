# IP Logging for Pi's

Firstly, these scripts work for me and may or may not work for you.  Basically, the php script in Simple-Serverside runs on a small server listening for connections
from the log-my-ip.sh script which is just pushing some data to the php script, this is then logged in a CSV format.  Mostly this is just for some historical value,
I don't currently use this for anything specific but I suppose you could.

---

## PI-host/

See the [README.md](PI-host/README.md) for more information.

## Simple-Serverside/ 

### log-ips.php

#### _Currently this isn't really working._

This script runs on the web server and is hit by a POST to store the info. Edit the PHP and change the filename variable if you want a different logging file.

