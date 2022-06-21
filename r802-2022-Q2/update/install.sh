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

# Step counter and SQL database
STEP=0
SQLDB=/var/local/www/db/moode-sqlite3.db

# Current moOde release
CURRENT_REL_LONG="8.0.2 2022-03-25"
CURRENT_REL_SHORT="r802"

# In-place update date
INPLACE_UPDATE_DATE="2022-06-21"

# Packages to be updated
PKGS=(
moode-player=8.1.0-1moode1~pre4
librespot=0.4.1-1moode1
camilladsp=1.0.0-1moode1
python3-camilladsp=1.0.0-1moode1
python3-camilladsp-plot=1.0.0-1moode1
camillagui=1.0.0-1moode2
chromium-browser )

# Linux kernel
# NOTE: Set to "" if kernel is not being installed
KERNEL_VERSION="5.15.32"
KERNEL_HASH="a54fe46c85fd4a2155f2282454bee3c2a3d5b5eb"

# Number of steps
TOTAL_STEPS=12

if [ $KERNEL_VERSION != "" ] ; then
	TOTAL_STEPS=$((TOTAL_STEPS + 1))
fi

#
# Functions
#

read_yn_input () {
	while true; do
	    read -p "$1" YN
	    case $YN in
	        [y] ) break;;
	        [n] ) break;;
	        * ) echo "** Valid entries are y|n";;
	    esac
	done
}

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

# Establish working directory
WD=/var/local/www
cd $WD

# Initialize log file
truncate ./update-$CURRENT_REL_SHORT.log --size 0

# Start and basic checks
# NOTE: Disk space check (> 512MB) is done in System Config before submitting the update

message_log "Start $INPLACE_UPDATE_DATE update for moOde $CURRENT_REL_LONG"

message_log "** Release check"
REL=$(moodeutl --mooderel | tr -d '\n')

if [ $REL != $CURRENT_REL_LONG ] ; then
	cancel_update "** Error: This update will only run on moOde $CURRENT_REL_LONG"
fi

# NOTE: Use of squashed file system is deprecated
echo "** File system check"
if [ -f /var/local/moode.sqsh ] ; then
	cancel_update "** Error: This update will only run on un-squashed /var/www"
fi

# Proceed with the update

# Update package list
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Update package list"
apt update

# Linux kernel and custom drivers
if [ $KERNEL_VERSION != "" ] ; then
	STEP=$((STEP + 1))
	message_log "** Step $STEP-$TOTAL_STEPS: Update to Linux kernel $KERNEL_VERSION"

	# Remove custom drivers for current kernel (they may not exist if user has bumped kernel)
	KERNEL=$(basename `ls -d /lib/modules/*-v7l+` | sed -r "s/([0-9.]*)[-].*/\1/")
	message_log "** - Kernel $KERNEL detected, removing existing custom drivers"
	apt-get remove -y "aloop-$KERNEL" "pcm1794a-$KERNEL" "ax88179-$KERNEL" "rtl88xxau-$KERNEL"

	message_log "** - Installing kernel $KERNEL_VERSION"
	# Ensure rpi-update runs
	rm /boot/.firmware_revision
	# Install kernel
	echo "y" | sudo PRUNE_MODULES=1 rpi-update $KERNEL_HASH

	# Install matching kernel drivers (these should exist in CS as part of prepping for the update)
	KERNEL=$(basename `ls -d /lib/modules/*-v7l+` | sed -r "s/([0-9.]*)[-].*/\1/")
	message_log "** - Kernel $KERNEL detected, installing matching custom drivers"
	apt-get install -y "aloop-$KERNEL" "pcm1794a-$KERNEL" "ax88179-$KERNEL" "rtl88xxau-$KERNEL"
fi

# Remove package hold
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Remove package hold"
moode-apt-mark unhold

# Install packages
for PKG in "${PKGS[@]}"
do
  STEP=$((STEP + 1))
  message_log "** Step $STEP-$TOTAL_STEPS: Install $PKG"
  apt install -y $PKG
done

# Apply package hold
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Apply package hold"
moode-apt-mark hold

# Post-install cleanup
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
# For missing sed in the on_upgrade() section of r801 moode-player package
#sed -i -e 's/[#]TemporaryTimeout[ ]=[ ].*/TemporaryTimeout = 90/' /etc/bluetooth/main.conf

# Flush cached disk writes
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Sync changes to disk"
sync

# All done
message_log "Finish $INPLACE_UPDATE_DATE update for moOde $CURRENT_REL_LONG"

cd ~/
