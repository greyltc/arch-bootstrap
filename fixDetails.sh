#!/usr/bin/env bash

echo "Fixing up some details..."

# reinstall the keyring since it may have failed in the chroot
pacman --noconfirm -S archlinux-keyring

# populate keyring
pacman-key --init
pacman-key --populate archlinux

# set the locale
LANGUAGE=en_US
TEXT_ENCODING=UTF-8
echo "${LANGUAGE}.${TEXT_ENCODING} ${TEXT_ENCODING}" >> /etc/locale.gen
echo LANG="${LANGUAGE}.${TEXT_ENCODING}" > /etc/locale.conf
locale-gen

# clean up the pacnews
PACNEW=/etc/pacman.conf.pacnew
mv $PACNEW ${PACNEW%.pacnew}
PACNEW=/etc/pacman.d/mirrorlist.pacnew
mv $PACNEW ${PACNEW%.pacnew}
PACNEW=/etc/shadow.pacnew
mv $PACNEW ${PACNEW%.pacnew}
PACNEW=/etc/passwd.pacnew
mv $PACNEW ${PACNEW%.pacnew}
PACNEW=/etc/resolv.conf.pacnew
mv $PACNEW ${PACNEW%.pacnew}

# fix TERM not being set
echo "export TERM=xterm" >> /etc/profile

