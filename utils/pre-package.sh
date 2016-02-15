#!/usr/bin/env bash
#
#
# Preparing the box for packaging. Will remove all unneeded logs, etc...

# make sure you you have already added sample-app from the origin repo to the installation
# https://github.com/openshift/origin/blob/master/examples/sample-app/application-template-stibuild.json

# Remove Non used containers - run as root
_exited=$(docker ps -aqf "status=exited")
[ "" != "${_exited}" ] && echo "[INFO] Deleting exited containers" && docker rm -vf ${_exited}

_created=$(docker ps -aqf "status=created")
[ "" != "${_created}" ] && echo "[INFO] Deleting created containers" && docker rm -vf ${_created}

# Remove unused images
_untagged=$(docker images | grep "<none>" | awk '{print $3}')
[ "" != "${_untagged}" ] && echo "[INFO] Deleting untagged images" && docker rmi ${_untagged}
_dangling=$(docker images -f "dangling=true" -q)
[ "" != "${_dangling}" ] && echo "[INFO] Deleting dangling images" && docker rmi ${_dangling}

#to address the vagrant bug - run these as the vagrant user
curl https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant.pub > .ssh/authorized_keys 
chmod 700 .ssh
chmod 600 .ssh/authorized_keys
chown -R vagrant:vagrant .ssh
oc edit scc restricted #change RunAsUser to RunAsAny

#for Postgres from Crunchy to work run as root
#in /etc/passwd:
#postgres:x:26:26:PostgreSQL Server:/var/lib/pgsql:/bin/bash

#in /etc/group:
#postgres:x:26:



# Stop services run as root
echo "[INFO] Stopping Origin service"
systemctl stop origin
echo "[INFO] Stopping Docker service"
systemctl stop docker

# Remove all source code, etc... run as root
echo "[INFO] Removing /go source tree"
rm -rf /go

# Remove all cache run as root
echo "[INFO] Clean dnf"
dnf clean all

# Clean out all of the caching dirs run as root
echo "[INFO] Clear cache and logs"
rm -rf /var/cache/* /usr/share/doc/*
# Remove logs run as root
rm -rf /var/log/journal/*
rm -f /var/log/anaconda/*
rm -f /var/log/audit/*
rm -f /var/log/*.log

# Compact disk space run as root
echo "[INFO] Compacting disk"
dd if=/dev/zero of=/EMPTY bs=1M
rm -f /EMPTY
sync

#final step
# vagrant package --base origin --output openshift3-1.1.1.1.box --vagrantfile ~/openshiftVagrant/Vagrantfile
# then upload it to Atlas
