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
__BUILD_DIR="/go/src/github.com/openshift"
__CONFIG_DIR="/var/lib/origin"
__TESTS_DIR=${__CONFIG_DIR}/tests
__BIN_DIR=${__CONFIG_DIR}/bin

# Setting sane defaults, just in case
: ${__OS_public_ip:="10.2.2.2"}
: ${__OS_apps_domain:="myapps.10.2.2.2.xip.io"}
: ${__OS_action:="none"} # (none, clean, build, config)
: ${__OS_origin_repo:="openshift"}
: ${__OS_origin_branch:="master"}
: ${__OS_build_images:="false"}
: ${__OS_config:="osetemplates,metrics,logging"} # testusers,originimages,centosimages,rhelimages,xpaasimages,otherimages,osetemplates,metrics,logging
: ${__OS_DOCKER_STORAGE_SIZE:="30G"}
: ${__OS_JOURNAL_SIZE:="100M"}
: ${__OS_force:=false}
: ${__OS_template_ose_tag:="ose-v1.3.0-1"}

# CONSTANTS
__VERSION="latest"
__MASTER_CONFIG="${__CONFIG_DIR}/openshift.local.config/master/master-config.yaml"
__REPO="https://github.com/${__OS_origin_repo}/origin.git"
#
##################################################

mkdir -p ${__TESTS_DIR}

# TODO: Review forcing
[ ! -z ${__OS_force} ] && echo "[INFO] Forcing reinstallation of things" && rm -f ${__TESTS_DIR}/*.configured

#################################################################

OS-Setup
DOCKER-Setup
ORIGIN-Setup
ADDONS-Setup