#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2014 The moOde audio player project / Tim Curtis
#

#
# Environment
#

# NOTE: Make sure these 3 parts are correct!

# Part 1: In-place update date (same as moOde release date)
INPLACE_UPDATE_DATE="2024-MM-DD"
SQLDB=/var/local/www/db/moode-sqlite3.db

# Part 2: List of package updates (cumulative)
PKG_UPDATES=(
moode-player=9.1.3-1moode1
bluez-alsa-utils=4.2.0-2moode1
camillagui=2.1.0-1moode2
chromium
chromium-browser
chromium-common
chromium-sandbox
rpi-chromium-mods
libasound2-plugin-bluez=4.2.0-2moode1
shairport-sync=4.3.4-1moode1
log2ram=1.7.2
librespot=0.5.0-1moode1
libnpupnp13=6.2.0-1moode1
libupnpp16=0.26.7-1moode1
upmpdcli=1.8.16-1moode1
upmpdcli-qobuz=1.8.16-1moode1
upmpdcli-tidal=1.8.16-1moode1
bluez-firmware
firmware-atheros
firmware-brcm80211
firmware-libertas
firmware-linux-free
firmware-misc-nonfree
firmware-realtek
raspi-firmware
)

# Part 3: Kernel package
# NOTE: Kernel install is skipped if KERNEL_NEW_VER=""
KERNEL_NEW_VER="6.6.51"
KERNEL_NEW_PKGVER="1:6.6.51-1+rpt3"

# Initialize step counter
STEP=0
PREDEFINED_STEPS=5
TOTAL_STEPS=$((${#PKG_UPDATES[@]} + $PREDEFINED_STEPS))
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
echo "**  This process updates moOde to the latest release."
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

# 3 - Linux kernel and custom drivers
if [ $KERNEL_NEW_VER != "" ] ; then
	STEP=$((STEP + 1))
	message_log "** Step $STEP-$TOTAL_STEPS: Update Linux kernel to $KERNEL_NEW_VER"
	KERNEL_VER_RUNNING=`uname -r | sed -r "s/([0-9.]*)[+].*/\1/"`
	dpkg --compare-versions $KERNEL_NEW_VER "gt" $KERNEL_VER_RUNNING
	if [ $? -eq 0 ] ; then
		message_log "** - Updating..."
		MODULES_TO_UNINSTALL=`dpkg-query --showformat='${Status} ${Package}\n' --show aloop-* pcm1794a-* rtl88xxau-* |grep -e "^install" | grep -v $KERNEL_NEW_VER | cut -d ' ' -f 4- | tr '\n' ' '`
		if [ "$MODULES_TO_UNINSTALL" != "" ]
		then
			message_log "** - Prepare environment"
			apt -y remove $MODULES_TO_UNINSTALL
		fi
		message_log "** - Install kernel"
		apt -y install "linux-image-rpi-v8=$KERNEL_NEW_PKGVER" "linux-image-rpi-2712=$KERNEL_NEW_PKGVER"
		message_log "** - Install custom drivers"
		apt-get install -y "aloop-$KERNEL_NEW_VER" "pcm1794a-$KERNEL_NEW_VER"
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

# 4 Install package updates
for PACKAGE in "${PKG_UPDATES[@]}"
do
	STEP=$((STEP + 1))
	message_log "** Step $STEP-$TOTAL_STEPS: Install $PACKAGE"
	if [ $(echo $PACKAGE | cut -d "=" -f 1) = "shairport-sync" ] || [ $(echo $PACKAGE | cut -d "=" -f 1) = "upmpdcli" ]; then
		apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install $PACKAGE
	else
		apt -y install $PACKAGE
	fi
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
# Remove downloaded archive files
apt-get clean

# NOTE: Fixes and specials go here
# Add symlink missing from r905 postinstall
[ ! -e /var/lib/mpd/music/NVME ] &&  ln -s /mnt/NVME /var/lib/mpd/music/NVME

# 7 - Flush cached disk writes
STEP=$((STEP + 1))
message_log "** Step $STEP-$TOTAL_STEPS: Sync changes to disk"
message_log "Finish $INPLACE_UPDATE_DATE update for moOde $CURRENT_REL_LONG"
sync

cd ~/
