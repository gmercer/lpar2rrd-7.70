package Kubernetes;

use strict;
use warnings;

use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;
use Scalar::Util qw(looks_like_number);

my @cadvisor_metrics = ( 'container_fs_usage_bytes', 'container_fs_reads_bytes_total', 'container_fs_writes_bytes_total', 'container_fs_reads_total', 'container_fs_writes_total', 'container_fs_read_seconds_total', 'container_fs_write_seconds_total', 'container_network_receive_bytes_total', 'container_network_receive_packets_total', 'container_network_transmit_bytes_total', 'container_network_transmit_packets_total' );

my $inputdir  = $ENV{INPUTDIR};
my $data_path = "$inputdir/data/Kubernetes";
my $top_path  = "$data_path/top";

sub new {
  my ( $self, $cluster, $endpoint, $token, $protocol, $uuid, $container, $namespaces, $monitor ) = @_;

  my $o = {};
  $o->{cluster}  = $cluster;
  $o->{endpoint} = $endpoint;
  $o->{token}    = $token;
  $o->{protocol} = $protocol;
  $o->{uuid}     = $uuid;

  if ( !defined $namespaces ) {
    $o->{namespaces} = ();
  }
  else {
    $o->{namespaces} = $namespaces;
  }

  if ( !defined $container ) {
    $o->{container} = 0;
  }
  else {
    $o->{container} = $container;
  }

  if ( !defined $monitor ) {
    if ($o->{container} == 1) {
      $o->{monitor} = 2;
    } else {
      $o->{monitor} = 3;
    }
  }
  else {
    $o->{monitor} = $monitor;
  }

  bless $o, $self;

  return $o;
}

sub apiTest {
  my ($self) = @_;

  #nodes
  my $url   = $self->{endpoint} . "/api/v1/nodes";
  my $nodes = $self->apiRequestWithoutDie($url);

  return $nodes;
}

sub metricResolution {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/apis/metrics.k8s.io/v1beta1/pods";
  my $pods = $self->apiRequest($url);

  my %data;

  my $resolution = 30;
  for ( @{ $pods->{items} } ) {
    my $pod = $_;

    if ( defined $pod->{window} ) {
      print "Metric resolution pods: $pod->{window}\n";
      if ( substr( $pod->{window}, -1 ) eq "s" ) {
        if ( $pod->{window} =~ m/m/ ) {
          my @metrics    = split /m/, $pod->{window};
          my $resolution = $metrics[1];
          chop($resolution);
          $metrics[0]  = $metrics[0] * 1;
          $resolution  = $resolution * 1;
          $resolution  = $resolution + ( $metrics[0] * 60 );
          $data{"pod"} = $resolution;
          last;
        }
        else {
          $resolution = $pod->{window};
          chop($resolution);
          $data{"pod"} = $resolution;
          last;
        }
      }
      elsif ( substr( $pod->{window}, -1 ) eq "m" ) {
        $resolution = $pod->{window};
        chop($resolution);
        $resolution = $resolution * 60;
        $data{"pod"} = $resolution;
        last;
      }
    }
  }

  $url = $self->{endpoint} . "/apis/metrics.k8s.io/v1beta1/nodes";
  my $nodes = $self->apiRequest($url);

  for ( @{ $nodes->{items} } ) {
    my $node = $_;

    if ( defined $node->{window} ) {
      print "Metric resolution nodes: $node->{window}\n";
      if ( substr( $node->{window}, -1 ) eq "s" ) {
        if ( $node->{window} =~ m/m/ ) {
          my @metrics    = split /m/, $node->{window};
          my $resolution = $metrics[1];
          chop($resolution);
          $metrics[0]   = $metrics[0] * 1;
          $resolution   = $resolution * 1;
          $resolution   = $resolution + ( $metrics[0] * 60 );
          $data{"node"} = $resolution;
          last;
        }
        else {
          $resolution = $node->{window};
          chop($resolution);
          $data{"node"} = $resolution;
          last;
        }
      }
      elsif ( substr( $node->{window}, -1 ) eq "m" ) {
        $resolution = $node->{window};
        chop($resolution);
        $resolution = $resolution * 60;
        $data{"node"} = $resolution;
        last;
      }
    }
  }

  Kubernetes::log("node resolution: " . $data{'node'}, $self->{cluster});

  return \%data;
}

sub getNamespaces {
  my ($self) = @_;

  #namespaces
  my $url        = $self->{endpoint} . "/api/v1/namespaces";
  my $namespaces = $self->apiRequest($url);
  my @namespaces_array;

  for ( @{ $namespaces->{items} } ) {
    my $namespace = $_;
    push( @namespaces_array, $namespace->{metadata}->{name} );
  }

  return \@namespaces_array;
}

sub checkNamespace {
  my ( $self, $namespace ) = @_;

  if ( defined $self->{namespaces} && scalar @{ $self->{namespaces} } >= 1 ) {
    my $result = 0;
    for my $ns ( @{ $self->{namespaces} } ) {
      if ( $ns eq $namespace ) {
        $result = 1;
      }
    }
    return $result;
  }
  else {
    return 0;
  }
}

sub getConfiguration {
  my ($self) = @_;

  my %tmp;
  my %data;
  $data{label}{cluster}{ $self->{uuid} } = $self->{cluster};

  #nodes
  my $url   = $self->{endpoint} . "/api/v1/nodes";
  my $nodes = $self->apiRequest($url);

  #print Dumper($nodes);

  for ( @{ $nodes->{items} } ) {
    my $node = $_;

    $data{label}{node}{ $node->{metadata}->{uid} }          = $node->{metadata}->{name};
    $data{label}{name_to_uuid}{ $node->{metadata}->{name} } = $node->{metadata}->{uid};

    $data{specification}{node}{ $node->{metadata}->{uid} }{name}        = $node->{metadata}->{name};
    $data{specification}{node}{ $node->{metadata}->{uid} }{cluster}     = $self->{cluster};
    $data{specification}{node}{ $node->{metadata}->{uid} }{capacity}    = $node->{status}->{capacity};
    $data{specification}{node}{ $node->{metadata}->{uid} }{allocatable} = $node->{status}->{allocatable};
    $data{specification}{node}{ $node->{metadata}->{uid} }{addresses}   = $node->{status}->{addresses};
    $data{specification}{node}{ $node->{metadata}->{uid} }{nodeInfo}    = $node->{status}->{nodeInfo};

    if ( !defined $data{architecture}{cluster_node}{ $self->{uuid} } ) {
      $data{architecture}{cluster_node}{ $self->{uuid} }[0] = $node->{metadata}->{uid};
    }
    else {
      push( @{ $data{architecture}{cluster_node}{ $self->{uuid} } }, $node->{metadata}->{uid} );
    }

  }

  my $c = scalar @{ $nodes->{items} };
  Kubernetes::log("nodes found: $c", $self->{cluster});

  undef $nodes;

  #namespaces
  $url = $self->{endpoint} . "/api/v1/namespaces";
  my $namespaces = $self->apiRequest($url);

  for ( @{ $namespaces->{items} } ) {
    my $namespace = $_;

    $data{label}{namespace}{ $namespace->{metadata}->{uid} } = $namespace->{metadata}->{name};

    if ( !defined $data{architecture}{cluster_namespace}{ $self->{uuid} } ) {
      $data{architecture}{cluster_namespace}{ $self->{uuid} }[0] = $namespace->{metadata}->{uid};
    }
    else {
      push( @{ $data{architecture}{cluster_namespace}{ $self->{uuid} } }, $namespace->{metadata}->{uid} );
    }

    $tmp{namespace}{ $namespace->{metadata}->{name} } = $namespace->{metadata}->{uid};

  }

  $c = scalar @{ $namespaces->{items} };
  Kubernetes::log("namespaces found: $c", $self->{cluster});
  
  undef($namespaces);

  #pods
  if ((!defined $self->{monitor}) || ( defined $self->{monitor} && "$self->{monitor}" ne "1")) {  
    if ( defined $self->{namespaces} && scalar @{$self->{namespaces}} >= 1) {
      $url = $self->{endpoint} . "/api/v1/pods";
      my $pods = $self->apiRequest($url);

      for ( @{ $pods->{items} } ) {
        my $pod = $_;

        if ( defined $self->{namespaces} && $self->checkNamespace( $pod->{metadata}->{namespace} ) eq "0" ) {
          next;
        }

        $data{label}{pod}{ $pod->{metadata}->{uid} }           = $pod->{metadata}->{name};
        $data{label}{name_to_uuid}{ $pod->{metadata}->{name} } = $pod->{metadata}->{uid};

        $data{specification}{pod}{ $pod->{metadata}->{uid} }{name}               = $pod->{metadata}->{name};
        $data{specification}{pod}{ $pod->{metadata}->{uid} }{cluster}            = $self->{cluster};
        $data{specification}{pod}{ $pod->{metadata}->{uid} }{'k8s-app'}{name}    = $pod->{metadata}->{labels}->{'k8s-app'};
        $data{specification}{pod}{ $pod->{metadata}->{uid} }{'k8s-app'}{version} = $pod->{metadata}->{labels}->{version};
        $data{specification}{pod}{ $pod->{metadata}->{uid} }{status}             = $pod->{status}->{phase};
        $data{specification}{pod}{ $pod->{metadata}->{uid} }{hostIP}             = $pod->{status}->{hostIP};
        $data{specification}{pod}{ $pod->{metadata}->{uid} }{podIP}              = $pod->{status}->{podIP};
        $data{specification}{pod}{ $pod->{metadata}->{uid} }{startTime}          = $pod->{status}->{startTime};

        if ( !defined $data{architecture}{cluster_pod}{ $self->{uuid} } ) {
          $data{architecture}{cluster_pod}{ $self->{uuid} }[0] = $pod->{metadata}->{uid};
        }
        else {
          push( @{ $data{architecture}{cluster_pod}{ $self->{uuid} } }, $pod->{metadata}->{uid} );
        }

        if ( defined $tmp{namespace}{ $pod->{metadata}->{namespace} } ) {
          if ( !defined $data{architecture}{namespace_pod}{ $tmp{namespace}{ $pod->{metadata}->{namespace} } } ) {
            $data{architecture}{namespace_pod}{ $tmp{namespace}{ $pod->{metadata}->{namespace} } }[0] = $pod->{metadata}->{uid};
          }
          else {
            push( @{ $data{architecture}{namespace_pod}{ $tmp{namespace}{ $pod->{metadata}->{namespace} } } }, $pod->{metadata}->{uid} );
          } 
        }

        if ( defined $self->{container} && "$self->{container}" ne "1" ) {
          for ( @{ $pod->{spec}->{containers} } ) {
            my $container = $_;

            my $new_name = "$pod->{metadata}->{name}--$container->{name}";

            $data{label}{container}{$new_name} = $container->{name};

            if ( !defined $data{architecture}{pod_container}{ $pod->{metadata}->{uid} } ) {
              $data{architecture}{pod_container}{ $pod->{metadata}->{uid} }[0] = $new_name;
            }
            else {
              push( @{ $data{architecture}{pod_container}{ $pod->{metadata}->{uid} } }, $new_name );
            }
          }
        }
      }

      $c = scalar @{ $pods->{items} };
      Kubernetes::log("pods found: $c", $self->{cluster});

      undef $pods;
    }
  }

  #services
  #$url = $self->{endpoint} . "/api/v1/services";
  #my $services = $self->apiRequest($url);
  #
  #for ( @{ $services->{items} } ) {
  #  my $service = $_;
  #
  #  $data{label}{service}{ $service->{metadata}->{uid} }                    = $service->{metadata}->{name};
  #  $data{specification}{service}{ $service->{metadata}->{uid} }{ports}     = $service->{spec}->{ports};
  #  $data{specification}{service}{ $service->{metadata}->{uid} }{labels}    = $service->{metadata}->{labels};
  #  $data{specification}{service}{ $service->{metadata}->{uid} }{uid}       = $service->{metadata}->{uid};
  #  $data{specification}{service}{ $service->{metadata}->{uid} }{name}      = $service->{metadata}->{name};
  #  $data{specification}{service}{ $service->{metadata}->{uid} }{namespace} = $service->{metadata}->{namespace};
  #  $data{specification}{service}{ $service->{metadata}->{uid} }{clusterIP} = $service->{spec}->{clusterIP};
  #
  #  if ( !defined $data{architecture}{cluster_service}{ $self->{uuid} } ) {
  #    $data{architecture}{cluster_service}{ $self->{uuid} }[0] = $service->{metadata}->{uid};
  #  }
  #  else {
  #    push( @{ $data{architecture}{cluster_service}{ $self->{uuid} } }, $service->{metadata}->{uid} );
  #  }
  #
  #}
  #undef($services);

  #endpoints
  #$url = $self->{endpoint} . "/api/v1/endpoints";
  #my $endpoints = $self->apiRequest($url);
  #for ( @{ $endpoints->{items} } ) {
  #  my $endpoint = $_;
  #
  #  $data{label}{endpoint}{ $endpoint->{metadata}->{uid} }         = $endpoint->{metadata}->{name};
  #  $data{specification}{endpoint}{ $endpoint->{metadata}->{uid} } = defined $endpoint->{subsets} ? $endpoint->{subsets} : ();
  #
  #  if ( !defined $data{architecture}{cluster_endpoint}{ $self->{uuid} } ) {
  #    $data{architecture}{cluster_endpoint}{ $self->{uuid} }[0] = $endpoint->{metadata}->{uid};
  #  }
  #  else {
  #    push( @{ $data{architecture}{cluster_endpoint}{ $self->{uuid} } }, $endpoint->{metadata}->{uid} );
  #  }
  #}

  return \%data;

}

sub getMetricsData {
  my ( $self, $resolution ) = @_;

  if ( !defined $resolution ) { $resolution = 30; }

  my %data;
  my %tmp_data;
  my %namespace;

  #namespaces
  my $url        = $self->{endpoint} . "/api/v1/namespaces";
  my $namespaces = $self->apiRequest($url);
  if (!defined $namespaces) { return () };

  for ( @{ $namespaces->{items} } ) {
    my $namespace = $_;
    $namespace{'namespace'}{ $namespace->{metadata}->{name} } = $namespace->{metadata}->{uid};
  }

  #nodes
  $url = $self->{endpoint} . "/api/v1/nodes";
  my $nodes = $self->apiRequest($url);
  for ( @{ $nodes->{items} } ) {
    my $node = $_;

    $tmp_data{ $node->{metadata}->{name} }{cpu_allocatable}    = transform( $node->{status}->{allocatable}->{cpu} );
    $tmp_data{ $node->{metadata}->{name} }{cpu_capacity}       = transform( $node->{status}->{capacity}->{cpu} );
    $tmp_data{ $node->{metadata}->{name} }{memory_allocatable} = transform( $node->{status}->{allocatable}->{memory} );
    $tmp_data{ $node->{metadata}->{name} }{memory_capacity}    = transform( $node->{status}->{capacity}->{memory} );
    $tmp_data{ $node->{metadata}->{name} }{pods_allocatable}   = transform( $node->{status}->{allocatable}->{pods} );
    $tmp_data{ $node->{metadata}->{name} }{pods_capacity}      = transform( $node->{status}->{capacity}->{pods} );
  }

  #pods count
  my $pods;
  if ( defined $self->{namespaces} && scalar @{$self->{namespaces}} >= 1) {
    $url = $self->{endpoint} . "/api/v1/pods";
    $pods = $self->apiRequest($url);

    for ( @{ $pods->{items} } ) {
      my $pod = $_;

      if ( defined $self->{namespaces} && $self->checkNamespace( $pod->{metadata}->{namespace} ) eq "0" ) {
        next;
      }

      $namespace{'pod'}{ $pod->{metadata}->{name} } = $pod->{metadata}->{namespace};
      $data{pod}{ $pod->{metadata}->{name} }{metadata}{node} = $pod->{spec}->{nodeName};

      if ( defined $pod->{spec}->{nodeName} ) {
        if ( !defined $tmp_data{ $pod->{spec}->{nodeName} }{pods} ) {
          $tmp_data{ $pod->{spec}->{nodeName} }{pods} = 1;
        }
        else {
          $tmp_data{ $pod->{spec}->{nodeName} }{pods} += 1;
        }
      }

      for ( @{ $pod->{spec}->{containers} } ) {
        my $container = $_;
        $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_request}    = defined $container->{resources}->{requests}->{cpu}    ? transform( $container->{resources}->{requests}->{cpu} )    : 0;
        $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_request} = defined $container->{resources}->{requests}->{memory} ? transform( $container->{resources}->{requests}->{memory} ) : 0;
        $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_limit}      = defined $container->{resources}->{limits}->{cpu}      ? transform( $container->{resources}->{limits}->{cpu} )      : 0;
        $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_limit}   = defined $container->{resources}->{limits}->{memory}   ? transform( $container->{resources}->{limits}->{memory} )   : 0;
      }

    }
  }

  #nodes metrics
  $url   = $self->{endpoint} . "/apis/metrics.k8s.io/v1beta1/nodes";
  $nodes = $self->apiRequest($url);

  for ( @{ $nodes->{items} } ) {
    my $node = $_;

    my $pretty_time = str2time( $node->{timestamp} );
    $pretty_time = int($pretty_time);

    $data{node}{ $node->{metadata}->{name} }{$pretty_time}{cpu}                = transform( $node->{usage}->{cpu} );
    $data{node}{ $node->{metadata}->{name} }{$pretty_time}{memory}             = transform( $node->{usage}->{memory} );
    $data{node}{ $node->{metadata}->{name} }{$pretty_time}{cpu_allocatable}    = $tmp_data{ $node->{metadata}->{name} }{cpu_allocatable};
    $data{node}{ $node->{metadata}->{name} }{$pretty_time}{cpu_capacity}       = $tmp_data{ $node->{metadata}->{name} }{cpu_capacity};
    $data{node}{ $node->{metadata}->{name} }{$pretty_time}{memory_allocatable} = $tmp_data{ $node->{metadata}->{name} }{memory_allocatable};
    $data{node}{ $node->{metadata}->{name} }{$pretty_time}{memory_capacity}    = $tmp_data{ $node->{metadata}->{name} }{memory_capacity};
    $data{node}{ $node->{metadata}->{name} }{$pretty_time}{pods}               = $tmp_data{ $node->{metadata}->{name} }{pods};
    $data{node}{ $node->{metadata}->{name} }{$pretty_time}{pods_allocatable}   = $tmp_data{ $node->{metadata}->{name} }{pods_allocatable};
    $data{node}{ $node->{metadata}->{name} }{$pretty_time}{pods_capacity}      = $tmp_data{ $node->{metadata}->{name} }{pods_capacity};

    #cadvisor
    $url = $self->{endpoint} . "/api/v1/nodes/$node->{metadata}->{name}/proxy/metrics/cadvisor";
    my $metrics = $self->apiRequestPlain($url);
    if ( defined $metrics ) {
      $data{metadata}{interval} = $resolution;
      my @rows = split( /\n/, $metrics );
      for (@rows) {
        my $row = $_;
        for (@cadvisor_metrics) {
          my $cadvisor_metric = $_;
          if ( $row =~ /^$cadvisor_metric\{container=\"\"/ || $row =~ /^$cadvisor_metric\{container_name=\"\"/ ) {
            my @row_split = split( / /, $row );
            if ( !defined $data{node}{ $node->{metadata}->{name} }{$pretty_time}{$cadvisor_metric} ) {
              $data{node}{ $node->{metadata}->{name} }{$pretty_time}{$cadvisor_metric} = $row_split[1];
            }
            else {
              $data{node}{ $node->{metadata}->{name} }{$pretty_time}{$cadvisor_metric} += $row_split[1];
            }
          }
	  if ( defined $self->{namespaces} && scalar @{$self->{namespaces}} >= 1) {
            if ( $row =~ /^$cadvisor_metric/ && $row !~ /^$cadvisor_metric\{container=\"POD\"/ && $row !~ /^$cadvisor_metric\{container_name=\"POD\"/ ) {
              my @values    = split( /"/, $row );
              my @row_split = split( / /, $row );
              if ( defined $values[12] && ( $values[12] eq ",pod=" || $values[12] eq ",pod_name=" ) ) {
                $tmp_data{cadvisor}{container}{ $values[13] }{ $values[1] }{$cadvisor_metric} = $row_split[1];
              }
              elsif ( defined $values[10] && ( $values[10] eq ",pod=" || $values[10] eq ",pod_name=" ) ) {
                $tmp_data{cadvisor}{container}{ $values[11] }{ $values[1] }{$cadvisor_metric} = $row_split[1];
              }
            }
            elsif ( ( $cadvisor_metric eq "container_network_transmit_bytes_total" || $cadvisor_metric eq "container_network_transmit_packets_total" || $cadvisor_metric eq "container_network_receive_bytes_total" || $cadvisor_metric eq "container_network_receive_packets_total" ) && ( $row =~ /^$cadvisor_metric\{container=\"POD\"/ || $row =~ /^$cadvisor_metric\{container_name=\"POD\"/ ) ) {
              my @values    = split( /"/, $row );
              my @row_split = split( / /, $row );
              if ( defined $values[12] && ( $values[12] eq ",pod=" || $values[12] eq ",pod_name=" ) ) {

                #$tmp_data{cadvisor}{pod}{$values[13]}{$values[7]}{$cadvisor_metric} = $row_split[1];
                if ( defined $tmp_data{cadvisor}{pod}{ $values[13] }{$cadvisor_metric} ) {
                  $tmp_data{cadvisor}{pod}{ $values[13] }{$cadvisor_metric} += $row_split[1];
                }
                else {
                  $tmp_data{cadvisor}{pod}{ $values[13] }{$cadvisor_metric} = $row_split[1];
                }
              }
            }
          } 
        }
      }
    }
  }

  #pods
  if ( defined $self->{namespaces} && scalar @{$self->{namespaces}} >= 1) {
    $url  = $self->{endpoint} . "/apis/metrics.k8s.io/v1beta1/pods";
    $pods = $self->apiRequest($url);

    for ( @{ $pods->{items} } ) {
      my $pod = $_;

      if ( !defined $pod->{timestamp} ) {
        next;
      }

      if ( !defined $data{pod}{ $pod->{metadata}->{name} } ) {
        next;
      }

      my $pretty_time = str2time( $pod->{timestamp} );
      $pretty_time = int($pretty_time);

      $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu}            = 0;
      $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory}         = 0;
      $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu_request}    = 0;
      $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu_limit}      = 0;
      $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory_request} = 0;
      $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory_limit}   = 0;

      if ( defined $tmp_data{cadvisor}{pod}{ $pod->{metadata}->{name} } ) {
        foreach my $cmetric ( keys %{ $tmp_data{cadvisor}{pod}{ $pod->{metadata}->{name} } } ) {
          if ( defined $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{$cmetric} ) {
            $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{$cmetric} += $tmp_data{cadvisor}{pod}{ $pod->{metadata}->{name} }{$cmetric};
          }
          else {
            $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{$cmetric} = $tmp_data{cadvisor}{pod}{ $pod->{metadata}->{name} }{$cmetric};
          }
        }
      }
    

      #if (defined $tmp_data{cadvisor}{pod}{$pod->{metadata}->{name}}) {
      #  foreach my $network_key (%{$tmp_data{cadvisor}{pod}{$pod->{metadata}->{name}}}) {
      #    foreach my $tmp_key (%{$tmp_data{cadvisor}{pod}{$pod->{metadata}->{name}}{$network_key}}) {
      #      if (defined $tmp_data{cadvisor}{pod}{$pod->{metadata}->{name}}{$network_key}{$tmp_key}) {
      #        $data{pod}{$pod->{metadata}->{name}}{network}{$network_key}{$pretty_time}{$tmp_key} = $tmp_data{cadvisor}{pod}{$pod->{metadata}->{name}}{$network_key}{$tmp_key};
      #        if (defined $data{pod}{$pod->{metadata}->{name}}{data}{$pretty_time}{$tmp_key}) {
      #          $data{pod}{$pod->{metadata}->{name}}{data}{$pretty_time}{$tmp_key} += $tmp_data{cadvisor}{pod}{$pod->{metadata}->{name}}{$network_key}{$tmp_key};
      #        } else {
      #          $data{pod}{$pod->{metadata}->{name}}{data}{$pretty_time}{$tmp_key} = $tmp_data{cadvisor}{pod}{$pod->{metadata}->{name}}{$network_key}{$tmp_key};
      #        }
      #      }
      #    }
      #  }
      #}

      for ( @{ $pod->{containers} } ) {
        my $container = $_;

        if ( (defined $self->{container} && "$self->{container}" ne "1") || (defined $self->{monitor} && "$self->{monitor}" eq "3" )) {
          $data{pod}{ $pod->{metadata}->{name} }{container}{ $container->{name} }{$pretty_time}{cpu}    = transform( $container->{usage}->{cpu} );
          $data{pod}{ $pod->{metadata}->{name} }{container}{ $container->{name} }{$pretty_time}{memory} = transform( $container->{usage}->{memory} );

          $data{pod}{ $pod->{metadata}->{name} }{container}{ $container->{name} }{$pretty_time}{cpu_request}    = defined $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_request}    ? $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_request}    : 0;
          $data{pod}{ $pod->{metadata}->{name} }{container}{ $container->{name} }{$pretty_time}{cpu_limit}      = defined $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_limit}      ? $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_limit}      : 0;
          $data{pod}{ $pod->{metadata}->{name} }{container}{ $container->{name} }{$pretty_time}{memory_request} = defined $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_request} ? $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_request} : 0;
          $data{pod}{ $pod->{metadata}->{name} }{container}{ $container->{name} }{$pretty_time}{memory_limit}   = defined $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_limit}   ? $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_limit}   : 0;
        }
        $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu_request}    = defined $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_request}    ? $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu_request} + $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_request}       : $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu_request};
        $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu_limit}      = defined $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_limit}      ? $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu_limit} + $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{cpu_limit}           : $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu_limit};
        $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory_request} = defined $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_request} ? $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory_request} + $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_request} : $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory_request};
        $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory_limit}   = defined $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_limit}   ? $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory_limit} + $tmp_data{ $pod->{metadata}->{name} }{ $container->{name} }{memory_limit}     : $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory_limit};

        if (( defined $self->{container} && "$self->{container}" ne "1") || (defined $self->{monitor} && "$self->{monitor}" eq "3" )) {
          if ( defined $tmp_data{cadvisor}{container}{ $pod->{metadata}->{name} }{ $container->{name} } ) {
            foreach my $tmp_key ( %{ $tmp_data{cadvisor}{container}{ $pod->{metadata}->{name} }{ $container->{name} } } ) {
              if ( defined $tmp_data{cadvisor}{container}{ $pod->{metadata}->{name} }{ $container->{name} }{$tmp_key} ) {
                $data{pod}{ $pod->{metadata}->{name} }{container}{ $container->{name} }{$pretty_time}{$tmp_key} = $tmp_data{cadvisor}{container}{ $pod->{metadata}->{name} }{ $container->{name} }{$tmp_key};

                #if (defined $data{node}{$tmp_data{container_node}{$container->{name}}}{$tmp_key} && defined $tmp_data{cadvisor}{node}{$pod->{metadata}->{name}}{$container->{name}}{$tmp_key}) {
                #  $data{node}{$tmp_data{container_node}{$container->{name}}}{$tmp_data{cadvisor}{node}{$pod->{metadata}->{name}}{$container->{name}}{$tmp_key}{time}}{$tmp_key} += $tmp_data{cadvisor}{node}{$pod->{metadata}->{name}}{$container->{name}}{$tmp_key}{value};
                #} else {
                #  $data{node}{$tmp_data{container_node}{$container->{name}}}{$tmp_data{cadvisor}{node}{$pod->{metadata}->{name}}{$container->{name}}{$tmp_key}{time}}{$tmp_key} = $tmp_data{cadvisor}{node}{$pod->{metadata}->{name}}{$container->{name}}{$tmp_key}{value};
                #}
              }
            }
          }
        }

        $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{cpu}    += transform( $container->{usage}->{cpu} );
        $data{pod}{ $pod->{metadata}->{name} }{data}{$pretty_time}{memory} += transform( $container->{usage}->{memory} );
      }
    }

    my $ntime = time();
    foreach my $pod ( keys %{ $data{pod} } ) {
      foreach my $time ( keys %{ $data{pod}{$pod}{data} } ) {
        if ( !defined $namespace{'pod'}{$pod} ) {
          next;
        }
        if ( !defined $data{namespace}{ $namespace{'namespace'}{ $namespace{'pod'}{$pod} } } ) {
          $data{namespace}{ $namespace{'namespace'}{ $namespace{'pod'}{$pod} } }{$ntime}{cpu}    = $data{pod}{$pod}{data}{$time}{cpu};
          $data{namespace}{ $namespace{'namespace'}{ $namespace{'pod'}{$pod} } }{$ntime}{memory} = $data{pod}{$pod}{data}{$time}{memory};
        }
        else {
          $data{namespace}{ $namespace{'namespace'}{ $namespace{'pod'}{$pod} } }{$ntime}{cpu}    += $data{pod}{$pod}{data}{$time}{cpu};
          $data{namespace}{ $namespace{'namespace'}{ $namespace{'pod'}{$pod} } }{$ntime}{memory} += $data{pod}{$pod}{data}{$time}{memory};
        }
      }
      if (defined $self->{monitor} && "$self->{monitor}" eq "1") {
        undef $data{pod}{$pod};
      }
    }
  }

  return \%data;
}

sub transform {
  my $data = shift;

  my $size;
  if ( substr( $data, -1 ) eq "i" ) {
    $size = substr( $data, -2 );
    chop($data);
  }
  else {
    $size = substr( $data, -1 );
  }

  if ( !looks_like_number($size) && $size ne "K" && $size ne "k" && $size ne "M" && $size ne "G" && $size ne "T" && $size ne "n" && $size ne "u" && $size ne "m" && $size ne "Ki" && $size ne "Mi" && $size ne "Mi" && $size ne "Gi" && $size ne "Ti" ) {
    error("Unknown metric: $data");
  }

  if ( !looks_like_number($data) ) {
    chop($data);
  }

  if ( $size eq "n" ) {
    $data = $data / 1000000000;
  }
  elsif ( $size eq "u" ) {
    $data = $data / 1000000;
  }
  elsif ( $size eq "m" ) {
    $data = $data / 1000;
  }
  elsif ( $size eq "Ki" ) {
    $data = $data / 1024;
  }
  elsif ( $size eq "K" | $size eq "k" ) {
    $data = ( ( $data * 1000 ) / 1024 ) / 1024;
  }
  elsif ( $size eq "Gi" ) {
    $data = $data * 1024;
  }
  elsif ( $size eq "G" ) {
    $data = ( ( $data * 1000 * 1000 * 1000 ) / ( 1024 * 1024 * 1024 ) ) * 1024;
  }
  elsif ( $size eq "M" ) {
    $data = ( $data * 1000 ) / 1024;
  }
  elsif ( $size eq "Ti" ) {
    $data = $data / ( 1024 * 1024 );
  }
  elsif ( $size eq "T" ) {
    $data = ( ( $data * 1000 * 1000 * 1000 * 1000 ) / ( 1024 * 1024 * 1024 * 1024 ) ) * 1024 * 1024;
  }
  else {
    if ( looks_like_number($data) ) {
      $data = $data * 1;
    }
  }

  return $data;
}

sub getPodsInfo {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/api/v1/pods";
  my $pods = $self->apiRequest($url);
  my %data;

  for ( @{ $pods->{items} } ) {
    my $pod = $_;

    $data{label}{pod}{ $pod->{metadata}->{uid} } = $pod->{metadata}->{name};

    $data{ $pod->{metadata}->{uid} }{name}               = $pod->{metadata}->{name};
    $data{ $pod->{metadata}->{uid} }{'k8s-app'}{name}    = $pod->{metadata}->{labels}->{'k8s-app'};
    $data{ $pod->{metadata}->{uid} }{'k8s-app'}{version} = $pod->{metadata}->{labels}->{version};
    $data{ $pod->{metadata}->{uid} }{volumes}            = $pod->{spec}->{volumes};
    $data{ $pod->{metadata}->{uid} }{containers}         = $pod->{spec}->{containers};
    $data{ $pod->{metadata}->{uid} }{restartPolicy}      = $pod->{spec}->{restartPolicy};
    $data{ $pod->{metadata}->{uid} }{status}             = $pod->{status}->{phase};
    $data{ $pod->{metadata}->{uid} }{conditions}         = $pod->{status}->{conditions};
    $data{ $pod->{metadata}->{uid} }{hostIP}             = $pod->{status}->{hostIP};
    $data{ $pod->{metadata}->{uid} }{podIP}              = $pod->{status}->{podIP};
    $data{ $pod->{metadata}->{uid} }{startTime}          = $pod->{status}->{startTime};
  }

  return \%data;
}

sub json2csv {
  my ($json) = @_;
  my $csv = '';

  # Nodes

  my $nodes         = "uuid;time;type;interval;cpu;cpu_allocatable;cpu_capacity;memory;memory_allocatable;memory_capacity;pods;pods_allocatable;pods_capacity;container_fs_writes_total;container_fs_reads_total;container_fs_writes_bytes_total;container_fs_reads_bytes_total;container_fs_write_seconds_total;container_fs_read_seconds_total;container_network_receive_bytes_total;container_network_transmit_bytes_total;container_network_receive_packets_total;container_network_transmit_packets_total;container_fs_usage_bytes;\n";
  my @nodes_metrics = ( 'cpu', 'cpu_allocatable', 'cpu_capacity', 'memory', 'memory_allocatable', 'memory_capacity', 'pods', 'pods_allocatable', 'pods_capacity', 'container_fs_writes_total', 'container_fs_reads_total', 'container_fs_writes_bytes_total', 'container_fs_reads_bytes_total', 'container_fs_write_seconds_total', 'container_fs_read_seconds_total', 'container_network_receive_bytes_total', 'container_network_transmit_bytes_total', 'container_network_receive_packets_total', 'container_network_transmit_packets_total', 'container_fs_usage_bytes' );

  foreach my $node ( keys %{ $json->{node} } ) {
    foreach my $time ( keys %{ $json->{node}{$node} } ) {
      $nodes .= $node . ";" . $time . ";node;" . $json->{metadata}{interval} . ";";
      for my $metric (@nodes_metrics) {
        if ( defined $json->{node}{$node}{$time}{$metric} ) {
          $nodes .= $json->{node}{$node}{$time}{$metric} . ";";
        }
        else {
          $nodes .= "U;";
        }
      }
      $nodes .= "\n";
    }
  }

  # Pods

  my $pods         = "uuid;time;type;interval;cpu;cpu_limit;cpu_request;memory;memory_limit;memory_request;container_network_receive_bytes_total;container_network_transmit_bytes_total;container_network_receive_packets_total;container_network_transmit_packets_total;\n";
  my @pods_metrics = ( 'cpu', 'cpu_limit', 'cpu_request', 'memory', 'memory_limit', 'memory_request', 'container_network_receive_bytes_total', 'container_network_transmit_bytes_total', 'container_network_receive_packets_total', 'container_network_transmit_packets_total' );

  foreach my $pod ( keys %{ $json->{pod} } ) {
    foreach my $time ( keys %{ $json->{pod}{$pod}{data} } ) {
      $pods .= $pod . ";" . $time . ";pod;" . $json->{metadata}{interval} . ";";
      for my $metric (@pods_metrics) {
        if ( defined $json->{pod}{$pod}{data}{$time}{$metric} ) {
          $pods .= $json->{pod}{$pod}{data}{$time}{$metric} . ";";
        }
        else {
          $pods .= "U;";
        }
      }
      $pods .= "\n";
    }
  }

  # Containers

  my $containers         = "uuid;time;type;interval;node;cpu;cpu_limit;cpu_request;memory;memory_limit;memory_request;container_fs_writes_total;container_fs_reads_total;container_fs_writes_bytes_total;container_fs_reads_bytes_total;container_fs_write_seconds_total;container_fs_read_seconds_total;container_fs_usage_bytes;\n";
  my @containers_metrics = ( 'cpu', 'cpu_limit', 'cpu_request', 'memory', 'memory_limit', 'memory_request', 'container_fs_writes_total', 'container_fs_reads_total', 'container_fs_writes_bytes_total', 'container_fs_reads_bytes_total', 'container_fs_write_seconds_total', 'container_fs_read_seconds_total', 'container_fs_usage_bytes' );

  foreach my $pod ( keys %{ $json->{pod} } ) {
    foreach my $container ( keys %{ $json->{pod}{$pod}{container} } ) {
      foreach my $time ( keys %{ $json->{pod}{$pod}{container}{$container} } ) {
        $containers .= $pod . "--" . $container . ";" . $time . ";container;" . $json->{metadata}{interval} . ";" . $json->{pod}{$pod}{metadata}{node} . ";";
        for my $metric (@containers_metrics) {
          if ( defined $json->{pod}{$pod}{container}{$container}{$time}{$metric} ) {
            $containers .= $json->{pod}{$pod}{container}{$container}{$time}{$metric} . ";";
          }
          else {
            $containers .= "U;";
          }
        }
        $containers .= "\n";
      }
    }
  }

  # Namespace

  my $namespaces         = "uuid;time;type;interval;cpu;memory;\n";
  my @namespaces_metrics = ( 'cpu', 'memory' );

  foreach my $namespace ( keys %{ $json->{namespace} } ) {
    foreach my $time ( keys %{ $json->{namespace}{$namespace} } ) {
      $namespaces .= $namespace . ";" . $time . ";namespace;" . $json->{metadata}{interval} . ";";
      for my $metric (@namespaces_metrics) {
        if ( defined $json->{namespace}{$namespace}{$time}{$metric} ) {
          $namespaces .= $json->{namespace}{$namespace}{$time}{$metric} . ";";
        }
        else {
          $namespaces .= "U;";
        }
      }
      $namespaces .= "\n";
    }
  }

  $csv .= $containers . "\n" . $pods . "\n" . $nodes . "\n" . $namespaces;

  return $csv;
}

sub apiRequestWithoutDie {
  my ( $self, $url ) = @_;

  my $protocol = $self->{protocol} . "://";
  my $json     = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header( Authorization => "Bearer $self->{token}" );

  my $resp;
  my $response;

  eval { $response = $ua->get( $protocol . $url ); };

  if ($@) {
    my $error = $@;
    error("API Request Error [$url]: $error", $self->{cluster});
  }

  eval { $resp = $json->decode( $response->content ); };

  if ($@) {
    my $error = $@;
    error("JSON decode response from API Error [$url]: $error", $self->{cluster});
  }

  if ( defined $resp->{status} ) {
    if ( $resp->{status} eq "Failure" ) {
      error("API Request Failure: $resp->{message} (bad token?)", $self->{cluster});
    }
  }

  return $resp;

}

sub apiRequest {
  my ( $self, $url ) = @_;

  my $protocol = $self->{protocol} . "://";
  my $json     = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header( Authorization => "Bearer $self->{token}" );

  my $resp;
  my $response;

  eval { $response = $ua->get( $protocol . $url ); };

  if ($@) {
    my $error = $@;
    error_die("API Request Error [$url]: $error", $self->{cluster});
  }

  eval { $resp = $json->decode( $response->content ); };

  if ($@) {
    my $error = $@;
    error($response->content, $self->{cluster});
    error_die("JSON decode response from API Error [$url]: $error", $self->{cluster});
  }

  if ( defined $resp->{status} ) {
    if ( $resp->{status} eq "Failure" ) {
      error_die("API Request Failure: $resp->{message} (bad token?)", $self->{cluster});
    }
  }

  return $resp;

}

sub apiRequestPlain {
  my ( $self, $url ) = @_;

  my $protocol = $self->{protocol} . "://";
  my $json     = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $resp = ();

  eval { $resp = $ua->get( $protocol . $url ); };

  if ($@) {
    my $error = $@;
    error($error);
  }

  return $resp->content;

}

sub log {
  my $text     = shift;
  my $alias    = shift;
  my $act_time = localtime();
  chomp($text);

  if (defined $alias) {
    print "[$act_time] [$alias]: $text \n";
  } else {
    print "[$act_time]: $text \n";
  }
  return 1;
}

sub error {
  my $text     = shift;
  my $alias    = shift;
  my $act_time = localtime();
  chomp($text);

  if (defined $alias) {
    print STDERR "[$act_time] [$alias]: $text : $!\n";
  } else {
    print STDERR "[$act_time]: $text : $!\n";
  }

  return 1;
}

sub error_die {
  my $text     = shift;
  my $alias    = shift;
  my $act_time = localtime();

  if (defined $alias) {
    print STDERR "[$act_time] [$alias]: $text : $!\n";
  } else {
    print STDERR "[$act_time]: $text : $!\n";
  }
  exit(1);
}

1;
