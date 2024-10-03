# orvm-json2db.pl
# store OracleVM metadata (metadata.json) in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use OracleVmDataWrapper;
use Xorux_lib;

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

# load data source: metadata.json
my $conf_json = OracleVmDataWrapper::get_conf();

#print Dumper $conf_json;
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

# LPAR2RRD: OracleVM assignment
# (TODO remove) object: hw_type => 'ORACLEVM', label => 'OracleVM', id => 'DEADBEEF'
# params: id => 'DEADBEEF', subsys => '(MANAGER|SERVER_POOL|SERVER|VM)', data => $data_out{(DATACENTER|CLUSTER|…)}

my $object_hw_type = "ORACLEVM";
my $object_label   = "OracleVM";
my $object_id      = "ORACLEVM";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

# managers
#my @datacenters = @{OVirtDataWrapper::get_uuids('datacenter')};
my @orvm_managers = @{ OracleVmDataWrapper::get_uuids('manager') };
foreach my $orvm_uuid (@orvm_managers) {
  my $orvm_label = OracleVmDataWrapper::get_label( 'manager', $orvm_uuid );
  if ($orvm_uuid) { $data_in{ORACLEVM}{$orvm_uuid}{label} = $orvm_label; }

  # add HostCfg UUID mappings from $conf_json->{architecture}{hostcfg} into hostcfg_relations
  my @hostcfg_manager;
  if ( exists $conf_json->{architecture}{hostcfg} && ref( $conf_json->{architecture}{hostcfg} ) eq 'HASH' ) {
    foreach my $hostcfg_uuid ( keys %{ $conf_json->{architecture}{hostcfg} } ) {
      my $hostcfg_manager = $conf_json->{architecture}{hostcfg}{$hostcfg_uuid}{manager};
      if ($hostcfg_manager) { push @hostcfg_manager, $hostcfg_uuid; }
    }
  }
  if ( scalar @hostcfg_manager ) { $data_in{ORACLEVM}{$orvm_uuid}{hostcfg} = \@hostcfg_manager; }

  undef %data_out;
  if ( exists $data_in{ORACLEVM}{$orvm_uuid}{label} )   { $data_out{$orvm_uuid}{label}   = $data_in{ORACLEVM}{$orvm_uuid}{label}; }
  if ( exists $data_in{ORACLEVM}{$orvm_uuid}{hostcfg} ) { $data_out{$orvm_uuid}{hostcfg} = $data_in{ORACLEVM}{$orvm_uuid}{hostcfg}; }

  my $params = { id => $object_id, subsys => 'MANAGER', data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  #print Dumper $params;

  # server_pools
  foreach my $serverpool_uuid ( @{ OracleVmDataWrapper::get_arch_manager( $orvm_uuid, 'manager_s', 'server_pool' ) } ) {
    my $serverpool_label = OracleVmDataWrapper::get_label( 'server_pool', $serverpool_uuid );
    if ($serverpool_uuid) { $data_in{ORACLEVM}{$serverpool_uuid}{label} = $serverpool_label; }

    my @parents_manager;
    if ( exists $conf_json->{architecture}{server_pool}{$serverpool_uuid} ) {
      my $parent_manager = $conf_json->{architecture}{server_pool}{$serverpool_uuid}{parent};
      if ($parent_manager) { push @parents_manager, $parent_manager; }
    }

    if ( scalar @parents_manager ) { $data_in{ORACLEVM}{$serverpool_uuid}{parents} = \@parents_manager; }

    undef %data_out;
    if ( exists $data_in{ORACLEVM}{$serverpool_uuid}{label} )   { $data_out{$serverpool_uuid}{label}   = $data_in{ORACLEVM}{$serverpool_uuid}{label}; }
    if ( exists $data_in{ORACLEVM}{$serverpool_uuid}{parents} ) { $data_out{$serverpool_uuid}{parents} = $data_in{ORACLEVM}{$serverpool_uuid}{parents}; }

    my $params = { id => $object_id, subsys => 'SERVERPOOL', data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    #print Dumper $params;

    # servers
    foreach my $server_uuid ( @{ OracleVmDataWrapper::get_arch( $serverpool_uuid, 'server_pool', 'server' ) } ) {
      my $server_label = OracleVmDataWrapper::get_label( 'server', $server_uuid );
      if ($server_uuid) { $data_in{ORACLEVM}{$server_uuid}{label} = $server_label; }

      my @parents_serverpools = @parents_manager;
      if ( exists $conf_json->{specification}{server}{$server_uuid} ) {
        my $parent_server_pool = $conf_json->{specification}{server}{$server_uuid}{parent_serverpool};
        if ($parent_server_pool) { push @parents_serverpools, $parent_server_pool; }

      }
      if ( scalar @parents_serverpools ) { $data_in{ORACLEVM}{$server_uuid}{parents} = \@parents_serverpools; }
      undef %data_out;
      if ( exists $data_in{ORACLEVM}{$server_uuid}{label} )   { $data_out{$server_uuid}{label}   = $data_in{ORACLEVM}{$server_uuid}{label}; }
      if ( exists $data_in{ORACLEVM}{$server_uuid}{parents} ) { $data_out{$server_uuid}{parents} = $data_in{ORACLEVM}{$server_uuid}{parents}; }

      my $params = { id => $object_id, subsys => 'SERVER', data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);

      #print Dumper $params; # delete

    }

    # vms
    my @vms = @{ OracleVmDataWrapper::get_arch( $serverpool_uuid, 'server_pool', 'vm' ) };
    foreach my $vm_uuid (@vms) {
      my $vm_label = OracleVmDataWrapper::get_label( 'vm', $vm_uuid );
      if ($vm_uuid) { $data_in{ORACLEVM}{$vm_uuid}{label} = $vm_label; }

      my @parents_serverpools = @parents_manager;
      if ( exists $conf_json->{specification}{vm}{$vm_uuid} ) {
        my $parent_server_pool = $conf_json->{specification}{vm}{$vm_uuid}{parent_server_pool};
        if ($parent_server_pool) { push @parents_serverpools, $parent_server_pool; }
      }
      if ( scalar @parents_serverpools ) { $data_in{ORACLEVM}{$vm_uuid}{parents} = \@parents_serverpools; }

      undef %data_out;
      if ( exists $data_in{ORACLEVM}{$vm_uuid}{label} )   { $data_out{$vm_uuid}{label}   = $data_in{ORACLEVM}{$vm_uuid}{label}; }
      if ( exists $data_in{ORACLEVM}{$vm_uuid}{parents} ) { $data_out{$vm_uuid}{parents} = $data_in{ORACLEVM}{$vm_uuid}{parents}; }

      my $params = { id => $object_id, subsys => 'VM', data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);

      #print Dumper $params; # delete

    }

  }

}

#print Dumper \%data_in;
#print Dumper \%data_out;
#print Dumper $params;
# finish
