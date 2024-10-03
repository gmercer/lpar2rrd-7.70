# nutanix-json2rrd.pl
# store Nutanix data

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;

use File::Copy;
use JSON;
use RRDp;
use Nutanix;

use NutanixDataWrapper;
use NutanixLoadDataModule;
use Xorux_lib qw(write_json);
use HostCfg;

use Data::Dumper;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('Nutanix') } == 0 ) {
  exit(0);
}

# data file paths
my $inputdir    = $ENV{INPUTDIR};
my $nutanix_dir = "$inputdir/data/NUTANIX";
my $json_dir    = "$nutanix_dir/json";
my $tmpdir      = "$inputdir/tmp";
my $linux_dir   = "$inputdir/data/Linux/no_hmc";

my $hosts_path      = "$nutanix_dir/HOST";
my $vms_path        = "$nutanix_dir/VM";
my $containers_path = "$nutanix_dir/SC";
my $pools_path      = "$nutanix_dir/SP";
my $vdisks_path     = "$nutanix_dir/VD";

# create directories/
my @create_dir = ( $hosts_path, $vms_path, $containers_path, $pools_path, $vdisks_path );
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

my $uuids = NutanixDataWrapper::get_labels();
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

#save to JSON
open my $fh, ">", $nutanix_dir . "/mapping.json";
print $fh JSON->new->pretty->encode( \%mapping );
close $fh;

my $data;
opendir( DH, $json_dir ) || die "Could not open '$json_dir' for reading '$!'\n";
@files = grep /.*.json/, readdir DH;

#@files = glob( $json_dir . '/*' );
foreach my $file ( sort @files ) {
  my $has_failed = 0;

  my @splits = split /_/, $file;

  Nutanix::log("File processing: $file");

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

  # hosts
  Nutanix::log("Nodes: pushing data to rrd");
  foreach my $hostKey ( keys %{ $data->{nodes} } ) {

    unless ( -d $hosts_path . "/" . $hostKey ) {
      mkdir( $hosts_path . "/" . $hostKey, 0755 ) || warn( localtime() . ": Cannot mkdir " . $hosts_path . "/" . $hostKey . ": $!" . __FILE__ . ':' . __LINE__ );
    }

    $rrd_filepath = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'host', 'uuid' => $hostKey } );
    unless ( -f $rrd_filepath ) {
      if ( NutanixLoadDataModule::create_rrd_host( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{nodes}->{$hostKey} } ) {
        %updates = ( 'cpu_usage_percent' => $data->{nodes}->{$hostKey}->{$timeKey}->{hypervisor_cpu_usage_ppm}, 'cpu_cores' => $data->{nodes}->{$hostKey}->{$timeKey}->{cpu_cores}, 'memory' => $data->{nodes}->{$hostKey}->{$timeKey}->{memory} / ( 1024 * 1024 ), 'memory_usage_percent' => $data->{nodes}->{$hostKey}->{$timeKey}->{hypervisor_memory_usage_ppm} );
        if ( NutanixLoadDataModule::update_rrd_host( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  # disks
  Nutanix::log("Disks: pushing data to rrd");
  foreach my $diskKey ( keys %{ $data->{disks} } ) {

    $rrd_filepath = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'disk', 'uuid' => $diskKey, 'parent' => $data->{'disk_node'}{$diskKey} } );
    unless ( -f $rrd_filepath ) {
      if ( NutanixLoadDataModule::create_rrd_host_disk( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{disks}->{$diskKey} } ) {
        %updates = ( 'iowait' => 0, 'iops_total' => $data->{disks}->{$diskKey}->{$timeKey}->{num_io}, 'iops_read' => $data->{disks}->{$diskKey}->{$timeKey}->{num_read_io}, 'iops_write' => $data->{disks}->{$diskKey}->{$timeKey}->{num_io}, 'io_throughput_total' => 0, 'io_throughput_read' => 0, 'io_throughput_write' => 0, 'read_latency' => 0, 'write_latency' => 0, 'total_latency' => $data->{disks}->{$diskKey}->{$timeKey}->{avg_io_latency_usecs}, 'read' => $data->{disks}->{$diskKey}->{$timeKey}->{read_io_bandwidth_kBps}, 'write' => $data->{disks}->{$diskKey}->{$timeKey}->{write_io_bandwidth_kBps} );
        if ( NutanixLoadDataModule::update_rrd_host_disk( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  # vms
  Nutanix::log("VMs: pushing data to rrd");
  foreach my $vmKey ( keys %{ $data->{vms} } ) {

    $rrd_filepath = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'vm', 'uuid' => $vmKey } );
    unless ( -f $rrd_filepath ) {
      if ( NutanixLoadDataModule::create_rrd_vm( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{vms}->{$vmKey} } ) {
        my ( $memfree, $mem );
        if ( defined $data->{vms}->{$vmKey}->{$timeKey}->{memory_usage_ppm} && defined $data->{vms}->{$vmKey}->{$timeKey}->{memory} ) {
          $memfree = ( $data->{vms}->{$vmKey}->{$timeKey}->{memory} ) * ( 1 - ( $data->{vms}->{$vmKey}->{$timeKey}->{memory_usage_ppm} / 1000000 ) );
          $mem     = $data->{vms}->{$vmKey}->{$timeKey}->{memory};
        }
        %updates = ( 'cpu_percent' => $data->{vms}->{$vmKey}->{$timeKey}->{hypervisor_cpu_usage_ppm}, 'cpu_cores' => $data->{vms}->{$vmKey}->{$timeKey}->{cpu_cores}, 'cpu_core_count' => $data->{vms}->{$vmKey}->{$timeKey}->{cpu_cores}, 'memory' => $mem, 'memory_internal_free' => $memfree, 'memory_target' => 0, 'transmitted' => $data->{vms}->{$vmKey}->{$timeKey}->{hypervisor_num_transmitted_bytes}, 'received' => $data->{vms}->{$vmKey}->{$timeKey}->{hypervisor_num_received_bytes}, 'iops_total' => 0, 'iops_read' => $data->{vms}->{$vmKey}->{$timeKey}->{controller_num_read_io}, 'iops_write' => $data->{vms}->{$vmKey}->{$timeKey}->{controller_num_write_io}, 'io_throughput_total' => 0, 'io_throughput_read' => 0, 'io_throughput_write' => 0, 'iowait' => 0, 'read_latency' => $data->{vms}->{$vmKey}->{$timeKey}->{controller_avg_read_io_latency_usecs}, 'write_latency' => $data->{vms}->{$vmKey}->{$timeKey}->{controller_avg_write_io_latency_usecs}, 'total' => $data->{vms}->{$vmKey}->{$timeKey}->{controller_io_bandwidth_kBps}, 'read' => $data->{vms}->{$vmKey}->{$timeKey}->{controller_read_io_bandwidth_kBps}, 'write' => $data->{vms}->{$vmKey}->{$timeKey}->{controller_write_io_bandwidth_kBps} );
        if ( NutanixLoadDataModule::update_rrd_vm( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  # storage containers
  Nutanix::log("Storage containers: pushing data to rrd");
  foreach my $scKey ( keys %{ $data->{containers} } ) {

    $rrd_filepath = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'container', 'uuid' => $scKey } );
    unless ( -f $rrd_filepath ) {
      if ( NutanixLoadDataModule::create_rrd_storage_container( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{containers}->{$scKey} } ) {
        %updates = ( 'iowait' => 0, 'iops_total' => $data->{containers}->{$scKey}->{$timeKey}->{controller_num_io}, 'iops_read' => $data->{containers}->{$scKey}->{$timeKey}->{controller_num_read_io}, 'iops_write' => $data->{containers}->{$scKey}->{$timeKey}->{controller_num_io}, 'io_throughput_total' => 0, 'io_throughput_read' => 0, 'io_throughput_write' => 0, 'read_latency' => 0, 'write_latency' => 0, 'total_latency' => $data->{containers}->{$scKey}->{$timeKey}->{controller_avg_io_latency_usecs}, 'read' => $data->{containers}->{$scKey}->{$timeKey}->{controller_read_io_bandwidth_kBps}, 'write' => $data->{containers}->{$scKey}->{$timeKey}->{controller_write_io_bandwidth_kBps} );
        if ( NutanixLoadDataModule::update_rrd_storage_container( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  # virtual disks
  Nutanix::log("Virtual disks: pushing data to rrd");
  foreach my $vdKey ( keys %{ $data->{vdisks} } ) {

    $rrd_filepath = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'vdisk', 'uuid' => $vdKey } );
    unless ( -f $rrd_filepath ) {
      if ( NutanixLoadDataModule::create_rrd_virtual_disk( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{vdisks}->{$vdKey} } ) {
        %updates = ( 'iowait' => 0, 'iops_total' => $data->{vdisks}->{$vdKey}->{$timeKey}->{controller_num_io}, 'iops_read' => $data->{vdisks}->{$vdKey}->{$timeKey}->{controller_num_read_io}, 'iops_write' => $data->{vdisks}->{$vdKey}->{$timeKey}->{controller_num_write_io}, 'io_throughput_total' => 0, 'io_throughput_read' => 0, 'io_throughput_write' => 0, 'read_latency' => 0, 'write_latency' => 0, 'total_latency' => $data->{vdisks}->{$vdKey}->{$timeKey}->{controller_avg_io_latency_usecs}, 'read' => $data->{vdisks}->{$vdKey}->{$timeKey}->{controller_read_io_bandwidth_kBps}, 'write' => $data->{vdisks}->{$vdKey}->{$timeKey}->{controller_write_io_bandwidth_kBps} );
        if ( NutanixLoadDataModule::update_rrd_virtual_disk( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  # storage pools
  Nutanix::log("Storage pools: pushing data to rrd");
  foreach my $spKey ( keys %{ $data->{pools} } ) {

    $rrd_filepath = NutanixDataWrapper::get_filepath_rrd( { 'type' => 'pool', 'uuid' => $spKey } );
    unless ( -f $rrd_filepath ) {
      if ( NutanixLoadDataModule::create_rrd_storage_pool( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }

    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{pools}->{$spKey} } ) {
        %updates = ( 'iowait' => 0, 'iops_total' => $data->{pools}->{$spKey}->{$timeKey}->{num_io}, 'iops_read' => $data->{pools}->{$spKey}->{$timeKey}->{num_read_io}, 'iops_write' => $data->{pools}->{$spKey}->{$timeKey}->{num_write_io}, 'io_throughput_total' => 0, 'io_throughput_read' => 0, 'io_throughput_write' => 0, 'read_latency' => 0, 'write_latency' => 0, 'total_latency' => $data->{pools}->{$spKey}->{$timeKey}->{avg_io_latency_usecs}, 'read' => $data->{pools}->{$spKey}->{$timeKey}->{read_io_bandwidth_kBps}, 'write' => $data->{pools}->{$spKey}->{$timeKey}->{write_io_bandwidth_kBps} );
        if ( NutanixLoadDataModule::update_rrd_storage_pool( $rrd_filepath, $timeKey, \%updates ) ) {
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

  # expects file name for the file, that's supposed to be moved from XEN_iostats/
  #     with file name "XEN_alias_hostname_perf_timestamp.json"
  my $src_file = shift;
  my $alias    = ( split( '_', $src_file ) )[0];
  my $source   = "$json_dir/$src_file";
  my $target1  = "$tmpdir/nutanix-$alias-perf-last1.json";
  my $target2  = "$tmpdir/nutanix-$alias-perf-last2.json";

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
