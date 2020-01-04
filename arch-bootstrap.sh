#!/usr/bin/env bash
#
# arch-bootstrap: Bootstrap a base Arch Linux system using any GNU distribution.
#
# Dependencies: bash >= 4, coreutils, wget, sed, gawk, tar, gzip, chroot, xz.
# Project: https://github.com/tokland/arch-bootstrap
#
# Install:
#
#   # install -m 755 arch-bootstrap.sh /usr/local/bin/arch-bootstrap
#
# Usage:
#
#   # arch-bootstrap destination
#   # arch-bootstrap -a x86_64 -r ftp://ftp.archlinux.org destination-64
#
# And then you can chroot to the destination directory (user: root, password: root):
#
#   # chroot destination

set -e -u -o pipefail

# to re-generate this list, under Arch run:
# bash <(curl -L 'https://raw.githubusercontent.com/greyltc/arch-bootstrap/master/get-pacman-dependencies.sh')
PACMAN_PACKAGES=(
  acl archlinux-keyring attr bzip2 curl e2fsprogs expat glibc gpgme keyutils krb5 libarchive libassuan libgpg-error libidn2 libnghttp2 libpsl libssh2 libunistring lz4 openssl pacman pacman-mirrorlist xz zlib zstd
)
BASIC_PACKAGES=(${PACMAN_PACKAGES[*]} filesystem dash)
EXTRA_PACKAGES=(coreutils bash grep gawk file tar systemd sed)
DEFAULT_REPO_URL="http://mirror.rackspace.com/archlinux"
DEFAULT_ARM_REPO_URL="http://mirror.archlinuxarm.org"

stderr() { 
  echo "$@" >&2 
}

debug() {
  stderr "--- $@"
}

extract_href() {
  sed -n '/<a / s/^.*<a [^>]*href="\([^\"]*\)".*$/\1/p'
}

fetch() {
  curl -L -s "$@"
}

uncompress() {
  local FILEPATH=$1 DEST=$2
  
  case "$FILEPATH" in
    *.gz) tar xzf "$FILEPATH" -C "$DEST";;
    *.xz) xz -dc "$FILEPATH" | tar x -C "$DEST";;
    *) debug "Error: unknown package format: $FILEPATH"
       return 1;;
  esac
}  

###
get_default_repo() {
  local ARCH=$1
  if [[ "$ARCH" == arm* || "$ARCH" == aarch64 ]]; then
    echo $DEFAULT_ARM_REPO_URL
  else
    echo $DEFAULT_REPO_URL
  fi
}

get_core_repo_url() {
  local REPO_URL=$1 ARCH=$2
  if [[ "$ARCH" == arm* || "$ARCH" == aarch64 ]]; then
    echo "${REPO_URL%/}/$ARCH/core"
  else
    echo "${REPO_URL%/}/core/os/$ARCH"
  fi
}

get_template_repo_url() {
  local REPO_URL=$1 ARCH=$2
  if [[ "$ARCH" == arm* || "$ARCH" == aarch64 ]]; then
    echo "${REPO_URL%/}/$ARCH"
  else
    echo "${REPO_URL%/}/\$repo/os/$ARCH"
  fi
}

configure_pacman() {
  local DEST=$1 ARCH=$2
  debug "configure DNS and pacman"
  cp "/etc/resolv.conf" "$DEST/etc/resolv.conf"
  SERVER=$(get_template_repo_url "$REPO_URL" "$ARCH")
  echo "Server = $SERVER" >> "$DEST/etc/pacman.d/mirrorlist"
}

configure_minimal_system() {
  local DEST=$1
  
  mkdir -p "$DEST/dev"
  echo "root:x:0:0:root:/root:/bin/bash" > "$DEST/etc/passwd" 
  echo 'root:$1$GT9AUpJe$oXANVIjIzcnmOpY07iaGi/:14657::::::' > "$DEST/etc/shadow"
  touch "$DEST/etc/group"
  echo "bootstrap" > "$DEST/etc/hostname"
  
  [[ "$EUID" -ne "0" ]] && FAKEROOT=fakeroot
  test -e "$DEST/etc/mtab" || mv "$DEST/etc/mtab" "$DEST/etc/mtab.bak"; echo "rootfs / rootfs rw 0 0" > "$DEST/etc/mtab"
  test -e "$DEST/dev/null" || $FAKEROOT mknod "$DEST/dev/null" c 1 3
  test -e "$DEST/dev/random" || $FAKEROOT mknod -m 0644 "$DEST/dev/random" c 1 8
  test -e "$DEST/dev/urandom" || $FAKEROOT mknod -m 0644 "$DEST/dev/urandom" c 1 9
  ln -s /usr/bin/dash "$DEST/usr/bin/sh"
  
  sed -i "s/^[[:space:]]*\(CheckSpace\)/# \1/" "$DEST/etc/pacman.conf"
  sed -i "s/^[[:space:]]*SigLevel[[:space:]]*=.*$/SigLevel = Never/" "$DEST/etc/pacman.conf"

  chmod 1777 "$DEST/tmp/"
  chmod 1777 "$DEST/var/tmp/"
  chmod 775 "$DEST/var/games/"
  chmod 1777 "$DEST/var/spool/mail/"
}

fetch_packages_list() {
  local REPO=$1 
  
  debug "fetch packages list: $REPO/"
  fetch "$REPO/" | extract_href | awk -F"/" '{print $NF}' | sort -rn ||
    { debug "Error: cannot fetch packages list: $REPO"; return 1; }
}

install_pacman_packages() {
  local BASIC_PACKAGES=$1 DEST=$2 LIST=$3 DOWNLOAD_DIR=$4
  debug "get ready to ignore a bunch of SCHILY.fflags errors!"
  debug "pacman package and dependencies: $BASIC_PACKAGES"
  
  for PACKAGE in $BASIC_PACKAGES; do
    local FILE=$(echo "$LIST" | grep -m1 "^$PACKAGE-[[:digit:]].*\(\.gz\|\.xz|\.zst\)$")
    test "$FILE" || { debug "Error: cannot find package: $PACKAGE"; return 1; }
    local FILEPATH="$DOWNLOAD_DIR/$FILE"
    
    debug "download package: $REPO/$FILE"
    fetch -o "$FILEPATH" "$REPO/$FILE"
    debug "uncompress package: $FILEPATH"
    uncompress "$FILEPATH" "$DEST"
  done
}

fix_details() {
  local DEST=$1
  cp fixDetails.sh "$DEST/usr/bin/fix-details"
  [[ "$EUID" -ne "0" ]] && FAKEIT="fakechroot fakeroot"
  $FAKEIT chroot "$DEST" fix-details
}

configure_static_qemu() {
  local ARCH=$1 DEST=$2
  [[ "$ARCH" == arm* ]] && ARCH=arm
  QEMU_STATIC_BIN=$(which qemu-$ARCH-static || echo )
  [[ -e "$QEMU_STATIC_BIN" ]] ||\
    { debug "no static qemu for $ARCH, ignoring"; return 0; }
  cp "$QEMU_STATIC_BIN" "$DEST/usr/bin"
}

install_packages() {
  local ARCH=$1 DEST=$2 PACKAGES=$3
  debug "install packages: $PACKAGES"
  [[ "$EUID" -ne "0" ]] && FAKEIT="fakechroot fakeroot"
  LC_ALL=C $FAKEIT chroot "$DEST" /usr/bin/pacman \
    --noconfirm --arch $ARCH -Sy --overwrite \* $PACKAGES
  LC_ALL=C $FAKEIT chroot "$DEST" pacman --noconfirm --arch $ARCH -S archlinux-keyring
}

show_usage() {
  stderr "Usage: $(basename "$0") [-f] [-s STAGE] [-q] [-a i686|x86_64|arm] [-r REPO_URL] [-d DOWNLOAD_DIR] DESTDIR"
}

main() {
  # Process arguments and options
  test $# -eq 0 && set -- "-h"
  local ARCH=
  local REPO_URL=
  local USE_QEMU=
  local DOWNLOAD_DIR=
  local FIX_DETAILS=
  local STAGE=0
  
  while getopts "qa:r:d:hs:f" ARG; do
    case "$ARG" in
      a) ARCH=$OPTARG;;
      r) REPO_URL=$OPTARG;;
      q) USE_QEMU=true;;
      d) DOWNLOAD_DIR=$OPTARG;;
      s) STAGE=$OPTARG;;
      f) FIX_DETAILS=true;;
      *) show_usage; return 1;;
    esac
  done
  shift $(($OPTIND-1))
  test $# -eq 1 || { show_usage; return 1; }
  
  [[ -z "$ARCH" ]] && ARCH=$(uname -m)
  [[ -z "$REPO_URL" ]] &&REPO_URL=$(get_default_repo "$ARCH")
  
  local DEST=$1
  local REPO=$(get_core_repo_url "$REPO_URL" "$ARCH")
  if [ "$STAGE" -eq "1" ] || [ "$STAGE" -eq "0" ] ; then
    debug "Step 1: Creating minimal root fs"
    [[ -z "$DOWNLOAD_DIR" ]] && DOWNLOAD_DIR=$(mktemp -d)
    mkdir -p "$DOWNLOAD_DIR"
    [[ "$DOWNLOAD_DIR" ]] && trap "rm -rf '$DOWNLOAD_DIR'" KILL TERM EXIT
    debug "destination directory: $DEST"
    debug "core repository: $REPO"
    debug "temporary directory: $DOWNLOAD_DIR"
  
    # Fetch packages, install system and do a minimal configuration
    mkdir -p "$DEST"
    local LIST=$(fetch_packages_list $REPO)
    install_pacman_packages "${BASIC_PACKAGES[*]}" "$DEST" "$LIST" "$DOWNLOAD_DIR"
    configure_pacman "$DEST" "$ARCH"
    configure_minimal_system "$DEST"
    [[ -n "$USE_QEMU" ]] && configure_static_qemu "$ARCH" "$DEST"
  fi
  if [ "$STAGE" -eq "2" ] || [ "$STAGE" -eq "0" ] ; then
    debug "Step 2: Installing basic and extra packages"
    install_packages "$ARCH" "$DEST" "${BASIC_PACKAGES[*]} ${EXTRA_PACKAGES[*]}"
    configure_pacman "$DEST" "$ARCH" # Pacman must be re-configured
    [[ -n "$FIX_DETAILS" ]] && fix_details "$DEST"
  fi
    
  [[ "$DOWNLOAD_DIR" ]] && rm -rf "$DOWNLOAD_DIR"
  
  debug "done"
}

main "$@"
#exit 0
