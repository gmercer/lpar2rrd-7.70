# GCloudDataWrapper.pm
# interface for accessing GCloud data:
#   provides lists of objects (ec2,…), respective filepaths and metadata, such as labels
#   metadata can be stored in a JSON file or in an SQLite database
#     thus backends GCloudDataWrapperJSON and GcloudDataWrapperSQLite

package GCloudDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};
require GCloudDataWrapperJSON;

#use GCloudDataWrapperSQLite;

# XorMon-only (ACL, TODO add GCloudDataWrapperSQLite as metadata source)
my $acl;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'GCLOUD', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/GCloud";

my $compute_path  = "$wrkdir/compute";
my $database_path = "$wrkdir/database";
my $region_path   = "$wrkdir/region";
my $conf_file     = "$wrkdir/conf.json";

################################################################################

# TODO use get_filepath_rrd instead of these specific subs

sub get_filepath_rrd_compute {
  my $uuid     = shift;
  my $filepath = "$compute_path/" . $uuid . ".rrd";

  return if ( $use_sql && !isGranted($uuid) );
  return $filepath;
}

sub get_filepath_rrd_region {
  my $uuid     = shift;
  my $filepath = "$region_path/" . $uuid . ".rrd";

  return if ( $use_sql && !isGranted($uuid) );
  return $filepath;
}

sub get_filepath_rrd_database {
  my $uuid     = shift;
  my $filepath = "$database_path/" . $uuid . ".rrd";

  return if ( $use_sql && !isGranted($uuid) );
  return $filepath;
}

sub get_filepath_rrd {
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'compute' ) {
    $filepath = "${compute_path}/$uuid.rrd";
  }
  elsif ( $type eq 'database' ) {
    $filepath = "${database_path}/$uuid.rrd";
  }
  elsif ( $type eq 'region' ) {
    $filepath = "${region_path}/$uuid.rrd";
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

  $result = GCloudDataWrapperJSON::get_items( \%params );

  #if ($use_sql) {
  #  my @filtered_result;
  #  foreach my $item (@{$result}) {
  #    my %result_item = %{$item};
  #    my ($uuid, $label) = each %result_item;
  #    if ($acl->isGranted({hw_type => 'GCLOUD', item_id => $uuid})) {
  #      push @filtered_result, $item;
  #    }
  #  }
  #  $result = \@filtered_result;
  #}

  return $result;
}

sub get_conf {
  my $result = GCloudDataWrapperJSON::get_conf(@_);
  return $result;
}

sub get_conf_section {
  my $result = GCloudDataWrapperJSON::get_conf_section(@_);
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
    $result = GCloudDataWrapperJSON::get_label(@_);
  }
  return $result;
}

sub get_engine {
  my ($uuid) = @_;
  return GCloudDataWrapperJSON::get_engine(@_);
}

sub get_conf_update_time {
  my $result = GCloudDataWrapperJSON::get_conf_update_time(@_);
  return $result;
}

################################################################################

1;
