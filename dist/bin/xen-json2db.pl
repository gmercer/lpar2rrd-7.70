# xen-json2db.pl
# store XenServer metadata (conf.json) in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use XenServerDataWrapperOOP;
use Xorux_lib;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

#my $db_filepath         = "$inputdir/data/data.db";
#my $iostats_dir         = "$inputdir/data/XEN_iostats";
#my $metadata_file       = "$iostats_dir/conf.json";
#my $tmpdir              = "$inputdir/tmp";

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source: conf.json

my $xenserver_metadata = XenServerDataWrapperOOP->new();
my $conf_json          = $xenserver_metadata->get_conf();

################################################################################

# fill tables

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
# $params = { id => $st_serial, subsys => 'DEVICE', data => $data_out{DEVICE} };
# SQLiteDataWrapper::subsys2db( $params );

# LPAR2RRD: XenServer assignment
# (TODO remove) object: hw_type => 'XENSERVER', label => 'XenServer', id => 'DEADBEEF'
# params: id                    => 'DEADBEEF', subsys => "(HOST|VM|STORAGE|…)", data => $data_out{(HOST|VM|STORAGE|…)}

my $object_hw_type = 'XENSERVER';
my $object_label   = 'XenServer';
my $object_id      = 'XENSERVER';

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

# VMs

# get only VMs with an existing RRD, not all VMs reported by XAPI
my @vms = @{ $xenserver_metadata->get_items( { item_type => 'vm' } ) };
foreach my $vm_item (@vms) {
  my %item = %{$vm_item};
  my ( $vm, $vm_label ) = each %item;
  if ( exists $conf_json->{labels}{vm}{$vm} )                         { $data_in{XENSERVER}{$vm}{label}            = $conf_json->{labels}{vm}{$vm}; }
  if ( exists $conf_json->{specification}{vm}{$vm}{memory} )          { $data_in{XENSERVER}{$vm}{memory}           = $conf_json->{specification}{vm}{$vm}{memory}; }
  if ( exists $conf_json->{specification}{vm}{$vm}{cpu_count} )       { $data_in{XENSERVER}{$vm}{vcpu}             = $conf_json->{specification}{vm}{$vm}{cpu_count}; }
  if ( exists $conf_json->{specification}{vm}{$vm}{cpu_count_start} ) { $data_in{XENSERVER}{$vm}{vcpu_startup}     = $conf_json->{specification}{vm}{$vm}{cpu_count_start}; }
  if ( exists $conf_json->{specification}{vm}{$vm}{cpu_count_max} )   { $data_in{XENSERVER}{$vm}{vcpu_max}         = $conf_json->{specification}{vm}{$vm}{cpu_count_max}; }
  if ( exists $conf_json->{specification}{vm}{$vm}{os} )              { $data_in{XENSERVER}{$vm}{operating_system} = $conf_json->{specification}{vm}{$vm}{os}; }

  my @parents;
  if ( exists $conf_json->{specification}{vm}{$vm}{parent_host} ) {
    my $parent_host = $conf_json->{specification}{vm}{$vm}{parent_host};
    if ($parent_host) { push @parents, $parent_host; }
  }
  if ( exists $conf_json->{specification}{vm}{$vm}{parent_pool} ) {
    my $parent_pool = $conf_json->{specification}{vm}{$vm}{parent_pool};
    if ($parent_pool) { push @parents, $parent_pool; }
  }
  if ( scalar @parents ) { $data_in{XENSERVER}{$vm}{parents} = \@parents; }

  undef %data_out;
  if ( exists $data_in{XENSERVER}{$vm}{label} )            { $data_out{$vm}{label}            = $data_in{XENSERVER}{$vm}{label}; }
  if ( exists $data_in{XENSERVER}{$vm}{memory} )           { $data_out{$vm}{memory}           = $data_in{XENSERVER}{$vm}{memory}; }
  if ( exists $data_in{XENSERVER}{$vm}{vcpu} )             { $data_out{$vm}{vcpu}             = $data_in{XENSERVER}{$vm}{vcpu}; }
  if ( exists $data_in{XENSERVER}{$vm}{vcpu_startup} )     { $data_out{$vm}{vcpu_startup}     = $data_in{XENSERVER}{$vm}{vcpu_startup}; }
  if ( exists $data_in{XENSERVER}{$vm}{vcpu_max} )         { $data_out{$vm}{vcpu_max}         = $data_in{XENSERVER}{$vm}{vcpu_max}; }
  if ( exists $data_in{XENSERVER}{$vm}{operating_system} ) { $data_out{$vm}{operating_system} = $data_in{XENSERVER}{$vm}{operating_system}; }
  if ( exists $data_in{XENSERVER}{$vm}{parents} )          { $data_out{$vm}{parents}          = $data_in{XENSERVER}{$vm}{parents}; }

  my $params = { id => $object_id, subsys => 'VM', data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);
}

# hosts

# get only hosts with an existing RRD, not all hosts reported by XAPI
my @hosts = @{ $xenserver_metadata->get_items( { item_type => 'host' } ) };
foreach my $host_item (@hosts) {
  my %item = %{$host_item};
  my ( $host, $host_label ) = each %item;
  if ( exists $conf_json->{labels}{host}{$host} )                      { $data_in{XENSERVER}{$host}{label}        = $conf_json->{labels}{host}{$host}; }
  if ( exists $conf_json->{specification}{host}{$host}{address} )      { $data_in{XENSERVER}{$host}{address}      = $conf_json->{specification}{host}{$host}{address}; }
  if ( exists $conf_json->{specification}{host}{$host}{memory} )       { $data_in{XENSERVER}{$host}{memory}       = $conf_json->{specification}{host}{$host}{memory}; }
  if ( exists $conf_json->{specification}{host}{$host}{cpu_count} )    { $data_in{XENSERVER}{$host}{cpu_count}    = $conf_json->{specification}{host}{$host}{cpu_count}; }
  if ( exists $conf_json->{specification}{host}{$host}{socket_count} ) { $data_in{XENSERVER}{$host}{socket_count} = $conf_json->{specification}{host}{$host}{socket_count}; }
  if ( exists $conf_json->{specification}{host}{$host}{cpu_model} )    { $data_in{XENSERVER}{$host}{cpu_model}    = $conf_json->{specification}{host}{$host}{cpu_model}; }
  if ( exists $conf_json->{specification}{host}{$host}{version_xen} )  { $data_in{XENSERVER}{$host}{version_xen}  = $conf_json->{specification}{host}{$host}{version_xen}; }

  my @parents;
  if ( exists $conf_json->{specification}{host}{$host}{parent_pool} ) {
    my $parent_pool = $conf_json->{specification}{host}{$host}{parent_pool};
    if ($parent_pool) { push @parents, $parent_pool; }
  }
  if ( scalar @parents ) { $data_in{XENSERVER}{$host}{parents} = \@parents; }

  undef %data_out;
  if ( exists $data_in{XENSERVER}{$host}{label} )        { $data_out{$host}{label}        = $data_in{XENSERVER}{$host}{label}; }
  if ( exists $data_in{XENSERVER}{$host}{address} )      { $data_out{$host}{address}      = $data_in{XENSERVER}{$host}{address}; }
  if ( exists $data_in{XENSERVER}{$host}{memory} )       { $data_out{$host}{memory}       = $data_in{XENSERVER}{$host}{memory}; }
  if ( exists $data_in{XENSERVER}{$host}{cpu_count} )    { $data_out{$host}{cpu_count}    = $data_in{XENSERVER}{$host}{cpu_count}; }
  if ( exists $data_in{XENSERVER}{$host}{socket_count} ) { $data_out{$host}{socket_count} = $data_in{XENSERVER}{$host}{socket_count}; }
  if ( exists $data_in{XENSERVER}{$host}{cpu_model} )    { $data_out{$host}{cpu_model}    = $data_in{XENSERVER}{$host}{cpu_model}; }
  if ( exists $data_in{XENSERVER}{$host}{version_xen} )  { $data_out{$host}{version_xen}  = $data_in{XENSERVER}{$host}{version_xen}; }
  if ( exists $data_in{XENSERVER}{$host}{parents} )      { $data_out{$host}{parents}      = $data_in{XENSERVER}{$host}{parents}; }

  my $params = { id => $object_id, subsys => 'HOST', data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);
}

# pools

foreach my $pool ( keys %{ $conf_json->{architecture}{pool} } ) {
  if ( exists $conf_json->{labels}{pool}{$pool} ) {
    $data_in{XENSERVER}{$pool}{label} = $conf_json->{labels}{pool}{$pool};
  }
  else {
    $data_in{XENSERVER}{$pool}{label} = 'unlabeled pool ' . substr( $pool, 0, 8 );
  }

  undef %data_out;
  if ( exists $data_in{XENSERVER}{$pool}{label} ) { $data_out{$pool}{label} = $data_in{XENSERVER}{$pool}{label}; }

  my $params = { id => $object_id, subsys => 'POOL', data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);
}

# network interfaces

foreach my $pif ( keys %{ $conf_json->{specification}{pif} } ) {
  if ( exists $conf_json->{specification}{pif}{$pif}{device} ) { $data_in{XENSERVER}{$pif}{label} = $conf_json->{specification}{pif}{$pif}{device}; }

  my @parents;
  if ( exists $conf_json->{specification}{pif}{$pif}{parent_host} ) {
    my $parent_host = $conf_json->{specification}{pif}{$pif}{parent_host};
    if ($parent_host) { push @parents, $parent_host; }
  }
  if ( scalar @parents ) { $data_in{XENSERVER}{$pif}{parents} = \@parents; }

  undef %data_out;
  if ( exists $data_in{XENSERVER}{$pif}{label} )   { $data_out{$pif}{label}   = $data_in{XENSERVER}{$pif}{label}; }
  if ( exists $data_in{XENSERVER}{$pif}{parents} ) { $data_out{$pif}{parents} = $data_in{XENSERVER}{$pif}{parents}; }

  my $params = { id => $object_id, subsys => 'LAN', data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);
}

# storages

foreach my $storage ( keys %{ $conf_json->{labels}{sr} } ) {

  # exclude storages without any RRD
  next unless ( $xenserver_metadata->get_filepath_rrd( { type => 'storage', uuid => $storage, skip_acl => 1 } ) );

  if ( exists $conf_json->{specification}{sr}{$storage}{label} )                { $data_in{XENSERVER}{$storage}{label}                = $conf_json->{specification}{sr}{$storage}{label}; }
  if ( exists $conf_json->{specification}{sr}{$storage}{type} )                 { $data_in{XENSERVER}{$storage}{type}                 = $conf_json->{specification}{sr}{$storage}{type}; }
  if ( exists $conf_json->{specification}{sr}{$storage}{virtual_allocation} )   { $data_in{XENSERVER}{$storage}{virtual_allocation}   = $conf_json->{specification}{sr}{$storage}{virtual_allocation}; }
  if ( exists $conf_json->{specification}{sr}{$storage}{physical_utilisation} ) { $data_in{XENSERVER}{$storage}{physical_utilisation} = $conf_json->{specification}{sr}{$storage}{physical_utilisation}; }
  if ( exists $conf_json->{specification}{sr}{$storage}{physical_size} )        { $data_in{XENSERVER}{$storage}{physical_size}        = $conf_json->{specification}{sr}{$storage}{physical_size}; }

  my @parents;
  if ( exists $conf_json->{architecture}{storage}{sr_host}{$storage} ) {
    my @parent_hosts = @{ $conf_json->{architecture}{storage}{sr_host}{$storage} };
    foreach my $parent_host (@parent_hosts) {

      # exclude relations where RRD does not exist
      my $filepath = $xenserver_metadata->get_filepath_rrd( { type => 'storage', uuid => $parent_host, id => $xenserver_metadata->shorten_sr_uuid($storage), skip_acl => 1 } );
      if ( $filepath && -f $filepath ) {
        push @parents, $parent_host;
      }
    }
  }
  if ( scalar @parents ) { $data_in{XENSERVER}{$storage}{parents} = \@parents; }

  my @children;
  if ( exists $conf_json->{architecture}{storage}{sr_vdi}{$storage} ) {
    my @child_vdis = @{ $conf_json->{architecture}{storage}{sr_vdi}{$storage} };
    if ( scalar @child_vdis ) { push @children, @child_vdis; }
  }
  if ( scalar @children ) { $data_in{XENSERVER}{$storage}{children} = \@children; }

  undef %data_out;
  if ( exists $data_in{XENSERVER}{$storage}{label} )                { $data_out{$storage}{label}                = $data_in{XENSERVER}{$storage}{label}; }
  if ( exists $data_in{XENSERVER}{$storage}{type} )                 { $data_out{$storage}{type}                 = $data_in{XENSERVER}{$storage}{type}; }
  if ( exists $data_in{XENSERVER}{$storage}{virtual_allocation} )   { $data_out{$storage}{virtual_allocation}   = $data_in{XENSERVER}{$storage}{virtual_allocation}; }
  if ( exists $data_in{XENSERVER}{$storage}{physical_utilisation} ) { $data_out{$storage}{physical_utilisation} = $data_in{XENSERVER}{$storage}{physical_utilisation}; }
  if ( exists $data_in{XENSERVER}{$storage}{physical_size} )        { $data_out{$storage}{physical_size}        = $data_in{XENSERVER}{$storage}{physical_size}; }
  if ( exists $data_in{XENSERVER}{$storage}{parents} )              { $data_out{$storage}{parents}              = $data_in{XENSERVER}{$storage}{parents}; }
  if ( exists $data_in{XENSERVER}{$storage}{children} )             { $data_out{$storage}{children}             = $data_in{XENSERVER}{$storage}{children}; }

  my $params = { id => $object_id, subsys => 'STORAGE', data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);
}

# storage VDIs (volumes)

foreach my $vdi ( keys %{ $conf_json->{specification}{vdi} } ) {
  if ( exists $conf_json->{specification}{vdi}{$vdi}{label} )                { $data_in{XENSERVER}{$vdi}{label}                = $conf_json->{specification}{vdi}{$vdi}{label}; }
  if ( exists $conf_json->{specification}{vdi}{$vdi}{physical_utilisation} ) { $data_in{XENSERVER}{$vdi}{physical_utilisation} = $conf_json->{specification}{vdi}{$vdi}{physical_utilisation}; }
  if ( exists $conf_json->{specification}{vdi}{$vdi}{virtual_size} )         { $data_in{XENSERVER}{$vdi}{virtual_size}         = $conf_json->{specification}{vdi}{$vdi}{virtual_size}; }

  my @children;
  if ( exists $conf_json->{architecture}{storage}{vdi_vm}{$vdi} ) {
    my @child_vms = @{ $conf_json->{architecture}{storage}{vdi_vm}{$vdi} };
    if ( scalar @child_vms ) { push @children, @child_vms; }
  }
  if ( scalar @children ) { $data_in{XENSERVER}{$vdi}{children} = \@children; }

  undef %data_out;
  if ( exists $data_in{XENSERVER}{$vdi}{label} )                { $data_out{$vdi}{label}                = $data_in{XENSERVER}{$vdi}{label}; }
  if ( exists $data_in{XENSERVER}{$vdi}{physical_utilisation} ) { $data_out{$vdi}{physical_utilisation} = $data_in{XENSERVER}{$vdi}{physical_utilisation}; }
  if ( exists $data_in{XENSERVER}{$vdi}{virtual_size} )         { $data_out{$vdi}{virtual_size}         = $data_in{XENSERVER}{$vdi}{virtual_size}; }
  if ( exists $data_in{XENSERVER}{$vdi}{children} )             { $data_out{$vdi}{children}             = $data_in{XENSERVER}{$vdi}{children}; }

  my $params = { id => $object_id, subsys => 'VOLUME', data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);
}

# finish
