# OracleVmDataWrapper.pm
package OracleVmDataWrapper;
use strict;
use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json);

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

my $acl;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'ORACLEVM', item_id => $uuid, match => 'granted' } );
  }
}

require OracleVmDataWrapperJSON;

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $inputdir        = $ENV{INPUTDIR};
my $wrkdir          = "$inputdir/data";
my $dc_path         = "$wrkdir/OracleVM";
my $server_path     = "$wrkdir/OracleVM/server";
my $vms_path        = "$wrkdir/OracleVM/vm";
my $metadata_file   = "$wrkdir/OracleVM/conf.json";
my %dictionary      = ();
my $metadata_loaded = 0;

################################################################################

sub get_conf {
  if ( !$metadata_loaded && -f $metadata_file ) {
    my ( $code, $ref ) = Xorux_lib::read_json($metadata_file);
    $metadata_loaded = $code;
    %dictionary      = $code ? %{$ref} : ();
  }

  return \%dictionary;
}

sub get_filepath_rrd_server {
  my $host_uuid = shift;
  return "$server_path/$host_uuid/sys.rrd";
}

sub get_filepath_rrd_server_net {
  my $host_uuid = shift;
  my $net_name  = shift;

  return "$server_path/$host_uuid/lan-$net_name.rrd";
}

sub get_filepath_rrd_server_disk {
  my $host_uuid = shift;
  my $disk_uuid = shift;

  return "$server_path/$host_uuid/disk-$disk_uuid.rrd";
}

sub get_filepath_rrd_vm {
  my $vm_uuid = shift;

  return "$vms_path/$vm_uuid/sys.rrd";
}

sub get_filepath_rrd_vm_disk {
  my $vm_uuid      = shift;
  my $vm_disk_uuid = shift;
  $vm_disk_uuid =~ s/\.iso|\.img//g;
  $vm_disk_uuid =~ s/\/dev\/mapper\///g;
  return "$vms_path/$vm_uuid/disk-$vm_disk_uuid.rrd";
}

sub get_filepath_rrd_vm_net {
  my $vm_uuid  = shift;
  my $net_uuid = shift;
  $net_uuid =~ s/:/===double-col===/g;
  return "$vms_path/$vm_uuid/lan-$net_uuid.rrd";
}

sub get_filepath_rrd {

  # params: { type => '(server|vm|)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'server' ) {
    $filepath = "$server_path/$uuid/sys.rrd";
  }
  elsif ( $type eq 'server_net' ) {
    if ( defined $params->{component_name} ) {
      my $net_name = $params->{component_name};
      $filepath = "$server_path/$uuid/lan-$net_name.rrd";
    }
  }
  elsif ( $type eq 'server_disk' ) {
    if ( defined $params->{component_name} ) {
      my $disk_uuid = $params->{component_name};
      $filepath = "$server_path/$uuid/disk-$disk_uuid.rrd";
    }
  }
  elsif ( $type eq 'vm' ) {
    $filepath = "$vms_path/$uuid/sys.rrd";
  }
  elsif ( $type eq 'vm_disk' ) {
    if ( defined $params->{component_name} ) {
      my $vm_disk_uuid = $params->{component_name};
      $vm_disk_uuid =~ s/\.iso|\.img//g;
      $vm_disk_uuid =~ s/\/dev\/mapper\///g;
      $filepath = "$vms_path/$uuid/disk-$vm_disk_uuid.rrd";
    }
  }
  elsif ( $type eq 'vm_net' ) {
    if ( defined $params->{component_name} ) {
      my $net_uuid = $params->{component_name};
      $net_uuid =~ s/:/===double-col===/g;
      $filepath = "$vms_path/$uuid/lan-$net_uuid.rrd";
    }
  }
  else {
    Xorux_lib::error( "Unknown rrd type $type: " . __FILE__ . ":" . __LINE__ );
    return '';
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
# get_items returns anything that is present on the host, but may not be running
# thus, the item may not have a performance (RRD) file
# that leads to issues when generating aggregated graphs, unless you always check the RRD filepath

sub get_items {
  my %params = %{ shift() };
  my $result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  $result = OracleVmDataWrapperJSON::get_items( \%params );

  return $result;
}

sub get_conf_section {
  my $result = OracleVmDataWrapperJSON::get_conf_section(@_);
  return $result;
}

sub get_arch {
  my $uuid    = shift;
  my $type    = shift;
  my $subtype = shift;
  my $conf    = get_conf();

  #my $test = $conf->{architecture}{ $type }{ $uuid }{ $subtype };
  #print Dumper $test;
  return ( exists $conf->{architecture}{$type}{$uuid}{$subtype} ) ? $conf->{architecture}{$type}{$uuid}{$subtype} : [];
}

sub get_arch_server {
  my $uuid    = shift;
  my $type    = shift;
  my $subtype = shift;
  my $conf    = get_conf();

  #my $test = $conf->{architecture}{ $type }{ $uuid }{ $subtype };
  #print Dumper $test;
  return ( exists $conf->{arch_server}{$type}{$uuid}{$subtype} ) ? $conf->{arch_server}{$type}{$uuid}{$subtype} : [];
}

sub get_arch_manager {
  my $uuid    = shift;
  my $type    = shift;
  my $subtype = shift;
  my $conf    = get_conf();

  #my $test = $conf->{architecture}{ $type }{ $uuid }{ $subtype };
  #print Dumper $test;
  return ( exists $conf->{architecture}{$type}{$uuid}{$subtype} ) ? $conf->{architecture}{$type}{$uuid}{$subtype} : [];
}

# get_parent ( $type,
#              $parent_type,
#              $uuid )
#  return: parent_uuid
sub get_parent {
  my $type = shift;
  my $uuid = shift;
  my $conf = get_conf();

  return $conf->{architecture}{$type}{$uuid}{parent};
}

# get_labels ( )
#  return: ( type1 => { uuid1 => "label1", ... }, type2 => { ... }, ... )
sub get_labels {
  my $dictionary = get_conf();

  return $dictionary->{labels};
}

# get_label ( $type,
#              $uuid )
#  return: label
sub get_label {
  my $type       = shift;
  my $uuid       = shift;
  my $dictionary = get_conf();
  return ( exists $dictionary->{labels}{$type}{$uuid} ) ? $dictionary->{labels}{$type}{$uuid} : $uuid;
}

# get_mapping ( $uuid )
#  return: agent_dirname
sub get_mapping {
  my $uuid       = shift;
  my $dictionary = get_conf();

  return ( exists $dictionary->{mapping}{$uuid} ) ? $dictionary->{mapping}{$uuid} : undef;
}

# get_uuids ( $type )
#  return: [ $uuid1, $uuid2,  ... ]
sub get_uuids {
  my $type = shift;
  my $conf = get_conf();
  my $ref  = [];

  #print Dumper $conf;

  if ( exists $conf->{labels}{$type} ) {
    my @keys = keys %{ $conf->{labels}{$type} };
    $ref = \@keys;
  }

  return $ref;
}

sub get_conf_update_time {
  my $result = OracleVmDataWrapperJSON::get_conf_update_time(@_);
  return $result;
}

################################################################################
1;
