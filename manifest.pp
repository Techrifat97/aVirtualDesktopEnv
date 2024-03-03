# Example: install_slim_and_desktop_and_vnc.pp
node /^virtualdesktop-\d+\.openstacklocal$/ {
# Install expect tool
package { 'expect':
  ensure => installed,
}

# Set DEBIAN_FRONTEND to noninteractive
exec { 'set_noninteractive_env':
  command => 'sudo sh -c "echo \"export DEBIAN_FRONTEND=noninteractive\" >> /etc/environment"',
  path    => '/bin',
}

# Install Slim display manager
package { 'slim':
  ensure => installed,
}

# Use expect to automate the download prompt for Slim
exec { 'install_slim_with_expect':
  command => 'expect -c "spawn apt-get install -y slim; expect \\"Do you want to continue?\\" { send \\"y\\r\\" }"',
  path    => '/bin',
  unless  => 'dpkg -l slim | grep -q ^ii',
  require => [Package['slim'], Exec['set_noninteractive_env']],
}

# Preconfigure Slim as the default display manager
exec { 'set_default_display_manager':
  command => 'sudo sh -c "echo \"slim shared/default-x-display-manager select slim\" | debconf-set-selections"',
  path    => '/bin',
  unless  => 'debconf-show slim | grep -q "shared/default-x-display-manager: slim"',
  require => Exec['install_slim_with_expect'],
}

# Reconfigure Slim to apply the preconfiguration
exec { 'reconfigure_slim':
  command => 'sudo dpkg-reconfigure -f noninteractive slim',
  path    => '/bin',
  unless  => 'debconf-show slim | grep -q "shared/default-x-display-manager: slim"',
  require => Exec['set_default_display_manager'],
}

# Install Ubuntu Desktop
package { 'ubuntu-desktop':
  ensure  => installed,
  require => Exec['set_noninteractive_env'],
}

# Install TigerVNC standalone server
package { 'tigervnc-standalone-server':
  ensure  => installed,
  require => Exec['set_noninteractive_env'],
}

# Execute vncserver with password "infoops" for both regular and view-only password
exec { 'configure_vncserver':
  command  => 'expect -c "spawn vncserver -localhost no; expect {Password: {send \"infoops\\r\"; exp_continue} verify: {send \"infoops\\r\"; exp_continue} Would you like to enter a view-only password (y/n)? {send \"n\\r\"; exp_continue}}"',
  path     => '/usr/bin',
  unless   => 'vncserver -list | grep -q "Xvnc :1"',
  require  => Package['tigervnc-standalone-server'],
  cwd      => '/home/ubuntu',
  logoutput => true,  # Log the output for debugging
  environment => ["HOME=/home/ubuntu"],  # Set the HOME environment variable
  timeout  => 600,  # Adjust timeout as needed
}

# Use a basic xterm session for the VNC server
exec { 'start_xterm_session':
  command  => 'sudo sh -c "echo \'#!/bin/sh\' > /etc/X11/Xtigervnc-session; echo \'exec /usr/bin/xterm -geometry 1024x768 -ls -name login -display $DISPLAY\' >> /etc/X11/Xtigervnc-session; chmod +x /etc/X11/Xtigervnc-session"',
  path     => '/bin',
  unless   => 'test -f /etc/X11/Xtigervnc-session',
  require  => Exec['configure_vncserver'],
}
#Enable and start Slim display manager service
service { 'slim':
  ensure  => 'running',
  enable  => true,
  require => [Package['slim'], Package['tigervnc-standalone-server'], Exec['configure_vncserver']],
}

# User configurations
$user_names = ['john', 'alice', 'bob', 'kate']

user { $user_names:
  ensure     => 'present',
  managehome => true,
}

include nfs_client
}
# mongodb.pp}
node 'mongodb-server.openstacklocal' {
# Install MongoDB dependencies
# Example: install_mongodb.pp

# Install MongoDB dependencies
package { ['gnupg', 'wget', 'apt-transport-https', 'ca-certificates', 'software-properties-common']:
  ensure => installed,
}

# Import MongoDB GPG key
exec { 'import_mongodb_gpg_key':
  command => 'wget -qO- https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor | sudo tee /usr/share/keyrings/mongodb-server-7.0.gpg >/dev/null',
  path    => '/bin',
  creates => '/usr/share/keyrings/mongodb-server-7.0.gpg',
  require => Package['gnupg'],
}

# Add MongoDB repository
exec { 'add_mongodb_repository':
  command => "echo \"deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse\" | sudo tee -a /etc/apt/sources.list.d/mongodb-org-7.0.list",
  path    => '/bin',
  require => Exec['import_mongodb_gpg_key'],
}

# Update package lists
exec { 'update_package_lists':
  command => 'sudo apt-get update',
  path    => '/usr/bin',
  require => Exec['add_mongodb_repository'],
}

# Install MongoDB
package { 'mongodb-org':
  ensure => installed,
  require => Exec['update_package_lists'],
}

# Enable and start MongoDB service
service { 'mongod':
  ensure  => 'running',
  enable  => true,
  require => Package['mongodb-org'],
}

}
node 'nfs-server.openstacklocal' {
  # Install nfs server package
  package { 'nfs-kernel-server':
    ensure => installed,
  }

  # Define shared directory - exports
  file { '/etc/exports':
    ensure  => file,
    content => "/shared *(rw,sync,no_root_squash,no_subtree_check)\n",
    notify  => Service['nfs-kernel-server'],
  }

  # Check that nfs service is running
  service { 'nfs-kernel-server':
    ensure => running,
    enable => true,
    require => Package['nfs-kernel-server'],
  }
}

# Class for NFS client setup
class nfs_client {
  package { 'nfs-common':
    ensure => installed,
  }

  # Creating mount point
  file { '/mnt/nfs_share':
    ensure => 'directory',
  }

  # Add an entry to /etc/fstab to mount the NFS
  mount { '/mnt/nfs_share':
    ensure  => 'mounted',
    atboot  => true,
    device  => '10.196.38.83:/shared',
    fstype  => 'nfs',
    options => 'defaults',
    require => [ Package['nfs-common'], File['/mnt/nfs_share'] ],
  }
}
