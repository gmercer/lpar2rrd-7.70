# PowerDataWrapper.pm
# interface for accessing IBM Power data:
#   provides filepaths

use PowerDataWrapperJSON;

package PowerDataWrapper;

use strict;
use warnings;
use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use HostCfg;
use Digest::MD5 qw(md5 md5_hex md5_base64);

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $inputdir = $ENV{INPUTDIR};

my $use_sql = 0;

################################################################################

sub get_filepath_rrd {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_filepath_rrd(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_filepath_rrd(@_);
  }
  return $result;
}

sub get_filepath_rrd_vm {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_filepath_rrd_vm(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_filepath_rrd_vm(@_);
  }
}

sub get_filepath_rrd_cpupool {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_filepath_rrd_cpupool(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_filepath_rrd_cpupool(@_);
  }
}

sub get_label {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_label(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_label(@_);
  }
}

sub get_pool_name {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_pool_name(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_pool_name(@_);
  }
}

sub get_conf {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_conf(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_conf(@_);
  }
}

sub get_items {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_items(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_items(@_);
  }
}

sub get_hmcs {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_hmcs(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_hmcs(@_);
  }
}

sub get_server_parent {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_server_parent(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_server_parent(@_);
  }
}

sub get_server_metric {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_server_metric(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_server_metric(@_);
  }
}

sub get_metric_from_config_cfg {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_metric_from_config_cfg(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_metric_from_config_cfg(@_);
  }
}

sub get_pool_parent {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_pool_parent(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_pool_parent(@_);
  }
}

sub get_vm_parent {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_vm_parent(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_vm_parent(@_);
  }
}

sub get_int_parent {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_int_parent(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_int_parent(@_);
  }
}

sub get_pool_id {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_pool_id(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_pool_id(@_);
  }
}

sub get_servers {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_servers(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_servers(@_);
  }
}

sub get_pools {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_pools(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_pools(@_);
  }
}

sub get_vms {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_vms(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_vms(@_);
  }
}

sub get_interfaces {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_interfaces(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_interfaces(@_);
  }
}

sub get_vm_tabs {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_vm_tabs(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_vm_tabs(@_);
  }
}

sub get_some_label {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_some_label(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_some_label(@_);
  }
}

sub lpar_id_to_name {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::lpar_id_to_name(@_);
  }
  else {
    $result = PowerDataWrapperJSON::lpar_id_to_name(@_);
  }
}

sub get_server_uid {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_server_uid(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_server_uid(@_);
  }
}

sub get_item_uid {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_item_uid(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_item_uid(@_);
  }
}

sub get_status {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_status(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_status(@_);
  }
}

sub getPartitionState {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::getPartitionState(@_);
  }
  else {
    $result = PowerDataWrapperJSON::getPartitionState(@_);
  }
}

sub update_conf {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::update_conf(@_);
  }
  else {
    $result = PowerDataWrapperJSON::update_conf(@_);
  }
}

sub getServerCount {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::getServerCount(@_);
  }
  else {
    $result = PowerDataWrapperJSON::getServerCount(@_);
  }
}

sub getLparCount {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::getLparCount(@_);
  }
  else {
    $result = PowerDataWrapperJSON::getLparCount(@_);
  }
}

sub md5_string {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::md5_string(@_);
  }
  else {
    $result = PowerDataWrapperJSON::md5_string(@_);
  }
}

sub handle_db_error {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::handle_db_error(@_);
  }
  else {
    $result = PowerDataWrapperJSON::handle_db_error(@_);
  }
}

sub parse_servername_from_filename {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::parse_servername_from_filename(@_);
  }
  else {
    $result = PowerDataWrapperJSON::parse_servername_from_filename(@_);
  }
}

sub get_dictionary {
  my $result;
  if ($use_sql) {
    $result = PowerDataWrapperSQL::get_dictionary(@_);
  }
  else {
    $result = PowerDataWrapperJSON::get_dictionary(@_);
  }
}

sub init {
  my $result1;
  my $result2;
  if ($use_sql) {
    ( $result1, $result2 ) = PowerDataWrapperSQL::init(@_);
  }
  else {
    ( $result1, $result2 ) = PowerDataWrapperJSON::init(@_);
  }
  return ( $result1, $result2 );
}

1;
