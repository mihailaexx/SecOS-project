Vagrant.configure("2") do |config|

  config.ssh.username = "vagrant"
  config.ssh.password = "vagrant"
  config.ssh.insert_key = false

  config.vm.boot_timeout = 600

  config.vm.box = "fedora/42-cloud-base"
  config.vm.box_check_update = false

  config.vm.define "lb" do |lb|
    lb.vm.hostname = "lb-node"
    lb.vm.disk :disk, size: "10GB", primary: true
    lb.vm.network "private_network", ip: "192.168.56.10"
    lb.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
      vb.cpus = 1
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
    end
    lb.vm.provision "shell", path: "scripts/lb.sh"
  end
  config.vm.define "idp" do |idp|
    idp.vm.hostname = "idp-node"
    idp.vm.disk :disk, size: "20GB", primary: true
    idp.vm.network "private_network", ip: "192.168.56.20"
    idp.vm.network "forwarded_port", guest: 8080, host: 8080
    idp.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
      vb.cpus = 4
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
    end
    idp.vm.provision "shell", path: "scripts/idp.sh"
  end
  config.vm.define "nfs" do |nfs|
    nfs.vm.hostname = "storage-node"
    nfs.vm.disk :disk, size: "10GB", primary: true
    nfs.vm.disk :disk, size: "25GB", name: "storage_raid_1"
    nfs.vm.disk :disk, size: "25GB", name: "storage_raid_2"
    nfs.vm.network "private_network", ip: "192.168.56.50"
    nfs.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
      vb.cpus = 1
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
    end
    nfs.vm.provision "shell", path: "scripts/nfs.sh"
  end
  config.vm.define "bastion1" do |bastion1|
    bastion1.vm.hostname = "bastion-01"
    bastion1.vm.disk :disk, size: "10GB", primary: true
    bastion1.vm.network "private_network", ip: "192.168.56.11"
    bastion1.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
      vb.cpus = 1
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
    end
    bastion1.vm.provision "shell", path: "scripts/bastion.sh"
  end
  config.vm.define "bastion2" do |bastion2|
    bastion2.vm.hostname = "bastion-02"
    bastion2.vm.disk :disk, size: "10GB", primary: true
    bastion2.vm.network "private_network", ip: "192.168.56.12"
    bastion2.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
      vb.cpus = 1
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
    end
    bastion2.vm.provision "shell", path: "scripts/bastion.sh"
  end
  config.vm.define "target" do |target|
    target.vm.hostname = "test-server"
    target.vm.disk :disk, size: "10GB", primary: true
    target.vm.disk :disk, size: "20GB", name: "target_pgdata"
    target.vm.network "private_network", ip: "192.168.56.60"
    target.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
      vb.cpus = 1
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
    end
    target.vm.provision "shell", path: "scripts/target.sh"
  end
  config.vm.provision "shell", inline: <<-SHELL
    restorecon -rv /etc/NetworkManager/system-connections/
    nmcli con mod "enp0s8" ipv4.never-default yes 2>/dev/null || true
    nmcli con up "enp0s8" 2>/dev/null || true
  SHELL
end
