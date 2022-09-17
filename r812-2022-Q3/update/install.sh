#!/bin/bash
#
# moOde audio player (C) 2014 Tim Curtis
# http://moodeaudio.org
#
# This Program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3, or (at your option)
# any later version.
#
# This Program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

#
# Environment
#

STEP=0
CURRENT_REL_LONG="8.1.2 2022-07-08"
CURRENT_REL_SHORT="r812"
INPLACE_UPDATE_DATE="2022-09-16"
SQLDB=/var/local/www/db/moode-sqlite3.db
NUM_PKG_UPDATES=4
PKG_UPDATES=(
alsa-cdsp=1.2.0-1moode1
camillagui=1.0.0-1moode3
librespot=0.4.2-1moode1
moode-player=8.2.0-1moode1~pre2
)
TOTAL_STEPS=$(($NUM_PKG_UPDATES + 6))

#
# Functions
#

cancel_update () {
	if [ $# -gt 0 ] ; then
		message_log "$1"
	fi
	message_log "** Exiting update"
	exit 1
}

message_log () {
	echo "$1"
	TIME=$(date +'%Y%m%d %H%M%S')
	echo "$TIME updater: $1" >> /var/log/moode.log
	echo "$TIME updater: $1" >> /var/local/www/update-$CURRENT_REL_SHORT.log
}

#
# Main
#

echo
echo "****************************************************************"
echo "**"
echo "**  This package updates moOde $CURRENT_REL_LONG and contains"
echo "**  important bug fixes and improvements."
echo "**"
echo "**  WARNING: This update is only supported on unmodfied builds"
echo "**  and ISO images of moOde $CURRENT_REL_LONG"
echo "**"
echo "**  NOTE: Reboot after the update completes."
echo "**"
echo "****************************************************************"
echo

WD=/var/local/www
cd $WD
truncate ./update-$CURRENT_REL_SHORT.log --size 0
message_log "Start $INPLACE_UPDATE_DATE update for moOde $CURRENT_REL_LONG"

message_log "** Release check"
REL=$(moodeutl --mooderel | tr -d '\n')
if [ "$REL" != "$CURRENT_REL_LONG" ] ; then
	cancel_update "** Error: This update will only run on moOde $CURRENT_REL_LONG"
fi

# 1 - Update package list
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Update package list"
apt update

# 2 - Remove package hold
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Remove package hold"
moode-apt-mark unhold

# 3 - Install timesyncd so date will be current otherwise requests to the repos will fail
# NOTE: 32-bit Bullseye did not contain the timesyncd package
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Install timesyncd"
apt install -y systemd-timesyncd

# 4 - Install package updates
for PACKAGE in "${PKG_UPDATES[@]}"
do
  STEP=$((STEP + 1))
  message_log "** Step $STEP-$TOTAL_STEPS: Install $PACKAGE"
  apt install -y $PACKAGE
done

# 5 - Apply package hold
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Apply package hold"
moode-apt-mark hold

# 6 - Post-install cleanup
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Post-install cleanup"
# Update theme background color in var/www/header.php
THEME_NAME=$(sqlite3 $SQLDB "SELECT value FROM cfg_system WHERE param='themename'")
THEME_COLOR=$(sqlite3 $SQLDB "SELECT bg_color FROM cfg_theme WHERE theme_name='$THEME_NAME'")
sed -i '/<meta name="theme-color" content=/c\ \t<meta name="theme-color" content="rgb($THEME_COLOR)">' /var/www/header.php
# Cleanup from kernel update (if any)
rm -rf /lib/modules.bak
rm -rf /boot.bak
apt-get clean
# NOTE: Fixes and specials go here
#

# 7 - Flush cached disk writes
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Sync changes to disk"
sync

# All done
message_log "Finish $INPLACE_UPDATE_DATE update for moOde $CURRENT_REL_LONG"

cd ~/
