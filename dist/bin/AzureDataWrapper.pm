# AzureDataWrapper.pm
# interface for accessing Azure data:

package AzureDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use JSON;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};
require AzureDataWrapperJSON;

#use AzureDataWrapperSQLite;

# XorMon-only (ACL, TODO add AzureDataWrapperSQLite as metadata source)
my $acl;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'AZURE', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Azure";

my $region_path   = "$wrkdir/region";
my $database_path = "$wrkdir/database";
my $vm_path       = "$wrkdir/vm";
my $app_path      = "$wrkdir/app";
my $conf_file     = "$wrkdir/conf.json";

################################################################################

sub get_filepath_rrd {

  # params: { type => '(vm|app|region|database)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'vm' ) {
    $filepath = "${vm_path}/$uuid.rrd";
  }
  elsif ( $type eq 'app' ) {
    $filepath = "${app_path}/$uuid.rrd";
  }
  elsif ( $type eq 'region' ) {
    $filepath = "${region_path}/$uuid.rrd";
  }
  elsif ( $type eq 'database' ) {
    $filepath = "${database_path}/$uuid.rrd";
  }
  else {
    return ();
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
    return ();
  }
}

sub get_filepath_rrd_vm {
  my $uuid     = shift;
  my $filepath = "$vm_path/" . $uuid . ".rrd";

  return if ( $use_sql && !isGranted($uuid) );
  return $filepath;
}

sub get_filepath_rrd_app {
  my $uuid     = shift;
  my $filepath = "$app_path/" . $uuid . ".rrd";

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

sub get_items {
  my %params = %{ shift() };
  my $result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  $result = AzureDataWrapperJSON::get_items( \%params );

  #if ($use_sql) {
  #  my @filtered_result;
  #  foreach my $item (@{$result}) {
  #    my %result_item = %{$item};
  #    my ($uuid, $label) = each %result_item;
  #    if ($acl->isGranted({hw_type => 'AZURE', item_id => $uuid})) {
  #      push @filtered_result, $item;
  #    }
  #  }
  #  $result = \@filtered_result;
  #}

  return $result;
}

sub get_conf {
  my $result = AzureDataWrapperJSON::get_conf(@_);
  return $result;
}

sub get_conf_section {
  my $result = AzureDataWrapperJSON::get_conf_section(@_);
  return $result;
}

sub get_labels {
  return get_conf_section('labels');
}

sub get_label {
  my ( $result, $type, $uuid );
  ( $type, $uuid ) = @_;

  $result = AzureDataWrapperJSON::get_label(@_);
  return $result;
}

sub get_conf_update_time {
  my $result = AzureDataWrapperJSON::get_conf_update_time(@_);
  return $result;
}

################################################################################

1;
