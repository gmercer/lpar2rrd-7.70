# cloudstack-json2db.pl
# store CloudStack metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use CloudstackDataWrapper;
use Xorux_lib;
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('Cloudstack') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'CLOUDSTACK'});
  exit(0);
}

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source: conf.json

my $conf_json  = CloudstackDataWrapper::get_conf();
my $label_json = CloudstackDataWrapper::get_conf_label();

################################################################################

my $object_hw_type = "CLOUDSTACK";
my $object_label   = "Cloudstack";
my $object_id      = "CLOUDSTACK";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

my @clouds = @{ CloudstackDataWrapper::get_items( { item_type => 'cloud' } ) };
foreach my $cloud (@clouds) {
  my ( $cloud_id, $cloud_label ) = each %{$cloud};

  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $cloud_id } );

  $data_in{$object_hw_type}{$cloud_id}{label} = $cloud_label;

  undef %data_out;
  if ( exists $data_in{$object_hw_type}{$cloud_id}{label} ) { $data_out{$cloud_id}{label} = $data_in{$object_hw_type}{$cloud_id}{label}; }

  my @hostcfg;
  push( @hostcfg, $cloud_id );
  $data_out{$cloud_id}{hostcfg} = \@hostcfg;

  my $params = { id => $object_id, subsys => "CLOUD", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  #hosts
  my @hosts = @{ CloudstackDataWrapper::get_items( { item_type => 'host', parent_type => 'cloud', parent_id => $cloud_id } ) };
  foreach my $host (@hosts) {
    my ( $host_uuid, $host_label ) = each %{$host};

    if ( exists $label_json->{label}{host}{$host_uuid} ) { $data_in{$object_hw_type}{$host_uuid}{label} = $label_json->{label}{host}{$host_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{host}{$host_uuid} } ) {
      if ( !defined $conf_json->{specification}{host}{$host_uuid}{$spec_key} || ref( $conf_json->{specification}{host}{$host_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{host}{$host_uuid}{$spec_key} ) eq "ARRAY" ) {
        next;
      }
      else {
        $data_in{$object_hw_type}{$host_uuid}{$spec_key} = $conf_json->{specification}{host}{$host_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $cloud_id;
    $data_in{$object_hw_type}{$host_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$host_uuid}{label} )   { $data_out{$host_uuid}{label}   = $data_in{$object_hw_type}{$host_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$host_uuid}{parents} ) { $data_out{$host_uuid}{parents} = $data_in{$object_hw_type}{$host_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{host}{$host_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$host_uuid}{$spec_key} ) { $data_out{$host_uuid}{$spec_key} = $data_in{$object_hw_type}{$host_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "HOST", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #instance
  my @instances = @{ CloudstackDataWrapper::get_items( { item_type => 'instance', parent_type => 'cloud', parent_id => $cloud_id } ) };
  foreach my $instance (@instances) {
    my ( $instance_uuid, $instance_label ) = each %{$instance};

    if ( exists $label_json->{label}{instance}{$instance_uuid} ) { $data_in{$object_hw_type}{$instance_uuid}{label} = $label_json->{label}{instance}{$instance_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{instance}{$instance_uuid} } ) {
      if ( !defined $conf_json->{specification}{instance}{$instance_uuid}{$spec_key} || ref( $conf_json->{specification}{instance}{$instance_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{instance}{$instance_uuid}{$spec_key} ) eq "ARRAY" ) {
        next;
      }
      else {
        $data_in{$object_hw_type}{$instance_uuid}{$spec_key} = $conf_json->{specification}{instance}{$instance_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $cloud_id;
    $data_in{$object_hw_type}{$instance_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$instance_uuid}{label} )   { $data_out{$instance_uuid}{label}   = $data_in{$object_hw_type}{$instance_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$instance_uuid}{parents} ) { $data_out{$instance_uuid}{parents} = $data_in{$object_hw_type}{$instance_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{instance}{$instance_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$instance_uuid}{$spec_key} ) { $data_out{$instance_uuid}{$spec_key} = $data_in{$object_hw_type}{$instance_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "INSTANCE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #volume
  my @volumes = @{ CloudstackDataWrapper::get_items( { item_type => 'volume', parent_type => 'cloud', parent_id => $cloud_id } ) };
  foreach my $volume (@volumes) {
    my ( $volume_uuid, $volume_label ) = each %{$volume};

    if ( exists $label_json->{label}{volume}{$volume_uuid} ) { $data_in{$object_hw_type}{$volume_uuid}{label} = $label_json->{label}{volume}{$volume_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{volume}{$volume_uuid} } ) {
      if ( !defined $conf_json->{specification}{volume}{$volume_uuid}{$spec_key} || ref( $conf_json->{specification}{volume}{$volume_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{volume}{$volume_uuid}{$spec_key} ) eq "ARRAY" ) {
        next;
      }
      else {
        $data_in{$object_hw_type}{$volume_uuid}{$spec_key} = $conf_json->{specification}{volume}{$volume_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $cloud_id;
    $data_in{$object_hw_type}{$volume_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$volume_uuid}{label} )   { $data_out{$volume_uuid}{label}   = $data_in{$object_hw_type}{$volume_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$volume_uuid}{parents} ) { $data_out{$volume_uuid}{parents} = $data_in{$object_hw_type}{$volume_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{volume}{$volume_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$volume_uuid}{$spec_key} ) { $data_out{$volume_uuid}{$spec_key} = $data_in{$object_hw_type}{$volume_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "VOLUME", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #primary storage
  my @primaryStorages = @{ CloudstackDataWrapper::get_items( { item_type => 'primaryStorage', parent_type => 'cloud', parent_id => $cloud_id } ) };
  foreach my $primaryStorage (@primaryStorages) {
    my ( $primaryStorage_uuid, $primaryStorage_label ) = each %{$primaryStorage};

    if ( exists $label_json->{label}{primaryStorage}{$primaryStorage_uuid} ) { $data_in{$object_hw_type}{$primaryStorage_uuid}{label} = $label_json->{label}{primaryStorage}{$primaryStorage_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{primaryStorage}{$primaryStorage_uuid} } ) {
      if ( !defined $conf_json->{specification}{primaryStorage}{$primaryStorage_uuid}{$spec_key} || ref( $conf_json->{specification}{primaryStorage}{$primaryStorage_uuid}{$spec_key} ) eq "HASH" || ref( $conf_json->{specification}{primaryStorage}{$primaryStorage_uuid}{$spec_key} ) eq "ARRAY" ) {
        next;
      }
      else {
        $data_in{$object_hw_type}{$primaryStorage_uuid}{$spec_key} = $conf_json->{specification}{primaryStorage}{$primaryStorage_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $cloud_id;
    $data_in{$object_hw_type}{$primaryStorage_uuid}{parents} = \@parents;

    undef %data_out;

    if ( exists $data_in{$object_hw_type}{$primaryStorage_uuid}{label} )   { $data_out{$primaryStorage_uuid}{label}   = $data_in{$object_hw_type}{$primaryStorage_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$primaryStorage_uuid}{parents} ) { $data_out{$primaryStorage_uuid}{parents} = $data_in{$object_hw_type}{$primaryStorage_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{primaryStorage}{$primaryStorage_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$primaryStorage_uuid}{$spec_key} ) { $data_out{$primaryStorage_uuid}{$spec_key} = $data_in{$object_hw_type}{$primaryStorage_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "PRIMARY_STORAGE", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

}

