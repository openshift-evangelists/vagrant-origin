#!/bin/bash
#
# This script will install Gitlab in an all-in-one OpenShift VM
#
# Requirements:
#   Gitlab will use the following images:
#     - gitlab-ce
#     - redis
#     - postgresql
#   Gitlab will use 3 PV for storing stateful data
#   Gi
#

# These actions need to be done as admin
. /scripts/base/common_functions

must_run_as_root

# Prepull the images
docker pull gitlab/gitlab-ce:8.8.1-ce.0
docker pull redis:2.8
docker pull centos/postgresql-94-centos7:latest

# Create the application.
# The PVC needs to be created first in order to be assigned to the appropriate PV
sudo_oc adm new-project gitlab
sudo_oc create -f /utils/gitlab/gitlab-template.json -n gitlab
sudo_oc create -f /utils/gitlab/gitlab-pvcs.json -n gitlab

# Create nfs with no_root_squash
/utils/gitlab/create-nfs-pv.sh pv-gitlab-redis-data gitlab gitlab-redis-data
/utils/gitlab/create-nfs-pv.sh pv-gitlab-etc        gitlab gitlab-etc
/utils/gitlab/create-nfs-pv.sh pv-gitlab-logs       gitlab gitlab-logs
/utils/gitlab/create-nfs-pv.sh pv-gitlab-opt        gitlab gitlab-opt
/utils/gitlab/create-nfs-pv.sh pv-gitlab-postgresql gitlab gitlab-postgresql

# Create the application
sudo_oc new-app gitlab-ce -n gitlab
