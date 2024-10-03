package Azure;

use strict;
use warnings;

use XML::Parser;
use HTTP::Request::Common;
use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir  = $ENV{INPUTDIR};
my $conf_path = "$inputdir/data/Azure";
my $last_path = "$conf_path/last";

unless ( -d $conf_path ) {
  mkdir( "$conf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $conf_path: $!" . __FILE__ . ':' . __LINE__ );
}

sub new {
  my ( $self, $tenant, $client, $secret, $diagnostics ) = @_;
  my $o = {};

  my $token = &getToken( $tenant, $client, $secret );

  $o->{token} = $token;

  $o->{diagnostics} = ( defined $diagnostics ) ? $diagnostics : 0;

  bless $o, $self;
  return $o;
}

sub getToken {
  my $tenant = shift;
  my $client = shift;
  my $secret = shift;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  my %data;
  $data{grant_type}    = "client_credentials";
  $data{client_id}     = $client;
  $data{client_secret} = $secret;
  $data{resource}      = "https://management.azure.com/";

  my $response = $ua->post( "https://login.microsoftonline.com/$tenant/oauth2/token", \%data );

  if ( $response->is_success ) {
    my $resp = $json->decode( $response->content );

    #print Dumper($resp);

    return $resp->{access_token};
  }
  else {
    error_die("ERROR: Can't handle login request, bad credentials?");
    return 1;
  }

  return 0;
}

sub testToken {
  my $tenant = shift;
  my $client = shift;
  my $secret = shift;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  my %data;
  $data{grant_type}    = "client_credentials";
  $data{client_id}     = $client;
  $data{client_secret} = $secret;
  $data{resource}      = "https://management.azure.com/";

  my $response = $ua->post( "https://login.microsoftonline.com/$tenant/oauth2/token", \%data );

  if ( $response->is_success ) {
    my $resp = $json->decode( $response->content );

    #print Dumper($resp);

    return $resp->{access_token};
  }
  else {
    return 0;
  }

}

sub getInstances {
  my ( $self, $resource, $subscription ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $response = $ua->get("https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Compute/virtualMachines?api-version=2019-12-01");

  my $resp = $json->decode( $response->content );

  #print Dumper($resp);

  return $resp;
}

sub getSubscription {
  my ( $self, $subscription ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $response = $ua->get("https://management.azure.com/subscriptions/$subscription?api-version=2016-06-01");

  my $resp = $json->decode( $response->content );

  return $resp->{displayName};

}

sub getResourceGroups {
  my ( $self, $subscription ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $response = $ua->get("https://management.azure.com/subscriptions/$subscription/resourcegroups?api-version=2020-06-01");

  my $resp = $json->decode( $response->content );

  my $resources;
  for ( @{ $resp->{value} } ) {
    my $res = $_;
    push( @{$resources}, $res->{name} );
  }

  return $resources;
}

sub getAppServices {
  my ( $self, $resource, $subscription ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $response = $ua->get("https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Web/sites?api-version=2019-08-01");

  my $resp = $json->decode( $response->content );

  #print Dumper($resp);

  return $resp;
}

sub getDatabaseServers {
  my ( $self, $resource, $subscription ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $response = $ua->get("https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Sql/servers?api-version=2019-06-01-preview");

  my $resp = $json->decode( $response->content );

  #print Dumper($resp);

  return $resp;

}

sub getDatabases {
  my ( $self, $resource, $subscription, $server ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $response = $ua->get("https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Sql/servers/$server/databases?api-version=2017-10-01-preview");

  my $resp = $json->decode( $response->content );

  #print Dumper($resp);

  return $resp;

}

sub getAgentMetrics {
  my ( $self, $resource, $subscription, $vm ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $response = $ua->get("https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Compute/virtualMachines/$vm/metricDefinitions?api-version=2014-04-01");

  my $resp = $json->decode( $response->content );

  #print Dumper($resp);

  if ( !defined $resp->{value} || scalar @{ $resp->{value} } == 0 ) {
    return ();
  }

  my %data;

  for ( @{ $resp->{value} } ) {
    my $metric = $_;
    if ( !defined $metric->{metricAvailabilities}->[0]->{location}->{tableInfo}->[0]->{sasToken} ) {
      next;
    }
    if ( $metric->{name}->{value} ne "/builtin/memory/usedmemory" && $metric->{name}->{value} ne "/builtin/memory/availablememory" ) {
      next;
    }

    my $i          = 0;
    my $act_time   = time();
    my $check_time = str2time( $metric->{metricAvailabilities}->[0]->{location}->{tableInfo}->[$i]->{endTime} );

    while ( $check_time < $act_time ) {
      $i          = $i + 1;
      $check_time = str2time( $metric->{metricAvailabilities}->[0]->{location}->{tableInfo}->[$i]->{endTime} );
    }

    #print "\nURL: $metric->{metricAvailabilities}->[0]->{location}->{tableEndpoint}";
    #print "\nTable: $metric->{metricAvailabilities}->[0]->{location}->{tableInfo}->[0]->{tableName}";
    #print "\nToken: $metric->{metricAvailabilities}->[0]->{location}->{tableInfo}->[0]->{sasToken}";

    if ( $metric->{name}->{value} eq "/builtin/memory/usedmemory" ) {
      $data{usedMemory} = getAgentMetricRequest( $metric->{metricAvailabilities}->[0]->{location}->{tableEndpoint}, $metric->{metricAvailabilities}->[0]->{location}->{tableInfo}->[$i]->{tableName}, $metric->{metricAvailabilities}->[0]->{location}->{tableInfo}->[$i]->{sasToken}, "/builtin/memory/usedmemory", "usedMemory" );
    }
    elsif ( $metric->{name}->{value} eq "/builtin/memory/availablememory" ) {
      $data{freeMemory} = getAgentMetricRequest( $metric->{metricAvailabilities}->[0]->{location}->{tableEndpoint}, $metric->{metricAvailabilities}->[0]->{location}->{tableInfo}->[$i]->{tableName}, $metric->{metricAvailabilities}->[0]->{location}->{tableInfo}->[$i]->{sasToken}, "/builtin/memory/availablememory", "freeMemory" );
    }

  }

  return \%data;

}

sub getAgentMetricRequest {
  my ( $url, $table, $sasToken, $metricName, $prettyName ) = @_;
  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 15,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  my %data;

  my $response;
  eval { $response = $ua->get( $url . $table . $sasToken . "&\$filter=CounterName%20eq%20'" . $metricName . "'&\$top=25" ); };
  if ($@) {
    return ();
  }

  my $parser = XML::Parser->new( Style => 'Tree' );
  my $ref;
  eval { $ref = $parser->parse( $response->content ); };
  if ($@) {
    return ();
  }

  if ( defined $ref->[1]->[10]->[14] ) {
    my $actual = 10;
    my $time;
    my $value;
    while ( defined $ref->[1]->[$actual]->[14] ) {
      $time        = $ref->[1]->[$actual]->[14]->[2]->[6]->[2];
      $time        = str2time($time);
      $time        = int( $time - ( $time % 60 ) );
      $value       = $ref->[1]->[$actual]->[14]->[2]->[8]->[2];
      $value       = $value / 1024 / 1024;
      $data{$time} = $value;
      $actual      = $actual + 2;
    }

    #print Dumper($ref->[1]->[10]->[14]->[2]);
  }

  return \%data;

}

sub getNetwork {
  my ( $self, $url ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $response = $ua->get("https://management.azure.com$url/?api-version=2020-05-01");

  my $resp = $json->decode( $response->content );

  #print Dumper($resp);

  return $resp;
}

sub getIpAdress {
  my ( $self, $url ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $response = $ua->get("https://management.azure.com$url/?api-version=2020-05-01");

  my $resp = $json->decode( $response->content );

  #print Dumper($resp);

  return $resp;
}

sub getInstanceView {
  my ( $self, $resource, $subscription, $vm ) = @_;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 20,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $again = 0;
  my $response;
  my $resp;

  eval {
    $response = $ua->get("https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Compute/virtualMachines/$vm/instanceView?api-version=2019-12-01");
    $resp     = $json->decode( $response->content );
  };
  if ($@) {
    $again = 1;
  }

  if ( $again eq "1" ) {
    sleep(3);

    eval {
      $response = $ua->get("https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Compute/virtualMachines/$vm/instanceView?api-version=2019-12-01");
      $resp     = $json->decode( $response->content );
    };
    if ($@) {
      $again = 2;
    }

  }

  #print Dumper($resp);

  if ( $again eq "2" ) {
    return ();
  }
  else {
    return $resp;
  }
}

sub getMetrics {
  my ( $self, $resource, $vm, $subscription, $timestamp_from, $timestamp ) = @_;

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($timestamp_from);
  $year += 1900;
  $mon  += 1;
  my $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
  my $start_time = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";

  ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($timestamp);
  $year += 1900;
  $mon  += 1;
  $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
  my $end_time = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $metrics = "Percentage CPU,Disk Read Bytes,Disk Write Bytes,Disk Read Operations/Sec,Disk Write Operations/Sec,Network In Total,Network Out Total";

  my $response = $ua->get( "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Compute/virtualMachines/$vm/providers/microsoft.insights/metrics?metricnames=$metrics&timespan=" . $start_time . "Z/" . $end_time . "Z&aggregation=Average&api-version=2018-01-01" );

  my $resp = $json->decode( $response->content );
  #print Dumper($resp);

  #my $definitions = $ua->get( "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Compute/virtualMachines/$vm/providers/microsoft.insights/metricDefinitions?api-version=2018-01-01" );
  #print Dumper($json->decode( $definitions->content ));

  return $resp;

}

sub getAppMetrics {
  my ( $self, $resource, $appService, $subscription, $timestamp_from, $timestamp ) = @_;

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($timestamp_from);
  $year += 1900;
  $mon  += 1;
  my $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
  my $start_time = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";

  ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($timestamp);
  $year += 1900;
  $mon  += 1;
  $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
  my $end_time = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 15,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $metrics = "CpuTime,Requests,BytesReceived,BytesSent,Http2xx,Http3xx,Http4xx,Http5xx,AverageResponseTime,AppConnections,IoReadBytesPerSecond,IoWriteBytesPerSecond,IoReadOperationsPerSecond,IoWriteOperationsPerSecond";

  my $response = $ua->get( "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Web/sites/$appService/providers/microsoft.insights/metrics?metricnames=$metrics&timespan=" . $start_time . "Z/" . $end_time . "Z&api-version=2018-01-01" );

  my $resp;
  eval { $resp = $json->decode( $response->content ); };
  if ($@) {
    return ();
  }

  #print "\nStart: $start_time End: $end_time\n";
  #print "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Web/sites/$appService/providers/microsoft.insights/metrics?metricnames=$metrics&timespan=".$start_time."Z/".$end_time."Z&api-version=2018-01-01";

  return $resp;

}

sub getMetricsDatabase {
  my ( $self, $resource, $subscription, $server, $database ) = @_;

  #Get last record
  my $lastHour       = time() - 600;
  my $timestamp_json = '';
  if ( open( my $fh, '<', $conf_path . "/" . $subscription . "_last.json" ) ) {
    while ( my $row = <$fh> ) {
      chomp $row;
      $timestamp_json .= $row;
    }
    close($fh);
  }
  else {
    open my $hl, ">", $conf_path . "/" . $subscription . "_last.json";
    $timestamp_json = "{\"timestamp\":\"$lastHour\"}";
    print $hl "{\"timestamp\":\"$lastHour\"}";
  }

  # decode JSON
  my $timestamp_data = decode_json($timestamp_json);
  if ( ref($timestamp_data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in timestamp file: missing data" ) && next;
  }

  my $timestamp = time();
  $timestamp = $timestamp - 180;
  my $timestamp_from = $timestamp_data->{timestamp};

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($timestamp_from);
  $year += 1900;
  $mon  += 1;
  my $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
  my $start_time = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";

  ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($timestamp);
  $year += 1900;
  $mon  += 1;
  $reformated = reformatTime( { 'month' => $mon, 'day' => $mday, 'hour' => $hour, 'min' => $min, 'sec' => $sec } );
  my $end_time = "$year-$reformated->{month}-$reformated->{day}T$reformated->{hour}:$reformated->{min}:$reformated->{sec}";
  my $json     = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $ua->default_header( Authorization => 'Bearer ' . $self->{token} );

  my $metrics = "allocated_data_storage,storage_percent,cpu_percent,physical_data_read_percent,log_write_percent,dtu_consumption_percent,storage,connection_successful,connection_failed,blocked_by_firewall,deadlock";

  my $response = $ua->get( "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resource/providers/Microsoft.Sql/servers/$server/databases/$database/providers/microsoft.insights/metrics?metricnames=$metrics&timespan=" . $start_time . "Z/" . $end_time . "Z&api-version=2018-01-01" );

  my $resp = $json->decode( $response->content );

  return $resp;

}

sub reformatTime {
  my ($time) = @_;
  my %data;
  foreach my $time_key ( keys %{$time} ) {
    $data{$time_key} = sprintf( "%02d", $time->{$time_key} );
  }
  return \%data;
}

sub error_die {
  my $message  = shift;
  my $act_time = localtime();
  print STDERR "$act_time: $message : $!\n";
  exit(1);
}

1;
