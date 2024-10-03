#cloudstack-json2rrd.pl
# store Cloudstack data

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;

use File::Copy;
use JSON;
use RRDp;
use HostCfg;
use CloudstackDataWrapper;
use CloudstackLoadDataModule;
use Xorux_lib qw(write_json);

use Data::Dumper;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir           = $ENV{INPUTDIR};
my $data_dir           = "$inputdir/data/Cloudstack";
my $json_dir           = "$data_dir/json";
my $host_dir           = "$data_dir/Host";
my $instance_dir       = "$data_dir/Instance";
my $volume_dir         = "$data_dir/Volume";
my $primaryStorage_dir = "$data_dir/PrimaryStorage";
my $tmpdir             = "$inputdir/tmp";

if ( keys %{ HostCfg::getHostConnections('Cloudstack') } == 0 ) {
  exit(0);
}

unless ( -d $host_dir ) {
  mkdir( "$host_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $host_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $instance_dir ) {
  mkdir( "$instance_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $instance_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $volume_dir ) {
  mkdir( "$volume_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $volume_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $primaryStorage_dir ) {
  mkdir( "$primaryStorage_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $primaryStorage_dir: $!" . __FILE__ . ':' . __LINE__ );
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

  #host
  print "\nHost                      : pushing data to rrd, " . localtime();

  foreach my $hostKey ( keys %{ $data->{host} } ) {
    $rrd_filepath = CloudstackDataWrapper::get_filepath_rrd( { type => 'host', uuid => $hostKey } );
    unless ( -f $rrd_filepath ) {
      if ( CloudstackLoadDataModule::create_rrd_host( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{host}->{$hostKey} } ) {
        %updates = ( 'cpuusedghz' => $data->{host}->{$hostKey}->{$timeKey}->{cpuusedghz}, 'cputotalghz' => $data->{host}->{$hostKey}->{$timeKey}->{cputotalghz}, 'cpuused' => $data->{host}->{$hostKey}->{$timeKey}->{cpuused}, 'cpunumber' => $data->{host}->{$hostKey}->{$timeKey}->{cpunumber}, 'memoryused' => $data->{host}->{$hostKey}->{$timeKey}->{memoryused}, 'memoryallocated' => $data->{host}->{$hostKey}->{$timeKey}->{memoryallocated}, 'memorytotal' => $data->{host}->{$hostKey}->{$timeKey}->{memorytotal}, 'networkkbswrite' => $data->{host}->{$hostKey}->{$timeKey}->{networkkbswrite}, 'networkkbsread' => $data->{host}->{$hostKey}->{$timeKey}->{networkkbsread} );
        if ( CloudstackLoadDataModule::update_rrd_host( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #instance
  print "\nInstance                  : pushing data to rrd, " . localtime();

  foreach my $instanceKey ( keys %{ $data->{instance} } ) {
    $rrd_filepath = CloudstackDataWrapper::get_filepath_rrd( { type => 'instance', uuid => $instanceKey } );
    unless ( -f $rrd_filepath ) {
      if ( CloudstackLoadDataModule::create_rrd_instance( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{instance}->{$instanceKey} } ) {
        %updates = ( 'cpuused' => $data->{instance}->{$instanceKey}->{$timeKey}->{cpuused}, 'cpuspeed' => $data->{instance}->{$instanceKey}->{$timeKey}->{cpuspeed}, 'memoryintfreekbs' => $data->{instance}->{$instanceKey}->{$timeKey}->{memoryintfreekbs}, 'memory' => $data->{instance}->{$instanceKey}->{$timeKey}->{memory}, 'diskkbswrite' => $data->{instance}->{$instanceKey}->{$timeKey}->{diskkbswrite}, 'diskkbsread' => $data->{instance}->{$instanceKey}->{$timeKey}->{diskkbsread}, 'diskiopstotal' => $data->{instance}->{$instanceKey}->{$timeKey}->{diskiopstotal}, 'diskiowrite' => $data->{instance}->{$instanceKey}->{$timeKey}->{diskiowrite}, 'diskioread' => $data->{instance}->{$instanceKey}->{$timeKey}->{diskioread}, 'networkread' => $data->{instance}->{$instanceKey}->{$timeKey}->{networkread}, 'networkwrite' => $data->{instance}->{$instanceKey}->{$timeKey}->{networkwrite}, 'networkkbsread' => $data->{instance}->{$instanceKey}->{$timeKey}->{networkkbsread}, 'networkkbswrite' => $data->{instance}->{$instanceKey}->{$timeKey}->{networkkbswrite} );
        if ( CloudstackLoadDataModule::update_rrd_instance( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #volume
  print "\nVolume                    : pushing data to rrd, " . localtime();

  foreach my $volumeKey ( keys %{ $data->{volume} } ) {
    $rrd_filepath = CloudstackDataWrapper::get_filepath_rrd( { type => 'volume', uuid => $volumeKey } );
    unless ( -f $rrd_filepath ) {
      if ( CloudstackLoadDataModule::create_rrd_volume( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{volume}->{$volumeKey} } ) {
        %updates = ( 'utilization' => $data->{volume}->{$volumeKey}->{$timeKey}->{utilization}, 'physicalsize' => $data->{volume}->{$volumeKey}->{$timeKey}->{physicalsize}, 'size' => $data->{volume}->{$volumeKey}->{$timeKey}->{size}, 'virtualsize' => $data->{volume}->{$volumeKey}->{$timeKey}->{virtualsize}, 'diskiowrite' => $data->{volume}->{$volumeKey}->{$timeKey}->{diskiowrite}, 'diskioread' => $data->{volume}->{$volumeKey}->{$timeKey}->{diskioread}, 'diskiopstotal' => $data->{volume}->{$volumeKey}->{$timeKey}->{diskiopstotal}, 'diskkbswrite' => $data->{volume}->{$volumeKey}->{$timeKey}->{diskkbswrite}, 'diskkbsread' => $data->{volume}->{$volumeKey}->{$timeKey}->{diskkbsread} );
        if ( CloudstackLoadDataModule::update_rrd_volume( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #primaryStorage
  print "\nPrimary Storage           : pushing data to rrd, " . localtime();

  foreach my $storageKey ( keys %{ $data->{primaryStorage} } ) {
    $rrd_filepath = CloudstackDataWrapper::get_filepath_rrd( { type => 'primaryStorage', uuid => $storageKey } );
    unless ( -f $rrd_filepath ) {
      if ( CloudstackLoadDataModule::create_rrd_primaryStorage( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{primaryStorage}->{$storageKey} } ) {
        %updates = ( 'disksizetotalgb' => $data->{primaryStorage}->{$storageKey}->{$timeKey}->{disksizetotalgb}, 'disksizeusedgb' => $data->{primaryStorage}->{$storageKey}->{$timeKey}->{disksizeusedgb}, 'disksizeallocatedgb' => $data->{primaryStorage}->{$storageKey}->{$timeKey}->{disksizeallocatedgb}, 'disksizeunallocatedgb' => $data->{primaryStorage}->{$storageKey}->{$timeKey}->{disksizeunallocatedgb}, 'overprovisioning' => $data->{primaryStorage}->{$storageKey}->{$timeKey}->{overprovisioning} );
        if ( CloudstackLoadDataModule::update_rrd_primaryStorage( $rrd_filepath, $timeKey, \%updates ) ) {
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
  my $target1  = "$tmpdir/cloudstack-$alias-perf-last1.json";
  my $target2  = "$tmpdir/cloudstack-$alias-perf-last2.json";

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
