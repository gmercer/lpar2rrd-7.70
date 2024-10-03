# OVirtDataWrapperOOP.pm
# interface for accessing oVirt data:
#   provides filepaths

package OVirtDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( ' INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data";

my $dc_path      = "$wrkdir/oVirt";
my $host_path    = "$wrkdir/oVirt/host";
my $storage_path = "$wrkdir/oVirt/storage";
my $vms_path     = "$wrkdir/oVirt/vm";
my $conf_file    = "$wrkdir/oVirt/metadata.json";

################################################################################

sub new {
  my ( $self, %args ) = @_;

  my $o = {};
  $o->{configuration} = get_conf();
  $o->{updated}       = ( stat($conf_file) )[9];
  $o->{acl_check}     = ( defined $args{acl_check} ) ? $args{acl_check} : 0;
  if ( $o->{acl_check} ) {
    require ACLx;
    $o->{aclx} = ACLx->new();
  }
  bless $o;

  return $o;
}

sub get_items {
  my $self   = shift;
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  # TODO
  if ( $params{item_type} eq 'datacenter' ) {
  }
  elsif ( $params{item_type} eq 'cluster' ) {
  }
  elsif ( $params{item_type} eq 'host' ) {
  }
  elsif ( $params{item_type} eq 'storage_domain' ) {
  }
  elsif ( $params{item_type} eq 'vm' ) {
  }
  elsif ( $params{item_type} eq 'disk' ) {
  }

  # ACL check
  if ( $self->{acl_check} ) {
    my @filtered;
    foreach my $item (@result) {
      my %this_item = %{$item};
      my ( $uuid, $label ) = each %this_item;
      if ( $self->is_granted($uuid) ) {
        push @filtered, { $uuid => $label };
      }
    }
    @result = @filtered;
  }

  return \@result;
}

sub get_filepath_rrd {

  # params: { type => '(host|storage_domain|vm|disk|host_nic|vm_nic)', uuid => 'DEADBEEF' }
  #     optional params id (for nic) and metric (for metrics added in separate rrds)
  #     optional flag skip_acl, optional legacy param id
  my $self   = shift;
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
  if ( $self->{acl_check} && !$skip_acl ) {
    if ( !$self->is_granted($uuid) ) {
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

sub get_conf_section {
  my $self    = shift;
  my $section = shift;
  my $ref;

  if ( $section eq 'labels' ) {
    $ref = $self->{configuration}{labels};
  }
  elsif ( $section eq 'mapping' ) {
    $ref = $self->{configuration}{mapping};
  }
  elsif ( $section eq 'arch' ) {
    $ref = $self->{configuration}{architecture};
  }
  elsif ( $section eq 'arch-dc' ) {
    $ref = $self->{configuration}{architecture}{datacenter};
  }
  elsif ( $section eq 'arch-cl' ) {
    $ref = $self->{configuration}{architecture}{cluster};
  }
  elsif ( $section eq 'arch-host' ) {
    $ref = $self->{configuration}{architecture}{host};
  }
  elsif ( $section eq 'arch-sd' ) {
    $ref = $self->{configuration}{architecture}{storage_domain};
  }
  elsif ( $section eq 'arch-vm' ) {
    $ref = $self->{configuration}{architecture}{vm};
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
  my $self    = shift;
  my $uuid    = shift;
  my $type    = shift;
  my $subtype = shift;

  return ( exists $self->{configuration}{architecture}{$type}{$uuid}{$subtype} ) ? $self->{configuration}{architecture}{$type}{$uuid}{$subtype} : [];
}

# get_parent ( $type,
#              $parent_type,
#              $uuid )
#  return: parent_uuid
sub get_parent {
  my $self = shift;
  my $type = shift;
  my $uuid = shift;

  return $self->{configuration}{architecture}{$type}{$uuid}{parent};
}

# get_labels ( )
#  return: ( type1 => { uuid1 => "label1", ... }, type2 => { ... }, ... )
sub get_labels {
  my $self = shift;

  return $self->{configuration}{labels};
}

# get_label ( $type,
#              $uuid )
#  return: label
sub get_label {
  my $self = shift;
  my $type = shift;
  my $uuid = shift;

  return ( exists $self->{configuration}{labels}{$type}{$uuid} ) ? $self->{configuration}{labels}{$type}{$uuid} : $uuid;
}

# get_mapping ( $uuid )
#  return: agent_dirname
sub get_mapping {
  my $self = shift;
  my $uuid = shift;

  return ( exists $self->{configuration}{mapping}{$uuid} ) ? $self->{configuration}{mapping}{$uuid} : undef;
}

# get_uuids ( $type )
#  return: [ $uuid1, $uuid2,  ... ]
sub get_uuids {
  my $self = shift;
  my $type = shift;
  my $ref  = [];

  if ( exists $self->{configuration}{labels}{$type} ) {
    my @keys = keys %{ $self->{configuration}{labels}{$type} };
    $ref = \@keys;
  }

  return $ref;
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'OVIRT', item_id => $uuid, match => 'granted' } );
  }

  return;
}

################################################################################

sub get_conf {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$conf_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

################################################################################

1;
