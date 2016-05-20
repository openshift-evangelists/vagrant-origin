#!/usr/bin/env bash
#

demo_images_list=(
  docker.io/openshift/php-55-centos7:latest

  docker.io/openshift/deployment-example
  docker.io/kubernetes/guestbook
)


echo "[INFO] Downloading images"
for image in ${demo_images_list[@]}; do
   echo "[INFO] Downloading image ${image}"
   docker pull $image
done
