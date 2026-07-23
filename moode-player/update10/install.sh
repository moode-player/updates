#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2014 The moOde audio player project / Tim Curtis
#

#
# Environment
#

# Part 1: In-place update date (same as moOde release date)
INPLACE_UPDATE_DATE="2026-07-22"
MOODE_RELEASE="10.3.1-1moode1"
SQLDB=/var/local/www/db/moode-sqlite3.db

# Part 2: List of package updates (cumulative)
PKG_UPDATES=(
moode-player=$MOODE_RELEASE
mpd=0.24.12-1moode1
squeezelite=2.0.0-1541+git20250609.72e1fd8-1moode1
caps=0.9.26-1moode1
camilladsp=4.1.3-1moode1
camillagui=4.1.0-1moode1
python3-camilladsp-plot=4.1.0-1moode1
python3-camilladsp=4.0.0-1moode1
alsa-cdsp=1.2.0-3moode1
upmpdcli=1.9.17-1moode1
upmpdcli-tidal=1.9.17-1moode1
upmpdcli-qobuz=1.9.17-1moode1
libnpupnp13=6.2.3-1moode1
libupnpp17=1.0.3-1moode1
python3-libupnpp=0.26.1-1moode1
peppy-meter=2026.7.20-1moode1
)

# Part 3: Kernel package
# NOTE: Kernel install is skipped if KERNEL_NEW_VER=""
KERNEL_NEW_VER="6.18.34"
KERNEL_NEW_PKGVER="1:6.18.34-1+rpt1"

# Initialize step counter
STEP=0
PREDEFINED_STEPS=6
TOTAL_STEPS=$((${#PKG_UPDATES[@]} + $PREDEFINED_STEPS))
if [ $KERNEL_NEW_VER != "" ]; then
	TOTAL_STEPS=$((TOTAL_STEPS + 1))
fi
# Zero pad
if [ $TOTAL_STEPS -lt 10 ]; then
	TOTAL_STEPS="0"$TOTAL_STEPS
fi

# Log files
MOODE_LOG="/var/log/moode.log"
UPDATER_LOG="/var/log/moode_update.log"

#
# Functions
#

cancel_update () {
	if [ $# -gt 0 ]; then
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

pad_step () {
	if [ $1 -lt 10 ]; then
		echo "0"$1
	else
		echo $1
	fi
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

# 1 - Get latest moode-apt-mark
STEP=$((STEP + 1))
message_log "** Step $(pad_step $STEP)-$TOTAL_STEPS: Get latest moode-apt-mark"
wget -q https://raw.githubusercontent.com/moode-player/pkgbuild/refs/heads/main/packages/moode-player/moode-apt-mark -O /usr/local/bin/moode-apt-mark
if [ $? -ne 0 ]; then
	cancel_update "** Step failed"
fi
# 2 - Remove package hold
STEP=$((STEP + 1))
message_log "** Step $(pad_step $STEP)-$TOTAL_STEPS: Remove package hold"
moode-apt-mark unhold
if [ $? -ne 0 ]; then
	cancel_update "** Step failed"
fi

# 3 - Update package list
STEP=$((STEP + 1))
message_log "** Step $(pad_step $STEP)-$TOTAL_STEPS: Update package list"
apt update
if [ $? -ne 0 ]; then
	cancel_update "** Step failed"
fi

# 4 - Linux kernel
if [ $KERNEL_NEW_VER != "" ]; then
	STEP=$((STEP + 1))
	message_log "** Step $(pad_step $STEP)-$TOTAL_STEPS: Update Linux kernel to $KERNEL_NEW_VER"
	KERNEL_VER_RUNNING=`uname -r | sed -r "s/([0-9.]*)[+].*/\1/"`
	dpkg --compare-versions $KERNEL_NEW_VER "gt" $KERNEL_VER_RUNNING
	if [ $? -eq 0 ]; then
		message_log "** - Checking Raspberry Pi kernel repository"
		apt -s install "linux-image-rpi-v8=$KERNEL_NEW_PKGVER"
		if [ $? -ne 0 ]; then
			message_log "** - Kernel not found, update skipped"
		else
			message_log "** - Kernel found, updating..."
			message_log "** - Patch initramfs.conf"
			sed -i 's/^MODULES.*/MODULES=most/' /etc/initramfs-tools/initramfs.conf
			if [ $? -ne 0 ]; then
				cancel_update "** Step failed"
			fi
			message_log "** - Install new kernel"
			apt -y install "linux-image-rpi-v8=$KERNEL_NEW_PKGVER" "linux-image-rpi-2712=$KERNEL_NEW_PKGVER"
			if [ $? -ne 0 ]; then
				cancel_update "** Step failed"
			fi
			message_log "** - Complete"
		fi
	else
		dpkg --compare-versions $KERNEL_VER_RUNNING "gt" $KERNEL_NEW_VER
		if [ $? -eq 0 ]
		then
			message_log "** - Installed Kernel is newer, update skipped"
		else
			message_log "** - Installed Kernel is current, no update required"
		fi
	fi
fi

# 5 Install package updates
#
# TODO: First check if package is already current
#
for PACKAGE in "${PKG_UPDATES[@]}"
do
	STEP=$((STEP + 1))
	message_log "** Step $(pad_step $STEP)-$TOTAL_STEPS: Install $PACKAGE"
	PKG_NAME=$(echo $PACKAGE | cut -d "=" -f 1)
	if [ $PKG_NAME = "moode-player" ]; then
		apt -y -o Dpkg::Options::="--force-confnew" install $PACKAGE
		if [ $? -ne 0 ]; then
			cancel_update "** Step failed"
		fi
	elif [ $PKG_NAME = "shairport-sync" ] || \
		[ $PKG_NAME = "upmpdcli" ] || \
		[ $PKG_NAME = "mpd" ]; then
		apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install $PACKAGE
		if [ $? -ne 0 ]; then
			cancel_update "** Step failed"
		fi
	elif [ $PKG_NAME = "bluez-alsa-utils" ] || [ $PKG_NAME = "libasound2-plugin-bluez" ]; then
		dpkg --compare-versions $(dpkg-query -W -f='${Version}' $PKG_NAME) gt "4.2.0-2moode1"
		if [ $? -eq 0 ]; then
			message_log "** - Installed package is newer, update skipped"
		else
			apt -y install $PACKAGE
			if [ $? -ne 0 ]; then
				cancel_update "** Step failed"
			fi
		fi
	elif [ $PKG_NAME = "caps" ]; then
		apt -y install $PACKAGE --allow-downgrades
		if [ $? -ne 0 ]; then
			cancel_update "** Step failed"
		fi
	elif [ $PKG_NAME = "peppy-meter" ]; then
		# Save the conf file updated via the earlier moode-player package install
		cp /etc/peppymeter/config.txt /etc/peppymeter/config.txt.save
		# This install will overwrite the conf (--force-confdef, --force-confold don't work for this package)
		apt -y install $PACKAGE
		if [ $? -ne 0 ]; then
			cancel_update "** Step failed"
		else
			# Restore the correct conf
			mv /etc/peppymeter/config.txt.save /etc/peppymeter/config.txt
		fi
	else
		apt -y install $PACKAGE
		if [ $? -ne 0 ]; then
			cancel_update "** Step failed"
		fi
	fi
done

# 6 - Apply package hold
STEP=$((STEP + 1))
message_log "** Step $(pad_step $STEP)-$TOTAL_STEPS: Apply package hold"
moode-apt-mark hold
if [ $? -ne 0 ]; then
	cancel_update "** Step failed"
fi

# 7 - Post-install cleanup
STEP=$((STEP + 1))
message_log "** Step $(pad_step $STEP)-$TOTAL_STEPS: Post-install cleanup"
# Restore theme background color in var/www/header.php
message_log "** - Restore theme color"
THEME_NAME=$(sqlite3 $SQLDB "SELECT value FROM cfg_system WHERE param='themename'")
THEME_COLOR=$(sqlite3 $SQLDB "SELECT bg_color FROM cfg_theme WHERE theme_name='$THEME_NAME'")
sed -i '/<meta name="theme-color" content=/c\ \t<meta name="theme-color" content="rgb($THEME_COLOR)">' /var/www/header.php
if [ $? -ne 0 ]; then
	cancel_update "** Step failed"
fi
# Remove downloaded APT archive files
message_log "** - Remove unneeded APT archive files"
apt-get clean
if [ $? -ne 0 ]; then
	cancel_update "** Step failed"
fi
# NOTE: Fixes and specials go here
# Overwrite Squeezelite package file with moode file
wget -q https://raw.githubusercontent.com/moode-player/moode/develop/lib/systemd/system/squeezelite.overwrite.service -O /lib/systemd/system/squeezelite.service
systemctl disable squeezelite

# 8 - Flush cached disk writes
STEP=$((STEP + 1))
message_log "** Step $(pad_step $STEP)-$TOTAL_STEPS: Sync changes to disk"
message_log "Finish $INPLACE_UPDATE_DATE update for moOde $CURRENT_REL_LONG"
sync
if [ $? -ne 0 ]; then
	cancel_update "** Step failed"
fi

cd ~/
