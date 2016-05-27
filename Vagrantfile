# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Maintainer: Jorge Morales <jmorales@redhat.com>
#
#

VAGRANTFILE_API_VERSION = "2"
Vagrant.require_version ">= 1.7.2"

VM_MEM = ENV['ORIGIN_VM_MEM'] || 4096 # Memory used for the VM
HOSTNAME = "origin"

Vagrant.configure(2) do |config|

   config.vm.box = "centos/7" 
   config.vm.box_check_update = false
   config.vm.network "private_network", ip: "10.2.2.2"
   config.vm.synced_folder ".", "/vagrant", disabled: true
   if Vagrant::Util::Platform.windows?
      config.vm.synced_folder "config", "/config"
      config.vm.synced_folder "scripts", "/scripts"
      config.vm.synced_folder "utils", "/utils"
   else
      config.vm.synced_folder "config", "/config", type: "rsync"
      config.vm.synced_folder "scripts", "/scripts", type: "rsync"
      config.vm.synced_folder "utils", "/utils", type: "rsync"
   end

   # config.vm.hostname = "#{VM_MEM}" # It seems there is a bug in Vagrant that it does not properly manage hostname substtution and does not remove ipv6 names
   config.vm.provision "shell", inline: "hostname #{HOSTNAME}", run: "always"
   config.vm.provision "shell", inline: "sed -i.bak '/::1/d' /etc/hosts && echo '127.0.1.1 #{HOSTNAME}' >> /etc/hosts"

   config.vm.provider "virtualbox" do |vb|
      vb.memory = "#{VM_MEM}"
      vb.cpus = 2
      vb.name = "origin"
   end

   config.vm.provider "libvirt" do |lv|
      lv.memory = "#{VM_MEM}".to_i
      lv.cpus = 2
   end

   config.vm.provision :shell, :path => "./scripts/install.sh"

   config.vm.provision :shell, inline: <<-SHELL
      echo ""
      echo "You can now access OpenShift console on: https://10.2.2.2:8443/console"
      echo ""
      echo "To use OpenShift CLI, run:"
      echo "$ vagrant ssh"
      echo "$ sudo -i"
      echo "$ oc status"
      echo "$ oc whoami"
      echo ""
      echo "If you have the oc client library on your host, you can also login from your host."
      echo "$ oc login https://10.2.2.2:8443"
      echo ""
   SHELL

end
