#!/bin/bash
#########################################################
# This script is intended to be run like this:
#
#   curl https://.../bootstrap.sh | sudo bash
#
#########################################################

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Did you leave out sudo?"
	exit
fi

# Clone the Mail-in-a-Box repository if it doesn't exist.
if [ ! -d $HOME/mailinabox ]; then
	echo Installing git . . .
	DEBIAN_FRONTEND=noninteractive apt-get -q -q install -y git < /dev/null
	echo

	echo Downloading Mail-in-a-Box . . .
	git clone \
		--depth 1 \
		https://github.com/mail-in-a-box/mailinabox \
		$HOME/mailinabox \
		< /dev/null 2> /dev/null

	echo
fi

# Change directory to it.
cd $HOME/mailinabox

# Update it.
	echo Updating Mail-in-a-Box to. . .
	git fetch --depth 1 --force --prune origin
	echo
fi

# Start setup script.
setup/start.sh