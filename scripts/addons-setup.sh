#!/usr/bin/env bash
#
# Maintainer: Jorge Morales <jmorales@redhat.com>
#
# Prepare, configure and start OpenShift
#
# $1 : Public IP Address
# $2 : Public host name
# $3 : Config (testusers,originimages,centosimages,rhelimages,xpaasimages,otherimages,osetemplates,metrics)
# $4 : Force
#
# The execution of this script will create a set of files <TESTS_DIR>/<THIS_SCRIPT_FILENAME>.<FUNCTION>.configured
# that can be deleted in order to rerun the function when running the script
#
# You can use a param (Force) with anyvalue that will force installing whatever addon you have selected

#set -o nounset

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"

# This script must be run as root
[ "$UID" -ne 0 ] && echo "To run this script you need root permissions (either root or sudo)" && exit 1

__base="addons_origin"
__BUILD_DIR="/go/src/github.com/openshift"
__CONFIG_DIR="/var/lib/origin"
__TESTS_DIR=${__CONFIG_DIR}/tests
__BIN_DIR=${__CONFIG_DIR}/bin

mkdir -p ${__TESTS_DIR}

__public_address=$1
__public_hostname=$2
__config=$3
__force=$4


__MASTER_CONFIG="${__CONFIG_DIR}/openshift.local.config/master/master-config.yaml"
template_ose_tag=ose-v1.2.0-1

. /etc/profile.d/openshift.sh

[ ! -z ${__force} ] && echo "[INFO] Forcing reinstallation of things" && rm ${__TESTS_DIR}/${__base}.*.configured

# TODO: Depending on the action, delete control files
arr=$(echo ${__config} | tr "," "\n")
for x in ${arr}
do
   touch ${__TESTS_DIR}/${__base}.${x}.wanted
done

# Installing templates into OpenShift
if [ -f ${__TESTS_DIR}/${__base}.osetemplates.wanted ]; then
  if [ ! -f ${__TESTS_DIR}/${__base}.osetemplates.configured ]; then
    echo "[INFO] Installing OpenShift templates"

  template_list=(
    ## SCL: Ruby 2, Ruby 2.2, Node.js 0.10, Perl 5.16, Perl 5.20, PHP 5.5, PHP 5.6, Python 3.4, Python 3.3, Python 2.7)
    ## Databases: Mysql 5.5, Mysql 5.6, PostgreSQL 9.2, PostgreSQL 9.4, Mongodb 2.4, Mongodb 2.6, Jenkins
    https://raw.githubusercontent.com/openshift/origin/master/examples/image-streams/image-streams-rhel7.json    
    ## JBoss Image streams(JWS, EAP, JDG, BRMS, AMQ)
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/jboss-image-streams.json
    ## Fuse Image Streams
    https://raw.githubusercontent.com/jboss-fuse/application-templates/master/fis-image-streams.json
    # EAP
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-amq-persistent-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-amq-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-basic-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-https-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-mongodb-persistent-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-mongodb-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-mysql-persistent-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-mysql-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-postgresql-persistent-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/eap/eap64-postgresql-s2i.json
    # DecisionServer
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/decisionserver/decisionserver62-amq-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/decisionserver/decisionserver62-basic-s2i.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/decisionserver/decisionserver62-https-s2i.json
    # Fuse
    ## No templates. They are created by mvn:io.fabric8.archetypes
    # DataGrid
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/datagrid/datagrid65-basic.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/datagrid/datagrid65-https.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/datagrid/datagrid65-mysql-persistent.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/datagrid/datagrid65-mysql.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/datagrid/datagrid65-postgresql-persistent.json
    https://raw.githubusercontent.com/jboss-openshift/application-templates/${template_ose_tag}/datagrid/datagrid65-postgresql.json

  )

    for template in ${template_list[@]}; do
      echo "[INFO] Importing template ${template}"
      oc create -f $template -n openshift >/dev/null
    done
    touch ${__TESTS_DIR}/${__base}.osetemplates.configured
  fi

  rm ${__TESTS_DIR}/${__base}.osetemplates.wanted
fi

# Create users
if [ -f ${__TESTS_DIR}/${__base}.testusers.wanted ]; then
  if [ ! -f ${__TESTS_DIR}/${__base}.testusers.configured ]; then
    echo "[INFO] Creating and configuring test users"
   
    ## Add whatever user you might want
    # oadm policy add-cluster-role-to-user cluster-admin admin 
    touch ${__TESTS_DIR}/${__base}.testusers.configured
  fi
   
  rm ${__TESTS_DIR}/${__base}.testusers.wanted
fi

# Create metrics
if [ -f ${__TESTS_DIR}/${__base}.metrics.wanted ]; then
  if [ ! -f ${__TESTS_DIR}/${__base}.metrics.configured ]; then
    echo "[INFO] Creating and configuring metrics"
   
    oc create -f https://raw.githubusercontent.com/openshift/origin-metrics/master/metrics-deployer-setup.yaml -n openshift-infra
    oadm policy add-role-to-user edit system:serviceaccount:openshift-infra:metrics-deployer -n openshift-infra
    oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:openshift-infra:heapster -n openshift-infra
    oc secrets new metrics-deployer nothing=/dev/null -n openshift-infra
    # This file is placed in /scripts in the VM by Vagrant. If you change, adapt the path. 
    oc process -f /scripts/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.${__public_hostname},USE_PERSISTENT_STORAGE=false | oc create -n openshift-infra -f -
    # Add metricsPublicURL to master-config
    sed -i.orig -e "s/\(.*metricsPublicURL:\).*/\1 https:\/\/hawkular-metrics.${__public_hostname}\/hawkular\/metrics/g" ${__MASTER_CONFIG}
    systemctl restart origin

    echo ""
    echo "[INFO] Please visit https:\/\/hawkular-metrics.${__public_hostname} and accept the ssl certificate for the metrics to work"
    echo ""

    touch ${__TESTS_DIR}/${__base}.metrics.configured
  fi

  rm ${__TESTS_DIR}/${__base}.metrics.wanted
fi

# Create logging
# TODO: For now it doesn't properly work, but still adding here
if [ -f ${__TESTS_DIR}/${__base}.logging.wanted ]; then
  if [ ! -f ${__TESTS_DIR}/${__base}.logging.configured ]; then
    echo "[INFO] Creating and configuring logging"
   
    oadm new-project logging
    oc secrets new logging-deployer nothing=/dev/null -n logging
    oc create -f - <<API
apiVersion: v1
kind: ServiceAccount
metadata:
  name: logging-deployer
secrets:
- name: logging-deployer
API
    oadm policy add-scc-to-user privileged system:serviceaccount:logging:aggregated-logging-fluentd
    oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:logging:aggregated-logging-fluentd
    oadm policy add-cluster-role-to-user cluster-admin system:serviceaccount:logging:logging-deployer
    oc policy add-role-to-user edit system:serviceaccount:logging:logging-deployer
    oc process logging-deployer-template -n openshift \
           -v KIBANA_HOSTNAME=kibana.apps.10.2.2.2.xip.io,ES_CLUSTER_SIZE=1,PUBLIC_MASTER_URL=https://10.2.2.2:8443 \
           | oc create -f -
    #
    while [ `oc get pods --no-headers | grep Running | wc -l` -eq 0 ]; do sleep 1; done
    echo "Configuring resources"
    while [ `oc get pods --no-headers | grep Running | wc -l` -eq 1 ]; do sleep 1; done
    echo "Done"
    oc process logging-support-template | oc create -f - 
    echo "Logging ready"

    echo ""

    touch ${__TESTS_DIR}/${__base}.logging.configured
  fi

  rm ${__TESTS_DIR}/${__base}.logging.wanted
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
      docker.io/openshift/mongodb-24-centos7:latest
      docker.io/openshift/mysql-55-centos7:latest
      docker.io/openshift/nodejs-010-centos7:latest
      docker.io/openshift/perl-516-centos7:latest
      docker.io/openshift/php-55-centos7:latest
      docker.io/openshift/postgresql-92-centos7:latest
      docker.io/openshift/python-33-centos7:latest
      docker.io/openshift/ruby-20-centos7:latest
      # Add wildfly
)

rhel_image_list=(
      # RHEL SCL
      registry.access.redhat.com/openshift3/jenkins-1-rhel7:latest
      registry.access.redhat.com/openshift3/mongodb-24-rhel7:latest
      registry.access.redhat.com/openshift3/mysql-55-rhel7:latest
      registry.access.redhat.com/openshift3/nodejs-010-rhel7:latest
      registry.access.redhat.com/openshift3/perl-516-rhel7:latest
      registry.access.redhat.com/openshift3/php-55-rhel7:latest
      registry.access.redhat.com/openshift3/postgresql-92-rhel7:latest
      registry.access.redhat.com/openshift3/python-33-rhel7:latest
      registry.access.redhat.com/openshift3/ruby-20-rhel7:latest
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
if [ -f ${__TESTS_DIR}/${__base}.originimages.wanted ]
then
  if [ ! -f ${__TESTS_DIR}/${__base}.originimages.configured ]
  then
    echo "[INFO] Downloading Origin images"
    for image in ${origin_image_list[@]}; do
       echo "[INFO] Downloading image ${image}"
       docker pull $image
    done
    touch ${__TESTS_DIR}/${__base}.originimages.configured
  fi 
  rm ${__TESTS_DIR}/${__base}.originimages.wanted
fi

if [ -f ${__TESTS_DIR}/${__base}.centosimages.wanted ]
then
  if [ ! -f ${__TESTS_DIR}/${__base}.centosimages.configured ]
  then
    echo "[INFO] Downloading CENTOS7 based images"
    for image in ${centos_image_list[@]}; do
       echo "[INFO] Downloading image ${image}"
       docker pull $image
    done
    touch ${__TESTS_DIR}/${__base}.centosimages.configured
  fi
  rm ${__TESTS_DIR}/${__base}.centosimages.wanted
fi

if [ -f ${__TESTS_DIR}/${__base}.rhelimages.wanted ]
then
  if [ ! -f ${__TESTS_DIR}/${__base}.rhelimages.configured ]
  then
    echo "[INFO] Downloading RHEL7 based images"
    for image in ${rhel_image_list[@]}; do
       echo "[INFO] Downloading image ${image}"
       docker pull $image
    done
    touch ${__TESTS_DIR}/${__base}.rhelimages.configured
  fi  
  rm ${__TESTS_DIR}/${__base}.rhelimages.wanted
fi

if [ -f ${__TESTS_DIR}/${__base}.xpaasimages.wanted ]
then
  if [ ! -f ${__TESTS_DIR}/${__base}.xpaasimages.configured ]
  then
    echo "[INFO] Downloading xPaaS RHEL7 based images"
    for image in ${xpaas_image_list[@]}; do
      echo "[INFO] Downloading image ${image}"
      docker pull $image
    done
    touch ${__TESTS_DIR}/${__base}.xpaasimages.configured
  fi
  rm ${__TESTS_DIR}/${__base}.xpaasimages.wanted
fi

if [ -f ${__TESTS_DIR}/${__base}.otherimages.wanted ]
then
  if [ ! -f ${__TESTS_DIR}/${__base}.otherimages.configured ]
  then
    echo "[INFO] Downloading other images"
    for image in ${other_image_list[@]}; do
       echo "[INFO] Downloading image ${image}"
       docker pull $image
    done
    touch ${__TESTS_DIR}/${__base}.otherimages.configured
  fi

  rm ${__TESTS_DIR}/${__base}.otherimages.wanted
fi