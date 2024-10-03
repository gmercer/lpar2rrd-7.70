# aws-json2db.pl
# store AWS metadata in SQLite database

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use AWSDataWrapper;
use Xorux_lib;
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

if ( keys %{ HostCfg::getHostConnections('AWS') } == 0 ) {
  SQLiteDataWrapper::deleteItems({ hw_type => 'AWS'});
  exit(0);
}

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source: conf.json

my $conf_json = AWSDataWrapper::get_conf();

################################################################################

my $object_hw_type = "AWS";
my $object_label   = "Amazon Web Services";
my $object_id      = "AWS";

my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
SQLiteDataWrapper::object2db($params);

#regions
my @regions = @{ AWSDataWrapper::get_items( { item_type => 'region' } ) };

foreach my $hostcfg_uuid ( keys %{ $conf_json->{specification}->{hostcfg_uuid} } ) {

  #delete old data
  SQLiteDataWrapper::deleteItemFromConfig( { uuid => $hostcfg_uuid } );
}

foreach my $region (@regions) {
  my ( $region_id, $region_label ) = each %{$region};

  $data_in{$object_hw_type}{$region_id}{label} = $region_label;

  undef %data_out;
  if ( exists $data_in{$object_hw_type}{$region_id}{label} ) { $data_out{$region_id}{label} = $data_in{$object_hw_type}{$region_id}{label}; }

  my $params = { id => $object_id, subsys => "REGION", data => \%data_out };
  SQLiteDataWrapper::subsys2db($params);

  #ec2
  my @ec2s = @{ AWSDataWrapper::get_items( { item_type => 'ec2', parent_type => 'region', parent_id => $region_id } ) };
  foreach my $ec2 (@ec2s) {
    my ( $ec2_uuid, $ec2_label ) = each %{$ec2};

    if ( exists $conf_json->{label}{ec2}{$ec2_uuid} ) { $data_in{$object_hw_type}{$ec2_uuid}{label} = $conf_json->{label}{ec2}{$ec2_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{ec2}{$ec2_uuid} } ) {
      if ( !defined $conf_json->{specification}{ec2}{$ec2_uuid}{$spec_key} ) {
        $data_in{$object_hw_type}{$ec2_uuid}{$spec_key} = " ";
      }
      else {
        $data_in{$object_hw_type}{$ec2_uuid}{$spec_key} = $conf_json->{specification}{ec2}{$ec2_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $region_id;
    $data_in{$object_hw_type}{$ec2_uuid}{parents} = \@parents;

    undef %data_out;

    my @hostcfg;
    push( @hostcfg, $conf_json->{specification}{ec2}{$ec2_uuid}{hostcfg_uuid} );
    $data_out{$ec2_uuid}{hostcfg} = \@hostcfg;

    if ( exists $data_in{$object_hw_type}{$ec2_uuid}{label} )   { $data_out{$ec2_uuid}{label}   = $data_in{$object_hw_type}{$ec2_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$ec2_uuid}{parents} ) { $data_out{$ec2_uuid}{parents} = $data_in{$object_hw_type}{$ec2_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{ec2}{$ec2_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$ec2_uuid}{$spec_key} ) { $data_out{$ec2_uuid}{$spec_key} = $data_in{$object_hw_type}{$ec2_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "EC2", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #ebs
  my @ebs = @{ AWSDataWrapper::get_items( { item_type => 'volume', parent_type => 'region', parent_id => $region_id } ) };
  foreach my $volume (@ebs) {
    my ( $volume_uuid, $volume_label ) = each %{$volume};

    if ( exists $conf_json->{label}{volume}{$volume_uuid} ) { $data_in{$object_hw_type}{$volume_uuid}{label} = $conf_json->{label}{volume}{$volume_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{volume}{$volume_uuid} } ) {
      $data_in{$object_hw_type}{$volume_uuid}{$spec_key} = $conf_json->{specification}{volume}{$volume_uuid}{$spec_key};
    }

    #parent pool
    my @parents;
    push @parents, $region_id;
    $data_in{$object_hw_type}{$volume_uuid}{parents} = \@parents;

    undef %data_out;

    my @hostcfg;
    push( @hostcfg, $conf_json->{specification}{volume}{$volume_uuid}{hostcfg_uuid} );
    $data_out{$volume_uuid}{hostcfg} = \@hostcfg;

    if ( exists $data_in{$object_hw_type}{$volume_uuid}{label} )   { $data_out{$volume_uuid}{label}   = $data_in{$object_hw_type}{$volume_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$volume_uuid}{parents} ) { $data_out{$volume_uuid}{parents} = $data_in{$object_hw_type}{$volume_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{volume}{$volume_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$volume_uuid}{$spec_key} ) { $data_out{$volume_uuid}{$spec_key} = $data_in{$object_hw_type}{$volume_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "EBS", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #api
  my @api = @{ AWSDataWrapper::get_items( { item_type => 'api', parent_type => 'region', parent_id => $region_id } ) };
  foreach my $ap (@api) {
    my ( $api_uuid, $api_label ) = each %{$ap};

    if ( exists $conf_json->{label}{api}{$api_uuid} ) { $data_in{$object_hw_type}{$api_uuid}{label} = $conf_json->{label}{api}{$api_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{api}{$api_uuid} } ) {
      if ( !defined $conf_json->{specification}{api}{$api_uuid}{$spec_key} ) {
        $data_in{$object_hw_type}{$api_uuid}{$spec_key} = " ";
      }
      else {
        $data_in{$object_hw_type}{$api_uuid}{$spec_key} = $conf_json->{specification}{api}{$api_uuid}{$spec_key};
      }
    }

    #parent pool
    my @parents;
    push @parents, $region_id;
    $data_in{$object_hw_type}{$api_uuid}{parents} = \@parents;

    undef %data_out;

    my @hostcfg;
    push( @hostcfg, $conf_json->{specification}{api}{$api_uuid}{hostcfg_uuid} );
    $data_out{$api_uuid}{hostcfg} = \@hostcfg;

    if ( exists $data_in{$object_hw_type}{$api_uuid}{label} )   { $data_out{$api_uuid}{label}   = $data_in{$object_hw_type}{$api_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$api_uuid}{parents} ) { $data_out{$api_uuid}{parents} = $data_in{$object_hw_type}{$api_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{api}{$api_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$api_uuid}{$spec_key} ) { $data_out{$api_uuid}{$spec_key} = $data_in{$object_hw_type}{$api_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "API", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

  #lambda
  my @lambda = @{ AWSDataWrapper::get_items( { item_type => 'lambda', parent_type => 'region', parent_id => $region_id } ) };
  foreach my $la (@lambda) {
    my ( $lambda_uuid, $lambda_label ) = each %{$la};

    if ( exists $conf_json->{label}{lambda}{$lambda_uuid} ) { $data_in{$object_hw_type}{$lambda_uuid}{label} = $conf_json->{label}{lambda}{$lambda_uuid}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{lambda}{$lambda_uuid} } ) {
      $data_in{$object_hw_type}{$lambda_uuid}{$spec_key} = $conf_json->{specification}{lambda}{$lambda_uuid}{$spec_key};
    }

    #parent pool
    my @parents;
    push @parents, $region_id;
    $data_in{$object_hw_type}{$lambda_uuid}{parents} = \@parents;

    undef %data_out;

    my @hostcfg;
    push( @hostcfg, $conf_json->{specification}{lambda}{$lambda_uuid}{hostcfg_uuid} );
    $data_out{$lambda_uuid}{hostcfg} = \@hostcfg;

    if ( exists $data_in{$object_hw_type}{$lambda_uuid}{label} )   { $data_out{$lambda_uuid}{label}   = $data_in{$object_hw_type}{$lambda_uuid}{label}; }
    if ( exists $data_in{$object_hw_type}{$lambda_uuid}{parents} ) { $data_out{$lambda_uuid}{parents} = $data_in{$object_hw_type}{$lambda_uuid}{parents}; }

    foreach my $spec_key ( keys %{ $conf_json->{specification}{lambda}{$lambda_uuid} } ) {
      if ( exists $data_in{$object_hw_type}{$lambda_uuid}{$spec_key} ) { $data_out{$lambda_uuid}{$spec_key} = $data_in{$object_hw_type}{$lambda_uuid}{$spec_key}; }
    }

    my $params = { id => $object_id, subsys => "LAMBDA", data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

  }

}
