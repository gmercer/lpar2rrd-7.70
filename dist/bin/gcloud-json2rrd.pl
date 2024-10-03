# gcloud-json2rrd.pl
# store GCloud data

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;

use File::Copy;
use JSON;
use RRDp;
use HostCfg;
use GCloudDataWrapper;
use GCloudLoadDataModule;
use Xorux_lib qw(write_json);

use Data::Dumper;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir     = $ENV{INPUTDIR};
my $data_dir     = "$inputdir/data/GCloud";
my $json_dir     = "$data_dir/json";
my $compute_dir  = "$data_dir/compute";
my $tmpdir       = "$inputdir/tmp";
my $region_dir   = "$data_dir/region";
my $database_dir = "$data_dir/database";

if ( keys %{ HostCfg::getHostConnections('GCloud') } == 0 ) {
  exit(0);
}

unless ( -d $compute_dir ) {
  mkdir( "$compute_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $compute_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $region_dir ) {
  mkdir( "$region_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $region_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $database_dir ) {
  mkdir( "$database_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $database_dir: $!" . __FILE__ . ':' . __LINE__ );
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
  }
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file $file: missing data" ) && next;
  }

  my %updates;
  my $rrd_filepath;

  #compute engine
  print "\nCompute engine               : pushing data to rrd, " . localtime();

  foreach my $computeKey ( keys %{ $data->{compute} } ) {
    $rrd_filepath = GCloudDataWrapper::get_filepath_rrd( { type => 'compute', uuid => $computeKey } );
    unless ( -f $rrd_filepath ) {
      if ( GCloudLoadDataModule::create_rrd_compute( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{compute}->{$computeKey} } ) {
        %updates = ( 'cpu_usage_percent' => $data->{compute}->{$computeKey}->{$timeKey}->{cpu_util}, 'disk_read_ops' => $data->{compute}->{$computeKey}->{$timeKey}->{read_ops}, 'disk_write_ops' => $data->{compute}->{$computeKey}->{$timeKey}->{write_ops}, 'disk_read_bytes' => $data->{compute}->{$computeKey}->{$timeKey}->{read_bytes}, 'disk_write_bytes' => $data->{compute}->{$computeKey}->{$timeKey}->{write_bytes}, 'network_in' => $data->{compute}->{$computeKey}->{$timeKey}->{received_bytes}, 'network_out' => $data->{compute}->{$computeKey}->{$timeKey}->{sent_bytes}, 'mem_used' => $data->{compute}->{$computeKey}->{$timeKey}->{mem_used}, 'mem_usage' => $data->{compute}->{$computeKey}->{$timeKey}->{mem_usage}, 'process_run' => $data->{compute}->{$computeKey}->{$timeKey}->{process}->{running}, 'process_pag' => $data->{compute}->{$computeKey}->{$timeKey}->{process}->{paging}, 'process_sto' => $data->{compute}->{$computeKey}->{$timeKey}->{process}->{stopped}, 'process_blo' => $data->{compute}->{$computeKey}->{$timeKey}->{process}->{blocked}, 'process_zom' => $data->{compute}->{$computeKey}->{$timeKey}->{process}->{zombies}, 'process_sle' => $data->{compute}->{$computeKey}->{$timeKey}->{process}->{sleeping} );

        if ( GCloudLoadDataModule::update_rrd_compute( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #databases
  print "\nGoogle SQL                   : pushing data to rrd, " . localtime();

  foreach my $databaseKey ( keys %{ $data->{database} } ) {
    my $engine = GCloudDataWrapper::get_engine($databaseKey);
    if ( !defined $engine ) { next; }

    $rrd_filepath = GCloudDataWrapper::get_filepath_rrd( { type => 'database', uuid => $databaseKey } );
    unless ( -f $rrd_filepath ) {
      if ( $engine eq "mysql" ) {
        if ( GCloudLoadDataModule::create_rrd_mysql( $rrd_filepath, $rrd_start_time ) ) {
          $has_failed = 1;
        }
      }
      elsif ( $engine eq "postgres" ) {
        if ( GCloudLoadDataModule::create_rrd_postgres( $rrd_filepath, $rrd_start_time ) ) {
          $has_failed = 1;
        }
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{database}->{$databaseKey} } ) {
        if ( !defined $engine ) { next; }
        if ( $engine eq "postgres" ) {
          %updates = ( 'cpu_util' => $data->{database}->{$databaseKey}->{$timeKey}->{cpu_util}, 'read_ops' => $data->{database}->{$databaseKey}->{$timeKey}->{read_ops}, 'write_ops' => $data->{database}->{$databaseKey}->{$timeKey}->{write_ops}, 'network_in' => $data->{database}->{$databaseKey}->{$timeKey}->{received_bytes}, 'network_out' => $data->{database}->{$databaseKey}->{$timeKey}->{sent_bytes}, 'disk_quota' => $data->{database}->{$databaseKey}->{$timeKey}->{disk_quota}, 'disk_used' => $data->{database}->{$databaseKey}->{$timeKey}->{disk_used}, 'mem_used' => $data->{database}->{$databaseKey}->{$timeKey}->{mem_used}, 'mem_total' => $data->{database}->{$databaseKey}->{$timeKey}->{mem_total}, 'connections' => $data->{database}->{$databaseKey}->{$timeKey}->{connections}, 'transaction_count' => $data->{database}->{$databaseKey}->{$timeKey}->{transaction_count} );
          if ( GCloudLoadDataModule::update_rrd_postgres( $rrd_filepath, $timeKey, \%updates ) ) {
            $has_failed = 1;
          }
        }
        elsif ( $engine eq "mysql" ) {
          %updates = ( 'cpu_util' => $data->{database}->{$databaseKey}->{$timeKey}->{cpu_util}, 'read_ops' => $data->{database}->{$databaseKey}->{$timeKey}->{read_ops}, 'write_ops' => $data->{database}->{$databaseKey}->{$timeKey}->{write_ops}, 'network_in' => $data->{database}->{$databaseKey}->{$timeKey}->{received_bytes}, 'network_out' => $data->{database}->{$databaseKey}->{$timeKey}->{sent_bytes}, 'disk_quota' => $data->{database}->{$databaseKey}->{$timeKey}->{disk_quota}, 'disk_used' => $data->{database}->{$databaseKey}->{$timeKey}->{disk_used}, 'mem_used' => $data->{database}->{$databaseKey}->{$timeKey}->{mem_used}, 'mem_total' => $data->{database}->{$databaseKey}->{$timeKey}->{mem_total}, 'connections' => $data->{database}->{$databaseKey}->{$timeKey}->{connections}, 'questions' => $data->{database}->{$databaseKey}->{$timeKey}->{questions}, 'queries' => $data->{database}->{$databaseKey}->{$timeKey}->{queries}, 'innodb_read' => $data->{database}->{$databaseKey}->{$timeKey}->{innodb_read}, 'innodb_write' => $data->{database}->{$databaseKey}->{$timeKey}->{innodb_write}, 'innodb_buffer_free' => $data->{database}->{$databaseKey}->{$timeKey}->{innodb_buffer_free}, 'innodb_buffer_total' => $data->{database}->{$databaseKey}->{$timeKey}->{innodb_buffer_total}, 'innodb_os_fsyncs' => $data->{database}->{$databaseKey}->{$timeKey}->{innodb_os_fsyncs}, 'innodb_data_fsyncs' => $data->{database}->{$databaseKey}->{$timeKey}->{innodb_data_fsyncs} );
          if ( GCloudLoadDataModule::update_rrd_mysql( $rrd_filepath, $timeKey, \%updates ) ) {
            $has_failed = 1;
          }
        }
      }
    }
  }

  #region
  print "\nRegion                      : pushing data to rrd, " . localtime();

  foreach my $regionKey ( keys %{ $data->{region} } ) {
    $rrd_filepath = GCloudDataWrapper::get_filepath_rrd( { type => 'region', uuid => $regionKey } );
    unless ( -f $rrd_filepath ) {
      if ( GCloudLoadDataModule::create_rrd_region( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      %updates = ( 'instances_running' => $data->{region}->{$regionKey}->{running}, 'instances_stopped' => $data->{region}->{$regionKey}->{stopped} );
      my $timestamp_region = time();

      if ( GCloudLoadDataModule::update_rrd_region( $rrd_filepath, $timestamp_region, \%updates ) ) {
        $has_failed = 1;
      }
    }
  }

  unless ($has_failed) {
    backup_perf_file($file);
  }

}

################################################################################

sub backup_perf_file {

  # expects file name for the file, that's supposed to be moved from XEN_iostats/
  #     with file name "XEN_alias_hostname_perf_timestamp.json"
  my $src_file = shift;
  my $alias    = ( split( '_', $src_file ) )[1];
  my $source   = "$json_dir/$src_file";
  my $target1  = "$tmpdir/gcloud-$alias-perf-last1.json";
  my $target2  = "$tmpdir/gcloud-$alias-perf-last2.json";

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
