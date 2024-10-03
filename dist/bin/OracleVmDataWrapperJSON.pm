# OracleVmDataWrapperJSON.pm
# interface for accessing OracleVM data:
#   accesses metadata in `conf.json`
# subroutines defined here should be called only by `OracleVMDataWrapper.pm`

package OracleVmDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

require OracleVmDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir    = $ENV{INPUTDIR};
my $wrkdir      = "$inputdir/data";
my $dc_path     = "$wrkdir/OracleVM";
my $server_path = "$wrkdir/OracleVM/server";
my $vms_path    = "$wrkdir/OracleVM/vm";
my $conf_file   = "$wrkdir/OracleVM/conf.json";

################################################################################

sub get_items {
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  if ( $params{item_type} eq 'manager' ) {
    my $all_managers = get_conf_section('manager_serverpool');
    foreach my $server ( keys %{$all_managers} ) {
      push @result, $server;
    }
  }
  elsif ( $params{item_type} eq 'server_pool' ) {
    my $pools = get_conf_section('get_all_server_pool');
    foreach my $pool ( keys %{$pools} ) {
      push @result, { $pool => get_label( 'server_pool', $pool ) };
    }
  }
  elsif ( $params{item_type} eq 'server' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'server_pool' ) {
        my $pool         = $params{parent_uuid};
        my $server_pools = get_conf_section('vms_server_pool');

        #print Dumper $server_pools;
        my @reported_servers = ( $server_pools && exists $server_pools->{$pool} ) ? @{ $server_pools->{$pool} } : ();
        foreach my $server (@reported_servers) {
          if ( -f OracleVmDataWrapper::get_filepath_rrd_vm($server) ) {
            push @result, { $server => get_label( 'vm', $server ) };
          }
        }
      }
    }
    else {
      my $all_servers = get_conf_section('get_all_server');
      foreach my $server ( keys %{$all_servers} ) {
        push @result, $server;
      }
    }
  }
  elsif ( $params{item_type} eq 'vm' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'server_pool' ) {
        my $server_pool = $params{parent_uuid};

        #my $server_vm = get_conf_section('arch-vm_server');
        my @server_pool_vms        = ();
        my @all_vms_in_server_pool = @{ get_items( { item_type => 'server', parent_type => 'server_pool', parent_uuid => $server_pool } ) };
        foreach my $vm_parse (@all_vms_in_server_pool) {
          my ( $vm_uuid, $vm_label ) = each %{$vm_parse};

          #my @server_vms = ( $server_vm && exists $server_vm->{$server_uuid} ) ? @{ $server_vm->{$server_uuid} } : ();
          push @server_pool_vms, $vm_uuid;
        }
        my %vms;
        @vms{@server_pool_vms} = ();
        foreach my $vm ( keys %vms ) {
          push @result, { $vm => get_label( 'vm', $vm ) };
        }
      }
    }
    else {
      my $all_vms = get_conf_section('get_all_vms');
      foreach my $vm ( keys %{$all_vms} ) {
        push @result, $vm;
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
    if ( open( FH, '<', "$conf_file" ) ) {
      $content = <FH>;
      close(FH);
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
  elsif ( $section eq 'arch-server_pool' ) {
    return $dictionary->{architecture}{server_pool_config};
  }
  elsif ( $section eq 'arch-vm_server' ) {
    return $dictionary->{architecture}{vms_server};
  }
  elsif ( $section eq 'vms_server_pool' ) {
    return $dictionary->{architecture}{vms_server_pool};
  }
  elsif ( $section eq 'server' ) {
    return $dictionary->{architecture}{server};
  }
  elsif ( $section eq 'spec-server' ) {
    return $dictionary->{specification}{server};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $dictionary->{specification}{vm};
  }
  elsif ( $section eq 'get_all_server_pool' ) {
    return $dictionary->{labels}{server_pool};
  }
  elsif ( $section eq 'get_all_server' ) {
    return $dictionary->{labels}{server};
  }
  elsif ( $section eq 'get_all_vms' ) {
    return $dictionary->{labels}{vm};
  }
  elsif ( $section eq 'manager_serverpool' ) {
    return $dictionary->{architecture}{manager_serverpool};
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

  #print STDERR"$conf_file!!!\n";
  return ( stat($conf_file) )[9];
}

################################################################################

1;
