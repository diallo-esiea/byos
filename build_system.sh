#!/bin/bash

CAT=/bin/cat
ECHO=/bin/echo
EXIT=exit
MOUNT=/bin/mount

APT_GET=/usr/bin/apt-get
CHROOT=/usr/sbin/chroot
DEBOOSTRAP=/usr/sbin/deboostrap
DPKG_RECONFIGURE=/usr/sbin/dpkg-reconfigure
PASSWD=/usr/bin/passwd

ARCH=amd64    		# i386, amd64
HOSTNAME=		#
INCLUDE=grub2,locales	#
MIRROR=       		# 
SUITE=squeeze 		# squeeze, wheezy, unstable, experimental
TARGET=       		#
VARIANT=      		# minbase, buildd, fakechroot, scratchbox

USAGE="$(basename "$0") [options] SUITE TARGET\n\n
\t\tSUITE\t(lenny, squeeze, sid)\n
\t\tTARGET\t\n\n
\toptions:\n
\t--------\n
\t\t-i, --include\tComma separated list of packages which will be added to download and extract lists\n
\t\t-m, --mirror\tCan be an http:// URL, a file:/// URL, or an ssh:/// URL\n
\t\t-v, --variant\tName of the bootstrap script variant to use (minbase, buildd, fakechroot, scratchbox)"

for i in "$@"; do
  case $i in
    -h|--help)
      ${ECHO} -e ${USAGE}
      exit 0
      ;;

  esac
done

#${DEBOOSTRAP} --arch=${ARCH} --include=${INCLUDE} --variant=${VARIANT} ${SUITE} ${TARGET} ${MIRROR}

# Binding the virtual filesystems
#${MOUNT} -o bind /dev ${TARGET}/dev
#${MOUNT} -o bind /sys ${TARGET}/sys
#${MOUNT} -t proc none ${TARGET}/proc

# Entering the chroot environment
#${CHROOT} ${TARGET} /bin/bash

# Configure locale
#${DPKG_RECONFIGURE} locales

# Create a password for root
#{PASSWD}

# Set the hostname
#${ECHO} ${HOSTNAME} > /etc/hostname

${CAT} > /etc/apt/sources.list << EOF
deb ${MIRROR} ${SUITE} main contrib non-free
deb-src ${MIRROR} ${SUITE} main contrib non-free
deb ${MIRROR} ${SUITE}-updates main contrib non-free
deb-src ${MIRROR} ${SUITE}-updates main contrib non-free
deb http://security.debian.org/debian-security ${SUITE}/updates main contrib non-free
deb-src http://security.debian.org/debian-security ${SUITE}/updates main contrib non-free
EOF 

# Update Debian package database:
#${APT_GET} update

# Quit the chroot environment
#${EXIT}
