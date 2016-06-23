echo "[INFO] Creating nexus"

# oc login -u admin
docker pull openshiftdemos/nexus:2.13.0-01

# Create project
oc new-project ci
oc create -f nexus.yaml
