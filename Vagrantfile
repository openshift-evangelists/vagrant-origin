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
ACTION  = ENV['ACTION'] || "none" # (none, clean, build, config)
CONFIG  = ENV['CONFIG'] || "osetemplates,metrics" # testusers,originimages,centosimages,rhelimages,xpaasimages,otherimages,osetemplates,metrics
FORCE_PREREQS = ENV['FORCE_PREREQS']
FORCE_DOCKER  = ENV['FORCE_DOCKER']
FORCE_ADDONS  = ENV['FORCE_ADDONS']
BUILD_IMAGES  = ENV['BUILD_IMAGES'] || "false" # (true|false)
JOURNAL_SIZE = ENV['JOURNAL_SIZE'] || "100M" # (Use a number suffixed by M,G)
DOCKER_STORAGE_SIZE = ENV['DOCKER_STORAGE_SIZE'] || "30G" # (Use a number suffixed by G)

Vagrant.configure(2) do |config|

   config.vm.box = "fedora-23" # vagrant box add --name fedora-23 Fedora-Cloud-Base-Vagrant-23-20151030.x86_64.vagrant-libvirt.box
   config.vm.box_check_update = false
   config.vm.network "private_network", ip: "#{PUBLIC_ADDRESS}"
   config.vm.synced_folder "scripts", "/scripts", type: "rsync"
   config.vm.synced_folder "utils", "/utils", type: "rsync"
   config.vm.hostname = "origin"

   config.vm.provider "virtualbox" do |vb|
      #   vb.gui = true
      vb.memory = "4096"
      vb.cpus = 2
      vb.name = "origin"
   end

   config.vm.provider "libvirt" do |lv|
      lv.memory = "4096"
      lv.cpus = 2
   end

   # Install base requirements
   config.vm.provision :shell, :path => "./scripts/prerequisites.sh", :args => "#{JOURNAL_SIZE} #{FORCE_PREREQS}"
  
   # Setup the VM
   config.vm.provision :shell, :path => "./scripts/configure_docker.sh", :args => "#{DOCKER_STORAGE_SIZE} #{FORCE_DOCKER}"

   # Build Origin
   config.vm.provision :shell, :path => "./scripts/build_origin.sh", :args => "#{PUBLIC_ADDRESS} #{PUBLIC_DOMAIN} #{ACTION} #{ORIGIN_REPO} #{ORIGIN_BRANCH} #{BUILD_IMAGES}"

   # Run and configure Origin
   config.vm.provision :shell, :path => "./scripts/addons_origin.sh", :args => "#{PUBLIC_ADDRESS} #{PUBLIC_DOMAIN} #{CONFIG} #{FORCE_ADDONS}"

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
