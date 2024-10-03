# docker-json2db.pl
# store Docker metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use DockerDataWrapper;
use Xorux_lib;
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('Docker') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'DOCKER'});
  exit(0);
}

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

my $label_json = DockerDataWrapper::get_labels();

################################################################################

my $object_hw_type = "DOCKER";
my $object_label   = "Docker";
my $object_id      = "DOCKER";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

my @hosts = @{ DockerDataWrapper::get_items( { item_type => 'host' } ) };
foreach my $host (@hosts) {
  my ( $host_uuid, $host_label ) = each %{$host};

  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $host_uuid } );

  $data_in{$object_hw_type}{$host_uuid}{label} = $host_label;

  undef %data_out;
  if ( exists $data_in{$object_hw_type}{$host_uuid}{label} ) { $data_out{$host_uuid}{label} = $data_in{$object_hw_type}{$host_uuid}{label}; }

  my @hostcfg;
  push( @hostcfg, $host_uuid );
  $data_out{$host_uuid}{hostcfg} = \@hostcfg;

  my $params = { id => $object_id, subsys => "HOST", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  # containers under host
  my @containers = @{ DockerDataWrapper::get_items( { item_type => 'container', parent_type => 'host', parent_uuid => $host_uuid } ) };
  foreach my $container (@containers) {
    my ( $container_uuid, $container_label ) = each %{$container};
    $data_in{$object_hw_type}{$container_uuid}{label} = $container_label;

    undef %data_out;
    if ( exists $data_in{$object_hw_type}{$container_uuid}{label} ) { $data_out{$container_uuid}{label} = $data_in{$object_hw_type}{$container_uuid}{label}; }

    my @parents;
    push @parents, $host_uuid;
    $data_out{$container_uuid}{parents} = \@parents;

    my $params = { id => $object_id, subsys => "CONTAINER", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
  }

  # volumes under host
  my @volumes = @{ DockerDataWrapper::get_items( { item_type => 'volume', parent_type => 'host', parent_uuid => $host_uuid } ) };
  foreach my $volume (@volumes) {
    my ( $volume_uuid, $volume_label ) = each %{$volume};
    $data_in{$object_hw_type}{$volume_uuid}{label} = $volume_label;

    undef %data_out;
    if ( exists $data_in{$object_hw_type}{$volume_uuid}{label} ) { $data_out{$volume_uuid}{label} = $data_in{$object_hw_type}{$volume_uuid}{label}; }

    my @parents;
    push @parents, $host_uuid;
    $data_out{$volume_uuid}{parents} = \@parents;

    my $params = { id => $object_id, subsys => "VOLUME", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);
  }
}

