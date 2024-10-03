# ProxmoxDataWrapperOOP.pm
# interface for accessing Proxmox data:

package ProxmoxDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Proxmox";

my $node_path         = "$wrkdir/Node";
my $vm_path           = "$wrkdir/VM";
my $lxc_path          = "$wrkdir/LXC";
my $storage_path      = "$wrkdir/Storage";
my $conf_file         = "$wrkdir/conf.json";
my $label_file        = "$wrkdir/labels.json";
my $architecture_file = "$wrkdir/architecture.json";
my $alert_file        = "$wrkdir/alert.json";

################################################################################

sub new {
  my ( $self, $args ) = @_;

  my $o = {};
  $o->{configuration} = get_conf();
  $o->{labels}        = ( defined $args->{conf_labels} && $args->{conf_labels} ) ? get_conf('label') : {};
  $o->{architecture}  = ( defined $args->{conf_arch} && $args->{conf_arch} ) ? get_conf('arch') : {};
  $o->{alerts}        = ( defined $args->{conf_alerts} && $args->{conf_alerts} ) ? get_conf('alert') : {};
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

  if ( $params{item_type} eq 'node' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster        = $params{parent_id};
        my $clusters       = $self->get_conf_section('arch-cluster-node');
        my @reported_nodes = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        my @sorted = sort { $labels->{node}->{$a} cmp $labels->{node}->{$b} } @reported_nodes;
	foreach my $node (@sorted) {
          push @result, { $node => $labels->{node}->{$node} };
        }
      }
    }
    else {
      foreach my $node ( keys %{ $labels->{node} } ) {
        push @result, { $node => $labels->{node}->{$node} };
      }
    }
  }
  elsif ( $params{item_type} eq 'vm' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster      = $params{parent_id};
        my $clusters     = $self->get_conf_section('arch-cluster-vm');
        my @reported_vms = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        my @sorted = sort { $labels->{vm}->{$a} cmp $labels->{vm}->{$b} } @reported_vms;
	foreach my $vm (@sorted) {
          push @result, { $vm => $labels->{vm}->{$vm} };
        }
      }
    }
    else {
      foreach my $vm ( keys %{ $labels->{vm} } ) {
        push @result, { $vm => $labels->{vm}->{$vm} };
      }
    }
  }
  elsif ( $params{item_type} eq 'lxc' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster       = $params{parent_id};
        my $clusters      = $self->get_conf_section('arch-cluster-lxc');
        my @reported_lxcs = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        my @sorted = sort { $labels->{lxc}->{$a} cmp $labels->{lxc}->{$b} } @reported_lxcs;
	foreach my $lxc (@sorted) {
          push @result, { $lxc => $labels->{lxc}->{$lxc} };
        }
      }
    }
    else {
      foreach my $lxc ( keys %{ $labels->{lxc} } ) {
        push @result, { $lxc => $labels->{lxc}->{$lxc} };
      }
    }
  }
  elsif ( $params{item_type} eq 'storage' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster           = $params{parent_id};
        my $clusters          = $self->get_conf_section('arch-cluster-storage');
        my @reported_storages = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        my @sorted = sort { $labels->{storage}->{$a} cmp $labels->{storage}->{$b} } @reported_storages;
	foreach my $storage (@sorted) {
          push @result, { $storage => $labels->{storage}->{$storage} };
        }
      }
    }
    else {
      foreach my $storage ( keys %{ $labels->{storage} } ) {
        push @result, { $storage => $labels->{storage}->{$storage} };
      }
    }
  }
  elsif ( $params{item_type} eq 'cluster' ) {
    my $clusters = $self->get_conf_section('arch-cluster-node');
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
  if ( $type eq 'node' ) {
    $filepath = "${node_path}/$uuid.rrd";
  }
  elsif ( $type eq 'vm' ) {
    $filepath = "${vm_path}/$uuid.rrd";
  }
  elsif ( $type eq 'lxc' ) {
    $filepath = "${lxc_path}/$uuid.rrd";
  }
  elsif ( $type eq 'storage' ) {
    $filepath = "${storage_path}/$uuid.rrd";
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
    return $self->{labels}{label};
  }
  elsif ( $section eq 'arch' ) {
    return $self->{architecture}{architecture};
  }
  elsif ( $section eq 'arch-cluster-node' ) {
    return $self->{architecture}{architecture}{cluster_node};
  }
  elsif ( $section eq 'arch-cluster-vm' ) {
    return $self->{architecture}{architecture}{cluster_vm};
  }
  elsif ( $section eq 'arch-cluster-lxc' ) {
    return $self->{architecture}{architecture}{cluster_lxc};
  }
  elsif ( $section eq 'arch-cluster-storage' ) {
    return $self->{architecture}{architecture}{cluster_storage};
  }
  elsif ( $section eq 'spec-node' ) {
    return $self->{configuration}{specification}{node};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $self->{configuration}{specification}{vm};
  }
  elsif ( $section eq 'spec-lxc' ) {
    return $self->{configuration}{specification}{lxc};
  }
  elsif ( $section eq 'spec-storage' ) {
    return $self->{configuration}{specification}{storage};
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
  return exists $self->{labels}{label}{$type}{$uuid} ? $self->{labels}{label}{$type}{$uuid} : $uuid;
}

sub get_conf_update_time {
  my $self = shift;
  return $self->{updated};
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'PROXMOX', item_id => $uuid, match => 'granted' } );
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
  elsif ( $type =~ m/alert/ ) {
    $path = $alert_file;
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
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

################################################################################

1;
