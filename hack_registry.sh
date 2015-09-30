#!/bin/bash

pushd /data/src/github.com/openshift/origin/images

git clone https://github.com/jwhonce/openshift-registry-proxy.git /tmp/orp && \
( cd /tmp/orp && git archive --format=tar HEAD:images) |tar xf -
cd ../hack

# edit build-images.sh add --> image openshift/origin-registry-proxy images/registryproxy
sed -i '/Active images/i \
image openshift/origin-registry-proxy images/registryproxy \
' build-images.sh