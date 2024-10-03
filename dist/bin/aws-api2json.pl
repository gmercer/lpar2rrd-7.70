use 5.008_008;

use strict;
use warnings;

use HostCfg;
if ( keys %{ HostCfg::getHostConnections('AWS') } == 0 ) {
  exit(0);
}

require AmazonWebServices;
require AWSDataWrapper;
use Data::Dumper;
use JSON;
require Xorux_lib;


defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $cfgdir   = "$inputdir/etc/web_config";

my $timeout        = 900;
my $reload_regions = 0;

my $data_path = "$inputdir/data/AWS";
my $perf_path = "$data_path/json";
my $conf_path = "$data_path/conf";

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

my %hosts = %{ HostCfg::getHostConnections('AWS') };
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
      local $SIG{ALRM} = sub { die "AWS API2JSON: $pid timeouted.\n"; };
      alarm($timeout);

      my $uuid = defined $hosts{$host}{uuid} ? $hosts{$host}{uuid} : $host;

      my ( $name, $interval, $aws_access_key_id, $aws_secret_access_key, $regions ) = ( $hosts{$host}{hostalias}, $hosts{$host}{interval}, $hosts{$host}{aws_access_key_id}, $hosts{$host}{aws_secret_access_key}, $hosts{$host}{regions} );
      api2json( $name, $interval, $aws_access_key_id, $aws_secret_access_key, $regions, $uuid );
      exit;
    }
  }
}

# wait for forked data retrieval
for $pid (@pids) {
  waitpid( $pid, 0 );
}

print "Configuration             : merging and saving, " . localtime();

opendir( DH, "$conf_path" ) || die "Could not open '$conf_path' for reading '$!'\n";
my @files = grep /.*.json/, readdir DH;
my %conf;
foreach my $file ( sort @files ) {
  if ( !defined $conf_hash{$file} ) {
    print "\nSkipping old conf            : $file, " . localtime();
    next;
  }
  print "\nConfiguration processing  : $file, " . localtime();

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

}

if (%conf) {
  open my $fa, ">", $data_path . "/conf.json";
  print $fa JSON->new->pretty->encode( \%conf );
  close $fa;
}

print "\n";

sub api2json {
  my ( $name, $interval, $aws_access_key_id, $aws_secret_access_key, $regions, $uuid ) = @_;

  my $aws = AmazonWebServices->new( $interval, $name, $uuid );

  $aws->set_aws_access_key_id($aws_access_key_id);
  my $aws_secret_access_key_unobscure = HostCfg::unobscure_password($aws_secret_access_key);
  $aws->set_aws_secret_access_key($aws_secret_access_key_unobscure);

  if ( $reload_regions == 1 ) {

    #check all regions and save to conf
    my $all_regions = $aws->get_all_regions();

    # read file
    my $cfg_json = '';
    if ( open( my $fh, '<', "$cfgdir/hosts.json" ) ) {
      while ( my $row = <$fh> ) {
        chomp $row;
        $cfg_json .= $row;
      }
      close($fh);
    }
    else {
      warn( localtime() . ": Cannot open the file hosts.json ($!)" ) && next;
      next;
    }

    # decode JSON
    my $cfg_hash = decode_json($cfg_json);
    if ( ref($cfg_hash) ne "HASH" ) {
      warn( localtime() . ": Error decoding JSON in file hosts.json: missing data" ) && next;
    }

    if ( defined $all_regions && ref($all_regions) eq 'ARRAY' ) {
      @{ $cfg_hash->{platforms}->{AWS}->{aliases}->{$name}->{'available_regions'} } = @{$all_regions};

      my $json_print = JSON->new->allow_nonref;
      if ( open( CFG, ">$cfgdir/hosts.json" ) ) {
        print CFG $json_print->pretty->encode( \%{$cfg_hash} );
        close CFG;
      }
      else {
        warn( localtime() . ": Cannot open the file hosts.json ($!)" ) && next;
        next;
      }
    }

  }

  for ( @{$regions} ) {
    my $region = $_;
    $aws->add_region($region);
  }

  my %conf = $aws->get_configuration();

  my $time = time();

  if (%conf) {

    #save to JSON
    #open my $fh, ">", $conf_path . "/conf_$name.json";
    #print $fh JSON->new->pretty->encode( \%conf );
    #close $fh;
    
    Xorux_lib::write_json($conf_path . "/conf_$name.json", \%conf);
  }

  my %data = $aws->get_metrics();
  $data{region} = $conf{specification}{region};

  #print Dumper(%data);

  if (%data) {

    #save to JSON
    open my $fh, ">", $perf_path . "/perf_" . $name . "_" . $time . ".json";
    print $fh JSON->new->pretty->encode( \%data );
    close $fh;
  }

}

