use 5.008_008;

use strict;
use warnings;

use Azure;
use HostCfg;
use Data::Dumper;
use JSON;
use Time::Local;
use POSIX qw(strftime ceil);
use Date::Parse;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir  = $ENV{INPUTDIR};
my $conf_path = "$inputdir/data/Azure/conf";
my $last_path = "$inputdir/data/Azure/last";
my $cfgdir    = "$inputdir/etc/web_config";

my $timeout = 900;

my $data_path = "$inputdir/data/Azure";
my $perf_path = "$data_path/json";

sub create_dir {
  unless ( -d $data_path ) {
    mkdir( "$data_path", 0755 ) || warn( localtime() . ": Cannot mkdir $data_path: $!" . __FILE__ . ':' . __LINE__ );
  }

  unless ( -d $perf_path ) {
    mkdir( "$perf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $perf_path: $!" . __FILE__ . ':' . __LINE__ );
  }

  unless ( -d $conf_path ) {
    mkdir( "$conf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $conf_path: $!" . __FILE__ . ':' . __LINE__ );
  }

  unless ( -d $last_path ) {
    mkdir( "$last_path", 0755 ) || warn( localtime() . ": Cannot mkdir $last_path: $!" . __FILE__ . ':' . __LINE__ );
  }
}

my %hosts = %{ HostCfg::getHostConnections('Azure') };
my @pids;
my $pid;
my %conf_hash;

if ( keys %hosts >= 1 ) {
  create_dir();
}
else {
  exit(0);
}

foreach my $host ( keys %hosts ) {
  $conf_hash{"conf_$hosts{$host}{hostalias}.json"} = 1;
  unless ( defined( $pid = fork() ) ) {
    warn( localtime() . ": Error: failed to fork for $host.\n" );
    next;
  }
  else {
    if ($pid) {
      push @pids, $pid;
    }
    else {
      local $SIG{ALRM} = sub { die "Azure API2JSON: $pid timeouted.\n"; };
      alarm($timeout);

      my $uuid = defined $hosts{$host}{uuid} ? $hosts{$host}{uuid} : $host;

      my ( $name, $tenant, $client, $secret, $subscriptions, $diagnostics ) = ( $hosts{$host}{hostalias}, $hosts{$host}{tenant}, $hosts{$host}{client}, $hosts{$host}{secret}, $hosts{$host}{subscriptions}, $hosts{$host}{diagnostics} );
      api2json( $name, $tenant, $client, $secret, $subscriptions, $uuid, $diagnostics );
      exit;
    }
  }
}

# wait for forked data retrieval
for $pid (@pids) {
  waitpid( $pid, 0 );
}

print "\nConfiguration                : merging and saving, " . localtime();

opendir( DH, "$conf_path" ) || die "Could not open '$conf_path' for reading '$!'\n";
my @files = grep /.*.json/, readdir DH;
my %conf;
foreach my $file ( sort @files ) {
  if ( !defined $conf_hash{$file} ) {
    print "\nSkipping old conf            : $file, " . localtime();
    next;
  }
  print "\nConfiguration processing     : $file, " . localtime();

  my $json = '';
  if ( open( my $fh, '<', "$conf_path/$file" ) ) {
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
  my $data = decode_json($json);
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file $file: missing data" ) && next;
  }

  foreach my $key ( keys %{ $data->{architecture} } ) {
    foreach my $key2 ( keys %{ $data->{architecture}->{$key} } ) {
      if ( !defined $conf{architecture}{$key}{$key2} ) {
        $conf{architecture}{$key}{$key2} = $data->{architecture}->{$key}->{$key2};
      }
      else {
        for ( @{ $data->{architecture}->{$key}->{$key2} } ) {
          my $value = $_;
          push( @{ $conf{architecture}{$key}{$key2} }, $value );
        }
      }
    }
  }

  foreach my $key ( keys %{ $data->{specification}->{region} } ) {
    if ( !defined $data->{specification}->{region}->{$key} ) {
      $conf{region}{$key} = $data->{specification}->{region}->{$key};
    }
    else {
      $conf{specification}{region}{$key}{running} += $data->{specification}->{region}->{$key}->{running};
      $conf{specification}{region}{$key}{stopped} += $data->{specification}->{region}->{$key}->{stopped};
    }
  }

  foreach my $key ( keys %{ $data->{specification} } ) {
    if ( $key eq "region" ) { next; }
    foreach my $key2 ( keys %{ $data->{specification}->{$key} } ) {
      $conf{specification}{$key}{$key2} = $data->{specification}->{$key}->{$key2};
    }
  }

  foreach my $key ( keys %{ $data->{label} } ) {
    foreach my $key2 ( keys %{ $data->{label}->{$key} } ) {
      $conf{label}{$key}{$key2} = $data->{label}->{$key}->{$key2};
    }
  }

  foreach my $key ( keys %{ $data->{statuses} } ) {
    for ( @{ $data->{statuses}->{$key} } ) {
      my $status = $_;
      push( @{ $conf{statuses}{$key} }, $status );
    }
  }

}

if (%conf) {
  open my $fa, ">", $data_path . "/conf.json";
  print $fa JSON->new->pretty->encode( \%conf );
  close $fa;
}

sub api2json {
  my ( $name, $tenant, $client, $secret, $subscriptions, $uuid, $diagnostics ) = @_;

  my $azure = Azure->new( $tenant, $client, $secret, $diagnostics );

  my %metricData;
  my %confData;

  $confData{specification}{hostcfg_uuid}{$uuid} = $uuid;

  for ( @{$subscriptions} ) {
    my $subscription = $_;

    my $sub = $azure->getSubscription($subscription);
    $sub = defined $sub ? $sub : "undef_sub_name-$name";
    $confData{label}{subscription}{$subscription} = $sub;

    #print "Subscription: $sub \n";

    my $timestamp = time();

    my $resources = $azure->getResourceGroups($subscription);

    for ( @{$resources} ) {
      my $resource    = $_;
      my $dia_enabled = ( defined $diagnostics && $diagnostics eq "1" ) ? "true" : "false";
      print "Sub: $sub, res: $resource - started processing (diagnostics enabled: $dia_enabled) " . localtime() . "\n";

      if ( exists $confData{architecture}{subscription_resource}{$subscription}[0] ) {
        push( @{ $confData{architecture}{subscription_resource}{$subscription} }, $resource );
      }
      else {
        $confData{architecture}{subscription_resource}{$subscription}[0] = $resource;
      }

      #Get last record
      my $lastHour       = time() - 600;
      my $timestamp_json = '';
      if ( open( my $fh, '<', $last_path . "/" . $subscription . "_" . $resource . "_last.json" ) ) {
        while ( my $row = <$fh> ) {
          chomp $row;
          $timestamp_json .= $row;
        }
        close($fh);
      }
      else {
        open my $hl, ">", $last_path . "/" . $subscription . "_" . $resource . "_last.json";
        $timestamp_json = "{\"timestamp\":\"$lastHour\"}";
        print $hl "{\"timestamp\":\"$lastHour\"}";
      }

      # decode JSON
      my $timestamp_data = decode_json($timestamp_json);
      if ( ref($timestamp_data) ne "HASH" ) {
        warn( localtime() . ": Error decoding JSON in timestamp file: missing data" ) && next;
      }

      my $timestamp  = time();
      my $time_end   = $timestamp - 180;
      my $time_start = ( $timestamp - $timestamp_data->{timestamp} <= 7200 ) ? $timestamp_data->{timestamp} - 600 : $timestamp - 7200;

      my $instances = $azure->getInstances( $resource, $subscription );

      my $instances_count = scalar @{ $instances->{value} };
      if ( $instances_count >= 1 ) {
        print "Sub: $sub, res: $resource - discovered $instances_count VMs\n";
      }

      for ( @{ $instances->{value} } ) {
        my $instance = $_;

        #conf data
        $confData{label}{vm}{ $instance->{properties}->{vmId} }                             = $instance->{name};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{vmId}               = $instance->{properties}->{vmId};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{id}                 = $instance->{id};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{name}               = $instance->{name};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{type}               = $instance->{type};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{location}           = $instance->{location};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{vmSize}             = $instance->{properties}->{hardwareProfile}->{vmSize};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{osDisk}{name}       = $instance->{properties}->{storageProfile}->{osDisk}->{name};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{osDisk}{diskSizeGB} = $instance->{properties}->{storageProfile}->{osDisk}->{diskSizeGB};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{osDisk}{osType}     = $instance->{properties}->{storageProfile}->{osDisk}->{osType};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{hostcfg_uuid}       = $uuid;

        my $instance_view = $azure->getInstanceView( $resource, $subscription, $instance->{name} );

        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{osName}    = $instance_view->{osName};
        $confData{specification}{vm}{ $instance->{properties}->{vmId} }{osVersion} = $instance_view->{osVersion};

        my $instance_status;

        for ( @{ $instance_view->{statuses} } ) {
          my $status = $_;
          if ( ( $status->{code} eq "PowerState/running" ) || ( $status->{code} eq "PowerState/deallocated" ) ) {
            $confData{specification}{vm}{ $instance->{properties}->{vmId} }{status} = $status->{displayStatus};
            $instance_status = $status->{displayStatus};
          }

          if ( !defined $metricData{region}{ $instance->{location} }{running} ) {
            $metricData{region}{ $instance->{location} }{running} = 0;
            $confData{specification}{region}{ $instance->{location} }{running} = 0;
          }

          if ( !defined $metricData{region}{ $instance->{location} }{stopped} ) {
            $metricData{region}{ $instance->{location} }{stopped} = 0;
            $confData{specification}{region}{ $instance->{location} }{stopped} = 0;
          }

          if ( $status->{code} eq "PowerState/running" ) {
            $confData{specification}{region}{ $instance->{location} }{running} = $confData{specification}{region}{ $instance->{location} }{running} + 1;
            $metricData{region}{ $instance->{location} }{running} = $metricData{region}{ $instance->{location} }{running} + 1;
          }
          elsif ( $status->{code} eq "PowerState/deallocated" ) {
            $confData{specification}{region}{ $instance->{location} }{stopped} = $confData{specification}{region}{ $instance->{location} }{stopped} + 1;
            $metricData{region}{ $instance->{location} }{stopped} = $metricData{region}{ $instance->{location} }{stopped} + 1;
          }

          if ( exists $confData{statuses}{vm}[0] ) {
            my %temp_data;
            $temp_data{vm}     = $instance->{name};
            $temp_data{code}   = $status->{code};
            $temp_data{status} = $status->{displayStatus};
            $temp_data{level}  = $status->{level};
            push( @{ $confData{statuses}{vm} }, \%temp_data );
          }
          else {
            $confData{statuses}{vm}[0]{vm}     = $instance->{name};
            $confData{statuses}{vm}[0]{code}   = $status->{code};
            $confData{statuses}{vm}[0]{status} = $status->{displayStatus};
            $confData{statuses}{vm}[0]{level}  = $status->{level};
          }
        }

        if ( exists $confData{architecture}{location_vm}{ $instance->{location} }[0] ) {
          push( @{ $confData{architecture}{location_vm}{ $instance->{location} } }, $instance->{properties}->{vmId} );
        }
        else {
          $confData{architecture}{location_vm}{ $instance->{location} }[0] = $instance->{properties}->{vmId};
        }

        if ( exists $confData{architecture}{resource_vm}{$resource}[0] ) {
          push( @{ $confData{architecture}{resource_vm}{$resource} }, $instance->{properties}->{vmId} );
        }
        else {
          $confData{architecture}{resource_vm}{$resource}[0] = $instance->{properties}->{vmId};
        }

        #network data
        for ( @{ $instance->{properties}->{networkProfile}->{networkInterfaces} } ) {
          my $network_interface = $_;
          my $network           = $azure->getNetwork( $network_interface->{id} );
          if ( ref($network) eq 'HASH' ) {
            for ( @{ $network->{properties}->{ipConfigurations} } ) {
              my $ip_conf = $_;
              if ( !defined $ip_conf->{properties}->{publicIPAddress}->{id} ) { next; }
              my $ip = $azure->getIpAdress( $ip_conf->{properties}->{publicIPAddress}->{id} );

              if ( exists $confData{specification}{vm}{ $instance->{properties}->{vmId} }{network}[0] ) {
                my %ip_data;
                $ip_data{name} = $ip->{name};
                $ip_data{ip}   = $ip->{properties}->{ipAddress};
                $ip_data{type} = $ip->{properties}->{publicIPAllocationMethod};
                push( @{ $confData{specification}{vm}{ $instance->{properties}->{vmId} }{network} }, \%ip_data );
              }
              else {
                $confData{specification}{vm}{ $instance->{properties}->{vmId} }{network}[0]{name} = $ip->{name};
                $confData{specification}{vm}{ $instance->{properties}->{vmId} }{network}[0]{ip}   = $ip->{properties}->{ipAddress};
                $confData{specification}{vm}{ $instance->{properties}->{vmId} }{network}[0]{type} = $ip->{properties}->{publicIPAllocationMethod};
              }
            }
          }
        }

        #skip fetching metrics data from deallocated VM
        if ( defined $instance_status && $instance_status ne "VM running" ) {
          next;
        }

        #metrics data
        my $customMetrics;
        if ( $dia_enabled eq "true" ) {
          $customMetrics = $azure->getAgentMetrics( $resource, $subscription, $instance->{name} );
        }
        else {
          $customMetrics = ();
        }

        #print Dumper($customMetrics);

        if ( ref($customMetrics) eq 'HASH' && keys %{ $customMetrics->{usedMemory} } ) {
          $confData{specification}{vm}{ $instance->{properties}->{vmId} }{agent} = 1;
        }
        else {
          $confData{specification}{vm}{ $instance->{properties}->{vmId} }{agent} = 0;
        }

        my $metrics = $azure->getMetrics( $resource, $instance->{name}, $subscription, $time_start, $time_end );
        if ( !defined $metrics->{value} ) {
          sleep(2);
          $metrics = $azure->getMetrics( $resource, $instance->{name}, $subscription, $time_start, $time_end );
        }

        my $type;

        for ( @{ $metrics->{value} } ) {
          my $metricValue = $_;

	  #print Dumper($metricValue->{name}->{value});

          if ( $metricValue->{name}->{value} eq "Percentage CPU" ) {
            $type = "cpu_util";
          }
          elsif ( $metricValue->{name}->{value} eq "Disk Read Bytes" ) {
            $type = "read_bytes";
          }
          elsif ( $metricValue->{name}->{value} eq "Disk Write Bytes" ) {
            $type = "write_bytes";
          }
          elsif ( $metricValue->{name}->{value} eq "Disk Read Operations/Sec" ) {
            $type = "read_ops";
          }
          elsif ( $metricValue->{name}->{value} eq "Disk Write Operations/Sec" ) {
            $type = "write_ops";
          }
          elsif ( $metricValue->{name}->{value} eq "Network In Total" ) {
            $type = "received_bytes";
          }
          elsif ( $metricValue->{name}->{value} eq "Network Out Total" ) {
            $type = "sent_bytes";
          }
          else {
            $type = "undef";
          }

          for ( @{ $metricValue->{timeseries} } ) {
            my $timeSerieData = $_;

            for ( @{ $timeSerieData->{data} } ) {
              my $timeData = $_;

              my $pretty_time = str2time( $timeData->{timeStamp} );

	      if (defined $timeData->{average}) {
                $metricData{vm}{ $instance->{properties}->{vmId} }{$pretty_time}{$type} = $timeData->{average};
              } elsif (defined $timeData->{total}) {
                $metricData{vm}{ $instance->{properties}->{vmId} }{$pretty_time}{$type} = $timeData->{total} / 60;
	      }
            }
          }

          #custom metrics to global metrics
          foreach my $timeKey ( keys %{ $metricData{vm}{ $instance->{properties}->{vmId} } } ) {
            if ( ref($customMetrics) eq 'HASH' && defined $customMetrics->{usedMemory}->{$timeKey} ) {
              $metricData{vm}{ $instance->{properties}->{vmId} }{$timeKey}{usedMemory} = $customMetrics->{usedMemory}->{$timeKey};
            }
            else {
              $metricData{vm}{ $instance->{properties}->{vmId} }{$timeKey}{usedMemory} = 0;
            }
            if ( ref($customMetrics) eq 'HASH' && defined $customMetrics->{freeMemory}->{$timeKey} ) {
              $metricData{vm}{ $instance->{properties}->{vmId} }{$timeKey}{freeMemory} = $customMetrics->{freeMemory}->{$timeKey};
            }
            else {
              $metricData{vm}{ $instance->{properties}->{vmId} }{$timeKey}{freeMemory} = 0;
            }
          }
        }
      }

      my $appServices = $azure->getAppServices( $resource, $subscription );

      my $appServices_count = scalar @{ $appServices->{value} };
      if ( $appServices_count >= 1 ) {
        print "Sub: $sub, res: $resource - discovered $appServices_count App Services\n";
      }

      for ( @{ $appServices->{value} } ) {
        my $appService = $_;

        my $appUUID = $resource . "_" . $appService->{name};

        $confData{label}{appService}{$appUUID}                   = $appService->{name};
        $confData{specification}{appService}{$appUUID}{id}       = $appService->{id};
        $confData{specification}{appService}{$appUUID}{name}     = $appService->{name};
        $confData{specification}{appService}{$appUUID}{type}     = $appService->{type};
        $confData{specification}{appService}{$appUUID}{kind}     = $appService->{kind};
        $confData{specification}{appService}{$appUUID}{location} = $appService->{location};
        $confData{specification}{appService}{$appUUID}{state}    = $appService->{properties}{state};
        $confData{specification}{appService}{$appUUID}{url}      = $appService->{defaultHostName};

        if ( exists $confData{architecture}{resource_appService}{$resource}[0] ) {
          push( @{ $confData{architecture}{resource_appService}{$resource} }, $appUUID );
        }
        else {
          $confData{architecture}{resource_appService}{$resource}[0] = $appUUID;
        }

        my $metrics = $azure->getAppMetrics( $resource, $appService->{name}, $subscription, $time_start, $time_end );

        my $type;
        for ( @{ $metrics->{value} } ) {
          my $metricValue = $_;

          if ( $metricValue->{name}->{value} eq "CpuTime" ) {
            $type = "cpu_time";
          }
          elsif ( $metricValue->{name}->{value} eq "Requests" ) {
            $type = "requests";
          }
          elsif ( $metricValue->{name}->{value} eq "IoReadBytesPerSecond" ) {
            $type = "read_bytes";
          }
          elsif ( $metricValue->{name}->{value} eq "IoWriteBytesPerSecond" ) {
            $type = "write_bytes";
          }
          elsif ( $metricValue->{name}->{value} eq "IoReadOperationsPerSecond" ) {
            $type = "read_ops";
          }
          elsif ( $metricValue->{name}->{value} eq "IoWriteOperationsPerSecond" ) {
            $type = "write_ops";
          }
          elsif ( $metricValue->{name}->{value} eq "BytesReceived" ) {
            $type = "received_bytes";
          }
          elsif ( $metricValue->{name}->{value} eq "BytesSent" ) {
            $type = "sent_bytes";
          }
          elsif ( $metricValue->{name}->{value} eq "Http2xx" ) {
            $type = "http_2xx";
          }
          elsif ( $metricValue->{name}->{value} eq "Http3xx" ) {
            $type = "http_3xx";
          }
          elsif ( $metricValue->{name}->{value} eq "Http4xx" ) {
            $type = "http_4xx";
          }
          elsif ( $metricValue->{name}->{value} eq "Http5xx" ) {
            $type = "http_5xx";
          }
          elsif ( $metricValue->{name}->{value} eq "AverageResponseTime" ) {
            $type = "response";
          }
          elsif ( $metricValue->{name}->{value} eq "AppConnections" ) {
            $type = "connections";
          }
          elsif ( $metricValue->{name}->{value} eq "FileSystemUsage" ) {
            $type = "filesystem_usage";
          }
          else {
            $type = "undef";
          }

          for ( @{ $metricValue->{timeseries} } ) {
            my $timeSerieData = $_;

            for ( @{ $timeSerieData->{data} } ) {
              my $timeData = $_;

              my $pretty_time = str2time( $timeData->{timeStamp} );

              if ( defined $timeData->{total} ) {
                $metricData{appService}{$appUUID}{$pretty_time}{$type} = $timeData->{total};
              }
              elsif ( defined $timeData->{average} ) {
                $metricData{appService}{$appUUID}{$pretty_time}{$type} = $timeData->{average};
              }
            }
          }
        }
      }

      my $databaseServers = $azure->getDatabaseServers( $resource, $subscription );

      for ( @{ $databaseServers->{value} } ) {
        my $databaseServer = $_;

        $confData{label}{databaseServer}{ $databaseServer->{id} }                   = $databaseServer->{name};
        $confData{specification}{databaseServer}{ $databaseServer->{id} }{id}       = $databaseServer->{id};
        $confData{specification}{databaseServer}{ $databaseServer->{id} }{name}     = $databaseServer->{name};
        $confData{specification}{databaseServer}{ $databaseServer->{id} }{type}     = $databaseServer->{type};
        $confData{specification}{databaseServer}{ $databaseServer->{id} }{version}  = $databaseServer->{properties}->{version};
        $confData{specification}{databaseServer}{ $databaseServer->{id} }{state}    = $databaseServer->{properties}->{state};
        $confData{specification}{databaseServer}{ $databaseServer->{id} }{login}    = $databaseServer->{properties}->{administratorLogin};
        $confData{specification}{databaseServer}{ $databaseServer->{id} }{domain}   = $databaseServer->{properties}->{fullyQualifiedDomainName};
        $confData{specification}{databaseServer}{ $databaseServer->{id} }{public}   = $databaseServer->{properties}->{publicNetworkAccess};
        $confData{specification}{databaseServer}{ $databaseServer->{id} }{location} = $databaseServer->{location};

        if ( exists $confData{architecture}{location_databaseServer}{ $databaseServer->{location} }[0] ) {
          push( @{ $confData{architecture}{location_databaseServer}{ $databaseServer->{location} } }, $databaseServer->{id} );
        }
        else {
          $confData{architecture}{location_databaseServer}{ $databaseServer->{location} }[0] = $databaseServer->{id};
        }

        my $databases = $azure->getDatabases( $resource, $subscription, $databaseServer->{name} );

        for ( @{ $databases->{value} } ) {
          my $database = $_;

          $confData{label}{database}{ $database->{properties}->{databaseId} }                       = $database->{name};
          $confData{specification}{database}{ $database->{properties}->{databaseId} }{id}           = $database->{properties}->{databaseId};
          $confData{specification}{database}{ $database->{properties}->{databaseId} }{name}         = $database->{name};
          $confData{specification}{database}{ $database->{properties}->{databaseId} }{location}     = $database->{location};
          $confData{specification}{database}{ $database->{properties}->{databaseId} }{collation}    = $database->{properties}->{collation};
          $confData{specification}{database}{ $database->{properties}->{databaseId} }{maxSizeBytes} = $database->{properties}->{maxSizeBytes};
          $confData{specification}{database}{ $database->{properties}->{databaseId} }{status}       = $database->{properties}->{status};
          $confData{specification}{database}{ $database->{properties}->{databaseId} }{server}       = $databaseServer->{name};

          if ( exists $confData{architecture}{databaseServer_database}{ $databaseServer->{id} }[0] ) {
            push( @{ $confData{architecture}{databaseServer_database}{ $databaseServer->{id} } }, $database->{properties}->{databaseId} );
          }
          else {
            $confData{architecture}{databaseServer_database}{ $databaseServer->{id} }[0] = $database->{properties}->{databaseId};
          }

          #metrics data
          #my $databaseMetrics = $azure->getMetricsDatabase($subscription->{resource}, $subscription->{subscription}, $databaseServer->{name}, $database->{name});

          #for (@{$databaseMetrics->{value}}) {
          #  my $metricValue = $_;
          #  for (@{$metricValue->{timeseries}}) {
          #    my $timeSerieData = $_;
          #
          #    for (@{$timeSerieData->{data}}) {
          #      my $timeData = $_;
          #      my $pretty_time = str2time($timeData->{timeStamp});
          #
          #      if (defined $timeData->{average}) {
          #        $metricData{database}{$database->{name}}{$pretty_time}{$metricValue->{name}->{value}} = $timeData->{average};
          #      } elsif (defined $timeData->{maximum}) {
          #        $metricData{database}{$database->{name}}{$pretty_time}{$metricValue->{name}->{value}} = $timeData->{maximum};
          #      } else {
          #        $metricData{database}{$database->{name}}{$pretty_time}{$metricValue->{name}->{value}} = 0;
          #      }
          #    }
          #  }
          #}
        }

      }

      if ( defined $metricData{vm} || defined $metricData{appService} ) {
        my $end = time() - 600;
        open my $hl, ">", $last_path . "/" . $subscription . "_" . $resource . "_last.json";
        print $hl "{\"timestamp\":\"$end\"}";
        close($hl);
      }

      print "Sub: $sub, res: $resource - finished " . localtime() . "\n";

    }
  }

  if (%confData) {

    #save to JSON
    open my $fh, ">", $conf_path . "/conf_$name.json";
    print $fh JSON->new->pretty->encode( \%confData );
    close $fh;
  }

  if (%metricData) {
    my $time = time();

    #save to JSON
    open my $fh, ">", $perf_path . "/perf_" . $name . "_" . $time . ".json";
    print $fh JSON->new->pretty->encode( \%metricData );
    close $fh;
  }

}

print "\n";
