use 5.008_008;

use strict;
use warnings;

use Proxmox;
use HostCfg;
use Data::Dumper;
use JSON;
use Date::Parse qw(str2time);
use Digest::MD5 qw(md5_hex);

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir  = $ENV{INPUTDIR};
my $data_path = "$inputdir/data/Proxmox";
my $perf_path = "$data_path/json";
my $conf_path = "$data_path/conf";
my $last_path = "$data_path/last";

if ( keys %{ HostCfg::getHostConnections('Proxmox') } == 0 ) {
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

unless ( -d $last_path ) {
  mkdir( "$last_path", 0755 ) || warn( localtime() . ": Cannot mkdir $last_path: $!" . __FILE__ . ':' . __LINE__ );
}

my %hosts = %{ HostCfg::getHostConnections('Proxmox') };
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
      local $SIG{ALRM} = sub { die "Proxmox API2JSON: $pid timeouted.\n"; };
      alarm($timeout);

      my ( $name, $host, $port, $protocol, $username, $password, $domain, $backup_host ) = ( $hosts{$host}{hostalias}, $hosts{$host}{host}, $hosts{$host}{api_port}, $hosts{$host}{protocol}, $hosts{$host}{username}, $hosts{$host}{password}, $hosts{$host}{domain}, $hosts{$host}{backup_host} );
      api2json( $name, $host, $port, $protocol, $username, $password, $domain, $backup_host );
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
  my ( $name, $host, $port, $protocol, $username, $password, $domain, $backup_host ) = @_;

  my $proxmox = Proxmox->new( $protocol, $host, $port, $backup_host );
  my $auth    = $proxmox->authCredentials( $username, $password, $domain, $name );

  #my $auth = $proxmox->authToken('admin@pve!test', "22a04525-8c79-4331-a609-e8dd1fe74d01");

  #get last record
  my $timestamp_json = '';
  my $last           = time() - 1200;
  if ( open( my $fh, '<', $last_path . "/" . $name . "_last.json" ) ) {
    while ( my $row = <$fh> ) {
      chomp $row;
      $timestamp_json .= $row;
    }
    close($fh);
    my $timestamp_data = decode_json($timestamp_json);
    if ( ref($timestamp_data) ne "HASH" ) {
      warn( localtime() . ": Error decoding JSON in timestamp file: missing data" ) && next;
    }
    $last = $timestamp_data->{timestamp};
  }

  my %data;
  my %perf;
  my %tmp;

  #cluster
  my $cluster = $proxmox->getClusterName();

  my $cluster_id = md5_hex($cluster);
  $data{label}{cluster}{$cluster_id} = $cluster;

  #status
  #my $statuses = $proxmox->getStatus();
  #for (@{$statuses->{data}}) {
  #  my $status = $_;
  #
  #  print Dumper($status);
  #}

  #nodes
  my $nodes = $proxmox->getNodes();
  for ( @{ $nodes->{data} } ) {
    my $node = $_;

    my $node_id = md5_hex( $cluster . "-" . $node->{node} );
    $data{label}{node}{$node_id} = $node->{node};

    $data{specification}{node}{$node_id}{cluster} = $cluster;
    $data{specification}{node}{$node_id}{name}    = $node->{node};
    $data{specification}{node}{$node_id}{status}  = $node->{status};
    $data{specification}{node}{$node_id}{uptime}  = $node->{uptime};

    $data{specification}{node}{$node_id}{maxcpu}  = $node->{maxcpu};
    $data{specification}{node}{$node_id}{maxmem}  = $node->{maxmem};
    $data{specification}{node}{$node_id}{maxdisk} = $node->{maxdisk};

    if ( exists $data{architecture}{cluster_node}{$cluster_id}[0] ) {
      push( @{ $data{architecture}{cluster_node}{$cluster_id} }, $node_id );
    }
    else {
      $data{architecture}{cluster_node}{$cluster_id}[0] = $node_id;
    }

    #perf data
    my $node_metrics = $proxmox->getNodeMetrics( $node->{node} );
    for ( @{ $node_metrics->{data} } ) {
      my $node_metric = $_;

      if ( $node_metric->{time} < $last || !defined $node_metric->{cpu} ) {next}

      $perf{node}{$node_id}{ $node_metric->{time} }{swaptotal} = $node_metric->{swaptotal};
      $perf{node}{$node_id}{ $node_metric->{time} }{memused}   = $node_metric->{memused};
      $perf{node}{$node_id}{ $node_metric->{time} }{iowait}    = $node_metric->{iowait};
      $perf{node}{$node_id}{ $node_metric->{time} }{swapused}  = $node_metric->{swapused};
      $perf{node}{$node_id}{ $node_metric->{time} }{loadavg}   = $node_metric->{loadavg};
      $perf{node}{$node_id}{ $node_metric->{time} }{maxcpu}    = $node_metric->{maxcpu};
      $perf{node}{$node_id}{ $node_metric->{time} }{roottotal} = $node_metric->{roottotal};
      $perf{node}{$node_id}{ $node_metric->{time} }{rootused}  = $node_metric->{rootused};
      $perf{node}{$node_id}{ $node_metric->{time} }{cpu}       = $node_metric->{cpu};
      $perf{node}{$node_id}{ $node_metric->{time} }{memtotal}  = $node_metric->{memtotal};
      $perf{node}{$node_id}{ $node_metric->{time} }{netout}    = $node_metric->{netout};
      $perf{node}{$node_id}{ $node_metric->{time} }{netin}     = $node_metric->{netin};
    }

    #disks under node
    #my $disks = $proxmox->getNodeDisks($node->{node});
    #for (@{$disks->{data}}) {
    #  my $disk = $_;
    #
    # #print Dumper($disk);
    # #$data{label}{disk}{$disk->{id}} = $host->{name};
    #
    #}

    #vm under node
    my $vms = $proxmox->getNodeVMs( $node->{node} );
    for ( @{ $vms->{data} } ) {
      my $vm = $_;

      my $vm_id = md5_hex( $cluster . "-" . $vm->{vmid} );
      $data{label}{vm}{$vm_id} = $vm->{name};

      $data{specification}{vm}{$vm_id}{node}    = $node->{node};
      $data{specification}{vm}{$vm_id}{cluster} = $cluster;
      $data{specification}{vm}{$vm_id}{name}    = $vm->{name};
      $data{specification}{vm}{$vm_id}{maxmem}  = $vm->{maxmem};
      $data{specification}{vm}{$vm_id}{maxdisk} = $vm->{maxdisk};
      $data{specification}{vm}{$vm_id}{cpus}    = $vm->{cpus};
      $data{specification}{vm}{$vm_id}{status}  = $vm->{status};
      $data{specification}{vm}{$vm_id}{uptime}  = $vm->{uptime};

      if ( exists $data{architecture}{cluster_vm}{$cluster_id}[0] ) {
        push( @{ $data{architecture}{cluster_vm}{$cluster_id} }, $vm_id );
      }
      else {
        $data{architecture}{cluster_vm}{$cluster_id}[0] = $vm_id;
      }

      if ( exists $data{architecture}{node_vm}{$node_id}[0] ) {
        push( @{ $data{architecture}{node_vm}{$node_id} }, $vm_id );
      }
      else {
        $data{architecture}{node_vm}{$node_id}[0] = $vm_id;
      }

      #perf data
      my $vm_metrics = $proxmox->getVMMetrics( $node->{node}, $vm->{vmid} );
      for ( @{ $vm_metrics->{data} } ) {
        my $vm_metric = $_;

        if ( $vm_metric->{time} < $last || !defined $vm_metric->{cpu} ) { next; }

        $perf{vm}{$vm_id}{ $vm_metric->{time} }{maxmem}    = $vm_metric->{maxmem};
        $perf{vm}{$vm_id}{ $vm_metric->{time} }{disk}      = $vm_metric->{disk};
        $perf{vm}{$vm_id}{ $vm_metric->{time} }{diskread}  = $vm_metric->{diskread};
        $perf{vm}{$vm_id}{ $vm_metric->{time} }{maxdisk}   = $vm_metric->{maxdisk};
        $perf{vm}{$vm_id}{ $vm_metric->{time} }{diskwrite} = $vm_metric->{diskwrite};
        $perf{vm}{$vm_id}{ $vm_metric->{time} }{netin}     = $vm_metric->{netin};
        $perf{vm}{$vm_id}{ $vm_metric->{time} }{mem}       = $vm_metric->{mem};
        $perf{vm}{$vm_id}{ $vm_metric->{time} }{maxcpu}    = $vm_metric->{maxcpu};
        $perf{vm}{$vm_id}{ $vm_metric->{time} }{cpu}       = $vm_metric->{cpu};
        $perf{vm}{$vm_id}{ $vm_metric->{time} }{netout}    = $vm_metric->{netout};
      }
    }

    #lxc under node
    my $lxcs = $proxmox->getNodeLXCs( $node->{node} );
    for ( @{ $lxcs->{data} } ) {
      my $lxc = $_;

      my $lxc_id = md5_hex( $cluster . "-" . $lxc->{vmid} );
      $data{label}{lxc}{$lxc_id} = $lxc->{name};

      $data{specification}{lxc}{$lxc_id}{node}    = $node->{node};
      $data{specification}{lxc}{$lxc_id}{cluster} = $cluster;
      $data{specification}{lxc}{$lxc_id}{name}    = $lxc->{name};
      $data{specification}{lxc}{$lxc_id}{maxmem}  = $lxc->{maxmem};
      $data{specification}{lxc}{$lxc_id}{maxdisk} = $lxc->{maxdisk};
      $data{specification}{lxc}{$lxc_id}{cpus}    = $lxc->{cpus};
      $data{specification}{lxc}{$lxc_id}{status}  = $lxc->{status};
      $data{specification}{lxc}{$lxc_id}{uptime}  = $lxc->{uptime};

      if ( exists $data{architecture}{cluster_lxc}{$cluster_id}[0] ) {
        push( @{ $data{architecture}{cluster_lxc}{$cluster_id} }, $lxc_id );
      }
      else {
        $data{architecture}{cluster_lxc}{$cluster_id}[0] = $lxc_id;
      }

      if ( exists $data{architecture}{node_lxc}{$node_id}[0] ) {
        push( @{ $data{architecture}{node_lxc}{$node_id} }, $lxc_id );
      }
      else {
        $data{architecture}{node_lxc}{$node_id}[0] = $lxc_id;
      }

      #perf data
      my $lxc_metrics = $proxmox->getLXCMetrics( $node->{node}, $lxc->{vmid} );
      for ( @{ $lxc_metrics->{data} } ) {
        my $lxc_metric = $_;

        if ( $lxc_metric->{time} < $last || !defined $lxc_metric->{cpu} ) { next; }

        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{maxmem}    = $lxc_metric->{maxmem};
        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{disk}      = $lxc_metric->{disk};
        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{diskread}  = $lxc_metric->{diskread};
        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{maxdisk}   = $lxc_metric->{maxdisk};
        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{diskwrite} = $lxc_metric->{diskwrite};
        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{netin}     = $lxc_metric->{netin};
        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{mem}       = $lxc_metric->{mem};
        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{maxcpu}    = $lxc_metric->{maxcpu};
        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{cpu}       = $lxc_metric->{cpu};
        $perf{lxc}{$lxc_id}{ $lxc_metric->{time} }{netout}    = $lxc_metric->{netout};
      }
    }

    #storage under node
    my $storages = $proxmox->getNodeStorages( $node->{node} );
    for ( @{ $storages->{data} } ) {
      my $storage = $_;

      my $storage_id = md5_hex( $cluster . "-" . $node->{node} . "-" . $storage->{storage} );

      $data{label}{storage}{$storage_id} = $storage->{storage} . " (" . $node->{node} . ")";

      $data{specification}{storage}{$storage_id}{cluster} = $cluster;
      $data{specification}{storage}{$storage_id}{node}    = $node->{node};
      $data{specification}{storage}{$storage_id}{name}    = $storage->{storage} . " (" . $node->{node} . ")";
      $data{specification}{storage}{$storage_id}{active}  = $storage->{active};
      $data{specification}{storage}{$storage_id}{shared}  = $storage->{shared};
      $data{specification}{storage}{$storage_id}{type}    = $storage->{type};
      $data{specification}{storage}{$storage_id}{avail}   = $storage->{avail};
      $data{specification}{storage}{$storage_id}{used}    = $storage->{used};
      $data{specification}{storage}{$storage_id}{total}   = $storage->{total};
      $data{specification}{storage}{$storage_id}{content} = $storage->{content};
      $data{specification}{storage}{$storage_id}{enabled} = $storage->{enabled};

      if ( exists $data{architecture}{node_storage}{$node_id}[0] ) {
        push( @{ $data{architecture}{node_storage}{$node_id} }, $storage_id );
      }
      else {
        $data{architecture}{node_storage}{$node_id}[0] = $storage_id;
      }

      if ( defined $tmp{$storage_id} ) {
        next;
      }
      else {
        $tmp{$storage_id} = 1;
      }

      if ( exists $data{architecture}{cluster_storage}{$cluster_id}[0] ) {
        push( @{ $data{architecture}{cluster_storage}{$cluster_id} }, $storage_id );
      }
      else {
        $data{architecture}{cluster_storage}{$cluster_id}[0] = $storage_id;
      }

      #perf data
      my $storage_metrics = $proxmox->getStorageMetrics( $node->{node}, $storage->{storage} );
      for ( @{ $storage_metrics->{data} } ) {
        my $storage_metric = $_;

        if ( $storage_metric->{time} < $last || !defined $storage_metric->{used} ) {next}

        $perf{storage}{$storage_id}{ $storage_metric->{time} }{used}  = $storage_metric->{used};
        $perf{storage}{$storage_id}{ $storage_metric->{time} }{total} = $storage_metric->{total};
      }
    }

  }

  if (%data) {
    open my $fh, ">", $conf_path . "/conf_$name.json";
    print $fh JSON->new->pretty->encode( \%data );
    close $fh;
  }

  if (%perf) {

    #save to JSON
    my $time = time();
    open my $fh, ">", $perf_path . "/perf_" . $name . "_" . $time . ".json";
    print $fh JSON->new->pretty->encode( \%perf );
    close $fh;

    my $end = time() - 600;
    open my $hl, ">", $last_path . "/" . $name . "_last.json";
    print $hl "{\"timestamp\":\"$end\"}";
    close($hl);
  }

}
