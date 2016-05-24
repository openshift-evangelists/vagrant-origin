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

# This script must be run as root
[ "$UID" -ne 0 ] && echo "To run this script you need root permissions (either root or sudo)" && exit 1

# Load Configuration file
. /config/config.env

__BUILD_DIR="/go/src/github.com/openshift"
__CONFIG_DIR="/var/lib/origin"
__TESTS_DIR=${__CONFIG_DIR}/tests
__BIN_DIR=${__CONFIG_DIR}/bin

: ${__OS_public_ip:="10.2.2.2"}
: ${__OS_apps_domain:="myapps.10.2.2.2.xip.io"}
: ${__OS_action:="none"} # (none, clean, build, config)
: ${__OS_origin_repo:="openshift"}
: ${__OS_origin_branch:="master"}
: ${__OS_build_images:="false"}
: ${__OS_config:="osetemplates,metrics,logging"} # testusers,originimages,centosimages,rhelimages,xpaasimages,otherimages,osetemplates,metrics,logging
: ${__OS_docker_storage_size:="30G"}
: ${__OS_force:=false}
: ${__OS_template_ose_tag:="ose-v1.3.0-1"}

# CONSTANTS
__VERSION="latest"
__MASTER_CONFIG="${__CONFIG_DIR}/openshift.local.config/master/master-config.yaml"
__REPO="https://github.com/${__OS_origin_repo}/origin.git"

if [ -z ${__OS_public_ip} ]
then
   echo "[ERROR] Environment variables not set"
   exit 1
else
   echo "[INFO] Configuration properly exported" 
   printenv | egrep "^__OS_"
fi

mkdir -p ${__TESTS_DIR}

# TODO: Review forcing
[ ! -z ${__OS_force} ] && echo "[INFO] Forcing reinstallation of things" && rm -f ${__TESTS_DIR}/*.configured

# Checks for existance of marker file
# $1: marker name
marker_check(){
   [ -f ${__TESTS_DIR}/$1.configured ] && return 1 || return 0
}

# Creates marker file
# $1: marker name
marker_create(){
   touch ${__TESTS_DIR}/$1.configured
}

INSTALL_BASE_OS(){
   if marker_check "os.status"; then
      # Install additional packages
      dnf install -y docker git golang bind-utils bash-completion htop nfs-utils; dnf clean all
      # TODO: Maybe update the whole box with: dnf update

      # Fail if commands have not been installed
      [ "$(which docker)" = "" ] && echo "[ERROR] Docker is not properly installed" && exit 1
      [ "$(which git)" = "" ] && echo "[ERROR] Git is not properly installed" && exit 1
      [ "$(which go)" = "" ] && echo "[ERROR] Go is not properly installed" && exit 1

      # Update journal size so it doesn't grow forever
      sed -i -e "s/.*SystemMaxUse.*/SystemMaxUse=${__OS_docker_storage_size}/" /etc/systemd/journald.conf
      systemctl restart systemd-journald

      # Add go environment to be able to build
      echo 'export GOPATH=/go' > /etc/profile.d/go.sh
      echo 'export PATH=$PATH:$GOROOT/bin:$GOPATH/bin' >> /etc/profile.d/go.sh

      marker_create "os.status"   
   fi
}

DOCKER_SETUP(){
   if marker_check "docker.setup"; then
      systemctl stop docker

      # Add docker capabilities to vagrant user
      groupadd docker
      usermod -aG docker vagrant

      # TODO: Find why Origin does not start in enforcing
      sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
      sudo setenforce 0
      echo "[WARN] Set SELinux to permissive for now"

      ##  Enable the internal registry and configure the Docker to allow pushing to internal OpenShift registry
      echo "[INFO] Configuring Docker for Red Hat registry and else ..."
      sed -i -e "s/^.*INSECURE_REGISTRY=.*/INSECURE_REGISTRY='--insecure-registry 0\.0\.0\.0\/0 '/" /etc/sysconfig/docker 
      sed -i -e "s/^.*OPTIONS=.*/OPTIONS='--selinux-enabled --storage-opt dm\.no_warn_on_loop_devices=true --storage-opt dm\.loopdatasize=${__OS_docker_storage_size}'/" /etc/sysconfig/docker
      # sed -i -e "s/^.*ADD_REGISTRY=.*/ADD_REGISTRY='--add-registry registry\.access\.redhat\.com'/" /etc/sysconfig/docker 

      ## Disable firewall
      systemctl stop firewalld; systemctl disable firewalld 
      systemctl start docker; systemctl enable docker

      marker_create "docker.setup"
   fi 
}

# Clean
clean_source(){
  # Delete the Origin repository previously checked out
  rm -rf ${__BUILD_DIR}
}

# Clean
clean_target(){
  # Delete the Origin repository previously checked out
  rm -rf ${__BUILD_DIR}/origin/_output
  rm -rf ${__CONFIG_DIR}/bin
}

clean_install(){
  echo "[INFO] Deleting old install"
  # Stop origin and delete all containers
  systemctl stop origin > /dev/null 2>&1
  sleep 3
  if [[ "$(docker ps -qa)" != "" ]]
  then
  docker stop $(docker ps -qa)
  docker rm -vf $(docker ps -qa)
  fi

  systemctl stop docker
  # Hack to delete secret volumes in use
  cat /etc/mtab | grep kubernetes | awk '{ print $2}' | xargs umount > /dev/null 2>&1

  # Deleting previous configuration
  rm -rf ${__CONFIG_DIR}/openshift.local.*
  rm -rf ${__CONFIG_DIR}/tests/addons*
  rm -rf ${__CONFIG_DIR}/tests/addons_origin*

  systemctl start docker
}

# Checkout
__checkout(){
  echo "[INFO] No origin source, so let's checkout and build it"
  mkdir -p ${__BUILD_DIR}

  pushd ${__BUILD_DIR}
  echo "[INFO] Cloning $__REPO to specified branch ${__OS_origin_branch}"

  git clone --single-branch --branch=${__OS_origin_branch} ${__REPO}
  [ "$?" -ne 0 ] && echo "[ERROR] Error cloning the repository" && exit 1

  [ ! -d ${__BUILD_DIR}/origin ] && echo "[ERROR] There is no source to build. Check that the repo was properly checked out" && exit 1
  popd
}

# Update
__update(){
  pushd ${__BUILD_DIR}/origin
  echo "[INFO] Updating to latest"
  git pull
  popd
}

BUILD(){
  export GOPATH=/go
  export PATH=$PATH:$GOPATH/bin

  # If source is there we update
  if [ -e ${__BUILD_DIR}/origin ]
  then
    __update
  else
    # else we checkout
    __checkout
  fi

  [ ! -d ${__BUILD_DIR}/origin ] && echo "[ERROR] There is no source to build. Check that the repo was properly checked out" && exit 1

  if [ ! -d ${__BUILD_DIR}/origin/_output ]
  then
    # We build
    cd ${__BUILD_DIR}/origin
    hack/build-go.sh
    # TODO: Test this
    if [ "${__OS_build_images}" = "true" ]
    then
      hack/build-base-images.sh
      hack/build-release.sh
      hack/build-images.sh
      __VERSION=$(git rev-parse --short "HEAD^{commit}" 2>/dev/null)
    fi

    # We copy the binaries into the <CONFIG_DIR>/bin and then link them
    mkdir -p ${__CONFIG_DIR}/bin
    pushd ${__BUILD_DIR}/origin/_output/local/bin/linux/amd64/
    for i in `ls *`
    do 
      cp -f ${i} ${__CONFIG_DIR}/bin
      ln -s ${__CONFIG_DIR}/bin/${i} /usr/bin/ > /dev/null 2>&1
    done
    popd

    # Add bash completions
    mkdir -p ${__CONFIG_DIR}/bin/bash
    pushd ${__BUILD_DIR}/origin/contrib/completions/bash/
    for i in `ls *`
    do
      cp -f ${i} ${__CONFIG_DIR}/bin/bash
      ln -s ${__CONFIG_DIR}/bin/bash/${i} /etc/bash_completion.d/ > /dev/null 2>&1
    done  

    popd
  fi
}

CONFIG(){
  [ -e ${__MASTER_CONFIG} ] && return 0
  echo "[INFO] Using images version ${__VERSION}"

  echo "export CONFIG_DIR=${__CONFIG_DIR}" > /etc/profile.d/openshift.sh
  echo "export MASTER_DIR=${__CONFIG_DIR}/openshift.local.config/master" >> /etc/profile.d/openshift.sh
  echo "export KUBECONFIG=${__CONFIG_DIR}/openshift.local.config/master/admin.kubeconfig" >> /etc/profile.d/openshift.sh
  echo "export MASTER_CONFIG=${__MASTER_CONFIG}" >> /etc/profile.d/openshift.sh


  # TODO: Fix permissions for openshift.local.config, openshift.local.etcd, openshift.local.volumes
  # Create initial configuration for Origin
  openshift start --public-master=${__OS_public_ip} \
      --master=${__OS_public_ip} \
      --etcd-dir=${__CONFIG_DIR}/openshift.local.etcd \
      --write-config=${__CONFIG_DIR}/openshift.local.config \
      --volume-dir=${__CONFIG_DIR}/openshift.local.volumes \
      --images='openshift/origin-${component}:'${__VERSION}

  chmod 666 ${__CONFIG_DIR}/openshift.local.config/master/*

  # Now we need to make some adjustments to the config
  sed -i.orig -e "s/\(.*subdomain:\).*/\1 ${__OS_apps_domain}/" ${__MASTER_CONFIG}
  # This options below should not be needed, as openshift-start is handling these
  #  -e "s/\(.*masterPublicURL:\).*/\1 https:\/\/${__OS_public_ip}:8443/g" \
  #  -e "s/\(.*publicURL:\).*/\1 https:\/\/${__OS_public_ip}:8443\/console\//g" \
  #  -e "s/\(.*assetPublicURL:\).*/\1 https:\/\/${__OS_public_ip}:8443\/console\//g"

  [ ! -d ${__CONFIG_DIR}/openshift.local.config/master ] && echo "[ERROR] There is no master config dir available at ${__CONFIG_DIR}/openshift.local.config/master" && exit 1
  # NOTE: If node name gets configurable, change this check and service file below
  [ ! -d ${__CONFIG_DIR}/openshift.local.config/node-origin ] && echo "[ERROR] There is no node config dir available at ${__CONFIG_DIR}/openshift.local.config/node-origin" && exit 1

  # Run Origin
  # openshift start --master-config=/var/lib/origin/openshift.local.config/master/master-config.yaml --node-config=/var/lib/origin/openshift.local.config/node-origin/node-config.yaml --public-master=#{PUBLIC_ADDRESS}
  cat <<-EOF > /etc/systemd/system/origin.service
  [Unit]
  Description=OpenShift
  After=docker.target network.target

  [Service]
  Type=notify
  ExecStart=/usr/bin/openshift start --master-config=${__CONFIG_DIR}/openshift.local.config/master/master-config.yaml --node-config=${__CONFIG_DIR}/openshift.local.config/node-origin/node-config.yaml --public-master=${__OS_public_ip}

  [Install]
  WantedBy=multi-user.target
EOF
  systemctl enable origin

}

ADD_RESOURCES() {
  . /etc/profile.d/openshift.sh

  # Install Registry
  if marker_check "origin.registry"; then
    echo "[INFO] Creating the OpenShift Registry"
    mkdir -p /opt/registry
    chmod 777 /opt/registry

    oc adm registry --service-account=registry \
                    --config=${__CONFIG_DIR}/openshift.local.config/master/admin.kubeconfig \
                    --mount-host=/opt/registry

    # TODO: Secure the registry (https://docs.openshift.org/latest/install_config/install/docker_registry.html)
    oc expose service docker-registry --hostname "hub.${__OS_public_ip}"
    echo "[INFO] Registry is accesible in hub.${__OS_public_ip}"

    marker_create "origin.registry"
  fi

  # Install Router
  if marker_check "origin.router"; then
    echo "[INFO] Creating the OpenShift Router"
    oc adm policy add-scc-to-user hostnetwork system:serviceaccount:default:router
    ## Create the router
    oc adm router --create --service-account=router

    marker_create "origin.router"
  fi

  # Add admin as cluster-admin
  if marker_check "origin.users"; then
    echo "[INFO] Creating and configuring users"
    ## Add admin as a cluster-admin
    oc adm policy add-cluster-role-to-user cluster-admin admin

    marker_create "origin.users"
  fi

  # Allow all users to run as anyuid
  if marker_check "origin.anyuid"; then
    echo "[INFO] Creating and configuring users"
    ## Add admin as a cluster-admin
    oc adm policy add-scc-to-group anyuid system:authenticated

    marker_create "origin.anyuid"
  fi

  if marker_check "origin.cockpit"; then
    echo "[INFO] Creating cockpit as administrative project"
    oc adm new-project cockpit
    oc create -f /scripts/cockpit/cockpit.json -n cockpit
    echo "[INFO] Cockpit is available at http://cockpit.${__OS_apps_domain}"

    marker_create "origin.cockpit"
  fi

  # Installing templates into OpenShift
  if marker_check "origin.templates"; then
    echo "[INFO] Installing Origin templates"

    template_list=(
      # Image streams (Centos7)
      ## SCL: Ruby 2, Ruby 2.2, Node.js 0.10, Perl 5.16, Perl 5.20, PHP 5.5, PHP 5.6, Python 3.4, Python 3.3, Python 2.7)
      ## Databases: Mysql 5.5, Mysql 5.6, PostgreSQL 9.2, PostgreSQL 9.4, Mongodb 2.4, Mongodb 2.6, Jenkins
      ## Wildfly 8.1
      https://raw.githubusercontent.com/openshift/origin/master/examples/image-streams/image-streams-centos7.json
      # DB templates (Centos)
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/mongodb-ephemeral-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/mongodb-persistent-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/mysql-ephemeral-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/mysql-persistent-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/postgresql-ephemeral-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/postgresql-persistent-template.json
      # Jenkins (Centos)
      https://raw.githubusercontent.com/openshift/origin/master/examples/jenkins/jenkins-ephemeral-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/jenkins/jenkins-persistent-template.json
      # Node.js (Centos)
      https://raw.githubusercontent.com/openshift/nodejs-ex/master/openshift/templates/nodejs-mongodb.json
      https://raw.githubusercontent.com/openshift/nodejs-ex/master/openshift/templates/nodejs.json
      ## NodeJS S2I image streams (recent releases not covered by SCL)
      https://raw.githubusercontent.com/ryanj/origin-s2i-nodejs/master/image-streams.json
      # Warpdrive-python
      https://raw.githubusercontent.com/GrahamDumpleton/warpdrive/master/openshift/warpdrive-python.json
    )

    for template in ${template_list[@]}; do
      echo "[INFO] Importing template ${template}"
      oc create -f $template -n openshift >/dev/null
    done

    marker_create "origin.templates"
  fi


  # Add nfs and some sample NFS mounts and PVs
  if marker_check "origin.nfs"; then
    echo "[INFO] Creating and configuring NFS"

    mkdir -p /nfsvolumes/pv{01..10}
    chown -R nfsnobody:nfsnobody /nfsvolumes
    chmod -R 777 /nfsvolumes

    echo '' > /etc/exports
    for i in {01..10}
    do
      echo "/nfsvolumes/pv${i} *(rw,root_squash)" >> /etc/exports
    done

    # To allow pods to write to remote NFS servers
    setsebool -P virt_use_nfs 1

    # Start and enable nfs
    systemctl start rpcbind nfs-server
    systemctl enable rpcbind nfs-server

    # Enable the new exports without bouncing the NFS service
    exportfs -a

    echo "[INFO] Creating 10 NFS PV {pv01..10} using from 10Gi in ReadWriteMany or ReadWriteOnly mode and Recycle Policy."
    for i in {01..10}
    do
    cat <<-EOF > /tmp/pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv${i}
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Recycle
  nfs:
    server: localhost
    path: /nfsvolumes/pv${i}
EOF
    # Create 10 volumes of 10Gi
    oc create -f /tmp/pv.yaml
    done

    marker_create "origin.nfs"
  fi

  # Add sample app. This needs to be lightweight and expose the app in a meaningful route
#  if [ ! -f ${__CONFIG_DIR}/tests/origin.sample.configured ]; then
#    echo "[INFO] Creating sample app"
    ## Add admin as a cluster-admin
#    oc new-project turbo --display-name="Turbo Sample" --description="This is an example project to demonstrate OpenShift v3"
#    oc process -f https://raw.githubusercontent.com/openshift/origin/master/examples/sample-app/application-template-stibuild.json | oc create -n turbo -f -
    # curl -skL -w "%{http_code} %{url_effective}\\n" -o /tmp/output -H 'Host: www.example.com' https://localhost:443

#    touch ${__CONFIG_DIR}/tests/origin.sample.configured
#  fi

}


ADDONS() {
   # TODO: Depending on the action, delete control files
   arr=$(echo ${__OS_config} | tr "," "\n")
   for x in ${arr}
   do
      touch ${__TESTS_DIR}/addons.${x}.wanted
   done

   # Installing templates into OpenShift
   if [ -f ${__TESTS_DIR}/addons.osetemplates.wanted ]; then
     if [ ! -f ${__TESTS_DIR}/addons.osetemplates.configured ]; then
       echo "[INFO] Installing OpenShift templates"

     template_list=(
       ## SCL: Ruby 2, Ruby 2.2, Node.js 0.10, Perl 5.16, Perl 5.20, PHP 5.5, PHP 5.6, Python 3.4, Python 3.3, Python 2.7)
       ## Databases: Mysql 5.5, Mysql 5.6, PostgreSQL 9.2, PostgreSQL 9.4, Mongodb 2.4, Mongodb 2.6, Jenkins
       https://raw.githubusercontent.com/openshift/origin/master/examples/image-streams/image-streams-rhel7.json    
       ## JBoss Image streams(JWS, EAP, JDG, BRMS, AMQ)
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/jboss-image-streams.json
       ## Fuse Image Streams
       https://raw.githubusercontent.com/jboss-fuse/application-templates/master/fis-image-streams.json
       # EAP
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-amq-persistent-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-amq-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-basic-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-https-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-mongodb-persistent-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-mongodb-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-mysql-persistent-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-mysql-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-postgresql-persistent-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/eap/eap64-postgresql-s2i.json
       # DecisionServer
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/decisionserver/decisionserver62-amq-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/decisionserver/decisionserver62-basic-s2i.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/decisionserver/decisionserver62-https-s2i.json
       # Fuse
       ## No templates. They are created by mvn:io.fabric8.archetypes
       # DataGrid
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/datagrid/datagrid65-basic.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/datagrid/datagrid65-https.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/datagrid/datagrid65-mysql-persistent.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/datagrid/datagrid65-mysql.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/datagrid/datagrid65-postgresql-persistent.json
       https://raw.githubusercontent.com/jboss-openshift/application-templates/${__OS_template_ose_tag}/datagrid/datagrid65-postgresql.json

     )

       for template in ${template_list[@]}; do
         echo "[INFO] Importing template ${template}"
         oc create -f $template -n openshift >/dev/null
       done
       touch ${__TESTS_DIR}/addons.osetemplates.configured
     fi

     rm ${__TESTS_DIR}/addons.osetemplates.wanted
   fi

   # Create users
   if [ -f ${__TESTS_DIR}/addons.testusers.wanted ]; then
     if [ ! -f ${__TESTS_DIR}/addons.testusers.configured ]; then
       echo "[INFO] Creating and configuring test users"
      
       ## Add whatever user you might want
       # oadm policy add-cluster-role-to-user cluster-admin admin 
       touch ${__TESTS_DIR}/addons.testusers.configured
     fi
      
     rm ${__TESTS_DIR}/addons.testusers.wanted
   fi

   # Create metrics
   if [ -f ${__TESTS_DIR}/addons.metrics.wanted ]; then
     if [ ! -f ${__TESTS_DIR}/addons.metrics.configured ]; then
       echo "[INFO] Creating and configuring metrics"
      
       oc create -f https://raw.githubusercontent.com/openshift/origin-metrics/master/metrics-deployer-setup.yaml -n openshift-infra
       oc adm policy add-role-to-user edit system:serviceaccount:openshift-infra:metrics-deployer -n openshift-infra
       oc adm policy add-cluster-role-to-user cluster-reader system:serviceaccount:openshift-infra:heapster -n openshift-infra
       oc secrets new metrics-deployer nothing=/dev/null -n openshift-infra
       # This file is placed in /scripts in the VM by Vagrant. If you change, adapt the path. 
       oc process -f /scripts/metrics/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.${__OS_apps_domain},USE_PERSISTENT_STORAGE=false | oc create -n openshift-infra -f -
       # Add metricsPublicURL to master-config
       sed -i.orig -e "s/\(.*metricsPublicURL:\).*/\1 https:\/\/hawkular-metrics.${__OS_apps_domain}\/hawkular\/metrics/g" ${__MASTER_CONFIG}
       systemctl restart origin
       
       # Add capabilities to enable/disable metrics to every authenticated user
       oc create -f /scripts/metrics/allinone-scaler-clusterrole.json
       oc adm policy add-role-to-group allinone:scaler system:authenticated

       echo "[INFO] Installing disable-metrics script"
       chmod 755 /scripts/metrics/disable-metrics
       ln -s /scripts/metrics/disable-metrics /usr/local/bin/disable-metrics 
       echo "[INFO] Installing enable-metrics script"
       chmod 755 /scripts/metrics/enable-metrics
       ln -s /scripts/metrics/enable-metrics /usr/local/bin/enable-metrics 

       echo ""
       echo "[INFO] Please visit https:\/\/hawkular-metrics.${__OS_apps_domain} and accept the ssl certificate for the metrics to work"
       echo ""

       touch ${__TESTS_DIR}/addons.metrics.configured
     fi

     rm ${__TESTS_DIR}/addons.metrics.wanted
   fi

   # Create logging
   # TODO: For now it doesn't properly work, but still adding here
   if [ -f ${__TESTS_DIR}/addons.logging.wanted ]; then
     if [ ! -f ${__TESTS_DIR}/addons.logging.configured ]; then
       echo "[INFO] Creating and configuring logging"

       oc create -n openshift -f https://raw.githubusercontent.com/openshift/origin-aggregated-logging/master/deployer/deployer.yaml
       oc adm new-project logging --node-selector=""
       oc project logging
       oc secrets new logging-deployer nothing=/dev/null
       # This step creates all the required service accounts
       oc new-app logging-deployer-account-template
       # Modify the service accounts adding all the required roles
       oc policy add-role-to-user edit --serviceaccount logging-deployer
       oc policy add-role-to-user daemonset-admin --serviceaccount logging-deployer
       oc adm policy add-cluster-role-to-user oauth-editor system:serviceaccount:logging:logging-deployer
       oc adm policy add-scc-to-user privileged system:serviceaccount:logging:aggregated-logging-fluentd
       oc adm policy add-cluster-role-to-user cluster-reader system:serviceaccount:logging:aggregated-logging-fluentd
       # Deploy EFK stack and configure all the created pods (Add these if you want ops cluster: KIBANA_OPS_HOSTNAME=kibana-ops.${__OS_apps_domain},ENABLE_OPS_CLUSTER=true,ES_OPS_CLUSTER_SIZE=1)
       oc new-app logging-deployer-template \
          -p KIBANA_HOSTNAME=kibana.${__OS_apps_domain} \
          -p ES_CLUSTER_SIZE=1 \
          -p PUBLIC_MASTER_URL=https://${__public_address}:8443
       oc label nodes --all logging-infra-fluentd=true

       sed -i.orig -e "s/\(.*loggingPublicURL:\).*/\1 \"https:\/\/kibana.${__OS_apps_domain}\"/" ${__MASTER_CONFIG}
       
       systemctl restart origin

       # Wait for startup
       while [ `oc get pods --no-headers | grep Running | wc -l` -eq 0 ]; do sleep 1; done
       echo "Configuring resources"
       while [ `oc get pods --no-headers | grep Running | wc -l` -eq 1 ]; do sleep 1; done
       echo "Done"
       oc process logging-support-template | oc create -f - 
       echo "Logging ready"

       echo ""

       touch ${__TESTS_DIR}/addons.logging.configured
     fi

     rm ${__TESTS_DIR}/addons.logging.wanted
   fi

   origin_image_list=(
         # Origin images
         docker.io/openshift/origin-deployer:latest
         docker.io/openshift/origin-docker-registry:latest
         docker.io/openshift/origin-haproxy-router:latest
         docker.io/openshift/origin-pod:latest
         docker.io/openshift/origin-sti-builder:latest 
         docker.io/openshift/origin-docker-builder:latest
         # docker.io/openshift/origin-custom-docker-builder:latest
         docker.io/openshift/origin-gitserver:latest
         # docker.io/openshift/origin-f5-router:latest
         # docker.io/openshift/origin-keepalived-ipfailover:latest
         docker.io/openshift/origin-recycler:latest
         # Metrics
         docker.io/openshift/origin-metrics-deployer:latest
         docker.io/openshift/origin-metrics-hawkular-metrics:latest
         docker.io/openshift/origin-metrics-heapster:latest
         docker.io/openshift/origin-metrics-cassandra:latest
   )

   centos_image_list=(
         # Centos SCL
         docker.io/openshift/jenkins-1-centos7:latest
         docker.io/centos/mongodb-26-centos7:latest
         docker.io/centos/mysql-56-centos7:latest
         docker.io/centos/nodejs-010-centos7:latest
         docker.io/centos/perl-520-centos7:latest
         docker.io/centos/php-56-centos7:latest
         docker.io/centos/postgresql-94-centos7:latest
         docker.io/centos/python-34-centos7:latest
         docker.io/centos/ruby-22-centos7:latest
         # Add wildfly
   )

   rhel_image_list=(
         # RHEL SCL
         registry.access.redhat.com/openshift3/jenkins-1-rhel7:latest
         registry.access.redhat.com/rhscl/mongodb-26:Q-rhel7:latest
         registry.access.redhat.com/rhscl/mysql-56-rhel7:latest
         registry.access.redhat.com/rhscl/nodejs-010-rhel7:latest
         registry.access.redhat.com/rhscl/perl-520-rhel7:latest
         registry.access.redhat.com/rhscl/php-56-rhel7:latest
         registry.access.redhat.com/rhscl/postgresql-94-rhel7:latest
         registry.access.redhat.com/rhscl/python-34-rhel7:latest
         registry.access.redhat.com/rhscl/ruby-22-rhel7:latest
         # RHEL images
   )

   xpaas_image_list=(
         # New
         registry.access.redhat.com/jboss-webserver-3/webserver30-tomcat7-openshift
         registry.access.redhat.com/jboss-webserver-3/webserver30-tomcat8-openshift
         registry.access.redhat.com/jboss-eap-6/eap64-openshift
         registry.access.redhat.com/jboss-decisionserver-6/decisionserver62-openshift
         registry.access.redhat.com/jboss-datagrid-6/datagrid65-openshift
         registry.access.redhat.com/jboss-amq-6/amq62-openshift
         # Old
         registry.access.redhat.com/jboss-amq-6/amq-openshift:6.2
         registry.access.redhat.com/jboss-eap-6/eap-openshift:6.4
         registry.access.redhat.com/jboss-webserver-3/tomcat7-openshift:3.0
         registry.access.redhat.com/jboss-webserver-3/tomcat8-openshift:3.0
   )

   other_image_list=(
         # Samples
         docker.io/openshift/hello-openshift:latest
   )

   # Pull down images
   if [ -f ${__TESTS_DIR}/addons.originimages.wanted ]
   then
     if [ ! -f ${__TESTS_DIR}/addons.originimages.configured ]
     then
       echo "[INFO] Downloading Origin images"
       for image in ${origin_image_list[@]}; do
          echo "[INFO] Downloading image ${image}"
          docker pull $image
       done
       touch ${__TESTS_DIR}/addons.originimages.configured
     fi 
     rm ${__TESTS_DIR}/addons.originimages.wanted
   fi

   if [ -f ${__TESTS_DIR}/addons.centosimages.wanted ]
   then
     if [ ! -f ${__TESTS_DIR}/addons.centosimages.configured ]
     then
       echo "[INFO] Downloading CENTOS7 based images"
       for image in ${centos_image_list[@]}; do
          echo "[INFO] Downloading image ${image}"
          docker pull $image
       done
       touch ${__TESTS_DIR}/addons.centosimages.configured
     fi
     rm ${__TESTS_DIR}/addons.centosimages.wanted
   fi

   if [ -f ${__TESTS_DIR}/addons.rhelimages.wanted ]
   then
     if [ ! -f ${__TESTS_DIR}/addons.rhelimages.configured ]
     then
       echo "[INFO] Downloading RHEL7 based images"
       for image in ${rhel_image_list[@]}; do
          echo "[INFO] Downloading image ${image}"
          docker pull $image
       done
       touch ${__TESTS_DIR}/addons.rhelimages.configured
     fi  
     rm ${__TESTS_DIR}/addons.rhelimages.wanted
   fi

   if [ -f ${__TESTS_DIR}/addons.xpaasimages.wanted ]
   then
     if [ ! -f ${__TESTS_DIR}/addons.xpaasimages.configured ]
     then
       echo "[INFO] Downloading xPaaS RHEL7 based images"
       for image in ${xpaas_image_list[@]}; do
         echo "[INFO] Downloading image ${image}"
         docker pull $image
       done
       touch ${__TESTS_DIR}/addons.xpaasimages.configured
     fi
     rm ${__TESTS_DIR}/addons.xpaasimages.wanted
   fi

   if [ -f ${__TESTS_DIR}/addons.otherimages.wanted ]
   then
     if [ ! -f ${__TESTS_DIR}/addons.otherimages.configured ]
     then
       echo "[INFO] Downloading other images"
       for image in ${other_image_list[@]}; do
          echo "[INFO] Downloading image ${image}"
          docker pull $image
       done
       touch ${__TESTS_DIR}/addons.otherimages.configured
     fi

     rm ${__TESTS_DIR}/addons.otherimages.wanted
   fi
}

INSTALL_BASE_OS

DOCKER_SETUP

# We clean what we want to redo
[ "${__OS_action}" = "clean" ]  && clean_source && clean_install
[ "${__OS_action}" = "build" ]  && clean_target && clean_install
[ "${__OS_action}" = "config" ] && clean_install

# This will build
BUILD
# This will configure openshift
CONFIG

# Start Origin
systemctl start origin

ADD_RESOURCES

ADDONS
