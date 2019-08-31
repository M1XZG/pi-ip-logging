#!/usr/bin/env bash
########################################################################################################
# Author            : "Robert McKenzie" <rmckenzi@rpmdp.com>
# Script Name       : log-my-ip.sh
# Description       : This script is written to send me a message on Telegram at the time of a
#					: reboot which includes the hostname, internal and external IP's and a reason
#					: for the reboot if one is provided.  It also sends commands to a linux server
#					: online where I collect the same info into a csv file, not sure what I'll do
#					: with this going forward but it's there, being captured, just incase.
#
# Date              : 16/07/2019
#
# Worth while notes :
# https://kvz.io/blog/2013/11/21/bash-best-practices/
#
########################################################################################################
#set -x
# Force script to exit on any error
#set -o errexit
# Prevents pipe errors and false true responses.
#set -o pipefail
#
########################################################################################################
# Setting up for some colours, use the ${_RESTORE} after a colour to return to normal
# black and white kinda thing.

_RESTORE='\033[0m'
_BOLD=$(tput bold)
_RED='\033[00;31m'
_GREEN='\033[00;32m'
_YELLOW='\033[00;33m'
_BLUE='\033[00;34m'
_PURPLE='\033[00;35m'
_WHITE='\033[01;37m'

########################################################################################################
#
# Uncomment this section if you wish to ensure the script is only run as a specific user
# root is the default, but this could be any valid user.
#
#		if [[ $EUID -ne 0 ]]; then
#       	echo -e "${_BOLD}Script must be run as user:${_RESTORE} ${_RED}root${_RESTORE}"
#           exit -1
#		fi
########################################################################################################
# Set a path so we know we can find what we require to run.
PATH=${PATH}:/usr/sbin:/usr/bin:/sbin:/bin

# We need this module installed to run, if it's not installed it will be after you run the script the
# first time :D
DEP="dnsutils"

########################################################################################################
# Configure all your variables here for the script.
########################################################################################################

# Telegram (TG) settings.. Token is your private bot key when it was created.  Don't give this out
TGTOKEN=""														# This is your super secret bot token, keep it private (leave blank to disable telegram function)
TGCHATID="TELEGRAM CHAT ID"										# Send only as the user in a private message
TGGRPID="TELEGRAM GROUP ID"										# Send to private group "Messages From My Bots"
TGURL="https://api.telegram.org/bot${TGTOKEN}/sendMessage"		# This shouldn't really change

# Link to my server that you collect the data
_MYSERVER=""													# This is the FQDN (leave blank to disable this function)
GCURL="http://${_MYSERVER}/<PATH TO YOUR PHP SCRIPT>"

WGETOPTS=" -q --no-check-certificate -O /dev/null"

# Shouldn't need to touch these
hostname="$(hostname)"
intip="$(hostname -I|awk '{print $1}')"
mydate="$(date)"

########################################################################################################
# The script starts here - Functions first
########################################################################################################

# Test for dnsutils - we need the dig command
check_for_deps()
{
	dpkg -s ${DEP}  | grep Status | grep -q "Status: install ok installed" &> /dev/null
	CMDRES=$?

	if [ ${CMDRES} = 1 ]; then
		sudo apt install ${DEP} -y || { echo -e "${_RED}Oh SNAP, something went wrong.  I couldn't install the dnsutils package${_RESTORE}."; exit 1; }
		extip="$(dig +short myip.opendns.com @resolver1.opendns.com)"
	else
		extip="$(dig +short myip.opendns.com @resolver1.opendns.com)"
	fi
}

send_message_to_telegram()
{
    tmpfile=$(mktemp /tmp/telebot.XXXXXXX)
    cat > $tmpfile <<EOF
{"chat_id":"$TGGRPID", "parse_mode":"markdown", "text":"*System Reboot Update*\n*Date*: ${mydate}\n*Hostname*: $hostname\n*Internal IP*: $intip\n*External IP*: $extip"}
EOF
    curl -k --header 'Content-Type: application/json' \
        --data-binary @${tmpfile} \
        --request POST ${TGURL}
    rm -f $tmpfile
}

# This function will send our reboot message to a server where you have a script running to receive it.
send_message_to_server()
{
	PING=1
	while [ ${PING} -gt 0 ]
	do
		ping -c 5 ${_MYSERVER} &> /dev/null
		PING=$?
	done
	wget ${WGETOPTS} ${GCURL} --post-data="hostname=${hostname}&intip=${intip}&extip=${extip}&mydate=${mydate}&note=${note}"
	if [ "${note}" = "REBOOT" ];then
		send_message
	fi
}

########################################################################################################
# The script starts here - Functions first
########################################################################################################

# Lets make sure we have some tools we need.  If not then the script will try to install dnsutils, if it 
# fails then exit.
check_for_deps

# Waiting for network .. this is needed to make sure the pi has network before we actually run through
# the rest of the script.  This will loop forever until network is found.  Shouldn't cause any issues
# but don't run this on a pi you don't intend to have network connected.
if [ "${_MYSERVER}" = "" ]; then
	echo -e "\n\t${_RED}You don't have _MYSERVER set, I'm going to exit now${_RESTORE}\n"
	exit 1
else
	PING=1
	while [ ${PING} -gt 0 ]
	do
		ping -c 5 ${_MYSERVER} &> /dev/null
		PING=$?
	done

	if [ "$1" = "" ]; then
		note="Manual"
	else
		note="$1"
	fi
fi

# If you don't have TGTOKEN set then this will be skipped.
if [ "${TGTOKEN}" = "" ];then
	# If you don't have TGTOKEN configured then this is skipped.
	echo -e "\n\t${_RED}You don't have TGTOKEN set, so I won't send alerts to Telegram${_RESTORE}\n"
else
	send_message_to_telegram
fi

# If you don't have GCURL set then this will be skipped.
if [ "${_MYSERVER}" = "" ];then
	# If you don't have _MYSERVER configured then this is skipped.
	echo -e "\n\t${_RED}You don't have _MYSERVER set, I'm going to exit now${_RESTORE}\n"
	exit 1
else
	send_message_to_server
fi
