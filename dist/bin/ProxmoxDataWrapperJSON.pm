# ProxmoxDataWrapperJSON.pm
# interface for accessing Proxmox data:

package ProxmoxDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

require ProxmoxDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Proxmox";

my $node_dir          = "$wrkdir/Node";
my $vm_dir            = "$wrkdir/VM";
my $storage_dir       = "$wrkdir/Storage";
my $conf_file         = "$wrkdir/conf.json";
my $label_file        = "$wrkdir/labels.json";
my $architecture_file = "$wrkdir/architecture.json";
my $alert_file        = "$wrkdir/alert.json";

################################################################################

sub get_items {
  my %params = %{ shift() };
  my @result;

  unless ( defined $params{item_type} ) {
    return;    # return error code
  }

  my $labels = get_labels();

  if ( $params{item_type} eq 'node' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster        = $params{parent_id};
        my $clusters       = get_conf_section('arch-cluster-node');
        my @reported_nodes = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $node (@reported_nodes) {
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
        my $clusters     = get_conf_section('arch-cluster-vm');
        my @reported_vms = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $vm (@reported_vms) {
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
        my $clusters      = get_conf_section('arch-cluster-lxc');
        my @reported_lxcs = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $lxc (@reported_lxcs) {
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
        my $clusters          = get_conf_section('arch-cluster-storage');
        my @reported_storages = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $storage (@reported_storages) {
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
    my $clusters = get_conf_section('arch-cluster-node');
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
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_alert {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$alert_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
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
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_conf_architecture {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$architecture_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_conf_section {
  my $section = shift;

  my $dictionary;
  if ( $section eq 'labels' ) {
    $dictionary = get_conf_label();
  }
  elsif ( $section =~ m/arch/ ) {
    $dictionary = get_conf_architecture();
  }
  else {
    $dictionary = get_conf();
  }

  if ( $section eq 'labels' ) {
    return $dictionary->{label};
  }
  elsif ( $section eq 'arch' ) {
    return $dictionary->{architecture};
  }
  elsif ( $section eq 'arch-cluster-node' ) {
    return $dictionary->{architecture}{cluster_node};
  }
  elsif ( $section eq 'arch-cluster-vm' ) {
    return $dictionary->{architecture}{cluster_vm};
  }
  elsif ( $section eq 'arch-cluster-lxc' ) {
    return $dictionary->{architecture}{cluster_lxc};
  }
  elsif ( $section eq 'arch-cluster-storage' ) {
    return $dictionary->{architecture}{cluster_storage};
  }
  elsif ( $section eq 'spec-node' ) {
    return $dictionary->{specification}{node};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $dictionary->{specification}{vm};
  }
  elsif ( $section eq 'spec-lxc' ) {
    return $dictionary->{specification}{lxc};
  }
  elsif ( $section eq 'spec-storage' ) {
    return $dictionary->{specification}{storage};
  }
  else {
    return ();
  }

}

sub get_labels {
  return get_conf_section('labels');
}

sub get_label {
  my $type   = shift;
  my $uuid   = shift;
  my $labels = get_labels();

  return exists $labels->{$type}{$uuid} ? $labels->{$type}{$uuid} : $uuid;
}

sub get_conf_update_time {
  return ( stat($conf_file) )[9];
}

################################################################################

1;
