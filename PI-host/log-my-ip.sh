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

ARGS="$@"

# We need this module installed to run, if it's not installed it will be after you run the script the
# first time :D
_RPM_DEP="dnsutils redhat-lsb-core"
_DEB_DEP="dnsutils"
########################################################################################################
# Configure all your variables here for the script.
########################################################################################################

# If you want to keep the 5 variables below in a config file that you can manage by script, ansible, etc
if [ -f /usr/local/etc/log-my-ip.ini ]; then
	source /usr/local/etc/log-my-ip.ini
else

	# This the branch used to check for updates
	GIT_BRANCH="multi-os"

	# If you want to use the self updating function, change the from NO to YES
	USE_SELFUPATE=NO

	# Telegram (TG) settings.. Token is your private bot key when it was created.  Don't give this out
	TGTOKEN="TELEGRAM TOKEN"				# This is your super secret bot token, keep it private
	TGCHATID="TELEGRAM CHAT ID"				# Send only as the user in a private message
	TGGRPID="TELEGRAM GROUP ID"				# Send to private group "Messages From My Bots"

	# Link to my server that you collect the data
	_MYSERVER="server.acme.com"				# This is the FQDN (leave blank to disable this function)
	# Path on the webserver to the php script
	_SECRETPATH="1234abcdQWERTY"				# This is added to the URL if you want to obfiscate the URL

	# My network range - This is used when searching to make sure we have an IP assigned, it might change later
	# to another method but for now it's what I'm using.  So enter something we can search for like:  172.16.29
	# or 192.168.0, etc
	_my_network_range="192.168.0"

fi

TGURL="https://api.telegram.org/bot${TGTOKEN}/sendMessage"		# This shouldn't really change

# Link to my server that you collect the data
GCURL="http://${_MYSERVER}/<PATH TO YOUR PHP SCRIPT>"

WGETOPTS=" -q --no-check-certificate -O /dev/null"

# Shouldn't need to touch these
hostname="$(hostname)"

intip=""
intipres="$(echo ${intip} | grep -q ${_my_network_range} || echo $?)"

while [ "$intipres" = "1" ]
do
	intip="$(hostname -I|awk '{print $1}')"
	intipres="$(echo ${intip} | grep -q ${_my_network_range} || echo $?)"
	sleep 5
done

mydate="$(date)"

########################################################################################################
# The script starts here - Functions first
########################################################################################################

# Test for dnsutils - we need the dig command
check_for_deps()
{
	which dig &> /dev/null
	_HAVE_DIG=$?
	which lsb_release &> /dev/null
	_HAVE_LSB=$?

	if [ ${_HAVE_DIG} = 1 ] || [ ${_HAVE_LSB} = 1 ]; then
		echo -e "${_RED}Oh SNAP! Looks like you're missing some dependencies.${_RESTORE}"
		if [ ${_HAVE_DIG} = 1 ] then
			echo
			echo -e "Unable to find the ${_RED}dig${_RESTORE} command. Please install dnsutils"
			echo
		fi
		if [ ${_HAVE_LSB} = 1 ] then
			echo
			echo -e "Unable to find the ${_RED}lsb_release${_RESTORE} command. Please install ${_GREEN}redhat-lsb-core${_RESTORE} in CentOS and RHEL"
			echo
		fi
		exit 1
	else
		extip="$(dig +short myip.opendns.com @resolver1.opendns.com)"
	fi
}

# Called from check_for_deps function only.
check_os()
{
	# Checking which flavour of Ubuntu we're using...
	_OSID=`lsb_release -i | awk '{print $3}'`                       # Gives release number, ie: Ubuntu (or RedHatEnterpriseServer)
	_RELEASE=`lsb_release -r | awk '{print $2}'`					# Gives release number, ie: 16.04 (ie: 7.6 for RHEL)
	_CODENAME=`lsb_release -c | awk '{print $2}'`					# Gives release codename, ie: xenial (ie: Maipo for RHEL)
	_CODENAME=$(echo "${_CODENAME}" | tr '[:upper:]' '[:lower:]')	# Ensure response is in lower case 

	case $_OSID in
	    RedHatEnterpriseServer|CentOS|AmazonAMI)
	        _OSTYPE="rpm"
			_PKGINST=`which yum`
			_PKGINSTARGS=" -y install "
			_PKGCHK=`which rpm`
			_PKGCHKARGS=" -qa "
			_DEP=${_RPM_DEP}
	    ;;
	    Ubuntu|Debian)
	        _OSTYPE="pkg"
			_PKGINST=`which apt`
			_PKGINSTARGS=" -y install "
			_PKGCHK=`which dpkg`
			_PKGCHKARGS=" -s "
			_DEP=${_DEB_DEP}
	    ;;
	    *)
	        _OSTYPE="unknown"
	    ;;
	esac

	# uncomment for debugging only.
	# echo "OSID          : ${_OSID}"
	# echo "RELEASE       : ${_RELEASE}"
	# echo "CODENAME      : ${_CODENAME}"
	# echo "OSTYPE        : ${_OSTYPE}"
}


send_message_to_telegram()
{
    tmpfile=$(mktemp /tmp/telebot.XXXXXXX)
    cat > $tmpfile <<EOF
{"chat_id":"$TGGRPID", "parse_mode":"markdown", "text":"*System Update*: $note\n*Date*: ${mydate}\n*Hostname*: $hostname\n*Internal IP*: $intip\n*External IP*: $extip"}
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

self_update() 
{
	# Taken from https://stackoverflow.com/questions/59727780/self-updating-bash-script-from-github

    [ "$UPDATE_GUARD" ] && return
    export UPDATE_GUARD=YES

	_SCRIPT=$(readlink -f "$0")
	_SCRIPTPATH=$(dirname "$_SCRIPT")
	_SCRIPTNAME="$0"
	#ARGS="$@"

    cd $_SCRIPTPATH
    git fetch

    [ -n $(git diff --name-only origin/$GIT_BRANCH | grep $_SCRIPTNAME) ] && {
        echo "Found a new version of me, updating myself..."
        git pull --force
        git checkout $GIT_BRANCH
        git pull --force
        echo "Running the new version..."
        exec "$_SCRIPTNAME" "${ARGS}"

        # Now exit this old instance
        exit 1
    }
    echo "Already the latest version."
}

########################################################################################################
# The script starts here - Functions first
########################################################################################################

# Lets make sure we have some tools we need.  If not then the script will try to install dnsutils, if it 
# fails then exit.
check_for_deps

# Look for updates to the script
if [ "${USE_SELFUPATE}" = "YES" ]; then
	self_update "${ARGS}"
fi

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

	if [ "${ARGS}" = "" ]; then
		note="Manual Update"
	else
		note="${ARGS}"
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
