# aws-json2rrd.pl
# store AWS data

use 5.008_008;

use strict;
use warnings;

use HostCfg;
if ( keys %{ HostCfg::getHostConnections('AWS') } == 0 ) {
  exit(0);
}

use Data::Dumper;

use File::Copy;
use JSON;
use RRDp;
require AWSDataWrapper;
require AWSLoadDataModule;
require Xorux_lib;

use Data::Dumper;

defined $ENV{INPUTDIR} || warn( localtime() . ": INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir   = $ENV{INPUTDIR};
my $data_dir   = "$inputdir/data/AWS";
my $json_dir   = "$data_dir/json";
my $tmpdir     = "$inputdir/tmp";
my $ec2_dir    = "$data_dir/EC2";
my $ebs_dir    = "$data_dir/EBS";
my $rds_dir    = "$data_dir/RDS";
my $s3_dir     = "$data_dir/S3";
my $region_dir = "$data_dir/Region";
my $api_dir    = "$data_dir/API";
my $lambda_dir = "$data_dir/Lambda";

if ( keys %{ HostCfg::getHostConnections('AWS') } == 0 ) {
  exit(0);
}

unless ( -d $ec2_dir ) {
  mkdir( "$ec2_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $ec2_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $region_dir ) {
  mkdir( "$region_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $region_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $ebs_dir ) {
  mkdir( "$ebs_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $ebs_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $rds_dir ) {
  mkdir( "$rds_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $rds_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $s3_dir ) {
  mkdir( "$s3_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $s3_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $api_dir ) {
  mkdir( "$api_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $api_dir: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $lambda_dir ) {
  mkdir( "$lambda_dir", 0755 ) || warn( localtime() . ": Cannot mkdir $lambda_dir: $!" . __FILE__ . ':' . __LINE__ );
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

  #ec2
  print "\nEC2                       : pushing data to rrd, " . localtime();
  foreach my $ec2Key ( keys %{ $data->{ec2} } ) {
    $rrd_filepath = AWSDataWrapper::get_filepath_rrd( { type => 'ec2', uuid => $ec2Key } );
    unless ( -f $rrd_filepath ) {
      if ( AWSLoadDataModule::create_rrd_ec2( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{ec2}->{$ec2Key} } ) {
        %updates = ( 'cpu_usage_percent' => $data->{ec2}->{$ec2Key}->{$timeKey}->{CPUUtilization}, 'cpu_cores' => $data->{ec2}->{$ec2Key}->{$timeKey}->{cpu_count}, 'memory_total_mb' => 1, 'memory_free_mb' => 1, 'disk_read_ops' => $data->{ec2}->{$ec2Key}->{$timeKey}->{DiskReadOps}, 'disk_write_ops' => $data->{ec2}->{$ec2Key}->{$timeKey}->{DiskWriteOps}, 'disk_read_bytes' => $data->{ec2}->{$ec2Key}->{$timeKey}->{DiskReadBytes}, 'disk_write_bytes' => $data->{ec2}->{$ec2Key}->{$timeKey}->{DiskWriteBytes}, 'network_in' => $data->{ec2}->{$ec2Key}->{$timeKey}->{NetworkIn}, 'network_out' => $data->{ec2}->{$ec2Key}->{$timeKey}->{NetworkOut} );

        if ( AWSLoadDataModule::update_rrd_ec2( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #rds
  print "\nRDS                       : pushing data to rrd, " . localtime();
  foreach my $rdsKey ( keys %{ $data->{rds} } ) {
    $rrd_filepath = AWSDataWrapper::get_filepath_rrd( { type => 'rds', uuid => $rdsKey } );
    unless ( -f $rrd_filepath ) {
      if ( AWSLoadDataModule::create_rrd_rds( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{rds}->{$rdsKey} } ) {
        %updates = ( 'disk_read_latency' => $data->{rds}->{$rdsKey}->{$timeKey}->{ReadLatency}, 'disk_write_latency' => $data->{rds}->{$rdsKey}->{$timeKey}->{WriteLatency}, 'cpu_usage_percent' => $data->{rds}->{$rdsKey}->{$timeKey}->{CPUUtilization}, 'disk_read_ops' => $data->{rds}->{$rdsKey}->{$timeKey}->{ReadIOPS}, 'disk_write_ops' => $data->{rds}->{$rdsKey}->{$timeKey}->{WriteIOPS}, 'disk_read_bytes' => $data->{rds}->{$rdsKey}->{$timeKey}->{ReadThroughput}, 'disk_write_bytes' => $data->{rds}->{$rdsKey}->{$timeKey}->{WriteThroughput}, 'network_in' => $data->{rds}->{$rdsKey}->{$timeKey}->{NetworkReceiveThroughput}, 'network_out' => $data->{rds}->{$rdsKey}->{$timeKey}->{NetworkTransmitThroughput}, 'mem_free' => $data->{rds}->{$rdsKey}->{$timeKey}->{FreeableMemory}, 'disk_free' => $data->{rds}->{$rdsKey}->{$timeKey}->{FreeStorageSpace}, 'db_connection' => $data->{rds}->{$rdsKey}->{$timeKey}->{DatabaseConnections}, 'burst_balance' => $data->{rds}->{$rdsKey}->{$timeKey}->{BurstBalance} );

        if ( AWSLoadDataModule::update_rrd_rds( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #EBS
  print "\nEBS                       : pushing data to rrd, " . localtime();
  foreach my $ebsKey ( keys %{ $data->{volume} } ) {
    $rrd_filepath = AWSDataWrapper::get_filepath_rrd( { type => 'ebs', uuid => $ebsKey } );
    unless ( -f $rrd_filepath ) {
      if ( AWSLoadDataModule::create_rrd_volume( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{volume}->{$ebsKey} } ) {
        my $volReadOps  = 0;
        my $volWriteOps = 0;
        my $volWrite    = 0;
        my $volRead     = 0;
        if ( exists $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeReadOps} && exists $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeReadOps} ) {
          $volReadOps = $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeReadOps} / 300;
        }
        if ( exists $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeWriteOps} && exists $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeWriteOps} ) {
          $volWriteOps = $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeWriteOps} / 300;
        }
        if ( exists $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeWriteBytes} && exists $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeWriteBytes} ) {
          $volWrite = $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeWriteBytes} / 300;
        }
        if ( exists $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeReadBytes} && exists $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeReadBytes} ) {
          $volRead = $data->{volume}->{$ebsKey}->{$timeKey}->{VolumeReadBytes} / 300;
        }
        %updates = ( 'disk_read_ops' => $volReadOps, 'disk_write_ops' => $volWriteOps, 'disk_read_bytes' => $volRead, 'disk_write_bytes' => $volWrite );

        if ( AWSLoadDataModule::update_rrd_volume( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #S3
  print "\nS3                        : pushing data to rrd, " . localtime();
  foreach my $s3Key ( keys %{ $data->{s3} } ) {
    $rrd_filepath = AWSDataWrapper::get_filepath_rrd( { type => 's3', uuid => $s3Key } );
    unless ( -f $rrd_filepath ) {
      if ( AWSLoadDataModule::create_rrd_s3( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{s3}->{$s3Key} } ) {
        %updates = ( 'number_objects' => $data->{s3}->{$s3Key}->{$timeKey}->{NumberOfObjects}, 'bucket_size' => $data->{s3}->{$s3Key}->{$timeKey}->{BucketSizeBytes} );

        if ( AWSLoadDataModule::update_rrd_s3( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #API GATEWAY
  print "\nAPI GATEWAY               : pushing data to rrd, " . localtime();
  foreach my $apiKey ( keys %{ $data->{api} } ) {
    $rrd_filepath = AWSDataWrapper::get_filepath_rrd( { type => 'api', uuid => $apiKey } );
    unless ( -f $rrd_filepath ) {
      if ( AWSLoadDataModule::create_rrd_api( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{api}->{$apiKey} } ) {
        %updates = ( 'count' => $data->{api}->{$apiKey}->{$timeKey}->{Count}, 'latency' => $data->{api}->{$apiKey}->{$timeKey}->{Latency}, 'five_error' => $data->{api}->{$apiKey}->{$timeKey}->{"5XXError"}, 'four_error' => $data->{api}->{$apiKey}->{$timeKey}->{"4XXError"}, 'integration_latency' => $data->{api}->{$apiKey}->{$timeKey}->{'IntegrationLatency'} );

        if ( AWSLoadDataModule::update_rrd_api( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #LAMBDA
  print "\nLambda                    : pushing data to rrd, " . localtime();
  foreach my $lambdaKey ( keys %{ $data->{lambda} } ) {
    $rrd_filepath = AWSDataWrapper::get_filepath_rrd( { type => 'lambda', uuid => $lambdaKey } );
    unless ( -f $rrd_filepath ) {
      if ( AWSLoadDataModule::create_rrd_lambda( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      foreach my $timeKey ( sort keys %{ $data->{lambda}->{$lambdaKey} } ) {
        %updates = ( 'invocations' => $data->{lambda}->{$lambdaKey}->{$timeKey}->{Invocations}, 'errors' => $data->{lambda}->{$lambdaKey}->{$timeKey}->{Errors}, 'duration' => $data->{lambda}->{$lambdaKey}->{$timeKey}->{"Duration"}, 'throttles' => $data->{lambda}->{$lambdaKey}->{$timeKey}->{"Throttles"}, 'concurrent_executions' => $data->{lambda}->{$lambdaKey}->{$timeKey}->{'ConcurrentExecutions'} );

        if ( AWSLoadDataModule::update_rrd_lambda( $rrd_filepath, $timeKey, \%updates ) ) {
          $has_failed = 1;
        }
      }
    }
  }

  #region
  print "\nRegion                    : pushing data to rrd, " . localtime();

  foreach my $regionKey ( keys %{ $data->{region} } ) {
    $rrd_filepath = AWSDataWrapper::get_filepath_rrd( { type => 'region', uuid => $regionKey } );
    unless ( -f $rrd_filepath ) {
      if ( AWSLoadDataModule::create_rrd_region( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    if ( $has_failed != 1 ) {
      %updates = ( 'instances_running' => $data->{region}->{$regionKey}->{running}, 'instances_stopped' => $data->{region}->{$regionKey}->{stopped} );
      my $timestamp_region = time();

      if ( AWSLoadDataModule::update_rrd_region( $rrd_filepath, $timestamp_region, \%updates ) ) {
        $has_failed = 1;
      }
    }
  }

  unless ($has_failed) {
    backup_perf_file($file);
  }
}

################################################################################

my @regions = @{ AWSDataWrapper::get_items( { item_type => 'region' } ) };

foreach my $region (@regions) {
  my ( $region_id, $region_label ) = each %{$region};

  my @ec2s = @{ AWSDataWrapper::get_items( { item_type => 'ec2', parent_type => 'region', parent_id => $region_id } ) };

  foreach my $ec2 (@ec2s) {
    my ( $ec2_uuid, $ec2_label ) = each %{$ec2};

    my $filepath = AWSDataWrapper::get_filepath_rrd( { type => 'ec2', uuid => $ec2_uuid } );
    unless ( -f $filepath ) {
      my $start_time = time() - 3600;
      AWSLoadDataModule::create_rrd_ec2( $filepath, $start_time );
    }

  }
}

################################################################################
#
sub backup_perf_file {

  # expects file name for the file, that's supposed to be moved from XEN_iostats/
  #     with file name "XEN_alias_hostname_perf_timestamp.json"
  my $src_file = shift;
  my $alias    = ( split( '_', $src_file ) )[1];
  my $source   = "$json_dir/$src_file";
  my $target1  = "$tmpdir/aws-$alias-perf-last1.json";
  my $target2  = "$tmpdir/aws-$alias-perf-last2.json";

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
