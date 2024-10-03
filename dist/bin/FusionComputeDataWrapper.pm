# FusionComputeWrapper.pm
# interface for accessing FusionCompute data:

package FusionComputeDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};
require FusionComputeDataWrapperJSON;

#use FusionComputeDataWrapperSQLite;

# XorMon-only (ACL, TODO add FusionComputeDataWrapperSQLite as metadata source)
my $acl;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'FUSIONCOMPUTE', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $input_dir       = $ENV{INPUTDIR};
my $wrkdir          = "$input_dir/data/FusionCompute";
my $hosts_path      = "$wrkdir/Host";
my $clusters_path   = "$wrkdir/Cluster";
my $vms_path        = "$wrkdir/VM";
my $datastores_path = "$wrkdir/Datastore";

################################################################################

sub get_filepath_rrd {

  # params: { type => '(vm|host|storage|network)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'vm' ) {
    $filepath = "$vms_path/$uuid.rrd";
  }
  elsif ( $type eq 'host' ) {
    $filepath = "$hosts_path/$uuid.rrd";
  }
  elsif ( $type eq 'cluster' ) {
    $filepath = "$clusters_path/$uuid.rrd";
  }
  elsif ( $type eq 'datastore' ) {
    $filepath = "$datastores_path/$uuid.rrd";
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

################################################################################

sub get_items {
  my %params = %{ shift() };
  my $result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  $result = FusionComputeDataWrapperJSON::get_items( \%params );

  return $result;
}

sub get_mapping {
  my $uuid       = shift;
  my $dictionary = FusionComputeDataWrapperJSON::get_conf_mapping();

  return ( exists $dictionary->{mapping}{$uuid} ) ? $dictionary->{mapping}{$uuid} : undef;
}

################################################################################

sub get_conf {
  my $result = FusionComputeDataWrapperJSON::get_conf(@_);
  return $result;
}

sub get_architecture {
  my $result = FusionComputeDataWrapperJSON::get_architecture();
  return $result;
}

sub get_spec {
  my $result = FusionComputeDataWrapperJSON::get_specification();
  return $result;
}

sub get_conf_section {
  my $result = FusionComputeDataWrapperJSON::get_conf_section(@_);
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

  if ( exists $self->{label} ) {
    $result = $self->{label}->{labels}->{$type}->{$uuid};
  }
  else {
    $result = FusionComputeDataWrapperJSON::get_label(@_);
  }
  return $result;
}

sub get_conf_update_time {
  my $result = FusionComputeDataWrapperJSON::get_conf_update_time(@_);
  return $result;
}

################################################################################

1;

