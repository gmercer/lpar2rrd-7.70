use 5.008_008;

use strict;
use warnings;

use Cloudstack;
use HostCfg;
use Data::Dumper;
use JSON;
use Date::Parse qw(str2time);

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir  = $ENV{INPUTDIR};
my $data_path = "$inputdir/data/Cloudstack";
my $perf_path = "$data_path/json";
my $conf_path = "$data_path/conf";

if ( keys %{ HostCfg::getHostConnections('Cloudstack') } == 0 ) {
  exit(0);
}

unless ( -d $data_path ) {
  mkdir( "$data_path", 0755 ) || warn( localtime() . ": Cannot mkdir $data_path: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $perf_path ) {
  mkdir( "$perf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $perf_path: $!" . __FILE__ . ':' . __LINE__ );
}

unless ( -d $conf_path ) {
  mkdir( "$conf_path", 0755 ) || warn( localtime() . ": Cannot mkdir $conf_path: $!" . __FILE__ . ':' . __LINE__ );
}

my %hosts = %{ HostCfg::getHostConnections('Cloudstack') };
my $pid;
my @pids;
my %conf_files;
my $timeout = 900;

foreach my $host ( keys %hosts ) {
  $conf_files{"conf_$hosts{$host}{hostalias}.json"} = 1;
  unless ( defined( $pid = fork() ) ) {
    warn( localtime() . ": Error: failed to fork for $host.\n" );
    next;
  }
  else {
    if ($pid) {
      push @pids, $pid;
    }
    else {
      local $SIG{ALRM} = sub { die "Cloudstack API2JSON: $pid timeouted.\n"; };
      alarm($timeout);

      my $uuid;
      if ( defined $hosts{$host}{uuid} ) {
        $uuid = $hosts{$host}{uuid};
      }
      else {
        $uuid = $hosts{$host}{hostalias};
      }

      my ( $name, $host, $port, $protocol, $username, $password ) = ( $hosts{$host}{hostalias}, $hosts{$host}{host}, $hosts{$host}{api_port}, $hosts{$host}{protocol}, $hosts{$host}{username}, $hosts{$host}{password} );
      api2json( $name, $host, $port, $protocol, $username, $password, $uuid );
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
my %alert;
foreach my $file ( sort @files ) {
  if ( !defined $conf_files{$file} ) {
    print "Skipping old conf         : $file, " . localtime() . "\n";
    next;
  }

  print "Configuration processing  : $file, " . localtime() . "\n";

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
  foreach my $key ( keys %{ $data->{alert} } ) {
    foreach my $key2 ( keys %{ $data->{alert}->{$key} } ) {
      $alert{alert}{$key}{$key2} = $data->{alert}->{$key}->{$key2};
    }
  }
}

if (%conf) {
  open my $fh, ">", $data_path . "/conf.json";
  print $fh JSON->new->pretty->encode( \%conf );
  close $fh;
}

if (%labels) {
  open my $fh, ">", $data_path . "/labels.json";
  print $fh JSON->new->pretty->encode( \%labels );
  close $fh;
}

if (%architecture) {
  open my $fh, ">", $data_path . "/architecture.json";
  print $fh JSON->new->pretty->encode( \%architecture );
  close $fh;
}

if (%alert) {
  open my $fh, ">", $data_path . "/alert.json";
  print $fh JSON->new->pretty->encode( \%alert );
  close $fh;
}

sub api2json {
  my ( $name, $host, $port, $protocol, $username, $password, $uuid ) = @_;

  my $cloudstack = Cloudstack->new( $name, $protocol, $host . ":" . $port );
  my $session    = $cloudstack->auth( $username, $password );

  my $hosts             = $cloudstack->getHosts();
  my $instances         = $cloudstack->getInstances();
  my $volumes           = $cloudstack->getVolumes();
  my $alerts            = $cloudstack->getAlerts();
  my $events            = $cloudstack->getEvents();
  my $primaryStorages   = $cloudstack->getPrimaryStorages();
  my $secondaryStorages = $cloudstack->getSecondaryStorages();
  my $systemVMs         = $cloudstack->getSystemVMs();

  my %data;
  $data{label}{cloud}{$uuid} = $name;

  foreach my $host ( @{ $hosts->{listhostsresponse}{host} } ) {
    if ( defined $host->{hypervisor} ) {
      $data{label}{host}{ $host->{id} } = $host->{name};

      $data{specification}{host}{ $host->{id} }{name}        = $host->{name};
      $data{specification}{host}{ $host->{id} }{cpunumber}   = $host->{cpunumber};
      $data{specification}{host}{ $host->{id} }{state}       = $host->{state};
      $data{specification}{host}{ $host->{id} }{cpusockets}  = $host->{cpusockets};
      $data{specification}{host}{ $host->{id} }{clustername} = $host->{clustername};
      $data{specification}{host}{ $host->{id} }{ip}          = $host->{ipaddress};
      $data{specification}{host}{ $host->{id} }{hypervisor}  = $host->{hypervisor};

      if ( exists $data{architecture}{cloud_host}{$uuid}[0] ) {
        push( @{ $data{architecture}{cloud_host}{$uuid} }, $host->{id} );
      }
      else {
        $data{architecture}{cloud_host}{$uuid}[0] = $host->{id};
      }
    }
  }

  foreach my $volume ( @{ $volumes->{listvolumesresponse}{volume} } ) {
    $data{label}{volume}{ $volume->{id} } = $volume->{name};

    $data{specification}{volume}{ $volume->{id} }{name}     = $volume->{name};
    $data{specification}{volume}{ $volume->{id} }{state}    = $volume->{state};
    $data{specification}{volume}{ $volume->{id} }{size}     = $volume->{size};
    $data{specification}{volume}{ $volume->{id} }{zonename} = $volume->{zonename};

    if ( exists $data{architecture}{cloud_volume}{$uuid}[0] ) {
      push( @{ $data{architecture}{cloud_volume}{$uuid} }, $volume->{id} );
    }
    else {
      $data{architecture}{cloud_volume}{$uuid}[0] = $volume->{id};
    }
  }

  foreach my $instance ( @{ $instances->{listvirtualmachinesresponse}{virtualmachine} } ) {
    $data{label}{instance}{ $instance->{id} } = $instance->{name};

    $data{specification}{instance}{ $instance->{id} }{name}         = $instance->{name};
    $data{specification}{instance}{ $instance->{id} }{memory}       = $instance->{memory};
    $data{specification}{instance}{ $instance->{id} }{hypervisor}   = $instance->{hypervisor};
    $data{specification}{instance}{ $instance->{id} }{cpunumber}    = $instance->{cpunumber};
    $data{specification}{instance}{ $instance->{id} }{templatename} = $instance->{templatename};
    $data{specification}{instance}{ $instance->{id} }{state}        = $instance->{state};

    if ( exists $data{architecture}{cloud_instance}{$uuid}[0] ) {
      push( @{ $data{architecture}{cloud_instance}{$uuid} }, $instance->{id} );
    }
    else {
      $data{architecture}{cloud_instance}{$uuid}[0] = $instance->{id};
    }
  }

  foreach my $primaryStorage ( @{ $primaryStorages->{liststoragepoolsmetricsresponse}{storagepool} } ) {
    $data{label}{primaryStorage}{ $primaryStorage->{id} } = $primaryStorage->{name};

    $data{specification}{primaryStorage}{ $primaryStorage->{id} }{name}            = $primaryStorage->{name};
    $data{specification}{primaryStorage}{ $primaryStorage->{id} }{type}            = $primaryStorage->{type};
    $data{specification}{primaryStorage}{ $primaryStorage->{id} }{state}           = $primaryStorage->{state};
    $data{specification}{primaryStorage}{ $primaryStorage->{id} }{scope}           = $primaryStorage->{scope};
    $data{specification}{primaryStorage}{ $primaryStorage->{id} }{disksizetotalgb} = $primaryStorage->{disksizetotalgb};
    $data{specification}{primaryStorage}{ $primaryStorage->{id} }{disksizeusedgb}  = $primaryStorage->{disksizeusedgb};

    if ( exists $data{architecture}{cloud_primaryStorage}{$uuid}[0] ) {
      push( @{ $data{architecture}{cloud_primaryStorage}{$uuid} }, $primaryStorage->{id} );
    }
    else {
      $data{architecture}{cloud_primaryStorage}{$uuid}[0] = $primaryStorage->{id};
    }
  }

  foreach my $secondaryStorage ( @{ $secondaryStorages->{listimagestoresresponse}{imagestore} } ) {
    $data{label}{secondaryStorage}{ $secondaryStorage->{id} } = $secondaryStorage->{name};

    $data{specification}{secondaryStorage}{ $secondaryStorage->{id} }{name}          = $secondaryStorage->{name};
    $data{specification}{secondaryStorage}{ $secondaryStorage->{id} }{protocol}      = $secondaryStorage->{protocol};
    $data{specification}{secondaryStorage}{ $secondaryStorage->{id} }{disksizetotal} = $secondaryStorage->{disksizetotal};
    $data{specification}{secondaryStorage}{ $secondaryStorage->{id} }{disksizeused}  = $secondaryStorage->{disksizeused};

    if ( exists $data{architecture}{cloud_secondaryStorage}{$uuid}[0] ) {
      push( @{ $data{architecture}{cloud_secondaryStorage}{$uuid} }, $secondaryStorage->{id} );
    }
    else {
      $data{architecture}{cloud_secondaryStorage}{$uuid}[0] = $secondaryStorage->{id};
    }
  }

  foreach my $systemVM ( @{ $systemVMs->{listsystemvmsresponse}{systemvm} } ) {
    $data{label}{systemVM}{ $systemVM->{id} } = $systemVM->{name};

    $data{specification}{systemVM}{ $systemVM->{id} }{name}         = $systemVM->{name};
    $data{specification}{systemVM}{ $systemVM->{id} }{systemvmtype} = $systemVM->{systemvmtype};
    $data{specification}{systemVM}{ $systemVM->{id} }{hypervisor}   = $systemVM->{hypervisor};
    $data{specification}{systemVM}{ $systemVM->{id} }{privateip}    = $systemVM->{privateip};
    $data{specification}{systemVM}{ $systemVM->{id} }{state}        = $systemVM->{state};
    $data{specification}{systemVM}{ $systemVM->{id} }{agentstate}   = $systemVM->{agentstate};

    if ( exists $data{architecture}{cloud_systemVM}{$uuid}[0] ) {
      push( @{ $data{architecture}{cloud_systemVM}{$uuid} }, $systemVM->{id} );
    }
    else {
      $data{architecture}{cloud_systemVM}{$uuid}[0] = $systemVM->{id};
    }
  }

  my $timecheck = time() - 604800;
  foreach my $alert ( @{ $alerts->{listalertsresponse}{alert} } ) {
    my $alertTimestamp = str2time( $alert->{sent} );
    if ( $alertTimestamp gt $timecheck ) {
      $data{alert}{$uuid}{ $alert->{id} }{name}        = $alert->{name};
      $data{alert}{$uuid}{ $alert->{id} }{description} = $alert->{description};
      $data{alert}{$uuid}{ $alert->{id} }{sent}        = $alert->{sent};
      $data{alert}{$uuid}{ $alert->{id} }{cloud}       = $name;
    }
  }

  #foreach my $event (@{$events->{listeventsresponse}{event}}) {
  #  my $eventTimestamp = str2time($event->{created});
  #  print Dumper($event);
  #  if ($eventTimestamp gt $timecheck) {
  #    $data{event}{$uuid}{$event->{id}}{type} = $event->{type};
  #    $data{event}{$uuid}{$event->{id}}{description} = $event->{description};
  #    $data{event}{$uuid}{$event->{id}}{created} = $event->{created};
  #  }
  #}

  if (%data) {
    open my $fh, ">", $conf_path . "/conf_$name.json";
    print $fh JSON->new->pretty->encode( \%data );
    close $fh;
  }

}
