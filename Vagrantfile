# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Maintainer: Jorge Morales <jmorales@redhat.com>
#
#

VAGRANTFILE_API_VERSION = "2"
Vagrant.require_version ">= 1.7.2"

ORIGIN_REPO = ENV['ORIGIN_REPO'] || "openshift"
ORIGIN_BRANCH = ENV['ORIGIN_BRANCH'] || "master"
PUBLIC_ADDRESS = ENV['ORIGIN_VM_IP'] || "10.2.2.2"
PUBLIC_DOMAIN  = ENV['ORIGIN_VM_DOMAIN'] || "apps.#{PUBLIC_ADDRESS}.xip.io"
VM_MEM = ENV['ORIGIN_VM_MEM'] || 4096 # Memory used for the VM
ACTION  = ENV['ACTION'] || "none" # (none, clean, build, config)
CONFIG  = ENV['CONFIG'] || "osetemplates,metrics" # testusers,originimages,centosimages,rhelimages,xpaasimages,otherimages,osetemplates,metrics
FORCE_OS = ENV['FORCE_OS']
FORCE_DOCKER  = ENV['FORCE_DOCKER']
FORCE_ADDONS  = ENV['FORCE_ADDONS']
BUILD_IMAGES  = ENV['BUILD_IMAGES'] || "false" # (true|false)
JOURNAL_SIZE = ENV['JOURNAL_SIZE'] || "100M" # (Use a number suffixed by M,G)
DOCKER_STORAGE_SIZE = ENV['DOCKER_STORAGE_SIZE'] || "30G" # (Use a number suffixed by G)
HOSTNAME = "origin"

Vagrant.configure(2) do |config|

   config.vm.box = "fedora/23-cloud-base" 
   # vagrant box add --name fedora/23-cloud-base Fedora-Cloud-Base-Vagrant-23-20151030.x86_64.vagrant-libvirt.box
   config.vm.box_check_update = false
   config.vm.network "private_network", ip: "#{PUBLIC_ADDRESS}"
   config.vm.synced_folder ".", "/vagrant", disabled: true
   if Vagrant::Util::Platform.windows?
      config.vm.synced_folder "scripts", "/scripts"
      config.vm.synced_folder "utils", "/utils"
   else
      config.vm.synced_folder "scripts", "/scripts", type: "rsync"
      config.vm.synced_folder "utils", "/utils", type: "rsync"
   end
   # config.vm.hostname = "#{VM_MEM}" # It seems there is a bug in Vagrant that it does not properly manage hostname substtution and does not remove ipv6 names
   config.vm.provision "shell", inline: "hostname #{HOSTNAME}", run: "always"
   config.vm.provision "shell", inline: "sed -i.bak '/::1/d' /etc/hosts && echo '127.0.1.1 #{HOSTNAME}' >> /etc/hosts"

   config.vm.provider "virtualbox" do |vb|
      #   vb.gui = true
      vb.memory = "#{VM_MEM}"
      vb.cpus = 2
      vb.name = "origin"
   end

   config.vm.provider "libvirt" do |lv|
      lv.memory = "#{VM_MEM}".to_i
      lv.cpus = 2
   end

   # Install base requirements
   config.vm.provision :shell, :path => "./scripts/os-setup.sh", :args => "#{JOURNAL_SIZE} #{FORCE_OS}"

   # Setup the VM
   config.vm.provision :shell, :path => "./scripts/docker-setup.sh", :args => "#{DOCKER_STORAGE_SIZE} #{FORCE_DOCKER}"

   # Build Origin
   config.vm.provision :shell, :path => "./scripts/origin-setup.sh", :args => "#{PUBLIC_ADDRESS} #{PUBLIC_DOMAIN} #{ACTION} #{ORIGIN_REPO} #{ORIGIN_BRANCH} #{BUILD_IMAGES}"

   # Run and configure Origin
   config.vm.provision :shell, :path => "./scripts/addons-setup.sh", :args => "#{PUBLIC_ADDRESS} #{PUBLIC_DOMAIN} #{CONFIG} #{FORCE_ADDONS}"

   config.vm.provision :shell, inline: <<-SHELL
      echo ""
      echo "You can now access OpenShift console on: https://#{PUBLIC_ADDRESS}:8443/console"
      echo ""
      echo "To use OpenShift CLI, run:"
      echo "$ vagrant ssh"
      echo "$ sudo -i"
      echo "$ oc status"
      echo "$ oc whoami"
      echo ""
      echo "If you have the oc client library on your host, you can also login from your host."
      echo "$ oc login https://#{PUBLIC_ADDRESS}:8443"
      echo ""
   SHELL

end
