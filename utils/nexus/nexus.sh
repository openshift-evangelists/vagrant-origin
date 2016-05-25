echo "Creating nexus"

# oc login -u admin

docker pull sonatype/nexus

# Create project
oc new-project ci
oc create -f nexus.json
oc new-app nexus-persistent

