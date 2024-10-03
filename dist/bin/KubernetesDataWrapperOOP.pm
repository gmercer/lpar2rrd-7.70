# KubernetesDataWrapperOOP.pm
# interface for accessing Kubernetes data:

package KubernetesDataWrapperOOP;

use strict;
use warnings;

use Data::Dumper;
use JSON;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Kubernetes";

my $pod_path          = "$wrkdir/Pod";
my $node_path         = "$wrkdir/Node";
my $container_path    = "$wrkdir/Container";
my $network_path      = "$wrkdir/Network";
my $namespace_path    = "$wrkdir/Namespace";
my $conf_file         = "$wrkdir/conf.json";
my $pods_file         = "$wrkdir/pods.json";
my $label_file        = "$wrkdir/labels.json";
my $top_file          = "$wrkdir/top/pod.json";
my $architecture_file = "$wrkdir/architecture.json";

################################################################################

sub new {
  my ( $self, $args ) = @_;

  my $o = {};
  $o->{conf}      = get_conf();
  $o->{labels}    = get_conf('label');
  $o->{arch}      = get_conf('arch');
  $o->{updated}   = ( stat($conf_file) )[9];
  $o->{acl_check} = ( defined $args->{acl_check} ) ? $args->{acl_check} : 0;
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

  if ( $params{item_type} eq 'node' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster        = $params{parent_id};
        my $clusters       = $self->get_conf_section('arch-cluster');
        my @reported_nodes = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $node (@reported_nodes) {
          my $path = $self->get_filepath_rrd( { type => 'node', uuid => $node } );
          if ( defined $path && -f $path ) {
            push @result, { $node => $self->{labels}{label}{node}{$node} };
          }
        }
      }
    }
    else {
      foreach my $node_uuid ( keys %{ $self->{labels}{label}{node} } ) {
        push @result, { $node_uuid => $self->{labels}{label}{node}{$node_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'pod' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster       = $params{parent_id};
        my $clusters      = $self->get_conf_section('arch-pod');
        my @reported_pods = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $pod (@reported_pods) {
          my $path = $self->get_filepath_rrd( { type => 'pod', uuid => $pod } );
          if ( defined $path && -f $path ) {
            push @result, { $pod => $self->{labels}{label}{pod}{$pod} };
          }
        }
      }
      elsif ( $params{parent_type} eq 'namespace' ) {
        my $namespace     = $params{parent_id};
        my $namespaces    = $self->get_conf_section('arch-namespace-pod');
        my @reported_pods = ( $namespaces && exists $namespaces->{$namespace} ) ? @{ $namespaces->{$namespace} } : ();
        foreach my $pod (@reported_pods) {
          my $path = $self->get_filepath_rrd( { type => 'pod', uuid => $pod } );
          if ( defined $path && -f $path ) {
            push @result, { $pod => $self->{labels}{label}{pod}{$pod} };
          }
        }
      }
    }
    else {
      foreach my $pod_uuid ( keys %{ $self->{labels}{label}{pod} } ) {
        push @result, { $pod_uuid => $self->{labels}{label}{pod}{$pod_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'namespace' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster             = $params{parent_id};
        my $clusters            = $self->get_conf_section('arch-namespace');
        my @reported_namespaces = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $namespace (@reported_namespaces) {
          push @result, { $namespace => $self->{labels}{label}{namespace}{$namespace} };
        }
      }
    }
    else {
      foreach my $namespace_uuid ( keys %{ $self->{labels}{label}{namespace} } ) {
        push @result, { $namespace_uuid => $self->{labels}{label}{namespace}{$namespace_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'service' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster           = $params{parent_id};
        my $clusters          = $self->get_conf_section('arch-service');
        my @reported_services = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $service (@reported_services) {
          push @result, { $service => $self->{labels}{label}{service}{$service} };
        }
      }
    }
    else {
      foreach my $service_uuid ( keys %{ $self->{labels}{label}{service} } ) {
        push @result, { $service_uuid => $self->{labels}{label}{service}{$service_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'endpoint' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster            = $params{parent_id};
        my $clusters           = $self->get_conf_section('arch-endpoint');
        my @reported_endpoints = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $endpoint (@reported_endpoints) {
          push @result, { $endpoint => $self->{labels}{label}{endpoint}{$endpoint} };
        }
      }
    }
    else {
      foreach my $endpoint_uuid ( keys %{ $self->{labels}{label}{endpoint} } ) {
        push @result, { $endpoint_uuid => $self->{labels}{label}{endpoint}{$endpoint_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'network' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'pod' ) {
        opendir( DH, "${network_path}/$params{parent_id}" ) || die "Could not open ${network_path}/$params{parent_id} for reading '$!'\n";
        my @files = grep /.*.rrd/, readdir DH;
        foreach my $file ( sort @files ) {
          my @splits = split /\./, $file;
          push @result, { $splits[0] => $splits[0] };
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'container' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'pod' ) {
        my $pod                 = $params{parent_id};
        my $pods                = $self->get_conf_section('arch-container');
        my @reported_containers = ( $pods && exists $pods->{$pod} ) ? @{ $pods->{$pod} } : ();
        foreach my $container (@reported_containers) {
          my $path = $self->get_filepath_rrd( { type => 'container', uuid => $container } );
          if ( defined $path && -f $path ) {
            push @result, { $container => $self->{labels}{label}{container}{$container} };
          }
        }
      }
      elsif ( $params{parent_type} eq 'cluster' ) {
        my $cluster  = $params{parent_id};
        my $clusters = $self->get_conf_section('arch-pod');

        my @reported_pods = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $pod (@reported_pods) {
          my $pods                = $self->get_conf_section('arch-container');
          my @reported_containers = ( $pods && exists $pods->{$pod} ) ? @{ $pods->{$pod} } : ();
          foreach my $container (@reported_containers) {
            my $path = $self->get_filepath_rrd( { type => 'container', uuid => $container } );
            if ( defined $path && -f $path ) {
              push @result, { $container => $self->{labels}{label}{container}{$container} };
            }
          }
        }
      }
    }
    else {
      foreach my $container_uuid ( keys %{ $self->{labels}{label}{container} } ) {
        push @result, { $container_uuid => $self->{labels}{label}{container}{$container_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'cluster' ) {
    my $clusters = $self->get_conf_section('arch-cluster');
    foreach my $cluster ( keys %{$clusters} ) {
      push @result, { $cluster => $self->{labels}{label}{cluster}{$cluster} };
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

  # params: { type => '(pod|node|container|namespace|network)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $self   = shift;
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'pod' ) {
    $filepath = "${pod_path}/$uuid.rrd";
  }
  elsif ( $type eq 'node' ) {
    $filepath = "${node_path}/$uuid.rrd";
  }
  elsif ( $type eq 'container' ) {
    $filepath = "${container_path}/$uuid.rrd";
  }
  elsif ( $type eq 'namespace' ) {
    $filepath = "${namespace_path}/$uuid.rrd";
  }
  elsif ( $type eq 'network' && defined $params->{parent} ) {
    $filepath = "${network_path}/$params->{parent}/$uuid.rrd";
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

sub get_conf_section {
  my $self    = shift;
  my $section = shift;

  if ( $section eq 'labels' ) {
    return $self->{labels}{label};
  }
  elsif ( $section eq 'arch' ) {
    return $self->{arch}{architecture};
  }
  elsif ( $section eq 'arch-cluster' ) {
    return $self->{arch}{architecture}{cluster_node};
  }
  elsif ( $section eq 'arch-pod' ) {
    return $self->{arch}{architecture}{cluster_pod};
  }
  elsif ( $section eq 'arch-namespace' ) {
    return $self->{arch}{architecture}{cluster_namespace};
  }
  elsif ( $section eq 'arch-namespace-pod' ) {
    return $self->{arch}{architecture}{namespace_pod};
  }
  elsif ( $section eq 'arch-service' ) {
    return $self->{arch}{architecture}{cluster_service};
  }
  elsif ( $section eq 'arch-endpoint' ) {
    return $self->{arch}{architecture}{cluster_endpoint};
  }
  elsif ( $section eq 'arch-container' ) {
    return $self->{arch}{architecture}{pod_container};
  }
  elsif ( $section eq 'spec-pod' ) {
    return $self->{conf}{specification}{pod};
  }
  elsif ( $section eq 'spec-node' ) {
    return $self->{conf}{specification}{node};
  }
  elsif ( $section eq 'spec-service' ) {
    return $self->{conf}{specification}{service};
  }
  elsif ( $section eq 'spec-endpoint' ) {
    return $self->{conf}{specification}{endpoint};
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
  my $self   = shift;
  my $type   = shift;
  my $uuid   = shift;
  my $labels = $self->get_labels();

  return exists $labels->{$type}{$uuid} ? $labels->{$type}{$uuid} : $uuid;
}

sub get_pod {
  my $self = shift;
  my $uuid = shift;
  my $pods = get_conf('pods');

  return exists $pods->{$uuid} ? $pods->{$uuid} : ();
}

sub get_service {
  my $self     = shift;
  my $uuid     = shift;
  my $services = $self->get_conf_section('spec-service');

  return exists $services->{$uuid} ? $services->{$uuid} : ();
}

sub get_conf_update_time {
  my $self = shift;
  return $self->{updated};
}

sub is_granted {
  my $self = shift;
  my $uuid = shift;

  if ( $self->{aclx} ) {
    return $self->{aclx}->isGranted( { hw_type => 'KUBERNETES', item_id => $uuid, match => 'granted' } );
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
  elsif ( $type =~ m/pods/ ) {
    $path = $pods_file;
  }
  elsif ( $type =~ m/top/ ) {
    $path = $top_file;
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
