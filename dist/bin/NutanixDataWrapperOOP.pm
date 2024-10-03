# NutanixDataWrapperOOP.pm
# interface for accessing Nutanix data:

package NutanixDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;
use utf8;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/NUTANIX";

my $hosts_path         = "$wrkdir/HOST";
my $vms_path           = "$wrkdir/VM";
my $containers_path    = "$wrkdir/SC";
my $pools_path         = "$wrkdir/SP";
my $vdisks_path        = "$wrkdir/VD";
my $conf_file          = "$wrkdir/conf.json";
my $alert_file         = "$wrkdir/alerts.json";
my $health_file        = "$wrkdir/health.json";
my $label_file         = "$wrkdir/label.json";
my $architecture_file  = "$wrkdir/architecture.json";
my $specification_file = "$wrkdir/specification.json";
my $mapping_file       = "$wrkdir/mapping.json";

################################################################################

sub new {
  my ( $self, $args ) = @_;

  my $o = {};
  $o->{configuration} = get_conf();
  $o->{labels}        = ( defined $args->{conf_labels} && $args->{conf_labels} ) ? get_conf('label') : {};
  $o->{architecture}  = ( defined $args->{conf_arch} && $args->{conf_arch} ) ? get_conf('arch') : {};
  $o->{specification} = ( defined $args->{conf_spec} && $args->{conf_spec} ) ? get_conf('spec') : {};
  $o->{alerts}        = ( defined $args->{conf_alerts} && $args->{conf_alerts} ) ? get_conf('alert') : {};
  $o->{events}        = ( defined $args->{conf_events} && $args->{conf_events} ) ? get_conf('event') : {};
  $o->{health}        = ( defined $args->{conf_health} && $args->{conf_health} ) ? get_conf('health') : {};
  $o->{mapping}       = ( defined $args->{conf_mapping} && $args->{conf_mapping} ) ? get_conf('mapping') : {};
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

  my $labels = $self->get_labels();
  if ( $params{item_type} eq 'host' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $pool           = $params{parent_uuid};
        my $pools          = $self->get_conf_section('arch-cluster');
        my @reported_hosts = ( $pools && exists $pools->{$pool} ) ? @{ $pools->{$pool} } : ();
        foreach my $host (@reported_hosts) {
          my $host_path = $self->get_filepath_rrd( { 'type' => 'host', 'uuid' => $host } );
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
          unless ( -d "${hosts_path}/$host" ) { next; }
          push @result, { $host => $labels->{host}->{$host} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'container' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster             = $params{parent_uuid};
        my $containers          = $self->get_conf_section('arch-cluster-container');
        my @reported_containers = ( $containers && exists $containers->{$cluster} ) ? @{ $containers->{$cluster} } : ();
        foreach my $container (@reported_containers) {
          my $container_path = $self->get_filepath_rrd( { 'type' => 'container', 'uuid' => $container } );
          if ( defined $container_path && -f $container_path ) {
            push @result, { $container => $labels->{container}->{$container} };
          }
        }
      }
    }
    else {
      if ( -d "$containers_path" ) {

        # get all hosts' directories
        opendir( DIR, $containers_path ) || warn( ' cannot open directory : ' . $containers_path . __FILE__ . ':' . __LINE__ ) && return;
        my @sc_dir = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        foreach my $sc (@sc_dir) {
          unless ( -d "${containers_path}/$sc" ) { next; }
          push @result, { $sc => $labels->{container}->{$sc} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'pool' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster        = $params{parent_uuid};
        my $pools          = $self->get_conf_section('arch-cluster-pool');
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
        my $disks          = $self->get_conf_section('arch-pool-disk');
        my @reported_disks = ( $disks && exists $disks->{$pool} ) ? @{ $disks->{$pool} } : ();
        foreach my $disk (@reported_disks) {
          push @result, { $disk => $labels->{disk}->{$disk} };
        }
      }
      elsif ( $params{parent_type} eq 'cluster' ) {
        my $cluster        = $params{parent_uuid};
        my $disks          = $self->get_conf_section('arch-cluster-disk');
        my @reported_disks = ( $disks && exists $disks->{$cluster} ) ? @{ $disks->{$cluster} } : ();
        foreach my $disk (@reported_disks) {
          push @result, { $disk => $labels->{disk}->{$disk} };
        }
      }
      elsif ( $params{parent_type} eq 'host' ) {
        my $host           = $params{parent_uuid};
        my $disks          = $self->get_conf_section('arch-host-disk');
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
        my $vdisks          = $self->get_conf_section('arch-vm-vdisk');
        my @reported_vdisks = ( $vdisks && exists $vdisks->{$vm} ) ? @{ $vdisks->{$vm} } : ();
        foreach my $vdisk (@reported_vdisks) {
          push @result, { $vdisk => $labels->{vdisk}->{$vdisk} };
        }
      }
      elsif ( $params{parent_type} eq 'cluster' ) {
        my $cluster         = $params{parent_uuid};
        my $vdisks          = $self->get_conf_section('arch-cluster-vdisk');
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
        my $vms          = $self->get_conf_section('arch-cluster-vm');
        my @reported_vms = ( $vms && exists $vms->{$cluster} ) ? @{ $vms->{$cluster} } : ();
        foreach my $vm (@reported_vms) {
          push @result, { $vm => $labels->{vm}->{$vm} };
        }
      }
      elsif ( $params{parent_type} eq 'host' ) {
        my $host    = $params{parent_uuid};
        my $host_vm = $self->get_conf_section('arch-host-vm');
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
          unless ( -f "${vms_path}/$file" ) { next; }
          my $uuid = $file;
          $uuid =~ s/$regex//;

          push @result, { $uuid => $labels->{vm}->{$uuid} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'cluster' ) {
    my $clusters = $self->get_conf_section('arch-cluster');
    foreach my $cluster ( keys %{$clusters} ) {
      push @result, { $cluster => $labels->{cluster}->{$cluster} };
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

  # params: { type => '(vm|host|disk|container|vdisk|pool)', uuid => 'DEADBEEF' }
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
  elsif ( $type eq 'disk' ) {
    if ( defined $params->{parent} ) {
      $filepath = "${hosts_path}/$params->{parent}/disk-$uuid.rrd";
    }
    else {
      my $spec      = $self->get_conf_section('spec-disk');
      my $host_uuid = $spec->{$uuid}{node_uuid};
      $filepath = "${hosts_path}/${host_uuid}/disk-$uuid.rrd";
    }
  }
  elsif ( $type eq 'container' ) {
    $filepath = "${containers_path}/$uuid.rrd";
  }
  elsif ( $type eq 'vdisk' ) {
    $filepath = "${vdisks_path}/$uuid.rrd";
  }
  elsif ( $type eq 'pool' ) {
    $filepath = "${pools_path}/$uuid.rrd";
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

sub get_conf_section {
  my $self    = shift;
  my $section = shift;

  if ( $section eq 'labels' ) {
    return $self->{labels}{labels};
  }
  elsif ( $section eq 'arch' ) {
    return $self->{architecture}{architecture};
  }
  elsif ( $section eq 'arch-host-vm' ) {
    return $self->{architecture}{architecture}{host_vm};
  }
  elsif ( $section eq 'arch-cluster-vm' ) {
    return $self->{architecture}{architecture}{cluster_vm};
  }
  elsif ( $section eq 'arch-cluster-container' ) {
    return $self->{architecture}{architecture}{cluster_container};
  }
  elsif ( $section eq 'arch-cluster-pool' ) {
    return $self->{architecture}{architecture}{cluster_pool};
  }
  elsif ( $section eq 'arch-cluster-vdisk' ) {
    return $self->{architecture}{architecture}{cluster_vdisk};
  }
  elsif ( $section eq 'arch-cluster-disk' ) {
    return $self->{architecture}{architecture}{cluster_disk};
  }
  elsif ( $section eq 'arch-pool-disk' ) {
    return $self->{architecture}{architecture}{pool_disk};
  }
  elsif ( $section eq 'arch-vm-vdisk' ) {
    return $self->{architecture}{architecture}{vm_vdisk};
  }
  elsif ( $section eq 'arch-host-disk' ) {
    return $self->{architecture}{architecture}{host_disk};
  }
  elsif ( $section eq 'arch-cluster' ) {
    return $self->{architecture}{architecture}{cluster};
  }
  elsif ( $section eq 'spec-host' ) {
    return $self->{specification}{specification}{host};
  }
  elsif ( $section eq 'spec-container' ) {
    return $self->{specification}{specification}{container};
  }
  elsif ( $section eq 'spec-pool' ) {
    return $self->{specification}{specification}{pool};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $self->{specification}{specification}{vm};
  }
  elsif ( $section eq 'spec-disk' ) {
    return $self->{specification}{specification}{disk};
  }
  elsif ( $section eq 'spec-vdisk' ) {
    return $self->{specification}{specification}{vdisk};
  }
  elsif ( $section eq 'alerts' ) {
    return $self->{alerts}{alerts};
  }
  elsif ( $section eq 'events' ) {
    return $self->{events}{events};
  }
  elsif ( $section eq 'health' ) {
    return $self->{health};
  }
  elsif ( $section eq 'mapping' ) {
    return $self->{mapping};
  }
  else {
    return ();
  }
}

sub get_labels {
  my $self = shift;
  return $self->get_conf_section('labels');
}

sub get_label {
  my $self = shift;
  my $type = shift;
  my $uuid = shift;
  return exists $self->{labels}{labels}{$type}{$uuid} ? $self->{labels}{labels}{$type}{$uuid} : $uuid;
}

sub get_host_cpu_count {
  my $self = shift;
  my $uuid = shift;
  return exists $self->{specification}{specification}{host}{$uuid}{cpu_count} ? $self->{specification}{specification}{host}{$uuid}{cpu_count} : -1;
}

sub shorten_sr_uuid {
  my $self = shift;
  my $uuid = shift;
  return ( split( '-', $uuid ) )[0];
}

sub get_conf_update_time {
  my $self = shift;
  return $self->{updated};
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'NUTANIX', item_id => $uuid, match => 'granted' } );
  }

  return;
}

################################################################################

sub get_conf {
  my $type = shift || 'conf';

  my $path;
  if ( $type =~ m/label/ ) {
    $path = $label_file;
  }
  elsif ( $type =~ m/arch/ ) {
    $path = $architecture_file;
  }
  elsif ( $type =~ m/spec/ ) {
    $path = $specification_file;
  }
  elsif ( $type =~ m/alert/ ) {
    $path = $alert_file;
  }
  elsif ( $type =~ m/event/ ) {
    $path = $alert_file;
  }
  elsif ( $type =~ m/health/ ) {
    $path = $health_file;
  }
  elsif ( $type =~ m/mapping/ ) {
    $path = $mapping_file;
  }
  else {
    $path = $conf_file;
  }

  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$path" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ JSON->new->utf8(0)->decode($content) };
    }
  }
  return \%dictionary;
}

################################################################################

1;
