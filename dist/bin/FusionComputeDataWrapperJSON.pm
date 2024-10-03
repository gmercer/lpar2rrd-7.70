# FusionComputeDataWrapperJSON.pm
# interface for accessing FusionCompute data:

package FusionComputeDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

require FusionComputeDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/FusionCompute";

my $hosts_path         = "$wrkdir/Host";
my $vms_path           = "$wrkdir/VM";
my $clusters_path      = "$wrkdir/Cluster";
my $datastores_path    = "$wrkdir/Datastore";
my $label_file         = "$wrkdir/label.json";
my $architecture_file  = "$wrkdir/architecture.json";
my $specification_file = "$wrkdir/specification.json";
my $mapping_file       = "$wrkdir/mapping.json";
my $alerts_file        = "$wrkdir/alerts.json";
my $urn_file           = "$wrkdir/urn.json";

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
        my $cluster        = $params{parent_uuid};
        my $clusters       = get_conf_section('arch-cluster-host');
        my @reported_hosts = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $host (@reported_hosts) {
          my $host_path = FusionComputeDataWrapper::get_filepath_rrd( { 'type' => 'host', 'uuid' => $host } );
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
          unless ( -e "$hosts_path/$host" ) { next; }
          $host =~ s/.rrd//;
          push @result, { $host => $labels->{host}->{$host} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'vm' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster      = $params{parent_uuid};
        my $clusters     = get_conf_section('arch-cluster-vm');
        my @reported_vms = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $vm (@reported_vms) {
          my $vm_path = FusionComputeDataWrapper::get_filepath_rrd( { 'type' => 'vm', 'uuid' => $vm } );
          if ( defined $vm_path && -f $vm_path ) {
            push @result, { $vm => $labels->{vm}->{$vm} };
          }
        }
      }
      elsif ( $params{parent_type} eq 'host' ) {
        my $host         = $params{parent_uuid};
        my $hosts        = get_conf_section('arch-host-vm');
        my @reported_vms = ( $hosts && exists $hosts->{$host} ) ? @{ $hosts->{$host} } : ();
        foreach my $vm (@reported_vms) {
          my $vm_path = FusionComputeDataWrapper::get_filepath_rrd( { 'type' => 'vm', 'uuid' => $vm } );
          if ( defined $vm_path && -f $vm_path ) {
            push @result, { $vm => $labels->{vm}->{$vm} };
          }
        }
      }
    }
    else {
      if ( -d "$vms_path" ) {

        # get all hosts' directories
        opendir( DIR, $vms_path ) || warn( ' cannot open directory : ' . $vms_path . __FILE__ . ':' . __LINE__ ) && return;
        my @vms_dir = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        foreach my $vm (@vms_dir) {
          unless ( -e "$vms_path/$vm" ) { next; }
          $vm =~ s/.rrd//;
          push @result, { $vm => $labels->{vm}->{$vm} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'cluster' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'site' ) {
        my $site           = $params{parent_uuid};
        my $sites          = get_conf_section('arch-site-cluster');
        my @reported_sites = ( $sites && exists $sites->{$site} ) ? @{ $sites->{$site} } : ();
        foreach my $cluster (@reported_sites) {
          my $cluster_path = FusionComputeDataWrapper::get_filepath_rrd( { 'type' => 'cluster', 'uuid' => $cluster } );
          if ( defined $cluster_path && -f $cluster_path ) {
            push @result, { $cluster => $labels->{cluster}->{$cluster} };
          }
        }
      }
    }
    else {
      if ( -d "$clusters_path" ) {

        # get all hosts' directories
        opendir( DIR, $clusters_path ) || warn( ' cannot open directory : ' . $clusters_path . __FILE__ . ':' . __LINE__ ) && return;
        my @clusters_dir = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        foreach my $cluster (@clusters_dir) {
          unless ( -e "$clusters_path/$cluster" ) { next; }
          $cluster =~ s/.rrd//;
          push @result, { $cluster => $labels->{cluster}->{$cluster} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'datastore' ) {
    if ( defined $params{parent_type} && defined $params{parent_uuid} ) {
      if ( $params{parent_type} eq 'site' ) {
        my $site                = $params{parent_uuid};
        my $sites               = get_conf_section('arch-site-datastore');
        my @reported_datastores = ( $sites && exists $sites->{$site} ) ? @{ $sites->{$site} } : ();
        foreach my $datastore (@reported_datastores) {
          my $datastore_path = FusionComputeDataWrapper::get_filepath_rrd( { 'type' => 'datastore', 'uuid' => $datastore } );
          if ( defined $datastore_path && -f $datastore_path ) {
            push @result, { $datastore => $labels->{datastore}->{$datastore} };
          }
        }
      }
    }
    else {
      if ( -d "$datastores_path" ) {

        # get all hosts' directories
        opendir( DIR, $datastores_path ) || warn( ' cannot open directory : ' . $datastores_path . __FILE__ . ':' . __LINE__ ) && return;
        my @datastores_dir = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        foreach my $datastore (@datastores_dir) {
          unless ( -e "$datastores_path/$datastore" ) { next; }
          $datastore =~ s/.rrd//;
          push @result, { $datastore => $labels->{datastore}->{$datastore} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'site' ) {
    my $sites = get_conf_section('arch-site-cluster');
    foreach my $site ( keys %{$sites} ) {
      push @result, { $site => $labels->{site}->{$site} };
    }
  }

  return \@result;
}
################################################################################

sub get_conf_mapping {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$mapping_file" ) ) {
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

sub get_architecture {
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

sub get_specification {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$specification_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_alerts {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$alerts_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_urn {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$urn_file" ) ) {
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

  if ( $section =~ m/label/ ) {
    $dictionary = get_conf_label();
  }
  elsif ( $section =~ m/arch/ ) {
    $dictionary = get_architecture();
  }
  elsif ( $section =~ m/spec/ ) {
    $dictionary = get_specification();
  }
  elsif ( $section =~ m/alerts/ ) {
    $dictionary = get_alerts();
  }
  elsif ( $section =~ m/urn/ ) {
    $dictionary = get_urn();
  }
  elsif ( $section =~ m/mapping/ ) {
    $dictionary = get_conf_mapping();
  }
  else {
    $dictionary = ();
  }

  if ( $section eq 'labels' ) {
    return $dictionary->{label};
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
  elsif ( $section eq 'arch-site-cluster' ) {
    return $dictionary->{architecture}{site_cluster};
  }
  elsif ( $section eq 'arch-cluster-host' ) {
    return $dictionary->{architecture}{cluster_host};
  }
  elsif ( $section eq 'arch-site-vm' ) {
    return $dictionary->{architecture}{site_vm};
  }
  elsif ( $section eq 'arch-cluster-vm' ) {
    return $dictionary->{architecture}{cluster_vm};
  }
  elsif ( $section eq 'arch-host-vm' ) {
    return $dictionary->{architecture}{host_vm};
  }
  elsif ( $section eq 'arch-site-datastore' ) {
    return $dictionary->{architecture}{site_datastore};
  }
  elsif ( $section eq 'spec-host' ) {
    return $dictionary->{specification}{host};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $dictionary->{specification}{vm};
  }
  elsif ( $section eq 'spec-datastore' ) {
    return $dictionary->{specification}{datastore};
  }
  elsif ( $section eq 'alerts' || $section eq 'urn' ) {
    return $dictionary;
  }
  elsif ( $section eq 'events' ) {
    return $dictionary->{events};
  }
  elsif ( $section eq 'health' ) {
    return $dictionary;
  }
  elsif ( $section eq 'mapping' ) {
    return $dictionary->{mapping};
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
  return ( stat($label_file) )[9];
}

################################################################################

1;

