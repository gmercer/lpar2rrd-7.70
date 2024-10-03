# OVirtDataWrapper.pm
# interface for accessing oVirt data:
#   provides filepaths

package OVirtDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib qw(error read_json);

# XorMon-only (ACL, TODO add OVirtDataWrapperSQLite as metadata source)
my $acl;
my $use_sql = 0;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'OVIRT', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || warn( ' INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir        = $ENV{INPUTDIR};
my $wrkdir          = "$inputdir/data";
my $dc_path         = "$wrkdir/oVirt";
my $host_path       = "$wrkdir/oVirt/host";
my $storage_path    = "$wrkdir/oVirt/storage";
my $vms_path        = "$wrkdir/oVirt/vm";
my $metadata_file   = "$wrkdir/oVirt/metadata.json";
my %dictionary      = ();
my $metadata_loaded = 0;

################################################################################

sub get_filepath_rrd {

  # params: { type => '(host|storage_domain|vm|disk|host_nic|vm_nic)', uuid => 'DEADBEEF' }
  #     optional params id (for nic) and metric (for metrics added in newer rrds)
  #     optional flag skip_acl, optional legacy param id
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'host' ) {
    $filepath = "${host_path}/$uuid/sys.rrd";
  }
  elsif ( $type eq 'storage_domain' ) {
    $filepath = "${storage_path}/sd-$uuid.rrd";
  }
  elsif ( $type eq 'vm' ) {
    $filepath = "${vms_path}/$uuid/sys.rrd";
  }
  elsif ( $type eq 'disk' ) {
    if ( defined $params->{metric} && $params->{metric} =~ m/iops/ ) {
      $filepath = "${storage_path}/disk2-$uuid.rrd";
    }
    else {
      $filepath = "${storage_path}/disk-$uuid.rrd";
    }
  }
  elsif ( $type eq 'host_nic' ) {
    if ( defined $params->{id} ) {
      my $id = $params->{id};
      $filepath = "${host_path}/$uuid/nic-$id.rrd";
    }
  }
  elsif ( $type eq 'vm_nic' ) {
    if ( defined $params->{id} ) {
      my $id = $params->{id};
      $filepath = "${vms_path}/$uuid/nic-$id.rrd";
    }
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

################################################################################

sub get_conf {
  if ( !$metadata_loaded && -f $metadata_file ) {
    my ( $code, $ref ) = Xorux_lib::read_json($metadata_file);
    $metadata_loaded = $code;
    %dictionary      = $code ? %{$ref} : ();
  }

  return \%dictionary;
}

sub get_conf_section {
  my $section    = shift;
  my $dictionary = get_conf();
  my $ref;

  if ( $section eq "labels" ) {
    $ref = $dictionary->{labels};
  }
  elsif ( $section eq "mapping" ) {
    $ref = $dictionary->{mapping};
  }
  elsif ( $section eq "win_mapping" ) {
    $ref = $dictionary->{win_mapping};
  }
  elsif ( $section eq "arch" ) {
    $ref = $dictionary->{architecture};
  }
  elsif ( $section eq "arch-dc" ) {
    $ref = $dictionary->{architecture}{datacenter};
  }
  elsif ( $section eq "arch-cl" ) {
    $ref = $dictionary->{architecture}{cluster};
  }
  elsif ( $section eq "arch-host" ) {
    $ref = $dictionary->{architecture}{host};
  }
  elsif ( $section eq "arch-sd" ) {
    $ref = $dictionary->{architecture}{storage_domain};
  }
  elsif ( $section eq "arch-disk" ) {
    $ref = $dictionary->{architecture}{disk};
  }
  elsif ( $section eq "arch-vm" ) {
    $ref = $dictionary->{architecture}{vm};
  }
  else {
    $ref = {};
  }

  return defined $ref && ref($ref) eq 'HASH' ? $ref : {};
}

# get_arch ( $uuid,
#            $type,
#            $subtype
#          )
#  return: [ $uuid1, $uuid2  ... ] i.e. reference to list of child uuids of subtype entries
#
sub get_arch {
  my $uuid    = shift;
  my $type    = shift;
  my $subtype = shift;
  my $conf    = get_conf();

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

# get_label ( $type, $uuid )
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

# get_win_mapping ( $uuid )
#  return: agent_dirname
sub get_win_mapping {
  my $uuid       = shift;
  my $dictionary = get_conf();

  return ( exists $dictionary->{win_mapping}{$uuid} ) ? $dictionary->{win_mapping}{$uuid} : undef;
}

# get_uuids ( $type )
#  return: [ $uuid1, $uuid2,  ... ]
sub get_uuids {
  my $type = shift;
  my $conf = get_conf();
  my $ref  = [];

  if ( exists $conf->{labels}{$type} ) {
    my @keys = keys %{ $conf->{labels}{$type} };
    $ref = \@keys;
  }

  return $ref;
}

################################################################################

1;
