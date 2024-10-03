# ovirt-json2db.pl
# store oVirt metadata (metadata.json) in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use OVirtDataWrapper;
use Xorux_lib;

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

# load data source: metadata.json
my $conf_json = OVirtDataWrapper::get_conf();

################################################################################

# fill tables (template)

# 1. setup %data_in
#
# $data_in{$st_name}{DEVICE}{'Serial'} = …

# 2. put %data_in into %data_out
#
# my $hash_key                                                                                              = $st_serial;
# if ( exists $data_in{$st_name}{DEVICE}{'Version'} )             { $data_out{DEVICE}{$hash_key}{'version'} = $data_in{$st_name}{DEVICE}{'Version'} };

# 3. save %data_out
#
# my $params = {id => $st_serial, label => $st_name, hw_type => "NIMBLE"};
# SQLiteDataWrapper::object2db( $params );
# $params = { id => $st_serial, subsys => "DEVICE", data => $data_out{DEVICE} };
# SQLiteDataWrapper::subsys2db( $params );

################################################################################

# LPAR2RRD: oVirt assignment
# (TODO remove) object: hw_type => 'OVIRT', label => 'oVirt', id => 'DEADBEEF'
# params: id => 'DEADBEEF', subsys => '(DATACENTER|CLUSTER|HOST|HOST_NIC|VM|STORAGE_DOMAIN|DISK)', data => $data_out{(DATACENTER|CLUSTER|…)}

my $object_id = 'OVIRT';
my $params = { id => 'OVIRT', label => 'oVirt', hw_type => 'OVIRT' };
SQLiteDataWrapper::object2db($params);

# sample item removal based on HostCfg
#SQLiteDataWrapper::deleteItemFromConfig( {uuid => '969f58f4-87cd-4ae0-ac8f-f8b919d57995'} );

# datacenters

my @datacenters = @{ OVirtDataWrapper::get_uuids('datacenter') };
foreach my $datacenter_uuid (@datacenters) {
  my $datacenter_label = OVirtDataWrapper::get_label( 'datacenter', $datacenter_uuid );
  if ($datacenter_uuid) { $data_in{OVIRT}{$datacenter_uuid}{label} = $datacenter_label; }

  # add HostCfg UUID mappings from $conf_json->{architecture}{hostcfg} into hostcfg_relations
  my @hostcfg_datacenter;
  if ( exists $conf_json->{architecture}{hostcfg} && ref( $conf_json->{architecture}{hostcfg} ) eq 'HASH' ) {
    foreach my $hostcfg_uuid ( keys %{ $conf_json->{architecture}{hostcfg} } ) {
      my $hostcfg_datacenter = $conf_json->{architecture}{hostcfg}{$hostcfg_uuid}{datacenter};
      if ($hostcfg_datacenter) { push @hostcfg_datacenter, $hostcfg_uuid; }
    }
  }
  if ( scalar @hostcfg_datacenter ) { $data_in{OVIRT}{$datacenter_uuid}{hostcfg} = \@hostcfg_datacenter; }

  undef %data_out;
  if ( exists $data_in{OVIRT}{$datacenter_uuid}{label} )   { $data_out{$datacenter_uuid}{label}   = $data_in{OVIRT}{$datacenter_uuid}{label}; }
  if ( exists $data_in{OVIRT}{$datacenter_uuid}{hostcfg} ) { $data_out{$datacenter_uuid}{hostcfg} = $data_in{OVIRT}{$datacenter_uuid}{hostcfg}; }

  my $params = { id => $object_id, subsys => 'DATACENTER', data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  # clusters

  my @clusters = @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'cluster' ) };
  foreach my $cluster_uuid (@clusters) {
    my $cluster_label = OVirtDataWrapper::get_label( 'cluster', $cluster_uuid );
    if ($cluster_uuid) { $data_in{OVIRT}{$cluster_uuid}{label} = $cluster_label; }

    my @parents_datacenter;
    if ( exists $conf_json->{architecture}{cluster}{$cluster_uuid} ) {
      my $parent_datacenter = $conf_json->{architecture}{cluster}{$cluster_uuid}{parent};
      if ($parent_datacenter) { push @parents_datacenter, $parent_datacenter; }
    }
    if ( scalar @parents_datacenter ) { $data_in{OVIRT}{$cluster_uuid}{parents} = \@parents_datacenter; }

    undef %data_out;
    if ( exists $data_in{OVIRT}{$cluster_uuid}{label} )   { $data_out{$cluster_uuid}{label}   = $data_in{OVIRT}{$cluster_uuid}{label}; }
    if ( exists $data_in{OVIRT}{$cluster_uuid}{parents} ) { $data_out{$cluster_uuid}{parents} = $data_in{OVIRT}{$cluster_uuid}{parents}; }

    my $params = { id => $object_id, subsys => 'CLUSTER', data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    # hosts

    my @hosts = @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'host' ) };
    foreach my $host_uuid (@hosts) {
      my $host_label = OVirtDataWrapper::get_label( 'host', $host_uuid );
      if ($host_uuid) { $data_in{OVIRT}{$host_uuid}{label} = $host_label; }

      my @parents_cluster = @parents_datacenter;
      if ( exists $conf_json->{architecture}{host}{$host_uuid} ) {
        my $parent_cluster = $conf_json->{architecture}{host}{$host_uuid}{parent};
        if ($parent_cluster) { push @parents_cluster, $parent_cluster; }
      }
      if ( scalar @parents_cluster ) { $data_in{OVIRT}{$host_uuid}{parents} = \@parents_cluster; }

      # add agent mapping
      my $host_agent = OVirtDataWrapper::get_mapping($host_uuid);
      if ($host_agent) { $data_in{OVIRT}{$host_uuid}{mapped_agent} = $host_agent; }

      undef %data_out;
      if ( exists $data_in{OVIRT}{$host_uuid}{label} )        { $data_out{$host_uuid}{label}        = $data_in{OVIRT}{$host_uuid}{label}; }
      if ( exists $data_in{OVIRT}{$host_uuid}{parents} )      { $data_out{$host_uuid}{parents}      = $data_in{OVIRT}{$host_uuid}{parents}; }
      if ( exists $data_in{OVIRT}{$host_uuid}{mapped_agent} ) { $data_out{$host_uuid}{mapped_agent} = $data_in{OVIRT}{$host_uuid}{mapped_agent}; }

      my $params = { id => $object_id, subsys => 'HOST', data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);

      # NICs

      my @nics = @{ OVirtDataWrapper::get_arch( $host_uuid, 'host', 'nic' ) };
      foreach my $nic_uuid (@nics) {
        my $nic_label = OVirtDataWrapper::get_label( 'host_nic', $nic_uuid );
        if ($nic_uuid) { $data_in{OVIRT}{$nic_uuid}{label} = $nic_label; }

        my @parents_host = @parents_cluster;
        if ( exists $conf_json->{architecture}{host_nic}{$nic_uuid} ) {
          my $parent_host = $conf_json->{architecture}{host_nic}{$nic_uuid}{parent};
          if ($parent_host) { push @parents_host, $parent_host; }
        }
        if ( scalar @parents_host ) { $data_in{OVIRT}{$nic_uuid}{parents} = \@parents_host; }

        undef %data_out;
        if ( exists $data_in{OVIRT}{$nic_uuid}{label} )   { $data_out{$nic_uuid}{label}   = $data_in{OVIRT}{$nic_uuid}{label}; }
        if ( exists $data_in{OVIRT}{$nic_uuid}{parents} ) { $data_out{$nic_uuid}{parents} = $data_in{OVIRT}{$nic_uuid}{parents}; }

        my $params = { id => $object_id, subsys => 'HOST_NIC', data => \%data_out };
        SQLiteDataWrapper::subsys2db($params);
      }
    }

    # VMs

    my @vms = @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'vm' ) };
    foreach my $vm_uuid (@vms) {
      my $vm_label = OVirtDataWrapper::get_label( 'vm', $vm_uuid );
      if ($vm_uuid) { $data_in{OVIRT}{$vm_uuid}{label} = $vm_label; }

      my @parents_cluster = @parents_datacenter;
      if ( exists $conf_json->{architecture}{vm}{$vm_uuid} ) {
        my $parent_cluster = $conf_json->{architecture}{vm}{$vm_uuid}{parent};
        if ($parent_cluster) { push @parents_cluster, $parent_cluster; }
      }
      if ( scalar @parents_cluster ) { $data_in{OVIRT}{$vm_uuid}{parents} = \@parents_cluster; }

      # add agent mapping
      my $vm_agent = OVirtDataWrapper::get_mapping($vm_uuid);
      if ($vm_agent) { $data_in{OVIRT}{$vm_uuid}{mapped_agent} = $vm_agent; }

      undef %data_out;
      if ( exists $data_in{OVIRT}{$vm_uuid}{label} )        { $data_out{$vm_uuid}{label}        = $data_in{OVIRT}{$vm_uuid}{label}; }
      if ( exists $data_in{OVIRT}{$vm_uuid}{parents} )      { $data_out{$vm_uuid}{parents}      = $data_in{OVIRT}{$vm_uuid}{parents}; }
      if ( exists $data_in{OVIRT}{$vm_uuid}{mapped_agent} ) { $data_out{$vm_uuid}{mapped_agent} = $data_in{OVIRT}{$vm_uuid}{mapped_agent}; }

      my $params = { id => $object_id, subsys => 'VM', data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);

      # TODO VM_NIC
    }
  }

  # storage domains

  my @storage_domains = @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'storage_domain' ) };
  foreach my $storage_domain_uuid (@storage_domains) {
    my $storage_domain_label = OVirtDataWrapper::get_label( 'storage_domain', $storage_domain_uuid );
    if ($storage_domain_uuid) { $data_in{OVIRT}{$storage_domain_uuid}{label} = $storage_domain_label; }

    my @parents_storage_domain;
    if ( exists $conf_json->{architecture}{storage_domain}{$storage_domain_uuid} ) {
      my $parent_datacenter = $conf_json->{architecture}{storage_domain}{$storage_domain_uuid}{parent};
      if ($parent_datacenter) { push @parents_storage_domain, $parent_datacenter; }
    }
    if ( scalar @parents_storage_domain ) { $data_in{OVIRT}{$storage_domain_uuid}{parents} = \@parents_storage_domain; }

    undef %data_out;
    if ( exists $data_in{OVIRT}{$storage_domain_uuid}{label} )   { $data_out{$storage_domain_uuid}{label}   = $data_in{OVIRT}{$storage_domain_uuid}{label}; }
    if ( exists $data_in{OVIRT}{$storage_domain_uuid}{parents} ) { $data_out{$storage_domain_uuid}{parents} = $data_in{OVIRT}{$storage_domain_uuid}{parents}; }

    my $params = { id => $object_id, subsys => 'STORAGE_DOMAIN', data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    # disks

    my @disks = @{ OVirtDataWrapper::get_arch( $storage_domain_uuid, 'storage_domain', 'disk' ) };
    foreach my $disk_uuid (@disks) {
      my $disk_label = OVirtDataWrapper::get_label( 'disk', $disk_uuid );
      if ($disk_uuid) { $data_in{OVIRT}{$disk_uuid}{label} = $disk_label; }

      my @parents_disk = @parents_storage_domain;
      if ( exists $conf_json->{architecture}{disk}{$disk_uuid} ) {
        my $parent_storage_domain = $conf_json->{architecture}{disk}{$disk_uuid}{parent};
        if ($parent_storage_domain) { push @parents_disk, $parent_storage_domain; }
      }
      if ( scalar @parents_disk ) { $data_in{OVIRT}{$disk_uuid}{parents} = \@parents_disk; }

      undef %data_out;
      if ( exists $data_in{OVIRT}{$disk_uuid}{label} )   { $data_out{$disk_uuid}{label}   = $data_in{OVIRT}{$disk_uuid}{label}; }
      if ( exists $data_in{OVIRT}{$disk_uuid}{parents} ) { $data_out{$disk_uuid}{parents} = $data_in{OVIRT}{$disk_uuid}{parents}; }

      my $params = { id => $object_id, subsys => 'DISK', data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);
    }
  }
}

# finish
