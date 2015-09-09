#!/bin/bash
#
# Script to create an origin image
#
# Pre requisites
#  Vagrant >= 1.7.2
#  vagrant-openshift
#
#
# Parameters to script
#  
# 

: ${VERSION:="1.0.5"}
: ${OS:="fedora"}  # Possible values are fedora, centos7, rhel7 
: ${BOX_NAME:="openshift-bootstrap"}
: ${BOX_TARGET_LOCATION:="/tmp"}
: ${USE_LATEST_BASE:="-true"} # CHANGE THIS
: ${SCRATCH_AREA:="/tmp/scratch"}
: ${VAGRANT_VERSION:="1.7.2"}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


#
# 
#
function check_prerequisites(){
   echo "Checking Requirements..."

   # TODO: Check that version is at least
   local vagrant_version=$(vagrant -v 2>/dev/null)
   if [ "Vagrant ${VAGRANT_VERSION}" != "$vagrant_version" ]; then
      echo "REQUIREMENT: Vagrant version required ${VAGRANT_VERSION} NOT met"
      exit 1
   else
      echo "REQUIREMENT: Vagrant version required ${VAGRANT_VERSION} met"   
   fi

   local vagrant_openshift_plugin=$(vagrant plugin list  2>/dev/null | grep vagrant-openshift)
   if [ "" == "$vagrant_openshift_plugin" ]; then
      echo "REQUIREMENT: vagrant-openshift plugin NOT installed"
      exit 1
   else
      echo "REQUIREMENT: vagrant-openshift plugin installed. ${vagrant_openshift_plugin}"
   fi

}




# Main execution of the script
#
#
#
check_prerequisites

#export IMAGES="--images 'openshift/origin-${component}:v0.4.4'"

# unset BRANCH to build from master
export BRANCH="--branch v${VERSION}"

echo "Clearing some ENV variables in the working shell. (GOPATH, OPENSHIFT_DEV_CLUSTER)"
unset GOPATH 2>/dev/null
unset OPENSHIFT_DEV_CLUSTER 2>/dev/null

echo "Creating scratch area for building bootstrap box at ${SCRATCH_AREA}. We are going to delete all previous content there"
mkdir -p ${SCRATCH_AREA}
rm -rf ${SCRATCH_AREA}/*
cd ${SCRATCH_AREA}

echo "Checkout source code"
echo "COMMAND: vagrant openshift-local-checkout --replace $BRANCH"
vagrant openshift-local-checkout --replace $BRANCH

echo "Working Dir: ${SCRATCH_AREA}/origin"
cd ${SCRATCH_AREA}/origin

if [ "$USE_LATEST_BASE" == "true" ]; then 
   echo "Get the latest fedora box"
   echo "COMMAND: vagrant box remove fedora_inst"
   vagrant box remove fedora_inst
else
   echo "We are going to use your current fedora_inst image if exists"
fi      

echo "Create .vagrant-openshift.json. This file holds the characteristics for your Vagrantfile"
echo "COMMAND: vagrant origin-init --stage inst --os ${OS} openshift-bootstrap --no-synced-folders"
vagrant origin-init --stage inst --os ${OS} openshift-bootstrap --no-synced-folders

echo "Expose registry to host OS for bootstraping"
sed -i '/guest: 8443, host: 8443$/a  config.vm.network "forwarded_port", guest: 5000, host: 5000' Vagrantfile

echo "Create new bootstrap box"
echo "Starting the bootstrap process and box"
# TODO: This process can fail depending on proper shutdown of previous run. 
# libvirt error: Name `origin_openshiftdev` of domain about to create is already taken. Please try to run `vagrant up` command again.
echo "COMMAND: vagrant up"
vagrant up

echo "Clone upstream repos"
echo "COMMAND: vagrant clone-upstream-repos --clean"
vagrant clone-upstream-repos --clean

echo "Checkout the appropriate branch: $BRANCH"
echo "COMMAND: vagrant checkout-repos $BRANCH"
vagrant checkout-repos $BRANCH

# TODO: To here
#vagrant destroy
echo "Stopping execution here, as from here down is not tested. In the Vagrant box there is no /data/src/github.com/openshift/origin"
exit 0
# Remove above lines when testing more

## NOT WORKING
# # install source for pod to proxy registry from cluster IP to exposed IP for host OS
# vagrant ssh 
# pushd /data/src/github.com/openshift/origin/images
# 
# git clone https://github.com/jwhonce/openshift-registry-proxy.git /tmp/orp && \
# ( cd /tmp/orp && git archive --format=tar HEAD:images) |tar xf -
# cd ../hack
# 
# edit build-images.sh add
#  image openshift/origin-registry-proxy images/registryproxy
# 
# exit

# Build OpenShift for bootstrap box
vagrant install-openshift $IMAGES
vagrant build-openshift-base
vagrant build-openshift-base-images
vagrant build-openshift --images
vagrant build-sti --binary-only

vagrant ssh
sudo su -

# Defined to reduce typing
export OADM=/data/src/github.com/openshift/origin/_output/local/go/bin/oadm
export OC=/data/src/github.com/openshift/origin/_output/local/go/bin/oc                                                                                                           

# Configure bootstrap OpenShift for class
systemctl enable openshift
systemctl start openshift

# Remove privileged required. Allow RunAsAny
oc get scc restricted --output=yaml |\
sed '/runAsUser/{n;s/MustRunAsRange/RunAsAny/}' | oc replace scc restricted -f -

# Create the router
oc edit scc priviliged
    add ‘system:serviceaccount:default:router’ user
echo '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"router"}}' | oc create -f -
oadm router \
 --credentials=/openshift.local.config/master/openshift-router.kubeconfig \
 --service-account=router
oadm registry --credentials=/openshift.local.config/master/openshift-registry.kubeconfig

# populate registry to improve class experience
docker pull fedora/apache
docker pull fedora/qpid

# Add xpaas templates
git clone https://github.com/openshift/openshift-ansible
oc create -n openshift -f openshift-ansible/openshift_examples/files/examples/xpaas-templates/

# This probably isn’t needed anymore
# systemctl restart docker

# deploy poxy pod
oc create -f /data/src/github.com/openshift/origin/images/registryproxy/pod.json

# allow students to be cluster-admin’s, allows them to create projects etc
oadm policy add-role-to-group cluster-admin system:authenticated \
   --config=/openshift.local.config/master/admin.kubeconfig --namespace=default

# Create sample project
oadm new-project turbo --admin=admin --description='Turbo\ Sample' --display-name='Turbo\ Sample'

# deploy sample application 
oc login
oc project turbo
oc process -f  /data/src/github.com/openshift/origin/examples/sample-app/application-template-stibuild.json | oc create -f -

# verify sample application is deployed successfully
curl -skL -w "%{http_code} %{url_effective}\\n" -o /tmp/output -H 'Host: www.example.com' https://localhost:443

# remove journal files before packaging
rm -rf /var/log/journald/*

exit

# package new bootstrap box for sharing with Steve and students
vagrant package --output ${BOX_TARGET_LOCATION}/${BOX_NAME}-${VERSION}.box
if [ -f ${BOX_TARGET_LOCATION}/${BOX_NAME}-${VERSION}.box ]
then
   echo "New Vagrant box has been created into ${BOX_TARGET_LOCATION}/${BOX_NAME}-${VERSION}.box"
else
   echo "Vagrant OpenShift bootstrap box creation failed"
fi