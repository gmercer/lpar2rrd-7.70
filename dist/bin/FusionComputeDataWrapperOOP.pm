# FusionComputeDataWrapperOOP.pm
# interface for accessing FusionCompute data:

package FusionComputeDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

# TODO introduce toggle between JSON and SQLite backends
my $use_sql = 0;    # defined $ENV{XORMON};

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

sub new {
  my ( $self, $args ) = @_;

  my $o = {};
  $o->{configuration} = get_conf();
  $o->{labels}        = ( defined $args->{conf_labels} && $args->{conf_labels} ) ? get_conf('label') : {};
  $o->{architecture}  = ( defined $args->{conf_arch} && $args->{conf_arch} ) ? get_conf('arch') : {};
  $o->{specification} = ( defined $args->{conf_spec} && $args->{conf_spec} ) ? get_conf('spec') : {};
  $o->{alerts}        = ( defined $args->{conf_alerts} && $args->{conf_alerts} ) ? get_conf('alert') : {};
  $o->{urn}           = ( defined $args->{conf_urns} && $args->{conf_alerts} ) ? get_conf('urn') : {};
  $o->{mapping}       = ( defined $args->{conf_mapping} && $args->{conf_mapping} ) ? get_conf('mapping') : {};
  $o->{updated}       = ( stat($label_file) )[9];
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
        my $cluster        = $params{parent_uuid};
        my $clusters       = $self->get_conf_section('arch-cluster-host');
        my @reported_hosts = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
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
        my $clusters     = $self->get_conf_section('arch-cluster-vm');
        my @reported_vms = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $vm (@reported_vms) {
          my $vm_path = $self->get_filepath_rrd( { 'type' => 'vm', 'uuid' => $vm } );
          if ( defined $vm_path && -f $vm_path ) {
            push @result, { $vm => $labels->{vm}->{$vm} };
          }
        }
      }
      elsif ( $params{parent_type} eq 'host' ) {
        my $host         = $params{parent_uuid};
        my $hosts        = $self->get_conf_section('arch-host-vm');
        my @reported_vms = ( $hosts && exists $hosts->{$host} ) ? @{ $hosts->{$host} } : ();
        foreach my $vm (@reported_vms) {
          my $vm_path = $self->get_filepath_rrd( { 'type' => 'vm', 'uuid' => $vm } );
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
        my $sites          = $self->get_conf_section('arch-site-cluster');
        my @reported_sites = ( $sites && exists $sites->{$site} ) ? @{ $sites->{$site} } : ();
        foreach my $cluster (@reported_sites) {
          my $cluster_path = $self->get_filepath_rrd( { 'type' => 'cluster', 'uuid' => $cluster } );
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
        my $sites               = $self->get_conf_section('arch-site-datastore');
        my @reported_datastores = ( $sites && exists $sites->{$site} ) ? @{ $sites->{$site} } : ();
        foreach my $datastore (@reported_datastores) {
          my $datastore_path = $self->get_filepath_rrd( { 'type' => 'datastore', 'uuid' => $datastore } );
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
          unless ( -e "${datastores_path}/$datastore" ) { next; }
          $datastore =~ s/.rrd//;
          push @result, { $datastore => $labels->{datastore}->{$datastore} };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'site' ) {
    my $sites = $self->get_conf_section('arch-site-cluster');
    foreach my $site ( keys %{$sites} ) {
      push @result, { $site => $labels->{site}->{$site} };
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
    $filepath = "${hosts_path}/$uuid.rrd";
  }
  elsif ( $type eq 'cluster' ) {
    $filepath = "${clusters_path}/$uuid.rrd";
  }
  elsif ( $type eq 'datastore' ) {
    $filepath = "${datastores_path}/$uuid.rrd";
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
  elsif ( $section eq 'arch-host-vm' ) {
    return $self->{architecture}{architecture}{host_vm};
  }
  elsif ( $section eq 'arch-cluster-vm' ) {
    return $self->{architecture}{architecture}{cluster_vm};
  }
  elsif ( $section eq 'arch-site-cluster' ) {
    return $self->{architecture}{architecture}{site_cluster};
  }
  elsif ( $section eq 'arch-cluster-host' ) {
    return $self->{architecture}{architecture}{cluster_host};
  }
  elsif ( $section eq 'arch-site-vm' ) {
    return $self->{architecture}{architecture}{site_vm};
  }
  elsif ( $section eq 'arch-cluster-vm' ) {
    return $self->{architecture}{architecture}{cluster_vm};
  }
  elsif ( $section eq 'arch-host-vm' ) {
    return $self->{architecture}{architecture}{host_vm};
  }
  elsif ( $section eq 'arch-site-datastore' ) {
    return $self->{architecture}{architecture}{site_datastore};
  }
  elsif ( $section eq 'spec-host' ) {
    return $self->{specification}{specification}{host};
  }
  elsif ( $section eq 'spec-vm' ) {
    return $self->{specification}{specification}{vm};
  }
  elsif ( $section eq 'spec-datastore' ) {
    return $self->{specification}{specification}{datastores};
  }
  elsif ( $section eq 'alerts' || $section eq 'urn' ) {
    return $self->{alerts};
  }
  elsif ( $section eq 'events' ) {
    return $self->{events};
  }
  elsif ( $section eq 'health' ) {
    return $self->{health};
  }
  elsif ( $section eq 'mapping' ) {
    return $self->{mapping}{mapping};
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
    return $self->{aclx}->isGranted( { hw_type => 'FUSIONCOMPUTE', item_id => $uuid, match => 'granted' } );
  }

  return;
}

################################################################################

sub get_conf {
  my $type = shift || 'label';

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
    $path = $alerts_file;
  }
  elsif ( $type =~ m/urn/ ) {
    $path = $urn_file;
  }
  elsif ( $type =~ m/mapping/ ) {
    $path = $mapping_file;
  }
  else {
    $path = $label_file;
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
