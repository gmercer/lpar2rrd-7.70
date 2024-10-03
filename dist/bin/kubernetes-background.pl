use 5.008_008;

use strict;
use warnings;

use Kubernetes;
use HostCfg;
use Data::Dumper;
use JSON;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir        = $ENV{INPUTDIR};
my $data_path       = "$inputdir/data/Kubernetes";
my $perf_path       = "$data_path/json";
my $csv_path        = "$data_path/csv";
my $background_path = "$data_path/background";

if ( keys %{ HostCfg::getHostConnections('Kubernetes') } == 0 ) {
  exit(0);
}

unless ( -d $perf_path ) {
  mkdir( "$perf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $perf_path: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $csv_path ) {
  mkdir( "$csv_path", 0755 ) || warn( localtime() . ": Cannot mkdir $csv_path: $!" . __FILE__ . ':' . __LINE__ );
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
  my $background_data;
  eval { $background_data = decode_json($background_json); };
  if ($@) {
    my $error = $@;
    warn("Empty bg pid file, deleting $background_path/$file");
    unlink "$background_path/$file";
    next;
  }
  
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

my %hosts = %{ HostCfg::getHostConnections('Kubernetes') };
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

      my ( $name, $host, $port, $token, $protocol, $container, $namespaces, $monitor ) = ( $hosts{$host}{hostalias}, $hosts{$host}{host}, $hosts{$host}{api_port}, $hosts{$host}{token}, $hosts{$host}{protocol}, $hosts{$host}{container}, $hosts{$host}{namespaces}, $hosts{$host}{monitor} );

      my $resolution_json = '';
      if ( open( my $fh, '<', "$data_path/resolution_$name.json" ) ) {
        while ( my $row = <$fh> ) {
          chomp $row;
          $resolution_json .= $row;
        }
        close($fh);
      }

      my $resolution;
      my $resolution_data = decode_json($resolution_json);
      if ( ref($resolution_data) ne "HASH" ) {
        warn( localtime() . ": Error decoding JSON in resolution file: missing data" );
      }
      else {
        if ( $resolution_data->{node} < $resolution_data->{pod} ) {
          $resolution = $resolution_data->{node};
        }
        else {
          $resolution = $resolution_data->{pod};
        }
      }

      my $limit = 20 * ( 60 / $resolution );

      for ( 1 .. $limit ) {
	eval {
          api2json( $name, $host, $port, $token, $protocol, $uuid, $resolution, $container, $namespaces, $monitor );
        };
        warn $@ if $@;
	sleep($resolution);
      }

      exit;
    }
  }
}

sub api2json {
  my ( $name, $host, $port, $token, $protocol, $uuid, $resolution, $container, $namespaces, $monitor ) = @_;

  my $kubernetes = Kubernetes->new( $name, $host, $token, $protocol, $uuid, $container, $namespaces, $monitor );

  my $perf = $kubernetes->getMetricsData($resolution);
  my $time = time();

  #if ($perf) {
  #  open my $fh, ">", $perf_path."/perf_".$name."_".$time.".json";
  #  print $fh JSON->new->pretty(0)->encode($perf);
  #  close $fh;
  #}

  if ($perf) {
    my $csv = Kubernetes::json2csv($perf);
    if ($csv) {
      open my $fhc, ">", $csv_path . "/perf_" . $name . "_" . $time . ".csv";
      print $fhc $csv;
      close $fhc;
    }
  }

}

