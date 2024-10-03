use strict;
use warnings;
use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use HostCfg;
use DatabasesWrapper;

$Data::Dumper::Sortkeys = 1;

my %creds        = %{ HostCfg::getHostConnections("OracleDB") };
my @host_aliases = keys %creds;
if ( !defined( keys %creds ) || !defined $host_aliases[0] ) {
  print "No OracleDB host found. Please save Host Configuration in GUI first<br>\n";
}
my $sh_out = "";
if (@ARGV) {
  $sh_out = $ARGV[0];
}

#print Dumper \%creds;
my @sh_arr = split( /,/, $sh_out );
print Dumper \@sh_arr;
my $sh_alias = $sh_arr[1];
my $sh_type  = "";
if ( !$sh_alias ) {
  warn( "No OracleDB host retrieved from params." . __FILE__ . ":" . __LINE__ ) && exit 1;
}

my $alias = $sh_alias;
print "\n\n$alias\n\n";
my $username   = $creds{$alias}{username};
my $password   = "\'$creds{$alias}{password}\'";
my $port       = $creds{$alias}{port};
my $db_name    = $creds{$alias}{instance};
my $type       = $creds{$alias}{type};
my $tcps_check = $creds{$alias}{useSSL};
my $ip         = "";

if ( $type ne "RAC" ) {
  $ip = $creds{$alias}{host};
}
my @health_status;

$ENV{'NLS_LANG'} = "AMERICAN_CZECH REPUBLIC.AL32UTF8";
my $ORACLE_HOME = $ENV{ORACLE_HOME};
my $inputdir    = $ENV{INPUTDIR};
my $odb_dir     = "$inputdir/data/OracleDB";
my $act_dir     = "$odb_dir/$alias";
my $iostats_dir = "$odb_dir/$alias/iostats";
my $conf_dir    = "$odb_dir/$alias/configuration";
my $totals_dir  = "$odb_dir/Totals";
my $t_conf_dir  = "$totals_dir/configuration";
my $hs_dir      = "$ENV{INPUTDIR}/tmp/health_status_summary";
my $hs_dir_odb  = "$ENV{INPUTDIR}/tmp/health_status_summary/OracleDB";
my $sql_dir     = "$inputdir/oracledb-sql";

my $totals_hosts = "$totals_dir/Hosts";
my $tcp          = "TCP";

if ( defined $tcps_check and $tcps_check eq "true" ) {
  $tcp = "TCPS";
}

my $odb_ic;

if ( -f "$ORACLE_HOME/sqlplus" ) {
  $odb_ic = $ORACLE_HOME;
}
elsif ( -f "$ORACLE_HOME/bin/sqlplus" ) {
  $odb_ic = "$ORACLE_HOME/bin";
}

# create directories in data/
unless ( -d "$odb_dir" ) {
  mkdir( "$odb_dir", 0755 ) || Xorux_lib::error( "Cannot mkdir $odb_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
}
unless ( -d $act_dir ) {
  mkdir( $act_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $act_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
}
unless ( -d $iostats_dir ) {
  mkdir( $iostats_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $iostats_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
}
unless ( -d $conf_dir ) {
  mkdir( $conf_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $conf_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
}
unless ( -d $totals_dir ) {
  mkdir( $totals_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $totals_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
}
unless ( -d $t_conf_dir ) {
  mkdir( $t_conf_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $t_conf_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
}
unless ( -d $hs_dir ) {
  mkdir( $hs_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $hs_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
}
unless ( -d $hs_dir_odb ) {
  mkdir( $hs_dir_odb, 0755 ) || Xorux_lib::error( "Cannot mkdir $hs_dir_odb: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
}
unless ( -d $totals_hosts ) {
  mkdir( $totals_hosts, 0755 ) || Xorux_lib::error( "Cannot mkdir $totals_hosts: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}

my $time = time();
my $ft   = filetime();
my %hash;
my %instance_names;
my %host_names;
my %pdb_names;

#Xorux_lib::error( "Message " . __FILE__ . ":". __LINE__ ) && exit 1;

print "\n$ft\n";

if ( $type eq "Standalone" ) {
  standalone_db( $username, $password, $ip, $port, $db_name );
}
elsif ( $type eq "RAC" or $type eq "RAC_Multitenant" ) {
  rac( $username, $password, $port, $db_name );
}
elsif ( $type eq "Multitenant" ) {
  multitenant( $username, $password, $ip, $port, $db_name );
}

generate_hsfiles();

#multitenant($connect_string);
print Dumper \%hash;

#print $result;
my $duration = time - $time;
print "\n\n$duration\n\n";

sub rac {
  my $username = shift;
  my $password = shift;
  my $port     = shift;
  my $db_name  = shift;
  my $ip       = $creds{$alias}{hosts}[0];

  #my $connect_s = "$username/$password"."@"."$ip".":$port/$db_name";
  my $connect_s = "$username/$password" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $ip . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $db_name . ')))"';

  undef %hash;

  my @help_arr = @{ $creds{$alias}{hosts} };
  for my $i ( 0 .. $#help_arr ) {

    #$connect_s = "$username/$password"."@"."$creds{$alias}{hosts}[$i]".":$port/$db_name";
    if ( $type ne "RAC_Multitenant" ) {
      $connect_s = "$username/$password" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $creds{$alias}{hosts}[$i] . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $db_name . ')))"';
      my $osql_file = "RAC_L.sql";
      if ($alias eq "IPA"){
        $osql_file = "cssz_RAC_L.sql";
      }
      sysmetric_history( "DB", $connect_s, $osql_file, "RAC", $creds{$alias}{hosts}[$i] );
    }
    else {
      $connect_s = "$username/$password" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $creds{$alias}{hosts}[$i] . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $db_name . ')))"';

      #      print "Multitenant_L.sql\n";
      sysmetric_history( "DB", $connect_s, "Multitenant_L.sql", "RAC", $creds{$alias}{hosts}[$i] );

      #      print Dumper \%hash;
      #if ($i > 0){
      #  delete $hash{RAC}{$creds{$alias}}{Capacity};
      #}
      my @pdbs;
      if ( $creds{$alias}{services} ) {
        @pdbs = @{ $creds{$alias}{services}[$i] };
        shift(@pdbs);
      }
      if (@pdbs) {
        foreach my $pdb (@pdbs) {
          $connect_s = "$username/$password" . "@" . "$creds{$alias}{hosts}[$i]" . ":$port/$pdb";

          #print "PDB_L.sql\n";
          sysmetric_history( "DB", $connect_s, "PDB_L.sql", "PDBrac", $creds{$alias}{hosts}[$i], $pdb );

          #print Dumper \%hash;
          $hash{RAC}{ $creds{$alias}{hosts}[$i] }{PDB}{$pdb}{'Data rate'}{"I/O Megabytes per Second"} = ( sprintf( "%e", $hash{RAC}{ $creds{$alias}{hosts}[$i] }{PDB}{$pdb}{'Data rate'}{"Physical Read Bytes Per Sec"} ) + sprintf( "%e", $hash{RAC}{ $creds{$alias}{hosts}[$i] }{PDB}{$pdb}{'Data rate'}{"Physical Write Bytes Per Sec"} ) ) / 1024 / 1024;
          $hash{RAC}{ $creds{$alias}{hosts}[$i] }{PDB}{$pdb}{'Data rate'}{"I/O Requests per Second"}  = ( sprintf( "%e", $hash{RAC}{ $creds{$alias}{hosts}[$i] }{PDB}{$pdb}{'Data rate'}{"Physical Reads Per Sec"} ) + sprintf( "%e", $hash{RAC}{ $creds{$alias}{hosts}[$i] }{PDB}{$pdb}{'Data rate'}{"Physical Writes Per Sec"} ) );
          $pdb_names{$pdb} = $hash{RAC}{ $creds{$alias}{hosts}[$i] }{PDB}{$pdb}{'PDBname'}{'PDB name'};

          #          $instance_names{$ip} = $db_name;
          delete( $hash{RAC}{ $creds{$alias}{hosts}[$i] }{PDB}{$pdb}{'PDBname'} );

        }    #pdb($username,$password,$ip,$port,$db_name);
      }
    }
  }

  for my $instance ( keys %{ $hash{RAC} } ) {
    my $bo;
    my $bt;
    my $bth;
    my $bf;
    unless ( $instance eq "info" ) {
      $bo  = defined $hash{RAC}{$instance}{RAC}{'gc cr block receive time'}      ? $hash{RAC}{$instance}{RAC}{'gc cr block receive time'}      : 0;
      $bt  = defined $hash{RAC}{$instance}{RAC}{'gc cr blocks received'}         ? $hash{RAC}{$instance}{RAC}{'gc cr blocks received'}         : 1;
      $bth = defined $hash{RAC}{$instance}{RAC}{'gc current block receive time'} ? $hash{RAC}{$instance}{RAC}{'gc current block receive time'} : 0;
      $bf  = defined $hash{RAC}{$instance}{RAC}{'gc current blocks received'}    ? $hash{RAC}{$instance}{RAC}{'gc current blocks received'}    : 1;
      $bt  = $bt == 0                                                            ? 1                                                           : $bt;
      $bf  = $bf == 0                                                            ? 1                                                           : $bf;
      Xorux_lib::write_json( "$iostats_dir/oracledb_$ft.json", \%hash );
      $hash{RAC}{$instance}{RAC}{'GC Avg CR Block receive ms'}  = sprintf( $bo / $bt );
      $hash{RAC}{$instance}{RAC}{'GC Avg CUR Block receive ms'} = sprintf( $bth / $bf );
    }

    $instance_names{$instance} = defined $hash{RAC}{$instance}{'Instance name'}{'Instance name'} ? $hash{RAC}{$instance}{'Instance name'}{'Instance name'} : $instance;
    delete( $hash{RAC}{$instance}{'Instance name'} );
    $host_names{$instance} = $hash{RAC}{$instance}{'Host name'}{'Host name'};
    delete( $hash{RAC}{$instance}{'Host name'} );
  }

  #if ($alias ne "DSB"){
  if(DatabasesWrapper::can_update("$act_dir/names_check", 1800, 1)){
    Xorux_lib::write_json( "$act_dir/pdb_names.json",      \%pdb_names );
    Xorux_lib::write_json( "$act_dir/instance_names.json", \%instance_names );
    Xorux_lib::write_json( "$act_dir/host_names.json",     \%host_names );
  }
  #}
  #merge_global();

  if (%hash) {
    $hash{RAC}{info}{alias}     = $alias;
    $hash{RAC}{info}{type}      = $type;
    $hash{RAC}{info}{timestamp} = time;
    Xorux_lib::write_json( "$iostats_dir/oracledb_$ft.json", \%hash );
  }

  #  print "perflikeconf";
  undef %hash;
  my @metrics = ("perflikeconf_rac.sql");

  # print "perflikeconf_rac.sql\n";
  tablespaces( $connect_s, \@metrics, "RAC" );
  my @pdbs;
  if ( $creds{$alias}{services} ) {
    @pdbs = @{ $creds{$alias}{services}[0] };
    shift(@pdbs);
  }
  if ( $creds{$alias}{services}[0] ) {

    #print "perflikeconf_pdb.sql\n";
    my @metric = ("perflikeconf_pdb.sql");

    for my $j ( 0 .. $#help_arr ) {
      if ( @{ $creds{$alias}{services}[$j] } ) {
        @pdbs = @{ $creds{$alias}{services}[$j] };

        foreach my $pdb (@pdbs) {
          my $connect_s_pdb = "$username/$password" . "@" . "$creds{$alias}{hosts}[$j]" . ":$port/$pdb";
          tablespaces( $connect_s_pdb, \@metric, "RAC", $creds{$alias}{hosts}[$j] );
        }
      }
    }
  }
  else {
  }
  if (%hash) {

    #    print Dumper \%hash;
    $hash{RAC}{info}{alias}     = $alias;
    $hash{RAC}{info}{id}        = "$ip-$db_name";
    $hash{RAC}{info}{type}      = $type;
    $hash{RAC}{info}{timestamp} = time;
    Xorux_lib::write_json( "$conf_dir/perflikeconf.json", \%hash );
  }
}

sub merge_global {
  my @merge_metrics = (
    'Global Cache Blocks Lost',              'Global Cache Average CR Get Time',
    'Global Cache Average Current Get Time', 'GC CR Block Received Per Second',
    'GC Current Block Received Per Second',  'Cell Physical IO Interconnect Bytes',
    'Global Cache Blocks Corrupted',
    'DB files read latency',          'db file scattered read',
    'db file sequential read',        'db file single write',
    'db file parallel write',         'log file sync',
    'log file single write',          'log file parallel write',
    'flashback log file sync',        'DB files write latency',
    'LOG files write latency',        'gc cr block 2-way',
    'gc cr block 3-way',              'gc current block 2-way',
    'gc current block 3-way',         'gc cr block busy',
    'gc cr block congested',          'gc cr grant 2-way',
    'gc cr grant congested',          'gc current block busy',
    'gc current block congested',     'gc cr block lost',
    'gc current block lost',          'gc cr failure',
    'gc current retry',               'gc current split',
    'gc current multi block request', 'gc current grant busy',
    'gc cr disk read',                'gc cr multi block request',
    'gc buffer busy acquire',         'gc buffer busy release',
    'gc current grant 2-way',         'gc current grant congested'
  );
  for my $instance ( keys %{ $hash{RAC} } ) {
    unless ( $instance eq "info" ) {
      foreach my $metric (@merge_metrics) {
        if ( $hash{$type}{info}{Global}{$metric} ) {
          if ( $hash{RAC}{$instance}{RAC}{$metric} ) {
            $hash{$type}{info}{Global}{$metric} += $hash{RAC}{$instance}{RAC}{$metric};
          }
        }
        else {
          if ( $hash{RAC}{$instance}{RAC}{$metric} ) {
            $hash{$type}{info}{Global}{$metric} = $hash{RAC}{$instance}{RAC}{$metric};
          }
          else {
            $hash{$type}{info}{Global}{$metric} = 0;
          }
        }
      }
    }
  }
}

sub multitenant {
  my $username = shift;
  my $password = shift;
  my $ip       = shift;
  my $port     = shift;
  my $db_name  = shift;
  my @pdbs;
  if ( $creds{$alias}{services} ) {
    @pdbs = @{ $creds{$alias}{services} };
  }
  my $connect_s = "$username/$password" . "@" . "$ip" . ":$port/$db_name";

  #my $connect_s = "$username/$password"."@".'"(DESCRIPTION=(ADDRESS=(PROTOCOL='.$tcp.')(HOST='.$ip.')(PORT='.$port.'))(CONNECT_DATA=(SERVICE_NAME='.$db_name.')))"';

  #my @metrics = ("Multitenant.sql");

  undef %hash;
  my @metrics = ("perflikeconf.sql");

  tablespaces( $connect_s, \@metrics, "Multitenant" );
  if (@pdbs) {
    my @metric = ("perflikeconf_pdb.sql");
    foreach my $pdb (@pdbs) {
      my $connect_s_pdb = "$username/$password" . "@" . "$ip" . ":$port/$pdb";
      tablespaces( $connect_s_pdb, \@metric, "Multitenant" );
    }
  }
  if (%hash) {
    $hash{$type}{info}{alias} = $alias;
    $hash{$type}{info}{id}    = "$ip-$db_name";
    $hash{$type}{info}{type}  = $type;
    Xorux_lib::write_json( "$conf_dir/perflikeconf.json", \%hash );
  }

  undef %hash;
  sysmetric_history( "DB", $connect_s, "Multitenant_L.sql", "Multitenant", $ip, $db_name );

  #  if(%hash){
  #    $hash{$type}{info}{alias} = $alias;
  #    $hash{$type}{info}{id} = "$ip-$db_name";
  #    $hash{$type}{info}{type} = $type;
  #    $hash{$type}{info}{timestamp} = time;
  #    $instance_names{$ip} = $hash{Standalone}{'Instance name'}{'Instance name'};
  #    delete($hash{Standalone}{'Instance name'});
  #
  #    Xorux_lib::write_json("$act_dir/instance_names.json", \%instance_names);
  #    Xorux_lib::write_json("$iostats_dir/oracledb_$ft.json", \%hash);
  #  }
  if (@pdbs) {
    foreach my $pdb (@pdbs) {
      $connect_s = "$username/$password" . "@" . "$ip" . ":$port/$pdb";

      sysmetric_history( "DB", $connect_s, "PDB_L.sql", "PDB", $ip, $pdb );

      $hash{PDB}{$pdb}{'Data rate'}{"I/O Megabytes per Second"} = ( sprintf( "%e", $hash{PDB}{$pdb}{'Data rate'}{"Physical Read Bytes Per Sec"} ) + sprintf( "%e", $hash{PDB}{$pdb}{'Data rate'}{"Physical Write Bytes Per Sec"} ) ) / 1024 / 1024;
      $hash{PDB}{$pdb}{'Data rate'}{"I/O Requests per Second"}  = ( sprintf( "%e", $hash{PDB}{$pdb}{'Data rate'}{"Physical Reads Per Sec"} ) + sprintf( "%e", $hash{PDB}{$pdb}{'Data rate'}{"Physical Writes Per Sec"} ) );
      $pdb_names{$pdb} = $hash{PDB}{$pdb}{'PDBname'}{'PDB name'};

      #      $instance_names{$ip} = $db_name;
      delete( $hash{PDB}{$pdb}{'PDBname'} );

    }    #pdb($username,$password,$ip,$port,$db_name);
  }

  if (%hash) {
    $hash{$type}{info}{alias}     = $alias;
    $hash{$type}{info}{type}      = $type;
    $hash{$type}{info}{timestamp} = time;
    $instance_names{$ip}          = $hash{Multitenant}{'Instance name'}{'Instance name'};

    #   $instance_names{$ip} = $db_name;
    delete( $hash{Multitenant}{'Instance name'} );
    $host_names{$ip} = $hash{Multitenant}{'Host name'}{'Host name'};
    delete( $hash{Multitenant}{'Host name'} );
    #
    #    print Dumper \%hash;
    if(DatabasesWrapper::can_update("$act_dir/names_check", 1800, 1)){
      Xorux_lib::write_json( "$act_dir/pdb_names.json",        \%pdb_names );
      Xorux_lib::write_json( "$act_dir/instance_names.json",   \%instance_names );
      Xorux_lib::write_json( "$act_dir/host_names.json",       \%host_names );
    }
    Xorux_lib::write_json( "$iostats_dir/oracledb_$ft.json", \%hash );

    #    Xorux_lib::write_json("$iostats_dir/pdb.json", \%hash);
  }
}

sub perflikeconf {
  my $username = shift;
  my $password = shift;
  my $ip       = shift;
  my $port     = shift;
  my $db_name  = shift;

  my $connect_s = "$username/$password" . "@" . "$ip" . ":$port/$db_name";

  my @metrics = ("perflikeconf.sql");

  undef %hash;
  tablespaces( $connect_s, \@metrics, $type );
  if (%hash) {
    $hash{$type}{info}{alias} = $alias;
    $hash{$type}{info}{id}    = "$ip-$db_name";
    $hash{$type}{info}{type}  = $type;
    Xorux_lib::write_json( "$conf_dir/perflikeconf.json", \%hash );
  }

}

sub standalone_db {
  my $username = shift;
  my $password = shift;
  my $ip       = shift;
  my $port     = shift;
  my $db_name  = shift;

  #my $connect_s = "$username/$password"."@"."$ip".":$port/$db_name";
  my $connect_s = "$username/$password" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $ip . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $db_name . ')))"';

  my @metrics = ("perflikeconf.sql");

  undef %hash;
  tablespaces( $connect_s, \@metrics, "Standalone" );
  if (%hash) {
    $hash{$type}{info}{alias} = $alias;
    $hash{$type}{info}{id}    = "$ip-$db_name";
    $hash{$type}{info}{type}  = $type;
    Xorux_lib::write_json( "$conf_dir/perflikeconf.json", \%hash );
  }

  undef %hash;

  sysmetric_history( "DB", $connect_s, "Standalone_L.sql", "Standalone", $ip );

  my $dataguard = $creds{$alias}{dataguard};

  if ( $dataguard and $dataguard->[0]->{hosts}->[0] and $dataguard->[0]->{hosts}->[0] ne "" ) {
    my @dg_list = @{$dataguard};
    for my $i ( 0 .. $#dg_list ) {
      my @hosts = @{ $dg_list[$i]->{hosts} };
      foreach my $dg_host (@hosts) {
        my $service = $dg_list[$i]->{instance}->[0];
        $connect_s = "$username/$password" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $dg_host . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $service . ')))"';
        sysmetric_history( "DG", $connect_s, "Standalone_L.sql", "Standalone", $dg_host );
        last;
      }
    }
  }

  if (%hash) {
    $hash{$type}{info}{alias}     = $alias;
    $hash{$type}{info}{id}        = "$ip-$db_name";
    $hash{$type}{info}{type}      = $type;
    $hash{$type}{info}{timestamp} = time;
    $instance_names{$ip}          = $hash{Standalone}{'Instance name'}{'Instance name'};
    delete( $hash{Standalone}{'Instance name'} );
    $host_names{$ip} = $hash{Standalone}{'Host name'}{'Host name'};
    delete( $hash{Standalone}{'Host name'} );

    if(DatabasesWrapper::can_update("$act_dir/names_check", 1800, 1)){
      Xorux_lib::write_json( "$act_dir/instance_names.json",   \%instance_names );
      Xorux_lib::write_json( "$act_dir/host_names.json",       \%host_names );
    }
    Xorux_lib::write_json( "$iostats_dir/oracledb_$ft.json", \%hash );
  }

  #Xorux_lib::write_json("$iostats_dir/standalone_oracledb_$ft.json",\%hash);
}

sub tablespaces {
  my $connect_s = shift;
  my $met       = shift;
  my $type      = shift;
  my $inst      = shift;
  my @metrics   = @{$met};
  for my $i ( 0 .. $#metrics ) {
    my $result;

    #    if($type eq "Standalone"){
    $result = qx {$odb_ic/sqlplus -S -L $connect_s \@$sql_dir\/$metrics[$i]; echo \"ret:\$?\"};

    #print $result;
    if ( $result =~ /ret:1/ ) {
      $result =~ s/ret:1//g;

      #warn $result;
      return 0;
    }
    else {
      $result =~ s/ret:0//g;
    }

    #    }else{
    #    }
    #    print $result;
    $result =~ s/"//g;

    #print $result;
    my @ssa = split( "##", $result );

    #    print Dumper \@ssa;
    for my $ts_number ( 0 .. $#ssa ) {
      my $name;
      if ( !$ssa[$ts_number] ) {
        next;
      }
      my @ada = split( "\n", $ssa[$ts_number] );
      if ( index( $ada[$#ada], "rows selected." ) != -1 ) {
        pop(@ada);
        pop(@ada);
      }

      #      print Dumper \@ada;
      my @header;
      my $start_index = 3;
      if ( $ada[0] eq "" ) {
        $name        = $ada[1];
        $start_index = 4;
        @header      = split( /\|/, $ada[3] );
      }
      else {
        $name   = $ada[0];
        @header = split( /\|/, $ada[2] );
      }

      #print Dumper \@header;
      for my $i ( $start_index .. $#ada ) {
        my %helper;
        my @rowdata = split( /\|/, $ada[$i] );
        for my $j ( 1 .. $#header ) {
          $helper{ $header[$j] } = $rowdata[$j];
        }
        if ($inst) {
          push( @{ $hash{$type}{$name}{"$inst,$rowdata[0]"} }, \%helper );
        }
        else {
          push( @{ $hash{$type}{$name}{ $rowdata[0] } }, \%helper );
        }
      }
    }
  }
}

sub generate_hsfiles {
  foreach my $row (@health_status) {
    my @row_arr = @{$row};

    if ( $row_arr[3] eq "OK" ) {
      my $checkup_file_ok;
      my $checkup_file_nok;
      if ( $row_arr[5] ) {
        $checkup_file_ok  = "$hs_dir_odb/$alias\_$row_arr[2]\,$row_arr[5].ok";
        $checkup_file_nok = "$hs_dir_odb/$alias\_$row_arr[2]\,$row_arr[5].nok";
      }
      else {
        $checkup_file_ok  = "$hs_dir_odb/$alias\_$row_arr[2].ok";
        $checkup_file_nok = "$hs_dir_odb/$alias\_$row_arr[2].nok";
      }
      if ( -f $checkup_file_nok ) {
        unlink $checkup_file_nok;
      }
      if ( $row_arr[5] ) {
        $row_arr[2] = $row_arr[5];
        pop @row_arr;
      }
      elsif ( $instance_names{ $row_arr[2] } ) {
        $row_arr[2] = $instance_names{ $row_arr[2] };
      }

      my $joined_row = join( " : ", @row_arr );
      open my $fh, '>', $checkup_file_ok;

      print $fh $joined_row;
      close $fh;

    }
    elsif ( $row_arr[3] eq "NOT_OK" ) {
      my $checkup_file_ok;
      my $checkup_file_nok;
      if ( $row_arr[6] ) {
        $checkup_file_ok  = "$hs_dir_odb/$alias\_$row_arr[2]\,$row_arr[6].ok";
        $checkup_file_nok = "$hs_dir_odb/$alias\_$row_arr[2]\,$row_arr[6].nok";
      }
      else {
        $checkup_file_ok  = "$hs_dir_odb/$alias\_$row_arr[2].ok";
        $checkup_file_nok = "$hs_dir_odb/$alias\_$row_arr[2].nok";
      }
      if ( -f $checkup_file_ok ) {
        unlink $checkup_file_ok;
      }
      if ( !-f $checkup_file_nok ) {
        if ( $row_arr[6] ) {
          $row_arr[2] = $row_arr[7];
          pop @row_arr;
        }
        elsif ( $instance_names{ $row_arr[2] } ) {
          $row_arr[2] = $instance_names{ $row_arr[2] };
        }
        my $joined_row = join( " : ", @row_arr );
        open my $fh, '>', $checkup_file_nok;
        print $fh $joined_row;
        close $fh;
      }
    }
  }
}

sub sysmetric_history {
  my $save_type = shift;
  my $connect_s = shift;
  my $file      = shift;
  my $type      = shift;
  my $instname  = shift;
  my $pdb       = shift;
  my $result    = "";

  $result = qx {$odb_ic/sqlplus -S -L $connect_s \@$sql_dir\/$file; echo \"ret:\$?\"};

  #  warn $result;
  print $result;
  if ( $result =~ /ret:1/ ) {
    $result =~ s/ret:1//g;
    my @arr = split( /\n/, $result );

    #print Dumper \@arr;
    my $err = "";
    foreach my $part (@arr) {
      if ( $part eq "" ) {
        last;
      }
      if ( $part ne "ERROR:" ) {
        $err .= " $part";
      }
    }

    #    my $checkup_file_ok = "$hs_dir/$alias-$instname.ok";
    #    my $checkup_file_nok = "$hs_dir/$alias-$instname.nok";
    #    if(-f $checkup_file_ok){
    #      unlink $checkup_file_ok;
    #    }
    #
    #    if(!-f $checkup_file_nok){
    #      open my $fh, '>', $checkup_file_nok;
    my $time_is_now = time;
    my @row;
    $row[0] = "OracleDB";
    $row[1] = "$alias";
    $row[2] = "$instname";
    $row[3] = "NOT_OK";
    $row[4] = "$time_is_now";
    $row[5] = "$err";

    if ($pdb) {
      $row[6] = "$pdb";
    }
    push( @health_status, \@row );

    #      print $fh "OracleDB : $alias : $instname : NOK : $time_is_now : $err";
    #     close $fh;
    #    }

    #warn $result;
    return 0;
  }
  else {
    $result =~ s/ret:0//g;

    #    my $checkup_file_ok = "$hs_dir/$alias-$instname.ok";
    #    my $checkup_file_nok = "$hs_dir/$alias-$instname.nok";
    #    if(-f $checkup_file_nok){
    #      unlink $checkup_file_nok;
    #    }
    my $time_is_now = time;
    my @row;
    $row[0] = "OracleDB";
    $row[1] = "$alias";
    $row[2] = "$instname";
    $row[3] = "OK";
    $row[4] = "$time_is_now";

    if ($pdb) {
      $row[5] = "$pdb";
    }
    push( @health_status, \@row );

    #open my $fh, '>', $checkup_file_ok;
    #my $time_is_now = time;
    #print $fh "OracleDB : $alias : $instname : OK : $time_is_now";
    #close $fh;
  }

  #print $?;
  #warn $result;
  $result =~ s/[\n]+//g;
  if ( $type eq "RAC" or $type eq "RAC_Multitenant" ) {
    work_result( $save_type, $result, $type, $instname );
  }
  elsif ( $type eq "PDB" ) {
    work_result( $save_type, $result, $type, $instname, $db_name, $pdb );
  }
  elsif ( $type eq "PDBrac" ) {
    work_result( $save_type, $result, $type, $instname, $db_name, $pdb );
  }
  else {
    work_result( $save_type, $result, $type, $instname, $db_name );
  }
}

sub work_result {
  my $save_type = shift;
  my $result    = shift;
  my $type      = shift;
  my $instname  = shift;
  my $db_name   = shift;
  my $pdb       = shift;

  my @res_arr = split( /\|/, $result );
  if ( $type eq "RAC" or $type eq "RAC_Multitenant" ) {
    for my $i ( 0 .. $#res_arr ) {
      next if ( $res_arr[$i] !~ /\;\;\;/ or $res_arr[$i] eq "" or $res_arr[$i] =~ /\\/ );
      my @arr  = split( ";;;", $res_arr[$i] );
      my $name = pop(@arr);
      pop(@arr);
      for my $j ( 0 .. $#arr ) {
        next if ( $res_arr[$i] eq "" or $res_arr[$i] =~ /\\/ );
        my @line = split( ";", $arr[$j] );
        if ( defined $line[3] ) {
          $line[3] =~ s/,/./g;
          if ( $line[3] =~ /^\./ ) {
            my $added_zero = "0" . "$line[3]";
            $hash{$type}{$instname}{$name}{ $line[1] } = $added_zero;
          }
          else {
            $hash{$type}{$instname}{$name}{ $line[1] } = $line[3];
          }
        }
        else {
          if ( $line[0] =~ /ORA-/ ) {
            warn "error $line[0] DB: $save_type, $type, $instname";
          }
        }
      }
    }
  }
  elsif ( $type eq "PDB" ) {
    for my $i ( 0 .. $#res_arr ) {
      next if ( $res_arr[$i] !~ /\;\;\;/ or $res_arr[$i] eq "" or $res_arr[$i] =~ /\\/ );
      my @arr  = split( ";;;", $res_arr[$i] );
      my $name = pop(@arr);
      $name =~ s/;//g;
      pop(@arr);
      for my $j ( 0 .. $#arr ) {
        next if ( $res_arr[$i] eq "" or $res_arr[$i] =~ /\\/ );
        my @line = split( ";", $arr[$j] );
        if ( defined $line[3] ) {
          $line[3] =~ s/,/./g;
          if ( $line[3] =~ /^\./ ) {
            my $added_zero = "0" . "$line[3]";
            $hash{$type}{$pdb}{$name}{ $line[1] } = $added_zero;
          }
          else {
            $hash{$type}{$pdb}{$name}{ $line[1] } = $line[3];
          }
        }
        else {
          if ( $line[0] =~ /ORA-/ ) {
            warn "error $line[0] DB: $save_type, $type, $instname";
          }
        }
      }
    }
  }
  elsif ( $type eq "PDBrac" ) {
    for my $i ( 0 .. $#res_arr ) {
      next if ( $res_arr[$i] !~ /\;\;\;/ or $res_arr[$i] eq "" or $res_arr[$i] =~ /\\/ );
      my @arr  = split( ";;;", $res_arr[$i] );
      my $name = pop(@arr);
      pop(@arr);
      for my $j ( 0 .. $#arr ) {
        next if ( $res_arr[$i] eq "" or $res_arr[$i] =~ /\\/ );
        my @line = split( ";", $arr[$j] );
        if ( defined $line[3] ) {
          $line[3] =~ s/,/./g;
          if ( $line[3] =~ /^\./ ) {
            my $added_zero = "0" . "$line[3]";
            $hash{RAC}{$instname}{PDB}{$pdb}{$name}{ $line[1] } = $added_zero;
          }
          else {
            $hash{RAC}{$instname}{PDB}{$pdb}{$name}{ $line[1] } = $line[3];
          }
        }
        else {
          if ( $line[0] =~ /ORA-/ ) {
            warn "error $line[0] DB: $save_type, $type, $instname";
          }
        }
      }
    }
  }
  else {
    for my $i ( 0 .. $#res_arr ) {
      next if ( $res_arr[$i] !~ /\;\;\;/ or $res_arr[$i] eq "" or $res_arr[$i] =~ /\\/ );
      my @arr  = split( ";;;", $res_arr[$i] );
      my $name = pop(@arr);
      pop(@arr);
      for my $j ( 0 .. $#arr ) {
        my @line = split( ";", $arr[$j] );
        next if ( $res_arr[$i] eq "" or $res_arr[$i] =~ /\\/ );
        if ( defined $line[3] ) {
          $line[3] =~ s/,/./g;
          my $added_zero;
          if ( $line[3] =~ /^\,/ ) {
            $added_zero = "0" . "$line[3]";
          }
          else {
            $added_zero = $line[3];
          }
          if ( $save_type eq "DG" ) {
            $hash{$type}{DG}{$instname}{$name}{ $line[1] } = $added_zero;
          }
          else {
            $hash{$type}{$name}{ $line[1] } = $added_zero;
          }
        }
        else {
          if ( $line[0] =~ /ORA-/ ) {
            warn "error $line[0] DB: $save_type, $type, $instname";
          }
        }
      }
    }
  }
}

sub round {
  my $value    = shift;
  my $decimals = shift;

  return $value = sprintf( "%." . "$decimals" . "f", $value );
}

# transforms given gmtime to UTC #
sub gmtime2utc {
  my ( $sec, $min, $hour, $mday, $mon, $year, $secbool ) = @_;
  $year += 1900;
  $mon  += 1;
  $mon  = sprintf( "%02d", $mon );
  $mday = sprintf( "%02d", $mday );
  $hour = sprintf( "%02d", $hour );
  $min  = sprintf( "%02d", $min );
  if ( defined $secbool and $secbool == 1 ) {
    return "$year-$mon-$mday" . "T" . "$hour:$min:$sec" . "Z";
  }
  else {
    return "$year-$mon-$mday" . "T" . "$hour:$min:00Z";
  }
}

sub filetime {
  my ( $sec, $min, $hour, $mday, $mon, $year ) = ( localtime( $time - 120 ) );
  my $utctime = gmtime2utc( $sec, $min, $hour, $mday, $mon, $year );
  $utctime = substr( $utctime, 0, -4 );
  $utctime =~ s/-//g;
  $utctime =~ s/://g;
  $utctime =~ s/T/_/g;

  return $utctime;
}

