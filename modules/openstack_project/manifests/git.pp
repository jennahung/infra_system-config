# Copyright 2013 Hewlett-Packard Development Company, L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
# Class to configure haproxy to serve git on a CentOS node.
#
# == Class: openstack_project::git
class openstack_project::git (
  $sysadmins = [],
  $balancer_member_names = [],
  $balancer_member_ips = []
) {
  class { 'openstack_project::server':
    iptables_public_tcp_ports => [80, 443, 9418],
    sysadmins                 => $sysadmins,
  }

  if ($::osfamily == 'RedHat') {
    class { 'selinux':
      mode => 'enforcing'
    }
  }

  package { 'socat':
    ensure => present,
  }

  package { 'lsof':
    ensure => present,
  }

  class { 'haproxy':
    enable         => true,
    global_options => {
      'log'     => '127.0.0.1 local0',
      'chroot'  => '/var/lib/haproxy',
      'pidfile' => '/var/run/haproxy.pid',
      'maxconn' => '4000',
      'user'    => 'haproxy',
      'group'   => 'haproxy',
      'daemon'  => '',
      'stats'   => 'socket /var/lib/haproxy/stats user root group root mode 0600 level admin',
      'tune.ssl.default-dh-param' => '2048',
    },
  }
  # The three listen defines here are what the world will hit.
  haproxy::listen { 'balance_git_http':
#    ipaddress        => [$::ipaddress, $::ipaddress6],
    ipaddress        => [$::ipaddress],
    ports            => ['80'],
    mode             => 'tcp',
    collect_exported => false,
    options          => {
      'balance' => 'source',
      'option'  => [
        'tcplog',
      ],
    },
  }
  haproxy::listen { 'balance_git_https':
    bind => {
      "${::ipaddress}:443" => ['ssl', 'crt', "/etc/haproxy/certs/${::fqdn}.pem"]
    },
    mode             => 'tcp',
    collect_exported => false,
    options          => {
      'balance' => 'source',
      'option'  => [
        'tcplog',
      ],
    },
  }
  haproxy::listen { 'balance_git_daemon':
#    ipaddress        => [$::ipaddress, $::ipaddress6],
    ipaddress        => [$::ipaddress],
    ports            => ['9418'],
    mode             => 'tcp',
    collect_exported => false,
    options          => {
      'maxconn' => '32',
      'backlog' => '64',
      'balance' => 'source',
      'option'  => [
        'tcplog',
      ],
    },
  }
  haproxy::balancermember { 'balance_git_http_member':
    listening_service => 'balance_git_http',
    server_names      => $balancer_member_names,
    ipaddresses       => $balancer_member_ips,
    ports             => '8080',
  }
  haproxy::balancermember { 'balance_git_https_member':
    listening_service => 'balance_git_https',
    server_names      => $balancer_member_names,
    ipaddresses       => $balancer_member_ips,
    ports             => '8080',
  }
  haproxy::balancermember { 'balance_git_daemon_member':
    listening_service => 'balance_git_daemon',
    server_names      => $balancer_member_names,
    ipaddresses       => $balancer_member_ips,
    ports             => '29418',
    options           => 'maxqueue 512',
  }

  file { '/etc/rsyslog.d/haproxy.conf':
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    source => 'puppet:///modules/openstack_project/git/rsyslog.haproxy.conf',
    notify => Service['rsyslog'],
  }

  cron { 'certbot':
    command => "certbot renew --renew-hook 'cat /etc/letsencrypt/live/${::fqdn}/fullchain.pem /etc/letsencrypt/live/${::fqdn}/privkey.pem > /etc/haproxy/certs/${::fqdn}.pem; service haproxy restart'",
    user => 'root',
    hour => [1, 13],
    minute => 6,
  }
}
