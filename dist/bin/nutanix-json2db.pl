# nutanix-json2db.pl
# store Nutanix metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use NutanixDataWrapper;
use Xorux_lib;
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('Nutanix') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'NUTANIX'});
  exit(0);
}

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source: conf.json

my $architecture_json = NutanixDataWrapper::get_architecture();
my $label_json        = NutanixDataWrapper::get_labels();
my $spec_json         = NutanixDataWrapper::get_spec();

################################################################################

my $object_hw_type = "NUTANIX";
my $object_label   = "Nutanix";
my $object_id      = "NUTANIX";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

# delete clusters first 
foreach my $cluster ( keys %{ $architecture_json->{architecture}{cluster} } ) {
  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $spec_json->{specification}{cluster}{$cluster}{hostcfg_uuid} } );
}

# add clusters to db
foreach my $cluster ( keys %{ $architecture_json->{architecture}{cluster} } ) {

  my $fake_storage_uuid = "$cluster-storage";

  if ( exists $label_json->{cluster}{$cluster} ) {
    $data_in{$object_hw_type}{$cluster}{label} = $label_json->{cluster}{$cluster};
  }
  else {
    $data_in{$object_hw_type}{$cluster}{label} = 'unlabeled cluster ' . substr( $cluster, 0, 8 );
  }

  undef %data_out;

  my @hostcfg;
  push( @hostcfg, $spec_json->{specification}{cluster}{$cluster}{hostcfg_uuid} );
  $data_out{$cluster}{hostcfg} = \@hostcfg;

  if ( exists $data_in{$object_hw_type}{$cluster}{label} ) { $data_out{$cluster}{label} = $data_in{$object_hw_type}{$cluster}{label}; }

  my $params = { id => $object_id, subsys => "POOL", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  # hosts
  my @hosts = @{ NutanixDataWrapper::get_items( { item_type => 'host', parent_type => 'cluster', parent_uuid => $cluster } ) };

  foreach my $host (@hosts) {
    my ( $host_uuid, $host_label ) = each %{$host};

    if ( exists $label_json->{host}{$host_uuid} ) { $data_in{$object_hw_type}{$host_uuid}{label} = $label_json->{host}{$host_uuid}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{host}{$host_uuid} } ) {
      $data_in{$object_hw_type}{$host_uuid}{$spec_key} = $spec_json->{specification}{host}{$host_uuid}{$spec_key};
    }

    #parent cluster
    my @parents;
    push @parents, $cluster;
    $data_in{$object_hw_type}{$host_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$host_uuid}{label} )   { $data_out{$host_uuid}{label}   = $data_in{$object_hw_type}{$host_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$host_uuid}{parents} ) { $data_out{$host_uuid}{parents} = $data_in{$object_hw_type}{$host_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{host}{$host_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$host_uuid}{$spec_key} ) { $data_out{$host_uuid}{$spec_key} = $data_in{$object_hw_type}{$host_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "HOST", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    #storage folder
    undef %data_out;
    $data_out{$fake_storage_uuid}{label}   = "Storage";
    $data_out{$fake_storage_uuid}{parents} = \@parents;
    $params                                = { id => $object_id, subsys => "STORAGE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  # vms
  my @vms = @{ NutanixDataWrapper::get_items( { item_type => 'vm', parent_type => 'cluster', parent_uuid => $cluster } ) };
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( exists $label_json->{vm}{$vm_uuid} ) { $data_in{$object_hw_type}{$vm_uuid}{label} = $label_json->{vm}{$vm_uuid}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{vm}{$vm_uuid} } ) {
      if ( !defined $spec_json->{specification}{vm}{$vm_uuid}{$spec_key} ) {
        $data_in{$object_hw_type}{$vm_uuid}{$spec_key} = 0;
      }
      else {
        $data_in{$object_hw_type}{$vm_uuid}{$spec_key} = $spec_json->{specification}{vm}{$vm_uuid}{$spec_key};
      }
    }

    #parent cluster
    my @parents;
    push @parents, $cluster;
    $data_in{$object_hw_type}{$vm_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$vm_uuid}{label} )   { $data_out{$vm_uuid}{label}   = $data_in{$object_hw_type}{$vm_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$vm_uuid}{parents} ) { $data_out{$vm_uuid}{parents} = $data_in{$object_hw_type}{$vm_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{vm}{$vm_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$vm_uuid}{$spec_key} ) { $data_out{$vm_uuid}{$spec_key} = $data_in{$object_hw_type}{$vm_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "VM", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #Storage Pool
  my @storage_pools = @{ NutanixDataWrapper::get_items( { item_type => 'pool', parent_type => 'cluster', parent_uuid => $cluster } ) };

  foreach my $sp (@storage_pools) {
    my ( $sp_uuid, $sp_label ) = each %{$sp};

    if ( exists $label_json->{pool}{$sp_uuid} ) { $data_in{$object_hw_type}{$sp_uuid}{label} = $label_json->{pool}{$sp_uuid}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{pool}{$sp_uuid} } ) {
      $data_in{$object_hw_type}{$sp_uuid}{$spec_key} = $spec_json->{specification}{pool}{$sp_uuid}{$spec_key};
    }

    #parent pool
    my @parents;
    push @parents, $fake_storage_uuid;
    $data_in{$object_hw_type}{$sp_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$sp_uuid}{label} )   { $data_out{$sp_uuid}{label}   = $data_in{$object_hw_type}{$sp_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$sp_uuid}{parents} ) { $data_out{$sp_uuid}{parents} = $data_in{$object_hw_type}{$sp_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{pool}{$sp_uuid} } ) {
      if ( $spec_key eq "disks" )                                  { next; }
      if ( exists $data_in{$object_hw_type}{$sp_uuid}{$spec_key} ) { $data_out{$sp_uuid}{$spec_key} = $data_in{$object_hw_type}{$sp_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "STORAGE_POOL", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #Storage Container
  my @storage_containers = @{ NutanixDataWrapper::get_items( { item_type => 'container', parent_type => 'cluster', parent_uuid => $cluster } ) };

  foreach my $sc (@storage_containers) {
    my ( $sc_uuid, $sc_label ) = each %{$sc};

    if ( exists $label_json->{container}{$sc_uuid} ) { $data_in{$object_hw_type}{$sc_uuid}{label} = $label_json->{container}{$sc_uuid}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{container}{$sc_uuid} } ) {
      if ( !defined $spec_json->{specification}{container}{$sc_uuid}{$spec_key} ) {
        $data_in{$object_hw_type}{$sc_uuid}{$spec_key} = 0;
      }
      else {
        $data_in{$object_hw_type}{$sc_uuid}{$spec_key} = $spec_json->{specification}{container}{$sc_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $fake_storage_uuid;
    $data_in{$object_hw_type}{$sc_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$sc_uuid}{label} )   { $data_out{$sc_uuid}{label}   = $data_in{$object_hw_type}{$sc_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$sc_uuid}{parents} ) { $data_out{$sc_uuid}{parents} = $data_in{$object_hw_type}{$sc_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{container}{$sc_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$sc_uuid}{$spec_key} ) { $data_out{$sc_uuid}{$spec_key} = $data_in{$object_hw_type}{$sc_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "STORAGE_CONTAINER", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #Virtual Disks
  my @virtual_disks = @{ NutanixDataWrapper::get_items( { item_type => 'vdisk', parent_type => 'cluster', parent_uuid => $cluster } ) };

  foreach my $vd (@virtual_disks) {
    my ( $vd_uuid, $vd_label ) = each %{$vd};

    if ( exists $label_json->{vdisk}{$vd_uuid} ) { $data_in{$object_hw_type}{$vd_uuid}{label} = $label_json->{vdisk}{$vd_uuid}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{vdisk}{$vd_uuid} } ) {
      if ( !defined $spec_json->{specification}{vdisk}{$vd_uuid}{$spec_key} ) {
        $data_in{$object_hw_type}{$vd_uuid}{$spec_key} = 0;
      }
      else {
        $data_in{$object_hw_type}{$vd_uuid}{$spec_key} = $spec_json->{specification}{vdisk}{$vd_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $fake_storage_uuid;
    $data_in{$object_hw_type}{$vd_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$vd_uuid}{label} )   { $data_out{$vd_uuid}{label}   = $data_in{$object_hw_type}{$vd_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$vd_uuid}{parents} ) { $data_out{$vd_uuid}{parents} = $data_in{$object_hw_type}{$vd_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{vdisk}{$vd_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$vd_uuid}{$spec_key} ) { $data_out{$vd_uuid}{$spec_key} = $data_in{$object_hw_type}{$vd_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "VIRTUAL_DISK", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #Physical Disks
  my @physical_disks = @{ NutanixDataWrapper::get_items( { item_type => 'disk', parent_type => 'cluster', parent_uuid => $cluster } ) };

  foreach my $sr (@physical_disks) {
    my ( $sr_uuid, $sr_label ) = each %{$sr};

    if ( exists $label_json->{disk}{$sr_uuid} ) { $data_in{$object_hw_type}{$sr_uuid}{label} = $label_json->{disk}{$sr_uuid}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{disk}{$sr_uuid} } ) {
      $data_in{$object_hw_type}{$sr_uuid}{$spec_key} = $spec_json->{specification}{disk}{$sr_uuid}{$spec_key};
    }

    #parent pool
    my @parents;
    push @parents, $fake_storage_uuid;
    $data_in{$object_hw_type}{$sr_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$sr_uuid}{label} )   { $data_out{$sr_uuid}{label}   = $data_in{$object_hw_type}{$sr_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$sr_uuid}{parents} ) { $data_out{$sr_uuid}{parents} = $data_in{$object_hw_type}{$sr_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $spec_json->{specification}{disk}{$sr_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$sr_uuid}{$spec_key} ) { $data_out{$sr_uuid}{$spec_key} = $data_in{$object_hw_type}{$sr_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "PHYSICAL_DISK", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

}

