# OpenshiftDataWrapperJSON.pm
# interface for accessing Openshift data:

package OpenshiftDataWrapperJSON;

use strict;
use warnings;

use Data::Dumper;
use JSON;

require OpenshiftDataWrapper;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data/Openshift";

my $node_path         = "$wrkdir/Node";
my $network_dir       = "$wrkdir/Network";
my $conf_file         = "$wrkdir/conf.json";
my $pods_file         = "$wrkdir/pods.json";
my $top_file          = "$wrkdir/top/pod.json";
my $openshift_file    = "$wrkdir/openshift.json";
my $label_file        = "$wrkdir/labels.json";
my $architecture_file = "$wrkdir/architecture.json";

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
        my $clusters       = get_conf_section('arch-cluster');
        my @reported_nodes = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $node (@reported_nodes) {
          if ( defined $params{menu} ) {
            push @result, { $node => $labels->{node}->{$node} };
          }
          elsif ( defined OpenshiftDataWrapper::get_filepath_rrd_node($node) && -f OpenshiftDataWrapper::get_filepath_rrd_node($node) ) {
            push @result, { $node => $labels->{node}->{$node} };
          }
        }
      }
    }
    else {
      foreach my $node_uuid ( keys %{ $labels->{node} } ) {
        push @result, $node_uuid;
      }
    }
  }
  elsif ( $params{item_type} eq 'pod' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster       = $params{parent_id};
        my $clusters      = get_conf_section('arch-pod');
        my @reported_pods = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $pod (@reported_pods) {
          if ( defined $params{menu} ) {
            push @result, { $pod => $labels->{pod}->{$pod} };
          }
          elsif ( defined OpenshiftDataWrapper::get_filepath_rrd_pod($pod) && -f OpenshiftDataWrapper::get_filepath_rrd_pod($pod) ) {
            push @result, { $pod => $labels->{pod}->{$pod} };
          }
        }
      }
      elsif ( $params{parent_type} eq 'namespace' && defined $params{cluster} ) {
        my $cluster       = $params{cluster};
        my $namespace     = $params{parent_id};
        my $namespaces    = get_conf_section('arch-namespace');
        my @reported_pods = defined $namespaces->{$cluster}->{$namespace} ? $namespaces->{$cluster}->{$namespace} : ();
        foreach my $pods (@reported_pods) {
          foreach my $pod ( @{$pods} ) {
            push @result, { $pod => $labels->{pod}->{$pod} };
          }
        }
      }
      elsif ( $params{parent_type} eq 'project' ) {
        my $project       = $params{parent_id};
        my $projects      = get_conf_section('project');
        my $namespaces    = get_conf_section('arch-namespace');
        my $namespace     = $projects->{$project}->{name};
        my $cluster       = $projects->{$project}->{cluster};
        my @reported_pods = defined $namespaces->{$cluster}->{$namespace} ? $namespaces->{$cluster}->{$namespace} : ();
        foreach my $pods (@reported_pods) {
          foreach my $pod ( @{$pods} ) {
            push @result, { $pod => $labels->{pod}->{$pod} };
          }
        }
      }
      elsif ( $params{parent_type} eq 'namespace' ) {
        my $namespace  = $params{parent_id};
        my $namespaces = get_conf_section('arch-namespace');
        foreach my $cluster ( keys %{$namespaces} ) {
          foreach my $pod ( @{ $namespaces->{$cluster}->{$namespace} } ) {
            push @result, { $pod => $labels->{pod}->{$pod} };
          }
        }
      }
    }
    else {
      foreach my $pod_uuid ( keys %{ $labels->{pod} } ) {
        push @result, { $pod_uuid => $labels->{pod}->{$pod_uuid} };
      }
    }
  }
  elsif ( $params{item_type} eq 'project' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster  = $params{parent_id};
        my $projects = get_conf_section('project');
        foreach my $project ( keys %{$projects} ) {
          if ( $projects->{$project}{cluster} eq $cluster ) {
            push @result, { $project => $projects->{$project}->{name} };
          }
        }
      }
    }
  }
  elsif ( $params{item_type} eq 'service' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster           = $params{parent_id};
        my $clusters          = get_conf_section('arch-service');
        my @reported_services = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $service (@reported_services) {
          push @result, { $service => $labels->{service}->{$service} };
        }
      }
    }
    else {
      foreach my $service_uuid ( keys %{ $labels->{service} } ) {
        push @result, $service_uuid;
      }
    }
  }
  elsif ( $params{item_type} eq 'endpoint' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'cluster' ) {
        my $cluster            = $params{parent_id};
        my $clusters           = get_conf_section('arch-endpoint');
        my @reported_endpoints = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $endpoint (@reported_endpoints) {
          push @result, { $endpoint => $labels->{endpoint}->{$endpoint} };
        }
      }
    }
    else {
      foreach my $endpoint_uuid ( keys %{ $labels->{endpoint} } ) {
        push @result, $endpoint_uuid;
      }
    }
  }
  elsif ( $params{item_type} eq 'network' ) {
    if ( defined $params{parent_type} && defined $params{parent_id} ) {
      if ( $params{parent_type} eq 'pod' ) {
        opendir( DH, "$network_dir/$params{parent_id}" ) || die "Could not open $network_dir/$params{parent_id} for reading '$!'\n";
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
        my $pods                = get_conf_section('arch-container');
        my @reported_containers = ( $pods && exists $pods->{$pod} ) ? @{ $pods->{$pod} } : ();
        foreach my $container (@reported_containers) {
          if ( defined $params{menu} ) {
            push @result, { $container => $labels->{container}->{$container} };
          }
          elsif ( defined OpenshiftDataWrapper::get_filepath_rrd_container($container) && -f OpenshiftDataWrapper::get_filepath_rrd_container($container) ) {
            push @result, { $container => $labels->{container}->{$container} };
          }
        }
      }
      elsif ( $params{parent_type} eq 'cluster' ) {
        my $cluster  = $params{parent_id};
        my $clusters = get_conf_section('arch-pod');

        my @reported_pods = ( $clusters && exists $clusters->{$cluster} ) ? @{ $clusters->{$cluster} } : ();
        foreach my $pod (@reported_pods) {
          my $pods                = get_conf_section('arch-container');
          my @reported_containers = ( $pods && exists $pods->{$pod} ) ? @{ $pods->{$pod} } : ();
          foreach my $container (@reported_containers) {
            if ( defined $params{menu} ) {
              push @result, { $container => $labels->{container}->{$container} };
            }
            elsif ( defined OpenshiftDataWrapper::get_filepath_rrd_container($container) && -f OpenshiftDataWrapper::get_filepath_rrd_container($container) ) {
              push @result, { $container => $labels->{container}->{$container} };
            }
          }
        }
      }
    }
    else {
      foreach my $container_uuid ( keys %{ $labels->{container} } ) {
        push @result, { $container_uuid => $labels->{container}->{$container_uuid} };
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

sub get_all_containers {
  my %data;
  my $labels = get_labels();
  my $pods   = get_conf_section('arch-container');
  foreach my $pod ( keys %{$pods} ) {
    foreach my $container ( @{ $pods->{$pod} } ) {

      #if ( defined OpenshiftDataWrapper::get_filepath_rrd_container($container) && -f OpenshiftDataWrapper::get_filepath_rrd_container($container) ) {
      $data{$pod}{$container} = $labels->{container}->{$container};

      #}
    }
  }

  return \%data;
}

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

sub get_conf_openshift {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$openshift_file" ) ) {
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
  elsif ( $section =~ m/project/ || $section =~ m/infrastructure/ ) {
    $dictionary = get_conf_openshift();
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
  elsif ( $section eq 'project' ) {
    return $dictionary->{project};
  }
  elsif ( $section eq 'arch-cluster' ) {
    return $dictionary->{architecture}{cluster_node};
  }
  elsif ( $section eq 'arch-pod' ) {
    return $dictionary->{architecture}{cluster_pod};
  }
  elsif ( $section eq 'arch-service' ) {
    return $dictionary->{architecture}{cluster_service};
  }
  elsif ( $section eq 'arch-endpoint' ) {
    return $dictionary->{architecture}{cluster_endpoint};
  }
  elsif ( $section eq 'arch-container' ) {
    return $dictionary->{architecture}{pod_container};
  }
  elsif ( $section eq 'arch-namespace' ) {
    return $dictionary->{architecture}{cluster_namespace_pod};
  }
  elsif ( $section eq 'spec-pod' ) {
    return $dictionary->{specification}{pod};
  }
  elsif ( $section eq 'spec-node' ) {
    return $dictionary->{specification}{node};
  }
  elsif ( $section eq 'spec-service' ) {
    return $dictionary->{specification}{service};
  }
  elsif ( $section eq 'spec-infrastructure' ) {
    return $dictionary->{infrastructure};
  }
  elsif ( $section eq 'spec-endpoint' ) {
    return $dictionary->{specification}{endpoint};
  }
  else {
    return ();
  }

}

sub get_labels {
  return get_conf_section('labels');
}

sub get_pods {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$pods_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_top {
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$top_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

sub get_label {
  my $type   = shift;
  my $uuid   = shift;
  my $labels = get_labels();

  return exists $labels->{$type}{$uuid} ? $labels->{$type}{$uuid} : $uuid;
}

sub get_pod {
  my $uuid = shift;
  my $pods = get_pods();

  return exists $pods->{$uuid} ? $pods->{$uuid} : ();
}

sub get_service {
  my $uuid     = shift;
  my $services = get_conf_section('spec-service');

  return exists $services->{$uuid} ? $services->{$uuid} : ();
}

sub get_conf_update_time {
  return ( stat($conf_file) )[9];
}

################################################################################

1;
