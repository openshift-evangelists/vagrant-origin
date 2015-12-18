#!/usr/bin/env bash
#
# Maintainer: Jorge Morales <jmorales@redhat.com>
#
# Install required packages and the environment for those packages if needed
#
# $1 : Force
#
# The execution of this script will create a file <TESTS_DIR>/<THIS_SCRIPT_FILENAME>.status.configured
# that can be deleted in order to rerun the script
#
#
# You can use a param (Force) with anyvalue that will force installing whatever addon you have selected

#set -o nounset

# This script must be run as root
[ "$UID" -ne 0 ] && echo "To run this script you need root permissions (either root or sudo)" && exit 1

__base="prerequisites"
__BUILD_DIR="/go/src/github.com/openshift"
__CONFIG_DIR="/var/lib/origin"
__TESTS_DIR=${__CONFIG_DIR}/tests
__BIN_DIR=${__CONFIG_DIR}/bin
__force=$1

mkdir -p ${__TESTS_DIR}

[ ! -z ${__force} ] && echo "[INFO] Forcing reinstallation of things" && rm ${__TESTS_DIR}/${__base}.*.configured

if [ ! -f ${__TESTS_DIR}/${__base}.status.configured ]
then
   dnf install -y docker git golang; dnf clean all

   echo 'export GOPATH=/go' > /etc/profile.d/go.sh
   echo 'export PATH=$PATH:$GOROOT/bin:$GOPATH/bin' >> /etc/profile.d/go.sh

   touch ${__TESTS_DIR}/${__base}.status.configured
fi