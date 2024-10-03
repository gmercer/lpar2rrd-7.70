# XenServerDataWrapperOOP.pm
# interface for accessing XenServer data:

package XenServerDataWrapperOOP;

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

my $hosts_path = "$wrkdir/XEN";
my $vms_path   = "$wrkdir/XEN_VMs";
my $conf_file  = "$wrkdir/XEN_iostats/conf.json";

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

  if ( $params{item_type} eq 'host' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'pool' ) {
        my $pool           = $params{parent_uuid};
        my $pools          = $self->get_conf_section('arch-pool');
        my @reported_hosts = ( $pools && exists $pools->{$pool} ) ? @{ $pools->{$pool} } : ();
        foreach my $host (@reported_hosts) {
          my $host_rrd = $self->get_filepath_rrd( { type => 'host', uuid => $host } );
          if ( $host_rrd && -f $host_rrd ) {
            push @result, { $host => $self->get_label( 'host', $host ) };
          }
        }
      }
    }
    else {
      if ( -d "$hosts_path" ) {

        # get all hosts' directories
        opendir my $DIR, $hosts_path || warn( ' cannot open directory : ' . $hosts_path . __FILE__ . ':' . __LINE__ ) && return;
        my @hosts_dir = grep !/^\.\.?$/, readdir $DIR;
        closedir $DIR;

        foreach my $host (@hosts_dir) {
          next unless ( -d "${hosts_path}/$host" );
          push @result, { $host => $self->get_label( 'host', $host ) };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'vm' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'pool' ) {
        my $pool    = $params{parent_uuid};
        my $host_vm = $self->get_conf_section('arch-host-vm');
        my @hosts   = @{ $self->get_items( { item_type => 'host', parent_type => 'pool', parent_uuid => $pool } ) };
        my @pool_vms;
        foreach my $host (@hosts) {
          my %host_item = %{$host};
          my ( $host_uuid, $host_label ) = each %host_item;
          my @host_vms = ( $host_vm && exists $host_vm->{$host_uuid} ) ? @{ $host_vm->{$host_uuid} } : ();
          push @pool_vms, @host_vms;
        }
        my %vms;
        @vms{@pool_vms} = ();
        foreach my $vm ( keys %vms ) {
          push @result, { $vm => $self->get_label( 'vm', $vm ) };
        }
      }
      elsif ( $params{parent_type} eq 'host' ) {
        my $host    = $params{parent_uuid};
        my $host_vm = $self->get_conf_section('arch-host-vm');
        if ( $host_vm && exists $host_vm->{$host} ) {
          foreach my $vm ( @{ $host_vm->{$host} } ) {
            push @result, { $vm => $self->get_label( 'vm', $vm ) };
          }
        }
      }
    }
    else {
      if ( -d "$vms_path" ) {

        # get all VM RRD filenames
        opendir my $DIR, $vms_path || warn( ' cannot open directory : ' . $vms_path . __FILE__ . ':' . __LINE__ ) && return;
        my @vm_dir = grep !/^\.\.?$/, readdir $DIR;
        closedir $DIR;

        my $regex          = qr/\.rrd$/;
        my @filtered_files = grep /$regex/, @vm_dir;

        foreach my $file (@vm_dir) {
          next unless ( -f "${vms_path}/$file" );

          my $uuid = $file;
          $uuid =~ s/$regex//;

          push @result, { $uuid => $self->get_label( 'vm', $uuid ) };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'pool' ) {
    my $pools = $self->get_conf_section('arch-pool');
    foreach my $pool ( keys %{$pools} ) {
      push @result, { $pool => $self->get_label( 'pool', $pool ) };
    }
  }
  elsif ( $params{item_type} eq 'storage' || $params{item_type} eq 'network' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'host' ) {
        my $host = $params{parent_uuid};
        if ( -d "$hosts_path/$host" ) {
          opendir my $DIR, "$hosts_path/$host" || warn( " cannot open directory : $hosts_path/$host " . __FILE__ . ':' . __LINE__ ) && return;
          my @host_dir = grep !/^\.\.?$/, readdir $DIR;
          closedir $DIR;

          my $regex          = qr/\.rrd$/;
          my @filtered_files = grep /$regex/, @host_dir;

          foreach my $file (@filtered_files) {
            if ( $file =~ m/^disk-(.*)\.rrd$/ && $params{item_type} eq 'storage' ) {
              my $id   = $1;
              my $uuid = $self->complete_sr_uuid( $id, $host );
              next unless ($uuid);
              push @result, { $uuid => $self->get_label( 'sr', $uuid ) };
            }
            elsif ( $file =~ m/^lan-(.*)\.rrd$/ && $params{item_type} eq 'network' ) {
              my $id   = $1;
              my $uuid = $self->get_network_uuid( $id, $host );
              next unless ($uuid);
              push @result, { $uuid => $self->get_label( 'network', $uuid ) };
            }
          }
        }
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

  # params: { type => '(vm|host|storage|network)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $self   = shift;
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'vm' ) {
    $filepath = "${vms_path}/$uuid.rrd";
  }
  elsif ( $type eq 'host' ) {
    $filepath = "${hosts_path}/$uuid/sys.rrd";
  }
  elsif ( $type eq 'storage' ) {

    # cover both call contexts: (a) host uuid and device id, (b) device uuid
    if ( defined $params->{id} ) {
      my $id = $params->{id};
      $filepath = "${hosts_path}/$uuid/disk-$id.rrd";

      # TODO translate ID to UUID for finer ACL check
    }
    else {
      my $short_uuid = $self->shorten_sr_uuid($uuid);
      foreach my $host_uuid ( @{ $self->get_parent( 'storage', $uuid ) } ) {
        $filepath = "${hosts_path}/${host_uuid}/disk-${short_uuid}.rrd";
        next unless ( -f $filepath );
      }
    }
  }
  elsif ( $type eq 'network' ) {

    # cover both call contexts: (a) host uuid and device id, (b) device uuid
    if ( defined $params->{id} ) {
      my $id = $params->{id};
      $filepath = "${hosts_path}/$uuid/lan-$id.rrd";

      # TODO translate ID to UUID for finer ACL check
    }
    else {
      my $pif_device = $self->get_network_device($uuid);
      foreach my $host_uuid ( @{ $self->get_parent( 'network', $uuid ) } ) {
        $filepath = "${hosts_path}/${host_uuid}/lan-${pif_device}.rrd";
        next unless ( -f $filepath );
      }
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
  elsif ( $section eq 'arch' ) {
    return $self->{configuration}{architecture};
  }
  elsif ( $section eq 'arch-host-vm' ) {
    return $self->{configuration}{architecture}{host_vm};
  }
  elsif ( $section eq 'arch-pool' ) {
    return $self->{configuration}{architecture}{pool};
  }
  elsif ( $section eq 'arch-network' ) {
    return $self->{configuration}{architecture}{network};
  }
  elsif ( $section eq 'arch-storage' ) {
    return $self->{configuration}{architecture}{storage};
  }
  elsif ( $section eq 'spec-host' ) {
    return $self->{configuration}{specification}{host};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $self->{configuration}{specification}{vm};
  }
  elsif ( $section eq 'spec-pif' ) {
    return $self->{configuration}{specification}{pif};
  }
  elsif ( $section eq 'spec-sr' ) {
    return $self->{configuration}{specification}{sr};
  }
  elsif ( $section eq 'spec-vdi' ) {
    return $self->{configuration}{specification}{vdi};
  }
  else {
    return ();
  }
}

# TODO eventually add other types
# note: returns an array, because some objects may have multiple parents
#   e.g., storage connected to several hosts
sub get_parent {
  my $self = shift;
  my $type = shift;
  my $uuid = shift;
  my $dictionary;
  my @result;

  if ( $type eq 'network' ) {
    $dictionary = $self->get_conf_section('spec-pif');
    if ( exists $dictionary->{$uuid}{parent_host} ) {
      push @result, $dictionary->{$uuid}{parent_host};
    }
  }
  elsif ( $type eq 'storage' ) {
    $dictionary = $self->get_conf_section('arch-storage');
    if ( exists $dictionary->{sr_host}{$uuid} ) {
      push @result, @{ $dictionary->{sr_host}{$uuid} };
    }
  }

  return \@result;
}

sub get_network_uuid {
  my $self       = shift;
  my $net_device = shift;
  my $host_uuid  = shift;
  my $dictionary = $self->get_conf_section('arch-network');

  foreach my $host ( keys %{ $dictionary->{host_pif} } ) {
    if ( $host eq $host_uuid ) {
      foreach my $pif ( @{ $dictionary->{host_pif}{$host} } ) {
        my $pif_device = $self->get_network_device($pif);
        if ( $pif_device && $pif_device eq $net_device ) {
          return $pif;
        }
      }
    }
  }

  return;
}

sub get_network_device {
  my $self       = shift;
  my $pif_uuid   = shift;
  my $dictionary = $self->get_conf_section('spec-pif');

  if ( exists $dictionary->{$pif_uuid}{device} ) {
    return $dictionary->{$pif_uuid}{device};
  }

  return;
}

sub complete_sr_uuid {
  my $self          = shift;
  my $sr_uuid_start = shift;
  my $host_uuid     = shift;
  my $dictionary    = $self->get_conf_section('arch-storage');

  foreach my $sr ( keys %{ $dictionary->{sr_host} } ) {
    if ( $sr =~ m/^$sr_uuid_start/ ) {
      foreach my $sr_host ( @{ $dictionary->{sr_host}{$sr} } ) {
        if ( $sr_host eq $host_uuid ) {
          return $sr;
        }
      }
    }
  }

  return;
}

sub get_label {
  my $self       = shift;
  my $type       = shift;                               # "pool", "host", "vm", "sr", "vdi", "network"
  my $uuid       = shift;
  my $dictionary = $self->get_conf_section('labels');

  if ( $type eq 'network' ) {
    my $device = $self->get_network_device($uuid);
    return $device ? $device : $uuid;
  }

  return exists $dictionary->{$type}{$uuid} ? $dictionary->{$type}{$uuid} : $uuid;
}

sub get_host_cpu_count {
  my $self       = shift;
  my $uuid       = shift;
  my $dictionary = $self->get_conf_section('spec-host');

  return exists $dictionary->{$uuid}{cpu_count} ? $dictionary->{$uuid}{cpu_count} : -1;
}

sub get_conf_update_time {
  my $self = shift;
  return $self->{updated};
}

sub shorten_sr_uuid {
  my $self = shift;
  my $uuid = shift;
  return ( split( '-', $uuid ) )[0];
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'XENSERVER', item_id => $uuid, match => 'granted' } );
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
