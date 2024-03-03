terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

provider "openstack" {
  cloud = "openstack" # defined in ~/.config/openstack/clouds.yaml
}

variable "puppet_master_ip" {
  description = "IP address of the Puppet Master"
  default     = "10.196.38.74"
}

resource "openstack_compute_instance_v2" "VirtualDesktop_instance" {
  count         = 4
  name          = "VirtualDesktop-${count.index + 1}"
  flavor_name   = "csh.1c2r"
  key_pair      = "MasterKey"
  security_groups = ["ssh-only"]

  block_device {
    uuid               = "6094568b-0d16-48a5-bc10-66645c361d4a"
    source_type        = "image"
    volume_size        = 25
    boot_index         = 0
    destination_type   = "volume"
    delete_on_termination = true
  }

  network {
    name = "acit"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y wget",
      "wget https://apt.puppetlabs.com/puppet8-release-jammy.deb",
      "sudo dpkg -i puppet8-release-jammy.deb",
      "sudo apt-get update",
      "sudo apt-get install -y puppet-agent",
      "echo '${var.puppet_master_ip} puppetmaster.openstacklocal puppetmaster' | sudo tee -a /etc/hosts",
      "echo '[main]' | sudo tee -a /etc/puppetlabs/puppet/puppet.conf > /dev/null",
      "echo 'certname = virtualdesktop-${count.index + 1}.openstacklocal' | sudo tee -a /etc/puppetlabs/puppet/puppet.conf > /dev/null",
      "echo 'server = puppetmaster.openstacklocal' | sudo tee -a /etc/puppetlabs/puppet/puppet.conf > /dev/null",
      "sudo systemctl start puppet",
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_ed25519")
      host        = self.network.0.fixed_ip_v4
    }
  }
}
output "VirtualDesktop_instance_ips" {
  value = [for instance in openstack_compute_instance_v2.VirtualDesktop_instance : instance.network.0.fixed_ip_v4]
}
#mongodb Server
resource "openstack_compute_instance_v2" "MongoDB_Server" {
  count         = 1
  name          = "MongoDB-Server"
  flavor_name   = "csh.1c2r"
  key_pair      = "MasterKey"
  security_groups = ["ssh-only"]

  block_device {
    uuid               = "6094568b-0d16-48a5-bc10-66645c361d4a"
    source_type        = "image"
    volume_size        = 25
    boot_index         = 0
    destination_type   = "volume"
    delete_on_termination = true
  }

  network {
    name = "acit"
  }

  provisioner "remote-exec" {
  inline = [
    "sudo apt-get update",
    "sudo apt-get install -y wget",
    "wget https://apt.puppetlabs.com/puppet8-release-jammy.deb",
    "sudo dpkg -i puppet8-release-jammy.deb",
    "sudo apt-get update",
    "sudo apt-get install -y puppet-agent",
    "echo '${var.puppet_master_ip} puppetmaster.openstacklocal puppetmaster' | sudo tee -a /etc/hosts",
    "echo '[main]' | sudo tee -a /etc/puppetlabs/puppet/puppet.conf > /dev/null",
    "echo 'certname = mongodb-server.openstacklocal' | sudo tee -a /etc/puppetlabs/puppet/puppet.conf > /dev/null",
    "echo 'server = puppetmaster.openstacklocal' | sudo tee -a /etc/puppetlabs/puppet/puppet.conf > /dev/null",
    "sudo systemctl start puppet",
  ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_ed25519")
      host        = self.network.0.fixed_ip_v4
    }
  }
}
output "MongoDB_Server_ip" {
  value = openstack_compute_instance_v2.MongoDB_Server.0.network.0.fixed_ip_v4
}


resource "openstack_compute_instance_v2" "nfs_server" {
  name         = "NFS-Server"
  image_name   = "Ubuntu 20.04"  
  flavor_name  = "csh.1c2r"      
  key_pair     = "MasterKey"     
  security_groups = ["default", "ssh-only"]

  network {
    name = "acit"
  }

  block_device {
    uuid                  = "6094568b-0d16-48a5-bc10-66645c361d4a" 
    source_type           = "image"
    volume_size           = 25
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  user_data = <<-EOF
    runcmd:
      - apt-get update && apt-get install -y nfs-kernel-server
      - echo "/srv/nfs *(rw,sync,no_root_squash,no_subtree_check)" > /etc/exports
      - systemctl restart nfs-kernel-server
  EOF

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y wget",
      "wget https://apt.puppetlabs.com/puppet8-release-jammy.deb",
      "sudo dpkg -i puppet8-release-jammy.deb",
      "sudo apt-get update",
      "sudo apt-get install -y puppet-agent",
      "echo '${var.puppet_master_ip} puppetmaster.openstacklocal puppetmaster' | sudo tee -a /etc/hosts",
      "echo '[main]' | sudo tee -a /etc/puppetlabs/puppet/puppet.conf > /dev/null",
      "echo 'certname = nfs-server.openstacklocal' | sudo tee -a /etc/puppetlabs/puppet/puppet.conf > /dev/null",
      "echo 'server = puppetmaster.openstacklocal' | sudo tee -a /etc/puppetlabs/puppet/puppet.conf > /dev/null",
      "sudo systemctl start puppet",
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_ed25519")
      host        = self.network.0.fixed_ip_v4
    }
  }

}
output "nfs_server_ip" {
  value = openstack_compute_instance_v2.nfs_server.network.0.fixed_ip_v4
}

resource "null_resource" "local_execution" {
  depends_on = [openstack_compute_instance_v2.nfs_server]

  provisioner "local-exec" {
    command = "sleep 30 && sudo /opt/puppetlabs/bin/puppetserver ca sign --all"
  }
}
