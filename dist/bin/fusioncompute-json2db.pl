# fusioncompute-json2db.pl
# store FusionCompute metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use FusionComputeDataWrapper;
use Xorux_lib;
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('FusionCompute') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'FUSIONCOMPUTE'});
  exit(0);
}

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

my $conf_json  = FusionComputeDataWrapper::get_spec();
my $label_json = FusionComputeDataWrapper::get_labels();

################################################################################

my $object_hw_type = "FUSIONCOMPUTE";
my $object_label   = "FusionCompute";
my $object_id      = "FUSIONCOMPUTE";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

my @sites = @{ FusionComputeDataWrapper::get_items( { item_type => 'site' } ) };
foreach my $site (@sites) {
  my ( $site_uuid, $site_label ) = each %{$site};

  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $conf_json->{specification}{site}{$site_uuid}{hostcfg_uuid} } );

  $data_in{$object_hw_type}{$site_uuid}{label} = $site_label;

  undef %data_out;
  if ( exists $data_in{$object_hw_type}{$site_uuid}{label} ) { $data_out{$site_uuid}{label} = $data_in{$object_hw_type}{$site_uuid}{label}; }

  my @hostcfg;
  push( @hostcfg, $conf_json->{specification}{site}{$site_uuid}{hostcfg_uuid} );
  $data_out{$site_uuid}{hostcfg} = \@hostcfg;

  my $params = { id => $object_id, subsys => "SITE", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  # clusters folder
  my @parents;
  push @parents, $site_uuid;
  my $fake_clusters_uuid = "$site_uuid-clusters";
  undef %data_out;
  $data_out{$fake_clusters_uuid}{label}   = "Clusters";
  $data_out{$fake_clusters_uuid}{parents} = \@parents;
  $params                                 = { id => $object_id, subsys => "CLUSTERS", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  # cluster under site
  my @clusters = @{ FusionComputeDataWrapper::get_items( { item_type => 'cluster', parent_type => 'site', parent_uuid => $site_uuid } ) };
  foreach my $cluster (@clusters) {
    my ( $cluster_uuid, $cluster_label ) = each %{$cluster};
    $data_in{$object_hw_type}{$cluster_uuid}{label} = $cluster_label;

    undef %data_out;
    if ( exists $data_in{$object_hw_type}{$cluster_uuid}{label} ) { $data_out{$cluster_uuid}{label} = $data_in{$object_hw_type}{$cluster_uuid}{label}; }

    my @parents;
    push @parents, $fake_clusters_uuid;
    $data_out{$cluster_uuid}{parents} = \@parents;

    my $params = { id => $object_id, subsys => "CLUSTER", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    # hosts under cluster
    my @hosts = @{ FusionComputeDataWrapper::get_items( { item_type => 'host', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
    foreach my $host (@hosts) {
      my ( $host_uuid, $host_label ) = each %{$host};

      $data_in{$object_hw_type}{$host_uuid}{label} = $host_label;

      undef %data_out;
      if ( exists $data_in{$object_hw_type}{$host_uuid}{label} ) { $data_out{$host_uuid}{label} = $data_in{$object_hw_type}{$host_uuid}{label}; }

      my @parents;
      push @parents, $cluster_uuid;
      $data_out{$host_uuid}{parents} = \@parents;

      my $params = { id => $object_id, subsys => "HOST", data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);
    }

    # vms under cluster
    my @vms = @{ FusionComputeDataWrapper::get_items( { item_type => 'vm', parent_type => 'cluster', parent_uuid => $cluster_uuid } ) };
    foreach my $vm (@vms) {
      my ( $vm_uuid, $vm_label ) = each %{$vm};

      $data_in{$object_hw_type}{$vm_uuid}{label} = $vm_label;

      undef %data_out;
      if ( exists $data_in{$object_hw_type}{$vm_uuid}{label} ) { $data_out{$vm_uuid}{label} = $data_in{$object_hw_type}{$vm_uuid}{label}; }

      my @parents;
      push @parents, $cluster_uuid;
      $data_out{$vm_uuid}{parents} = \@parents;

      my $params = { id => $object_id, subsys => "VM", data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);
    }
  }

  # datastore under site
  my @datastores = @{ FusionComputeDataWrapper::get_items( { item_type => 'datastore', parent_type => 'site', parent_uuid => $site_uuid } ) };
  foreach my $datastore (@datastores) {
    my ( $datastore_uuid, $datastore_label ) = each %{$datastore};

    $data_in{$object_hw_type}{$datastore_uuid}{label} = $datastore_label;

    undef %data_out;
    if ( exists $data_in{$object_hw_type}{$datastore_uuid}{label} ) { $data_out{$datastore_uuid}{label} = $data_in{$object_hw_type}{$datastore_uuid}{label}; }

    my @parents;
    push @parents, $site_uuid;
    $data_out{$datastore_uuid}{parents} = \@parents;

    my $params = { id => $object_id, subsys => "DATASTORE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
  }

}

