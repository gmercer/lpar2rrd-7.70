use 5.008_008;

use strict;
use warnings;

use Cloudstack;
use HostCfg;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use JSON;
use POSIX;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir        = $ENV{INPUTDIR};
my $data_path       = "$inputdir/data/Cloudstack";
my $perf_path       = "$data_path/json";
my $background_path = "$data_path/background";

if ( keys %{ HostCfg::getHostConnections('Cloudstack') } == 0 ) {
  exit(0);
}

unless ( -d $perf_path ) {
  mkdir( "$perf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $perf_path: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $background_path ) {
  mkdir( "$background_path", 0755 ) || warn( localtime() . ": Cannot mkdir $background_path: $!" . __FILE__ . ':' . __LINE__ );
}

opendir( DH, "$background_path" ) || die "Could not open '$background_path' for reading '$!'\n";
my @files = grep /.*.json/, readdir DH;
foreach my $file ( sort @files ) {
  my $background_json = '';
  if ( open( FH, '<', "$background_path/$file" ) ) {
    while ( my $row = <FH> ) {
      chomp $row;
      $background_json .= $row;
    }
    close(FH);
  }

  # decode JSON
  my $background_data = decode_json($background_json);
  if ( ref($background_data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in background file: missing data" );
  }
  else {
    if ( defined $background_data->{pid} ) {
      my $exists = kill 0, $background_data->{pid};
      if ($exists) {
        eval { system("kill -9  $background_data->{pid}"); }
      }
    }
  }
}

my %hosts = %{ HostCfg::getHostConnections('Cloudstack') };
my $pid;
my @pids;
my $timeout = 1200;

foreach my $host ( keys %hosts ) {
  unless ( defined( $pid = fork() ) ) {
    warn( localtime() . ": Error: failed to fork for $host.\n" );
    next;
  }
  else {
    if ($pid) {
      push @pids, $pid;
    }
    else {
      local $SIG{ALRM} = sub { exit(0); };
      alarm($timeout);
      my $my_pid   = $$;
      my %hash_pid = ( 'pid' => $my_pid );
      open my $fh, ">", $background_path . "/" . $hosts{$host}{hostalias} . ".json";
      print $fh JSON->new->pretty->encode( \%hash_pid );
      close $fh;

      my $uuid;
      if ( defined $hosts{$host}{uuid} ) {
        $uuid = $hosts{$host}{uuid};
      }
      else {
        $uuid = $hosts{$host}{hostalias};
      }

      my ( $name, $host, $port, $protocol, $username, $password ) = ( $hosts{$host}{hostalias}, $hosts{$host}{host}, $hosts{$host}{api_port}, $hosts{$host}{protocol}, $hosts{$host}{username}, $hosts{$host}{password} );

      my $limit = 20;
      my $sleep = 60;

      for ( 1 .. $limit ) {
        api2json( $name, $host, $port, $protocol, $username, $password, $uuid );
        sleep($sleep);
      }

      exit;

    }
  }
}

sub api2json {
  my ( $name, $host, $port, $protocol, $username, $password, $uuid ) = @_;

  my $cloudstack = Cloudstack->new( $name, $protocol, $host . ":" . $port );
  my $session    = $cloudstack->auth( $username, $password );

  #metrics data
  my $time             = time();
  my $hostsMetrics     = $cloudstack->getHostsMetrics();
  my $instancesMetrics = $cloudstack->getInstancesMetrics();
  my $volumesMetrics   = $cloudstack->getVolumesMetrics();
  my $primaryStorages  = $cloudstack->getPrimaryStorages();

  my %metricsData;
  foreach my $host ( @{ $hostsMetrics->{listhostsmetricsresponse}{host} } ) {
    if ( defined $host->{cpuusedghz} ) {
      $metricsData{host}{ $host->{id} }{$time}{networkkbswrite} = $host->{networkkbswrite};
      $metricsData{host}{ $host->{id} }{$time}{networkkbsread}  = $host->{networkkbsread};
      $metricsData{host}{ $host->{id} }{$time}{memoryallocated} = $host->{memoryallocated};
      $metricsData{host}{ $host->{id} }{$time}{memoryused}      = $host->{memoryused};
      $metricsData{host}{ $host->{id} }{$time}{memorytotal}     = $host->{memorytotal};
      $metricsData{host}{ $host->{id} }{$time}{cpuusedghz}      = ceil( removeChars( $host->{cpuusedghz} ) * 100 );
      $metricsData{host}{ $host->{id} }{$time}{cputotalghz}     = ceil( removeChars( $host->{cputotalghz} ) * 100 );
      $metricsData{host}{ $host->{id} }{$time}{cpuused}         = removeChars( $host->{cpuused} );
      $metricsData{host}{ $host->{id} }{$time}{cpunumber}       = $host->{cpunumber};
    }
  }

  foreach my $instance ( @{ $instancesMetrics->{listvirtualmachinesmetricsresponse}{virtualmachine} } ) {
    if ( defined $instance->{cpuused} ) {
      $metricsData{instance}{ $instance->{id} }{$time}{diskkbswrite}     = $instance->{diskkbswrite};
      $metricsData{instance}{ $instance->{id} }{$time}{diskkbsread}      = $instance->{diskkbsread};
      $metricsData{instance}{ $instance->{id} }{$time}{diskiopstotal}    = $instance->{diskiopstotal};
      $metricsData{instance}{ $instance->{id} }{$time}{diskiowrite}      = $instance->{diskiowrite};
      $metricsData{instance}{ $instance->{id} }{$time}{diskioread}       = $instance->{diskioread};
      $metricsData{instance}{ $instance->{id} }{$time}{memoryintfreekbs} = ( $instance->{memory} * 1000 gt $instance->{memoryintfreekbs} ) ? $instance->{memoryintfreekbs} : $instance->{memory} * 1000;
      $metricsData{instance}{ $instance->{id} }{$time}{memory}           = $instance->{memory};
      $metricsData{instance}{ $instance->{id} }{$time}{cpuused}          = ( defined removeChars( $instance->{cpuused} ) ) ? ceil( removeChars( $instance->{cpuused} ) ) : ();
      $metricsData{instance}{ $instance->{id} }{$time}{cpuspeed}         = $instance->{cpuspeed};
      $metricsData{instance}{ $instance->{id} }{$time}{networkread}      = ceil( removeChars( $instance->{networkread} ) );
      $metricsData{instance}{ $instance->{id} }{$time}{networkwrite}     = ceil( removeChars( $instance->{networkwrite} ) );
      $metricsData{instance}{ $instance->{id} }{$time}{networkkbsread}   = $instance->{networkkbsread};
      $metricsData{instance}{ $instance->{id} }{$time}{networkkbswrite}  = $instance->{networkkbswrite};
    }
  }

  foreach my $volume ( @{ $volumesMetrics->{listvolumesmetricsresponse}{volume} } ) {
    if ( defined $volume->{diskiopstotal} ) {
      $metricsData{volume}{ $volume->{id} }{$time}{diskiowrite}   = $volume->{diskiowrite};
      $metricsData{volume}{ $volume->{id} }{$time}{diskiopstotal} = $volume->{diskiopstotal};
      $metricsData{volume}{ $volume->{id} }{$time}{virtualsize}   = $volume->{virtualsize};
      $metricsData{volume}{ $volume->{id} }{$time}{size}          = $volume->{size};
      $metricsData{volume}{ $volume->{id} }{$time}{physicalsize}  = $volume->{physicalsize};
      $metricsData{volume}{ $volume->{id} }{$time}{diskkbswrite}  = $volume->{diskkbswrite};
      $metricsData{volume}{ $volume->{id} }{$time}{diskioread}    = $volume->{diskioread};
      $metricsData{volume}{ $volume->{id} }{$time}{diskkbsread}   = $volume->{diskkbsread};
      $metricsData{volume}{ $volume->{id} }{$time}{utilization}   = ceil( removeChars( $volume->{utilization} ) );
    }
  }

  foreach my $primaryStorage ( @{ $primaryStorages->{liststoragepoolsmetricsresponse}{storagepool} } ) {
    $metricsData{primaryStorage}{ $primaryStorage->{id} }{$time}{disksizetotalgb}  = ceil( parseChars( $primaryStorage->{disksizetotalgb}, 0 ) * 1024 );
    $metricsData{primaryStorage}{ $primaryStorage->{id} }{$time}{overprovisioning} = ceil( parseChars( $primaryStorage->{disksizetotalgb}, 1 ) * 1024 );
    $metricsData{primaryStorage}{ $primaryStorage->{id} }{$time}{disksizeusedgb}   = removeChars( $primaryStorage->{disksizeusedgb} ) * 1024;
    $metricsData{primaryStorage}{ $primaryStorage->{id} }{$time}{disksizeallocatedgb}   = removeChars( $primaryStorage->{disksizeallocatedgb} ) * 1024;
    $metricsData{primaryStorage}{ $primaryStorage->{id} }{$time}{disksizeunallocatedgb} = removeChars( $primaryStorage->{disksizeunallocatedgb} ) * 1024;
  }

  if (%metricsData) {
    open my $fh, ">", $perf_path . "/perf_" . $name . "_" . $time . ".json";
    print $fh JSON->new->pretty(0)->encode( \%metricsData );
    close $fh;
  }

}

sub parseChars {
  my $string         = shift;
  my $multiplication = shift;

  my $num = 1;
  my @spl = split( '\(x', $string );
  if ( defined $spl[1] ) {
    if ( defined $multiplication && $multiplication eq "1" ) {
      $num = $spl[1];
      $num =~ s/\)//;
    }
    my $removed = removeChars( $spl[0] );
    return $removed * $num;
  }
  else {
    return removeChars($string);
  }
}

sub removeChars {
  my $string = shift;

  if ( !defined $string || !length $string ) {
    return ();
  }

  $string =~ tr/%//d;

  chop($string);
  if ( !looks_like_number($string) ) {
    $string = removeChars($string);
  }
  else {
    return $string * 1;
  }
}
