package AmazonWebServices;

use strict;
use warnings;

use AWS::CLIWrapper;
use HTTP::Request::Common;
use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};

my $signer;

my $conf_path = "$inputdir/data/AWS";

unless ( -d $conf_path ) {
  mkdir( "$conf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $conf_path: $!" . __FILE__ . ':' . __LINE__ );
}

#my @regions = ('us-east-2', 'eu-central-1');
my @regions;

my %ec2;
my @ec2_metrics = ( 'NetworkIn', 'NetworkOut', 'CPUUtilization', 'DiskReadBytes', 'DiskWriteBytes', 'DiskWriteOps', 'DiskReadOps' );
my %ec2_cpu_count;

my @volumes;
my @volume_metrics = ( 'VolumeReadBytes', 'VolumeWriteBytes', 'VolumeReadOps', 'VolumeWriteOps' );

my @rds;
my @rds_metrics = ( 'CPUUtilization', 'BurstBalance', 'DatabaseConnections', 'DiskQueueDepth', 'FreeableMemory', 'FreeStorageSpace', 'NetworkReceiveThroughput', 'NetworkTransmitThroughput', 'ReadIOPS', 'ReadLatency', 'ReadThroughput', 'WriteIOPS', 'WriteLatency', 'WriteThroughput' );

my @s3;
my @s3_metrics = ( 'BucketSizeBytes', 'NumberOfObjects' );

my @api;
my @api_metrics = ( 'Count', 'Latency', '5XXError', '4XXError', 'IntegrationLatency' );

my @lambda;
my @lambda_metrics = ( 'Invocations', 'Errors', 'Throttles', 'Duration', 'ConcurrentExecutions' );

sub new {
  my ( $self, $interval, $name, $uuid ) = @_;
  my $o = {};
  bless $o, $self;
  $o->{interval} = $interval;

  $o->{uuid} = defined $uuid ? $uuid : $name;

  if ( defined $name ) {
    $o->{name} = $name;
  }
  return $o;
}

sub set_aws_access_key_id {
  my ( $self, $aws_access_key_id ) = @_;
  $self->{aws_access_key_id} = $aws_access_key_id;

  #system("export AWS_ACCESS_KEY_ID=$aws_access_key_id");
  $ENV{'AWS_ACCESS_KEY_ID'} = $aws_access_key_id;
}

sub set_aws_secret_access_key {
  my ( $self, $aws_secret_access_key ) = @_;
  $self->{aws_secret_access_key} = $aws_secret_access_key;

  #system("export AWS_SECRET_ACCESS_KEY=$aws_secret_access_key");
  $ENV{'AWS_SECRET_ACCESS_KEY'} = $aws_secret_access_key;
}

sub get_all_regions() {
  my ($self) = @_;
  my $aws = AWS::CLIWrapper->new(
    region => 'us-east-2',
  );
  my $res = $aws->ec2(
    'describe-regions' => {},
    timeout            => 60,    # optional. default is 30 seconds
  );

  my $regions;
  if ($res) {
    foreach my $result ( @{ $res->{Regions} } ) {
      push( @{$regions}, $result->{RegionName} );
    }
  }
  else {
    warn $AWS::CLIWrapper::Error->{Code};
    warn $AWS::CLIWrapper::Error->{Message};
  }

  return $regions;
}

sub add_region() {
  my ( $self, $region ) = @_;
  push( @{ $self->{regions} }, $region );
}

sub get_metrics() {
  my ($self) = @_;

  my %json_request;

  my %data;

  my $lastHour = time() - 600;

  #Get last record
  my $timestamp_json = '';
  if ( open( my $fh, '<', $conf_path . "/last_" . $self->{name} . ".json" ) ) {
    while ( my $row = <$fh> ) {
      chomp $row;
      $timestamp_json .= $row;
    }
    close($fh);
  }
  else {
    open my $hl, ">", $conf_path . "/last_" . $self->{name} . ".json";
    $timestamp_json = "{\"timestamp\":\"$lastHour\"}";
    print $hl "{\"timestamp\":\"$lastHour\"}";
  }

  # decode JSON
  my $timestamp_data = decode_json($timestamp_json);
  if ( ref($timestamp_data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in timestamp file: missing data" ) && next;
  }

  my $timeStmpFrom = $timestamp_data->{timestamp};

  my $timestamp_diff = 0;

  my $interval = $self->{interval};

  my $timeStmpNow = ceil( time() / $interval ) * $interval;
  if ( $timeStmpFrom <= ( $timeStmpNow - 1800 ) ) {
    $timeStmpFrom = ceil( ( $timeStmpNow - 1800 ) / $interval ) * $interval;
  }

  if ( $timeStmpNow > time() ) {
    $timeStmpNow = $timeStmpNow - $interval;
  }

  my $timeFrom = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime($timeStmpFrom) );
  my $timeTo   = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime($timeStmpNow) );

  my @t    = localtime(time);
  my $diff = timegm(@t) - timelocal(@t);

  foreach my $region ( @{ $self->{regions} } ) {
    
    my $aws;
    eval {    
      $aws = AWS::CLIWrapper->new(
        region => $region,
      );
    };
    if ($@) {
      logger("[perf] region error: $@");
      next;
    }

    my $loop     = 1;
    my $first    = 1;
    my $step     = 50;
    my $sum      = 0;

    if ( exists $self->{ec2}{$region} && scalar @{ $self->{ec2}{$region} } >= 1 ) {

      $sum = scalar @{ $self->{ec2}{$region} };
      logger("fetching $sum vms in region $region");

      $loop     = 1;
      my $vm_start = 0;
      my $vm_stop  = 0;
      $first    = 1;
      $step     = 50;
      while ( $loop eq "1" ) {

        my $i = 0;
        %json_request = ();
        if ( $first eq "0" ) {
          $vm_start = $vm_stop + 1;
        }
        else {
          $first = 0;
        }
        if ( $sum - 1 <= $vm_start + $step ) {
          $vm_stop = $sum - 1;
          $loop    = 0;
        }
        else {
          $vm_stop = $vm_start + $step - 1;
        }

        for ( $vm_start .. $vm_stop ) {
          my $ct       = $_;
          my $instance = $self->{ec2}{$region}[$ct];

          if ( !defined $instance ) {
            $loop = 0;
            next;
          }

          for my $metric (@ec2_metrics) {
            my $stat = ( $metric eq "CPUUtilization" ) ? "Average" : "Sum";
            $json_request{MetricDataQueries}[$i]{Id}                                       = "id$i";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Namespace}            = "AWS/EC2";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{MetricName}           = "$metric";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Name}  = "InstanceId";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Value} = "$instance";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Period}                       = $interval;
            $json_request{MetricDataQueries}[$i]{MetricStat}{Stat}                         = $stat;

            #$json_request{MetricDataQueries}[0]{MetricStat}{Unit} = "Bytes";
            $json_request{MetricDataQueries}[$i]{Label}      = $instance . "_" . $metric;
            $json_request{MetricDataQueries}[$i]{ReturnData} = \1;

            $i++;
          }
        }

        $json_request{StartTime} = "$timeFrom";
        $json_request{EndTime}   = "$timeTo";

	my $res; 
	eval {
          $res = $aws->cloudwatch(
            'get-metric-data' => { 'cli-input-json' => {%json_request} },
            timeout           => 60,                                        # optional. default is 30 seconds
          );
	};
	if ($@) {
          logger("[perf] ec2 error: $@");
          next;
        }

        if ($res) {
          foreach my $result ( @{ $res->{MetricDataResults} } ) {
            my @splits = split /_/, $result->{Label};
            my $order  = 0;
            foreach my $c ( @{ $result->{Timestamps} } ) {
              my $time = str2time($c);
              if ( $time > $timestamp_diff ) {
                $timestamp_diff = $time;
              }
              $data{ec2}{ $splits[0] }{$time}{ $splits[1] } = $result->{Values}->[$order];
              $order++;

              if ( !exists $data{ec2}{ $splits[0] }{$time}{cpu_count} ) {
                $data{ec2}{ $splits[0] }{$time}{cpu_count} = $self->{ec2_cpu_count}->{ $splits[0] };
              }
            }

            #print Dumper($result);
          }
        }
        else {
          warn $AWS::CLIWrapper::Error->{Code};
          warn $AWS::CLIWrapper::Error->{Message};
        }
      }
    }

    #Volumes
    my $i;
    my $res;

    if ( exists $self->{volumes}{$region} && scalar @{ $self->{volumes}{$region} } >= 1 ) {

      $sum = scalar @{ $self->{volumes}{$region} };
      logger("fetching $sum volumes in region $region");

      $loop = 1;
      my $vol_start = 0;
      my $vol_stop  = 0;
      $first = 1;
      while ( $loop eq "1" ) {

        my $i = 0;
        %json_request = ();
        if ( $first eq "0" ) {
          $vol_start = $vol_stop + 1;
        }
        else {
          $first = 0;
        }
        if ( $sum - 1 <= $vol_start + $step ) {
          $vol_stop = $sum - 1;
          $loop     = 0;
        }
        else {
          $vol_stop = $vol_start + $step - 1;
        }

        for ( $vol_start .. $vol_stop ) {
          my $ct     = $_;
          my $volume = $self->{volumes}{$region}[$ct];

          if ( !defined $volume ) {
            $loop = 0;
            next;
          }

          for my $metric (@volume_metrics) {
            $json_request{MetricDataQueries}[$i]{Id}                                       = "id$i";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Namespace}            = "AWS/EBS";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{MetricName}           = "$metric";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Name}  = "VolumeId";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Value} = "$volume";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Period}                       = $interval;
            $json_request{MetricDataQueries}[$i]{MetricStat}{Stat}                         = "Sum";

            #$json_request{MetricDataQueries}[0]{MetricStat}{Unit} = "Bytes";
            $json_request{MetricDataQueries}[$i]{Label}      = $volume . "_" . $metric;
            $json_request{MetricDataQueries}[$i]{ReturnData} = \1;
            $i++;
          }
        }

        $json_request{StartTime} = "$timeFrom";
        $json_request{EndTime}   = "$timeTo";

	eval {
          $res = $aws->cloudwatch(
            'get-metric-data' => { 'cli-input-json' => {%json_request} },
            timeout           => 60,                                        # optional. default is 30 seconds
          );
	};
	if ($@) {
          logger("[perf] volumes error: $@");
          next;
        }

        if ($res) {
          foreach my $result ( @{ $res->{MetricDataResults} } ) {
            my @splits = split /_/, $result->{Label};
            my $order  = 0;
            foreach my $c ( @{ $result->{Timestamps} } ) {
              my $time = str2time($c);
              $data{volume}{ $splits[0] }{$time}{ $splits[1] } = $result->{Values}->[$order];
              $order++;
            }

            #print Dumper($result);
          }
        }
        else {
          warn $AWS::CLIWrapper::Error->{Code};
          warn $AWS::CLIWrapper::Error->{Message};
        }
      }
    }

    #RDS

    if ( exists $self->{rds}{$region} && scalar @{ $self->{rds}{$region} } >= 1 ) {

      $sum = scalar @{ $self->{rds}{$region} };
      logger("fetching $sum RDS in region $region");

      $step = 30;
      $loop = 1;
      my $rds_start = 0;
      my $rds_stop  = 0;
      $first = 1;
      while ( $loop eq "1" ) {

        my $i = 0;
        %json_request = ();
        if ( $first eq "0" ) {
          $rds_start = $rds_stop + 1;
        }
        else {
          $first = 0;
        }
        if ( $sum - 1 <= $rds_start + $step ) {
          $rds_stop = $sum - 1;
          $loop     = 0;
        }
        else {
          $rds_stop = $rds_start + $step - 1;
        }

        for ( $rds_start .. $rds_stop ) {
          my $ct  = $_;
          my $rds = $self->{rds}{$region}[$ct];

          if ( !defined $rds ) {
            $loop = 0;
            next;
          }

          for my $metric (@rds_metrics) {
            $json_request{MetricDataQueries}[$i]{Id}                                       = "id$i";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Namespace}            = "AWS/RDS";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{MetricName}           = "$metric";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Name}  = "DBInstanceIdentifier";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Value} = "$rds->[1]";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Period}                       = $interval;
            $json_request{MetricDataQueries}[$i]{MetricStat}{Stat}                         = "Average";

            #$json_request{MetricDataQueries}[0]{MetricStat}{Unit} = "Bytes";
            $json_request{MetricDataQueries}[$i]{Label}      = $rds->[0] . "_" . $metric;
            $json_request{MetricDataQueries}[$i]{ReturnData} = \1;
            $i++;
          }
        }

        $json_request{StartTime} = "$timeFrom";
        $json_request{EndTime}   = "$timeTo";

	eval {
          $res = $aws->cloudwatch(
            'get-metric-data' => { 'cli-input-json' => {%json_request} },
            timeout           => 60,                                        # optional. default is 30 seconds
          );
	};
	if ($@) {
          logger("[perf] rds error: $@");
          next;
        }

        if ($res) {
          foreach my $result ( @{ $res->{MetricDataResults} } ) {
            my @splits = split /_/, $result->{Label};
            my $order  = 0;
            foreach my $c ( @{ $result->{Timestamps} } ) {
              my $time = str2time($c);
              $data{rds}{ $splits[0] }{$time}{ $splits[1] } = $result->{Values}->[$order];
              $order++;
            }

            #print Dumper($result);
          }
        }
        else {
          warn $AWS::CLIWrapper::Error->{Code};
          warn $AWS::CLIWrapper::Error->{Message};
        }
      }
    }

    #S3

    # if (exists $self->{s3} && scalar @{$self->{s3}} >= 1) {
    #
    #  $i = 0;
    #  %json_request = ();
    #
    #  for my $instance (@{$self->{s3}}) {
    #
    #    for my $metric (@s3_metrics) {
    #
    #      $json_request{MetricDataQueries}[$i]{Id} = "id$i";
    #      $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Namespace} = "AWS/S3";
    #      $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{MetricName} = "$metric";
    #      $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Name} = "BucketName";
    #      $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Value} = "$instance";
    #      $json_request{MetricDataQueries}[$i]{MetricStat}{Period} = $interval;
    #      $json_request{MetricDataQueries}[$i]{MetricStat}{Stat} = "Sum";
    #      #$json_request{MetricDataQueries}[0]{MetricStat}{Unit} = "Bytes";
    #      $json_request{MetricDataQueries}[$i]{Label} = $instance."_".$metric;
    #      $json_request{MetricDataQueries}[$i]{ReturnData} = \1;
    #
    #      $i++;
    #
    #    }
    #
    #  }
    #
    #  $json_request{StartTime} = "$timeFrom";
    #  $json_request{EndTime} = "$timeTo";
    #
    #  $res = $aws->cloudwatch(
    #    'get-metric-data' => {
    #      'cli-input-json' => { %json_request }
    #    },
    #    timeout => 18, # optional. default is 30 seconds
    #  );
    #
    #  if ($res) {
    #    foreach my $result (@{$res->{MetricDataResults}}) {
    #      my @splits = split /_/, $result->{Label};
    #      my $order = 0;
    #      foreach my $c (@{$result->{Timestamps}}) {
    #        my $time = str2time($c);
    #        $data{s3}{$splits[0]}{$time}{$splits[1]} = $result->{Values}->[$order];
    #        $order++;
    #       }
    #
    #       #print Dumper($result);
    #     }
    #  } else {
    #    warn $AWS::CLIWrapper::Error->{Code};
    #    warn $AWS::CLIWrapper::Error->{Message};
    #  }
    #
    #}

    #API GATEWAY

    if ( exists $self->{api}{$region} && scalar @{ $self->{api}{$region} } >= 1 ) {

      $sum = scalar @{ $self->{api}{$region} };
      logger("fetching $sum APIs GW in region $region");

      $step = 50;
      $loop = 1;
      my $api_start = 0;
      my $api_stop  = 0;
      $first = 1;
      while ( $loop eq "1" ) {

        my $i = 0;
        %json_request = ();
        if ( $first eq "0" ) {
          $api_start = $api_stop + 1;
        }
        else {
          $first = 0;
        }
        if ( $sum - 1 <= $api_start + $step ) {
          $api_stop = $sum - 1;
          $loop     = 0;
        }
        else {
          $api_stop = $api_start + $step - 1;
        }

        for ( $api_start .. $api_stop ) {
          my $ct  = $_;
          my $api = $self->{api}{$region}[$ct];

          if ( !defined $api ) {
            $loop = 0;
            next;
          }

          for my $metric (@api_metrics) {
            $json_request{MetricDataQueries}[$i]{Id}                                       = "id$i";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Namespace}            = "AWS/ApiGateway";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{MetricName}           = "$metric";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Name}  = "ApiName";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Value} = "$api->[1]";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Period}                       = $interval;
            $json_request{MetricDataQueries}[$i]{MetricStat}{Stat}                         = "Sum";

            #$json_request{MetricDataQueries}[0]{MetricStat}{Unit} = "Bytes";
            $json_request{MetricDataQueries}[$i]{Label}      = $api->[0] . "_" . $metric;
            $json_request{MetricDataQueries}[$i]{ReturnData} = \1;
            $i++;
          }
        }

        $json_request{StartTime} = "$timeFrom";
        $json_request{EndTime}   = "$timeTo";

	eval {
          $res = $aws->cloudwatch(
            'get-metric-data' => { 'cli-input-json' => {%json_request} },
            timeout           => 60,                                        # optional. default is 30 seconds
          );
	};
	if ($@) {
          logger("[perf] api error: $@");
          next;
        }

        if ($res) {
          foreach my $result ( @{ $res->{MetricDataResults} } ) {
            my @splits = split /_/, $result->{Label};
            my $order  = 0;
            foreach my $c ( @{ $result->{Timestamps} } ) {
              my $time = str2time($c);
              $data{api}{ $splits[0] }{$time}{ $splits[1] } = $result->{Values}->[$order];
              $order++;
            }

            #print Dumper($result);
          }
        }
        else {
          warn $AWS::CLIWrapper::Error->{Code};
          warn $AWS::CLIWrapper::Error->{Message};
        }
      }
    }

    #Lambda

    if ( exists $self->{lambda}{$region} && scalar @{ $self->{lambda}{$region} } >= 1 ) {

      $sum = scalar @{ $self->{lambda}{$region} };
      logger("fetching $sum lambdas in region $region");

      $loop = 1;
      my $lam_start = 0;
      my $lam_stop  = 0;
      $first = 1;
      while ( $loop eq "1" ) {

        my $i = 0;
        %json_request = ();
        if ( $first eq "0" ) {
          $lam_start = $lam_stop + 1;
        }
        else {
          $first = 0;
        }
        if ( $sum - 1 <= $lam_start + $step ) {
          $lam_stop = $sum - 1;
          $loop     = 0;
        }
        else {
          $lam_stop = $lam_start + $step - 1;
        }

        for ( $lam_start .. $lam_stop ) {
          my $ct     = $_;
          my $lambda = $self->{lambda}{$region}[$ct];

          if ( !defined $lambda ) {
            $loop = 0;
            next;
          }

          for my $metric (@lambda_metrics) {
            $json_request{MetricDataQueries}[$i]{Id}                                       = "id$i";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Namespace}            = "AWS/Lambda";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{MetricName}           = "$metric";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Name}  = "FunctionName";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Metric}{Dimensions}[0]{Value} = "$lambda->[1]";
            $json_request{MetricDataQueries}[$i]{MetricStat}{Period}                       = $interval;
            $json_request{MetricDataQueries}[$i]{MetricStat}{Stat}                         = "Sum";

            #$json_request{MetricDataQueries}[0]{MetricStat}{Unit} = "Bytes";
            $json_request{MetricDataQueries}[$i]{Label}      = $lambda->[0] . "_" . $metric;
            $json_request{MetricDataQueries}[$i]{ReturnData} = \1;
            $i++;
          }
        }

        $json_request{StartTime} = "$timeFrom";
        $json_request{EndTime}   = "$timeTo";

	eval {
          $res = $aws->cloudwatch(
            'get-metric-data' => { 'cli-input-json' => {%json_request} },
            timeout           => 60,                                        # optional. default is 30 seconds
          );
        };
	if ($@) {
          logger("[perf] ec2 error: $@");
          next;
        }

        if ($res) {
          foreach my $result ( @{ $res->{MetricDataResults} } ) {
            my @splits = split /_/, $result->{Label};
            my $order  = 0;
            foreach my $c ( @{ $result->{Timestamps} } ) {
              my $time = str2time($c);
              $data{lambda}{ $splits[0] }{$time}{ $splits[1] } = $result->{Values}->[$order];
              $order++;
            }

            #print Dumper($result);
          }
        }
        else {
          warn $AWS::CLIWrapper::Error->{Code};
          warn $AWS::CLIWrapper::Error->{Message};
        }
      }
    }
  }

  if (%data) {

    if ( $timestamp_diff == 0 ) {
      $timestamp_diff = time() - 600;
    }

    $timestamp_diff = $timestamp_diff - 600;

    open my $hl, ">", $conf_path . "/last_" . $self->{name} . ".json";
    print $hl "{\"timestamp\":\"$timestamp_diff\"}";
    close $hl;

    return %data;
  }
  else {
    return ();
  }
}

sub get_configuration() {
  my ($self) = @_;

  my %data;

  $data{specification}{hostcfg_uuid}{ $self->{uuid} } = $self->{uuid};

  foreach my $region ( @{ $self->{regions} } ) {

    logger("Region: $region");

    my $aws;
    eval {
      $aws = AWS::CLIWrapper->new(
        region => $region,
      );
    };
    if ($@) {
      logger("[conf] region error: $@");
      next;
    }

    if (!defined $data{specification}{region}{$region}) {
      $data{specification}{region}{$region}{running} = 0;
      $data{specification}{region}{$region}{stopped} = 0;
    }

    my $res;
    eval {
      $res = $aws->ec2(
        'describe-instances' => {
	  'query' => 'Reservations[*].Instances[*].{InstanceType:InstanceType,PrivateIpAddress:PrivateIpAddress,CpuOptions:CpuOptions,Placement:Placement,State:State,StateReason:StateReason,Hypervisor:Hypervisor,LaunchTime:LaunchTime,VirtualizationType:VirtualizationType,PublicDnsName:PublicDnsName,CpuOptions:CpuOptions,InstanceId:InstanceId,Tags:Tags,BlockDeviceMappings:BlockDeviceMappings}',
	  'filters' => 'Name=tag-key,Values=Name'
	},
        timeout              => 60,    # optional. default is 30 seconds
      );
    };
    if ($@) {
      logger("[conf] ec2 error: $@");
      next;
    }

    if (defined $res) {
      for my $reservation ( @{ $res } ) {
        for my $is ( @{ $reservation } ) {

	  $data{specification}{ec2}{ $is->{InstanceId} }{InstanceType}       = $is->{InstanceType};
          $data{specification}{ec2}{ $is->{InstanceId} }{PrivateIpAddress}   = $is->{PrivateIpAddress};
          $data{specification}{ec2}{ $is->{InstanceId} }{CoreCount}          = $is->{CpuOptions}->{CoreCount};
          $data{specification}{ec2}{ $is->{InstanceId} }{Zone}               = $is->{Placement}->{AvailabilityZone};
          $data{specification}{ec2}{ $is->{InstanceId} }{State}              = $is->{State}->{Name};
          $data{specification}{ec2}{ $is->{InstanceId} }{StateReason}        = $is->{StateReason}->{Message};
          $data{specification}{ec2}{ $is->{InstanceId} }{Hypervisor}         = $is->{Hypervisor};
          $data{specification}{ec2}{ $is->{InstanceId} }{LaunchTime}         = $is->{LaunchTime};
          $data{specification}{ec2}{ $is->{InstanceId} }{VirtualizationType} = $is->{VirtualizationType};
          $data{specification}{ec2}{ $is->{InstanceId} }{PublicDnsName}      = $is->{PublicDnsName};
          $data{specification}{ec2}{ $is->{InstanceId} }{hostcfg_uuid}       = $self->{uuid};

          $self->{ec2_cpu_count}->{ $is->{InstanceId} } = $is->{CpuOptions}->{CoreCount};

          if ( !defined $data{specification}{region}{$region}{running} ) {
            $data{specification}{region}{$region}{running} = 0;
          }
          if ( !defined $data{specification}{region}{$region}{stopped} ) {
            $data{specification}{region}{$region}{stopped} = 0;
          }

          if ( $is->{State}->{Name} eq "running" ) {
            $data{specification}{region}{$region}{running}++;

            #print "\n$is->{State}->{Name} - running!";
          }
          else {
            $data{specification}{region}{$region}{stopped}++;

            #print "\n$is->{State}->{Name} - stopped!";
          }

          if ( exists $data{architecture}{region_ec2}{$region}[0] ) {
            push( @{ $data{architecture}{region_ec2}{$region} }, $is->{InstanceId} );
          }
          else {
            $data{architecture}{region_ec2}{$region}[0] = $is->{InstanceId};
          }

         

          for ( @{ $is->{Tags} } ) {
            my $tag = $_;
            if ( $tag->{Key} eq 'Name' ) {
              $data{specification}{ec2}{ $is->{InstanceId} }{Name} = $tag->{Value};
	      $tag->{Value} =~ s/[^\x00-\x7f]//g;
	      $data{label}{ec2}{ $is->{InstanceId} } = $tag->{Value};
            }
          }

          for ( @{ $is->{BlockDeviceMappings} } ) {
            my $volume = $_;
            if ( exists $data{architecture}{ec2_volume}{ $is->{InstanceId} }[0] ) {
              push( @{ $data{architecture}{ec2_volume}{ $is->{InstanceId} } }, $volume->{Ebs}->{VolumeId} );
            }
            else {
              $data{architecture}{ec2_volume}{ $is->{InstanceId} }[0] = $volume->{Ebs}->{VolumeId};
            }
          }

          if ( defined $self->{ec2}{$region}[0] ) {
            push( @{ $self->{ec2}{$region} }, $is->{InstanceId} );
          }
          else {
            $self->{ec2}{$region}[0] = $is->{InstanceId};
          }

          #print Dumper($is);
        } 
      }
    }
    else {
      warn $AWS::CLIWrapper::Error->{Code};
      warn $AWS::CLIWrapper::Error->{Message};
    }

    eval {
      $res = $aws->ec2(
        'describe-volumes' => {
	  'query' => 'Volumes[*].{VolumeId:VolumeId,VolumeType:VolumeType,Size:Size,State:State,AvailabilityZone:AvailabilityZone}'
	},
        timeout            => 60,    # optional. default is 30 seconds
      );
    };
    if ($@) {
      logger("[conf] volumes error: $@");
      next;
    }

    #print Dumper($res);

    if ($res) {
      for my $volume ( @{ $res } ) {

        #print Dumper($volume);

        $data{label}{volume}{ $volume->{VolumeId} }                       = $volume->{VolumeId};
        $data{specification}{volume}{ $volume->{VolumeId} }{VolumeType}   = $volume->{VolumeType};
        $data{specification}{volume}{ $volume->{VolumeId} }{Size}         = $volume->{Size};
        $data{specification}{volume}{ $volume->{VolumeId} }{State}        = $volume->{State};
        $data{specification}{volume}{ $volume->{VolumeId} }{Zone}         = $volume->{AvailabilityZone};
        $data{specification}{volume}{ $volume->{VolumeId} }{hostcfg_uuid} = $self->{uuid};

        if ( exists $data{architecture}{region_volume}{$region}[0] ) {
          push( @{ $data{architecture}{region_volume}{$region} }, $volume->{VolumeId} );
        }
        else {
          $data{architecture}{region_volume}{$region}[0] = $volume->{VolumeId};
        }

        if ( defined $self->{volumes}{$region}[0] ) {
          push( @{ $self->{volumes}{$region} }, $volume->{VolumeId} );
        }
        else {
          $self->{volumes}{$region}[0] = $volume->{VolumeId};
        }

      }

    }
    else {
      warn $AWS::CLIWrapper::Error->{Code};
      warn $AWS::CLIWrapper::Error->{Message};
    }

    eval {
      $res = $aws->rds(
        'describe-db-instances' => {
	  'query' => 'DBInstances[*].{DbiResourceId:DbiResourceId,DBInstanceIdentifier:DBInstanceIdentifier,DBInstanceStatus:DBInstanceStatus,AvailabilityZone:AvailabilityZone,DBInstanceClass:DBInstanceClass,AllocatedStorage:AllocatedStorage,StorageType:StorageType,Engine:Engine,DBInstanceIdentifier:DBInstanceIdentifier}'
	},
        timeout                 => 60,    # optional. default is 30 seconds
      );
    };
    if ($@) {
      logger("[conf] rds error: $@");
      next;
    }

    if ($res) {
      for my $db ( @{ $res } ) {

        #print Dumper($db);

        $data{label}{rds}{ $db->{DbiResourceId} }                       = $db->{DBInstanceIdentifier};
        $data{specification}{rds}{ $db->{DbiResourceId} }{status}       = $db->{DBInstanceStatus};
        $data{specification}{rds}{ $db->{DbiResourceId} }{zone}         = $db->{AvailabilityZone};
        $data{specification}{rds}{ $db->{DbiResourceId} }{class}        = $db->{DBInstanceClass};
        $data{specification}{rds}{ $db->{DbiResourceId} }{storage}      = $db->{AllocatedStorage};
        $data{specification}{rds}{ $db->{DbiResourceId} }{storageType}  = $db->{StorageType};
        $data{specification}{rds}{ $db->{DbiResourceId} }{engine}       = $db->{Engine};
        $data{specification}{rds}{ $db->{DbiResourceId} }{name}         = $db->{DBInstanceIdentifier};
        $data{specification}{rds}{ $db->{DbiResourceId} }{hostcfg_uuid} = $self->{uuid};

        if ( exists $data{architecture}{region_rds}{$region}[0] ) {
          push( @{ $data{architecture}{region_rds}{$region} }, $db->{DbiResourceId} );
        }
        else {
          $data{architecture}{region_rds}{$region}[0] = $db->{DbiResourceId};
        }

        my @rds_arr = ( $db->{DbiResourceId}, $db->{DBInstanceIdentifier} );

        if ( defined $self->{rds}{$region}[0] ) {
          push( @{ $self->{rds}{$region} }, \@rds_arr );
        }
        else {
          $self->{rds}{$region}[0] = \@rds_arr;
        }
      }

    }
    else {
      warn $AWS::CLIWrapper::Error->{Code};
      warn $AWS::CLIWrapper::Error->{Message};
    }

    #$res = $aws->s3api(
    #  'list-buckets' => {},
    #   timeout => 18, # optional. default is 30 seconds
    #);
    #
    #if ($res) {
    #  for my $s3 ( @{ $res->{Buckets} }) {
    #    $data{label}{s3}{$s3->{Name}} = $s3->{Name};
    #    $data{specification}{s3}{$s3->{Name}}{name} = $s3->{Name};
    #    $data{specification}{s3}{$s3->{Name}}{created} = $s3->{CreationDate};
    #
    #	push(@{$self->{s3}}, $s3->{Name});
    #  }
    #
    #
    #} else {
    #  warn $AWS::CLIWrapper::Error->{Code};
    #  warn $AWS::CLIWrapper::Error->{Message};
    #}

    #API

    eval {
      $res = $aws->apigateway(
        'get-rest-apis' => {
	  'query' => 'items[*].{id:id,name:name,createdDate:createdDate,apiKeySource:apiKeySource,description:description}'
	},
        timeout         => 60,    # optional. default is 30 seconds
      );
    };
    if ($@) {
      logger("[conf] api error: $@");
      next;
    }

    if ($res) {
      for my $api ( @{ $res } ) {
        $data{label}{api}{ $api->{id} }                       = $api->{name};
        $data{specification}{api}{ $api->{id} }{name}         = $api->{name};
        $data{specification}{api}{ $api->{id} }{created}      = $api->{createdDate};
        $data{specification}{api}{ $api->{id} }{sourceKey}    = $api->{apiKeySource};
        $data{specification}{api}{ $api->{id} }{description}  = $api->{description};
        $data{specification}{api}{ $api->{id} }{region}       = $region;
        $data{specification}{api}{ $api->{id} }{hostcfg_uuid} = $self->{uuid};

        my @api_arr = ( $api->{id}, $api->{name} );

        if ( defined $self->{api}{$region}[0] ) {
          push( @{ $self->{api}{$region} }, \@api_arr );
        }
        else {
          $self->{api}{$region}[0] = \@api_arr;
        }

        if ( exists $data{architecture}{region_api}{$region}[0] ) {
          push( @{ $data{architecture}{region_api}{$region} }, $api->{id} );
        }
        else {
          $data{architecture}{region_api}{$region}[0] = $api->{id};
        }
      }

    }
    else {
      warn $AWS::CLIWrapper::Error->{Code};
      warn $AWS::CLIWrapper::Error->{Message};
    }

    #Lambda

    eval {
      $res = $aws->lambda(
        'list-functions' => {
	  'query' => 'Functions[*].{RevisionId:RevisionId,FunctionName:FunctionName,Handler:Handler,MemorySize:MemorySize,Runtime:Runtime}'
	},
        timeout          => 60,    # optional. default is 30 seconds
      );
    };
    if ($@) {
      logger("[conf] lambda error: $@");
      next;
    }

    if ($res) {
      for my $lambda ( @{ $res } ) {
        $data{label}{lambda}{ $lambda->{RevisionId} }                       = $lambda->{FunctionName};
        $data{specification}{lambda}{ $lambda->{RevisionId} }{name}         = $lambda->{FunctionName};
        $data{specification}{lambda}{ $lambda->{RevisionId} }{handler}      = $lambda->{Handler};
        $data{specification}{lambda}{ $lambda->{RevisionId} }{memory}       = $lambda->{MemorySize};
        $data{specification}{lambda}{ $lambda->{RevisionId} }{runtime}      = $lambda->{Runtime};
        $data{specification}{lambda}{ $lambda->{RevisionId} }{region}       = $region;
        $data{specification}{lambda}{ $lambda->{RevisionId} }{hostcfg_uuid} = $self->{uuid};

        my @lambda_arr = ( $lambda->{RevisionId}, $lambda->{FunctionName} );

        if ( defined $self->{lambda}{$region}[0] ) {
          push( @{ $self->{lambda}{$region} }, \@lambda_arr );
        }
        else {
          $self->{lambda}{$region}[0] = \@lambda_arr;
        }

        if ( exists $data{architecture}{region_lambda}{$region}[0] ) {
          push( @{ $data{architecture}{region_lambda}{$region} }, $lambda->{RevisionId} );
        }
        else {
          $data{architecture}{region_lambda}{$region}[0] = $lambda->{RevisionId};
        }
      }
    }
    else {
      warn $AWS::CLIWrapper::Error->{Code};
      warn $AWS::CLIWrapper::Error->{Message};
    }

  }

  if (%data) {
    return %data;
  }
  else {
    return 0;
  }

}

sub logger {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "[$act_time]: $text \n";
  return 1;
}

1;
