#!/usr/bin/env bash
#
# Maintainer: Jorge Morales <jmorales@redhat.com>
#
# This script will configure Docker for running OpenShift
#
# $1 : Docker loopback storage size
# $2 : Force
#
# The execution of this script will create a file <TESTS_DIR>/<THIS_SCRIPT_FILENAME>.status.configured
# that can be deleted in order to rerun the script
#
# You can use a param (Force) with anyvalue that will force installing whatever you have selected

#set -o nounset

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"

# This script must be run as root
[ "$UID" -ne 0 ] && echo "To run this script you need root permissions (either root or sudo)" && exit 1

__base="configure_docker"
__BUILD_DIR="/go/src/github.com/openshift"
__CONFIG_DIR="/var/lib/origin"
__TESTS_DIR=${__CONFIG_DIR}/tests
__BIN_DIR=${__CONFIG_DIR}/bin
__docker_storage_size=$1
__force=$2

mkdir -p ${__TESTS_DIR}

[ ! -z ${_force} ] && echo "[INFO] Forcing reinstallation of things" && rm ${__TESTS_DIR}/${__base}.*.configured

if [ ! -f ${__TESTS_DIR}/${__base}.status.configured ]
then
   systemctl stop docker

   # TODO: Find why Origin does not start in enforcing
   sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
   sudo setenforce 0
   echo "[WARN] Set SELinux to permissive for now"

   ##  Enable the internal registry and configure the Docker to allow pushing to internal OpenShift registry
   echo "[INFO] Configuring Docker for Red Hat registry and else ..."
   sed -i -e "s/^.*INSECURE_REGISTRY=.*/INSECURE_REGISTRY='--insecure-registry 0\.0\.0\.0\/0 '/" /etc/sysconfig/docker 
   sed -i -e "s/^.*OPTIONS=.*/OPTIONS='--selinux-enabled --storage-opt dm\.no_warn_on_loop_devices=true --storage-opt dm\.loopdatasize=${__docker_storage_size}'/" /etc/sysconfig/docker
   # sed -i -e "s/^.*ADD_REGISTRY=.*/ADD_REGISTRY='--add-registry registry\.access\.redhat\.com'/" /etc/sysconfig/docker 

   ## Disable firewall
   systemctl stop firewalld; systemctl disable firewalld 
   systemctl start docker; systemctl enable docker

   touch ${__TESTS_DIR}/${__base}.status.configured
fi