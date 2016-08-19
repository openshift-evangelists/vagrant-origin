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
# Functions:
#   CAPITALCASE_FUNCTIONS: Are global functions
#   lower_case_functions: Are local functions
#   __private_functions: Are private functions
#
# You can use a param (Force) with anyvalue that will force installing whatever addon you have selected

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"

. /scripts/base/common_functions
. /scripts/base/os-setup
. /scripts/base/docker-setup
. /scripts/base/origin-setup
. /scripts/base/addons-setup

must_run_as_root
load_configuration

##################################################
#
# Setting sane defaults, just in case
: ${__OS_PUBLIC_IP:="10.2.2.2"}
: ${__OS_APPS_DOMAIN:="apps.10.2.2.2.xip.io"}
: ${__OS_ACTION:="none"} # (none, clean, build, config)
: ${__OS_ORIGIN_REPO:="openshift"}
: ${__OS_ORIGIN_BRANCH:="master"}
: ${__OS_ONLY_BUILD_PLATFORMS:="linux/amd64"}
: ${__OS_BUILD_IMAGES:="false"}
: ${__OS_CONFIG:="xpaastemplates,metrics,logging"} # testusers,originimages,centosimages,rhelimages,xpaasimages,otherimages,osetemplates,xpaastemplates,metrics,logging
: ${__OS_DOCKER_VERSION:=""}
: ${__OS_DOCKER_STORAGE_SIZE:="30G"}
: ${__OS_JOURNAL_SIZE:="100M"}
: ${__OS_FORCE:=false}
: ${__OS_XPAAS_TAG:="ose-v1.3.1"}
: ${__OS_PV_COUNT:="10"}
: ${__OS_PV_NFS_SIZE:="10"}
: ${__OS_PV_OPTIONS:="rw,root_squash"}
#
##################################################

mkdir -p ${__TESTS_DIR}

# TODO: Review forcing
[ ! -z ${__OS_FORCE} ] && echo "[INFO] Forcing reinstallation of things" && rm -f ${__TESTS_DIR}/*.configured

#################################################################

OS-Setup
DOCKER-Setup
ORIGIN-Setup
ADDONS-Setup
