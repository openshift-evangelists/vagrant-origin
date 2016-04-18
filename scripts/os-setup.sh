#!/usr/bin/env bash
#
# Maintainer: Jorge Morales <jmorales@redhat.com>
#
# Install required packages and the environment for those packages if needed
#
# $1 : Journal size
# $2 : Force
#
# The execution of this script will create a file <TESTS_DIR>/<THIS_SCRIPT_FILENAME>.status.configured
# that can be deleted in order to rerun the script
#
#
# You can use a param (Force) with anyvalue that will force installing whatever addon you have selected

#set -o nounset

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"

# This script must be run as root
[ "$UID" -ne 0 ] && echo "To run this script you need root permissions (either root or sudo)" && exit 1

__base="prerequisites"
__BUILD_DIR="/go/src/github.com/openshift"
__CONFIG_DIR="/var/lib/origin"
__TESTS_DIR=${__CONFIG_DIR}/tests
__BIN_DIR=${__CONFIG_DIR}/bin
__journal_size=$1
__force=$2

mkdir -p ${__TESTS_DIR}

[ ! -z ${__force} ] && echo "[INFO] Forcing reinstallation of things" && rm ${__TESTS_DIR}/${__base}.*.configured

if [ ! -f ${__TESTS_DIR}/${__base}.status.configured ]
then
   # Change https with http in yum repos for allowing to cache locally on host for faster installs 
   for file in `ls /etc/yum.repos.d/`
   do
      sed -i -e 's/https/http/g' /etc/yum.repos.d/$file
   done   

   # Install additional packages
   dnf install -y docker git golang bind-utils bash-completion; dnf clean all
   # TODO: Maybe update the whole box with: dnf update

   # Fail if commands have not been installed
   [ "$(which docker)" = "" ] && echo "[ERROR] Docker is not properly installed" && exit 1
   [ "$(which git)" = "" ] && echo "[ERROR] Git is not properly installed" && exit 1
   [ "$(which go)" = "" ] && echo "[ERROR] Go is not properly installed" && exit 1

   # Update journal size so it doesn't grow forever
   sed -i -e "s/.*SystemMaxUse.*/SystemMaxUse=${__journal_size}/" /etc/systemd/journald.conf
   systemctl restart systemd-journald

   # Add go environment to be able to build
   echo 'export GOPATH=/go' > /etc/profile.d/go.sh
   echo 'export PATH=$PATH:$GOROOT/bin:$GOPATH/bin' >> /etc/profile.d/go.sh

   touch ${__TESTS_DIR}/${__base}.status.configured
fi
