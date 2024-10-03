# openshift-csv2rrd.pl
# store Openshift data

use 5.008_008;

use strict;
use warnings;

use File::Copy;
use JSON;
use RRDp;
use HostCfg;
use Kubernetes;
use OpenshiftDataWrapper;
use KubernetesLoadDataModule;
use Xorux_lib qw(write_json);

use Data::Dumper;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir      = $ENV{INPUTDIR};
my $data_dir      = "$inputdir/data/Openshift";
my $csv_dir       = "$data_dir/csv";
my $node_dir      = "$data_dir/Node";
my $pod_dir       = "$data_dir/Pod";
my $network_dir   = "$data_dir/Network";
my $container_dir = "$data_dir/Container";
my $namespace_dir = "$data_dir/Namespace";
my $tmpdir        = "$inputdir/tmp";
my $top_dir       = "$data_dir/top";

if ( keys %{ HostCfg::getHostConnections('Openshift') } == 0 ) {
  exit(0);
}

my @cadvisor_metrics = ( 'container_fs_usage_bytes', 'container_fs_reads_bytes_total', 'container_fs_writes_bytes_total', 'container_fs_reads_total', 'container_fs_writes_total', 'container_fs_read_seconds_total', 'container_fs_write_seconds_total' );

unless ( -d $node_dir ) {
  mkdir( "$node_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $node_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $top_dir ) {
  mkdir( "$top_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $top_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $pod_dir ) {
  mkdir( "$pod_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $pod_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $container_dir ) {
  mkdir( "$container_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $container_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $network_dir ) {
  mkdir( "$network_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $network_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $namespace_dir ) {
  mkdir( "$namespace_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $namespace_dir: $!" . __FILE__ . ':' . __LINE__ );
}

my $rrdtool = $ENV{RRDTOOL};

my $rrd_start_time;

################################################################################

RRDp::start "$rrdtool";

my $rrdtool_version = 'Unknown';
$_ = `$rrdtool`;
if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
  $rrdtool_version = $1;
}
print "RRDp    version: $RRDp::VERSION \n";
print "RRDtool version: $rrdtool_version\n";

my $labels = OpenshiftDataWrapper::get_labels();
my @files;
my $data;
my %top;
my %last = get_last();

opendir( DH, $csv_dir ) || die "Could not open '$csv_dir' for reading '$!'\n";
@files = grep /.*.csv/, readdir DH;

#@files = glob( $csv_dir . '/*' );
foreach my $file ( sort @files ) {

  my %tmp_data;
  my $has_failed = 0;
  my @splits     = split /_/, $file;

  Kubernetes::log($file);

  my $timestamp = my $rrd_start_time = time() - 4200;
  my $type      = $splits[0];
  my %legend;
  my %updates;
  my $rrd_filepath;

  # read file
  if ( open( my $fh, '<', "$csv_dir/$file" ) ) {
    while ( my $row = <$fh> ) {
      my @fields = split ";", $row;
      if ( $fields[0] eq "uuid" ) {
        my $i = 0;
        for my $field (@fields) {
          $legend{$field} = $i;
          $i++;
        }
      }
      elsif ( defined $fields[1] ) {

	#print "- $fields[0] \n";

        if ( $fields[ $legend{'type'} ] eq "container" || $fields[ $legend{'type'} ] eq "namespace") {
          $rrd_filepath = OpenshiftDataWrapper::get_filepath_rrd( { type => $fields[ $legend{'type'} ], uuid => $fields[0] } );
        }
        else {
          if ( !defined $labels->{name_to_uuid}->{ $fields[0] } ) {
            next;
          }
          $rrd_filepath = OpenshiftDataWrapper::get_filepath_rrd( { type => $fields[ $legend{'type'} ], uuid => $labels->{name_to_uuid}->{ $fields[0] } } );
        }
        if ( $fields[ $legend{'type'} ] eq "node" ) {
          unless ( -f $rrd_filepath ) {
            if ( KubernetesLoadDataModule::create_rrd_node( $rrd_filepath, $rrd_start_time ) ) {
              $has_failed = 1;
            }
          }
          if ( $has_failed != 1 ) {
            for (@cadvisor_metrics) {
              my $cadvisor_metric = $_;
              if ( defined $last{ $fields[0] }{$cadvisor_metric} && defined $fields[ $legend{$cadvisor_metric} ] && $fields[ $legend{$cadvisor_metric} ] ne "U" ) {
                if ( $last{ $fields[0] }{$cadvisor_metric} > $fields[ $legend{$cadvisor_metric} ] ) {
                  $last{ $fields[0] }{$cadvisor_metric} = $fields[ $legend{$cadvisor_metric} ];
                  $fields[ $legend{$cadvisor_metric} ] = ();
                }
                else {
                  my $resave = $fields[ $legend{$cadvisor_metric} ];
                  if ( defined $tmp_data{ $fields[0] }{$cadvisor_metric} ) {
                    $fields[ $legend{$cadvisor_metric} ] = ( $fields[ $legend{$cadvisor_metric} ] - $last{ $fields[0] }{$cadvisor_metric} ) + $tmp_data{ $fields[0] }{$cadvisor_metric};
                  }
                  else {
                    $fields[ $legend{$cadvisor_metric} ] = $fields[ $legend{$cadvisor_metric} ] - $last{ $fields[0] }{$cadvisor_metric};
                  }
                  $last{ $fields[0] }{$cadvisor_metric} = $resave;
                }
              }
              elsif ( defined $fields[ $legend{$cadvisor_metric} ] && $fields[ $legend{$cadvisor_metric} ] ne "U" ) {
                $last{ $fields[0] }{$cadvisor_metric} = $fields[ $legend{$cadvisor_metric} ];
		$fields[ $legend{$cadvisor_metric} ] = ();
              }

              if ( defined $legend{$cadvisor_metric} && defined $fields[ $legend{$cadvisor_metric} ] && $fields[ $legend{$cadvisor_metric} ] ne "U" ) {
                $fields[ $legend{$cadvisor_metric} ] = $fields[ $legend{$cadvisor_metric} ] / $fields[ $legend{'interval'} ];
              }

              if ( defined $legend{$cadvisor_metric} && defined $fields[ $legend{$cadvisor_metric} ] && $fields[ $legend{$cadvisor_metric} ] eq "U" ) {
                $fields[ $legend{$cadvisor_metric} ] = ();
              }
            }

            %updates = (
              'cpu'                                      => $fields[ $legend{'cpu'} ],
              'cpu_allocatable'                          => $fields[ $legend{'cpu_allocatable'} ],
              'cpu_capacity'                             => $fields[ $legend{'cpu_capacity'} ],
              'memory'                                   => $fields[ $legend{'memory'} ],
              'memory_allocatable'                       => $fields[ $legend{'memory_allocatable'} ],
              'memory_capacity'                          => $fields[ $legend{'memory_capacity'} ],
              'ephemeral_storage_allocatable'            => 0,
              'ephemeral_storage_capacity'               => 0,
              'pods'                                     => $fields[ $legend{'pods'} ],
              'pods_allocatable'                         => $fields[ $legend{'pods_allocatable'} ],
              'pods_capacity'                            => $fields[ $legend{'pods_capacity'} ],
              'container_fs_reads_bytes_total'           => $fields[ $legend{'container_fs_reads_bytes_total'} ],
              'container_fs_writes_bytes_total'          => $fields[ $legend{'container_fs_writes_bytes_total'} ],
              'container_fs_reads_total'                 => $fields[ $legend{'container_fs_reads_total'} ],
              'container_fs_writes_total'                => $fields[ $legend{'container_fs_writes_total'} ],
              'container_fs_read_seconds_total'          => $fields[ $legend{'container_fs_read_seconds_total'} ],
              'container_fs_write_seconds_total'         => $fields[ $legend{'container_fs_write_seconds_total'} ],
              'container_network_receive_bytes_total'    => $fields[ $legend{'container_network_receive_bytes_total'} ],
              'container_network_receive_packets_total'  => $fields[ $legend{'container_network_receive_packets_total'} ],
              'container_network_transmit_bytes_total'   => $fields[ $legend{'container_network_transmit_bytes_total'} ],
              'container_network_transmit_packets_total' => $fields[ $legend{'container_network_transmit_packets_total'} ],
              'metric_resolution'                        => $fields[ $legend{'interval'} ]
            );

            if ( KubernetesLoadDataModule::update_rrd_node( $rrd_filepath, $fields[ $legend{'time'} ], \%updates ) ) {
              $has_failed = 1;
            }
          }
        }
	elsif ( $fields[ $legend{'type'} ] eq "namespace" ) {
          unless ( -f $rrd_filepath ) {
            if ( KubernetesLoadDataModule::create_rrd_namespace( $rrd_filepath, $rrd_start_time ) ) {
              $has_failed = 1;
            }
          }

          %updates = (
            'cpu'    => $fields[ $legend{'cpu'} ],
            'memory' => $fields[ $legend{'memory'} ]
          );

          if ( KubernetesLoadDataModule::update_rrd_namespace( $rrd_filepath, $fields[ $legend{'time'} ], \%updates ) ) {
            $has_failed = 1;
          }

        }
        elsif ( $fields[ $legend{'type'} ] eq "pod" ) {
          if ( defined $fields[ $legend{'memory'} ] && $fields[ $legend{'memory'} ] gt 0 ) {
            unless ( -f $rrd_filepath ) {
              if ( KubernetesLoadDataModule::create_rrd_pod( $rrd_filepath, $rrd_start_time ) ) {
                $has_failed = 1;
              }
            }

            if ( !defined $top{pod}{ $labels->{name_to_uuid}->{ $fields[0] } }{cpu} ) {
              $top{pod}{ $labels->{name_to_uuid}->{ $fields[0] } }{cpu}     = $fields[ $legend{'cpu'} ];
              $top{pod}{ $labels->{name_to_uuid}->{ $fields[0] } }{memory}  = $fields[ $legend{'memory'} ];
              $top{pod}{ $labels->{name_to_uuid}->{ $fields[0] } }{counter} = 1;
            }
            else {
              $top{pod}{ $labels->{name_to_uuid}->{ $fields[0] } }{cpu}     += $fields[ $legend{'cpu'} ];
              $top{pod}{ $labels->{name_to_uuid}->{ $fields[0] } }{memory}  += $fields[ $legend{'memory'} ];
              $top{pod}{ $labels->{name_to_uuid}->{ $fields[0] } }{counter} += 1;
            }

            %updates = (
              'cpu'                                    => $fields[ $legend{'cpu'} ],
              'cpu_request'                            => $fields[ $legend{'cpu_request'} ],
              'cpu_limit'                              => $fields[ $legend{'cpu_limit'} ],
              'memory'                                 => $fields[ $legend{'memory'} ],
              'memory_request'                         => $fields[ $legend{'memory_request'} ],
              'memory_limit'                           => $fields[ $legend{'memory_limit'} ],
              'container_network_receive_bytes_total'  => $fields[ $legend{'container_network_receive_bytes_total'} ],
              'container_network_transmit_bytes_total' => $fields[ $legend{'container_network_transmit_bytes_total'} ]
            );

            if ( KubernetesLoadDataModule::update_rrd_pod( $rrd_filepath, $fields[ $legend{'time'} ], \%updates ) ) {
              $has_failed = 1;
            }
          }
        }
        elsif ( $fields[ $legend{'type'} ] eq "container" ) {
          if ( defined $fields[ $legend{'memory'} ] && $fields[ $legend{'memory'} ] gt 0 ) {
            unless ( -f $rrd_filepath ) {
              if ( KubernetesLoadDataModule::create_rrd_container( $rrd_filepath, $rrd_start_time ) ) {
                $has_failed = 1;
              }
            }

            for (@cadvisor_metrics) {
              my $cadvisor_metric = $_;

              if ( defined $last{ $fields[0] }{$cadvisor_metric} && defined $fields[ $legend{$cadvisor_metric} ] && $fields[ $legend{$cadvisor_metric} ] ne "U" ) {
                if ( $last{ $fields[0] }{$cadvisor_metric} > $fields[ $legend{$cadvisor_metric} ] ) {
                  $last{ $fields[0] }{$cadvisor_metric} = $fields[ $legend{$cadvisor_metric} ];
                  undef $fields[ $legend{$cadvisor_metric} ];
                }
                else {
                  if ( defined $tmp_data{ $fields[ $legend{'node'} ] }{$cadvisor_metric} ) {
                    $tmp_data{ $fields[ $legend{'node'} ] }{$cadvisor_metric} += ( $fields[ $legend{$cadvisor_metric} ] - $last{ $fields[0] }{$cadvisor_metric} );
                  }
                  else {
                    $tmp_data{ $fields[ $legend{'node'} ] }{$cadvisor_metric} = ( $fields[ $legend{$cadvisor_metric} ] - $last{ $fields[0] }{$cadvisor_metric} );
                  }
                  my $tmp_value = $last{ $fields[0] }{$cadvisor_metric};
                  $last{ $fields[0] }{$cadvisor_metric} = $fields[ $legend{$cadvisor_metric} ];
                  $fields[ $legend{$cadvisor_metric} ] = $fields[ $legend{$cadvisor_metric} ] - $tmp_value;
                }
              }
              elsif ( defined( $fields[ $legend{$cadvisor_metric} ] ) && $fields[ $legend{$cadvisor_metric} ] ne "U" ) {
                $last{ $fields[0] }{$cadvisor_metric} = $fields[ $legend{$cadvisor_metric} ];
                undef $fields[ $legend{$cadvisor_metric} ];
              }

              if ( defined $fields[ $legend{$cadvisor_metric} ] && $fields[ $legend{$cadvisor_metric} ] ne "U" ) {
                $fields[ $legend{$cadvisor_metric} ] = $fields[ $legend{$cadvisor_metric} ] / $fields[ $legend{'interval'} ];
              }

              if ( defined $fields[ $legend{$cadvisor_metric} ] && $fields[ $legend{$cadvisor_metric} ] eq "U" ) {
                $fields[ $legend{$cadvisor_metric} ] = ();
              }
            }

            %updates = (
              'cpu'                              => $fields[ $legend{'cpu'} ],
              'cpu_request'                      => $fields[ $legend{'cpu_request'} ],
              'cpu_limit'                        => $fields[ $legend{'cpu_limit'} ],
              'memory'                           => $fields[ $legend{'memory'} ],
              'memory_request'                   => $fields[ $legend{'memory_request'} ],
              'memory_limit'                     => $fields[ $legend{'memory_limit'} ],
              'container_fs_reads_bytes_total'   => $fields[ $legend{'container_fs_reads_bytes_total'} ],
              'container_fs_writes_bytes_total'  => $fields[ $legend{'container_fs_writes_bytes_total'} ],
              'container_fs_reads_total'         => $fields[ $legend{'container_fs_reads_total'} ],
              'container_fs_writes_total'        => $fields[ $legend{'container_fs_writes_total'} ],
              'container_fs_read_seconds_total'  => $fields[ $legend{'container_fs_read_seconds_total'} ],
              'container_fs_write_seconds_total' => $fields[ $legend{'container_fs_write_seconds_total'} ],
              'container_fs_usage_bytes'         => $fields[ $legend{'container_fs_usage_bytes'} ]
            );

            if ( KubernetesLoadDataModule::update_rrd_container( $rrd_filepath, $fields[ $legend{'time'} ], \%updates ) ) {
              $has_failed = 1;
            }
          }
        }
      }
    }
    close($fh);
  }
  else {
    warn( localtime() . ": Cannot open the file $file ($!)" ) && next;
    next;
  }

  unless ($has_failed) {
    backup_perf_file($file);
    save_top( \%top );
  }

}

save_last( \%last );

################################################################################

sub backup_perf_file {

  my $src_file = shift;
  my $alias    = ( split( '_', $src_file ) )[1];
  my $source   = "$csv_dir/$src_file";
  my $target1  = "$tmpdir/openshift-$alias-perf-last1.csv";
  my $target2  = "$tmpdir/openshift-$alias-perf-last2.csv";

  if ( -f $target1 ) {
    move( $target1, $target2 ) or die "error: cannot replace the old backup data file: $!";
  }
  move( $source, $target1 ) or die "error: cannot backup the data file: $!";
}

sub save_top {
  my $data = shift;

  if ($data) {
    open my $fh, ">", $top_dir . "/pod.json";
    print $fh JSON->new->pretty->encode($data);
    close $fh;
  }
}

sub save_last {
  my $data = shift;

  if ($data) {
    open my $fh, ">", $data_dir . "/last.json";
    print $fh JSON->new->pretty->encode($data);
    close $fh;
  }
}

sub get_last {
  my $data;
  my $json = '';
  if ( open( my $fh, '<', "$data_dir/last.json" ) ) {
    while ( my $row = <$fh> ) {
      chomp $row;
      $json .= $row;
    }
    close($fh);
  }
  else {
    return ();
  }

  # decode JSON
  eval { $data = decode_json($json); };
  if ($@) {
    my $error = $@;
    error($error);
    return ();
  }
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file last.json: missing data" ) && return ();
  }

  return %$data;
}

sub debug {
  my $text = shift;

  if ($text) {
    open my $fh, ">>", $data_dir . "/debug.log";
    print $fh $text;
    close $fh;
  }
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print STDERR "$act_time: $text : $!\n";
  return 1;
}

print "\n";
