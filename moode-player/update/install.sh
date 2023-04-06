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

# NOTE: Make sure these three parts are correct!

# Part 1: In-place update date (same as moOde release date)
INPLACE_UPDATE_DATE="2023-MM-DD"
SQLDB=/var/local/www/db/moode-sqlite3.db

# Part 2: List of package updates (cumulative)
PKG_UPDATES=(
moode-player=8.3.1-1moode1
bluez-alsa=4.0.0-2moode1
bluez-alsa-utils=4.0.0-2moode1
libasound2-plugin-bluez=4.0.0-2moode1
camilladsp=1.0.3-1moode1
camillagui=1.0.1-1moode1
python3-camilladsp-plot=1.0.2-1moode1
mpd2cdspvolume=0.3.1-1moode1
mpd=0.23.12-1moode1
python3-mpd2=3.0.5
shairport-sync=4.1.1-1moode1
python3-libupnpp=0.21.0-1moode1
libnpupnp2=5.0.1-1moode1
libupnpp7=0.22.4-1moode1
upmpdcli=1.7.7-1moode1
)

# Part 3: New kernel package (set to "" if moOde release does not include new kernel)
#KERNEL_NEW_VER="5.15.84"
#KERNEL_NEW_PKGVER="1:1.20230106-1"
#KERNEL_NEW_VER="5.15.84"
#KERNEL_NEW_PKGVER="1:1.20230306-1"
#KERNEL_NEW_VER="6.1.19"
#KERNEL_NEW_PKGVER="1:1.20230317-1"
KERNEL_NEW_VER="6.1.21"
KERNEL_NEW_PKGVER="1:1.20230405-1"

# Initialize the step counter
STEP=0
TOTAL_STEPS=$((${#PKG_UPDATES[@]} + 6))
if [ $KERNEL_NEW_VER != "" ] ; then
	TOTAL_STEPS=$((TOTAL_STEPS + 1))
fi

# Log files
MOODE_LOG="/var/log/moode.log"
UPDATER_LOG="/var/log/moode_update.log"

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
	echo "$TIME updater: $1" >> $MOODE_LOG
	echo "$TIME updater: $1" >> $UPDATER_LOG
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
truncate $UPDATER_LOG --size 0
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
# NOTE: It should already be present in 2023 RaspiOS Bullseye 32/64-bit releases
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Install timesyncd"
apt -y install systemd-timesyncd

# 4 - Linux kernel and custom drivers
# NOTE: Starting with kernel 6.1.y the custom Allo ASIX ax88179 driver is no longer installed
# due to build breakage in the driver which has been unmaintained since mid-2022. Instead the
# stock ASIX ax88179 driver is used.
if [ $KERNEL_NEW_VER != "" ] ; then
	STEP=$((STEP + 1))
	message_log "** Step $STEP-$TOTAL_STEPS: Update Linux kernel to $KERNEL_NEW_VER"
	KERNEL_VER_RUNNING=`uname -r | sed -r "s/([0-9.]*)[-].*/\1/"`
	dpkg --compare-versions $KERNEL_NEW_VER "gt" $KERNEL_VER_RUNNING
	if [ $? -eq 0 ] ; then
		message_log "** - Updating..."
		MODULES_TO_UNINSTALL=`dpkg-query --showformat='${Status} ${Package}\n' --show pcm1794a-* aloop-* ax88179-* rtl88xxau-* |grep -e "^install" | grep -v $KERNEL_NEW_VER | cut -d ' ' -f 4- | tr '\n' ' '`
		if [ "$MODULES_TO_UNINSTALL" != "" ]
		then
			message_log "** - Prepare environment"
			apt -y remove $MODULES_TO_UNINSTALL
		fi
		message_log "** - Install kernel"
		apt -y install "raspberrypi-kernel=$KERNEL_NEW_PKGVER"
		message_log "** - Install bootloader"
		apt -y install "raspberrypi-bootloader=$KERNEL_NEW_PKGVER"
		message_log "** - Install custom drivers"
		apt-get install -y "aloop-$KERNEL_NEW_VER" "pcm1794a-$KERNEL_NEW_VER" "rtl88xxau-$KERNEL_NEW_VER"
		message_log "** - Complete"
	else
		dpkg --compare-versions $KERNEL_VER_RUNNING "gt" $KERNEL_NEW_VER
		if [ $? -eq 0 ]
		then
			message_log "** - Kernel is newer, update cannot be performed"
		else
			message_log "** - Kernel is current, no update required"
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
message_log "Finish $INPLACE_UPDATE_DATE update for moOde $CURRENT_REL_LONG"
sync

cd ~/
