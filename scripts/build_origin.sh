#!/usr/bin/env bash
#
# Maintainer: Jorge Morales <jmorales@redhat.com>
#
# Prepare, configure and start OpenShift
#
# $1 : Public IP Address
# $2 : Public host name
# $3 : Action to do   (clean, build, config) Just one of them
# $4 : Github Origin repo
# $5 : Github Origin branch
#
# You can use a ENV (FORCE_ORIGIN) with anyvalue that will force installing whatever addon you have selected

#set -o nounset

# This script must be run as root
[ "$UID" -ne 0 ] && echo "To run this script you need root permissions (either root or sudo)" && exit 1

__base="build_origin"
__BUILD_DIR="/go/src/github.com/openshift"
__CONFIG_DIR="/var/lib/origin"
__TESTS_DIR=${__CONFIG_DIR}/tests
__BIN_DIR=${__CONFIG_DIR}/bin

mkdir -p ${__TESTS_DIR}

__public_address=$1
__public_hostname=$2
__action=$3
__origin_repo=$4
__origin_branch=$5

__MASTER_CONFIG="${__CONFIG_DIR}/openshift.local.config/master/master-config.yaml"
__REPO="https://github.com/${__origin_repo}/origin.git"

[ ! -z ${FORCE_ORIGIN} ] && echo "[INFO] Forcing reinstallation of things" && rm ${__TESTS_DIR}/${__base}.*.configured

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
  rm -rf ${__CONFIG_DIR}/tests/${__base}*
  rm -rf ${__CONFIG_DIR}/tests/addons_origin*

  systemctl start docker
}

# Checkout
__checkout(){
  echo "[INFO] No origin source, so let's checkout and build it"
  mkdir -p ${__BUILD_DIR}

  pushd ${__BUILD_DIR}
  echo "[INFO] Cloning $__REPO at branch ${__origin_branch}"
  git clone ${__REPO} -b ${__origin_branch} 
  popd
}

# Update
__update(){
  pushd ${__BUILD_DIR}/origin
  echo "[INFO] Updating to latest"
  git pull
  popd 
}

build(){
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

  if [ ! -d ${__BUILD_DIR}/origin/_output ]
  then
    # We build  
    cd ${__BUILD_DIR}/origin
    hack/build-go.sh

    # We copy the binaries into the <CONFIG_DIR>/bin and then link them
    mkdir -p ${__CONFIG_DIR}/bin
    pushd ${__BUILD_DIR}/origin/_output/local/bin/linux/amd64/
    for i in `ls *`; do cp -f ${i} ${__CONFIG_DIR}/bin; ln -s ${__CONFIG_DIR}/bin/${i} /usr/bin/ > /dev/null 2>&1; done
    popd
  fi
}

config(){
  [ -e ${__MASTER_CONFIG} ] && return 0

  echo "export CONFIG_DIR=${__CONFIG_DIR}" > /etc/profile.d/openshift.sh
  echo "export MASTER_DIR=${__CONFIG_DIR}/openshift.local.config/master" >> /etc/profile.d/openshift.sh
  echo "export KUBECONFIG=${__CONFIG_DIR}/openshift.local.config/master/admin.kubeconfig" >> /etc/profile.d/openshift.sh

  # TODO: Fix permissions for openshift.local.config, openshift.local.etcd, openshift.local.volumes
  # Create initial configuration for Origin
  openshift start --public-master=${__public_address} \
            --master=${__public_address} \
            --etcd-dir=${__CONFIG_DIR}/openshift.local.etcd \
            --write-config=${__CONFIG_DIR}/openshift.local.config \
            --volume-dir=${__CONFIG_DIR}/openshift.local.volumes

  chmod 666 ${__CONFIG_DIR}/openshift.local.config/master/*

  # Now we need to make some adjustments to the config
  # TODO: I think this is not needed anymore
#  sed -i.orig -e "s/\(.*subdomain:\).*/\1 ${__public_hostname}/" ${__MASTER_CONFIG} \
#  -e "s/\(.*masterPublicURL:\).*/\1 https:\/\/${__public_address}:8443/g" \
#  -e "s/\(.*publicURL:\).*/\1 https:\/\/${__public_address}:8443\/console\//g" \
#  -e "s/\(.*assetPublicURL:\).*/\1 https:\/\/${__public_address}:8443\/console\//g"

  # Run Origin
  # openshift start --master-config=/var/lib/origin/openshift.local.config/master/master-config.yaml --node-config=/var/lib/origin/openshift.local.config/node-localhost/node-config.yaml --public-master=#{PUBLIC_ADDRESS}
  cat <<-EOF > /etc/systemd/system/origin.service
  [Unit]
  Description=OpenShift
  After=docker.target network.target

  [Service]
  Type=notify
  ExecStart=/usr/bin/openshift start --master-config=/var/lib/origin/openshift.local.config/master/master-config.yaml --node-config=/var/lib/origin/openshift.local.config/node-localhost/node-config.yaml --public-master=${__public_address}

  [Install]
  WantedBy=multi-user.target
EOF
  systemctl enable origin
}

add_resources() {
  . /etc/profile.d/openshift.sh
  
  # Install Registry
  if [ ! -f ${__CONFIG_DIR}/tests/${__base}.registry.configured ]; then
    echo "[INFO] Creating the OpenShift Registry"
    oadm registry --create --credentials=/var/lib/origin/openshift.local.config/master/openshift-registry.kubeconfig
    touch ${__CONFIG_DIR}/tests/${__base}.registry.configured
  fi

  # Install Router
  if [ ! -f ${__CONFIG_DIR}/tests/${__base}.router.configured ]; then
    echo "[INFO] Creating the OpenShift Router"
    ## Add Router Service Account to default namespace
    echo '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"router","namespace":"default"}}' | oc create -f -
    ## Add router ServiceAccount to privileged SCC
    oc get scc privileged -o json  | sed '/\"users\"/a \"system:serviceaccount:default:router\",' | oc replace scc privileged -f -
    ## Create the router
    oadm router --create --credentials=/var/lib/origin/openshift.local.config/master/openshift-router.kubeconfig --service-account=router 
    touch ${__CONFIG_DIR}/tests/${__base}.router.configured
  fi

  # Add admin as cluster-admin
  if [ ! -f ${__CONFIG_DIR}/tests/${__base}.users.configured ]; then
    echo "[INFO] Creating and configuring users"
    ## Add admin as a cluster-admin
    oadm policy add-cluster-role-to-user cluster-admin admin 
    touch ${__CONFIG_DIR}/tests/${__base}.users.configured
  fi

  # Installing templates into OpenShift
  if [ ! -f ${__CONFIG_DIR}/tests/${__base}.templates.configured ]; then
    echo "[INFO] Installing Origin templates"

    template_list=(
      # Image streams
      https://raw.githubusercontent.com/openshift/origin/master/examples/image-streams/image-streams-centos7.json
      # DB templates
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/mongodb-ephemeral-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/mongodb-persistent-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/mysql-ephemeral-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/mysql-persistent-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/postgresql-ephemeral-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/db-templates/postgresql-persistent-template.json
      # Jenkins
      https://raw.githubusercontent.com/openshift/origin/master/examples/jenkins/jenkins-ephemeral-template.json
      https://raw.githubusercontent.com/openshift/origin/master/examples/jenkins/jenkins-persistent-template.json
      # Node.js
      https://raw.githubusercontent.com/openshift/nodejs-ex/master/openshift/templates/nodejs-mongodb.json
      https://raw.githubusercontent.com/openshift/nodejs-ex/master/openshift/templates/nodejs.json
    )
    
    for template in ${template_list[@]}; do
      echo "[INFO] Importing template ${template}"
      oc create -f $template -n openshift >/dev/null
    done
    touch ${__CONFIG_DIR}/tests/${__base}.templates.configured
  fi

}


# We clean what we want to redo
[ "${__action}" = "clean" ]  && clean_source && clean_install
[ "${__action}" = "build" ]  && clean_target && clean_install
[ "${__action}" = "config" ] && clean_install
# This will build
build
# This will configure openshift
config

# Start Origin
systemctl start origin

add_resources