# gcloud-json2db.pl
# store GCloud metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use GCloudDataWrapper;
use Xorux_lib;
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('GCloud') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'GCLOUD'});
  exit(0);
}

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source: conf.json

my $conf_json = GCloudDataWrapper::get_conf();

################################################################################

my $object_hw_type = "GCLOUD";
my $object_label   = "Google Cloud";
my $object_id      = "GCLOUD";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

foreach my $hostcfg_uuid ( keys %{ $conf_json->{specification}->{hostcfg_uuid} } ) {

  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $hostcfg_uuid } );
}

#region
my @regions = @{ GCloudDataWrapper::get_items( { item_type => 'region' } ) };
foreach my $region (@regions) {
  my ( $region_id, $region_label ) = each %{$region};

  $data_in{$object_hw_type}{$region_id}{label} = $region_label;

  undef %data_out;
  if ( exists $data_in{$object_hw_type}{$region_id}{label} ) { $data_out{$region_id}{label} = $data_in{$object_hw_type}{$region_id}{label}; }

  my $params = { id => $object_id, subsys => "REGION", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  #compute engine
  my @computes = @{ GCloudDataWrapper::get_items( { item_type => 'compute', parent_type => 'region', parent_id => $region_id } ) };
  foreach my $compute (@computes) {
    my ( $compute_uuid, $compute_label ) = each %{$compute};

    if ( exists $conf_json->{label}{compute}{$compute_uuid} ) { $data_in{$object_hw_type}{$compute_uuid}{label} = $conf_json->{label}{compute}{$compute_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{compute}{$compute_uuid} } ) {
      if ( !defined $conf_json->{specification}{compute}{$compute_uuid}{$spec_key} ) {
        $data_in{$object_hw_type}{$compute_uuid}{$spec_key} = " ";
      }
      else {
        $data_in{$object_hw_type}{$compute_uuid}{$spec_key} = $conf_json->{specification}{compute}{$compute_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $region_id;
    $data_in{$object_hw_type}{$compute_uuid}{parents} = \@parents;

    undef %data_out;

    my @hostcfg;
    push( @hostcfg, $conf_json->{specification}{compute}{$compute_uuid}{hostcfg_uuid} );
    $data_out{$compute_uuid}{hostcfg} = \@hostcfg;

    if ( exists $data_in{$object_hw_type}{$compute_uuid}{label} )   { $data_out{$compute_uuid}{label}   = $data_in{$object_hw_type}{$compute_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$compute_uuid}{parents} ) { $data_out{$compute_uuid}{parents} = $data_in{$object_hw_type}{$compute_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{compute}{$compute_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$compute_uuid}{$spec_key} ) { $data_out{$compute_uuid}{$spec_key} = $data_in{$object_hw_type}{$compute_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "COMPUTE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

}
