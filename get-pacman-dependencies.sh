#!/bin/sh
set -e -u -o pipefail

shared_dependencies() {
  local EXECUTABLE=$1
  for PACKAGE in $(ldd "$EXECUTABLE" | grep "=> /" | awk '{print $3}'); do 
    LC_ALL=c pacman -Qo $PACKAGE
  done | awk '{print $5}'
}

pkgbuild_dependencies() {
  curl -LsS 'https://projects.archlinux.org/svntogit/packages.git/plain/trunk/PKGBUILD?h=packages/pacman' -o /tmp/pacman_PKGBUILD
  local EXCLUDE=$1
  source /tmp/pacman_PKGBUILD
  for DEPEND in ${depends[@]}; do
    echo "$DEPEND" | sed "s/[>=<].*$//"
  done | grep -v "$EXCLUDE"
}

# Main
{ 
  shared_dependencies "/usr/bin/pacman"
  pkgbuild_dependencies "bash"
} | sort -u | xargs

