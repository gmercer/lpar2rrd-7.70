# openshift-json2rrd.pl
# store Openshift data

use 5.008_008;

use strict;
use warnings;

use File::Copy;
use JSON;
use RRDp;
use HostCfg;
use OpenshiftDataWrapper;
use KubernetesLoadDataModule;
use Xorux_lib qw(write_json);

use Data::Dumper;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir      = $ENV{INPUTDIR};
my $data_dir      = "$inputdir/data/Openshift";
my $json_dir      = "$data_dir/json";
my $node_dir      = "$data_dir/Node";
my $pod_dir       = "$data_dir/Pod";
my $network_dir   = "$data_dir/Network";
my $container_dir = "$data_dir/Container";
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

opendir( DH, $json_dir ) || die "Could not open '$json_dir' for reading '$!'\n";
@files = grep /.*.json/, readdir DH;

#@files = glob( $json_dir . '/*' );
foreach my $file ( sort @files ) {

  my %last = get_last();
  my %tmp_data;
  my $has_failed = 0;
  my @splits     = split /_/, $file;

  print "\nFile processing           : $file, " . localtime();

  my $timestamp = my $rrd_start_time = time() - 4200;

  # read file
  my $json = '';
  if ( open( FH, '<', "$json_dir/$file" ) ) {
    while ( my $row = <FH> ) {
      chomp $row;
      $json .= $row;
    }
    close(FH);
  }
  else {
    warn( localtime() . ": Cannot open the file $file ($!)" ) && next;
    next;
  }

  # decode JSON
  eval { $data = decode_json($json); };
  if ($@) {
    my $error = $@;
    error("Empty perf file, deleting $json_dir/$file");
    unlink "$json_dir/$file";
    next;
  }
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file $file: missing data" ) && next;
  }

  my %updates;
  my $rrd_filepath;

  #pod
  print "\nPod                       : pushing data to rrd, " . localtime();

  foreach my $podKey ( keys %{ $data->{pod} } ) {
    if ( !defined $podKey || !defined $labels->{name_to_uuid}->{$podKey} ) { next; }
    print "\n - $podKey";
    $rrd_filepath = OpenshiftDataWrapper::get_filepath_rrd( { type => 'pod', uuid => $labels->{name_to_uuid}->{$podKey} } );
    my $created_rrd = ( -f $rrd_filepath ) ? 1 : 0;

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{pod}->{$podKey}->{data} } ) {

        #top
        if ( !defined $top{pod}{ $labels->{name_to_uuid}->{$podKey} }{cpu} ) {
          $top{pod}{ $labels->{name_to_uuid}->{$podKey} }{cpu}     = $data->{pod}->{$podKey}->{data}->{$timeKey}->{cpu};
          $top{pod}{ $labels->{name_to_uuid}->{$podKey} }{memory}  = $data->{pod}->{$podKey}->{data}->{$timeKey}->{memory};
          $top{pod}{ $labels->{name_to_uuid}->{$podKey} }{counter} = 1;
        }
        else {
          $top{pod}{ $labels->{name_to_uuid}->{$podKey} }{cpu}     += $data->{pod}->{$podKey}->{data}->{$timeKey}->{cpu};
          $top{pod}{ $labels->{name_to_uuid}->{$podKey} }{memory}  += $data->{pod}->{$podKey}->{data}->{$timeKey}->{memory};
          $top{pod}{ $labels->{name_to_uuid}->{$podKey} }{counter} += 1;
        }

        if ( defined $data->{pod}->{$podKey}->{data}->{$timeKey}->{memory} && $data->{pod}->{$podKey}->{data}->{$timeKey}->{memory} gt 0 ) {
          if ( $created_rrd eq "0" ) {
            if ( KubernetesLoadDataModule::create_rrd_pod( $rrd_filepath, $rrd_start_time ) ) {
              $has_failed = 1;
            }
            $created_rrd = 1;
          }

          %updates = ( 'cpu' => $data->{pod}->{$podKey}->{data}->{$timeKey}->{cpu}, 'cpu_request' => $data->{pod}->{$podKey}->{data}->{$timeKey}->{cpu_request}, 'cpu_limit' => $data->{pod}->{$podKey}->{data}->{$timeKey}->{cpu_limit}, 'memory' => $data->{pod}->{$podKey}->{data}->{$timeKey}->{memory}, 'memory_request' => $data->{pod}->{$podKey}->{data}->{$timeKey}->{memory_request}, 'memory_limit' => $data->{pod}->{$podKey}->{data}->{$timeKey}->{memory_limit}, 'container_network_receive_bytes_total' => $data->{pod}->{$podKey}->{data}->{$timeKey}->{container_network_receive_bytes_total}, 'container_network_transmit_bytes_total' => $data->{pod}->{$podKey}->{data}->{$timeKey}->{container_network_transmit_bytes_total} );

          if ( KubernetesLoadDataModule::update_rrd_pod( $rrd_filepath, $timeKey, \%updates ) ) {
            $has_failed = 1;
          }
        }
      }
    }

    my $pod_network_dir = "$network_dir/$labels->{name_to_uuid}->{$podKey}";
    unless ( -d $pod_network_dir ) {
      mkdir( "$pod_network_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $pod_network_dir: $!" . __FILE__ . ':' . __LINE__ );
    }

    #pod network
    print " - Network: ";
    foreach my $networkKey ( sort keys %{ $data->{pod}->{$podKey}->{network} } ) {
      print "$networkKey ";
      $rrd_filepath = OpenshiftDataWrapper::get_filepath_rrd( { type => 'network', parent => $labels->{name_to_uuid}->{$podKey}, uuid => $networkKey } );
      unless ( -f $rrd_filepath ) {
        if ( KubernetesLoadDataModule::create_rrd_pod_network( $rrd_filepath, $rrd_start_time ) ) {
          $has_failed = 1;
        }
      }

      if ( $has_failed != 1 ) {
        foreach my $timeKey ( sort keys %{ $data->{pod}->{$podKey}->{network}->{$networkKey} } ) {
          %updates = ( 'container_network_transmit_bytes_total' => $data->{pod}->{$podKey}->{network}->{$networkKey}->{$timeKey}->{container_network_transmit_bytes_total}, 'container_network_receive_bytes_total' => $data->{pod}->{$podKey}->{network}->{$networkKey}->{$timeKey}->{container_network_receive_bytes_total}, 'container_network_transmit_packets_total' => $data->{pod}->{$podKey}->{network}->{$networkKey}->{$timeKey}->{container_network_transmit_packets_total}, 'container_network_receive_packets_total' => $data->{pod}->{$podKey}->{network}->{$networkKey}->{$timeKey}->{container_network_receive_packets_total} );

          if ( KubernetesLoadDataModule::update_rrd_pod_network( $rrd_filepath, $timeKey, \%updates ) ) {
            $has_failed = 1;
          }
        }
      }
    }

    #containers under pod
    print " - Container: ";
    foreach my $containerKey ( sort keys %{ $data->{pod}->{$podKey}->{container} } ) {
      print "$podKey ";
      my $new_name = "$podKey--$containerKey";
      $rrd_filepath = OpenshiftDataWrapper::get_filepath_rrd( { type => 'container', uuid => $new_name } );
      my $created_rrd = ( -f $rrd_filepath ) ? 1 : 0;
      if ( $has_failed != 1 ) {
        foreach my $timeKey ( sort keys %{ $data->{pod}->{$podKey}->{container}->{$containerKey} } ) {

          for (@cadvisor_metrics) {
            my $cadvisor_metric = $_;

            if ( defined $last{$new_name}{$cadvisor_metric} && defined $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} ) {
              if ( $last{$new_name}{$cadvisor_metric} > $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} ) {
                $last{$new_name}{$cadvisor_metric} = $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric};
                undef $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric};
              }
              else {
                if ( defined $tmp_data{ $data->{pod}->{$podKey}->{metadata}->{node} }{$cadvisor_metric} ) {
                  $tmp_data{ $data->{pod}->{$podKey}->{metadata}->{node} }{$cadvisor_metric} += ( $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} - $last{$new_name}{$cadvisor_metric} );
                }
                else {
                  $tmp_data{ $data->{pod}->{$podKey}->{metadata}->{node} }{$cadvisor_metric} = ( $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} - $last{$new_name}{$cadvisor_metric} );
                }
                my $tmp_value = $last{$new_name}{$cadvisor_metric};
                $last{$new_name}{$cadvisor_metric} = $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric};
                $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} = $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} - $tmp_value;
              }
            }
            elsif ( defined( $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} ) ) {
              $last{$new_name}{$cadvisor_metric} = $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric};
              undef $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric};
            }

            if ( defined $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} ) {
              $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} = $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{$cadvisor_metric} / $data->{metadata}->{interval};
            }
          }
          if ( defined $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{memory} && $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{memory} gt 0 ) {
            if ( $created_rrd eq "0" ) {
              if ( KubernetesLoadDataModule::create_rrd_container( $rrd_filepath, $rrd_start_time ) ) {
                $has_failed = 1;
              }
              $created_rrd = 1;
            }
            %updates = ( 'cpu' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{cpu}, 'cpu_request' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{cpu_request}, 'cpu_limit' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{cpu_limit}, 'memory' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{memory}, 'memory_request' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{memory_request}, 'memory_limit' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{memory_limit}, 'container_fs_reads_bytes_total' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{container_fs_reads_bytes_total}, 'container_fs_writes_bytes_total' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{container_fs_writes_bytes_total}, 'container_fs_reads_total' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{container_fs_reads_total}, 'container_fs_writes_total' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{container_fs_writes_total}, 'container_fs_read_seconds_total' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{container_fs_read_seconds_total}, 'container_fs_write_seconds_total' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{container_fs_write_seconds_total}, 'container_fs_usage_bytes' => $data->{pod}->{$podKey}->{container}->{$containerKey}->{$timeKey}->{container_fs_usage_bytes} );

            if ( KubernetesLoadDataModule::update_rrd_container( $rrd_filepath, $timeKey, \%updates ) ) {
              $has_failed = 1;
            }
          }
        }
      }
    }
  }

  #node
  print "\nNode                      : pushing data to rrd, " . localtime();

  foreach my $nodeKey ( keys %{ $data->{node} } ) {
    print "\n - $nodeKey ($labels->{name_to_uuid}->{$nodeKey})";
    $rrd_filepath = OpenshiftDataWrapper::get_filepath_rrd( { type => 'node', uuid => $labels->{name_to_uuid}->{$nodeKey} } );
    unless ( -f $rrd_filepath ) {
      if ( KubernetesLoadDataModule::create_rrd_node( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
        print " !! error !! ";
      }
    }
    if ( $has_failed != 1 ) {

      foreach my $timeKey ( sort keys %{ $data->{node}->{$nodeKey} } ) {

        for (@cadvisor_metrics) {
          my $cadvisor_metric = $_;

          if ( defined $last{$nodeKey}{$cadvisor_metric} && defined $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} ) {
            if ( $last{$nodeKey}{$cadvisor_metric} > $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} ) {
              $last{$nodeKey}{$cadvisor_metric} = $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric};
              undef $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric};
            }
            else {
              my $resave = $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric};
              if ( defined $tmp_data{$nodeKey}{$cadvisor_metric} ) {
                $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} = ( $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} - $last{$nodeKey}{$cadvisor_metric} ) + $tmp_data{$nodeKey}{$cadvisor_metric};
              }
              else {
                $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} = $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} - $last{$nodeKey}{$cadvisor_metric};
              }
              $last{$nodeKey}{$cadvisor_metric} = $resave;
            }
          }
          elsif ( defined( $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} ) ) {
            $last{$nodeKey}{$cadvisor_metric} = $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric};
          }

          if ( defined $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} ) {
            $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} = $data->{node}->{$nodeKey}->{$timeKey}->{$cadvisor_metric} / $data->{metadata}->{interval};
          }
        }

        %updates = ( 'cpu' => $data->{node}->{$nodeKey}->{$timeKey}->{cpu}, 'cpu_allocatable' => $data->{node}->{$nodeKey}->{$timeKey}->{cpu_allocatable}, 'cpu_capacity' => $data->{node}->{$nodeKey}->{$timeKey}->{cpu_capacity}, 'memory' => $data->{node}->{$nodeKey}->{$timeKey}->{memory}, 'memory_allocatable' => $data->{node}->{$nodeKey}->{$timeKey}->{memory_allocatable}, 'memory_capacity' => $data->{node}->{$nodeKey}->{$timeKey}->{memory_capacity}, 'ephemeral_storage_allocatable' => 0, 'ephemeral_storage_capacity' => 0, 'pods' => $data->{node}->{$nodeKey}->{$timeKey}->{pods}, 'pods_allocatable' => $data->{node}->{$nodeKey}->{$timeKey}->{pods_allocatable}, 'pods_capacity' => $data->{node}->{$nodeKey}->{$timeKey}->{pods_capacity}, 'container_fs_reads_bytes_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_fs_reads_bytes_total}, 'container_fs_writes_bytes_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_fs_writes_bytes_total}, 'container_fs_reads_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_fs_reads_total}, 'container_fs_writes_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_fs_writes_total}, 'container_fs_read_seconds_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_fs_read_seconds_total}, 'container_fs_write_seconds_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_fs_write_seconds_total}, 'container_network_receive_bytes_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_network_receive_bytes_total}, 'container_network_receive_packets_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_network_receive_packets_total}, 'container_network_transmit_bytes_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_network_transmit_bytes_total}, 'container_network_transmit_packets_total' => $data->{node}->{$nodeKey}->{$timeKey}->{container_network_transmit_packets_total}, metric_resolution => $data->{metadata}->{interval} );

        if ( KubernetesLoadDataModule::update_rrd_node( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  unless ($has_failed) {
    backup_perf_file($file);
    save_top( \%top );
  }

  save_last( \%last );
}

#print "\n\nCheck RRD items           :  ".localtime();
#my @clusters = @{OpenshiftDataWrapper::get_items({ item_type => 'cluster' })};
#foreach my $cluster (@clusters) {
#  my ($cluster_id, $cluster_label) = each %{$cluster};
#  print "\nCluster $cluster_label";
#  my @nodes = @{OpenshiftDataWrapper::get_items({ item_type => 'node', parent_type => 'cluster', parent_id => $cluster_id })};
#  print "\nNodes: ";
#  foreach my $node (@nodes) {
#    my ($node_uuid, $node_label) = each %{$node};
#    print "$node_label ";
#  }
#  my @projects = @{OpenshiftDataWrapper::get_items({ item_type => 'project', parent_type => 'cluster', parent_id => $cluster_id })};
#  print "\nProjects: ";
#  foreach my $project (@projects) {
#    my ($project_uuid, $project_label) = each %{$project};
#    print "$project_label ";
#  }
#  my @pods = @{OpenshiftDataWrapper::get_items({ item_type => 'pod', parent_type => 'cluster', parent_id => $cluster_id })};
#  print "\nPods: ";
#  foreach my $pod (@pods) {
#    my ($pod_uuid, $pod_label) = each %{$pod};
#    print "$pod_label ";
#  }
#}

################################################################################

sub backup_perf_file {

  my $src_file = shift;
  my $alias    = ( split( '_', $src_file ) )[1];
  my $source   = "$json_dir/$src_file";
  my $target1  = "$tmpdir/openshift-$alias-perf-last1.json";
  my $target2  = "$tmpdir/openshift-$alias-perf-last2.json";

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
    close(FH);
  }
  else {
    return ();
  }

  # decode JSON
  eval { $data = decode_json($json); };
  if ($@) {
    my $error = $@;
    error("Empty last.json");
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
