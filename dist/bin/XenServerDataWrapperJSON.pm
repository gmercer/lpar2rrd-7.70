# XenServerDataWrapperJSON.pm
# interface for accessing XenServer data:
#   accesses metadata in `conf.json`
# subroutines defined here should be called only by `XenServerDataWrapper.pm`
# alternative backend will be `XenServerDataWrapperSQLite`

package XenServerDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

require XenServerDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data";

my $hosts_path = "$wrkdir/XEN";
my $vms_path   = "$wrkdir/XEN_VMs";
my $conf_file  = "$wrkdir/XEN_iostats/conf.json";

################################################################################

#     get_items({ item_type   => $string1, # e.g. 'vm', 'pool', 'storage'
#                 parent_type => $string2, # e.g. 'pool', 'host'
#                 parent_uuid => $string3,
#                 item_mask   => $regex1,  # TODO
#                 parent_mask => $regex2   # TODO
#               });
#
# return: ( { uuid1 => 'label1' }, { uuid2 => 'label2' }, ... )

sub get_items {
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  if ( $params{item_type} eq 'host' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'pool' ) {
        my $pool           = $params{parent_uuid};
        my $pools          = get_conf_section('arch-pool');
        my @reported_hosts = ( $pools && exists $pools->{$pool} ) ? @{ $pools->{$pool} } : ();
        foreach my $host (@reported_hosts) {
          my $host_rrd = XenServerDataWrapper::get_filepath_rrd( { type => 'host', uuid => $host } );
          if ( $host_rrd && -f $host_rrd ) {
            push @result, { $host => get_label( 'host', $host ) };
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
          push @result, { $host => get_label( 'host', $host ) };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'vm' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'pool' ) {
        my $pool    = $params{parent_uuid};
        my $host_vm = get_conf_section('arch-host-vm');
        my @hosts   = @{ get_items( { item_type => 'host', parent_type => 'pool', parent_uuid => $pool } ) };
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
          push @result, { $vm => get_label( 'vm', $vm ) };
        }
      }
      elsif ( $params{parent_type} eq 'host' ) {
        my $host    = $params{parent_uuid};
        my $host_vm = get_conf_section('arch-host-vm');
        if ( $host_vm && exists $host_vm->{$host} ) {
          foreach my $vm ( @{ $host_vm->{$host} } ) {
            push @result, { $vm => get_label( 'vm', $vm ) };
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

          push @result, { $uuid => get_label( 'vm', $uuid ) };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'pool' ) {
    my $pools = get_conf_section('arch-pool');
    foreach my $pool ( keys %{$pools} ) {
      push @result, { $pool => get_label( 'pool', $pool ) };
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
              my $uuid = complete_sr_uuid( $id, $host );
              next unless ($uuid);
              push @result, { $uuid => get_label( 'sr', $uuid ) };
            }
            elsif ( $file =~ m/^lan-(.*)\.rrd$/ && $params{item_type} eq 'network' ) {
              my $id   = $1;
              my $uuid = get_network_uuid( $id, $host );
              next unless ($uuid);
              push @result, { $uuid => get_label( 'network', $uuid ) };
            }
          }
        }
      }
    }
  }

  return \@result;
}

################################################################################

sub get_conf {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $FH, '<', "$conf_file" ) ) {
      $content = <$FH>;
      close $FH;
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_conf_section {
  my $section    = shift;
  my $dictionary = get_conf();

  if ( $section eq 'labels' ) {
    return $dictionary->{labels};
  }
  elsif ( $section eq 'arch' ) {
    return $dictionary->{architecture};
  }
  elsif ( $section eq 'arch-host-vm' ) {
    return $dictionary->{architecture}{host_vm};
  }
  elsif ( $section eq 'arch-pool' ) {
    return $dictionary->{architecture}{pool};
  }
  elsif ( $section eq 'arch-network' ) {
    return $dictionary->{architecture}{network};
  }
  elsif ( $section eq 'arch-storage' ) {
    return $dictionary->{architecture}{storage};
  }
  elsif ( $section eq 'spec-host' ) {
    return $dictionary->{specification}{host};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $dictionary->{specification}{vm};
  }
  elsif ( $section eq 'spec-pif' ) {
    return $dictionary->{specification}{pif};
  }
  elsif ( $section eq 'spec-sr' ) {
    return $dictionary->{specification}{sr};
  }
  elsif ( $section eq 'spec-vdi' ) {
    return $dictionary->{specification}{vdi};
  }
  else {
    return ();
  }
}

# TODO eventually add other types
# note: returns an array, because some objects may have multiple parents
#   e.g., storage connected to several hosts
sub get_parent {
  my $type = shift;
  my $uuid = shift;
  my $dictionary;
  my @result;

  if ( $type eq 'network' ) {
    $dictionary = get_conf_section('spec-pif');
    if ( exists $dictionary->{$uuid}{parent_host} ) {
      push @result, $dictionary->{$uuid}{parent_host};
    }
  }
  elsif ( $type eq 'storage' ) {
    $dictionary = get_conf_section('arch-storage');
    if ( exists $dictionary->{sr_host}{$uuid} ) {
      push @result, @{ $dictionary->{sr_host}{$uuid} };
    }
  }

  return \@result;
}

sub get_network_uuid {
  my $net_device = shift;
  my $host_uuid  = shift;
  my $dictionary = get_conf_section('arch-network');

  foreach my $host ( keys %{ $dictionary->{host_pif} } ) {
    if ( $host eq $host_uuid ) {
      foreach my $pif ( @{ $dictionary->{host_pif}{$host} } ) {
        my $pif_device = get_network_device($pif);
        if ( $pif_device && $pif_device eq $net_device ) {
          return $pif;
        }
      }
    }
  }

  return;
}

sub get_network_device {
  my $pif_uuid   = shift;
  my $dictionary = get_conf_section('spec-pif');

  if ( exists $dictionary->{$pif_uuid}{device} ) {
    return $dictionary->{$pif_uuid}{device};
  }

  return;
}

sub complete_sr_uuid {
  my $sr_uuid_start = shift;
  my $host_uuid     = shift;
  my $dictionary    = get_conf_section('arch-storage');

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

sub get_labels {
  return get_conf_section('labels');
}

sub get_label {
  my $type   = shift;          # "pool", "host", "vm", "sr", "vdi", "network"
  my $uuid   = shift;
  my $labels = get_labels();

  if ( $type eq 'network' ) {
    my $device = get_network_device($uuid);
    return $device ? $device : $uuid;
  }

  return exists $labels->{$type}{$uuid} ? $labels->{$type}{$uuid} : $uuid;
}

sub get_host_cpu_count {
  my $uuid       = shift;
  my $dictionary = get_conf_section('spec-host');

  return exists $dictionary->{$uuid}{cpu_count} ? $dictionary->{$uuid}{cpu_count} : -1;
}

sub get_conf_update_time {
  return ( stat($conf_file) )[9];
}

################################################################################

1;
