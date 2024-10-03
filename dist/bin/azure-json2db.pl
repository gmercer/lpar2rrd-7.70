# azure-json2db.pl
# store Azure metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use AzureDataWrapper;
use Xorux_lib;
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('Azure') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'AZURE'});
  exit(0);
}

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source: conf.json

my $conf_json = AzureDataWrapper::get_conf();

################################################################################

my $object_hw_type = "AZURE";
my $object_label   = "Microsoft Azure";
my $object_id      = "AZURE";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

foreach my $hostcfg_uuid ( keys %{ $conf_json->{specification}->{hostcfg_uuid} } ) {

  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $hostcfg_uuid } );
}

#location
my @locations = @{ AzureDataWrapper::get_items( { item_type => 'location' } ) };
foreach my $location (@locations) {
  my ( $location_id, $location_label ) = each %{$location};

  $data_in{$object_hw_type}{$location_id}{label} = $location_label;

  undef %data_out;
  if ( exists $data_in{$object_hw_type}{$location_id}{label} ) { $data_out{$location_id}{label} = $data_in{$object_hw_type}{$location_id}{label}; }

  my $params = { id => $object_id, subsys => "LOCATION", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  #vm
  my @vms = @{ AzureDataWrapper::get_items( { item_type => 'vm', parent_type => 'location', parent_id => $location_id } ) };
  foreach my $vm (@vms) {
    my ( $vm_uuid, $vm_label ) = each %{$vm};

    if ( exists $conf_json->{label}{vm}{$vm_uuid} ) { $data_in{$object_hw_type}{$vm_uuid}{label} = $conf_json->{label}{vm}{$vm_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{vm}{$vm_uuid} } ) {
      if ( $spec_key eq "osDisk" )  { next; }
      if ( $spec_key eq "network" ) { next; }
      if ( !defined $conf_json->{specification}{vm}{$vm_uuid}{$spec_key} ) {
        $data_in{$object_hw_type}{$vm_uuid}{$spec_key} = " ";
      }
      else {
        $data_in{$object_hw_type}{$vm_uuid}{$spec_key} = $conf_json->{specification}{vm}{$vm_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $location_id;
    $data_in{$object_hw_type}{$vm_uuid}{parents} = \@parents;

    undef %data_out;

    my @hostcfg;
    push( @hostcfg, $conf_json->{specification}{vm}{$vm_uuid}{hostcfg_uuid} );
    $data_out{$vm_uuid}{hostcfg} = \@hostcfg;

    if ( exists $data_in{$object_hw_type}{$vm_uuid}{label} )   { $data_out{$vm_uuid}{label}   = $data_in{$object_hw_type}{$vm_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$vm_uuid}{parents} ) { $data_out{$vm_uuid}{parents} = $data_in{$object_hw_type}{$vm_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{vm}{$vm_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$vm_uuid}{$spec_key} ) { $data_out{$vm_uuid}{$spec_key} = $data_in{$object_hw_type}{$vm_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "VM", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }
}
