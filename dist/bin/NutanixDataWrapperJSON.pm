# NutanixDataWrapperJSON.pm
# interface for accessing Nutanix data:

package NutanixDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

require NutanixDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/NUTANIX";

my $hosts_path         = "$wrkdir/HOST";
my $vms_path           = "$wrkdir/VM";
my $sc_path            = "$wrkdir/SC";
my $conf_file          = "$wrkdir/conf.json";
my $alert_file         = "$wrkdir/alerts.json";
my $health_file        = "$wrkdir/health.json";
my $label_file         = "$wrkdir/label.json";
my $architecture_file  = "$wrkdir/architecture.json";
my $specification_file = "$wrkdir/specification.json";
my $mapping_file       = "$wrkdir/mapping.json";

################################################################################

sub get_items {
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  my $labels = get_labels();

  if ( $params{item_type} eq 'host' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $pool           = $params{parent_uuid};
        my $pools          = get_conf_section('arch-cluster');
        my @reported_hosts = ( $pools && exists $pools->{$pool} ) ? @{ $pools->{$pool} } : ();
        foreach my $host (@reported_hosts) {
          my $host_path = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'host', 'uuid' => $host } );
          if ( defined $host_path && -f $host_path ) {
            push @result, { $host => $labels->{host}->{$host} };
          }
        }
      }
    }
    else {
      if ( -d "$hosts_path" ) {

        # get all hosts' directories
        opendir( DIR, $hosts_path ) || warn( ' cannot open directory : ' . $hosts_path . __FILE__ . ':' . __LINE__ ) && return;
        my @hosts_dir = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        foreach my $host (@hosts_dir) {
          unless ( -d "$hosts_path/$host" ) { next; }
          push @result, { $host => $labels->{host}->{$host} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'container' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster             = $params{parent_uuid};
        my $containers          = get_conf_section('arch-cluster-container');
        my @reported_containers = ( $containers && exists $containers->{$cluster} ) ? @{ $containers->{$cluster} } : ();
        foreach my $container (@reported_containers) {
          my $container_path = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'container', 'uuid' => $container } );
          if ( defined $container_path && -f $container_path ) {
            push @result, { $container => $labels->{container}->{$container} };
          }
        }
      }
    }
    else {
      if ( -d "$sc_path" ) {

        # get all hosts' directories
        opendir( DIR, $sc_path ) || warn( ' cannot open directory : ' . $sc_path . __FILE__ . ':' . __LINE__ ) && return;
        my @sc_dir = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        foreach my $sc (@sc_dir) {
          unless ( -d "$sc_path/$sc" ) { next; }
          push @result, { $sc => $labels->{container}->{$sc} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'pool' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster        = $params{parent_uuid};
        my $pools          = get_conf_section('arch-cluster-pool');
        my @reported_pools = ( $pools && exists $pools->{$cluster} ) ? @{ $pools->{$cluster} } : ();
        foreach my $pool (@reported_pools) {
          push @result, { $pool => $labels->{pool}->{$pool} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'disk' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'pool' ) {
        my $pool           = $params{parent_uuid};
        my $disks          = get_conf_section('arch-pool-disk');
        my @reported_disks = ( $disks && exists $disks->{$pool} ) ? @{ $disks->{$pool} } : ();
        foreach my $disk (@reported_disks) {
          push @result, { $disk => $labels->{disk}->{$disk} };
        }
      }
      elsif ( $params{parent_type} eq 'cluster' ) {
        my $cluster        = $params{parent_uuid};
        my $disks          = get_conf_section('arch-cluster-disk');
        my @reported_disks = ( $disks && exists $disks->{$cluster} ) ? @{ $disks->{$cluster} } : ();
        foreach my $disk (@reported_disks) {
          push @result, { $disk => $labels->{disk}->{$disk} };
        }
      }
      elsif ( $params{parent_type} eq 'host' ) {
        my $host           = $params{parent_uuid};
        my $disks          = get_conf_section('arch-host-disk');
        my @reported_disks = ( $disks && exists $disks->{$host} ) ? @{ $disks->{$host} } : ();
        foreach my $disk (@reported_disks) {
          push @result, { $disk => $labels->{disk}->{$disk} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'vdisk' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'vm' ) {
        my $vm              = $params{parent_uuid};
        my $vdisks          = get_conf_section('arch-vm-vdisk');
        my @reported_vdisks = ( $vdisks && exists $vdisks->{$vm} ) ? @{ $vdisks->{$vm} } : ();
        foreach my $vdisk (@reported_vdisks) {
          push @result, { $vdisk => $labels->{vdisk}->{$vdisk} };
        }
      }
      elsif ( $params{parent_type} eq 'cluster' ) {
        my $cluster         = $params{parent_uuid};
        my $vdisks          = get_conf_section('arch-cluster-vdisk');
        my @reported_vdisks = ( $vdisks && exists $vdisks->{$cluster} ) ? @{ $vdisks->{$cluster} } : ();
        foreach my $vdisk (@reported_vdisks) {
          push @result, { $vdisk => $labels->{vdisk}->{$vdisk} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'vm' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster      = $params{parent_uuid};
        my $vms          = get_conf_section('arch-cluster-vm');
        my @reported_vms = ( $vms && exists $vms->{$cluster} ) ? @{ $vms->{$cluster} } : ();
        foreach my $vm (@reported_vms) {
          push @result, { $vm => $labels->{vm}->{$vm} };
        }
      }
      elsif ( $params{parent_type} eq 'host' ) {
        my $host    = $params{parent_uuid};
        my $host_vm = get_conf_section('arch-host-vm');
        if ( $host_vm && exists $host_vm->{$host} ) {
          foreach my $vm ( @{ $host_vm->{$host} } ) {
            push @result, { $vm => $labels->{vm}->{$vm} };
          }
        }
      }
    }
    else {
      if ( -d "$vms_path" ) {

        # get all VM RRD filenames
        opendir( DIR, $vms_path ) || warn( ' cannot open directory : ' . $vms_path . __FILE__ . ':' . __LINE__ ) && return;
        my @vm_dir = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        my $regex          = qr/\.rrd$/;
        my @filtered_files = grep /$regex/, @vm_dir;

        foreach my $file (@vm_dir) {
          unless ( -f "$vms_path/$file" ) { next; }
          my $uuid = $file;
          $uuid =~ s/$regex//;

          push @result, { $uuid => $labels->{vm}->{$uuid} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'cluster' ) {
    my $clusters = get_conf_section('arch-cluster');
    foreach my $cluster ( keys %{$clusters} ) {
      push @result, { $cluster => $labels->{cluster}->{$cluster} };
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
    if ( open( my $fh, '<', "$conf_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ JSON->new->utf8(0)->decode($content) };
    }
  }
  return \%dictionary;
}

sub get_conf_mapping {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$mapping_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ JSON->new->utf8(0)->decode($content) };
    }
  }
  return \%dictionary;
}

sub get_conf_label {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$label_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ JSON->new->utf8(0)->decode($content) };
    }
  }
  return \%dictionary;
}

sub get_architecture {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$architecture_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ JSON->new->utf8(0)->decode($content) };
    }
  }
  return \%dictionary;
}

sub get_specification {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$specification_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ JSON->new->utf8(0)->decode($content) };
    }
  }
  return \%dictionary;
}

sub get_alerts {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$alert_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ JSON->new->utf8(0)->decode($content) };
    }
  }
  return \%dictionary;
}

sub get_health {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$health_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ JSON->new->utf8(0)->decode($content) };
    }
  }
  return \%dictionary;
}

sub get_conf_section {
  my $section = shift;

  my $dictionary;

  if ( $section =~ m/label/ ) {
    $dictionary = get_conf_label();
  }
  elsif ( $section =~ m/arch/ ) {
    $dictionary = get_architecture();
  }
  elsif ( $section =~ m/spec/ ) {
    $dictionary = get_specification();
  }
  elsif ( $section =~ m/alert/ ) {
    $dictionary = get_alerts();
  }
  elsif ( $section =~ m/event/ ) {
    $dictionary = get_alerts();
  }
  elsif ( $section =~ m/health/ ) {
    $dictionary = get_health();
  }
  elsif ( $section =~ m/mapping/ ) {
    $dictionary = get_conf_mapping();
    return $dictionary->{mapping};
  }
  else {
    $dictionary = ();
  }

  if ( $section eq 'labels' ) {
    return $dictionary->{labels};
  }
  elsif ( $section eq 'arch' ) {
    return $dictionary->{architecture};
  }
  elsif ( $section eq 'arch-host-vm' ) {
    return $dictionary->{architecture}{host_vm};
  }
  elsif ( $section eq 'arch-cluster-vm' ) {
    return $dictionary->{architecture}{cluster_vm};
  }
  elsif ( $section eq 'arch-cluster-container' ) {
    return $dictionary->{architecture}{cluster_container};
  }
  elsif ( $section eq 'arch-cluster-pool' ) {
    return $dictionary->{architecture}{cluster_pool};
  }
  elsif ( $section eq 'arch-cluster-vdisk' ) {
    return $dictionary->{architecture}{cluster_vdisk};
  }
  elsif ( $section eq 'arch-cluster-disk' ) {
    return $dictionary->{architecture}{cluster_disk};
  }
  elsif ( $section eq 'arch-pool-disk' ) {
    return $dictionary->{architecture}{pool_disk};
  }
  elsif ( $section eq 'arch-vm-vdisk' ) {
    return $dictionary->{architecture}{vm_vdisk};
  }
  elsif ( $section eq 'arch-host-disk' ) {
    return $dictionary->{architecture}{host_disk};
  }
  elsif ( $section eq 'arch-cluster' ) {
    return $dictionary->{architecture}{cluster};
  }
  elsif ( $section eq 'spec-host' ) {
    return $dictionary->{specification}{host};
  }
  elsif ( $section eq 'spec-container' ) {
    return $dictionary->{specification}{container};
  }
  elsif ( $section eq 'spec-pool' ) {
    return $dictionary->{specification}{pool};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $dictionary->{specification}{vm};
  }
  elsif ( $section eq 'spec-disk' ) {
    return $dictionary->{specification}{disk};
  }
  elsif ( $section eq 'spec-vdisk' ) {
    return $dictionary->{specification}{vdisk};
  }
  elsif ( $section eq 'alerts' ) {
    return $dictionary->{alerts};
  }
  elsif ( $section eq 'events' ) {
    return $dictionary->{events};
  }
  elsif ( $section eq 'health' ) {
    return $dictionary;
  }
  else {
    return ();
  }
}

sub get_labels {
  return get_conf_section('labels');
}

sub get_label {
  my $type   = shift;          # "pool", "host", "vm", "sr", "vdi", "network", "sc", "sp", "vg", "vd"
  my $uuid   = shift;
  my $labels = get_labels();

  return exists $labels->{$type}{$uuid} ? $labels->{$type}{$uuid} : $uuid;
}

sub get_host_cpu_count {
  my $uuid       = shift;
  my $dictionary = get_conf_section('spec-host');

  return exists $dictionary->{$uuid}{cpu_count} ? $dictionary->{$uuid}{cpu_count} : -1;
}

sub get_conf_update_time {
  return ( stat($specification_file) )[9];
}

################################################################################

1;

