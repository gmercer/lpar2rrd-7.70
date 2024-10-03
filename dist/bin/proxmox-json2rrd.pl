# proxmox-json2rrd.pl
# store Proxmox data

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;

use File::Copy;
use JSON;
use RRDp;
use HostCfg;
use ProxmoxDataWrapper;
use ProxmoxLoadDataModule;
use Xorux_lib qw(write_json);

use Data::Dumper;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir    = $ENV{INPUTDIR};
my $data_dir    = "$inputdir/data/Proxmox";
my $json_dir    = "$data_dir/json";
my $node_dir    = "$data_dir/Node";
my $vm_dir      = "$data_dir/VM";
my $lxc_dir     = "$data_dir/LXC";
my $storage_dir = "$data_dir/Storage";
my $tmpdir      = "$inputdir/tmp";

if ( keys %{ HostCfg::getHostConnections('Proxmox') } == 0 ) {
  exit(0);
}

unless ( -d $node_dir ) {
  mkdir( "$node_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $node_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $vm_dir ) {
  mkdir( "$vm_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $vm_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $lxc_dir ) {
  mkdir( "$lxc_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $lxc_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $storage_dir ) {
  mkdir( "$storage_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $storage_dir: $!" . __FILE__ . ':' . __LINE__ );
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
my $data;

opendir( DH, $json_dir ) || die "Could not open '$json_dir' for reading '$!'\n";
@files = grep /.*.json/, readdir DH;

#@files = glob( $json_dir . '/*' );
foreach my $file ( sort @files ) {

  my $has_failed = 0;
  my @splits     = split /_/, $file;

  print "\nFile processing           : $file, " . localtime();

  my $timestamp = my $rrd_start_time = time() - 4200;

  # read file
  my $json = '';
  if ( open( my $fh, '<', "$json_dir/$file" ) ) {
    while ( my $row = <$fh> ) {
      chomp $row;
      $json .= $row;
    }
    close($fh);
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

  #node
  print "\nNode                      : pushing data to rrd, " . localtime();

  foreach my $nodeKey ( keys %{ $data->{node} } ) {
    $rrd_filepath = ProxmoxDataWrapper::get_filepath_rrd( { type => 'node', uuid => $nodeKey } );
    unless ( -f $rrd_filepath ) {
      if ( ProxmoxLoadDataModule::create_rrd_node( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{node}->{$nodeKey} } ) {
        %updates = ( 'cpu' => $data->{node}->{$nodeKey}->{$timeKey}->{cpu}, 'loadavg' => $data->{node}->{$nodeKey}->{$timeKey}->{loadavg}, 'maxcpu' => $data->{node}->{$nodeKey}->{$timeKey}->{maxcpu}, 'memused' => $data->{node}->{$nodeKey}->{$timeKey}->{memused}, 'memtotal' => $data->{node}->{$nodeKey}->{$timeKey}->{memtotal}, 'iowait' => $data->{node}->{$nodeKey}->{$timeKey}->{iowait}, 'swapused' => $data->{node}->{$nodeKey}->{$timeKey}->{swapused}, 'swaptotal' => $data->{node}->{$nodeKey}->{$timeKey}->{swaptotal}, 'netin' => $data->{node}->{$nodeKey}->{$timeKey}->{netin}, 'netout' => $data->{node}->{$nodeKey}->{$timeKey}->{netout}, 'rootused' => $data->{node}->{$nodeKey}->{$timeKey}->{rootused}, 'roottotal' => $data->{node}->{$nodeKey}->{$timeKey}->{roottotal} );
        if ( ProxmoxLoadDataModule::update_rrd_node( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #vm
  print "\nVM                        : pushing data to rrd, " . localtime();

  foreach my $vmKey ( keys %{ $data->{vm} } ) {
    $rrd_filepath = ProxmoxDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $vmKey } );
    unless ( -f $rrd_filepath ) {
      if ( ProxmoxLoadDataModule::create_rrd_vm( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{vm}->{$vmKey} } ) {
        %updates = ( 'cpu' => $data->{vm}->{$vmKey}->{$timeKey}->{cpu}, 'maxcpu' => $data->{vm}->{$vmKey}->{$timeKey}->{maxcpu}, 'mem' => $data->{vm}->{$vmKey}->{$timeKey}->{mem}, 'maxmem' => $data->{vm}->{$vmKey}->{$timeKey}->{maxmem}, 'netin' => $data->{vm}->{$vmKey}->{$timeKey}->{netin}, 'netout' => $data->{vm}->{$vmKey}->{$timeKey}->{netout}, 'diskread' => $data->{vm}->{$vmKey}->{$timeKey}->{diskread}, 'diskwrite' => $data->{vm}->{$vmKey}->{$timeKey}->{diskwrite} );
        if ( ProxmoxLoadDataModule::update_rrd_vm( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #lxc
  print "\nLXC                       : pushing data to rrd, " . localtime();

  foreach my $lxcKey ( keys %{ $data->{lxc} } ) {
    $rrd_filepath = ProxmoxDataWrapper::get_filepath_rrd( { type => 'lxc', uuid => $lxcKey } );
    unless ( -f $rrd_filepath ) {
      if ( ProxmoxLoadDataModule::create_rrd_vm( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{lxc}->{$lxcKey} } ) {
        %updates = ( 'cpu' => $data->{lxc}->{$lxcKey}->{$timeKey}->{cpu}, 'maxcpu' => $data->{lxc}->{$lxcKey}->{$timeKey}->{maxcpu}, 'mem' => $data->{lxc}->{$lxcKey}->{$timeKey}->{mem}, 'maxmem' => $data->{lxc}->{$lxcKey}->{$timeKey}->{maxmem}, 'netin' => $data->{lxc}->{$lxcKey}->{$timeKey}->{netin}, 'netout' => $data->{lxc}->{$lxcKey}->{$timeKey}->{netout}, 'diskread' => $data->{lxc}->{$lxcKey}->{$timeKey}->{diskread}, 'diskwrite' => $data->{lxc}->{$lxcKey}->{$timeKey}->{diskwrite} );
        if ( ProxmoxLoadDataModule::update_rrd_vm( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #storage
  print "\nStorage                   : pushing data to rrd, " . localtime();

  foreach my $storageKey ( keys %{ $data->{storage} } ) {
    $rrd_filepath = ProxmoxDataWrapper::get_filepath_rrd( { type => 'storage', uuid => $storageKey } );
    unless ( -f $rrd_filepath ) {
      if ( ProxmoxLoadDataModule::create_rrd_storage( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{storage}->{$storageKey} } ) {
        %updates = ( 'used' => $data->{storage}->{$storageKey}->{$timeKey}->{used}, 'total' => $data->{storage}->{$storageKey}->{$timeKey}->{total} );
        if ( ProxmoxLoadDataModule::update_rrd_storage( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  unless ($has_failed) {
    backup_perf_file($file);
  }

}

################################################################################

sub backup_perf_file {

  my $src_file = shift;
  my $alias    = ( split( '_', $src_file ) )[1];
  my $source   = "$json_dir/$src_file";
  my $target1  = "$tmpdir/proxmox-$alias-perf-last1.json";
  my $target2  = "$tmpdir/proxmox-$alias-perf-last2.json";

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
