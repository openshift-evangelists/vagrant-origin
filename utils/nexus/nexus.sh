echo "Creating nexus"

# oc login -u admin

# export REGISTRY=$(oc get service docker-registry -n default --template '{{.spec.clusterIP}}{{"\n"}}')
# export MYTOKEN=$(oc whoami -t)

docker pull sonatype/nexus
# NEXUS_IMG=$(docker images | grep "sonatype/nexus" | awk '{print $3}' | uniq)
# docker tag $NEXUS_IMG $REGISTRY:5000/sonatype/nexus:latest
# docker login -u adminuser -e mailto:adminuser@abc.com -p $MYTOKEN $REGISTRY:5000

# Create project
oc new-project ci
oc create -f nexus.json
oc deploy nexus

