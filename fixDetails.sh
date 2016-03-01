#!/bin/sh
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

# set timezone to UTC
ln -s /usr/share/zoneinfo/UTC /etc/localtime

# clean up the pacnews by overwriting the origionals
mv /etc/pacman.conf.pacnew /etc/pacman.conf || true
mv /etc/hosts.pacnew /etc/hosts || true
mv /etc/resolv.conf.pacnew /etc/resolv.conf || true
#mv /etc/pacman.d/mirrorlist.pacnew /etc/pacman.d/mirrorlist || true
#mv /etc/shadow.pacnew /etc/shadow || true
#mv /etc/passwd.pacnew /etc/passwd || true

# fix TERM not being set
echo "export TERM=xterm" >> /etc/profile
