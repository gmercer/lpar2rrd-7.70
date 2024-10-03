# NutanixWrapper.pm
# interface for accessing Nutanix data:

package NutanixDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};
require NutanixDataWrapperJSON;

#use NutanixDataWrapperSQLite;

# XorMon-only (ACL, TODO add NutanixDataWrapperSQLite as metadata source)
my $acl;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'NUTANIX', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $input_dir       = $ENV{INPUTDIR};
my $wrkdir          = "$input_dir/data/NUTANIX";
my $hosts_path      = "$wrkdir/HOST";
my $vms_path        = "$wrkdir/VM";
my $containers_path = "$wrkdir/SC";
my $pools_path      = "$wrkdir/SP";
my $vdisks_path     = "$wrkdir/VD";
my $conf_file       = "$wrkdir/conf.json";

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
    $filepath = "$hosts_path/$uuid/sys.rrd";
  }
  elsif ( $type eq 'disk' ) {
    if ( defined $params->{parent} ) {
      $filepath = "$hosts_path/" . $params->{parent} . "/disk-" . $uuid . ".rrd";
    }
    else {
      my $spec      = get_conf_section('spec-disk');
      my $host_uuid = $spec->{$uuid}{node_uuid};
      $filepath = "$hosts_path/" . $host_uuid . "/disk-" . $uuid . ".rrd";
    }
  }
  elsif ( $type eq 'container' ) {
    $filepath = "$containers_path/$uuid.rrd";
  }
  elsif ( $type eq 'vdisk' ) {
    $filepath = "$vdisks_path/$uuid.rrd";
  }
  elsif ( $type eq 'pool' ) {
    $filepath = "$pools_path/$uuid.rrd";
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

  $result = NutanixDataWrapperJSON::get_items( \%params );

  return $result;
}

sub is_active {
  return get_items( { item_type => 'host' } ) ? 1 : 0;
}

# get_mapping ( $uuid )
#  return: agent_dirname
sub get_mapping {
  my $uuid       = shift;
  my $dictionary = NutanixDataWrapperJSON::get_conf_mapping();

  return ( exists $dictionary->{mapping}{$uuid} ) ? $dictionary->{mapping}{$uuid} : undef;
}

################################################################################

sub get_conf {
  my $result = NutanixDataWrapperJSON::get_conf(@_);
  return $result;
}

sub get_architecture {
  my $result = NutanixDataWrapperJSON::get_architecture();
  return $result;
}

sub get_spec {
  my $result = NutanixDataWrapperJSON::get_specification();
  return $result;
}

sub get_conf_section {
  my $result = NutanixDataWrapperJSON::get_conf_section(@_);
  return $result;
}

sub get_parent {
  my $result = NutanixDataWrapperJSON::get_parent(@_);
  return $result;
}

sub get_network_uuid {
  my $result = NutanixDataWrapperJSON::get_network_uuid(@_);
  return $result;
}

sub get_network_device {
  my $result = NutanixDataWrapperJSON::get_network_device(@_);
  return $result;
}

sub complete_sr_uuid {
  my $result = NutanixDataWrapperJSON::complete_sr_uuid(@_);
  return $result;
}

sub shorten_sr_uuid {
  my $uuid = shift;
  return ( split( '-', $uuid ) )[0];
}

sub get_labels {
  return get_conf_section('labels');
}

sub get_label {
  my ( $result, $type, $uuid );

  if ( scalar(@_) == 2 ) {
    ( $type, $uuid ) = @_;
  }

  $result = NutanixDataWrapperJSON::get_label(@_);
  return $result;
}

sub get_host_cpu_count {
  my $result = NutanixDataWrapperJSON::get_host_cpu_count(@_);
  return $result;
}

sub get_conf_update_time {
  my $result = NutanixDataWrapperJSON::get_conf_update_time(@_);
  return $result;
}

################################################################################

1;

