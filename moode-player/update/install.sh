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

INPLACE_UPDATE_DATE="2022-12-27"
SQLDB=/var/local/www/db/moode-sqlite3.db

PKG_UPDATES=(
moode-player=8.2.4-1moode1
mpd=0.23.11-1moode1
camilladsp=1.0.3-1moode1
camillagui=1.0.1-1moode1
python3-camilladsp-plot=1.0.2-1moode1
shairport-sync=4.1.1-1moode1
)

STEP=0
TOTAL_STEPS=$((${#PKG_UPDATES[@]} + 6))

# Package with kernel to use
KERNEL_PKG_VERSION="1:1.20221104-1"
# Kernel version in the package raspberrypi-kernel-$KERNEL_PKG_VERSION
KERNEL_VERSION="5.15.76"

if [ $KERNEL_VERSION != "" ] ; then
	TOTAL_STEPS=$((TOTAL_STEPS + 1))
fi

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
	echo "$TIME updater: $1" >> /var/local/www/update-moode.log
}

#
# Main
#

echo
echo "**********************************************************"
echo "**"
echo "**  This package updates moOde to the latest release and"
echo "**  contains important improvements and bug fixes."
echo "**"
echo "**  NOTE: This update is only supported on unmodified"
echo "**  moOde builds and ISO images"
echo "**"
echo "**  Reboot after the update completes."
echo "**"
echo "**********************************************************"
echo

WD=/var/local/www
cd $WD
truncate ./update-moode.log --size 0
message_log "Start $INPLACE_UPDATE_DATE update for moOde"

# 1 - Remove package hold
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Remove package hold"
moode-apt-mark unhold

# 2 - Update package list
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Update package list"
apt update

# 3 - Install timesyncd so date will be current otherwise requests to the repos will fail
# NOTE: 32-bit Bullseye did not contain the timesyncd package
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Install timesyncd"
apt -y install systemd-timesyncd

# 4 - Linux kernel and custom drivers
if [ $KERNEL_VERSION != "" ] ; then
	STEP=$((STEP + 1))
	message_log "** Step $STEP-$TOTAL_STEPS: Update to Linux kernel $KERNEL_VERSION (raspberrypi-kernel-$KERNEL_PKG_VERSION)"
	KERNEL_VER_RUNNING=`uname -r | sed -r "s/([0-9.]*)[-].*/\1/"`
	dpkg --compare-versions $KERNEL_VERSION "gt" $KERNEL_VER_RUNNING
	if [ $? -eq 0 ]
	then
		message_log "** - Updating kernel from $KERNEL_VER_RUNNING to $KERNEL_VERSION."
		MODULES_TO_UNINSTALL=`dpkg-query --showformat='${Status} ${Package}\n' --show pcm1794a-* aloop-* ax88179-* rtl88xxau-* |grep -e "^install" | grep -v $KERNEL_VERSION | cut -d ' ' -f 4- | tr '\n' ' '`
		if [ "$MODULES_TO_UNINSTALL" != "" ]
		then
			message_log "** - Removing existing custom drivers: $MODULES_TO_UNINSTALL"
			apt -y remove $MODULES_TO_UNINSTALL
		fi

		# Ensure rpi-update runs NOTE: Is this needed anymore since we are not using rpi-update ?
		rm -f /boot/.firmware_revision
		# Install kernel
		apt -y install "raspberrypi-kernel=$KERNEL_PKG_VERSION"
		# Install bootloader
		apt -y install "raspberrypi-bootloader=$KERNEL_PKG_VERSION"

		# Install matching kernel drivers (these should exist in CS as part of prepping for the update)
		message_log "** - Installing matching custom drivers for kernel $KERNEL_VERSION"
		apt-get install -y "aloop-$KERNEL_VERSION" "pcm1794a-$KERNEL_VERSION" "ax88179-$KERNEL_VERSION" "rtl88xxau-$KERNEL_VERSION"
	else
		dpkg --compare-versions $KERNEL_VER_RUNNING "gt" $KERNEL_VERSION
		if [ $? -eq 0 ]
		then
			message_log "** - Warning: Running newer kernel then supported for this release (manual upgrade?)."
		else
			message_log "**- No kernel upgrade required"
		fi
	fi
fi

# 5 Install package updates
for PACKAGE in "${PKG_UPDATES[@]}"
do
  STEP=$((STEP + 1))
  message_log "** Step $STEP-$TOTAL_STEPS: Install $PACKAGE"
  if [ $(echo $PACKAGE | cut -d "=" -f 1) = "shairport-sync" ]; then
	  apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install $PACKAGE
  else
	  apt -y install $PACKAGE
   fi
done

# 6 - Apply package hold
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Apply package hold"
moode-apt-mark hold

# 7 - Post-install cleanup
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

# 8 - Flush cached disk writes
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Sync changes to disk"
sync

# All done
message_log "Finish $INPLACE_UPDATE_DATE update for moOde $CURRENT_REL_LONG"

cd ~/
