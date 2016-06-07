#!/usr/bin/env bash
#
# Create NFS volume
#
# Params:
#   $1: Volume name/number
#

. /scripts/base/common_functions

must_run_as_root

[ -z $1 ] && echo "[ERROR]You need to specify the volume name to this script" && exit 1
[ -z $2 ] && echo "[ERROR]You need to specify the namespace for the PVC to this script" && exit 2
[ -z $3 ] && echo "[ERROR]You need to specify the PVC name to this script" && exit 3

__volume=$1
__namespace=$2
__claim=$3

# Make sure /nfsvolumes exists and has proper permissions
if [ ! -d /nfsvolumes ]
then
   mkdir /nfsvolumes
   chown nfsnobody:nfsnobody /nfsvolumes
   chmod 777 /nfsvolumes
   echo "[INFO] /nfsvolumes directory created"
fi

# Create this volume
mkdir -p /nfsvolumes/${__volume}
chown nfsnobody:nfsnobody /nfsvolumes/${__volume}
chmod 777 /nfsvolumes/${__volume}

# Add the volume to /etc/exports and reload
# If the volume does not exists already
if [[ "$(cat /etc/exports | grep ${__volume})" == "" ]]
then
  echo "/nfsvolumes/${__volume} *(rw,no_root_squash)" >> /etc/exports
  # Enable the new exports without bouncing the NFS service
  exportfs -a
else
  echo "[WARN] NFS Volume ${__volume} already existing in disc. Not updated"
fi

echo "[INFO] Creating NFS PV ${__volume} using from 10Gi in ReadWriteMany or ReadWriteOnly mode and Recycle Policy."

# Get the uid of the PVC
__uid=$(sudo_oc get pvc/${__claim} -o json -n ${__namespace} | jq -r '.metadata.uid')

cat <<-EOF > /tmp/pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${__volume}
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
    - ReadWriteMany
  claimRef:
    apiVersion: v1
    kind: PersistentVolumeClaim
    name: ${__claim}
    namespace: ${__namespace}
    uid: ${__uid}
  persistentVolumeReclaimPolicy: Recycle
  nfs:
    server: localhost
    path: /nfsvolumes/${__volume}
EOF

sudo_oc create -f /tmp/pv.yaml
echo "[INFO] PV Created"
echo "$(sudo_oc get pv/${__volume})"
