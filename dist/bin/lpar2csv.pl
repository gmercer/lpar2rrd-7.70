
use warnings;
use strict;
use RRDp;
use Data::Dumper;
use Env qw(QUERY_STRING);
use Time::Local;
use File::Basename;
use Xorux_lib;

# main variables
my $basedir = $ENV{INPUTDIR};
my $rrdtool = $ENV{RRDTOOL};
my $tmpdir  = $ENV{TMPDIR_STOR} ||= "$basedir/tmp";
my $webdir  = $ENV{WEBDIR} ||= "$basedir/www";
my $bindir  = "$basedir/bin";
my $wrkdir  = "$basedir/data";

my $error_in_csv = 0;

my %custom_inventory;
my %vmware_inventory;

# csv variables
my $sep      = ";";      # csv separator
my $STEP     = 60;
my $act_unix = time();
my %data;

if ( defined $ENV{CSV_SEPARATOR} ) {
  $sep = $ENV{CSV_SEPARATOR};
}

my $buffer;
if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
  read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
}
else {
  $buffer = $ENV{'QUERY_STRING'};
}

# hash containing URL parameters. Use like this: $params{server}
my %params = %{ Xorux_lib::parse_url_params($buffer) };

#
# platform: POWER, VMWARE, HITACHI, ... e.g.
#
my $platform = ( $params{platform} ) ? $params{platform} : "";

if ( $params{subsys} && $params{subsys} eq "TOP" ) {
  top();
}
elsif ( $params{subsys} && $params{subsys} eq "RCA" ) {
  resource_configuration_advisor();
}
elsif ( $platform eq "POWER" ) {
  set_csv_for_power();
  print_data();
}
elsif ( $platform eq "VMWARE" ) {
  set_csv_for_vmware();
  print_data();
}
elsif ( $platform eq "OVIRT" ) {
  set_csv_for_ovirt();
  print_data();
}
elsif ( $platform eq "LINUX" ) {
  set_csv_for_linux();
  print_data();
}
else {
  error( "Unsupported platform \"$platform\"! " . __FILE__ . ":" . __LINE__ ) && exit;
}

exit;

sub print_data {
  if ( $error_in_csv == 1 ) { return 1; }    # error message was printed to csv file, e.g. case when RESPOOL has not VMs

  if ( !exists $data{NAME} || !exists $data{CSVHEADER} || !exists $data{STATS} ) {
    error( "Nothing to print! Probably unsupported subsystem or storage type! " . __FILE__ . ":" . __LINE__ );
    if ( defined $ENV{'QUERY_STRING'} ) {
      error("QUERY_STRING=$ENV{'QUERY_STRING'}");
    }
    exit;
  }

  my $header = "Time (DD.MM.YYYY HH:MM:SS)" . $sep . "name";
  my $name   = $data{NAME};

  # add items to header
  foreach ( sort { $a <=> $b } keys( %{ $data{CSVHEADER} } ) ) {
    $header .= $sep . $data{CSVHEADER}{$_};
  }

  print "Content-type: text/plain\n\n";
  print "$header\n";

  foreach my $timestamp ( sort { $a <=> $b } keys( %{ $data{STATS} } ) ) {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($timestamp);
    my $date = sprintf( "%02d.%02d.%4d %02d:%02d:%02d", $mday, $mon + 1, $year + 1900, $hour, $min, $sec );

    my $print_line = $date . $sep . $name;

    foreach my $stat_name_id ( sort { $a <=> $b } keys( %{ $data{CSVHEADER} } ) ) {
      my $value     = '';
      my $stat_name = $data{CSVHEADER}{$stat_name_id};
      if ( defined $data{STATS}{$timestamp}{$stat_name} && isdigit( $data{STATS}{$timestamp}{$stat_name} ) ) {
        $value = $data{STATS}{$timestamp}{$stat_name};
      }
      $print_line .= $sep . $value;
    }
    print "$print_line\n";
  }

  return 1;
}

sub resource_configuration_advisor {
  my $platform = ( $params{platform} ) ? $params{platform} : "";
  my $item     = ( $params{item} )     ? $params{item}     : "";
  my $time     = ( $params{time} )     ? $params{time}     : "";

  if ( !defined $item     || $item eq '' )     { error( "Not defined item!" . __FILE__ . ":" . __LINE__ )     && return 0; }
  if ( !defined $time     || $time eq '' )     { error( "Not defined time!" . __FILE__ . ":" . __LINE__ )     && return 0; }
  if ( !defined $platform || $platform eq '' ) { error( "Not defined platform!" . __FILE__ . ":" . __LINE__ ) && return 0; }

  my $time_string = "";
  my $item_string = "";
  my $csv_in      = "";

  if ( $time eq "day" ) {
    $time_string = "daily";
  }
  elsif ( $time eq "week" ) {
    $time_string = "weekly";
  }
  elsif ( $time eq "month" ) {
    $time_string = "monthly";
  }
  else {
    error( "Unsupported time=\"$time\"!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  if ( $item eq "rep_cpu" ) {
    $item_string = "cpu";
  }
  elsif ( $item eq "rep_mem" ) {
    $item_string = "mem";
  }
  else {
    error( "Unsupported item=\"$item\"!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  if ( $platform eq "POWER" ) {
    $csv_in = "$webdir/$item_string" . "_config_advisor_$time_string.csv";
  }
  elsif ( $platform eq "VMWARE" ) {
    $csv_in = "$webdir/$item_string" . "_config_advisor_$time_string" . "_vm.csv";
  }
  else {
    error( "Unsupported platform=\"$platform\"!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  if ( !-f $csv_in ) { error( "Data source file \"$csv_in\" does not exists!" . __FILE__ . ":" . __LINE__ ) && return 0; }

  print "Content-type: text/plain\n\n";

  open( IN, "< $csv_in" ) || error( "Couldn't open file $csv_in $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print <IN>;
  close(IN);

  return 1;
}

sub top {
  my $platform = ( $params{platform} ) ? $params{platform} : "";
  my $item     = ( $params{item} )     ? $params{item}     : "";
  my $time     = ( $params{time} )     ? $params{time}     : "";
  my $limit    = ( $params{limit} )    ? $params{limit}    : "";
  my $global   = 0;
  my $period   = "";
  my $stat_name = $item;

  if ( !defined $item     || $item eq '' )     { error( "Not defined item!" . __FILE__ . ":" . __LINE__ )     && return 0; }
  if ( !defined $time     || $time eq '' )     { error( "Not defined time!" . __FILE__ . ":" . __LINE__ )     && return 0; }
  if ( !defined $platform || $platform eq '' ) { error( "Not defined platform!" . __FILE__ . ":" . __LINE__ ) && return 0; }

  my %selected_servers;
  if ( exists $params{server} ) {
    if ( ref( $params{server} ) eq "ARRAY" ) {
      foreach ( @{ $params{server} } ) {
        $selected_servers{$_} = $_;
      }
    }
    elsif ( $params{server} eq "XOR-GLOBAL-XOR" ) {
      $global = 1;
    }
    elsif ( $params{server} ne '' ) {
      $selected_servers{ $params{server} } = $params{server};
    }
  }

  my @lines;
  if ( $platform eq "POWER" && -f "$tmpdir/topten.tmp" ) {
    open( TOP, "< $tmpdir/topten.tmp" ) || error( "Couldn't open file $tmpdir/topten.tmp $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @lines = <TOP>;
    close(TOP);
  }
  elsif ( $platform eq "VMWARE" && -f "$tmpdir/topten_vm.tmp" ) {
    open( TOP, "< $tmpdir/topten_vm.tmp" ) || error( "Couldn't open file $tmpdir/topten_vm.tmp $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @lines = <TOP>;
    close(TOP);
  }

  if ( $item eq "rep_cpu" )     { $stat_name = "CPU"; }
  if ( $item eq "rep_saniops" ) { $stat_name = "SAN-IOPS"; }
  if ( $item eq "rep_iops" )    { $stat_name = "IOPS"; }
  if ( $item eq "rep_disk" )    { $stat_name = "DISK"; }
  if ( $item eq "rep_san" )     { $stat_name = "SAN"; }
  if ( $item eq "rep_lan" )     { $stat_name = "LAN"; }

  my %data;
  foreach my $line (@lines) {
    chomp $line;
    my $metric = "";
    my $server = "";
    my $name   = "";
    my $stat_d = "";
    my $stat_w = "";
    my $stat_m = "";
    my $stat_y = "";

    if ( $platform eq "POWER" || ( $platform eq "VMWARE" && $item ne "rep_iops" ) ) {
      ( $metric, $server, $name, undef, $stat_d, $stat_w, $stat_m, $stat_y ) = split( ",", $line );
    }
    elsif ( $platform eq "VMWARE" && $item eq "rep_iops" ) {
      ( $metric, $server, $name, $stat_d, $stat_w, $stat_m, $stat_y ) = split( ",", $line );
    }
    else {
      return 0;
    }

    if ( !defined $metric || !defined $server || !defined $name ) { next; }

    # save only selected servers
    if ( $global == 0 && !exists $selected_servers{$server} ) { next; }

    # POWER
    if ( $platform eq "POWER" && $item eq "rep_cpu"     && $metric ne "load_cpu" )    { next; }
    if ( $platform eq "POWER" && $item eq "rep_saniops" && $metric ne "os_san_iops" ) { next; }
    if ( $platform eq "POWER" && $item eq "rep_san"     && $metric ne "os_san1" )     { next; }
    if ( $platform eq "POWER" && $item eq "rep_lan"     && $metric ne "os_lan" )      { next; }

    # VMWARE
    if ( $platform eq "VMWARE" && $item eq "rep_cpu"  && $metric ne "vm_cpu" )  { next; }
    if ( $platform eq "VMWARE" && $item eq "rep_iops" && $metric ne "vm_iops" ) { next; }
    if ( $platform eq "VMWARE" && $item eq "rep_disk" && $metric ne "vm_disk" ) { next; }
    if ( $platform eq "VMWARE" && $item eq "rep_lan"  && $metric ne "vm_net" )  { next; }

    $name =~ s/\.r[a-z][a-z]$//;

    if ( $time eq "day" && isdigit($stat_d) ) {
      $period = "Last Day";
      $data{$stat_d}{SERVER}{$server}{NAME}{$name} = $name;
    }
    if ( $time eq "week" && isdigit($stat_w) ) {
      $period = "Last Week";
      $data{$stat_w}{SERVER}{$server}{NAME}{$name} = $name;
    }
    if ( $time eq "month" && isdigit($stat_m) ) {
      $period = "Last Month";
      $data{$stat_m}{SERVER}{$server}{NAME}{$name} = $name;
    }
    if ( $time eq "year" && isdigit($stat_y) ) {
      $period = "Last Year";
      $data{$stat_y}{SERVER}{$server}{NAME}{$name} = $name;
    }

  }

  print "Content-type: text/plain\n\n";
  my $header = "SERVER" . $sep . "LPAR" . $sep . "$stat_name - $period" . "\n";
  if ( $platform eq "POWER" ) {
    print "SERVER" . $sep . "LPAR" . $sep . "$stat_name - $period" . "\n";
  }
  elsif ( $platform eq "VMWARE" ) {
    print "vCenter" . $sep . "VM" . $sep . "$stat_name - $period" . "\n";
  }

  my $idx = 0;
OUTER: foreach my $stat ( sort { $b <=> $a } keys %data ) {
    if ( exists $data{$stat}{SERVER} ) {
      foreach my $server ( sort keys %{ $data{$stat}{SERVER} } ) {
        if ( exists $data{$stat}{SERVER}{$server}{NAME} ) {
          foreach my $name ( sort keys %{ $data{$stat}{SERVER}{$server}{NAME} } ) {
            $idx++;
            print "\"$server\"" . $sep . "\"$name\"" . $sep . $stat . "\n";
            if ( $idx >= $limit ) { last OUTER; }
          }
        }
      }
    }
  }

  return 1;
}

sub rrd_from_active_hmc {
  my $server   = shift;
  my $rrd_path = shift;
  my $rrd_old  = shift;

  my $active_rrd          = $rrd_old;
  my $active_rrd_last_upd = ( stat("$active_rrd") )[9];

  # find all hmcs
  opendir( DIR, "$wrkdir/$server" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && exit;
  my @hmc_list = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);
  chomp @hmc_list;

  foreach my $hmc (@hmc_list) {
    if ( -f "$wrkdir/$server/$hmc/$rrd_path" && $active_rrd ne "$wrkdir/$server/$hmc/$rrd_path" ) {
      my $rrd_last_upd = ( stat("$wrkdir/$server/$hmc/$rrd_path") )[9];
      if ( defined $active_rrd_last_upd && $rrd_last_upd > $active_rrd_last_upd ) {
        $active_rrd          = "$wrkdir/$server/$hmc/$rrd_path";
        $active_rrd_last_upd = $rrd_last_upd;
      }
    }
  }

  return $active_rrd;
}

sub set_csv_for_linux {
  my $subsys = ( $params{subsys} ) ? $params{subsys} : "";
  my $hmc    = ( $params{hmc} )    ? $params{hmc}    : "";
  my $server = ( $params{server} ) ? $params{server} : "";
  my $lpar   = ( $params{lpar} )   ? $params{lpar}   : "";
  my $item   = ( $params{item} )   ? $params{item}   : "";
  my $sunix  = ( $params{sunix} )  ? $params{sunix}  : "";
  my $eunix  = ( $params{eunix} )  ? $params{eunix}  : "";

  if ( !isdigit($sunix) || !isdigit($sunix) ) {
    error( "Not defined sunix or eunix! sunix=$sunix,eunix=$eunix, Exiting... " . __FILE__ . ":" . __LINE__ ) && exit;
  }

  # check if eunix time is not higher than actual unix time
  if ( defined $eunix && isdigit($eunix) && $eunix > $act_unix ) {
    $eunix = $act_unix;    # if eunix higher than act unix - set it up to act unix
  }

  # change SAMPLE RATE if configured
  if ( $params{sample_rate} && isdigit( $params{sample_rate} ) ) {
    if ( $params{sample_rate} == 60 || $params{sample_rate} == 300 || $params{sample_rate} == 3600 || $params{sample_rate} == 18000 || $params{sample_rate} == 86400 ) {
      $STEP = $params{sample_rate};
    }
    else {
      error( "Unsupported sample_rate option \"$params{sample_rate}\"! Used default 60 seconds... " . __FILE__ . ":" . __LINE__ );
    }
  }

  # csv for single lpar (cpu,oscpu,mem,...)
  if ( $subsys && $hmc && $server && $lpar ) {
    if ( $subsys eq "LPAR" ) {
      if ( $item eq "oscpu" )     { xport_lpar_oscpu( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "mem" )       { xport_lpar_mem( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "cpu-linux" ) { xport_linux_cpu( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "san1" )      { xport_lpar_san( $hmc, $server, $lpar, $item, $sunix, $eunix ); }
      if ( $item eq "san2" )      { xport_lpar_san( $hmc, $server, $lpar, $item, $sunix, $eunix ); }
    }
  }

  return 1;
}

sub set_csv_for_power {
  my $subsys = ( $params{subsys} ) ? $params{subsys} : "";
  my $hmc    = ( $params{hmc} )    ? $params{hmc}    : "";
  my $server = ( $params{server} ) ? $params{server} : "";
  my $lpar   = ( $params{lpar} )   ? $params{lpar}   : "";
  my $item   = ( $params{item} )   ? $params{item}   : "";
  my $sunix  = ( $params{sunix} )  ? $params{sunix}  : "";
  my $eunix  = ( $params{eunix} )  ? $params{eunix}  : "";

  if ( !isdigit($sunix) || !isdigit($sunix) ) {
    error( "Not defined sunix or eunix! sunix=$sunix,eunix=$eunix, Exiting... " . __FILE__ . ":" . __LINE__ ) && exit;
  }

  # check if eunix time is not higher than actual unix time
  if ( defined $eunix && isdigit($eunix) && $eunix > $act_unix ) {
    $eunix = $act_unix;    # if eunix higher than act unix - set it up to act unix
  }

  # change SAMPLE RATE if configured
  if ( $params{sample_rate} && isdigit( $params{sample_rate} ) ) {
    if ( $params{sample_rate} == 60 || $params{sample_rate} == 300 || $params{sample_rate} == 3600 || $params{sample_rate} == 18000 || $params{sample_rate} == 86400 ) {
      $STEP = $params{sample_rate};
    }
    else {
      error( "Unsupported sample_rate option \"$params{sample_rate}\"! Used default 60 seconds... " . __FILE__ . ":" . __LINE__ );
    }
  }

  # csv for single lpar (cpu,oscpu,mem,...)
  if ( $subsys && $hmc && $server && $lpar ) {
    if ( $subsys eq "LPAR" ) {
      if ( $item eq "lpar" )         { xport_lpar_cpu_hmc( $hmc, $server, $lpar, $sunix, $eunix ); }      # lpar cpu from hmc
      if ( $item eq "oscpu" )        { xport_lpar_oscpu( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "queue_cpu" )    { xport_lpar_queue_cpu( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "mem" )          { xport_lpar_mem( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "pg1" )          { xport_lpar_pg1( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "pg2" )          { xport_lpar_pg2( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "lan" )          { xport_lpar_lan( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "san1" )         { xport_lpar_san( $hmc, $server, $lpar, $item, $sunix, $eunix ); }
      if ( $item eq "san2" )         { xport_lpar_san( $hmc, $server, $lpar, $item, $sunix, $eunix ); }
      if ( $item eq "san_resp" )     { xport_lpar_san_resp( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "sea" )          { xport_lpar_sea( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "lparmemalloc" ) { xport_lpar_memalloc( $hmc, $server, $lpar, $sunix, $eunix ); }
    }
    if ( $subsys eq "POOL" ) {
      if ( $item eq "pool" )                       { xport_pool_cpu( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "pool-max" )                   { xport_pool_cpu_max( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "shpool" )                     { xport_shpool_cpu( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "shpool-max" )                 { xport_shpool_cpu_max( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $lpar eq "pool" && $item eq "lparagg" ) { xport_pool_lparagg( $hmc, $server, $lpar, $sunix, $eunix ); }
    }
    if ( $subsys eq "SERVER" ) {
      if ( $item eq "memalloc" )  { xport_power_mem( $hmc, $server, $lpar, $sunix, $eunix ); }
      if ( $item eq "memaggreg" ) { xport_power_mem_aggreg( $hmc, $server, $lpar, $sunix, $eunix ); }
    }
    if ( $subsys eq "CUSTOM-LPAR" ) {
      get_custom_inventory( "$lpar", "$item" );
      xport_custom_lpar( $item, $lpar, $sunix, $eunix );
    }
    if ( $subsys eq "CUSTOM-POOL" ) {
      get_custom_inventory( "$lpar", "$item" );
      xport_custom_pool( $item, $lpar, $sunix, $eunix );
    }
  }

  return 1;
}

sub set_csv_for_vmware {
  my $subsys  = ( $params{subsys} )  ? $params{subsys}  : "";
  my $cluster = ( $params{cluster} ) ? $params{cluster} : "";
  my $host    = ( $params{host} )    ? $params{host}    : "";
  my $vcenter = ( $params{vcenter} ) ? $params{vcenter} : "";
  my $server  = ( $params{server} )  ? $params{server}  : "";
  my $item    = ( $params{item} )    ? $params{item}    : "";
  my $sunix   = ( $params{sunix} )   ? $params{sunix}   : "";
  my $eunix   = ( $params{eunix} )   ? $params{eunix}   : "";

  if ( !isdigit($sunix) || !isdigit($sunix) ) {
    error( "Not defined sunix or eunix! sunix=$sunix,eunix=$eunix, Exiting... " . __FILE__ . ":" . __LINE__ ) && exit;
  }

  # change SAMPLE RATE if configured
  if ( $params{sample_rate} && isdigit( $params{sample_rate} ) ) {
    if ( $params{sample_rate} == 60 || $params{sample_rate} == 300 || $params{sample_rate} == 3600 || $params{sample_rate} == 18000 || $params{sample_rate} == 86400 ) {
      $STEP = $params{sample_rate};
    }
    else {
      error( "Unsupported sample_rate option \"$params{sample_rate}\"! Used default 60 seconds... " . __FILE__ . ":" . __LINE__ );
    }
  }

  # csv for single lpar (cpu,oscpu,mem,...)
  if ( $subsys && $host && $vcenter && $server ) {
    if ($cluster) {
      if ( $subsys eq "CLUSTER" ) {
        if ( $item eq "clustcpu" )    { xport_cluster_cpu( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "clustlpar" )   { xport_cluster_cpu_vms( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "clustser" )    { xport_cluster_cpu_servers( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "clustmem" )    { xport_cluster_memory( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "clustlpardy" ) { xport_cluster_cpu_rdy( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "clustlan" )    { xport_cluster_lan( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
      }
      if ( $subsys eq "ESXI" ) {
        if ( $item eq "pool" )      { xport_esxi_cpu( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "lparagg" )   { xport_esxi_cpu_vms( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "memalloc" )  { xport_esxi_memalloc( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "memaggreg" ) { xport_esxi_memaggreg( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "vmdiskrw" )  { xport_esxi_vmdiskrw( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
        if ( $item eq "vmnetrw" )   { xport_esxi_vmnetrw( $vcenter, $cluster, $host, $server, $sunix, $eunix ); }
      }
      if ( $subsys eq "VM" ) {
        if ( exists $params{vm_name} && $params{vm_name} ne '' && exists $params{vm_uuid} && $params{vm_uuid} ne '' ) {
          if ( $item eq "lpar" )      { xport_vm_cpu( $vcenter, $cluster, $host, $server, $params{vm_name}, $params{vm_uuid}, $sunix, $eunix ); }
          if ( $item eq "vmw-proc" )  { xport_vm_cpu_prct( $vcenter, $cluster, $host, $server, $params{vm_name}, $params{vm_uuid}, $sunix, $eunix ); }
          if ( $item eq "vmw-mem" )   { xport_vm_mem( $vcenter, $cluster, $host, $server, $params{vm_name}, $params{vm_uuid}, $sunix, $eunix ); }
          if ( $item eq "vmw-disk" )  { xport_vm_disk( $vcenter, $cluster, $host, $server, $params{vm_name}, $params{vm_uuid}, $sunix, $eunix ); }
          if ( $item eq "vmw-net" )   { xport_vm_net( $vcenter, $cluster, $host, $server, $params{vm_name}, $params{vm_uuid}, $sunix, $eunix ); }
          if ( $item eq "vmw-swap" )  { xport_vm_swap( $vcenter, $cluster, $host, $server, $params{vm_name}, $params{vm_uuid}, $sunix, $eunix ); }
          if ( $item eq "vmw-comp" )  { xport_vm_comp( $vcenter, $cluster, $host, $server, $params{vm_name}, $params{vm_uuid}, $sunix, $eunix ); }
          if ( $item eq "vmw-ready" ) { xport_vm_rdy( $vcenter, $cluster, $host, $server, $params{vm_name}, $params{vm_uuid}, $sunix, $eunix ); }

          if ( $item eq "vmw-iops" && exists $params{vcenter_id} && $params{vcenter_id} ne '' ) {
            xport_vm_iops( $vcenter, $cluster, $host, $server, $params{vcenter_id}, $params{vm_name}, $params{vm_uuid}, $sunix, $eunix );
          }
        }
      }
      if ( $subsys eq "RESPOOL" ) {
        if ( exists $params{respool} && $params{respool} ne '' && exists $params{id} && $params{id} ne '' ) {
          if ( $item eq "rpcpu" )  { xport_respool_cpu( $vcenter, $cluster, $host, $server, $params{respool}, $params{id}, $sunix, $eunix ); }
          if ( $item eq "rplpar" ) { xport_respool_cpu_vms( $vcenter, $cluster, $host, $server, $params{respool}, $params{id}, $sunix, $eunix ); }
          if ( $item eq "rpmem" )  { xport_respool_mem( $vcenter, $cluster, $host, $server, $params{respool}, $params{id}, $sunix, $eunix ); }
        }
      }
    }
    if ( $subsys eq "DATASTORE" ) {
      if ( exists $params{datacenter} && $params{datacenter} ne '' && exists $params{datastore} && $params{datastore} ne '' && exists $params{uuid} && $params{uuid} ne '' ) {
        if ( $item eq "dsmem" )     { xport_datastore_mem( $vcenter, $cluster, $host, $server, $params{datacenter}, $params{datastore}, $params{uuid}, $sunix, $eunix ); }
        if ( $item eq "dsrw" )      { xport_datastore_data( $vcenter, $cluster, $host, $server, $params{datacenter}, $params{datastore}, $params{uuid}, $sunix, $eunix ); }
        if ( $item eq "dsarw" )     { xport_datastore_iops( $vcenter, $cluster, $host, $server, $params{datacenter}, $params{datastore}, $params{uuid}, $sunix, $eunix ); }
        if ( $item eq "dslat" )     { xport_datastore_latency( $vcenter, $cluster, $host, $server, $params{datacenter}, $params{datastore}, $params{uuid}, $sunix, $eunix ); }
        if ( $item eq "ds-vmiops" ) { xport_datastore_vmiops( $vcenter, $cluster, $host, $server, $params{datacenter}, $params{datastore}, $params{uuid}, $sunix, $eunix ); }
      }
    }
  }
  if ( defined $subsys && ( $subsys eq "CUSTOM-ESXI" || $subsys eq "CUSTOM-VM" ) && exists $params{lpar} ) {
    if ( $subsys eq "CUSTOM-VM" ) { get_vmware_inventory(); }    # it is necessary to translate VM uuid to name and find ESXi under which this VM belongs
    get_custom_inventory( "$params{lpar}", "$item", $subsys );
    xport_custom_vmware( $item, $params{lpar}, $sunix, $eunix );
  }

  return 1;
}

sub set_csv_for_ovirt {
  my $subsys     = ( $params{subsys} )     ? $params{subsys}     : "";
  my $host       = ( $params{host} )       ? $params{host}       : "";
  my $uuid       = ( $params{uuid} )       ? $params{uuid}       : "";
  my $name       = ( $params{name} )       ? $params{name}       : "";
  my $datacenter = ( $params{datacenter} ) ? $params{datacenter} : "";
  my $item       = ( $params{item} )       ? $params{item}       : "";
  my $sunix      = ( $params{sunix} )      ? $params{sunix}      : "";
  my $eunix      = ( $params{eunix} )      ? $params{eunix}      : "";

  if ( !isdigit($sunix) || !isdigit($sunix) ) {
    error( "Not defined sunix or eunix! sunix=$sunix,eunix=$eunix, Exiting... " . __FILE__ . ":" . __LINE__ ) && exit;
  }

  # change SAMPLE RATE if configured
  if ( $params{sample_rate} && isdigit( $params{sample_rate} ) ) {
    if ( $params{sample_rate} == 60 || $params{sample_rate} == 300 || $params{sample_rate} == 3600 || $params{sample_rate} == 18000 || $params{sample_rate} == 86400 ) {
      $STEP = $params{sample_rate};
    }
    else {
      error( "Unsupported sample_rate option \"$params{sample_rate}\"! Used default 60 seconds... " . __FILE__ . ":" . __LINE__ );
    }
  }

  if ( !defined $subsys || $subsys eq '' ) {
    error( "subsys is not defined! " . __FILE__ . ":" . __LINE__ ) && exit;
  }
  if ( !defined $host || $host eq '' ) {
    error( "host is not defined! " . __FILE__ . ":" . __LINE__ ) && exit;
  }
  if ( !defined $uuid || $uuid eq '' ) {
    error( "uuid is not defined! " . __FILE__ . ":" . __LINE__ ) && exit;
  }
  if ( !defined $name || $name eq '' ) {
    error( "name is not defined! " . __FILE__ . ":" . __LINE__ ) && exit;
  }
  if ( !defined $datacenter || $datacenter eq '' ) {
    error( "datacenter is not defined! " . __FILE__ . ":" . __LINE__ ) && exit;
  }
  if ( !defined $item || $item eq '' ) {
    error( "item is not defined! " . __FILE__ . ":" . __LINE__ ) && exit;
  }

  if ( $item eq "ovirt_vm_cpu_core" )          { xport_ovirt_cpu_core( $subsys, $host, $uuid, $name, $datacenter, $sunix, $eunix ); }
  if ( $item eq "ovirt_vm_cpu_percent" )       { xport_ovirt_cpu_percent( $subsys, $host, $uuid, $name, $datacenter, $sunix, $eunix ); }
  if ( $item eq "ovirt_storage_domain_space" ) { xport_ovirt_storage_domain_space( $subsys, $host, $uuid, $name, $datacenter, $sunix, $eunix ); }
  if ( $item eq "ovirt_disk_data" )            { xport_ovirt_disk_data( $subsys, $host, $uuid, $name, $datacenter, $sunix, $eunix ); }
  if ( $item eq "ovirt_disk_latency" )         { xport_ovirt_disk_latency( $subsys, $host, $uuid, $name, $datacenter, $sunix, $eunix ); }

  #"ovirt_vm_cpu_core", "ovirt_vm_cpu_percent", "ovirt_vm_mem", "ovirt_vm_aggr_net", "ovirt_vm_aggr_data", "ovirt_vm_aggr_latency"
  #"ovirt_storage_domain_space", "ovirt_storage_domain_aggr_data", "ovirt_storage_domain_aggr_latency"
  #"ovirt_disk_data", "ovirt_disk_latency"

  return 1;
}

sub xport_ovirt_disk_latency {
  my $type       = shift;
  my $host       = shift;
  my $uuid       = shift;
  my $name       = shift;
  my $datacenter = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $rrd = "$wrkdir/oVirt/storage/disk-$uuid.rrd";

  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $pow2 = 1000**2;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:read=\"$rrd\":disk_read_latency:AVERAGE";
  $cmd .= " DEF:write=\"$rrd\":disk_write_latency:AVERAGE";
  $cmd .= " CDEF:read_ms=read,1000,*";
  $cmd .= " CDEF:write_ms=write,1000,*";
  $cmd .= " XPORT:write_ms:\"Write\"";
  $cmd .= " XPORT:read_ms:\"Read\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Write [ms]'} = $value1;
      $data{STATS}{$timestamp}{'Read [ms]'}  = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$host - $name";
  $data{CSVHEADER}{1} = "Write [ms]";
  $data{CSVHEADER}{2} = "Read [ms]";

  return 1;
}

sub xport_ovirt_disk_data {
  my $type       = shift;
  my $host       = shift;
  my $uuid       = shift;
  my $name       = shift;
  my $datacenter = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $rrd = "$wrkdir/oVirt/storage/disk-$uuid.rrd";

  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $pow2 = 1000**2;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:read=\"$rrd\":data_current_read:AVERAGE";
  $cmd .= " DEF:write=\"$rrd\":data_current_write:AVERAGE";
  $cmd .= " CDEF:read_mb=read,$pow2,/";

  #$cmd .= " CDEF:read_graph=0,read,-";
  $cmd .= " CDEF:write_mb=write,$pow2,/";
  $cmd .= " XPORT:write_mb:\"Write\"";
  $cmd .= " XPORT:read_mb:\"Read\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Write [MB/sec]'} = $value1;
      $data{STATS}{$timestamp}{'Read [MB/sec]'}  = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$host - $name";
  $data{CSVHEADER}{1} = "Write [MB/sec]";
  $data{CSVHEADER}{2} = "Read [MB/sec]";

  return 1;
}

sub xport_ovirt_storage_domain_space {
  my $type       = shift;
  my $host       = shift;
  my $uuid       = shift;
  my $name       = shift;
  my $datacenter = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $rrd = "$wrkdir/oVirt/storage/sd-$uuid.rrd";

  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:space_gb=\"$rrd\":used_disk_size_gb:AVERAGE";
  $cmd .= " DEF:space_total_gb=\"$rrd\":total_disk_size_gb:AVERAGE";
  $cmd .= " CDEF:space_tb=space_gb,1024,/";
  $cmd .= " CDEF:space_total_tb=space_total_gb,1024,/";
  $cmd .= " XPORT:space_total_tb:\"Space total [TB]\"";
  $cmd .= " XPORT:space_tb:\"Space used [TB]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Space total [TB]'} = $value1;
      $data{STATS}{$timestamp}{'Space used [TB]'}  = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$host - $name";
  $data{CSVHEADER}{1} = "Space total [TB]";
  $data{CSVHEADER}{2} = "Space used [TB]";

  return 1;
}

sub xport_ovirt_cpu_percent {
  my $type       = shift;
  my $host       = shift;
  my $uuid       = shift;
  my $name       = shift;
  my $datacenter = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $rrd = "$wrkdir/oVirt/vm/$uuid/sys.rrd";

  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:user_p=\"$rrd\":user_cpu_usage_p:AVERAGE";
  $cmd .= " DEF:system_p=\"$rrd\":system_cpu_usage_p:AVERAGE";
  $cmd .= " CDEF:idle_p=100,user_p,-,system_p,-";
  $cmd .= " XPORT:system_p:\"Sys\"";
  $cmd .= " XPORT:user_p:\"User\"";
  $cmd .= " XPORT:idle_p:\"Idle\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value3    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      $data{STATS}{$timestamp}{'Sys [%]'}  = $value1;
      $data{STATS}{$timestamp}{'User [%]'} = $value2;
      $data{STATS}{$timestamp}{'Idle [%]'} = $value3;
    }
  }

  # set csv header
  $data{NAME}         = "$host - $name";
  $data{CSVHEADER}{1} = "Sys [%]";
  $data{CSVHEADER}{2} = "User [%]";
  $data{CSVHEADER}{3} = "Idle [%]";

  return 1;
}

sub xport_ovirt_cpu_core {
  my $type       = shift;
  my $host       = shift;
  my $uuid       = shift;
  my $name       = shift;
  my $datacenter = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $rrd = "$wrkdir/oVirt/vm/$uuid/sys.rrd";

  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:cpu_c=\"$rrd\":cpu_usage_c:AVERAGE";
  $cmd .= " DEF:cores=\"$rrd\":number_of_cores:AVERAGE";
  $cmd .= " XPORT:cpu_c:\"Utilization [cores]\"";
  $cmd .= " XPORT:cores:\"Available [cores]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Utilization [cores]'} = $value1;
      $data{STATS}{$timestamp}{'Available [cores]'}   = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$host - $name";
  $data{CSVHEADER}{1} = "Utilization [cores]";
  $data{CSVHEADER}{2} = "Available [cores]";

  return 1;
}

sub xport_vm_iops {
  my $vcenter    = shift;
  my $cluster    = shift;
  my $host       = shift;
  my $server     = shift;
  my $vcenter_id = shift;
  my $vm_name    = shift;
  my $vm_uuid    = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $idx   = 0;
  my @files = <$wrkdir/$vcenter_id/*/*/$vm_uuid.rrv>;
  foreach my $rrd (@files) {
    chomp $rrd;

    my $datastore_uuid = $rrd;
    $datastore_uuid =~ s/\/$vm_uuid\.rrv$//;
    $datastore_uuid =~ s/^.*\///g;

    my ($datastore_name) = <$wrkdir/$vcenter_id/*/*\.$datastore_uuid>;
    $datastore_name =~ s/\.$datastore_uuid$//;
    $datastore_name =~ s/^.*\///g;

    #print STDERR "$datastore_name : $datastore_uuid : $rrd\n";

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }
    $idx++;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:vm_iops_read=\"$rrd\":vm_iops_read:AVERAGE";
    $cmd .= " DEF:vm_iops_write=\"$rrd\":vm_iops_write:AVERAGE";
    $cmd .= " CDEF:read=vm_iops_read,1,/";
    $cmd .= " CDEF:write=vm_iops_write,1,/";
    $cmd .= " XPORT:read:\"Read [IOPS]\"";
    $cmd .= " XPORT:write:\"Write [IOPS]\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1564351260</t><v>7.2856117916e-01</v><v>0.0000000000e+00</v><v>2.2343333333e+00</v><v>0.0000000000e+00</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
          if ( exists $data{STATS}{$timestamp}{"Read [IOPS]"} && isdigit( $data{STATS}{$timestamp}{"Read [IOPS]"} ) ) {
            $data{STATS}{$timestamp}{"Read [IOPS]"} += $value1;
          }
          else {
            $data{STATS}{$timestamp}{"Read [IOPS]"} = $value1;
          }
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
          if ( exists $data{STATS}{$timestamp}{"Write [IOPS]"} && isdigit( $data{STATS}{$timestamp}{"Write [IOPS]"} ) ) {
            $data{STATS}{$timestamp}{"Write [IOPS]"} += $value2;
          }
          else {
            $data{STATS}{$timestamp}{"Write [IOPS]"} = $value2;
          }
        }
      }
    }
  }

  if ( $idx == 0 ) {
    $error_in_csv = 1;
    print "Content-type: text/plain\n\n";
    print "Datastore files for this VM \"$vm_name\" not found!\n";
    return 1;
  }

  # set csv header
  $data{CSVHEADER}{1} = "Read [IOPS]";
  $data{CSVHEADER}{2} = "Write [IOPS]";
  $data{NAME}         = "$vm_name";

  return 1;
}

sub xport_respool_mem {
  my $vcenter      = shift;
  my $cluster      = shift;
  my $host         = shift;
  my $server       = shift;
  my $respool_name = shift;
  my $respool_id   = shift;
  my $sunix        = shift;
  my $eunix        = shift;

  my $rrd = "$wrkdir/$server/$host/$respool_id.rrc";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:granted=\"$rrd\":Memory_granted_KB:AVERAGE";
  $cmd .= " DEF:active=\"$rrd\":Memory_active_KB:AVERAGE";
  $cmd .= " DEF:consumed=\"$rrd\":Memory_consumed_KB:AVERAGE";
  $cmd .= " DEF:balloon=\"$rrd\":Memory_baloon_KB:AVERAGE";
  $cmd .= " DEF:swap=\"$rrd\":Memory_swap_KB:AVERAGE";
  $cmd .= " DEF:reservation=\"$rrd\":Memory_reservation:AVERAGE";
  $cmd .= " DEF:limit=\"$rrd\":Memory_limit:AVERAGE";
  $cmd .= " CDEF:grantg=granted,1024,/,1024,/";
  $cmd .= " CDEF:activeg=active,1024,/,1024,/";
  $cmd .= " CDEF:consumg=consumed,1024,/,1024,/";
  $cmd .= " CDEF:balloong=balloon,1024,/,1024,/";
  $cmd .= " CDEF:swapg=swap,1024,/,1024,/";
  $cmd .= " CDEF:reservationg=reservation,1024,/";
  $cmd .= " CDEF:limitg=limit,1024,/";
  $cmd .= " XPORT:reservationg:\"Reservation [GB]\"";
  $cmd .= " XPORT:grantg:\"Granted [GB]\"";
  $cmd .= " XPORT:consumg:\"Consumed [GB]\"";
  $cmd .= " XPORT:activeg:\"Active [GB]\"";
  $cmd .= " XPORT:balloong:\"Baloon [GB]\"";
  $cmd .= " XPORT:swapg:\"Swap out [GB]\"";
  $cmd .= " XPORT:limitg:\"Limit [GB]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4, $value5, $value6, $value7 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value7    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      if ( isdigit($value4) ) {
        $value4 = sprintf '%.2f', $value4;
      }
      else {
        $value4 = '';
      }
      if ( isdigit($value5) ) {
        $value5 = sprintf '%.2f', $value5;
      }
      else {
        $value5 = '';
      }
      if ( isdigit($value6) ) {
        $value6 = sprintf '%.2f', $value6;
      }
      else {
        $value6 = '';
      }
      if ( isdigit($value7) ) {
        $value7 = sprintf '%.2f', $value7;
      }
      else {
        $value7 = '';
      }
      $data{STATS}{$timestamp}{'Reservation [GB]'} = $value1;
      $data{STATS}{$timestamp}{'Granted [GB]'}     = $value2;
      $data{STATS}{$timestamp}{'Consumed [GB]'}    = $value3;
      $data{STATS}{$timestamp}{'Active [GB]'}      = $value4;
      $data{STATS}{$timestamp}{'Baloon [GB]'}      = $value5;
      $data{STATS}{$timestamp}{'Swap out [GB]'}    = $value6;
      $data{STATS}{$timestamp}{'Limit [GB]'}       = $value7;
    }
  }

  # set csv header
  $data{NAME}         = "$cluster - $respool_name";
  $data{CSVHEADER}{1} = "Reservation [GB]";
  $data{CSVHEADER}{2} = "Granted [GB]";
  $data{CSVHEADER}{3} = "Consumed [GB]";
  $data{CSVHEADER}{4} = "Active [GB]";
  $data{CSVHEADER}{5} = "Baloon [GB]";
  $data{CSVHEADER}{6} = "Swap out [GB]";
  $data{CSVHEADER}{7} = "Limit [GB]";

  return 1;
}

sub xport_respool_cpu_vms {
  my $vcenter      = shift;
  my $cluster      = shift;
  my $host         = shift;
  my $server       = shift;
  my $respool_name = shift;
  my $respool_id   = shift;
  my $sunix        = shift;
  my $eunix        = shift;

  # find vm uuids of this ResPool
  my %vm_uuids;
  if ( -f "$wrkdir/$server/$host/$respool_id.vmr" ) {
    open( RES, "< $wrkdir/$server/$host/$respool_id.vmr" ) || error( "Couldn't open file $wrkdir/$server/$host/$respool_id.vmr $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @res = <RES>;
    close(RES);

    my $idx = 0;
    foreach my $line (@res) {
      $idx++;
      my ( $uuid, undef ) = split( /:/, $line );
      $vm_uuids{$uuid} = $uuid;
    }

    if ( $idx == 0 ) {
      $error_in_csv = 1;

      #error( "VMs not found in $wrkdir/$server/$host/$respool_id.vmr ! $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      print "Content-type: text/plain\n\n";
      print "VMs for this RESPOOL \"$respool_name\" not found in $wrkdir/$server/$host/$respool_id.vmr!\n";
      return 1;
    }
  }
  else {
    $error_in_csv = 1;

    #error( "File $wrkdir/$server/$host/$respool_id.vmr does not exists! VMs not found! $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print "Content-type: text/plain\n\n";
    print "File $wrkdir/$server/$host/$respool_id.vmr does not exists! VMs for this RESPOOL \"$respool_name\" not found!\n";
    return 1;
  }

  # find VMs under this cluster
  my @vms;
  if ( -f "$wrkdir/$server/$host/hosts_in_cluster" ) {
    open( HOSTS, "< $wrkdir/$server/$host/hosts_in_cluster" ) || error( "Couldn't open file $wrkdir/$server/$host/hosts_in_cluster $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = <HOSTS>;
    close(HOSTS);

    foreach my $line (@lines) {
      chomp $line;
      my ( $esxi_ip, $vcenter_ip ) = split( /XORUX/, $line );
      if ( -f "$wrkdir/$esxi_ip/$vcenter_ip/cpu.csv" ) {
        open( VML, "< $wrkdir/$esxi_ip/$vcenter_ip/cpu.csv" ) || error( "Couldn't open file $wrkdir/$esxi_ip/$vcenter_ip/cpu.csv $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        my @vm_lines = <VML>;
        close(VML);

        foreach my $vm_line (@vm_lines) {
          chomp $vm_line;

          # vm-jindra,4,0,-1,normal,4000,CentOS 7 (64-bit),poweredOn,guestToolsRunning,ipaddr,501c487b-66db-574a-1578-8bb38694a41f,4096
          my ( $vm_name, undef, undef, undef, undef, undef, undef, undef, undef, undef, $vm_uuid ) = split( /,/, $vm_line );

          # test if this VM belong to this RESPOOL
          if ( !exists $vm_uuids{$vm_uuid} ) { next; }

          if ( -f "$wrkdir/vmware_VMs/$vm_uuid.rrm" ) {
            push( @vms, "$esxi_ip,$vm_name,$wrkdir/vmware_VMs/$vm_uuid.rrm" );
          }
        }
      }
    }
  }

  my $vm_idx = 0;
  foreach my $line (@vms) {
    my ( $esxi, $vm_name, $rrd ) = split( /,/, $line );

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:utiltot_mhz=\"$rrd\":CPU_usage:AVERAGE";
    $cmd .= " CDEF:utiltot_ghz=utiltot_mhz,1000,/";
    $cmd .= " CDEF:utiltot=utiltot_mhz,1000,/";              # since 4.74- (u)
    $cmd .= " XPORT:utiltot:\"$esxi - $vm_name [GHz]\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        $data{STATS}{$timestamp}{"$esxi - $vm_name [GHz]"} = $value1;
      }
    }

    # set csv header
    $data{CSVHEADER}{$vm_idx} = "$esxi - $vm_name [GHz]";
    $vm_idx++;
  }
  if ( $vm_idx == 0 ) {
    $error_in_csv = 1;

    #error( "File $wrkdir/$server/$host/$respool_id.vmr does not exists! VMs not found! $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print "Content-type: text/plain\n\n";
    print "VMs for this RESPOOL \"$respool_name\" not found!\n";
    return 1;
  }
  $data{NAME} = "$respool_name";

  return 1;
}

sub xport_respool_cpu {
  my $vcenter      = shift;
  my $cluster      = shift;
  my $host         = shift;
  my $server       = shift;
  my $respool_name = shift;
  my $respool_id   = shift;
  my $sunix        = shift;
  my $eunix        = shift;

  my $rrd = "$wrkdir/$server/$host/$respool_id.rrc";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:cpuutiltot_MHz=\"$rrd\":CPU_usage_MHz:AVERAGE";
  $cmd .= " DEF:cpu_limit_MHz=\"$rrd\":CPU_limit:AVERAGE";
  $cmd .= " DEF:cpu_reservation_MHz=\"$rrd\":CPU_reservation:AVERAGE";
  $cmd .= " CDEF:cpuutiltot=cpuutiltot_MHz,1000,/";
  $cmd .= " CDEF:cpu_limit=cpu_limit_MHz,1000,/";
  $cmd .= " CDEF:cpu_reservation=cpu_reservation_MHz,1000,/";

  $cmd .= " XPORT:cpu_reservation:\"Reservation [GHz]\"";
  $cmd .= " XPORT:cpuutiltot:\"Utilization [GHz]\"";
  $cmd .= " XPORT:cpu_limit:\"Limit [Ghz]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value3    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      $data{STATS}{$timestamp}{'Reservation [GHz]'} = $value1;
      $data{STATS}{$timestamp}{'Utilization [GHz]'} = $value2;
      $data{STATS}{$timestamp}{'Limit [Ghz]'}       = $value3;
    }
  }

  # set csv header
  $data{NAME}         = "$cluster - $respool_name";
  $data{CSVHEADER}{1} = "Reservation [GHz]";
  $data{CSVHEADER}{2} = "Utilization [GHz]";
  $data{CSVHEADER}{3} = "Limit [Ghz]";

  return 1;
}

sub xport_datastore_vmiops {
  my $vcenter    = shift;
  my $cluster    = shift;
  my $host       = shift;
  my $server     = shift;
  my $datacenter = shift;
  my $datastore  = shift;
  my $uuid       = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $dir = "$wrkdir/$server/$host/$uuid";

  my @files;
  opendir( DIR, $dir ) || error( "can't opendir $dir: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  @files = grep { (/\.rrv$/) } readdir(DIR);
  closedir DIR;

  my $vm_idx = 0;
  foreach my $rrd_name (@files) {
    my $rrd = "$wrkdir/$server/$host/$uuid/$rrd_name";
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }
    $vm_idx++;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:vm_iops_read=\"$rrd\":vm_iops_read:AVERAGE";
    $cmd .= " DEF:vm_iops_write=\"$rrd\":vm_iops_write:AVERAGE";
    $cmd .= " CDEF:read=vm_iops_read,1,/";
    $cmd .= " CDEF:write=vm_iops_write,1,/";

    $cmd .= " XPORT:read:\"Read [IOPS]\"";
    $cmd .= " XPORT:write:\"Write [IOPS]\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
          if ( exists $data{STATS}{$timestamp}{'Read [IOPS]'} && isdigit( $data{STATS}{$timestamp}{'Read [IOPS]'} ) ) {
            $data{STATS}{$timestamp}{'Read [IOPS]'} += $value1;
          }
          else {
            $data{STATS}{$timestamp}{'Read [IOPS]'} = $value1;
          }
        }
        else {
          # add there empty string, because there will not be any data when all VM's has NaN values
          unless ( exists $data{STATS}{$timestamp}{'Read [IOPS]'} && isdigit( $data{STATS}{$timestamp}{'Read [IOPS]'} ) ) {
            $data{STATS}{$timestamp}{'Read [IOPS]'} = "";
          }
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
          if ( exists $data{STATS}{$timestamp}{'Write [IOPS]'} && isdigit( $data{STATS}{$timestamp}{'Write [IOPS]'} ) ) {
            $data{STATS}{$timestamp}{'Write [IOPS]'} += $value2;
          }
          else {
            $data{STATS}{$timestamp}{'Write [IOPS]'} = $value2;
          }
        }
        else {
          # add there empty string, because there will not be any data when all VM's has NaN values
          unless ( exists $data{STATS}{$timestamp}{'Write [IOPS]'} && isdigit( $data{STATS}{$timestamp}{'Write [IOPS]'} ) ) {
            $data{STATS}{$timestamp}{'Write [IOPS]'} = "";
          }
        }
      }
    }
  }

  if ( $vm_idx == 0 ) {
    $error_in_csv = 1;
    print "Content-type: text/plain\n\n";
    print "VMs for this Datastore \"$datacenter - $datastore\" not found!\n";
    return 1;
  }

  # set csv header
  $data{NAME}         = "$datacenter - $datastore";
  $data{CSVHEADER}{1} = "Read [IOPS]";
  $data{CSVHEADER}{2} = "Write [IOPS]";

  return 1;
}

sub xport_datastore_latency {
  my $vcenter    = shift;
  my $cluster    = shift;
  my $host       = shift;
  my $server     = shift;
  my $datacenter = shift;
  my $datastore  = shift;
  my $uuid       = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $rrd = "$wrkdir/$server/$host/$uuid.rru";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Dstore_readLatency=\"$rrd\":Dstore_readLatency:AVERAGE";
  $cmd .= " DEF:Dstore_writeLatency=\"$rrd\":Dstore_writeLatency:AVERAGE";
  $cmd .= " CDEF:read=Dstore_readLatency,1,/";
  $cmd .= " CDEF:write=Dstore_writeLatency,1,/";

  $cmd .= " XPORT:read:\"Read [ms]\"";
  $cmd .= " XPORT:write:\"Write [ms]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Read [ms]'}  = $value1;
      $data{STATS}{$timestamp}{'Write [ms]'} = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$datacenter - $datastore";
  $data{CSVHEADER}{1} = "Read [ms]";
  $data{CSVHEADER}{2} = "Write [ms]";

  return 1;
}

sub xport_datastore_iops {
  my $vcenter    = shift;
  my $cluster    = shift;
  my $host       = shift;
  my $server     = shift;
  my $datacenter = shift;
  my $datastore  = shift;
  my $uuid       = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $rrd = "$wrkdir/$server/$host/$uuid.rrt";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Datastore_ReadAvg=\"$rrd\":Datastore_ReadAvg:AVERAGE";
  $cmd .= " DEF:Datastore_WriteAvg=\"$rrd\":Datastore_WriteAvg:AVERAGE";
  $cmd .= " CDEF:read=Datastore_ReadAvg,1,/";
  $cmd .= " CDEF:write=Datastore_WriteAvg,1,/";

  $cmd .= " XPORT:read:\"Read [IOPS/sec]\"";
  $cmd .= " XPORT:write:\"Write [IOPS/sec]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.0f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.0f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Read [IOPS/sec]'}  = $value1;
      $data{STATS}{$timestamp}{'Write [IOPS/sec]'} = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$datacenter - $datastore";
  $data{CSVHEADER}{1} = "Read [IOPS/sec]";
  $data{CSVHEADER}{2} = "Write [IOPS/sec]";

  return 1;
}

sub xport_datastore_data {
  my $vcenter    = shift;
  my $cluster    = shift;
  my $host       = shift;
  my $server     = shift;
  my $datacenter = shift;
  my $datastore  = shift;
  my $uuid       = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $rrd = "$wrkdir/$server/$host/$uuid.rrt";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Datastore_read=\"$rrd\":Datastore_read:AVERAGE";
  $cmd .= " DEF:Datastore_write=\"$rrd\":Datastore_write:AVERAGE";
  $cmd .= " CDEF:read=Datastore_read,1024,/";
  $cmd .= " CDEF:write=Datastore_write,1024,/";

  $cmd .= " XPORT:read:\"Read [MB/sec]\"";
  $cmd .= " XPORT:write:\"Write [MB/sec]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Read [MB/sec]'}  = $value1;
      $data{STATS}{$timestamp}{'Write [MB/sec]'} = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$datacenter - $datastore";
  $data{CSVHEADER}{1} = "Read [MB/sec]";
  $data{CSVHEADER}{2} = "Write [MB/sec]";

  return 1;
}

sub xport_datastore_mem {
  my $vcenter    = shift;
  my $cluster    = shift;
  my $host       = shift;
  my $server     = shift;
  my $datacenter = shift;
  my $datastore  = shift;
  my $uuid       = shift;
  my $sunix      = shift;
  my $eunix      = shift;

  my $rrd = "$wrkdir/$server/$host/$uuid.rrs";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:total=\"$rrd\":Disk_capacity:AVERAGE";
  $cmd .= " DEF:granted=\"$rrd\":Disk_used:AVERAGE";
  $cmd .= " DEF:active=\"$rrd\":Disk_provisioned:AVERAGE";
  $cmd .= " CDEF:grantg=granted,1024,/,1024,/,1024,/";
  $cmd .= " CDEF:activeg=active,1024,/,1024,/,1024,/";
  $cmd .= " CDEF:totg=total,1024,/,1024,/,1024,/";

  $cmd .= " XPORT:totg:\"Total [TB]\"";
  $cmd .= " XPORT:grantg:\"Used [TB]\"";
  $cmd .= " XPORT:activeg:\"Provisioned [TB]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value3    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      $data{STATS}{$timestamp}{'Total [TB]'}       = $value1;
      $data{STATS}{$timestamp}{'Used [TB]'}        = $value2;
      $data{STATS}{$timestamp}{'Provisioned [TB]'} = $value3;
    }
  }

  # set csv header
  $data{NAME}         = "$datacenter - $datastore";
  $data{CSVHEADER}{1} = "Total [TB]";
  $data{CSVHEADER}{2} = "Used [TB]";
  $data{CSVHEADER}{3} = "Provisioned [TB]";

  return 1;
}

sub xport_esxi_vmnetrw {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/$server/$host/pool.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  my $kbmb     = 1000;
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Network_received=\"$rrd\":Network_received:AVERAGE";
  $cmd .= " DEF:Network_transmitted=\"$rrd\":Network_transmitted:AVERAGE";
  $cmd .= " CDEF:pagein_b=Network_received,$kbmb,/";
  $cmd .= " CDEF:pageout_b=Network_transmitted,$kbmb,/";

  $cmd .= " XPORT:pagein_b:\"Read [MB/sec]\"";
  $cmd .= " XPORT:pageout_b:\"Write [MB/sec]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Read [MB/sec]'}  = $value1;
      $data{STATS}{$timestamp}{'Write [MB/sec]'} = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$cluster - $server";
  $data{CSVHEADER}{1} = "Read [MB/sec]";
  $data{CSVHEADER}{2} = "Write [MB/sec]";

  return 1;
}

sub xport_esxi_vmdiskrw {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/$server/$host/pool.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  my $kbmb     = 1024;
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Disk_read=\"$rrd\":Disk_read:AVERAGE";
  $cmd .= " DEF:Disk_write=\"$rrd\":Disk_write:AVERAGE";
  $cmd .= " CDEF:pagein_b=Disk_read,$kbmb,/";
  $cmd .= " CDEF:pageout_b=Disk_write,$kbmb,/";

  $cmd .= " XPORT:pagein_b:\"Read [MB/sec]\"";
  $cmd .= " XPORT:pageout_b:\"Write [MB/sec]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Read [MB/sec]'}  = $value1;
      $data{STATS}{$timestamp}{'Write [MB/sec]'} = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$cluster - $server";
  $data{CSVHEADER}{1} = "Read [MB/sec]";
  $data{CSVHEADER}{2} = "Write [MB/sec]";

  return 1;
}

sub xport_esxi_memaggreg {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  # find VMs under this ESXi
  my @vms;
  if ( -f "$wrkdir/$server/$host/cpu.csv" ) {
    open( VML, "< $wrkdir/$server/$host/cpu.csv" ) || error( "Couldn't open file $wrkdir/$server/$host/cpu.csv $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @vm_lines = <VML>;
    close(VML);

    foreach my $vm_line (@vm_lines) {
      chomp $vm_line;

      # vm-jindra,4,0,-1,normal,4000,CentOS 7 (64-bit),poweredOn,guestToolsRunning,ipaddr,501c487b-66db-574a-1578-8bb38694a41f,4096
      my ( $vm_name, undef, undef, undef, undef, undef, undef, undef, undef, undef, $vm_uuid ) = split( /,/, $vm_line );
      if ( -f "$wrkdir/vmware_VMs/$vm_uuid.rrm" ) {
        push( @vms, "$server,$vm_name,$wrkdir/vmware_VMs/$vm_uuid.rrm" );
      }
    }
  }

  my $vm_idx = 0;
  foreach my $line (@vms) {
    my ( $esxi, $vm_name, $rrd ) = split( /,/, $line );

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:cur=\"$rrd\":Memory_granted:AVERAGE";
    $cmd .= " CDEF:curg=cur,1024,/,1024,/";

    $cmd .= " XPORT:curg:\"$vm_name [GB]\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        $data{STATS}{$timestamp}{"$vm_name [GB]"} = $value1;
      }
    }

    # set csv header
    $data{CSVHEADER}{$vm_idx} = "$vm_name [GB]";
    $vm_idx++;
  }
  $data{NAME} = "$server";

  return 1;
}

sub xport_esxi_memalloc {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/$server/$host/pool.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:total=\"$rrd\":Memory_Host_Size:AVERAGE";
  $cmd .= " DEF:baloon=\"$rrd\":Memory_baloon:AVERAGE";
  $cmd .= " DEF:granted=\"$rrd\":Memory_granted:AVERAGE";
  $cmd .= " DEF:active=\"$rrd\":Memory_active:AVERAGE";
  $cmd .= " CDEF:grantg=granted,1024,/,1024,/";
  $cmd .= " CDEF:activeg=active,1024,/,1024,/";
  $cmd .= " CDEF:baloong=baloon,1024,/,1024,/";
  $cmd .= " CDEF:totg=total,1024,/,1024,/,1024,/";

  $cmd .= " XPORT:totg:\"Total [GB]\"";
  $cmd .= " XPORT:grantg:\"Granted [GB]\"";
  $cmd .= " XPORT:activeg:\"Active [GB]\"";
  $cmd .= " XPORT:baloong:\"Baloon [GB]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value4    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      if ( isdigit($value4) ) {
        $value4 = sprintf '%.2f', $value4;
      }
      else {
        $value4 = '';
      }
      $data{STATS}{$timestamp}{'Total [GB]'}   = $value1;
      $data{STATS}{$timestamp}{'Granted [GB]'} = $value2;
      $data{STATS}{$timestamp}{'Active [GB]'}  = $value3;
      $data{STATS}{$timestamp}{'Baloon [GB]'}  = $value4;
    }
  }

  # set csv header
  $data{NAME}         = "$cluster - $server";
  $data{CSVHEADER}{1} = "Total [GB]";
  $data{CSVHEADER}{2} = "Granted [GB]";
  $data{CSVHEADER}{3} = "Active [GB]";
  $data{CSVHEADER}{4} = "Baloon [GB]";

  return 1;
}

sub xport_vm_rdy {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $vm_name = shift;
  my $vm_uuid = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/vmware_VMs/$vm_uuid.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  # if this file exists & contains UNIX time, graph CPU_ready from this time, otherwise not limited
  my $CPU_ready_time_file = "$wrkdir/vmware_VMs/CPU_ready_time.txt";
  my $stime               = 0;

  # care for start time for CPU_ready
  if ( -f $CPU_ready_time_file ) {
    if ( open( FF, "<$CPU_ready_time_file" ) ) {
      $stime = (<FF>);
      close(FF);

      chomp $stime;
      $stime *= 1;
    }
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  my $kbmb     = 1;
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:CPU_ready_ms=\"$rrd\":CPU_ready_ms:AVERAGE";
  $cmd .= " DEF:vCPU=\"$rrd\":vCPU:AVERAGE";
  $cmd .= " CDEF:pagein_bn=CPU_ready_ms,200,/,vCPU,/";
  $cmd .= " CDEF:pagein_b=TIME,$stime,LT,0,pagein_bn,IF";

  #$cmd .= " CDEF:pageout_b_nf=vCPU,$kbmb,/";
  #$cmd .= " LINE1:pagein_b#FF4040:\" $leg_read  \"";
  #$cmd .= " CDEF:vcpu=pageout_b_nf,$kbmb,*";

  $cmd .= " XPORT:pagein_b:\"CPU READY/vCPU\"";
  $cmd .= " XPORT:vCPU:\"vCPU [units]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1564351260</t><v>7.2856117916e-01</v><v>0.0000000000e+00</v><v>2.2343333333e+00</v><v>0.0000000000e+00</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{"CPU READY/vCPU"} = $value1;
      $data{STATS}{$timestamp}{"vCPU [units]"}   = $value2;
    }
  }

  # set csv header
  $data{CSVHEADER}{1} = "CPU READY/vCPU";
  $data{CSVHEADER}{2} = "vCPU [units]";
  $data{NAME}         = "$vm_name";

  return 1;
}

sub xport_vm_comp {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $vm_name = shift;
  my $vm_uuid = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/vmware_VMs/$vm_uuid.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  my $kbmb     = 1024;
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Memory_compres=\"$rrd\":Memory_compres:AVERAGE";
  $cmd .= " DEF:Memory_decompres=\"$rrd\":Memory_decompres:AVERAGE";
  $cmd .= " CDEF:pagein_b=Memory_compres,$kbmb,/";
  $cmd .= " CDEF:pageout_b=Memory_decompres,$kbmb,/";
  $cmd .= " XPORT:pagein_b:\"Decompres [KB/sec]\"";
  $cmd .= " XPORT:pageout_b:\"Compres [KB/sec]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1564351260</t><v>7.2856117916e-01</v><v>0.0000000000e+00</v><v>2.2343333333e+00</v><v>0.0000000000e+00</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{"Decompres [KB/sec]"} = $value1;
      $data{STATS}{$timestamp}{"Compres [KB/sec]"}   = $value2;
    }
  }

  # set csv header
  $data{CSVHEADER}{1} = "Decompres [KB/sec]";
  $data{CSVHEADER}{2} = "Compres [KB/sec]";
  $data{NAME}         = "$vm_name";

  return 1;
}

sub xport_vm_swap {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $vm_name = shift;
  my $vm_uuid = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/vmware_VMs/$vm_uuid.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  my $kbmb     = 1000;
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Memory_swapin=\"$rrd\":Memory_swapin:AVERAGE";
  $cmd .= " DEF:Memory_swapout=\"$rrd\":Memory_swapout:AVERAGE";
  $cmd .= " CDEF:pagein_b=Memory_swapin,$kbmb,/";
  $cmd .= " CDEF:pageout_b=Memory_swapout,$kbmb,/";
  $cmd .= " XPORT:pagein_b:\"Out [MB/sec]\"";
  $cmd .= " XPORT:pageout_b:\"In [MB/sec]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1564351260</t><v>7.2856117916e-01</v><v>0.0000000000e+00</v><v>2.2343333333e+00</v><v>0.0000000000e+00</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{"Out [MB/sec]"} = $value1;
      $data{STATS}{$timestamp}{"In [MB/sec]"}  = $value2;
    }
  }

  # set csv header
  $data{CSVHEADER}{1} = "Out [MB/sec]";
  $data{CSVHEADER}{2} = "In [MB/sec]";
  $data{NAME}         = "$vm_name";

  return 1;
}

sub xport_vm_net {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $vm_name = shift;
  my $vm_uuid = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/vmware_VMs/$vm_uuid.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  my $kbmb     = 1000;
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Network_usage=\"$rrd\":Network_usage:AVERAGE";
  $cmd .= " CDEF:pagein_b=Network_usage,$kbmb,/";
  $cmd .= " XPORT:pagein_b:\"Usage [MB/sec]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1564351260</t><v>7.2856117916e-01</v><v>0.0000000000e+00</v><v>2.2343333333e+00</v><v>0.0000000000e+00</v></row>
      my ( $timestamp, $value1 ) = split( "</t><v>", $row );

      $timestamp =~ s/^<row><t>//;
      $value1    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      $data{STATS}{$timestamp}{"Usage [MB/sec]"} = $value1;
    }
  }

  # set csv header
  $data{CSVHEADER}{1} = "Usage [MB/sec]";
  $data{NAME} = "$vm_name";

  return 1;
}

sub xport_vm_disk {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $vm_name = shift;
  my $vm_uuid = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/vmware_VMs/$vm_uuid.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  my $kbmb     = 1024;
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Disk_usage=\"$rrd\":Disk_usage:AVERAGE";
  $cmd .= " CDEF:pagein_b=Disk_usage,$kbmb,/";
  $cmd .= " XPORT:pagein_b:\"Usage [MB/sec]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1564351260</t><v>7.2856117916e-01</v><v>0.0000000000e+00</v><v>2.2343333333e+00</v><v>0.0000000000e+00</v></row>
      my ( $timestamp, $value1 ) = split( "</t><v>", $row );

      $timestamp =~ s/^<row><t>//;
      $value1    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      $data{STATS}{$timestamp}{"Usage [MB/sec]"} = $value1;
    }
  }

  # set csv header
  $data{CSVHEADER}{1} = "Usage [MB/sec]";
  $data{NAME} = "$vm_name";

  return 1;
}

sub xport_vm_mem {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $vm_name = shift;
  my $vm_uuid = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/vmware_VMs/$vm_uuid.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  my $kbmb     = 1024;
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:Memory_granted=\"$rrd\":Memory_granted:AVERAGE";
  $cmd .= " DEF:Memory_active=\"$rrd\":Memory_active:AVERAGE";
  $cmd .= " DEF:Memory_baloon=\"$rrd\":Memory_baloon:AVERAGE";

  $cmd .= " CDEF:usage=Memory_granted,$kbmb,/,$kbmb,/";
  $cmd .= " CDEF:pageout_b_nf=Memory_baloon,$kbmb,/,$kbmb,/";    # baloon is MB ?
                                                                 #$cmd .= " CDEF:pagein_b=Memory_active,$kbmb,/,$kbmb,/";        # active
  $cmd .= " CDEF:pagein_b_nf=Memory_active,$kbmb,/,$kbmb,/";     # active

  $cmd .= " XPORT:usage:\"Mem granted [GB]\"";
  $cmd .= " XPORT:pageout_b_nf:\"Mem baloon [GB]\"";
  $cmd .= " XPORT:pagein_b_nf:\"Mem active [GB]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1564351260</t><v>7.2856117916e-01</v><v>0.0000000000e+00</v><v>2.2343333333e+00</v><v>0.0000000000e+00</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value3    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      $data{STATS}{$timestamp}{"Mem granted [GB]"} = $value1;
      $data{STATS}{$timestamp}{"Mem baloon [GB]"}  = $value2;
      $data{STATS}{$timestamp}{"Mem active [GB]"}  = $value3;
    }
  }

  # set csv header
  $data{CSVHEADER}{1} = "Mem granted [GB]";
  $data{CSVHEADER}{2} = "Mem baloon [GB]";
  $data{CSVHEADER}{3} = "Mem active [GB]";
  $data{NAME}         = "$vm_name";

  return 1;
}

sub xport_cluster_cpu_rdy {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  # if this file exists & contains UNIX time, graph CPU_ready from this time, otherwise not limited
  my $CPU_ready_time_file = "$wrkdir/vmware_VMs/CPU_ready_time.txt";
  my $stime               = 0;

  # care for start time for CPU_ready
  if ( -f $CPU_ready_time_file ) {
    if ( open( FF, "<$CPU_ready_time_file" ) ) {
      $stime = (<FF>);
      close(FF);

      chomp $stime;
      $stime *= 1;
    }
  }

  # find VMs under this cluster
  my @vms;
  if ( -f "$wrkdir/$server/$host/hosts_in_cluster" ) {
    open( HOSTS, "< $wrkdir/$server/$host/hosts_in_cluster" ) || error( "Couldn't open file $wrkdir/$server/$host/hosts_in_cluster $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = <HOSTS>;
    close(HOSTS);

    foreach my $line (@lines) {
      chomp $line;
      my ( $esxi_ip, $vcenter_ip ) = split( /XORUX/, $line );
      if ( -f "$wrkdir/$esxi_ip/$vcenter_ip/cpu.csv" ) {
        open( VML, "< $wrkdir/$esxi_ip/$vcenter_ip/cpu.csv" ) || error( "Couldn't open file $wrkdir/$esxi_ip/$vcenter_ip/cpu.csv $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        my @vm_lines = <VML>;
        close(VML);

        foreach my $vm_line (@vm_lines) {
          chomp $vm_line;

          # vm-jindra,4,0,-1,normal,4000,CentOS 7 (64-bit),poweredOn,guestToolsRunning,ipaddr,501c487b-66db-574a-1578-8bb38694a41f,4096
          my ( $vm_name, undef, undef, undef, undef, undef, undef, undef, undef, undef, $vm_uuid ) = split( /,/, $vm_line );
          if ( -f "$wrkdir/vmware_VMs/$vm_uuid.rrm" ) {
            push( @vms, "$esxi_ip,$vm_name,$wrkdir/vmware_VMs/$vm_uuid.rrm" );
          }
        }
      }
    }
  }

  my $vm_idx = 0;
  foreach my $line (@vms) {
    my ( $esxi, $vm_name, $rrd ) = split( /,/, $line );

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:CPU_ready_msx=\"$rrd\":CPU_ready_ms:AVERAGE";
    $cmd .= " DEF:vCPU=\"$rrd\":vCPU:AVERAGE";
    $cmd .= " CDEF:CPU_ready_ms=TIME,$stime,LT,0,CPU_ready_msx,IF";
    $cmd .= " CDEF:CPU_ready_leg=CPU_ready_ms,200,/,vCPU,/";
    $cmd .= " XPORT:CPU_ready_leg:\"$esxi - $vm_name [CPU-ready-%/vCPU]\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        $data{STATS}{$timestamp}{"$esxi - $vm_name [CPU-ready-%/vCPU]"} = $value1;
      }
    }

    # set csv header
    $data{CSVHEADER}{$vm_idx} = "$esxi - $vm_name [CPU-ready-%/vCPU]";
    $vm_idx++;
  }
  $data{NAME} = "$cluster";

  return 1;
}

sub xport_cluster_memory {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  # find VMs under this cluster
  my @inventory;
  if ( -f "$wrkdir/$server/$host/hosts_in_cluster" ) {
    open( HOSTS, "< $wrkdir/$server/$host/hosts_in_cluster" ) || error( "Couldn't open file $wrkdir/$server/$host/hosts_in_cluster $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = <HOSTS>;
    close(HOSTS);

    foreach my $line (@lines) {
      chomp $line;
      my ( $esxi_ip, $vcenter_ip ) = split( /XORUX/, $line );
      if ( -f "$wrkdir/$esxi_ip/$vcenter_ip/pool.rrm" ) {
        push( @inventory, "$esxi_ip,$wrkdir/$esxi_ip/$vcenter_ip/pool.rrm" );
      }
    }
  }

  #
  # aggregate memory from ESXi servers
  #
  foreach my $line (@inventory) {
    my ( $esxi, $rrd ) = split( /,/, $line );

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:hosts_m=\"$rrd\":Memory_Host_Size:AVERAGE";
    $cmd .= " CDEF:hosts_mem=hosts_m,1024,/,1024,/,1024,/";
    $cmd .= " XPORT:hosts_mem:\"$esxi mem\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;

          if ( exists $data{STATS}{$timestamp}{"Total [GB]"} && isdigit( $data{STATS}{$timestamp}{"Total [GB]"} ) ) {
            $data{STATS}{$timestamp}{"Total [GB]"} += $value1;
          }
          else {
            $data{STATS}{$timestamp}{"Total [GB]"} = $value1;
          }
        }
      }
    }

    # set csv header
    $data{CSVHEADER}{0} = "Total [GB]";

    #$idx++;
  }

  #
  # rest from single rrd (Granted, Consumed, Active, ...)
  #
  my $rrd = "$wrkdir/$server/$host/cluster.rrc";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:total=\"$rrd\":Memory_total_MB:AVERAGE";
  $cmd .= " DEF:granted=\"$rrd\":Memory_granted_KB:AVERAGE";
  $cmd .= " DEF:active=\"$rrd\":Memory_active_KB:AVERAGE";
  $cmd .= " DEF:consumed=\"$rrd\":Memory_consumed_KB:AVERAGE";
  $cmd .= " DEF:balloon=\"$rrd\":Memory_baloon_KB:AVERAGE";
  $cmd .= " DEF:swap=\"$rrd\":Memory_swap_KB:AVERAGE";

  $cmd .= " CDEF:grantg=granted,1024,/,1024,/";
  $cmd .= " CDEF:activeg=active,1024,/,1024,/";
  $cmd .= " CDEF:totg=total,1024,/";
  $cmd .= " CDEF:consumg=consumed,1024,/,1024,/";
  $cmd .= " CDEF:balloong=balloon,1024,/,1024,/";
  $cmd .= " CDEF:swapg=swap,1024,/,1024,/";

  $cmd .= " XPORT:totg:\"Total effective [GB]\"";
  $cmd .= " XPORT:grantg:\"Granted [GB]\"";
  $cmd .= " XPORT:consumg:\"Consumed [GB]\"";
  $cmd .= " XPORT:activeg:\"Active [GB]\"";
  $cmd .= " XPORT:balloong:\"Balloon [GB]\"";
  $cmd .= " XPORT:swapg:\"Swap out [GB]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4, $value5, $value6 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value6    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      if ( isdigit($value4) ) {
        $value4 = sprintf '%.2f', $value4;
      }
      else {
        $value4 = '';
      }
      if ( isdigit($value5) ) {
        $value5 = sprintf '%.2f', $value5;
      }
      else {
        $value5 = '';
      }
      if ( isdigit($value6) ) {
        $value6 = sprintf '%.2f', $value6;
      }
      else {
        $value6 = '';
      }
      $data{STATS}{$timestamp}{'Total effective [GB]'} = $value1;
      $data{STATS}{$timestamp}{'Granted [GB]'}         = $value2;
      $data{STATS}{$timestamp}{'Consumed [GB]'}        = $value3;
      $data{STATS}{$timestamp}{'Active [GB]'}          = $value4;
      $data{STATS}{$timestamp}{'Balloon [GB]'}         = $value5;
      $data{STATS}{$timestamp}{'Swap out [GB]'}        = $value6;
    }
  }

  # set csv header
  $data{CSVHEADER}{1} = 'Total effective [GB]';
  $data{CSVHEADER}{2} = 'Granted [GB]';
  $data{CSVHEADER}{3} = 'Consumed [GB]';
  $data{CSVHEADER}{4} = 'Active [GB]';
  $data{CSVHEADER}{5} = 'Balloon [GB]';
  $data{CSVHEADER}{6} = 'Swap out [GB]';

  $data{NAME} = "$cluster";

  return 1;
}

sub xport_vm_cpu_prct {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $vm_name = shift;
  my $vm_uuid = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/vmware_VMs/$vm_uuid.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:cpuusageproc=\"$rrd\":CPU_usage_Proc:AVERAGE";
  $cmd .= " DEF:vcpu_l=\"$rrd\":vCPU:AVERAGE";
  $cmd .= " DEF:one_core_hz=\"$rrd\":host_hz:AVERAGE";
  $cmd .= " DEF:cpuusage=\"$rrd\":CPU_usage:AVERAGE";

  $cmd .= " CDEF:CPU_usage_Proc=cpuusageproc,100,/";
  $cmd .= " CDEF:pageout_b_nf=vcpu_l,100,/";
  $cmd .= " CDEF:vCPU=vcpu_l,1,/";                                                             # number
  $cmd .= " CDEF:host_MHz=one_core_hz,1000,/,1000,/";                                          # to be in MHz
  $cmd .= " CDEF:CPU_usage=cpuusage,1,/";                                                      # MHz
  $cmd .= " CDEF:CPU_usage_res=CPU_usage,host_MHz,/,vCPU,/,100,*";                             # usage proc counted
  $cmd .= " CDEF:pagein_b_raw=CPU_usage_Proc,UN,CPU_usage_res,CPU_usage_Proc,IF";
  $cmd .= " CDEF:pagein_b=pagein_b_raw,UN,UNKN,pagein_b_raw,100,GT,100,pagein_b_raw,IF,IF";    # cut more than 100%, VMware does the same
  $cmd .= " CDEF:vcpu=pageout_b_nf,100,*";

  $cmd .= " XPORT:pagein_b:\"CPU usage [%]\"";
  $cmd .= " XPORT:vcpu:\"vCPU [units]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1564351260</t><v>7.2856117916e-01</v><v>0.0000000000e+00</v><v>2.2343333333e+00</v><v>0.0000000000e+00</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{"CPU usage [%]"} = $value1;
      $data{STATS}{$timestamp}{"vCPU [units]"}  = $value2;
    }
  }

  # set csv header
  $data{CSVHEADER}{1} = "CPU usage [%]";
  $data{CSVHEADER}{2} = "vCPU [units]";
  $data{NAME}         = "$vm_name";

  return 1;
}

sub xport_vm_cpu {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $vm_name = shift;
  my $vm_uuid = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/vmware_VMs/$vm_uuid.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:cpu_entitl_mhz=\"$rrd\":CPU_Alloc:AVERAGE";
  $cmd .= " DEF:utiltot_mhz=\"$rrd\":CPU_usage:AVERAGE";
  $cmd .= " DEF:one_core_hz=\"$rrd\":host_hz:AVERAGE";

  $cmd .= " CDEF:utiltot_c=utiltot_mhz,one_core_hz,/,1000000,*";
  $cmd .= " CDEF:cpu_entitl_c=cpu_entitl_mhz,one_core_hz,/,1000000,*";

  $cmd .= " CDEF:utiltot_ghz=utiltot_mhz,1000,/";
  $cmd .= " CDEF:cpu_entitl_ghz=cpu_entitl_mhz,1000,/";

  $cmd .= " XPORT:utiltot_c:\"CPU usage [cores]\"";
  $cmd .= " XPORT:cpu_entitl_c:\"reserved CPU [cores]\"";
  $cmd .= " XPORT:utiltot_ghz:\"CPU usage [GHz]\"";
  $cmd .= " XPORT:cpu_entitl_ghz:\"reserved CPU [GHz]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1564351260</t><v>7.2856117916e-01</v><v>0.0000000000e+00</v><v>2.2343333333e+00</v><v>0.0000000000e+00</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value4    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      if ( isdigit($value4) ) {
        $value4 = sprintf '%.2f', $value4;
      }
      else {
        $value4 = '';
      }
      $data{STATS}{$timestamp}{"CPU usage [cores]"}    = $value1;
      $data{STATS}{$timestamp}{"reserved CPU [cores]"} = $value2;
      $data{STATS}{$timestamp}{"CPU usage [GHz]"}      = $value3;
      $data{STATS}{$timestamp}{"reserved CPU [GHz]"}   = $value4;
    }
  }

  # set csv header
  $data{CSVHEADER}{1} = "CPU usage [cores]";
  $data{CSVHEADER}{2} = "reserved CPU [cores]";
  $data{CSVHEADER}{3} = "CPU usage [GHz]";
  $data{CSVHEADER}{4} = "reserved CPU [GHz]";
  $data{NAME}         = "$vm_name";

  return 1;
}

sub xport_esxi_cpu_vms {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  # find VMs under this ESXi
  my @vms;
  if ( -f "$wrkdir/$server/$host/cpu.csv" ) {
    open( VML, "< $wrkdir/$server/$host/cpu.csv" ) || error( "Couldn't open file $wrkdir/$server/$host/cpu.csv $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @vm_lines = <VML>;
    close(VML);

    foreach my $vm_line (@vm_lines) {
      chomp $vm_line;

      # vm-jindra,4,0,-1,normal,4000,CentOS 7 (64-bit),poweredOn,guestToolsRunning,ipaddr,501c487b-66db-574a-1578-8bb38694a41f,4096
      my ( $vm_name, undef, undef, undef, undef, undef, undef, undef, undef, undef, $vm_uuid ) = split( /,/, $vm_line );
      if ( -f "$wrkdir/vmware_VMs/$vm_uuid.rrm" ) {
        push( @vms, "$server,$vm_name,$wrkdir/vmware_VMs/$vm_uuid.rrm" );
      }
    }
  }

  my $vm_idx = 0;
  foreach my $line (@vms) {
    my ( $esxi, $vm_name, $rrd ) = split( /,/, $line );

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:utiltot_mhz=\"$rrd\":CPU_usage:AVERAGE";
    $cmd .= " CDEF:utiltot_ghz=utiltot_mhz,1000,/";
    $cmd .= " CDEF:utiltot=utiltot_mhz,1000,/";              # since 4.74- (u)
    $cmd .= " XPORT:utiltot:\"$vm_name [GHz]\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        $data{STATS}{$timestamp}{"$vm_name [GHz]"} = $value1;
      }
    }

    # set csv header
    $data{CSVHEADER}{$vm_idx} = "$vm_name [GHz]";
    $vm_idx++;
  }
  $data{NAME} = "$server";

  return 1;
}

sub xport_esxi_cpu {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  my $rrd = "$wrkdir/$server/$host/pool.rrm";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:cpu_entitl_mhz=\"$rrd\":CPU_Alloc:AVERAGE";
  $cmd .= " DEF:utiltot_mhz=\"$rrd\":CPU_usage:AVERAGE";
  $cmd .= " DEF:one_core_hz=\"$rrd\":host_hz:AVERAGE";
  $cmd .= " CDEF:cpuutiltot=utiltot_mhz,one_core_hz,/,1000000,*";
  $cmd .= " CDEF:cpu=cpu_entitl_mhz,one_core_hz,/,1000000,*";
  $cmd .= " CDEF:cpu_entitl_ghz=cpu_entitl_mhz,1000,/";
  $cmd .= " CDEF:utiltot_ghz=utiltot_mhz,1000,/";
  $cmd .= " XPORT:cpu:\"Total [cores]\"";
  $cmd .= " XPORT:cpuutiltot:\"Utilization [cores]\"";
  $cmd .= " XPORT:cpu_entitl_ghz:\"Total [Ghz]\"";
  $cmd .= " XPORT:utiltot_ghz:\"Utilization [Ghz]\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value4    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      if ( isdigit($value4) ) {
        $value4 = sprintf '%.2f', $value4;
      }
      else {
        $value4 = '';
      }
      $data{STATS}{$timestamp}{'Total [cores]'}       = $value1;
      $data{STATS}{$timestamp}{'Utilization [cores]'} = $value2;
      $data{STATS}{$timestamp}{'Total [Ghz]'}         = $value3;
      $data{STATS}{$timestamp}{'Utilization [Ghz]'}   = $value4;
    }
  }

  # set csv header
  $data{NAME}         = "$cluster - $server";
  $data{CSVHEADER}{1} = "Total [cores]";
  $data{CSVHEADER}{2} = "Utilization [cores]";
  $data{CSVHEADER}{3} = "Total [Ghz]";
  $data{CSVHEADER}{4} = "Utilization [Ghz]";

  return 1;
}

sub xport_cluster_lan {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  # find VMs under this cluster
  my @inventory;
  if ( -f "$wrkdir/$server/$host/hosts_in_cluster" ) {
    open( HOSTS, "< $wrkdir/$server/$host/hosts_in_cluster" ) || error( "Couldn't open file $wrkdir/$server/$host/hosts_in_cluster $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = <HOSTS>;
    close(HOSTS);

    foreach my $line (@lines) {
      chomp $line;
      my ( $esxi_ip, $vcenter_ip ) = split( /XORUX/, $line );
      if ( -f "$wrkdir/$esxi_ip/$vcenter_ip/pool.rrm" ) {
        push( @inventory, "$esxi_ip,$wrkdir/$esxi_ip/$vcenter_ip/pool.rrm" );
      }
    }
  }

  my $idx = 0;
  foreach my $line (@inventory) {
    my ( $esxi, $rrd ) = split( /,/, $line );

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:net_rec=\"$rrd\":Network_received:AVERAGE";
    $cmd .= " DEF:net_tra=\"$rrd\":Network_transmitted:AVERAGE";
    $cmd .= " CDEF:read=net_rec,1000,/";
    $cmd .= " CDEF:write=net_tra,1000,/";
    $cmd .= " XPORT:read:\"$esxi read [MB/sec]\"";
    $cmd .= " XPORT:write:\"$esxi write [MB/sec]\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
        }
        else {
          $value2 = '';
        }
        $data{STATS}{$timestamp}{"$esxi read [MB/sec]"}  = $value1;
        $data{STATS}{$timestamp}{"$esxi write [MB/sec]"} = $value2;
      }
    }

    # set csv header
    $data{CSVHEADER}{$idx} = "$esxi read [MB/sec]";
    $idx++;
    $data{CSVHEADER}{$idx} = "$esxi write [MB/sec]";
    $idx++;
  }
  $data{NAME} = "$cluster";

  return 1;
}

sub xport_cluster_cpu_servers {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  # find VMs under this cluster
  my @inventory;
  if ( -f "$wrkdir/$server/$host/hosts_in_cluster" ) {
    open( HOSTS, "< $wrkdir/$server/$host/hosts_in_cluster" ) || error( "Couldn't open file $wrkdir/$server/$host/hosts_in_cluster $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = <HOSTS>;
    close(HOSTS);

    foreach my $line (@lines) {
      chomp $line;
      my ( $esxi_ip, $vcenter_ip ) = split( /XORUX/, $line );
      if ( -f "$wrkdir/$esxi_ip/$vcenter_ip/pool.rrm" ) {
        push( @inventory, "$esxi_ip,$wrkdir/$esxi_ip/$vcenter_ip/pool.rrm" );
      }
    }
  }

  my $idx = 0;
  foreach my $line (@inventory) {
    my ( $esxi, $rrd ) = split( /,/, $line );

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:utiltot_mhz=\"$rrd\":CPU_usage:AVERAGE";
    $cmd .= " DEF:one_core_hz=\"$rrd\":host_hz:AVERAGE";
    $cmd .= " CDEF:cpuutiltot=utiltot_mhz,one_core_hz,/,1000000,*";
    $cmd .= " XPORT:cpuutiltot:\"$esxi [cores]\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        $data{STATS}{$timestamp}{"$esxi [cores]"} = $value1;
      }
    }

    # set csv header
    $data{CSVHEADER}{$idx} = "$esxi [cores]";
    $idx++;
  }
  $data{NAME} = "$cluster";

  return 1;
}

sub xport_cluster_cpu_vms {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  # find VMs under this cluster
  my @vms;
  if ( -f "$wrkdir/$server/$host/hosts_in_cluster" ) {
    open( HOSTS, "< $wrkdir/$server/$host/hosts_in_cluster" ) || error( "Couldn't open file $wrkdir/$server/$host/hosts_in_cluster $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = <HOSTS>;
    close(HOSTS);

    foreach my $line (@lines) {
      chomp $line;
      my ( $esxi_ip, $vcenter_ip ) = split( /XORUX/, $line );
      if ( -f "$wrkdir/$esxi_ip/$vcenter_ip/cpu.csv" ) {
        open( VML, "< $wrkdir/$esxi_ip/$vcenter_ip/cpu.csv" ) || error( "Couldn't open file $wrkdir/$esxi_ip/$vcenter_ip/cpu.csv $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        my @vm_lines = <VML>;
        close(VML);

        foreach my $vm_line (@vm_lines) {
          chomp $vm_line;

          # vm-jindra,4,0,-1,normal,4000,CentOS 7 (64-bit),poweredOn,guestToolsRunning,ipaddr,501c487b-66db-574a-1578-8bb38694a41f,4096
          my ( $vm_name, undef, undef, undef, undef, undef, undef, undef, undef, undef, $vm_uuid ) = split( /,/, $vm_line );
          if ( -f "$wrkdir/vmware_VMs/$vm_uuid.rrm" ) {
            push( @vms, "$esxi_ip,$vm_name,$wrkdir/vmware_VMs/$vm_uuid.rrm" );
          }
        }
      }
    }
  }

  my $vm_idx = 0;
  foreach my $line (@vms) {
    my ( $esxi, $vm_name, $rrd ) = split( /,/, $line );

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }

    # avoid old lpars which do not exist in the period
    if ( ( stat($rrd) )[9] < $sunix ) { next; }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:utiltot_mhz=\"$rrd\":CPU_usage:AVERAGE";
    $cmd .= " CDEF:utiltot_ghz=utiltot_mhz,1000,/";
    $cmd .= " CDEF:utiltot=utiltot_mhz,1000,/";              # since 4.74- (u)
    $cmd .= " XPORT:utiltot:\"$esxi - $vm_name [GHz]\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        $data{STATS}{$timestamp}{"$esxi - $vm_name [GHz]"} = $value1;
      }
    }

    # set csv header
    $data{CSVHEADER}{$vm_idx} = "$esxi - $vm_name [GHz]";
    $vm_idx++;
  }
  $data{NAME} = "$cluster";

  return 1;
}

sub xport_cluster_cpu {
  my $vcenter = shift;
  my $cluster = shift;
  my $host    = shift;
  my $server  = shift;
  my $sunix   = shift;
  my $eunix   = shift;

  #print STDERR localtime($sunix) . " - " . localtime($eunix) . "\n";

  my $rrd = "$wrkdir/$server/$host/cluster.rrc";
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  $cmd .= " DEF:cpu_MHz=\"$rrd\":CPU_total_MHz:AVERAGE";
  $cmd .= " CDEF:cpu=cpu_MHz,1000,/";
  $cmd .= " DEF:cpuutiltot_MHz=\"$rrd\":CPU_usage_MHz:AVERAGE";
  $cmd .= " CDEF:cpuutiltot=cpuutiltot_MHz,1000,/";
  $cmd .= " XPORT:cpu:\"Total effective in GHz\"";
  $cmd .= " XPORT:cpuutiltot:\"Utilization in GHz\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Total effective in GHz'} = $value1;
      $data{STATS}{$timestamp}{'Utilization in GHz'}     = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$cluster";
  $data{CSVHEADER}{1} = "Total effective in GHz";
  $data{CSVHEADER}{2} = "Utilization in GHz";

  return 1;
}

sub xport_custom_pool {
  my $item  = shift;
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  if    ( $item eq "custom" )    { xport_custom_pool_cpu( $name, $sunix, $eunix ); }
  elsif ( $item eq "custommem" ) { xport_custom_pool_memalloc( $name, $sunix, $eunix ); }
  else                           { error( "Unknown CUSTOM GROUP item! custom-group=\"$name\",item=\"$item\" $!" . __FILE__ . ":" . __LINE__ ) && exit; }

  return 1;
}

sub xport_custom_lpar {
  my $item  = shift;
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  if    ( $item eq "custom" )       { xport_custom_lpar_cpu( $name, $sunix, $eunix ); }
  elsif ( $item eq "custommem" )    { xport_custom_lpar_memalloc( $name, $sunix, $eunix ); }
  elsif ( $item eq "customosmem" )  { xport_custom_lpar_mem( $name, $sunix, $eunix ); }
  elsif ( $item eq "customoslan" )  { xport_custom_lpar_lan( $name, $sunix, $eunix ); }
  elsif ( $item eq "customossan1" ) { xport_custom_lpar_san1( $name, $sunix, $eunix ); }
  elsif ( $item eq "customossan2" ) { xport_custom_lpar_san2( $name, $sunix, $eunix ); }
  else                              { error( "Unknown CUSTOM GROUP item! custom-group=\"$name\",item=\"$item\" $!" . __FILE__ . ":" . __LINE__ ) && exit; }

  return 1;
}

sub xport_custom_vmware {
  my $item  = shift;
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  if ( $item eq "custom_esxi_cpu" ) {
    xport_custom_esxi_cpu( $name, $sunix, $eunix );
  }
  elsif ( $item eq "custom" || $item eq "customvmmemactive" || $item eq "customvmmemconsumed" ) {
    xport_custom_vm( $name, $item, $sunix, $eunix );
  }
  elsif ( $item eq "customdisk" || $item eq "customnet" ) {
    xport_custom_vm_rw( $name, $item, $sunix, $eunix );
  }
  else {
    error( "Unknown CUSTOM GROUP item! custom-group=\"$name\",item=\"$item\" $!" . __FILE__ . ":" . __LINE__ ) && exit;
  }

  return 1;
}

sub xport_custom_vm_rw {
  my $name  = shift;
  my $item  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $divider  = 1000;
  my $ds_name1 = "Disk_read";
  my $ds_name2 = "Disk_write";
  if ( $item eq "customnet" ) {
    $ds_name1 = "Network_received";
    $ds_name2 = "Network_transmitted";
  }

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $vm_uuid = $rrd;
    $vm_uuid = basename($vm_uuid);
    $vm_uuid =~ s/\..*$//;    # remove suffix like .rrd

    my $name_out = $vm_uuid;
    if ( exists $vmware_inventory{VM}{$vm_uuid}{VM_NAME} ) {
      $name_out = $vmware_inventory{VM}{$vm_uuid}{VM_NAME};
    }
    if ( exists $vmware_inventory{VM}{$vm_uuid}{SERVER} ) {
      $name_out = "$vmware_inventory{VM}{$vm_uuid}{SERVER}: $name_out";
    }

    my $name_out1 = "R - $name_out";
    my $name_out2 = "W - $name_out";

    my $cmd      = "";
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    $cmd .= " DEF:recb=\"$rrd\":$ds_name1:AVERAGE";
    $cmd .= " DEF:trab=\"$rrd\":$ds_name2:AVERAGE";
    $cmd .= " CDEF:recb_u=recb,$divider,/";
    $cmd .= " CDEF:trab_u=trab,$divider,/";

    $cmd .= " XPORT:recb_u:read";
    $cmd .= " XPORT:trab_u:write";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {
        if ( !test_rrdtool_xport_line( $row, "2" ) ) { next; }

        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
        }
        else {
          $value2 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{$name_out1} ) {
          $data{STATS}{$timestamp}{$name_out1} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{$name_out1} && !isdigit( $data{STATS}{$timestamp}{$name_out1} ) ) {
          $data{STATS}{$timestamp}{$name_out1} = $value1;
        }
        if ( !exists $data{STATS}{$timestamp}{$name_out2} ) {
          $data{STATS}{$timestamp}{$name_out2} = $value2;
        }
        elsif ( exists $data{STATS}{$timestamp}{$name_out2} && !isdigit( $data{STATS}{$timestamp}{$name_out2} ) ) {
          $data{STATS}{$timestamp}{$name_out2} = $value2;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id1 = $metric_idx;
    if ( exists $lpar_idxs{$name_out1} && isdigit( $lpar_idxs{$name_out1} ) ) {
      $header_id1 = $lpar_idxs{$name_out1};
    }
    $lpar_idxs{$name_out1} = $header_id1;
    $data{CSVHEADER}{$header_id1} = $name_out1;

    $metric_idx++;
    my $header_id2 = $metric_idx;
    if ( exists $lpar_idxs{$name_out2} && isdigit( $lpar_idxs{$name_out2} ) ) {
      $header_id2 = $lpar_idxs{$name_out2};
    }
    $lpar_idxs{$name_out2} = $header_id2;
    $data{CSVHEADER}{$header_id2} = $name_out2;
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_vm {
  my $name  = shift;
  my $item  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $vm_uuid = $rrd;
    $vm_uuid = basename($vm_uuid);
    $vm_uuid =~ s/\..*$//;    # remove suffix like .rrd

    my $name_out = $vm_uuid;
    if ( exists $vmware_inventory{VM}{$vm_uuid}{VM_NAME} ) {
      $name_out = $vmware_inventory{VM}{$vm_uuid}{VM_NAME};
    }
    if ( exists $vmware_inventory{VM}{$vm_uuid}{SERVER} ) {
      $name_out = "$vmware_inventory{VM}{$vm_uuid}{SERVER}: $name_out";
    }

    my $cmd      = "";
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";

    if ( $item eq "custom" ) {
      $cmd .= " DEF:utiltot_mhz=\"$rrd\":CPU_usage:AVERAGE";
      $cmd .= " CDEF:utiltot_ghz=utiltot_mhz,1000,/";
      $cmd .= " CDEF:utiltot=utiltot_mhz,1000,/";
    }
    elsif ( $item eq "customvmmemactive" ) {
      $cmd .= " DEF:utiltot_mhz=\"$rrd\":Memory_active:AVERAGE";
      $cmd .= " CDEF:utiltot=utiltot_mhz,1048576,/";
    }
    elsif ( $item eq "customvmmemconsumed" ) {
      $cmd .= " DEF:utiltot_mhz=\"$rrd\":Memory_granted:AVERAGE";
      $cmd .= " CDEF:utiltot=utiltot_mhz,1048576,/";
    }
    $cmd .= " XPORT:utiltot:Utilization";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {
        if ( !test_rrdtool_xport_line( $row, "1" ) ) { next; }

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{$name_out} ) {
          $data{STATS}{$timestamp}{$name_out} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{$name_out} && !isdigit( $data{STATS}{$timestamp}{$name_out} ) ) {
          $data{STATS}{$timestamp}{$name_out} = $value1;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{$name_out} && isdigit( $lpar_idxs{$name_out} ) ) {
      $header_id = $lpar_idxs{$name_out};
    }
    $lpar_idxs{$name_out} = $header_id;

    $data{CSVHEADER}{$header_id} = $name_out;
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_esxi_cpu {
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $esxi = $rrd;
    $esxi =~ s/^$wrkdir\///;
    $esxi =~ s/\/.*$//;

    my $cmd      = "";
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:utiltot_mhz=\"$rrd\":CPU_usage:AVERAGE";
    $cmd .= " DEF:one_core_hz=\"$rrd\":host_hz:AVERAGE";
    $cmd .= " CDEF:cpuutiltot=utiltot_mhz,one_core_hz,/,1000000,*";
    $cmd .= " XPORT:cpuutiltot:Utilization_in_CPU_cores";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{$esxi} ) {
          $data{STATS}{$timestamp}{$esxi} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{$esxi} && !isdigit( $data{STATS}{$timestamp}{$esxi} ) ) {
          $data{STATS}{$timestamp}{$esxi} = $value1;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{$esxi} && isdigit( $lpar_idxs{$esxi} ) ) {
      $header_id = $lpar_idxs{$esxi};
    }
    $lpar_idxs{$esxi} = $header_id;

    $data{CSVHEADER}{$header_id} = $esxi;
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_pool_memalloc {
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $hmc       = $rrd;
    my $server    = $rrd;
    my $lpar_name = basename($rrd);

    $hmc =~ s/\/$lpar_name$//;
    $hmc = basename($hmc);

    $server =~ s/\/$lpar_name$//;
    $server =~ s/\/$hmc$//;
    $server = basename($server);

    $lpar_name =~ s/mem\.rrm$/CPU pool/;
    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $pool = $lpar_name;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:tot=\"$rrd\":conf_sys_mem:AVERAGE";
    $cmd .= " DEF:free=\"$rrd\":curr_avail_mem:AVERAGE";
    $cmd .= " CDEF:totg=tot,1024,/";
    $cmd .= " CDEF:freeg=free,1024,/";
    $cmd .= " CDEF:curg=totg,freeg,-";
    $cmd .= " XPORT:curg:memalloc";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{"$server - $pool"} ) {
          $data{STATS}{$timestamp}{"$server - $pool"} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$server - $pool"} && !isdigit( $data{STATS}{$timestamp}{"$server - $pool"} ) ) {
          $data{STATS}{$timestamp}{"$server - $pool"} = $value1;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{"$server - $pool"} && isdigit( $lpar_idxs{"$server - $pool"} ) ) {
      $header_id = $lpar_idxs{"$server - $pool"};
    }
    $lpar_idxs{"$server - $pool"} = $header_id;

    $data{CSVHEADER}{$header_id} = "$server - $pool";
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_pool_cpu {
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $hmc       = $rrd;
    my $server    = $rrd;
    my $lpar_name = basename($rrd);

    $hmc =~ s/\/$lpar_name$//;
    $hmc = basename($hmc);

    $server =~ s/\/$lpar_name$//;
    $server =~ s/\/$hmc$//;
    $server = basename($server);

    $lpar_name =~ s/\.rrm$//;
    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $pool = $lpar_name;
    if ( $lpar_name eq "pool" ) { $pool = "CPU pool"; }
    elsif ( $lpar_name =~ m/^SharedPool/ ) {
      if ( -f "$wrkdir/$server/$hmc/cpu-pools-mapping.txt" ) {
        my $pool_id = $lpar_name;
        $pool_id =~ s/SharedPool//g;
        open( FR, "< $wrkdir/$server/$hmc/cpu-pools-mapping.txt" ) || error( "Couldn't open file $wrkdir/$server/$hmc/cpu-pools-mapping.txt $!" . __FILE__ . ":" . __LINE__ ) && exit;
        foreach my $linep (<FR>) {
          chomp($linep);
          ( my $id, my $pool_name ) = split( /,/, $linep );
          if ( $id == $pool_id ) {
            $pool = "$pool_name";
            last;
          }
        }
        close(FR);
      }
    }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    if ( $lpar_name eq "pool" ) {
      $cmd .= " DEF:totcyc=\"$rrd\":total_pool_cycles:AVERAGE";
      $cmd .= " DEF:uticyc=\"$rrd\":utilized_pool_cyc:AVERAGE";
      $cmd .= " DEF:cpu=\"$rrd\":conf_proc_units:AVERAGE";
      $cmd .= " DEF:cpubor=\"$rrd\":bor_proc_units:AVERAGE";
      $cmd .= " CDEF:totcpu=cpu,cpubor,+";
      $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
      $cmd .= " CDEF:cpuutiltot=cpuutil,totcpu,*";
      $cmd .= " XPORT:cpuutiltot:\"Utilization in CPU cores\"";
    }
    elsif ( $lpar_name =~ m/^SharedPool/ ) {
      $cmd .= " DEF:max=\"$rrd\":max_pool_units:AVERAGE";
      $cmd .= " DEF:res=\"$rrd\":res_pool_units:AVERAGE";
      $cmd .= " DEF:totcyc=\"$rrd\":total_pool_cycles:AVERAGE";
      $cmd .= " DEF:uticyc=\"$rrd\":utilized_pool_cyc:AVERAGE";
      $cmd .= " CDEF:max1=max,res,-";
      $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
      $cmd .= " CDEF:cpuutiltot=cpuutil,max,*";
      $cmd .= " XPORT:cpuutiltot:\"Utilization in CPU cores\"";
    }

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{"$server - $pool"} ) {
          $data{STATS}{$timestamp}{"$server - $pool"} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$server - $pool"} && !isdigit( $data{STATS}{$timestamp}{"$server - $pool"} ) ) {
          $data{STATS}{$timestamp}{"$server - $pool"} = $value1;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{"$server - $pool"} && isdigit( $lpar_idxs{"$server - $pool"} ) ) {
      $header_id = $lpar_idxs{"$server - $pool"};
    }
    $lpar_idxs{"$server - $pool"} = $header_id;

    $data{CSVHEADER}{$header_id} = "$server - $pool";
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_lpar_san2 {
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $adapter_name = $rrd;
    my $lpar_name    = $rrd;
    $lpar_name =~ s/\/san-.+\.mmm$//;
    my $hmc    = $lpar_name;
    my $server = $lpar_name;
    $lpar_name    = basename($lpar_name);
    $adapter_name = basename($adapter_name);
    $adapter_name =~ s/\.mmm$//;
    $adapter_name =~ s/^lan-//;

    $hmc =~ s/\/$lpar_name$//;
    $hmc = basename($hmc);

    $server =~ s/\/$lpar_name$//;
    $server =~ s/\/$hmc$//;
    $server = basename($server);

    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $out_name = "$server - $lpar_name - $adapter_name";

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:rcb_nf=\"$rrd\":iops_in:AVERAGE";
    $cmd .= " DEF:trb_nf=\"$rrd\":iops_out:AVERAGE";
    $cmd .= " CDEF:rcb=rcb_nf,100000,GT,UNKN,rcb_nf,IF";
    $cmd .= " CDEF:trb=trb_nf,100000,GT,UNKN,trb_nf,IF";
    $cmd .= " CDEF:rcb-mil=rcb,1,/";
    $cmd .= " CDEF:trb-mil=trb,1,/";
    $cmd .= " XPORT:rcb-mil:rcb";
    $cmd .= " XPORT:trb-mil:trb";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
        }
        else {
          $value2 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{"$out_name Read IOPS"} ) {
          $data{STATS}{$timestamp}{"$out_name Read IOPS"} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$out_name Read IOPS"} && !isdigit( $data{STATS}{$timestamp}{"$out_name Read IOPS"} ) ) {
          $data{STATS}{$timestamp}{"$out_name Read IOPS"} = $value1;
        }
        if ( !exists $data{STATS}{$timestamp}{"$out_name Write IOPS"} ) {
          $data{STATS}{$timestamp}{"$out_name Write IOPS"} = $value2;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$out_name Write IOPS"} && !isdigit( $data{STATS}{$timestamp}{"$out_name Write IOPS"} ) ) {
          $data{STATS}{$timestamp}{"$out_name Write IOPS"} = $value2;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{"$out_name"} && isdigit( $lpar_idxs{"$out_name"} ) ) {
      $header_id = $lpar_idxs{"$out_name"};
    }
    $lpar_idxs{"$out_name"} = $header_id;

    $data{CSVHEADER}{$header_id} = "$out_name Read IOPS";
    $header_id++;
    $metric_idx++;
    $data{CSVHEADER}{$header_id} = "$out_name Write IOPS";
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_lpar_san1 {
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $adapter_name = $rrd;
    my $lpar_name    = $rrd;
    $lpar_name =~ s/\/san-.+\.mmm$//;
    my $hmc    = $lpar_name;
    my $server = $lpar_name;
    $lpar_name    = basename($lpar_name);
    $adapter_name = basename($adapter_name);
    $adapter_name =~ s/\.mmm$//;
    $adapter_name =~ s/^lan-//;

    $hmc =~ s/\/$lpar_name$//;
    $hmc = basename($hmc);

    $server =~ s/\/$lpar_name$//;
    $server =~ s/\/$hmc$//;
    $server = basename($server);

    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $out_name = "$server - $lpar_name - $adapter_name";

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:trb_nf=\"$rrd\":trans_bytes:AVERAGE";
    $cmd .= " DEF:rcb_nf=\"$rrd\":recv_bytes:AVERAGE";
    $cmd .= " CDEF:rcb=rcb_nf,1000000000,GT,UNKN,rcb_nf,IF";
    $cmd .= " CDEF:trb=trb_nf,1000000000,GT,UNKN,trb_nf,IF";
    $cmd .= " CDEF:rcb-mil=rcb,1000000,/";
    $cmd .= " CDEF:trb-mil=trb,1000000,/";
    $cmd .= " XPORT:rcb-mil:rcb";
    $cmd .= " XPORT:trb-mil:trb";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
        }
        else {
          $value2 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{"$out_name Read MB/sec"} ) {
          $data{STATS}{$timestamp}{"$out_name Read MB/sec"} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$out_name Read MB/sec"} && !isdigit( $data{STATS}{$timestamp}{"$out_name Read MB/sec"} ) ) {
          $data{STATS}{$timestamp}{"$out_name Read MB/sec"} = $value1;
        }
        if ( !exists $data{STATS}{$timestamp}{"$out_name Write MB/sec"} ) {
          $data{STATS}{$timestamp}{"$out_name Write MB/sec"} = $value2;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$out_name Write MB/sec"} && !isdigit( $data{STATS}{$timestamp}{"$out_name Write MB/sec"} ) ) {
          $data{STATS}{$timestamp}{"$out_name Write MB/sec"} = $value2;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{"$out_name"} && isdigit( $lpar_idxs{"$out_name"} ) ) {
      $header_id = $lpar_idxs{"$out_name"};
    }
    $lpar_idxs{"$out_name"} = $header_id;

    $data{CSVHEADER}{$header_id} = "$out_name Read MB/sec";
    $header_id++;
    $metric_idx++;
    $data{CSVHEADER}{$header_id} = "$out_name Write MB/sec";
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_lpar_lan {
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $adapter_name = $rrd;
    my $lpar_name    = $rrd;
    $lpar_name =~ s/\/lan-.+\.mmm$//;
    my $hmc    = $lpar_name;
    my $server = $lpar_name;
    $lpar_name    = basename($lpar_name);
    $adapter_name = basename($adapter_name);
    $adapter_name =~ s/\.mmm$//;
    $adapter_name =~ s/^lan-//;

    $hmc =~ s/\/$lpar_name$//;
    $hmc = basename($hmc);

    $server =~ s/\/$lpar_name$//;
    $server =~ s/\/$hmc$//;
    $server = basename($server);

    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $out_name = "$server - $lpar_name - $adapter_name";

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:rcb_nf=\"$rrd\":trans_bytes:AVERAGE";
    $cmd .= " DEF:trb_nf=\"$rrd\":recv_bytes:AVERAGE";
    $cmd .= " CDEF:rcb=rcb_nf,1000000000,GT,UNKN,rcb_nf,IF";
    $cmd .= " CDEF:trb=trb_nf,1000000000,GT,UNKN,trb_nf,IF";
    $cmd .= " CDEF:rcb-mil=rcb,1000000,/";
    $cmd .= " CDEF:trb-mil=trb,1000000,/";
    $cmd .= " XPORT:rcb-mil:rcb";
    $cmd .= " XPORT:trb-mil:trb";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
        }
        else {
          $value2 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{"$out_name Read MB/sec"} ) {
          $data{STATS}{$timestamp}{"$out_name Read MB/sec"} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$out_name Read MB/sec"} && !isdigit( $data{STATS}{$timestamp}{"$out_name Read MB/sec"} ) ) {
          $data{STATS}{$timestamp}{"$out_name Read MB/sec"} = $value1;
        }
        if ( !exists $data{STATS}{$timestamp}{"$out_name Write MB/sec"} ) {
          $data{STATS}{$timestamp}{"$out_name Write MB/sec"} = $value2;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$out_name Write MB/sec"} && !isdigit( $data{STATS}{$timestamp}{"$out_name Write MB/sec"} ) ) {
          $data{STATS}{$timestamp}{"$out_name Write MB/sec"} = $value2;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{"$out_name"} && isdigit( $lpar_idxs{"$out_name"} ) ) {
      $header_id = $lpar_idxs{"$out_name"};
    }
    $lpar_idxs{"$out_name"} = $header_id;

    $data{CSVHEADER}{$header_id} = "$out_name Read MB/sec";
    $header_id++;
    $metric_idx++;
    $data{CSVHEADER}{$header_id} = "$out_name Write MB/sec";
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_lpar_mem {
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $lpar_name = $rrd;
    $lpar_name =~ s/\/mem\.mmm$//;
    my $hmc    = $lpar_name;
    my $server = $lpar_name;
    $lpar_name = basename($lpar_name);

    $hmc =~ s/\/$lpar_name$//;
    $hmc = basename($hmc);

    $server =~ s/\/$lpar_name$//;
    $server =~ s/\/$hmc$//;
    $server = basename($server);

    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:cur=\"$rrd\":nuse:AVERAGE";
    $cmd .= " DEF:in_use_clnt=\"$rrd\":in_use_clnt:AVERAGE";
    $cmd .= " CDEF:cur_real=cur,in_use_clnt,-";
    $cmd .= " CDEF:tot=cur_real,1048576,/";
    $cmd .= " XPORT:tot:memalloc";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{"$server - $lpar_name"} ) {
          $data{STATS}{$timestamp}{"$server - $lpar_name"} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$server - $lpar_name"} && !isdigit( $data{STATS}{$timestamp}{"$server - $lpar_name"} ) ) {
          $data{STATS}{$timestamp}{"$server - $lpar_name"} = $value1;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{"$server - $lpar_name"} && isdigit( $lpar_idxs{"$server - $lpar_name"} ) ) {
      $header_id = $lpar_idxs{"$server - $lpar_name"};
    }
    $lpar_idxs{"$server - $lpar_name"} = $header_id;

    $data{CSVHEADER}{$header_id} = "$server - $lpar_name";
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_lpar_memalloc {
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $hmc       = $rrd;
    my $server    = $rrd;
    my $lpar_name = basename($rrd);

    $hmc =~ s/\/$lpar_name$//;
    $hmc = basename($hmc);

    $server =~ s/\/$lpar_name$//;
    $server =~ s/\/$hmc$//;
    $server = basename($server);

    $lpar_name =~ s/\.rsm$//;
    $lpar_name =~ s/\.rmm$//;
    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:cur=\"$rrd\":curr_mem:AVERAGE";
    $cmd .= " CDEF:tot=cur,1024,/";
    $cmd .= " XPORT:tot:memalloc";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{"$server - $lpar_name"} ) {
          $data{STATS}{$timestamp}{"$server - $lpar_name"} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$server - $lpar_name"} && !isdigit( $data{STATS}{$timestamp}{"$server - $lpar_name"} ) ) {
          $data{STATS}{$timestamp}{"$server - $lpar_name"} = $value1;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{"$server - $lpar_name"} && isdigit( $lpar_idxs{"$server - $lpar_name"} ) ) {
      $header_id = $lpar_idxs{"$server - $lpar_name"};
    }
    $lpar_idxs{"$server - $lpar_name"} = $header_id;

    $data{CSVHEADER}{$header_id} = "$server - $lpar_name";
  }
  $data{NAME} = "$name";

  return 1;
}

sub xport_custom_lpar_cpu {
  my $name  = shift;
  my $sunix = shift;
  my $eunix = shift;

  # max 10k peak in % is allowed (in fact it cann by higher than 1k now when 1 logical CPU == 0.1 entitlement
  my $cpu_max_filter = ( defined $ENV{CPU_MAX_FILTER} ) ? $ENV{CPU_MAX_FILTER} : 100;

  my $metric_idx = 0;
  my %lpar_idxs;
  foreach my $rrd ( keys %custom_inventory ) {
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    my $hmc       = $rrd;
    my $server    = $rrd;
    my $lpar_name = basename($rrd);

    $hmc =~ s/\/$lpar_name$//;
    $hmc = basename($hmc);

    $server =~ s/\/$lpar_name$//;
    $server =~ s/\/$hmc$//;
    $server = basename($server);

    $lpar_name =~ s/\.rrm$//;
    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:cur=\"$rrd\":curr_proc_units:AVERAGE";
    $cmd .= " DEF:ent=\"$rrd\":entitled_cycles:AVERAGE";
    $cmd .= " DEF:cap=\"$rrd\":capped_cycles:AVERAGE";
    $cmd .= " DEF:uncap=\"$rrd\":uncapped_cycles:AVERAGE";
    $cmd .= " CDEF:tot=cap,uncap,+";
    $cmd .= " CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF";
    $cmd .= " CDEF:utiltot=util,cur,*";
    $cmd .= " CDEF:utiltot_res=utiltot,100,*,0.5,+,FLOOR,100,/";
    $cmd .= " XPORT:utiltot_res:Utilization_in_CPU_cores";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }

        if ( !exists $data{STATS}{$timestamp}{"$server - $lpar_name"} ) {
          $data{STATS}{$timestamp}{"$server - $lpar_name"} = $value1;
        }
        elsif ( exists $data{STATS}{$timestamp}{"$server - $lpar_name"} && !isdigit( $data{STATS}{$timestamp}{"$server - $lpar_name"} ) ) {
          $data{STATS}{$timestamp}{"$server - $lpar_name"} = $value1;
        }
      }
    }

    # set csv header
    $metric_idx++;
    my $header_id = $metric_idx;
    if ( exists $lpar_idxs{"$server - $lpar_name"} && isdigit( $lpar_idxs{"$server - $lpar_name"} ) ) {
      $header_id = $lpar_idxs{"$server - $lpar_name"};
    }
    $lpar_idxs{"$server - $lpar_name"} = $header_id;

    $data{CSVHEADER}{$header_id} = "$server - $lpar_name";
  }
  $data{NAME} = "$name";

  return 1;
}

sub get_custom_inventory {
  my $name = shift;
  my $item = shift;

  $name = urldecodel("$name");

  my $cmd_file = "";

  if    ( $item eq "custom" && -f "$tmpdir/custom-group-$name-y.cmd" )               { $cmd_file = "$tmpdir/custom-group-$name-y.cmd"; }
  elsif ( $item eq "custommem" && -f "$tmpdir/custom-group-mem-$name-y.cmd" )        { $cmd_file = "$tmpdir/custom-group-mem-$name-y.cmd"; }
  elsif ( $item eq "customosmem" && -f "$tmpdir/custom-group-mem-os-$name-y.cmd" )   { $cmd_file = "$tmpdir/custom-group-mem-os-$name-y.cmd"; }
  elsif ( $item eq "customoslan" && -f "$tmpdir/custom-group-lan-os-$name-y.cmd" )   { $cmd_file = "$tmpdir/custom-group-lan-os-$name-y.cmd"; }
  elsif ( $item eq "customossan1" && -f "$tmpdir/custom-group-san1-os-$name-y.cmd" ) { $cmd_file = "$tmpdir/custom-group-san1-os-$name-y.cmd"; }
  elsif ( $item eq "customossan2" && -f "$tmpdir/custom-group-san2-os-$name-y.cmd" ) { $cmd_file = "$tmpdir/custom-group-san2-os-$name-y.cmd"; }
  elsif ( $item eq "custom_esxi_cpu" && -f "$tmpdir/custom-group-cpu-$name-y.cmd" )  { $cmd_file = "$tmpdir/custom-group-cpu-$name-y.cmd"; }
  elsif ( $item =~ m/^customvmmem/ && -f "$tmpdir/custom-group-vmmem-$name-y.cmd" )  { $cmd_file = "$tmpdir/custom-group-vmmem-$name-y.cmd"; }
  elsif ( $item eq "customdisk" && -f "$tmpdir/custom-group-disk-$name-y.cmd" )      { $cmd_file = "$tmpdir/custom-group-disk-$name-y.cmd"; }
  elsif ( $item eq "customnet" && -f "$tmpdir/custom-group-net-$name-y.cmd" )        { $cmd_file = "$tmpdir/custom-group-net-$name-y.cmd"; }

  if ( -f $cmd_file ) {
    open( IN, "< $cmd_file" ) || error( "Couldn't open file $cmd_file $!" . __FILE__ . ":" . __LINE__ ) && exit;
    my @lines = <IN>;
    close(IN);
    chomp @lines;

    my $delimeter = "XORDELIMETERXOR";

    foreach my $line (@lines) {

      #$line =~ s/^.* DEF:/ DEF:/;
      $line =~ s/\s+DEF:/$delimeter DEF:/g;
      $line =~ s/\s+CDEF:/$delimeter CDEF:/g;
      $line =~ s/\s+VDEF:/$delimeter VDEF:/g;
      $line =~ s/\s+PRINT:/$delimeter PRINT:/g;
      $line =~ s/\s+GPRINT:/$delimeter GPRINT:/g;
      $line =~ s/\s+LINE:/$delimeter LINE:/g;
      $line =~ s/\s+AREA:/$delimeter AREA:/g;
      $line =~ s/\s+STACK:/$delimeter STACK:/g;
      $line =~ s/\s+COMMENT:/$delimeter COMMENT:/g;
      $line =~ s/\s+HRULE:/$delimeter HRULE:/g;

      my @new_lines = split( /$delimeter/, $line );

      #print STDERR "########## $line\n";
      #print STDERR join("\n", @new_lines);

      foreach (@new_lines) {
        $_ =~ s/^\s+//g;
        $_ =~ s/\s+$//g;

        if ( $_ =~ m/^DEF:/ ) {
          $_ =~ s/\\:/===double-col===/g;
          my ( undef, $rrd, undef, undef ) = split( /:/, $_ );
          $rrd =~ s/^.*="//;
          $rrd =~ s/"$//;
          $rrd =~ s/===double-col===/:/g;

          $custom_inventory{$rrd} = $rrd;
        }
      }
    }
  }
  else {
    error( "Couldn't load custom group inventory. Custom-group=\"$name\" cmd-file=\"$cmd_file\" $!" . __FILE__ . ":" . __LINE__ ) && exit;
  }

  return 1;
}

sub xport_power_mem_aggreg {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  # find lpars
  opendir( DIR, "$wrkdir/$server/$hmc" ) || error( "can't opendir $wrkdir/$server/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && exit;
  my @lpars_dir = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  my @rrd_files = grep {/\.rrm$/} @lpars_dir;
  chomp @rrd_files;

  my $metric_idx = 1;
  foreach my $file_name (@rrd_files) {
    my $lpar_name = $file_name;
    $lpar_name =~ s/\.rrm$//;

    # Exclude pools and memory
    if ( $lpar_name =~ m/^mem-pool$/ || $lpar_name =~ m/^pool$/ || $lpar_name =~ m/^mem$/ || $lpar_name =~ m/^SharedPool[0-9]$/ || $lpar_name =~ m/^SharedPool[1-9][0-9]$/ || $lpar_name =~ m/^cod$/ ) {
      next;
    }

    # set the right rrd file (.rsm if AMS is not used, .rmm if AMS is used)
    $file_name =~ s/\.rrm$/\.rsm/;
    if ( !-f "$wrkdir/$server/$hmc/$file_name" ) { $file_name =~ s/\.rsm$/\.rmm/; }

    $file_name =~ s/\//&&1/g;
    my $rrd = "$wrkdir/$server/$hmc/$file_name";
    $rrd = rrd_from_active_hmc( "$server", "$file_name", "$rrd" );
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $rrd_upd_time = ( stat("$rrd") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:cur=\"$rrd\":curr_mem:AVERAGE";
    $cmd .= " CDEF:curg=cur,1024,/";
    $cmd .= " XPORT:curg:\"$lpar_name\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        $data{STATS}{$timestamp}{"$lpar_name"} = $value1;
      }
    }

    # set csv header
    $data{CSVHEADER}{$metric_idx} = "$lpar_name";
    $metric_idx++;
  }
  $data{NAME} = "$server";

  return 1;
}

sub xport_power_mem {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  my $rrd = "$wrkdir/$server/$hmc/mem.rrm";
  $rrd = rrd_from_active_hmc( "$server", "mem.rrm", "$rrd" );
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:free=\"$rrd\":curr_avail_mem:AVERAGE";
  $cmd .= " DEF:fw=\"$rrd\":sys_firmware_mem:AVERAGE";
  $cmd .= " DEF:tot=\"$rrd\":conf_sys_mem:AVERAGE";
  $cmd .= " CDEF:freeg=free,1024,/";
  $cmd .= " CDEF:fwg=fw,1024,/";
  $cmd .= " CDEF:totg=tot,1024,/";
  $cmd .= " CDEF:used=totg,freeg,-";
  $cmd .= " CDEF:used1=used,fwg,-";
  $cmd .= " XPORT:fwg:\"Firmware memory\"";
  $cmd .= " XPORT:used:\"Used memory\"";
  $cmd .= " XPORT:freeg:\"Free memory\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value3    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      $data{STATS}{$timestamp}{'Firmware memory'} = $value1;
      $data{STATS}{$timestamp}{'Used memory'}     = $value2;
      $data{STATS}{$timestamp}{'Free memory'}     = $value3;
    }
  }

  # set csv header
  $data{NAME}         = "$server";
  $data{CSVHEADER}{1} = "Firmware memory";
  $data{CSVHEADER}{2} = "Used memory";
  $data{CSVHEADER}{3} = "Free memory";

  return 1;
}

sub xport_pool_lparagg {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  # find lpars
  opendir( DIR, "$wrkdir/$server/$hmc" ) || error( "can't opendir $wrkdir/$server/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && exit;
  my @lpars_dir = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  my @rrd_files = grep {/\.rrm$/} @lpars_dir;
  chomp @rrd_files;

  my $metric_idx = 1;
  foreach my $file_name (@rrd_files) {
    my $rrd_upd_time = ( stat("$wrkdir/$server/$hmc/$file_name") )[9];
    if ( $rrd_upd_time < $sunix ) { next; }

    # Exclude pools and memory
    my $lpar_name = $file_name;
    $lpar_name =~ s/\.rrm$//;
    if ( $lpar_name =~ m/^mem-pool$/ || $lpar_name =~ m/^pool$/ || $lpar_name =~ m/^mem$/ || $lpar_name =~ m/^SharedPool[0-9]$/ || $lpar_name =~ m/^SharedPool[1-9][0-9]$/ || $lpar_name =~ m/^cod$/ ) {
      next;
    }

    $file_name =~ s/\//&&1/g;
    my $rrd = "$wrkdir/$server/$hmc/$file_name";
    $rrd = rrd_from_active_hmc( "$server", "$file_name", "$rrd" );
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }

    $lpar_name =~ s/:/\\:/g;
    $lpar_name =~ s/&&1/\//g;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:cap=\"$rrd\":capped_cycles:AVERAGE";
    $cmd .= " DEF:uncap=\"$rrd\":uncapped_cycles:AVERAGE";
    $cmd .= " DEF:ent=\"$rrd\":entitled_cycles:AVERAGE";
    $cmd .= " DEF:cur=\"$rrd\":curr_proc_units:AVERAGE";
    $cmd .= " CDEF:tot=cap,uncap,+";
    $cmd .= " CDEF:util=tot,ent,/";
    $cmd .= " CDEF:utiltotu=util,cur,*";
    $cmd .= " CDEF:utiltot=utiltotu,UN,0,utiltotu,IF";
    $cmd .= " XPORT:utiltot:\"$lpar_name\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $value1 ) = split( "</t><v>", $row );

        $timestamp =~ s/^<row><t>//;
        $value1    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        $data{STATS}{$timestamp}{"$lpar_name"} = $value1;
      }
    }

    # set csv header
    $data{CSVHEADER}{$metric_idx} = "$lpar_name";
    $metric_idx++;
  }
  $data{NAME} = "$server";

  return 1;
}

sub xport_shpool_cpu_max {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  $lpar =~ s/\//&&1/g;
  my $rrd = "$wrkdir/$server/$hmc/$lpar.rrm";
  $rrd = rrd_from_active_hmc( "$server", "$lpar.rrm", "$rrd" );
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $rrd_max = "$wrkdir/$server/$hmc/$lpar.xrm";
  $rrd_max = rrd_from_active_hmc( "$server", "$lpar.xrm", "$rrd_max" );
  if ( !-f $rrd_max ) {
    error( "RRD file does not exist! \"$rrd_max\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  $lpar =~ s/&&1/\//g;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd     =~ s/:/\\:/g;
  $rrd_max =~ s/:/\\:/g;

  #$STEP = 300;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:max=\"$rrd\":max_pool_units:AVERAGE";
  $cmd .= " DEF:res=\"$rrd\":res_pool_units:AVERAGE";
  $cmd .= " DEF:totcyc=\"$rrd\":total_pool_cycles:AVERAGE";
  $cmd .= " DEF:uticyc=\"$rrd\":utilized_pool_cyc:AVERAGE";
  $cmd .= " CDEF:max1=max,res,-";
  $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
  $cmd .= " CDEF:cpuutiltot=cpuutil,max,*";
  $cmd .= " CDEF:utilisa=cpuutil,100,*";
  $cmd .= " XPORT:res:\"Reserved CPU cores\"";
  $cmd .= " XPORT:max1:\"Max CPU cores\"";
  $cmd .= " XPORT:cpuutiltot:\"Utilization in CPU cores\"";

  $cmd .= " DEF:max_max=\"$rrd_max\":max_pool_units:MAX";
  $cmd .= " DEF:res_max=\"$rrd_max\":res_pool_units:MAX";
  $cmd .= " DEF:totcyc_max=\"$rrd_max\":total_pool_cycles:MAX";
  $cmd .= " DEF:uticyc_max=\"$rrd_max\":utilized_pool_cyc:MAX";
  $cmd .= " CDEF:max1_max=max_max,res_max,-";
  $cmd .= " CDEF:cpuutil_max=uticyc_max,totcyc_max,GT,UNKN,uticyc_max,totcyc_max,/,IF";
  $cmd .= " CDEF:cpuutiltot_max=cpuutil_max,max_max,*";
  $cmd .= " XPORT:cpuutiltot_max:\"Maximum peaks in CPU cores\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value4    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      if ( isdigit($value4) ) {
        $value4 = sprintf '%.2f', $value4;
      }
      else {
        $value4 = '';
      }
      $data{STATS}{$timestamp}{'Reserved CPU cores'}         = $value1;
      $data{STATS}{$timestamp}{'Max CPU cores'}              = $value2;
      $data{STATS}{$timestamp}{'Utilization in CPU cores'}   = $value3;
      $data{STATS}{$timestamp}{'Maximum peaks in CPU cores'} = $value4;
    }
  }

  # set csv header
  $data{NAME}         = "$lpar";
  $data{CSVHEADER}{1} = "Reserved CPU cores";
  $data{CSVHEADER}{2} = "Max CPU cores";
  $data{CSVHEADER}{3} = "Utilization in CPU cores";
  $data{CSVHEADER}{4} = "Maximum peaks in CPU cores";

  if ( -f "$wrkdir/$server/$hmc/cpu-pools-mapping.txt" ) {
    my $pool_id = $lpar;
    $pool_id =~ s/SharedPool//g;
    open( FR, "< $wrkdir/$server/$hmc/cpu-pools-mapping.txt" ) || error( "Couldn't open file $wrkdir/$server/$hmc/cpu-pools-mapping.txt $!" . __FILE__ . ":" . __LINE__ ) && exit;
    foreach my $linep (<FR>) {
      chomp($linep);
      ( my $id, my $pool_name ) = split( /,/, $linep );
      if ( $id == $pool_id ) {
        $data{NAME} = "$pool_name";
        last;
      }
    }
    close(FR);
  }

  return 1;
}

sub xport_shpool_cpu {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  $lpar =~ s/\//&&1/g;
  my $rrd = "$wrkdir/$server/$hmc/$lpar.rrm";
  $rrd = rrd_from_active_hmc( "$server", "$lpar.rrm", "$rrd" );
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  $lpar =~ s/&&1/\//g;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:max=\"$rrd\":max_pool_units:AVERAGE";
  $cmd .= " DEF:res=\"$rrd\":res_pool_units:AVERAGE";
  $cmd .= " DEF:totcyc=\"$rrd\":total_pool_cycles:AVERAGE";
  $cmd .= " DEF:uticyc=\"$rrd\":utilized_pool_cyc:AVERAGE";
  $cmd .= " CDEF:max1=max,res,-";
  $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
  $cmd .= " CDEF:cpuutiltot=cpuutil,max,*";
  $cmd .= " CDEF:utilisa=cpuutil,100,*";
  $cmd .= " XPORT:res:\"Reserved CPU cores\"";
  $cmd .= " XPORT:max1:\"Max CPU cores\"";
  $cmd .= " XPORT:cpuutiltot:\"Utilization in CPU cores\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value3    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      $data{STATS}{$timestamp}{'Reserved CPU cores'}       = $value1;
      $data{STATS}{$timestamp}{'Max CPU cores'}            = $value2;
      $data{STATS}{$timestamp}{'Utilization in CPU cores'} = $value3;
    }
  }

  # set csv header
  $data{NAME}         = "$lpar";
  $data{CSVHEADER}{1} = "Reserved CPU cores";
  $data{CSVHEADER}{2} = "Max CPU cores";
  $data{CSVHEADER}{3} = "Utilization in CPU cores";

  if ( -f "$wrkdir/$server/$hmc/cpu-pools-mapping.txt" ) {
    my $pool_id = $lpar;
    $pool_id =~ s/SharedPool//g;
    open( FR, "< $wrkdir/$server/$hmc/cpu-pools-mapping.txt" ) || error( "Couldn't open file $wrkdir/$server/$hmc/cpu-pools-mapping.txt $!" . __FILE__ . ":" . __LINE__ ) && exit;
    foreach my $linep (<FR>) {
      chomp($linep);
      ( my $id, my $pool_name ) = split( /,/, $linep );
      if ( $id == $pool_id ) {
        $data{NAME} = "$pool_name";
        last;
      }
    }
    close(FR);
  }

  return 1;
}

sub xport_pool_cpu_max {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  my $rrd = "$wrkdir/$server/$hmc/pool.rrm";
  $rrd = rrd_from_active_hmc( "$server", "pool.rrm", "$rrd" );
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $rrd_max = "$wrkdir/$server/$hmc/pool.xrm";
  $rrd_max = rrd_from_active_hmc( "$server", "pool.xrm", "$rrd_max" );
  if ( !-f $rrd_max ) {
    error( "RRD file does not exist! \"$rrd_max\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd     =~ s/:/\\:/g;
  $rrd_max =~ s/:/\\:/g;

  #$STEP = 300;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:totcyc=\"$rrd\":total_pool_cycles:AVERAGE";
  $cmd .= " DEF:uticyc=\"$rrd\":utilized_pool_cyc:AVERAGE";
  $cmd .= " DEF:cpu=\"$rrd\":conf_proc_units:AVERAGE";
  $cmd .= " DEF:cpubor=\"$rrd\":bor_proc_units:AVERAGE";
  $cmd .= " CDEF:totcpu=cpu,cpubor,+";
  $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
  $cmd .= " CDEF:cpuutiltot=cpuutil,totcpu,*";
  $cmd .= " CDEF:utilisa=cpuutil,100,*";
  $cmd .= " XPORT:cpu:\"Configured CPU cores\"";
  $cmd .= " XPORT:cpubor:\"Not assigned CPU cores\"";
  $cmd .= " XPORT:cpuutiltot:\"Utilization in CPU cores\"";

  $cmd .= " DEF:totcyc_max=\"$rrd_max\":total_pool_cycles:MAX";
  $cmd .= " DEF:uticyc_max=\"$rrd_max\":utilized_pool_cyc:MAX";
  $cmd .= " DEF:cpu_max=\"$rrd_max\":conf_proc_units:MAX";
  $cmd .= " DEF:cpubor_max=\"$rrd_max\":bor_proc_units:MAX";
  $cmd .= " CDEF:totcpu_max=cpu_max,cpubor_max,+";
  $cmd .= " CDEF:cpuutil_max=uticyc_max,totcyc_max,GT,UNKN,uticyc_max,totcyc_max,/,IF";
  $cmd .= " CDEF:cpuutiltot_max=cpuutil_max,totcpu_max,*";
  $cmd .= " XPORT:cpuutiltot_max:\"Maximum peaks in CPU cores\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value4    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      if ( isdigit($value4) ) {
        $value4 = sprintf '%.2f', $value4;
      }
      else {
        $value4 = '';
      }
      $data{STATS}{$timestamp}{'Configured CPU cores'}       = $value1;
      $data{STATS}{$timestamp}{'Not assigned CPU cores'}     = $value2;
      $data{STATS}{$timestamp}{'Utilization in CPU cores'}   = $value3;
      $data{STATS}{$timestamp}{'Maximum peaks in CPU cores'} = $value4;
    }
  }

  # set csv header
  $data{NAME}         = "CPU pool";
  $data{CSVHEADER}{1} = "Configured CPU cores";
  $data{CSVHEADER}{2} = "Not assigned CPU cores";
  $data{CSVHEADER}{3} = "Utilization in CPU cores";
  $data{CSVHEADER}{4} = "Maximum peaks in CPU cores";

  return 1;
}

sub xport_pool_cpu {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  my $rrd = "$wrkdir/$server/$hmc/pool.rrm";
  $rrd = rrd_from_active_hmc( "$server", "pool.rrm", "$rrd" );
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:totcyc=\"$rrd\":total_pool_cycles:AVERAGE";
  $cmd .= " DEF:uticyc=\"$rrd\":utilized_pool_cyc:AVERAGE";
  $cmd .= " DEF:cpu=\"$rrd\":conf_proc_units:AVERAGE";
  $cmd .= " DEF:cpubor=\"$rrd\":bor_proc_units:AVERAGE";
  $cmd .= " CDEF:totcpu=cpu,cpubor,+";
  $cmd .= " CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF";
  $cmd .= " CDEF:cpuutiltot=cpuutil,totcpu,*";
  $cmd .= " CDEF:utilisa=cpuutil,100,*";
  $cmd .= " XPORT:cpu:\"Configured CPU cores\"";
  $cmd .= " XPORT:cpubor:\"Not assigned CPU cores\"";
  $cmd .= " XPORT:cpuutiltot:\"Utilization in CPU cores\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value3    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      $data{STATS}{$timestamp}{'Configured CPU cores'}     = $value1;
      $data{STATS}{$timestamp}{'Not assigned CPU cores'}   = $value2;
      $data{STATS}{$timestamp}{'Utilization in CPU cores'} = $value3;
    }
  }

  # set csv header
  $data{NAME}         = "CPU pool";
  $data{CSVHEADER}{1} = "Configured CPU cores";
  $data{CSVHEADER}{2} = "Not assigned CPU cores";
  $data{CSVHEADER}{3} = "Utilization in CPU cores";

  return 1;
}

sub xport_lpar_sea {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  # find adapters
  opendir( DIR, "$wrkdir/$server/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$server/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && exit;
  my @lpar_os_agent_dir = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  my @rrd_files = grep {/^sea-ent.*\.mmm$/} @lpar_os_agent_dir;
  chomp @rrd_files;

  my $metric_idx = 1;
  foreach my $file_name (@rrd_files) {
    my $adapter_name = $file_name;
    $adapter_name =~ s/^sea-//;
    $adapter_name =~ s/\.mmm$//;

    $lpar =~ s/\//&&1/g;
    my $rrd = "$wrkdir/$server/$hmc/$lpar/$file_name";
    $rrd = rrd_from_active_hmc( "$server", "$lpar/$file_name", "$rrd" );
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    $lpar =~ s/&&1/\//g;

    my $divider       = 1073741824;
    my $count_avg_day = 1;
    my $minus_one     = -1;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:received_bytes=\"$rrd\":recv_bytes:AVERAGE";
    $cmd .= " DEF:transfers_bytes=\"$rrd\":trans_bytes:AVERAGE";
    $cmd .= " DEF:received_packets=\"$rrd\":recv_packets:AVERAGE";
    $cmd .= " DEF:transfers_packets=\"$rrd\":trans_packets:AVERAGE";
    $cmd .= " XPORT:received_bytes:\"REC bytes\"";
    $cmd .= " XPORT:transfers_bytes:\"TRANS bytes\"";
    $cmd .= " XPORT:received_packets:\"REC packets\"";
    $cmd .= " XPORT:transfers_packets:\"TRANS packets\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value4    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
        }
        else {
          $value2 = '';
        }
        if ( isdigit($value3) ) {
          $value3 = sprintf '%.2f', $value3;
        }
        else {
          $value3 = '';
        }
        if ( isdigit($value4) ) {
          $value4 = sprintf '%.2f', $value4;
        }
        else {
          $value4 = '';
        }
        $data{STATS}{$timestamp}{"$adapter_name - REC bytes"}     = $value1;
        $data{STATS}{$timestamp}{"$adapter_name - TRANS bytes"}   = $value2;
        $data{STATS}{$timestamp}{"$adapter_name - REC packets"}   = $value3;
        $data{STATS}{$timestamp}{"$adapter_name - TRANS packets"} = $value4;
      }
    }

    # set csv header
    $data{NAME} = "$lpar";
    $metric_idx++;
    $data{CSVHEADER}{$metric_idx} = "$adapter_name - REC bytes";
    $metric_idx++;
    $data{CSVHEADER}{$metric_idx} = "$adapter_name - TRANS bytes";
    $metric_idx++;
    $data{CSVHEADER}{$metric_idx} = "$adapter_name - REC packets";
    $metric_idx++;
    $data{CSVHEADER}{$metric_idx} = "$adapter_name - TRANS packets";
  }

  return 1;
}

sub xport_lpar_san_resp {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  # find adapters
  opendir( DIR, "$wrkdir/$server/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$server/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && exit;
  my @lpar_os_agent_dir = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  my @rrd_files = grep {/^san_resp-.*\.mmm$/} @lpar_os_agent_dir;
  chomp @rrd_files;

  my $metric_idx = 1;
  foreach my $file_name (@rrd_files) {
    my $adapter_name = $file_name;
    $adapter_name =~ s/^san_resp-//;
    $adapter_name =~ s/\.mmm$//;

    $lpar =~ s/\//&&1/g;
    my $rrd = "$wrkdir/$server/$hmc/$lpar/$file_name";
    $rrd = rrd_from_active_hmc( "$server", "$lpar/$file_name", "$rrd" );
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    $lpar =~ s/&&1/\//g;

    my $divider       = 1073741824;
    my $count_avg_day = 1;
    my $minus_one     = -1;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:read=\"$rrd\":resp_t_r:AVERAGE";
    $cmd .= " DEF:write=\"$rrd\":resp_t_w:AVERAGE";
    $cmd .= " CDEF:read_res=read,100,*,0.5,+,FLOOR,100,/";
    $cmd .= " CDEF:write_res=write,100,*,0.5,+,FLOOR,100,/";
    $cmd .= " XPORT:read_res:\"READ in ms\"";
    $cmd .= " XPORT:write_res:\"WRITE in ms\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.0f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.0f', $value2;
        }
        else {
          $value2 = '';
        }
        $data{STATS}{$timestamp}{"$adapter_name - READ (ms/sec)"}  = $value1;
        $data{STATS}{$timestamp}{"$adapter_name - Write (ms/sec)"} = $value2;
      }
    }

    # set csv header
    $data{NAME} = "$lpar";
    $metric_idx++;
    $data{CSVHEADER}{$metric_idx} = "$adapter_name - READ (ms/sec)";
    $metric_idx++;
    $data{CSVHEADER}{$metric_idx} = "$adapter_name - WRITE (ms/sec)";
  }

  return 1;
}

sub xport_lpar_san {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $item   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  # find adapters
  opendir( DIR, "$wrkdir/$server/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$server/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && exit;
  my @lpar_os_agent_dir = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  my @rrd_files = grep {/^san-.*\.mmm$/} @lpar_os_agent_dir;
  chomp @rrd_files;

  my $metric_idx = 1;
  foreach my $file_name (@rrd_files) {
    my $adapter_name = $file_name;
    $adapter_name =~ s/^san-//;
    $adapter_name =~ s/\.mmm$//;

    $lpar =~ s/\//&&1/g;
    my $rrd = "$wrkdir/$server/$hmc/$lpar/$file_name";
    $rrd = rrd_from_active_hmc( "$server", "$lpar/$file_name", "$rrd" );
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    $lpar =~ s/&&1/\//g;

    my $ds_name_os1 = "";
    my $ds_name_os2 = "";
    my $name_os1    = "";
    my $name_os2    = "";
    if ( $item eq "san1" ) {
      $ds_name_os1 = "recv_bytes";
      $ds_name_os2 = "trans_bytes";
      $name_os1    = "Recv bytes";
      $name_os2    = "Trans bytes";
    }
    if ( $item eq "san2" ) {
      $ds_name_os1 = "iops_in";
      $ds_name_os2 = "iops_out";
      $name_os1    = "IOPS in";
      $name_os2    = "IOPS out";
    }

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:value_os1=\"$rrd\":$ds_name_os1:AVERAGE";
    $cmd .= " DEF:value_os2=\"$rrd\":$ds_name_os2:AVERAGE";
    $cmd .= " CDEF:value_os1_res=value_os1,1,*,0.5,+,FLOOR,1,/";
    $cmd .= " CDEF:value_os2_res=value_os2,1,*,0.5,+,FLOOR,1,/";
    $cmd .= " XPORT:value_os1_res:\"$name_os1\"";
    $cmd .= " XPORT:value_os2_res:\"$name_os2\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.0f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.0f', $value2;
        }
        else {
          $value2 = '';
        }
        if ( $item eq "san1" ) {
          $data{STATS}{$timestamp}{"$adapter_name - REC bytes (B/sec)"}   = $value1;
          $data{STATS}{$timestamp}{"$adapter_name - TRANS bytes (B/sec)"} = $value2;
        }
        if ( $item eq "san2" ) {
          $data{STATS}{$timestamp}{"$adapter_name - IOPS in"}  = $value1;
          $data{STATS}{$timestamp}{"$adapter_name - IOPS out"} = $value2;
        }
      }
    }

    # set csv header
    $data{NAME} = "$lpar";
    $metric_idx++;
    if ( $item eq "san1" ) {
      $data{CSVHEADER}{$metric_idx} = "$adapter_name - REC bytes (B/sec)";
    }
    elsif ( $item eq "san2" ) {
      $data{CSVHEADER}{$metric_idx} = "$adapter_name - IOPS in";
    }
    $metric_idx++;
    if ( $item eq "san1" ) {
      $data{CSVHEADER}{$metric_idx} = "$adapter_name - TRANS bytes (B/sec)";
    }
    elsif ( $item eq "san2" ) {
      $data{CSVHEADER}{$metric_idx} = "$adapter_name - IOPS out";
    }
  }

  return 1;
}

sub xport_lpar_lan {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  # find adapters
  opendir( DIR, "$wrkdir/$server/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$server/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && exit;
  my @lpar_os_agent_dir = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  my @rrd_files = grep {/^lan-.*\.mmm$/} @lpar_os_agent_dir;
  chomp @rrd_files;

  my $metric_idx = 1;
  foreach my $file_name (@rrd_files) {
    my $adapter_name = $file_name;
    $adapter_name =~ s/^lan-//;
    $adapter_name =~ s/\.mmm$//;

    $lpar =~ s/\//&&1/g;
    my $rrd = "$wrkdir/$server/$hmc/$lpar/$file_name";
    $rrd = rrd_from_active_hmc( "$server", "$lpar/$file_name", "$rrd" );
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      next;
    }
    $lpar =~ s/&&1/\//g;

    my $divider       = 1073741824;
    my $count_avg_day = 1;
    my $minus_one     = -1;

    my $cmd = "";

    #my $max_rows = 170000;
    my $max_rows = 17000000000;
    my $xport    = "xport";
    $rrd =~ s/:/\\:/g;

    $cmd .= "$xport";
    if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

      # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
      $cmd .= " --showtime";
    }
    $cmd .= " --start \\\"$sunix\\\"";
    $cmd .= " --end \\\"$eunix\\\"";
    $cmd .= " --step \\\"$STEP\\\"";
    $cmd .= " --maxrows \\\"$max_rows\\\"";
    $cmd .= " DEF:received_bytes=\"$rrd\":recv_bytes:AVERAGE";
    $cmd .= " DEF:transfers_bytes=\"$rrd\":trans_bytes:AVERAGE";
    $cmd .= " CDEF:recv=received_bytes";
    $cmd .= " CDEF:trans=transfers_bytes";
    $cmd .= " CDEF:recv_s=recv,86400,*";
    $cmd .= " CDEF:recv_smb=recv_s,$divider,/";
    $cmd .= " CDEF:recv_smb_n=recv_smb,$count_avg_day,*";
    $cmd .= " CDEF:trans_s=trans,86400,*";
    $cmd .= " CDEF:trans_smb=trans_s,$divider,/";
    $cmd .= " CDEF:trans_smb_n=trans_smb,$count_avg_day,*";
    $cmd .= " CDEF:recv_neg=recv_s,$minus_one,*";
    $cmd .= " CDEF:received_bytes_res=received_bytes,1,*,0.5,+,FLOOR,1,/";
    $cmd .= " CDEF:transfers_bytes_res=transfers_bytes,1,*,0.5,+,FLOOR,1,/";
    $cmd .= " XPORT:received_bytes_res:\"REC_bytes\"";
    $cmd .= " XPORT:transfers_bytes_res:\"TRANS_bytes\"";

    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1,    $value2 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value2    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
        }
        else {
          $value2 = '';
        }
        $data{STATS}{$timestamp}{"$adapter_name - REC bytes (B/sec)"}   = $value1;
        $data{STATS}{$timestamp}{"$adapter_name - TRANS bytes (B/sec)"} = $value2;
      }
    }

    # set csv header
    $data{NAME} = "$lpar";
    $metric_idx++;
    $data{CSVHEADER}{$metric_idx} = "$adapter_name - REC bytes (B/sec)";
    $metric_idx++;
    $data{CSVHEADER}{$metric_idx} = "$adapter_name - TRANS bytes (B/sec)";
  }

  return 1;
}

sub xport_lpar_pg2 {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  $lpar =~ s/\//&&1/g;
  my $rrd = "$wrkdir/$server/$hmc/$lpar/pgs.mmm";
  $rrd = rrd_from_active_hmc( "$server", "$lpar/pgs.mmm", "$rrd" );
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  $lpar =~ s/&&1/\//g;

  my $filter = 100000000;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:paging=\"$rrd\":paging_space:AVERAGE";
  $cmd .= " DEF:percent_a=\"$rrd\":percent:AVERAGE";
  $cmd .= " XPORT:paging:Paging_space_in_MB";
  $cmd .= " XPORT:percent_a:percent";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Paging space (MB)'} = $value1;
      $data{STATS}{$timestamp}{'Paging space (%)'}  = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$lpar";
  $data{CSVHEADER}{1} = "Paging space (MB)";
  $data{CSVHEADER}{2} = "Paging space (%)";

  return 1;
}

sub xport_lpar_pg1 {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  $lpar =~ s/\//&&1/g;
  my $rrd = "$wrkdir/$server/$hmc/$lpar/pgs.mmm";
  $rrd = rrd_from_active_hmc( "$server", "$lpar/pgs.mmm", "$rrd" );
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  $lpar =~ s/&&1/\//g;

  my $filter = 100000000;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:pagein=\"$rrd\":page_in:AVERAGE";
  $cmd .= " DEF:pageout=\"$rrd\":page_out:AVERAGE";
  $cmd .= " CDEF:pagein_b_nf=pagein,4096,*";
  $cmd .= " CDEF:pageout_b_nf=pageout,4096,*";
  $cmd .= " CDEF:pagein_b=pagein_b_nf,$filter,GT,UNKN,pagein_b_nf,IF";
  $cmd .= " CDEF:pageout_b=pageout_b_nf,$filter,GT,UNKN,pageout_b_nf,IF";
  $cmd .= " CDEF:pagein_mb=pagein_b,1048576,/";
  $cmd .= " CDEF:pagein_mb_neg=pagein_mb,-1,*";
  $cmd .= " CDEF:pageout_mb=pageout_b,1048576,/";
  $cmd .= " CDEF:pageout_mb_res=pageout_mb,1000,*,0.5,+,FLOOR,1000,/";
  $cmd .= " CDEF:pagein_mb_res=pagein_mb,1000,*,0.5,+,FLOOR,1000,/";
  $cmd .= " XPORT:pageout_mb_res:Page_out";
  $cmd .= " XPORT:pagein_mb_res:Page_in";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Page out'} = $value1;
      $data{STATS}{$timestamp}{'Page in)'} = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$lpar";
  $data{CSVHEADER}{1} = "Page out";
  $data{CSVHEADER}{2} = "Page in";

  return 1;
}

sub xport_lpar_mem {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  $lpar =~ s/\//&&1/g;
  my $rrd = "$wrkdir/$server/$hmc/$lpar/mem.mmm";
  $rrd = rrd_from_active_hmc( "$server", "$lpar/mem.mmm", "$rrd" );
  ## try NMON data
  #if ( !-f $rrd ) {
  #  $rrd = "$wrkdir/$server/$hmc/$lpar--NMON--/mem.mmm";
  #  $rrd = rrd_from_active_hmc( "$server", "$lpar--NMON--/mem.mmm", "$rrd" );
  #  if ( -f $rrd ) {
  #    error( "NMON data: $rrd exists");
  #  }
  #  else {
  #    error( "NMON data: $rrd NOT exists");
  #  }
  #  return 0;
  #}
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  $lpar =~ s/&&1/\//g;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:size=\"$rrd\":size:AVERAGE";
  $cmd .= " DEF:used=\"$rrd\":nuse:AVERAGE";
  $cmd .= " DEF:free=\"$rrd\":free:AVERAGE";
  $cmd .= " DEF:pin=\"$rrd\":pin:AVERAGE";
  $cmd .= " DEF:in_use_work=\"$rrd\":in_use_work:AVERAGE";
  $cmd .= " DEF:in_use_clnt=\"$rrd\":in_use_clnt:AVERAGE";
  $cmd .= " CDEF:free_g=free,1048576,/";
  $cmd .= " CDEF:usedg=used,1048576,/";
  $cmd .= " CDEF:in_use_clnt_g=in_use_clnt,1048576,/";
  $cmd .= " CDEF:used_realg=usedg,in_use_clnt_g,-";
  $cmd .= " CDEF:pin_g=pin,1048576,/";
  $cmd .= " CDEF:used_realg_res=used_realg,1000,*,0.5,+,FLOOR,1000,/";
  $cmd .= " CDEF:in_use_clnt_res=in_use_clnt_g,1000,*,0.5,+,FLOOR,1000,/";
  $cmd .= " CDEF:free_g_res=free_g,1000,*,0.5,+,FLOOR,1000,/";
  $cmd .= " CDEF:pin_res=pin_g,1000,*,0.5,+,FLOOR,1000,/";
  $cmd .= " CDEF:used_realg_res_a=used_realg_res,1000,*";
  $cmd .= " CDEF:in_use_clnt_res_a=in_use_clnt_res,1000,*";
  $cmd .= " CDEF:free_g_res_a=free_g_res,1000,*";
  $cmd .= " CDEF:pin_res_a=pin_res,1000,*";
  $cmd .= " XPORT:used_realg_res_a:Used_memory_in_MB";
  $cmd .= " XPORT:in_use_clnt_res_a:FS_Cache_in_MB";
  $cmd .= " XPORT:free_g_res_a:Free_in_MB";
  $cmd .= " XPORT:pin_res_a:Pinned_in_MB";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value4    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      if ( isdigit($value4) ) {
        $value4 = sprintf '%.2f', $value4;
      }
      else {
        $value4 = '';
      }
      $data{STATS}{$timestamp}{'Used memory (MB)'} = $value1;
      $data{STATS}{$timestamp}{'FS Cache (MB)'}    = $value2;
      $data{STATS}{$timestamp}{'Free (MB)'}        = $value3;
      $data{STATS}{$timestamp}{'Pinned (MB)'}      = $value4;
    }
  }

  # set csv header
  $data{NAME}         = "$lpar";
  $data{CSVHEADER}{1} = "Used memory (MB)";
  $data{CSVHEADER}{2} = "FS Cache (MB)";
  $data{CSVHEADER}{3} = "Free (MB)";
  $data{CSVHEADER}{4} = "Pinned (MB)";

  return 1;
}

sub xport_lpar_queue_cpu {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  my $os_s = "";

  $lpar =~ s/\//&&1/g;
  my $rrd = "$wrkdir/$server/$hmc/$lpar/queue_cpu.mmm";
  $rrd = rrd_from_active_hmc( "$server", "$lpar/queue_cpu.mmm", "$rrd" );
  if ( !-f $rrd ) {
    $rrd  = "$wrkdir/$server/$hmc/$lpar/queue_cpu_aix.mmm";
    $rrd  = rrd_from_active_hmc( "$server", "$lpar/queue_cpu_aix.mmm", "$rrd" );
    $os_s = "AIX";

    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }
  }
  $lpar =~ s/&&1/\//g;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";

  if ( $os_s eq "AIX" ) {
    $cmd .= " DEF:loadcpu=\"$rrd\":load:AVERAGE";
    $cmd .= " DEF:virtualp=\"$rrd\":virtual_p:AVERAGE";
    $cmd .= " DEF:blockedp=\"$rrd\":blocked_p:AVERAGE";
    $cmd .= " DEF:blockedraw=\"$rrd\":blocked_raw:AVERAGE";
    $cmd .= " DEF:blockedIO=\"$rrd\":blocked_IO:AVERAGE";

    $cmd .= " XPORT:loadcpu:\"Load Avrg\"";
    $cmd .= " XPORT:virtualp:\"Virtual Processors\"";
    $cmd .= " XPORT:blockedp:\"Blocked Processes\"";
    $cmd .= " XPORT:blockedraw:\"Blocked raw\"";
    $cmd .= " XPORT:blockedIO:\"Blocked direct IO\"";
    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1, $value2, $value3, $value4, $value5 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value5    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
        }
        else {
          $value2 = '';
        }
        if ( isdigit($value3) ) {
          $value3 = sprintf '%.2f', $value3;
        }
        else {
          $value3 = '';
        }
        if ( isdigit($value4) ) {
          $value4 = sprintf '%.2f', $value4;
        }
        else {
          $value4 = '';
        }
        if ( isdigit($value5) ) {
          $value5 = sprintf '%.2f', $value5;
        }
        else {
          $value5 = '';
        }
        $data{STATS}{$timestamp}{'Load Avrg'}          = $value1;
        $data{STATS}{$timestamp}{'Virtual Processors'} = $value2;
        $data{STATS}{$timestamp}{'Blocked Processes'}  = $value3;
        $data{STATS}{$timestamp}{'Blocked raw'}        = $value4;
        $data{STATS}{$timestamp}{'Blocked direct IO'}  = $value5;
      }
    }

    # set csv header
    $data{NAME}         = "$lpar";
    $data{CSVHEADER}{1} = "Load Avrg";
    $data{CSVHEADER}{2} = "Virtual Processors";
    $data{CSVHEADER}{3} = "Blocked Processes";
    $data{CSVHEADER}{4} = "Blocked raw";
    $data{CSVHEADER}{5} = "Blocked direct IO";
  }
  else {
    $cmd .= " DEF:loadcpu=\"$rrd\":load:AVERAGE";
    $cmd .= " DEF:virtualp=\"$rrd\":virtual_p:AVERAGE";
    $cmd .= " DEF:blockedp=\"$rrd\":blocked_p:AVERAGE";

    $cmd .= " XPORT:loadcpu:\"Load Avrg\"";
    $cmd .= " XPORT:virtualp:\"Virtual Processors\"";
    $cmd .= " XPORT:blockedp:\"Blocked Processes\"";
    $cmd =~ s/\\"/"/g;

    RRDp::start "$rrdtool";
    RRDp::cmd qq($cmd);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
      RRDp::end;
      return 0;
    }
    RRDp::end;

    my @rrd_result;
    if ( $ret =~ /0x/ ) {
      @rrd_result = split( '\n', $$ret );
    }
    else {
      @rrd_result = split( '\n', $ret );
    }

    foreach my $row (@rrd_result) {
      chomp $row;

      #print "$row\n";
      $row =~ s/^\s+//g;
      $row =~ s/\s+$//g;
      if ( $row =~ "^<row><t>" ) {

        #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
        my ( $timestamp, $values ) = split( "</t><v>", $row );
        my ( $value1, $value2, $value3 ) = split( "</v><v>", $values );

        $timestamp =~ s/^<row><t>//;
        $value3    =~ s/<\/v><\/row>$//;

        if ( isdigit($value1) ) {
          $value1 = sprintf '%.2f', $value1;
        }
        else {
          $value1 = '';
        }
        if ( isdigit($value2) ) {
          $value2 = sprintf '%.2f', $value2;
        }
        else {
          $value2 = '';
        }
        if ( isdigit($value3) ) {
          $value3 = sprintf '%.2f', $value3;
        }
        else {
          $value3 = '';
        }
        $data{STATS}{$timestamp}{'Load Avrg'}          = $value1;
        $data{STATS}{$timestamp}{'Virtual Processors'} = $value2;
        $data{STATS}{$timestamp}{'Blocked Processes'}  = $value3;
      }
    }

    # set csv header
    $data{NAME}         = "$lpar";
    $data{CSVHEADER}{1} = "Load Avrg";
    $data{CSVHEADER}{2} = "Virtual Processors";
    $data{CSVHEADER}{3} = "Blocked Processes";
  }

  return 1;
}

sub xport_lpar_oscpu {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  $lpar =~ s/\//&&1/g;
  my $rrd = "$wrkdir/$server/$hmc/$lpar/cpu.mmm";
  $rrd = rrd_from_active_hmc( "$server", "$lpar/cpu.mmm", "$rrd" );
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  $lpar =~ s/&&1/\//g;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:entitled=\"$rrd\":entitled:AVERAGE";
  $cmd .= " DEF:cpusy=\"$rrd\":cpu_sy:AVERAGE";
  $cmd .= " DEF:cpuus=\"$rrd\":cpu_us:AVERAGE";
  $cmd .= " DEF:cpuwa=\"$rrd\":cpu_wa:AVERAGE";
  $cmd .= " CDEF:stog=100,cpusy,-,cpuus,-,cpuwa,-";
  $cmd .= " CDEF:cpusy_res=cpusy,100,*,0.5,+,FLOOR,100,/";
  $cmd .= " CDEF:cpuus_res=cpuus,100,*,0.5,+,FLOOR,100,/";
  $cmd .= " CDEF:cpuwa_res=cpuwa,100,*,0.5,+,FLOOR,100,/";
  $cmd .= " CDEF:stog_res=stog,100,*,0.5,+,FLOOR,100,/";
  $cmd .= " XPORT:cpusy_res:Sys";
  $cmd .= " XPORT:cpuus_res:User";
  $cmd .= " XPORT:cpuwa_res:IO_wait";
  $cmd .= " XPORT:stog_res:Idle";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1, $value2, $value3, $value4 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value4    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      if ( isdigit($value3) ) {
        $value3 = sprintf '%.2f', $value3;
      }
      else {
        $value3 = '';
      }
      if ( isdigit($value4) ) {
        $value4 = sprintf '%.2f', $value4;
      }
      else {
        $value4 = '';
      }
      $data{STATS}{$timestamp}{'Sys'}     = $value1;
      $data{STATS}{$timestamp}{'User'}    = $value2;
      $data{STATS}{$timestamp}{'IO wait'} = $value3;
      $data{STATS}{$timestamp}{'Idle'}    = $value4;
    }
  }

  # set csv header
  $data{NAME}         = "$lpar";
  $data{CSVHEADER}{1} = "Sys";
  $data{CSVHEADER}{2} = "User";
  $data{CSVHEADER}{3} = "IO wait";
  $data{CSVHEADER}{4} = "Idle";

  return 1;
}

sub xport_linux_cpu {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  $lpar =~ s/\//&&1/g;
  my $rrd_cpu_linux = "$wrkdir/$server/$hmc/$lpar/linux_cpu.mmm";    # CPU cores
  my $rrd           = "$wrkdir/$server/$hmc/$lpar/cpu.mmm";          # CPU OS %
  if ( !-f $rrd_cpu_linux || !-f $rrd ) {
    error( "RRD files does not exist! \"$rrd_cpu_linux(cpu_cores) and $rrd(cpu %)\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  $lpar =~ s/&&1/\//g;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:entitled=\"$rrd\":entitled:AVERAGE";
  $cmd .= " DEF:cpusy=\"$rrd\":cpu_sy:AVERAGE";
  $cmd .= " DEF:cpuus=\"$rrd\":cpu_us:AVERAGE";
  $cmd .= " DEF:cpuwa=\"$rrd\":cpu_wa:AVERAGE";
  $cmd .= " DEF:cpucount=\"$rrd_cpu_linux\":cpu_count:AVERAGE";
  $cmd .= " DEF:cpuinmhz=\"$rrd_cpu_linux\":cpu_in_mhz:AVERAGE";
  $cmd .= " DEF:threadscore=\"$rrd_cpu_linux\":threads_core:AVERAGE";
  $cmd .= " DEF:corespersocket=\"$rrd_cpu_linux\":cores_per_socket:AVERAGE";
  $cmd .= " CDEF:cpu_cores=cpucount,100,/";
  $cmd .= " CDEF:stog1=cpusy,cpuus,cpuwa,+,+";
  $cmd .= " CDEF:stog2=cpu_cores,stog1,*";
  $cmd .= " XPORT:cpucount:total_cpu";
  $cmd .= " XPORT:stog2:util_cpu";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Total CPU'}       = $value1;
      $data{STATS}{$timestamp}{'Utilization CPU'} = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$lpar";
  $data{CSVHEADER}{1} = "Total CPU";
  $data{CSVHEADER}{2} = "Utilization CPU";

  return 1;
}

sub xport_lpar_memalloc {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  $lpar =~ s/\//&&1/g;
  my $rrd = "$wrkdir/$server/$hmc/$lpar.rsm";
  $rrd = rrd_from_active_hmc( "$server", "$lpar.rsm", "$rrd" );
  if ( !-f $rrd ) {

    # try .rmm
    $rrd = "$wrkdir/$server/$hmc/$lpar.rmm";
    $rrd = rrd_from_active_hmc( "$server", "$lpar.rmm", "$rrd" );
    if ( !-f $rrd ) {
      error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
      return 0;
    }
  }
  $lpar =~ s/&&1/\//g;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:cur=\"$rrd\":curr_mem:AVERAGE";
  $cmd .= " CDEF:curg=cur,1024,/";
  $cmd .= " XPORT:curg:\"lparmemalloc\"";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {
      my ( $timestamp, $value1 ) = split( "</t><v>", $row );

      $timestamp =~ s/^<row><t>//;
      $value1    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      $data{STATS}{$timestamp}{"Current allocated memory in GB"} = $value1;
    }
  }

  # set csv header
  $data{NAME} = "$lpar";
  $data{CSVHEADER}{1} = "Current allocated memory in GB";

  return 1;
}

sub xport_lpar_cpu_hmc {
  my $hmc    = shift;
  my $server = shift;
  my $lpar   = shift;
  my $sunix  = shift;
  my $eunix  = shift;

  $lpar =~ s/\//&&1/g;
  my $rrd = "$wrkdir/$server/$hmc/$lpar.rrm";
  $rrd = rrd_from_active_hmc( "$server", "$lpar.rrm", "$rrd" );
  if ( !-f $rrd ) {
    error( "RRD file does not exist! \"$rrd\" " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  $lpar =~ s/&&1/\//g;

  # max 10k peak in % is allowed (in fact it cann by higher than 1k now when 1 logical CPU == 0.1 entitlement
  my $cpu_max_filter = ( defined $ENV{CPU_MAX_FILTER} ) ? $ENV{CPU_MAX_FILTER} : 100;

  my $cmd = "";

  #my $max_rows = 170000;
  my $max_rows = 17000000000;
  my $xport    = "xport";
  $rrd =~ s/:/\\:/g;

  $cmd .= "$xport";
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }
  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:cur=\"$rrd\":curr_proc_units:AVERAGE";
  $cmd .= " DEF:ent=\"$rrd\":entitled_cycles:AVERAGE";
  $cmd .= " DEF:cap=\"$rrd\":capped_cycles:AVERAGE";
  $cmd .= " DEF:uncap=\"$rrd\":uncapped_cycles:AVERAGE";
  $cmd .= " CDEF:tot=cap,uncap,+";
  $cmd .= " CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF";
  $cmd .= " CDEF:utiltot=util,cur,*";
  $cmd .= " CDEF:utiltot_res=utiltot,100,*,0.5,+,FLOOR,100,/";
  $cmd .= " XPORT:cur:Entitled";
  $cmd .= " XPORT:utiltot_res:Utilization_in_CPU_cores";

  $cmd =~ s/\\"/"/g;

  RRDp::start "$rrdtool";
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "rrdtool xport error : $$ret  " . __FILE__ . ":" . __LINE__ );
    RRDp::end;
    return 0;
  }
  RRDp::end;

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;

    #print "$row\n";
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {

      #<row><t>1537314840</t><v>NaN</v><v>NaN</v></row>
      my ( $timestamp, $values ) = split( "</t><v>", $row );
      my ( $value1,    $value2 ) = split( "</v><v>", $values );

      $timestamp =~ s/^<row><t>//;
      $value2    =~ s/<\/v><\/row>$//;

      if ( isdigit($value1) ) {
        $value1 = sprintf '%.2f', $value1;
      }
      else {
        $value1 = '';
      }
      if ( isdigit($value2) ) {
        $value2 = sprintf '%.2f', $value2;
      }
      else {
        $value2 = '';
      }
      $data{STATS}{$timestamp}{'Entitled'}                 = $value1;
      $data{STATS}{$timestamp}{'Utilization in CPU cores'} = $value2;
    }
  }

  # set csv header
  $data{NAME}         = "$lpar";
  $data{CSVHEADER}{1} = "Entitled";
  $data{CSVHEADER}{2} = "Utilization in CPU cores";

  return 1;
}

sub get_vmware_inventory {
  my $menu_txt = "$tmpdir/menu.txt";
  if ( -f $menu_txt ) {
    open( MENU, "<$menu_txt" ) || error( "Couldn't open file $menu_txt $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
    my @menu = <MENU>;
    chomp @menu;
    close(MENU);

    #
    # Vcenter
    #
    my @list_of_vcenters = grep {/^V:.*:Totals:.*:.*:.*:.*:.*:V/} @menu;

    # V:10.22.11.10:Totals:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=hmctotals&entitle=0&gui=1&none=none:::Hosting::V
    foreach my $line (@list_of_vcenters) {
      my ( undef, $vc_ip, undef, $url, undef, undef, $vcenter, undef ) = split( /:/, $line );

      $vc_ip   =~ s/===double-col===/:/g;
      $url     =~ s/===double-col===/:/g;
      $vcenter =~ s/===double-col===/:/g;

      $vmware_inventory{VCENTER}{$vcenter}{VCENTER_IP} = $vc_ip;
    }

    #
    # CLUSTER
    #
    my @list_of_cl = grep {/^A:.*:cluster_.*:Totals:.*:.*:.*:.*:V/} @menu;    # "V" -> only VMware section
                                                                              # A:10.22.11.10:cluster_New Cluster:Cluster totals:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=cluster&entitle=0&gui=1&none=none::Hosting::V
    foreach my $line (@list_of_cl) {
      my ( undef, undef, $cluster, undef, $detail_url, undef, $vcenter, undef ) = split( /:/, $line );

      $cluster    =~ s/^cluster_//;
      $cluster    =~ s/===double-col===/:/g;
      $vcenter    =~ s/===double-col===/:/g;
      $detail_url =~ s/===double-col===/:/g;

      # get url params
      $detail_url =~ s/^.+detail\.sh\?//;
      my @params = split( /&/, $detail_url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && defined $value ) {
            $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{URL_PARAM}{$param} = $value;
          }
        }
      }
    }

    #
    # VM
    #
    #my @list_of_vms = grep {/^L:.*:.*:.*:.*:.*:.*:.*:V$/} @menu; # "V" -> only VMware section
    my @list_of_vms = grep {/^L:.*:.*:.*:.*:.*:.*:.*:V/} @menu;    # "V" -> only VMware section
                                                                   # L:cluster_New Cluster:10.22.11.9:501c1a53-cf7d-07cb-88e4-cf94ca6c5b0e:vm-karel:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=501c1a53-cf7d-07cb-88e4-cf94ca6c5b0e&item=lpar&entitle=0&gui=1&none=none::Hosting:V
    foreach my $line (@list_of_vms) {
      my ( undef, $cluster, $server, $vm_uuid, $vm_name, $detail_url, undef, $vcenter, undef ) = split( /:/, $line );

      $cluster    =~ s/^cluster_//;
      $cluster    =~ s/===double-col===/:/g;
      $server     =~ s/===double-col===/:/g;
      $vm_uuid    =~ s/===double-col===/:/g;
      $vm_name    =~ s/===double-col===/:/g;
      $vcenter    =~ s/===double-col===/:/g;
      $detail_url =~ s/===double-col===/:/g;

      $vmware_inventory{VM}{$vm_uuid}{VCENTER} = $vcenter;
      $vmware_inventory{VM}{$vm_uuid}{CLUSTER} = $cluster;
      $vmware_inventory{VM}{$vm_uuid}{SERVER}  = $server;
      $vmware_inventory{VM}{$vm_uuid}{VM_NAME} = $vm_name;

      $vmware_inventory{VM_NAME}{$vm_name}{VCENTER}{$vcenter}{CLUSTER}{$cluster}{VM_UUID} = $vm_uuid;
      $vmware_inventory{VM_NAME}{$vm_name}{VCENTER}{$vcenter}{CLUSTER}{$cluster}{SERVER}  = $server;

      $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{VM}{$vm_uuid}{VM_NAME} = $vm_name;
      $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{VM}{$vm_uuid}{SERVER}  = $server;

      # get url params
      $detail_url =~ s/^.+detail\.sh\?//;
      my @params = split( /&/, $detail_url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && defined $value ) {
            $vmware_inventory{VM}{$vm_uuid}{URL_PARAM}{$param}                                            = $value;
            $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{VM}{$vm_uuid}{URL_PARAM}{$param}      = $value;
            $vmware_inventory{VM_NAME}{$vm_name}{VCENTER}{$vcenter}{CLUSTER}{$cluster}{URL_PARAM}{$param} = $value;
          }
        }
      }
    }

    #
    # ESXi
    #
    my @list_of_esxi = grep {/^S:cluster_.*:.*:CPUpool-pool:CPU:.*:.*:.*:V/} @menu;

    # S:cluster_New Cluster:10.22.11.9:CPUpool-pool:CPU pool:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=pool&item=pool&entitle=0&gui=1&none=none::1548025200:V
    foreach my $line (@list_of_esxi) {
      my ( undef, $cluster, $esxi, undef, undef, $url, undef ) = split( /:/, $line );

      $cluster =~ s/^cluster_//;
      $cluster =~ s/===double-col===/:/g;
      $url     =~ s/===double-col===/:/g;
      $esxi    =~ s/===double-col===/:/g;
      my $vcenter = "";

      # get url params
      $url =~ s/^.+detail\.sh\?//;
      my @params = split( /&/, $url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && $param eq "host" && defined $value ) {    # Vcenter IP
            foreach my $vc ( sort keys %{ $vmware_inventory{VCENTER} } ) {
              if ( exists $vmware_inventory{VCENTER}{$vc}{VCENTER_IP} && $vmware_inventory{VCENTER}{$vc}{VCENTER_IP} eq $value ) {
                $vcenter = $vc;
              }
            }
            last;
          }
        }
      }
      if ( defined $vcenter && $vcenter ne '' ) {
        $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{ESXI}{$esxi}{NAME} = $esxi;
      }
    }

    #
    # RESPOOL
    #
    my @list_of_rp = grep {/^B:.*:cluster_.*:.*:.*:.*:.*:.*:V/} @menu;

    # B:10.22.11.10:cluster_New Cluster:Development:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=resgroup-139&item=resourcepool&entitle=0&gui=1&none=none::Hosting::V
    foreach my $line (@list_of_rp) {
      my ( undef, undef, $cluster, $rp, $url, undef, $vcenter, undef, undef ) = split( /:/, $line );

      $cluster =~ s/^cluster_//;
      $cluster =~ s/===double-col===/:/g;
      $url     =~ s/===double-col===/:/g;
      $rp      =~ s/===double-col===/:/g;
      $vcenter =~ s/===double-col===/:/g;

      # get url params
      $url =~ s/^.+detail\.sh\?//;
      my @params = split( /&/, $url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && defined $value ) {
            $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{RESPOOL}{$rp}{URL_PARAM}{$param} = $value;
          }
        }
      }
    }

    #
    # DATASTORE
    #
    my @list_of_ds = grep {/^Z:.*:datastore_.*:.*:.*:.*:.*:.*:V/} @menu;

    # Z:10.22.11.10:datastore_DC:3PAR-phys-xorux-test:/lpar2rrd-cgi/detail.sh?host=datastore_datacenter-2&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=590e2b41-3f75d5e4-3f85-18a90577a87c&item=datastore&entitle=0&gui=1&none=none::Hosting::V
    foreach my $line (@list_of_ds) {
      my ( undef, undef, $dc, $ds, $url, undef, $vcenter, undef, undef ) = split( /:/, $line );

      $dc      =~ s/^datastore_//;
      $dc      =~ s/===double-col===/:/g;
      $ds      =~ s/===double-col===/:/g;
      $url     =~ s/===double-col===/:/g;
      $vcenter =~ s/===double-col===/:/g;
      $url     =~ s/^.+detail\.sh\?//;

      $vmware_inventory{VCENTER}{$vcenter}{DATASTORE}{$ds}{DATACENTER} = $dc;
      $vmware_inventory{VCENTER}{$vcenter}{DATASTORE}{$ds}{URL}        = $url;

      # get url params
      my @params = split( /&/, $url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && defined $value ) {
            $vmware_inventory{VCENTER}{$vcenter}{DATASTORE}{$ds}{URL_PARAM}{$param} = $value;
          }
        }
      }
    }

  }

  return 1;
}

sub urlencode {
  my $s = shift;
  $s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  return $s;
}

sub urldecodel {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  return $s;
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  #print "$act_time: $text : $!\n" if $DEBUG > 2;;

  return 1;
}

sub isdigit {
  my $digit = shift;

  if ( !defined($digit) || $digit eq '' ) {
    return 0;
  }

  if ( $digit =~ m/^-+$/ ) {
    return 0;
  }

  #if ( $digit =~ m/^e-/ || $digit =~ m/^e\+/ || $digit =~ m/^[0-9]-[0-9]/ || $digit =~ m/^[0-9]\+[0-9]/ ) { # sometimes rrdtool xport returns e-02
  #  return 0;
  #}

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/^-//;
  $digit_work =~ s/e//;
  $digit_work =~ s/\+//;
  $digit_work =~ s/\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  # NOT a number
  return 0;
}

sub test_rrdtool_xport_line {
  my $line      = shift;
  my $val_count = shift;

  # <row><t>1638403680</t><v>0.0000000000e+00</v><v>0.0000000000e+00</v></row>

  if ( $val_count == 1 ) {
    if ( $line =~ m/^<row><t>[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]<\/t><v>[0-9]\.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]e[+-][0-9][0-9]<\/v><\/row>$/ ) { return 1; }
  }
  if ( $val_count == 2 ) {
    if ( $line =~ m/^<row><t>[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]<\/t><v>[0-9]\.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]e[+-][0-9][0-9]<\/v><v>[0-9]\.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]e[+-][0-9][0-9]<\/v><\/row>$/ ) { return 1; }
  }
  if ( $val_count == 3 ) {
    if ( $line =~ m/^<row><t>[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]<\/t><v>[0-9]\.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]e[+-][0-9][0-9]<\/v><v>[0-9]\.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]e[+-][0-9][0-9]<\/v><v>[0-9]\.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]e[+-][0-9][0-9]<\/v><\/row>$/ ) { return 1; }
  }

  return 0;
}
