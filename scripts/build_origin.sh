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
# $6 : Build Origin images (true|false)
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
__build_images=$6

__version="latest"
__MASTER_CONFIG="${__CONFIG_DIR}/openshift.local.config/master/master-config.yaml"
# Using http instead of https for allowing to local cache with squid for faster provisionings
__REPO="http://github.com/${__origin_repo}/origin.git"

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

  [ ! -d ${__BUILD_DIR}/origin ] && echo "[ERROR] There is no source to build. Check that the repo was properly checked out" && exit 1

  if [ ! -d ${__BUILD_DIR}/origin/_output ]
  then
    # We build
    cd ${__BUILD_DIR}/origin
    hack/build-go.sh
    # TODO: Test this
    if [ "${__build_images}" = "true" ]
    then
      hack/build-base-images.sh
      hack/build-release.sh
      hack/build-images.sh
      __version=$(git rev-parse --short "HEAD^{commit}" 2>/dev/null)
    fi

    # We copy the binaries into the <CONFIG_DIR>/bin and then link them
    mkdir -p ${__CONFIG_DIR}/bin
    pushd ${__BUILD_DIR}/origin/_output/local/bin/linux/amd64/
    for i in `ls *`; do cp -f ${i} ${__CONFIG_DIR}/bin; ln -s ${__CONFIG_DIR}/bin/${i} /usr/bin/ > /dev/null 2>&1; done
    popd
  fi
}

config(){
  [ -e ${__MASTER_CONFIG} ] && return 0
  echo "[INFO] Using images version ${__version}"

  echo "export CONFIG_DIR=${__CONFIG_DIR}" > /etc/profile.d/openshift.sh
  echo "export MASTER_DIR=${__CONFIG_DIR}/openshift.local.config/master" >> /etc/profile.d/openshift.sh
  echo "export KUBECONFIG=${__CONFIG_DIR}/openshift.local.config/master/admin.kubeconfig" >> /etc/profile.d/openshift.sh

  # TODO: Fix permissions for openshift.local.config, openshift.local.etcd, openshift.local.volumes
  # Create initial configuration for Origin
  openshift start --public-master=${__public_address} \
            --master=${__public_address} \
            --etcd-dir=${__CONFIG_DIR}/openshift.local.etcd \
            --write-config=${__CONFIG_DIR}/openshift.local.config \
            --volume-dir=${__CONFIG_DIR}/openshift.local.volumes \
            --images='openshift/origin-${component}:'${__version}

  chmod 666 ${__CONFIG_DIR}/openshift.local.config/master/*

  # Now we need to make some adjustments to the config
  sed -i.orig -e "s/\(.*subdomain:\).*/\1 ${__public_hostname}/" ${__MASTER_CONFIG}
  # This options below should not be needed, as openshift-start is handling these
#  -e "s/\(.*masterPublicURL:\).*/\1 https:\/\/${__public_address}:8443/g" \
#  -e "s/\(.*publicURL:\).*/\1 https:\/\/${__public_address}:8443\/console\//g" \
#  -e "s/\(.*assetPublicURL:\).*/\1 https:\/\/${__public_address}:8443\/console\//g"

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
  ExecStart=/usr/bin/openshift start --master-config=${__CONFIG_DIR}/openshift.local.config/master/master-config.yaml --node-config=${__CONFIG_DIR}/openshift.local.config/node-origin/node-config.yaml --public-master=${__public_address}

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
    oadm registry --create --credentials=${__CONFIG_DIR}/openshift.local.config/master/openshift-registry.kubeconfig
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
    oadm router --create --credentials=${__CONFIG_DIR}/openshift.local.config/master/openshift-router.kubeconfig --service-account=router
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
    )

    for template in ${template_list[@]}; do
      echo "[INFO] Importing template ${template}"
      oc create -f $template -n openshift >/dev/null
    done
    touch ${__CONFIG_DIR}/tests/${__base}.templates.configured
  fi

  # Add sample app. This needs to be lightweight and expose the app in a meaningful route
#  if [ ! -f ${__CONFIG_DIR}/tests/${__base}.sample.configured ]; then
#    echo "[INFO] Creating sample app"
    ## Add admin as a cluster-admin
#    oc new-project turbo --display-name="Turbo Sample" --description="This is an example project to demonstrate OpenShift v3"
#    oc process -f https://raw.githubusercontent.com/openshift/origin/master/examples/sample-app/application-template-stibuild.json | oc create -n turbo -f -
    # curl -skL -w "%{http_code} %{url_effective}\\n" -o /tmp/output -H 'Host: www.example.com' https://localhost:443

#    touch ${__CONFIG_DIR}/tests/${__base}.sample.configured
#  fi

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
