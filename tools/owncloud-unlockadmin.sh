#!/bin/bash
#
# This script will give you administrative access to the ownCloud
# instance running here.
#
# Run this at your own risk. This is for testing & experimentation
# purpopses only. After this point you are on your own.

source /etc/mailinabox.conf # load global vars

ADMIN=$(./mail.py user admins | head -n 1)
test -z "$1" || ADMIN=$1 

echo I am going to unlock admin features for $ADMIN.
echo You can provide another user to unlock as the first argument of this script.
echo 
echo WARNING: you could break mail-in-a-box when fiddling around with owncloud\'s admin interface
echo If in doubt, press CTRL-C to cancel.
echo 
echo Press enter to continue.
read

sqlite3 $STORAGE_ROOT/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_group_user VALUES ('admin', '$ADMIN')" && echo Done.
