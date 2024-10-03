# fusioncompute-json2rrd.pl
# store FusionCompute data

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use File::Copy;
use JSON;
use RRDp;
use FusionCompute;
use FusionComputeDataWrapper;
use FusionComputeLoadDataModule;
use Xorux_lib qw(write_json);
use HostCfg;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('FusionCompute') } == 0 ) {
  exit(0);
}

# data file paths
my $inputdir          = $ENV{INPUTDIR};
my $fusioncompute_dir = "$inputdir/data/FusionCompute";
my $json_dir          = "$fusioncompute_dir/json";
my $linux_dir         = "$inputdir/data/Linux/no_hmc";
my $tmpdir            = "$inputdir/tmp";

my $hosts_path      = "$fusioncompute_dir/Host";
my $clusters_path   = "$fusioncompute_dir/Cluster";
my $vms_path        = "$fusioncompute_dir/VM";
my $datastores_path = "$fusioncompute_dir/Datastore";

# create directories/
my @create_dir = ( $hosts_path, $clusters_path, $vms_path, $datastores_path );
for (@create_dir) {
  my $dir = $_;
  unless ( -d $dir ) {
    mkdir( "$dir", 0755 ) || warn( localtime() . ": Cannot mkdir $dir: $!" . __FILE__ . ':' . __LINE__ );
  }
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

my @files;

my $uuids = FusionComputeDataWrapper::get_labels();
my %mapping;

#create mapping file
eval {
  if ( -d $linux_dir ) {
    opendir( my $dh, $linux_dir ) || die "Can't open $linux_dir: $!";
    while ( readdir $dh ) {
      my $uuid_path = $linux_dir . "/" . $_;
      chomp($uuid_path);
      $uuid_path =~ s/\n//g;
      $uuid_path =~ s/\r//g;
      if ( -e "$uuid_path/uuid.txt" ) {
        my $uuid_file = '';
        if ( open( FH, '<', "$uuid_path/uuid.txt" ) ) {
          while ( my $row = <FH> ) {
            chomp $row;
            $uuid_file .= $row;
          }
          close(FH);
        }
        else {
          warn( localtime() . ": Cannot open the file $uuid_path/uuid.txt ($!)" ) && next;
          next;
        }
        if ( defined $uuids->{vm}->{$uuid_file} ) {
          $mapping{mapping}{$uuid_file} = $_;
        }
      }
    }
    closedir $dh;
  }
};
if ($@) {
  error($@);
}

if ( keys %{ $mapping{'mapping'} } > 0 ) {
  my $mapped = keys %{ $mapping{'mapping'} };
  if ( $mapped > 0 ) {
    FusionCompute::log("Mapped: $mapped linux agents");
  }
}

#save to JSON
open my $fh, ">", $fusioncompute_dir . "/mapping.json";
print $fh JSON->new->pretty->encode( \%mapping );
close $fh;

my $data;
opendir( DH, $json_dir ) || die "Could not open '$json_dir' for reading '$!'\n";
@files = grep /.*.json/, readdir DH;

#@files = glob( $json_dir . '/*' );
foreach my $file ( sort @files ) {
  my $has_failed = 0;

  my @splits = split /_/, $file;

  FusionCompute::log("File processing: $file");

  my $timestamp = my $rrd_start_time = $splits[1];

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

  # clusters
  FusionCompute::log("Clusters: pushing data to rrd");
  foreach my $clusterKey ( keys %{ $data->{cluster} } ) {

    $rrd_filepath = FusionComputeDataWrapper::get_filepath_rrd( { 'type' => 'cluster', 'uuid' => $clusterKey } );
    unless ( -f $rrd_filepath ) {
      if ( FusionComputeLoadDataModule::create_rrd_cluster( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{cluster}->{$clusterKey} } ) {
        %updates = (
          'cpu_usage'          => $data->{cluster}->{$clusterKey}->{$timeKey}->{cpu_usage},
          'mem_usage'          => $data->{cluster}->{$clusterKey}->{$timeKey}->{mem_usage},
          'logic_disk_usage'   => $data->{cluster}->{$clusterKey}->{$timeKey}->{logic_disk_usage},
          'disk_io_in'         => $data->{cluster}->{$clusterKey}->{$timeKey}->{disk_io_in},
          'disk_io_out'        => $data->{cluster}->{$clusterKey}->{$timeKey}->{disk_io_out},
          'nic_byte_in_usage'  => $data->{cluster}->{$clusterKey}->{$timeKey}->{nic_byte_in_usage},
          'nic_byte_out_usage' => $data->{cluster}->{$clusterKey}->{$timeKey}->{nic_byte_out_usage},
          'nic_byte_in'        => $data->{cluster}->{$clusterKey}->{$timeKey}->{nic_byte_in},
          'nic_byte_out'       => $data->{cluster}->{$clusterKey}->{$timeKey}->{nic_byte_out}
        );
        if ( FusionComputeLoadDataModule::update_rrd_cluster( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  # hosts
  FusionCompute::log("Hosts: pushing data to rrd");
  foreach my $hostKey ( keys %{ $data->{host} } ) {

    $rrd_filepath = FusionComputeDataWrapper::get_filepath_rrd( { 'type' => 'host', 'uuid' => $hostKey } );
    unless ( -f $rrd_filepath ) {
      if ( FusionComputeLoadDataModule::create_rrd_host( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{host}->{$hostKey} } ) {
        my $host_total_size = defined $data->{host}->{$hostKey}->{$timeKey}->{hostTotalSizeMB} ? $data->{host}->{$hostKey}->{$timeKey}->{hostTotalSizeMB} * ( 1024 * 1024 ) : ();
        %updates = (
          'cpu_usage'             => $data->{host}->{$hostKey}->{$timeKey}->{cpu_usage},
          'dom0_cpu_usage'        => $data->{host}->{$hostKey}->{$timeKey}->{dom0_cpu_usage},
          'cpu_cores'             => $data->{host}->{$hostKey}->{$timeKey}->{cpuRealCores},
          'cpu_cores_wr'          => $data->{host}->{$hostKey}->{$timeKey}->{cpuRealCoresWithoutReserved},
          'mem_usage'             => $data->{host}->{$hostKey}->{$timeKey}->{mem_usage},
          'dom0_mem_usage'        => $data->{host}->{$hostKey}->{$timeKey}->{dom0_mem_usage},
          'mem_total'             => $host_total_size,
          'nic_byte_in'           => $data->{host}->{$hostKey}->{$timeKey}->{nic_byte_in},
          'nic_byte_out'          => $data->{host}->{$hostKey}->{$timeKey}->{nic_byte_out},
          'nic_pkg_send'          => $data->{host}->{$hostKey}->{$timeKey}->{nic_pkg_send},
          'nic_pkg_rcv'           => $data->{host}->{$hostKey}->{$timeKey}->{nic_pkg_rcv},
          'nic_byte_in_usage'     => $data->{host}->{$hostKey}->{$timeKey}->{nic_byte_in_usage},
          'nic_byte_out_usage'    => $data->{host}->{$hostKey}->{$timeKey}->{nic_byte_out_usage},
          'nic_pkg_rx_drop_speed' => $data->{host}->{$hostKey}->{$timeKey}->{nic_pkg_rx_drop_speed},
          'nic_pkg_tx_drop_speed' => $data->{host}->{$hostKey}->{$timeKey}->{nic_pkg_tx_drop_speed},
          'disk_io_in'            => $data->{host}->{$hostKey}->{$timeKey}->{disk_io_in},
          'disk_io_out'           => $data->{host}->{$hostKey}->{$timeKey}->{disk_io_out},
          'disk_io_read'          => $data->{host}->{$hostKey}->{$timeKey}->{disk_io_read},
          'disk_io_write'         => $data->{host}->{$hostKey}->{$timeKey}->{disk_io_write},
          'logic_disk_usage'      => $data->{host}->{$hostKey}->{$timeKey}->{logic_disk_usage},
          'domU_cpu_usage'        => $data->{host}->{$hostKey}->{$timeKey}->{domU_cpu_usage},
          'domU_mem_usage'        => $data->{host}->{$hostKey}->{$timeKey}->{domU_mem_usage}
        );
        if ( FusionComputeLoadDataModule::update_rrd_host( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  # vms
  FusionCompute::log("VMs: pushing data to rrd");
  foreach my $vmKey ( keys %{ $data->{vm} } ) {

    $rrd_filepath = FusionComputeDataWrapper::get_filepath_rrd( { 'type' => 'vm', 'uuid' => $vmKey } );
    unless ( -f $rrd_filepath ) {
      if ( FusionComputeLoadDataModule::create_rrd_vm( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{vm}->{$vmKey} } ) {
        my $mem_total = defined $data->{vm}->{$vmKey}->{$timeKey}->{memoryQuantityMB} ? $data->{vm}->{$vmKey}->{$timeKey}->{memoryQuantityMB} * ( 1024 * 1024 ) : ();
        %updates = (
          'cpu_usage'             => $data->{vm}->{$vmKey}->{$timeKey}->{cpu_usage},
          'cpu_quantity'          => $data->{vm}->{$vmKey}->{$timeKey}->{cpuQuantity},
          'cores_per_socket'      => $data->{vm}->{$vmKey}->{$timeKey}->{coresPerSocket},
          'mem_usage'             => $data->{vm}->{$vmKey}->{$timeKey}->{mem_usage},
          'mem_total'             => $mem_total,
          'disk_usage'            => $data->{vm}->{$vmKey}->{$timeKey}->{disk_usage},
          'disk_io_in'            => $data->{vm}->{$vmKey}->{$timeKey}->{disk_io_in},
          'disk_io_out'           => $data->{vm}->{$vmKey}->{$timeKey}->{disk_io_out},
          'disk_req_in'           => $data->{vm}->{$vmKey}->{$timeKey}->{disk_req_in},
          'disk_req_out'          => $data->{vm}->{$vmKey}->{$timeKey}->{disk_req_out},
          'disk_rd_ios'           => $data->{vm}->{$vmKey}->{$timeKey}->{disk_rd_ios},
          'disk_wr_ios'           => $data->{vm}->{$vmKey}->{$timeKey}->{disk_wr_ios},
          'disk_iowr_ticks'       => $data->{vm}->{$vmKey}->{$timeKey}->{disk_iowr_ticks},
          'disk_iord_ticks'       => $data->{vm}->{$vmKey}->{$timeKey}->{disk_iord_ticks},
          'disk_rd_sectors'       => $data->{vm}->{$vmKey}->{$timeKey}->{disk_rd_sectors},
          'disk_wr_sectors'       => $data->{vm}->{$vmKey}->{$timeKey}->{disk_wr_sectors},
          'disk_tot_ticks'        => $data->{vm}->{$vmKey}->{$timeKey}->{disk_tot_ticks},
          'nic_byte_in'           => $data->{vm}->{$vmKey}->{$timeKey}->{nic_byte_in},
          'nic_byte_out'          => $data->{vm}->{$vmKey}->{$timeKey}->{nic_byte_out},
          'nic_byte_in_out'       => $data->{vm}->{$vmKey}->{$timeKey}->{nic_byte_in_out},
          'nic_rx_drop_pkt_speed' => $data->{vm}->{$vmKey}->{$timeKey}->{nic_rx_drop_pkt_speed},
          'nic_tx_drop_pkt_speed' => $data->{vm}->{$vmKey}->{$timeKey}->{nic_tx_drop_pkt_speed}
        );
        if ( FusionComputeLoadDataModule::update_rrd_vm( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  # datastores
  FusionCompute::log("Datastores: pushing data to rrd");
  foreach my $dataKey ( keys %{ $data->{datastore} } ) {

    $rrd_filepath = FusionComputeDataWrapper::get_filepath_rrd( { 'type' => 'datastore', 'uuid' => $dataKey } );
    unless ( -f $rrd_filepath ) {
      if ( FusionComputeLoadDataModule::create_rrd_datastore( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{datastore}->{$dataKey} } ) {
        %updates = (
          'total' => $data->{datastore}->{$dataKey}->{$timeKey}->{capacityGB},
          'used'  => $data->{datastore}->{$dataKey}->{$timeKey}->{usedSizeGB},
          'free'  => $data->{datastore}->{$dataKey}->{$timeKey}->{freeSizeGB},
        );
        if ( FusionComputeLoadDataModule::update_rrd_datastore( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  unless ($has_failed) {
    backup_perf_file($file);
  }
}

sub backup_perf_file {
  my $src_file = shift;
  my $alias    = ( split( '_', $src_file ) )[0];
  my $source   = "$json_dir/$src_file";
  my $target1  = "$tmpdir/fusioncompute-$alias-perf-last1.json";
  my $target2  = "$tmpdir/fusioncompute-$alias-perf-last2.json";

  if ( -f $target1 ) {
    move( $target1, $target2 ) or die "error: cannot replace the old backup data file: $!";
  }
  move( $source, $target1 ) or die "error: cannot backup the data file: $!";
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print STDERR "$act_time: $text : $!\n";
  return 1;
}

print "\n";
