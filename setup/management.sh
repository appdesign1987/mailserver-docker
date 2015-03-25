#!/bin/bash

source setup/functions.sh

apt_install python3-flask links duplicity libyaml-dev python3-dnspython python3-dateutil
hide_output pip3 install rtyaml

# Create a backup directory and a random key for encrypting backups.
mkdir -p $STORAGE_ROOT/backup
if [ ! -f $STORAGE_ROOT/backup/secret_key.txt ]; then
	$(umask 077; openssl rand -base64 2048 > $STORAGE_ROOT/backup/secret_key.txt)
fi

# Link the management server daemon into a well known location.
rm -f /usr/local/bin/mailinabox-daemon
ln -s `pwd`/management/daemon.py /usr/local/bin/mailinabox-daemon

# Create an init script to start the management daemon and keep it
# running after a reboot.
rm -f /etc/init.d/mailinabox
ln -s $(pwd)/conf/management-initscript /etc/init.d/mailinabox
hide_output update-rc.d mailinabox defaults

# Perform a daily backup.
cat > /etc/cron.daily/mailinabox-backup << EOF;
#!/bin/bash
# Mail-in-a-Box --- Do not edit / will be overwritten on update.
# Perform a backup.
$(pwd)/management/backup.py
EOF
chmod +x /etc/cron.daily/mailinabox-backup

# Start it. Remove the api key file first so that start.sh
# can wait for it to be created to know that the management
# server is ready.
rm -f /var/lib/mailinabox/api.key
restart_service mailinabox
