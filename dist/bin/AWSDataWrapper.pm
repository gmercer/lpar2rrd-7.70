# AWSDataWrapper.pm
# interface for accessing AWS data:
#   provides lists of objects (ec2,…), respective filepaths and metadata, such as labels
#   metadata can be stored in a JSON file or in an SQLite database
#     thus backends AWSDataWrapperJSON and AWSDataWrapperSQLite

package AWSDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};
require AWSDataWrapperJSON;

#use AWSDataWrapperSQLite;

# XorMon-only (ACL, TODO add NutanixDataWrapperSQLite as metadata source)
my $acl;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'AWS', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/AWS";

my $ec2_path    = "$wrkdir/EC2";
my $volume_path = "$wrkdir/EBS";
my $rds_path    = "$wrkdir/RDS";
my $api_path    = "$wrkdir/API";
my $lambda_path = "$wrkdir/Lambda";
my $s3_path     = "$wrkdir/S3";
my $conf_file   = "$wrkdir/conf.json";
my $region_path = "$wrkdir/Region";

################################################################################

# TODO define types of objects "use constant …"

use constant TYPES => qw( ec2 );

################################################################################

sub get_filepath_rrd {
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'ec2' ) {
    $filepath = "${ec2_path}/$uuid.rrd";
  }
  elsif ( $type eq 'region' ) {
    $filepath = "${region_path}/$uuid.rrd";
  }
  elsif ( $type eq 'volume' || $type eq 'ebs' ) {
    $filepath = "${volume_path}/$uuid.rrd";
  }
  elsif ( $type eq 'api' ) {
    $filepath = "${api_path}/$uuid.rrd";
  }
  elsif ( $type eq 'lambda' ) {
    $filepath = "${lambda_path}/$uuid.rrd";
  }
  elsif ( $type eq 's3' ) {
    $filepath = "${s3_path}/$uuid.rrd";
  }
  elsif ( $type eq 'rds' ) {
    $filepath = "${rds_path}/$uuid.rrd";
  }
  else {
    return;
  }

  # ACL check
  if ( $use_sql && !$skip_acl ) {
    if ( !isGranted($uuid) ) {
      return;
    }
  }

  if ( defined $filepath ) {
    return $filepath;
  }
  else {
    return;
  }
}

sub get_items {
  my %params = %{ shift() };
  my $result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  $result = AWSDataWrapperJSON::get_items( \%params );

  return $result;
}

sub get_conf {
  my $result = AWSDataWrapperJSON::get_conf(@_);
  return $result;
}

sub get_conf_section {
  my $result = AWSDataWrapperJSON::get_conf_section(@_);
  return $result;
}

sub get_labels {
  return get_conf_section('labels');
}

sub get_label {
  my ( $result, $self, $type, $uuid );

  #OOP
  if ( scalar(@_) == 3 ) {
    ( $self, $type, $uuid ) = @_;
  }

  if ( exists $self->{labels} ) {
    $result = $self->{labels}->{labels}->{$type}->{$uuid};
  }
  else {
    $result = AWSDataWrapperJSON::get_label(@_);
  }
  return $result;
}

sub get_conf_update_time {
  my $result = AWSDataWrapperJSON::get_conf_update_time(@_);
  return $result;
}

################################################################################

1;
