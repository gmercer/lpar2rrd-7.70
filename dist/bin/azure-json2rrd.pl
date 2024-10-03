# azure-json2rrd.pl
# store Azure data

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;

use File::Copy;
use JSON;
use RRDp;
use HostCfg;
use AzureDataWrapper;
use AzureLoadDataModule;
use Xorux_lib qw(write_json);

use Data::Dumper;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir   = $ENV{INPUTDIR};
my $data_dir   = "$inputdir/data/Azure";
my $json_dir   = "$data_dir/json";
my $vm_dir     = "$data_dir/vm";
my $app_dir    = "$data_dir/app";
my $region_dir = "$data_dir/region";
my $tmpdir     = "$inputdir/tmp";

if ( keys %{ HostCfg::getHostConnections('Azure') } == 0 ) {
  exit(0);
}

unless ( -d $vm_dir ) {
  mkdir( "$vm_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $vm_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $app_dir ) {
  mkdir( "$app_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $app_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $region_dir ) {
  mkdir( "$region_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $region_dir: $!" . __FILE__ . ':' . __LINE__ );
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

  print "\nFile processing              : $file, " . localtime();

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

  #compute engine
  print "\nVirtual Machines             : pushing data to rrd, " . localtime();

  foreach my $vmKey ( keys %{ $data->{vm} } ) {
    $rrd_filepath = AzureDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $vmKey } );
    unless ( -f $rrd_filepath ) {
      if ( AzureLoadDataModule::create_rrd_vm( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{vm}->{$vmKey} } ) {
        %updates = ( 'cpu_usage_percent' => $data->{vm}->{$vmKey}->{$timeKey}->{cpu_util}, 'disk_read_ops' => $data->{vm}->{$vmKey}->{$timeKey}->{read_ops}, 'disk_write_ops' => $data->{vm}->{$vmKey}->{$timeKey}->{write_ops}, 'disk_read_bytes' => $data->{vm}->{$vmKey}->{$timeKey}->{read_bytes}, 'disk_write_bytes' => $data->{vm}->{$vmKey}->{$timeKey}->{write_bytes}, 'network_in' => $data->{vm}->{$vmKey}->{$timeKey}->{received_bytes}, 'network_out' => $data->{vm}->{$vmKey}->{$timeKey}->{sent_bytes}, 'mem_free' => $data->{vm}->{$vmKey}->{$timeKey}->{freeMemory}, 'mem_used' => $data->{vm}->{$vmKey}->{$timeKey}->{usedMemory} );

        if ( AzureLoadDataModule::update_rrd_vm( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #region
  print "\nRegion                       : pushing data to rrd, " . localtime();

  foreach my $regionKey ( keys %{ $data->{region} } ) {
    $rrd_filepath = AzureDataWrapper::get_filepath_rrd( { type => 'region', uuid => $regionKey } );
    unless ( -f $rrd_filepath ) {
      if ( AzureLoadDataModule::create_rrd_region( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      %updates = ( 'instances_running' => $data->{region}->{$regionKey}->{running}, 'instances_stopped' => $data->{region}->{$regionKey}->{stopped} );
      my $timestamp_region = time();

      if ( AzureLoadDataModule::update_rrd_region( $rrd_filepath, $timestamp_region, \%updates ) ) {
        $has_failed = 1;
      }
    }
  }

  #app services
  print "\nApp Services                 : pushing data to rrd, " . localtime();

  foreach my $appKey ( keys %{ $data->{appService} } ) {
    $rrd_filepath = AzureDataWrapper::get_filepath_rrd( { type => 'app', uuid => $appKey } );
    unless ( -f $rrd_filepath ) {
      if ( AzureLoadDataModule::create_rrd_app( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{appService}->{$appKey} } ) {
        %updates = ( 'cpu_time' => $data->{appService}->{$appKey}->{$timeKey}->{cpu_time}, 'requests' => $data->{appService}->{$appKey}->{$timeKey}->{requests}, 'read_bytes' => $data->{appService}->{$appKey}->{$timeKey}->{read_bytes}, 'write_bytes' => $data->{appService}->{$appKey}->{$timeKey}->{write_bytes}, 'read_ops' => $data->{appService}->{$appKey}->{$timeKey}->{read_ops}, 'write_ops' => $data->{appService}->{$appKey}->{$timeKey}->{write_ops}, 'received_bytes' => $data->{appService}->{$appKey}->{$timeKey}->{received_bytes}, 'sent_bytes' => $data->{appService}->{$appKey}->{$timeKey}->{sent_bytes}, 'http_2xx' => $data->{appService}->{$appKey}->{$timeKey}->{http_2xx}, 'http_3xx' => $data->{appService}->{$appKey}->{$timeKey}->{http_3xx}, 'http_4xx' => $data->{appService}->{$appKey}->{$timeKey}->{http_4xx}, 'http_5xx' => $data->{appService}->{$appKey}->{$timeKey}->{http_5xx}, 'response' => $data->{appService}->{$appKey}->{$timeKey}->{response}, 'connections' => $data->{appService}->{$appKey}->{$timeKey}->{connections}, 'filesystem_usage' => $data->{appService}->{$appKey}->{$timeKey}->{filesystem_usage} );

        if ( AzureLoadDataModule::update_rrd_app( $rrd_filepath, $timeKey, \%updates ) ) {
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
  my $target1  = "$tmpdir/azure-$alias-perf-last1.json";
  my $target2  = "$tmpdir/azure-$alias-perf-last2.json";

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
