use strict;
use warnings;
use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use Time::HiRes qw(time);
use HostCfg;

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
my $username = $creds{$alias}{username};
my $password = "\'$creds{$alias}{password}\'";
my $port     = $creds{$alias}{port};
my $db_name  = $creds{$alias}{instance};
my $type     = $creds{$alias}{type};
my $ip       = "";

if ( $type ne "RAC" ) {
  $ip = $creds{$alias}{host};
}

$ENV{'NLS_LANG'} = "AMERICAN_CZECH REPUBLIC.AL32UTF8";
my $ORACLE_HOME = $ENV{ORACLE_HOME};                 #"/opt/oracle/instantclient_19_3;"
my $inputdir    = $ENV{INPUTDIR};
my $odb_dir     = "$inputdir/data/OracleDB";
my $act_dir     = "$odb_dir/$alias";
my $iostats_dir = "$odb_dir/$alias/iostats";
my $conf_dir    = "$odb_dir/$alias/configuration";
my $sql_dir     = "$inputdir/oracledb-sql";

my $odb_ic;

if ( -f "$ORACLE_HOME/sqlplus" ) {
  $odb_ic = $ORACLE_HOME;
}
elsif ( -f "$ORACLE_HOME/bin/sqlplus" ) {
  $odb_ic = "$ORACLE_HOME/bin";
}

# create directories in data/
unless ( -d $odb_dir ) {
  mkdir( $odb_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $odb_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
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

my $time = time();
my $ft   = filetime();
my %hash;

#Xorux_lib::error( "Message " . __FILE__ . ":". __LINE__ ) && exit 1;

my $run_conf     = 0;
my $checkup_file = "$odb_dir/$alias/conf_hourly";
if ( -e $checkup_file ) {
  my $modtime  = ( stat($checkup_file) )[9];
  my $timediff = time - $modtime;
  if ( $timediff >= 3600 ) {
    $run_conf = 1;
    open my $fh, '>', $checkup_file;
    print $fh "1\n";
    close $fh;
  }
}
elsif ( !-e $checkup_file ) {
  $run_conf = 1;
  open my $fh, '>', $checkup_file;
  print $fh "1\n";
  close $fh;
}
if ($run_conf) {
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
}

#multitenant($connect_string);
#print Dumper \%hash;
#print $result;
my $duration = time - $time;
print "\n\n$duration\n\n";

sub rac {
  my $username = shift;
  my $password = shift;
  my $port     = shift;
  my $db_name  = shift;
  my $ip       = $creds{$alias}{hosts}[0];

  my $connect_s = "$username/$password" . "@" . "$ip" . ":$port/$db_name";
  if ( $type ne "RAC_Multitenant" ) {
    my @metrics = ("RAC.sql");
    undef %hash;
    tablespaces( $connect_s, \@metrics, "RAC" );
  }
  else {
    my @metrics  = ("CDB.sql");
    my @help_arr = @{ $creds{$alias}{hosts} };

    tablespaces( $connect_s, \@metrics, "RAC" );

    my @pdbs;
    if ( $creds{$alias}{services} ) {
      @pdbs = @{ $creds{$alias}{services}[0] };
      shift(@pdbs);
    }
    if ( $creds{$alias}{services}[0] ) {
      my @metrics = ("PDB.sql");

      for my $j ( 0 .. $#help_arr ) {
        if ( @{ $creds{$alias}{services}[$j] } ) {
          @pdbs = @{ $creds{$alias}{services}[$j] };

          foreach my $pdb (@pdbs) {
            my $connect_s_pdb = "$username/$password" . "@" . "$creds{$alias}{hosts}[$j]" . ":$port/$pdb";
            tablespaces( $connect_s_pdb, \@metrics, "PDB", "$creds{$alias}{hosts}[$j],$pdb" );
          }
        }
      }
    }
    else {
    }

  }
  if (%hash) {

    #    print Dumper \%hash;
    $hash{$type}{info}{alias} = $alias;
    $hash{$type}{info}{id}    = "$ip-$db_name";
    $hash{$type}{info}{type}  = $type;

    #if ($alias ne "DSB"){
    Xorux_lib::write_json( "$conf_dir/conf.json", \%hash );

    #}
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

  #my $connect_s = "$username/$password"."@".'"(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST='.$ip.')(PORT='.$port.'))(CONNECT_DATA=(SERVICE_NAME='.$db_name.')))"';

  #  my @metrics = ("perflikeconf.sql");

  undef %hash;

  my @metrics = ("CDB.sql");
  tablespaces( $connect_s, \@metrics, "Multitenant" );

  if (@pdbs) {
    my @metrics = ("PDB.sql");
    foreach my $pdb (@pdbs) {
      $connect_s = "$username/$password" . "@" . "$ip" . ":$port/$pdb";
      tablespaces( $connect_s, \@metrics, "PDB", $pdb );
    }
  }    #pdb($username,$password,$ip,$port,$db_name);

  if (%hash) {

    $hash{$type}{info}{alias} = $alias;
    $hash{$type}{info}{id}    = "$ip-$db_name";
    $hash{$type}{info}{type}  = $type;
    Xorux_lib::write_json( "$conf_dir/conf.json", \%hash );
  }

  #  tablespaces($connect_s, \@metrics,"Standalone");
  #  if(%hash){
  #    $hash{$type}{info}{alias} = $alias;
  #    $hash{$type}{info}{id} = "$ip-$db_name";
  #    $hash{$type}{info}{type} = $type;
  #    Xorux_lib::write_json("$conf_dir/perflikeconf.json", \%hash);
  #  }

  #  undef %hash;

  #  sysmetric_history($connect_s, "Standalone_L.sql", "Standalone", $ip);
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

}

sub standalone_db {
  my $username = shift;
  my $password = shift;
  my $ip       = shift;
  my $port     = shift;
  my $db_name  = shift;

  my $connect_s = "$username/$password" . "@" . "$ip" . ":$port/$db_name";

  my @metrics = ("Standalone.sql");
  undef %hash;
  tablespaces( $connect_s, \@metrics, "Standalone" );

  #  print Dumper \%hash;
  if (%hash) {
    $hash{$type}{info}{alias} = $alias;
    $hash{$type}{info}{id}    = "$ip-$db_name";
    $hash{$type}{info}{type}  = $type;
    Xorux_lib::write_json( "$conf_dir/conf.json", \%hash );
  }

  undef %hash;
  my $dataguard = $creds{$alias}{dataguard};
  @metrics = ("dataguard.sql");

  if ( $dataguard and $dataguard->[0] ) {
    tablespaces( $connect_s, \@metrics, "RAC" );

    #    my @dg_list = @{$dataguard};
    #    for my $i (0 .. $#dg_list){
    #      my @hosts = @{$dg_list[$i]->{hosts}};
    #      foreach my $dg_host (@hosts){
    #        my $service = $dg_list[$i]->{instance}->[0];
    #        $connect_s = "$username/$password"."@".'"(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST='.$dg_host.')(PORT='.$port.'))(CONNECT_DATA=(SERVICE_NAME='.$service.')))"';
    #        last;
    #      }
    #    }
  }

  #  print Dumper \%hash;
  if (%hash) {
    $hash{RAC}{info}{alias} = $alias;
    $hash{RAC}{info}{id}    = "$ip-$db_name";
    $hash{RAC}{info}{type}  = $type;
    Xorux_lib::write_json( "$conf_dir/dataguard.json", \%hash );
  }

  #  undef %hash;
  #
  #  sysmetric_history($connect_s, "Standalone_L.sql","Standalone");
  #  if(%hash){
  #    $hash{$type}{info}{alias} = $alias;
  #    $hash{$type}{info}{id} = "$ip-$db_name";
  #    $hash{$type}{info}{type} = $type;
  #    Xorux_lib::write_json("$iostats_dir/perf.json", \%hash);
  #  }
  #Xorux_lib::write_json("$iostats_dir/standalone_oracledb_$ft.json",\%hash);
}

sub tablespaces {
  my $connect_s = shift;
  my $met       = shift;
  my $type      = shift;
  my $pdb       = shift;
  my @metrics   = @{$met};
  for my $i ( 0 .. $#metrics ) {
    my $result;

    $result = qx {$odb_ic/sqlplus -S -L $connect_s \@$sql_dir\/$metrics[$i]; echo \"ret:\$?\"};

    #$result = $res;
    if ( $result =~ /ret:1/ ) {
      $result =~ s/ret:1//g;

      #warn $result;
      return 0;
    }
    else {
      $result =~ s/ret:0//g;
    }

    #    }else{
    #      $result = $conf_socialka;
    #    }
    #    print $result;
    $result =~ s/"//g;
    print $result;
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
        if ( $type eq "PDB" and ( $name eq "PDB info" or $name eq "Tablespace info" or $name eq "SGA info" ) ) {
          push( @{ $hash{$name}{$pdb}{ $rowdata[0] } }, \%helper );
        }
        push( @{ $hash{$type}{$name}{ $rowdata[0] } }, \%helper );
      }
    }
  }
}

sub sysmetric_history {
  my $connect_s = shift;
  my $file      = shift;
  my $type      = shift;
  my $instname  = shift;
  my $result    = "";

  $result = qx {$odb_ic/sqlplus -S $connect_s \@$sql_dir\/$file};

  $result =~ s/[\n]+//g;
  if ( $type eq "RAC" ) {
    work_result( $result, $type, $instname );
  }
  else {
    work_result( $result, $type );
  }
}

sub work_result {
  my $result   = shift;
  my $type     = shift;
  my $instname = shift;
  my @res_arr  = split( /\|/, $result );
  if ( $type eq "RAC" ) {
    for my $i ( 0 .. $#res_arr ) {
      my @arr  = split( ";;;", $res_arr[$i] );
      my $name = pop(@arr);
      pop(@arr);
      for my $j ( 0 .. $#arr ) {
        my @line = split( ";", $arr[$j] );
        $line[3] =~ s/,/./g;
        if ( $line[3] =~ /^\./ ) {
          my $added_zero = "0" . "$line[3]";
          $hash{$type}{$instname}{$name}{ $line[1] } = $added_zero;
        }
        else {
          $hash{$type}{$instname}{$name}{ $line[1] } = $line[3];
        }
      }
    }
  }
  else {
    for my $i ( 0 .. $#res_arr ) {
      my @arr  = split( ";;;", $res_arr[$i] );
      my $name = pop(@arr);
      pop(@arr);
      for my $j ( 0 .. $#arr ) {
        my @line = split( ";", $arr[$j] );
        $line[3] =~ s/,/./g;
        if ( $line[3] =~ /^\,/ ) {
          my $added_zero = "0" . "$line[3]";
          $hash{$type}{$name}{ $line[1] } = $added_zero;
        }
        else {
          $hash{$type}{$name}{ $line[1] } = $line[3];
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

