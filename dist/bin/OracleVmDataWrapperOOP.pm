# OracleVmDataWrapperOOP.pm
# interface for accessing OracleVM data:

package OracleVmDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data";

my $dc_path     = "$wrkdir/OracleVM";
my $server_path = "$wrkdir/OracleVM/server";
my $vms_path    = "$wrkdir/OracleVM/vm";
my $conf_file   = "$wrkdir/OracleVM/conf.json";

################################################################################

sub new {
  my ( $self, $args ) = @_;

  my $o = {};
  $o->{configuration} = get_conf();
  $o->{updated}       = ( stat($conf_file) )[9];
  $o->{acl_check}     = ( defined $args->{acl_check} ) ? $args->{acl_check} : 0;
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

  if ( $params{item_type} eq 'manager' ) {
    my $all_managers = $self->get_conf_section('manager_serverpool');
    foreach my $server ( keys %{$all_managers} ) {
      push @result, { $server => $self->get_label( 'manager', $server ) }
    }
  }
  elsif ( $params{item_type} eq 'server_pool' ) {
    my $pools = $self->get_conf_section('get_all_server_pool');
    foreach my $pool ( keys %{$pools} ) {
      push @result, { $pool => $self->get_label( 'server_pool', $pool ) };
    }
  }
  elsif ( $params{item_type} eq 'server' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'server_pool' ) {
        my $pool         = $params{parent_uuid};
        my $server_pools = $self->get_conf_section('vms_server_pool');

        #print Dumper $server_pools;
        my @reported_servers = ( $server_pools && exists $server_pools->{$pool} ) ? @{ $server_pools->{$pool} } : ();
        foreach my $server (@reported_servers) {
          if ( -f $self->get_filepath_rrd( { type => 'server', uuid => $server } ) ) {
            push @result, { $server => $self->get_label( 'server', $server ) };
          }
        }
      }
    }
    else {
      my $all_servers = $self->get_conf_section('get_all_server');
      foreach my $server ( keys %{$all_servers} ) {
        push @result, { $server => $self->get_label( 'server', $server ) };
      }
    }
  }
  elsif ( $params{item_type} eq 'vm' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'server_pool' ) {
        my $server_pool            = $params{parent_uuid};
        my @server_pool_vms        = ();
        my @all_vms_in_server_pool = @{ $self->get_items( { item_type => 'server', parent_type => 'server_pool', parent_uuid => $server_pool } ) };
        foreach my $vm_parse (@all_vms_in_server_pool) {
          my ( $vm_uuid, $vm_label ) = each %{$vm_parse};
          push @server_pool_vms, $vm_uuid;
        }
        my %vms;
        @vms{@server_pool_vms} = ();
        foreach my $vm ( keys %vms ) {
          push @result, { $vm => $self->get_label( 'vm', $vm ) };
        }
      }
    }
    else {
      my $all_vms = $self->get_conf_section('get_all_vms');
      foreach my $vm ( keys %{$all_vms} ) {
        push @result, { $vm => $self->get_label( 'vm', $vm ) };
      }
    }
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

  # params: { type => '(server|server_net|server_disk|vm|vm_net|vm_disk)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $self   = shift;
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'server' ) {
    $filepath = "${server_path}/$uuid/sys.rrd";
  }
  elsif ( $type eq 'server_net' ) {
    if ( defined $params->{component_name} ) {
      my $net_name = $params->{component_name};
      $filepath = "${server_path}/$uuid/lan-${net_name}.rrd";
    }
  }
  elsif ( $type eq 'server_disk' ) {
    if ( defined $params->{component_name} ) {
      my $disk_uuid = $params->{component_name};
      $filepath = "${server_path}/$uuid/disk-${disk_uuid}.rrd";
    }
  }
  elsif ( $type eq 'vm' ) {
    $filepath = "${vms_path}/$uuid/sys.rrd";
  }
  elsif ( $type eq 'vm_disk' ) {
    if ( defined $params->{component_name} ) {
      my $vm_disk_uuid = $params->{component_name};
      $vm_disk_uuid =~ s/\.iso|\.img//g;
      $vm_disk_uuid =~ s/\/dev\/mapper\///g;
      $filepath = "${vms_path}/$uuid/disk-${vm_disk_uuid}.rrd";
    }
  }
  elsif ( $type eq 'vm_net' ) {
    if ( defined $params->{component_name} ) {
      my $net_uuid = $params->{component_name};
      $net_uuid =~ s/:/===double-col===/g;
      $filepath = "${vms_path}/$uuid/lan-${net_uuid}.rrd";
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

  if ( $section eq 'labels' ) {
    return $self->{configuration}{labels};
  }
  elsif ( $section eq 'arch-server_pool' ) {
    return $self->{configuration}{architecture}{server_pool_config};
  }
  elsif ( $section eq 'arch-vm_server' ) {
    return $self->{configuration}{architecture}{vms_server};
  }
  elsif ( $section eq 'vms_server_pool' ) {
    return $self->{configuration}{architecture}{vms_server_pool};
  }
  elsif ( $section eq 'server' ) {
    return $self->{configuration}{architecture}{server};
  }
  elsif ( $section eq 'spec-server' ) {
    return $self->{configuration}{specification}{server};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $self->{configuration}{specification}{vm};
  }
  elsif ( $section eq 'get_all_server_pool' ) {
    return $self->{configuration}{labels}{server_pool};
  }
  elsif ( $section eq 'get_all_server' ) {
    return $self->{configuration}{labels}{server};
  }
  elsif ( $section eq 'get_all_vms' ) {
    return $self->{configuration}{labels}{vm};
  }
  elsif ( $section eq 'manager_serverpool' ) {
    return $self->{configuration}{architecture}{manager_serverpool};
  }
  else {
    return ();
  }
}

sub get_arch {
  my $self    = shift;
  my $uuid    = shift;
  my $type    = shift;
  my $subtype = shift;

  return ( exists $self->{configuration}{architecture}{$type}{$uuid}{$subtype} ) ? $self->{configuration}{architecture}{$type}{$uuid}{$subtype} : [];
}

sub get_labels {
  my $self = shift;

  return $self->{configuration}{labels};
}

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

sub get_label {
  my $self       = shift;
  my $type       = shift;                               # "manager", "server_pool", "server", "vm"
  my $uuid       = shift;
  my $dictionary = $self->get_conf_section('labels');

  return exists $dictionary->{$type}{$uuid} ? $dictionary->{$type}{$uuid} : $uuid;
}

sub get_mapping {
  my $self = shift;
  my $uuid = shift;

  return ( exists $self->{configuration}{mapping}{$uuid} ) ? $self->{configuration}{mapping}{$uuid} : undef;
}

sub get_conf_update_time {
  my $self = shift;
  return $self->{updated};
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'ORACLEVM', item_id => $uuid, match => 'granted' } );
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

1;
