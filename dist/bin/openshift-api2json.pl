use 5.008_008;

use strict;
use warnings;

use Kubernetes;
use Openshift;
use HostCfg;
use Data::Dumper;
use JSON;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir  = $ENV{INPUTDIR};
my $data_path = "$inputdir/data/Openshift";
my $perf_path = "$data_path/json";
my $csv_path  = "$data_path/csv";
my $conf_path = "$data_path/conf";

if ( keys %{ HostCfg::getHostConnections('Openshift') } == 0 ) {
  exit(0);
}

unless ( -d $data_path ) {
  mkdir( "$data_path", 0755 ) || warn( localtime() . ": Cannot mkdir $data_path: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $perf_path ) {
  mkdir( "$perf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $perf_path: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $csv_path ) {
  mkdir( "$csv_path", 0755 ) || warn( localtime() . ": Cannot mkdir $csv_path: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $conf_path ) {
  mkdir( "$conf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $conf_path: $!" . __FILE__ . ':' . __LINE__ );
}

my %hosts = %{ HostCfg::getHostConnections('Openshift') };
my $pid;
my @pids;
my %conf_files;
my $timeout = 900;

foreach my $host ( keys %hosts ) {
  $conf_files{"conf_$hosts{$host}{hostalias}.json"}      = 1;
  $conf_files{"pods_$hosts{$host}{hostalias}.json"}      = 1;
  $conf_files{"openshift_$hosts{$host}{hostalias}.json"} = 1;
  unless ( defined( $pid = fork() ) ) {
    warn( localtime() . ": Error: failed to fork for $host.\n" );
    next;
  }
  else {
    if ($pid) {
      push @pids, $pid;
    }
    else {
      local $SIG{ALRM} = sub { die "K8S API2JSON: $pid timeouted.\n"; };
      alarm($timeout);

      my $uuid;
      if ( defined $hosts{$host}{uuid} ) {
        $uuid = $hosts{$host}{uuid};
      }
      else {
        $uuid = $hosts{$host}{hostalias};
      }

      my ( $name, $host, $port, $token, $protocol, $container, $namespaces, $monitor ) = ( $hosts{$host}{hostalias}, $hosts{$host}{host}, $hosts{$host}{api_port}, $hosts{$host}{token}, $hosts{$host}{protocol}, $hosts{$host}{container}, $hosts{$host}{namespaces}, $hosts{$host}{monitor} );
      api2json( $name, $host, $port, $token, $protocol, $uuid, $container, $namespaces, $monitor );
      exit;
    }
  }
}

# wait for forked data retrieval
for $pid (@pids) {
  waitpid( $pid, 0 );
}

print "Configuration             : merging and saving, " . localtime() . "\n";

opendir( DH, "$conf_path" ) || die "Could not open '$conf_path' for reading '$!'\n";
my @files = grep /.*.json/, readdir DH;
my %conf;
my %pods;
my %labels;
my %architecture;
my %openshift;
foreach my $file ( sort { $b cmp $a } @files ) {
  if ( !defined $conf_files{$file} ) {
    Kubernetes::log("Skipping old conf: $file");
    next;
  }

  my @splits = split /_/, $file;
  my $type   = $splits[0];

  if ( $type eq "pods" ) {
    Kubernetes::log("Pods processing: $file");
  }
  elsif ( $type eq "openshift" ) {
    Kubernetes::log("Openshift data processing: $file");
  }
  else {
    Kubernetes::log("Configuration processing: $file");
  }

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

  if ( $type eq "pods" ) {
    foreach my $podKey ( keys %{$data} ) {
      $pods{$podKey} = $data->{$podKey};
    }
  }
  elsif ( $type eq "openshift" ) {
    foreach my $key ( keys %{ $data->{infrastructure} } ) {
      foreach my $key2 ( keys %{ $data->{infrastructure}->{$key} } ) {
        $openshift{infrastructure}{$key}{$key2} = $data->{infrastructure}->{$key}->{$key2};
      }
    }
    foreach my $key ( keys %{ $data->{project} } ) {
      foreach my $key2 ( keys %{ $data->{project}->{$key} } ) {
        $openshift{project}{$key}{$key2} = $data->{project}->{$key}->{$key2};
      }
      if ( defined $data->{project}->{$key}->{name} ) {
        $labels{label}{project}{$key} = $data->{project}->{$key}->{name};
      }
    }
    foreach my $key ( keys %{ $data->{project_name} } ) {
      $openshift{project_name}{$key} = $data->{project_name}->{$key};
    }
  }
  else {
    foreach my $key ( keys %{ $data->{architecture} } ) {
      foreach my $key2 ( keys %{ $data->{architecture}->{$key} } ) {
        if ( !defined $architecture{architecture}{$key}{$key2} ) {
          $architecture{architecture}{$key}{$key2} = $data->{architecture}->{$key}->{$key2};
        }
        else {
          for ( @{ $data->{architecture}->{$key}->{$key2} } ) {
            my $value = $_;
            push( @{ $architecture{architecture}{$key}{$key2} }, $value );
          }
        }
      }
    }
    foreach my $key ( keys %{ $data->{specification} } ) {
      foreach my $key2 ( keys %{ $data->{specification}->{$key} } ) {
        $conf{specification}{$key}{$key2} = $data->{specification}->{$key}->{$key2};
      }
    }
    foreach my $key ( keys %{ $data->{label} } ) {
      foreach my $key2 ( keys %{ $data->{label}->{$key} } ) {
        $labels{label}{$key}{$key2} = $data->{label}->{$key}->{$key2};
      }
    }
  }
}

if (%pods) {
  open my $fh, ">", $data_path . "/pods.json";
  print $fh JSON->new->encode( \%pods );
  close $fh;
}

if (%conf) {
  open my $fh, ">", $data_path . "/conf.json";
  print $fh JSON->new->encode( \%conf );
  close $fh;
}

if (%labels) {
  open my $fh, ">", $data_path . "/labels.json";
  print $fh JSON->new->encode( \%labels );
  close $fh;
}

if (%architecture) {
  open my $fh, ">", $data_path . "/architecture.json";
  print $fh JSON->new->encode( \%architecture );
  close $fh;
}

if (%openshift) {
  open my $fh, ">", $data_path . "/openshift.json";
  print $fh JSON->new->encode( \%openshift );
  close $fh;
}

sub api2json {
  my ( $name, $host, $port, $token, $protocol, $uuid, $container, $namespaces, $monitor ) = @_;

  Kubernetes::log("start api2json", $name);

  my $kubernetes = Kubernetes->new( $name, $host, $token, $protocol, $uuid, $container, $namespaces, $monitor );

  my $conf       = $kubernetes->getConfiguration();
  my $pods       = $kubernetes->getPodsInfo();
  my $resolution = $kubernetes->metricResolution();

  if ($conf) {
    open my $fh, ">", $conf_path . "/conf_$name.json";
    print $fh JSON->new->pretty->encode($conf);
    close $fh;
  }

  if ($pods) {
    open my $fh, ">", $conf_path . "/pods_$name.json";
    print $fh JSON->new->pretty->encode($pods);
    close $fh;
  }

  if ($resolution) {
    open my $fh, ">", $data_path . "/resolution_$name.json";
    print $fh JSON->new->pretty->encode($resolution);
    close $fh;
  }

  my $openshift      = Openshift->new( $name, $host, $token, $protocol, $uuid );
  my $openshift_conf = $openshift->getConfiguration();

  if ($openshift_conf) {
    open my $fh, ">", $conf_path . "/openshift_$name.json";
    print $fh JSON->new->pretty->encode($openshift_conf);
    close $fh;
  }

  Kubernetes::log("end api2json", $name);

}
