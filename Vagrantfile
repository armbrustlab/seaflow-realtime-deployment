# -*- mode: ruby -*-
# vi: set ft=ruby :

$set_source_environment_variables = <<SCRIPT
tee "/etc/profile.d/myvars.sh" > "/dev/null" <<EOF
# Broadcast IP
export BROADCAST_IP=192.168.1.255
EOF
SCRIPT


Vagrant.configure("2") do |config|
  config.vm.define "source" do |source|
    source.vm.hostname = "source"
    source.vm.box = "ubuntu/focal64"
    source.vm.network "public_network", bridge: "en8: Thunderbolt Ethernet", ip: "192.168.1.20"
    # source.vm.network "forwarded_port", id: "ssh", host: 2222, guest: 22
    source.ssh.forward_agent = true
    source.vm.provider "virtualbox" do |v|
      v.memory = 800
      v.cpus = 1
    end
    source.vm.synced_folder "./cruisereplay_data", "/cruisereplay_data"

    source.vm.provision "shell", inline: $set_source_environment_variables, run: "always"
    source.vm.provision "shell", inline: "echo '192.168.1.21 sink sink' >>/etc/hosts"

    source.vm.provision "shell", inline: <<-SHELL
      sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
      systemctl restart sshd.service
    SHELL
    #source.vm.provision "ansible" do |ansible|
    #  ansible.playbook = "ansible/playbook-source.yml"
    #end
  end
  
  config.vm.define "sink" do |sink|
    sink.vm.hostname = "sink"
    sink.vm.box = "ubuntu/focal64"
    sink.vm.network "public_network", bridge: "en8: Thunderbolt Ethernet", ip: "192.168.1.21"
    # sink.vm.network "forwarded_port", id: "ssh", host: 2221, guest: 22
    # sink.vm.network "forwarded_port", id: "postgres", host: 5432, guest: 5432
    # sink.vm.network "forwarded_port", id: "grafana", host: 3000, guest: 3000
    # sink.vm.network "forwarded_port", id: "minio-api", host: 9000, guest: 9000
    # sink.vm.network "forwarded_port", id: "minio-console", host: 9001, guest: 9001
    sink.vm.provider "virtualbox" do |v|
      v.memory = 16000
      v.cpus = 2
    end
    sink.vm.synced_folder "./jobs_data", "/jobs_data"
    sink.vm.synced_folder "./consul_state", "/consul_state"
    sink.vm.provision "shell", inline: "echo '192.168.1.20 source source' >>/etc/hosts"

    #sink.vm.provision "ansible" do |ansible|
    #  ansible.playbook = "ansible/playbook-sink.yml"
    #end
  end

  
end
