# proxmox-json2db.pl
# store Proxmox metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use ProxmoxDataWrapper;
use Xorux_lib;
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('Proxmox') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'PROXMOX'});
  exit(0);
}

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source: conf.json

my $conf_json  = ProxmoxDataWrapper::get_conf();
my $label_json = ProxmoxDataWrapper::get_conf_label();

################################################################################

my $object_hw_type = "PROXMOX";
my $object_label   = "Proxmox";
my $object_id      = "PROXMOX";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

my @clusters = @{ ProxmoxDataWrapper::get_items( { item_type => 'cluster' } ) };
foreach my $cluster (@clusters) {
  my ( $cluster_id, $cluster_label ) = each %{$cluster};

  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $cluster_id } );

  $data_in{$object_hw_type}{$cluster_id}{label} = $cluster_label;

  undef %data_out;
  if ( exists $data_in{$object_hw_type}{$cluster_id}{label} ) { $data_out{$cluster_id}{label} = $data_in{$object_hw_type}{$cluster_id}{label}; }

  my @hostcfg;
  push( @hostcfg, $cluster_id );
  $data_out{$cluster_id}{hostcfg} = \@hostcfg;

  my $params = { id => $object_id, subsys => "CLUSTER", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  #nodes
  my @nodes = @{ ProxmoxDataWrapper::get_items( { item_type => 'node', parent_type => 'cluster', parent_id => $cluster_id } ) };
  foreach my $node (@nodes) {
    my ( $node_uuid, $node_label ) = each %{$node};

    if ( exists $label_json->{label}{node}{$node_uuid} ) { $data_in{$object_hw_type}{$node_uuid}{label} = $label_json->{label}{node}{$node_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{node}{$node_uuid} } ) {
      if ( !defined $conf_json->{specification}{node}{$node_uuid}{$spec_key} || ref( $conf_json->{specification}{node}{$node_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{node}{$node_uuid}{$spec_key} ) eq "ARRAY" ) {
        next;
      }
      else {
        $data_in{$object_hw_type}{$node_uuid}{$spec_key} = $conf_json->{specification}{node}{$node_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $cluster_id;
    $data_in{$object_hw_type}{$node_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$node_uuid}{label} )   { $data_out{$node_uuid}{label}   = $data_in{$object_hw_type}{$node_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$node_uuid}{parents} ) { $data_out{$node_uuid}{parents} = $data_in{$object_hw_type}{$node_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{node}{$node_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$node_uuid}{$spec_key} ) { $data_out{$node_uuid}{$spec_key} = $data_in{$object_hw_type}{$node_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "NODE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #vm
  my @vms = @{ ProxmoxDataWrapper::get_items( { item_type => 'vm', parent_type => 'cluster', parent_id => $cluster_id } ) };
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( exists $label_json->{label}{vm}{$vm_uuid} ) { $data_in{$object_hw_type}{$vm_uuid}{label} = $label_json->{label}{vm}{$vm_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{vm}{$vm_uuid} } ) {
      if ( !defined $conf_json->{specification}{vm}{$vm_uuid}{$spec_key} || ref( $conf_json->{specification}{vm}{$vm_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{vm}{$vm_uuid}{$spec_key} ) eq "ARRAY" ) {
        next;
      }
      else {
        $data_in{$object_hw_type}{$vm_uuid}{$spec_key} = $conf_json->{specification}{vm}{$vm_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $cluster_id;
    $data_in{$object_hw_type}{$vm_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$vm_uuid}{label} )   { $data_out{$vm_uuid}{label}   = $data_in{$object_hw_type}{$vm_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$vm_uuid}{parents} ) { $data_out{$vm_uuid}{parents} = $data_in{$object_hw_type}{$vm_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{vm}{$vm_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$vm_uuid}{$spec_key} ) { $data_out{$vm_uuid}{$spec_key} = $data_in{$object_hw_type}{$vm_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "VM", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #lxc
  my @lxcs = @{ ProxmoxDataWrapper::get_items( { item_type => 'lxc', parent_type => 'cluster', parent_id => $cluster_id } ) };
  foreach my $lxc (@lxcs) {
    my ( $lxc_uuid, $lxc_label ) = each %{$lxc};

    if ( exists $label_json->{label}{lxc}{$lxc_uuid} ) { $data_in{$object_hw_type}{$lxc_uuid}{label} = $label_json->{label}{lxc}{$lxc_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{lxc}{$lxc_uuid} } ) {
      if ( !defined $conf_json->{specification}{lxc}{$lxc_uuid}{$spec_key} || ref( $conf_json->{specification}{lxc}{$lxc_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{lxc}{$lxc_uuid}{$spec_key} ) eq "ARRAY" ) {
        next;
      }
      else {
        $data_in{$object_hw_type}{$lxc_uuid}{$spec_key} = $conf_json->{specification}{lxc}{$lxc_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $cluster_id;
    $data_in{$object_hw_type}{$lxc_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$lxc_uuid}{label} )   { $data_out{$lxc_uuid}{label}   = $data_in{$object_hw_type}{$lxc_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$lxc_uuid}{parents} ) { $data_out{$lxc_uuid}{parents} = $data_in{$object_hw_type}{$lxc_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{lxc}{$lxc_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$lxc_uuid}{$spec_key} ) { $data_out{$lxc_uuid}{$spec_key} = $data_in{$object_hw_type}{$lxc_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "LXC", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #storage
  my @storages = @{ ProxmoxDataWrapper::get_items( { item_type => 'storage', parent_type => 'cluster', parent_id => $cluster_id } ) };
  foreach my $storage (@storages) {
    my ( $storage_uuid, $storage_label ) = each %{$storage};

    if ( exists $label_json->{label}{storage}{$storage_uuid} ) { $data_in{$object_hw_type}{$storage_uuid}{label} = $label_json->{label}{storage}{$storage_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{storage}{$storage_uuid} } ) {
      if ( !defined $conf_json->{specification}{storage}{$storage_uuid}{$spec_key} || ref( $conf_json->{specification}{storage}{$storage_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{storage}{$storage_uuid}{$spec_key} ) eq "ARRAY" ) {
        next;
      }
      else {
        $data_in{$object_hw_type}{$storage_uuid}{$spec_key} = $conf_json->{specification}{storage}{$storage_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $cluster_id;
    $data_in{$object_hw_type}{$storage_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$storage_uuid}{label} )   { $data_out{$storage_uuid}{label}   = $data_in{$object_hw_type}{$storage_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$storage_uuid}{parents} ) { $data_out{$storage_uuid}{parents} = $data_in{$object_hw_type}{$storage_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{storage}{$storage_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$storage_uuid}{$spec_key} ) { $data_out{$storage_uuid}{$spec_key} = $data_in{$object_hw_type}{$storage_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "STORAGE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

}

