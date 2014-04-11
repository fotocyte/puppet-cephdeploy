#   Copyright 2013-2014 Cisco Systems, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#   Author: Donald Talton <dotalton@cisco.com>

# === Parameters:
#
# [*ceph_deploy_user*]
#   (required) The cephdeploy account username
#
# [*ceph_deploy_password*]
#   (required) The cephdeploy account password.
#
# [*ceph_monitor_fsid*]
#   (required) The ceph monitor fsid.
#     generated by running 'uuidgen'
#   Defaults to 'present'
#
# [*mon_initial_members*]
#   (required) The mon member for the initial monmap.
#
# [*ceph_monitor_address*]
#   (required) The IP address of the initial mon member.
#
# [*ceph_public_network*]
#   (required) The client-facing network.
#
# [*ceph_cluster_network*]
#   (required) The data replication network.
#
# [*ceph_release*]
#   (required) The Ceph release to use.
#
# [*has_compute*]
#   (required) Whether or not the host has nova-compute running.


class cephdeploy(
  $ceph_deploy_user,
  $ceph_deploy_password,
  $ceph_monitor_fsid,
  $mon_initial_members,
  $ceph_monitor_address,
  $ceph_public_network,
  $ceph_cluster_network,
  $ceph_release = 'emperor',
  $has_compute = false,
){

## User setup

  user {$ceph_deploy_user:
    ensure   => present,
    password => $ceph_deploy_password,
    home     => "/home/$ceph_deploy_user",
    shell    => '/bin/bash',
  }

  file {"/home/$ceph_deploy_user":
    ensure  => directory,
    owner   => $ceph_deploy_user,
    group   => $ceph_deploy_user,
    mode    => 0755,
    require => User[$ceph_deploy_user],
  }

  file {"/home/$ceph_deploy_user/.ssh":
    ensure  => directory,
    owner   => $ceph_deploy_user,
    group   => $ceph_deploy_user,
    mode    => 0700,
    require => File["/home/$ceph_deploy_user"],
  }

  file {"/home/$ceph_deploy_user/.ssh/id_rsa":
    content => template('cephdeploy/id_rsa.erb'),
    owner   => $ceph_deploy_user,
    group   => $ceph_deploy_user,
    mode    => 0600,
    require => File["/home/$ceph_deploy_user/.ssh"],
  }

  file {"/home/$ceph_deploy_user/.ssh/id_rsa.pub":
    content => template('cephdeploy/id_rsa.pub.erb'),
    owner   => $ceph_deploy_user,
    group   => $ceph_deploy_user,
    mode    => 0644,
    require => File["/home/$ceph_deploy_user/.ssh"],
  }

  file {"/home/$ceph_deploy_user/.ssh/authorized_keys":
    content => template('cephdeploy/id_rsa.pub.erb'),
    owner   => $ceph_deploy_user,
    group   => $ceph_deploy_user,
    mode    => 0600,
    require => File["/home/$ceph_deploy_user/.ssh"],
  }

  file {"/home/$ceph_deploy_user/.ssh/config":
    content => template('cephdeploy/config.erb'),
    owner   => $ceph_deploy_user,
    group   => $ceph_deploy_user,
    mode    => 0600,
    require => File["/home/$ceph_deploy_user/.ssh"],
  }

  file {"log $ceph_deploy_user":
    owner   => $ceph_deploy_user,
    group   => $ceph_deploy_user,
    mode    => 0777,
    path    => "/home/$ceph_deploy_user/bootstrap/ceph.log",
    require => [ Exec['install ceph'], File["/etc/sudoers.d/$ceph_deploy_user"], File["/home/$ceph_deploy_user"], User[$ceph_deploy_user] ],
  }

  exec {'passwordless sudo for ceph deploy user':
    command => "/bin/echo \"$ceph_deploy_user ALL = (root) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/$ceph_deploy_user",
    unless  => "/usr/bin/test -e /etc/sudoers.d/$ceph_deploy_user",
  }

  file {"/etc/sudoers.d/$ceph_deploy_user":
    mode    => 0440,
    require => Exec['passwordless sudo for ceph deploy user'],
  }

  file { "/home/$ceph_deploy_user/zapped":
    ensure => directory,
  }

  file {"/home/$ceph_deploy_user/bootstrap":
    ensure => directory,
    owner  => $ceph_deploy_user,
    group  => $ceph_deploy_user,
  }

## Install ceph and dependencies

  case $::osfamily {
    'RedHat', 'Suse': {
      cephdeploy::yum {'ceph-packages':
	release => $ceph_release,
      }
    }
    'Debian': {
      cephdeploy::apt {'ceph-packages':
        release => $ceph_release,
      }
    }
  }

  package {'ceph-deploy':
    ensure => present,
  }

## ceph.conf setup

  concat { "/home/$ceph_deploy_user/bootstrap/ceph.conf":
    owner   => $ceph_deploy_user,
    group   => $ceph_deploy_user,
    path    => "/home/$ceph_deploy_user/bootstrap/ceph.conf",
    require => File["/home/$ceph_deploy_user/bootstrap"],
  }

  concat::fragment { 'ceph':
    target  => "/home/$ceph_deploy_user/bootstrap/ceph.conf",
    order   => '01',
    content => template('cephdeploy/ceph.conf.erb'),
    require => File["/home/$ceph_deploy_user/bootstrap"],
  }

## Keyring setup

  file { 'ceph.mon.keyring':
    owner   => $ceph_deploy_user,
    group   => $ceph_deploy_user,
    path    => "/home/$ceph_deploy_user/bootstrap/ceph.mon.keyring",
    content => template('cephdeploy/ceph.mon.keyring.erb'),
    require => File["/home/$ceph_deploy_user/bootstrap/ceph.conf"],
  }

  file {'service perms':
    mode    => 0644,
    path    => '/etc/ceph/ceph.client.admin.keyring',
    require => Exec['install ceph'],
  }

  exec { 'install ceph':
    cwd     => "/home/$ceph_deploy_user/bootstrap",
    command => "/usr/bin/ceph-deploy install --no-adjust-repos $::hostname",
    require => [ Package['ceph-deploy'], File['ceph.mon.keyring'], File["/home/$ceph_deploy_user/bootstrap"] ],
  }

  case $::osfamily {
    'RedHat': {
      file { '/lib/udev/rules.d/95-ceph-osd.rules':
        ensure  => file,
        content => template('cephdeploy/95-ceph-osd.rules.erb'),
	require => Exec['install ceph']
      }
    }
  }

  file { '/etc/ceph/ceph.conf':
    mode    => 0644,
    require => Exec['install ceph'],
  }

## If the ceph node is also running nova-compute

  if $has_compute {

    file { '/etc/ceph/secret.xml':
      content => template('cephdeploy/secret.xml-compute.erb'),
      require => Exec["install ceph"],
    }

    exec { 'get-or-set virsh secret':
      command => '/usr/bin/virsh secret-define --file /etc/ceph/secret.xml | /usr/bin/awk \'{print $2}\' | sed \'/^$/d\' > /etc/ceph/virsh.secret',
      creates => "/etc/ceph/virsh.secret",
      require => [ File['/etc/ceph/ceph.conf'], Package['libvirt-bin'], File['/etc/ceph/secret.xml'] ],
    }

    exec { 'set-secret-value virsh':
      command => "/usr/bin/virsh secret-set-value --secret $(cat /etc/ceph/virsh.secret) --base64 $(ceph auth get-key client.admin)",
      require => [ Exec['get-or-set virsh secret'], Exec['install ceph'] ],
    }

  }


}
