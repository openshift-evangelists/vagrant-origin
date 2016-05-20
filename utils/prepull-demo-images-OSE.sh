#!/usr/bin/env bash
#

demo_images_list=(
  registry.access.redhat.com/jboss-eap-6/eap64-openshift
  registry.access.redhat.com/openshift3/jenkins-1-rhel7
  registry.access.redhat.com/openshift3/nodejs-010-rhel7
  registry.access.redhat.com/openshift3/ose-docker-builder
  registry.access.redhat.com/openshift3/ose-pod
  registry.access.redhat.com/openshift3/ose-recycler
  registry.access.redhat.com/openshift3/ose-sti-builder
  registry.access.redhat.com/rhscl/ruby-22-rhel7
  registry.access.redhat.com/rhscl/php-56-rhel7
  registry.access.redhat.com/rhscl/mysql-56-rhel7
  registry.access.redhat.com/rhscl/postgresql-94-rhel7
  docker.io/openshift/deployment-example
  docker.io/kubernetes/guestbook
)
#  registry.access.redhat.com/jboss-eap-6/eap64-openshift
#  docker.io/library/centos:centos7


echo "[INFO] Downloading images"
for image in ${demo_images_list[@]}; do
   echo "[INFO] Downloading image ${image}"
   docker pull $image
done