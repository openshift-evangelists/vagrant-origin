#!/usr/bin/env bash
#

oc new-project ci --display-name="Continuous Integration for OpenShift" --description="This project holds all continuous integration required infrastructure, like Nexus, Jenkins,..."

oc create -f https://raw.githubusercontent.com/jorgemoralespou/nexus-ose/master/nexus/ose3/nexus-resources.json -n ci

mkdir /tmp/nexus

chmod 777 /tmp/nexus

oc create -f - <<-EOF
{
    "apiVersion": "v1",
    "kind": "PersistentVolume",
    "metadata": {
        "name": "nexus-pv",
        "labels": {
           "type": "local"
        }
    },
    "spec": {
        "hostPath": {
            "path": "/tmp/nexus"
        },
        "accessModes": [
            "ReadWriteOnce"
        ],
        "capacity": {
            "storage": "5Gi"
        },
        "persistentVolumeReclaimPolicy": "Retain"
    }
}
EOF

oc get scc hostaccess -o json \
        | sed '/\"users\"/a \"system:serviceaccount:ci:nexus\",'  \
        | oc replace scc hostaccess -f -

oc new-app --template=nexus-persistent --param=APPLICATION_HOSTNAME=nexus.apps.10.2.2.2.xip.io
