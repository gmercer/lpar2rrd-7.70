use 5.008_008;

use strict;
use warnings;

use GoogleCloud;
use HostCfg;
use Data::Dumper;
use JSON;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $cfgdir   = "$inputdir/etc/web_config";

my $timeout = 900;

my $data_path = "$inputdir/data/GCloud";
my $perf_path = "$data_path/json";
my $conf_path = "$inputdir/data/GCloud/conf";

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
}

my %hosts = %{ HostCfg::getHostConnections('GCloud') };
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
      local $SIG{ALRM} = sub { die "GCloud API2JSON: $pid timeouted.\n"; };
      alarm($timeout);

      my $uuid = defined $hosts{$host}{uuid} ? $hosts{$host}{uuid} : $host;

      my ( $name, $credentials ) = ( $hosts{$host}{hostalias}, $hosts{$host}{credentials} );
      api2json( $name, $credentials, $uuid );
      exit;
    }
  }
}

# wait for forked data retrieval
for $pid (@pids) {
  waitpid( $pid, 0 );
}

print "Configuration                : merging and saving, " . localtime();

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

  foreach my $key ( keys %{ $data->{engines} } ) {
    $conf{engines}{$key} = $data->{engines}->{$key};
  }

}

print "\n";

if (%conf) {
  open my $fa, ">", $data_path . "/conf.json";
  print $fa JSON->new->pretty->encode( \%conf );
  close $fa;
}

sub api2json {
  my ( $name, $credentials, $uuid ) = @_;

  my $gcloud = GoogleCloud->new( $name, $credentials, 1, $uuid );

  my $instances = $gcloud->listInstances(1);

  if ($instances) {

    #save to JSON
    open my $fh, ">", $conf_path . "/conf_" . $name . ".json";
    print $fh JSON->new->pretty->encode($instances);
    close $fh;
  }

  my $metrics = $gcloud->getMetrics();
  if ($metrics) {
    my $time = time();

    #save to JSON
    open my $fh, ">", $perf_path . "/perf_" . $name . "_" . $time . ".json";
    print $fh JSON->new->pretty->encode($metrics);
    close $fh;
  }

}
