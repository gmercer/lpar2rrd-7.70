use strict;
use warnings;
use Data::Dumper;
use Xorux_lib;
use HostCfg;

if ( scalar(@ARGV) < 6 ) {

  #if ( scalar( @ARGV ) < 3 ) {
  print STDERR "error: expected five parameters <database name> <host> <port> <type> <username> <password> \n";
  exit 2;
}
my %creds = %{ HostCfg::getHostConnections("OracleDB") };

my ( $db_name, $host, $port, $type, $username, $password ) = @ARGV;
my $alias = "";

#?my $type         = $creds{$alias}{type};
$ENV{'NLS_LANG'} = "AMERICAN_CZECH REPUBLIC.AL32UTF8";
my $inputdir    = $ENV{INPUTDIR};
my $ORACLE_BASE = $ENV{ORACLE_BASE};
my $ORACLE_HOME = $ENV{ORACLE_HOME};
my $LIBPATH     = $ENV{LIBPATH};
my $LD_LIBPATH  = $ENV{LD_LIBRARY_PATH};
my $sql_dir     = "$inputdir/oracledb-sql";

my $tcps_check = $creds{$alias}{useSSL};
my $tcp        = "TCP";

if ( defined $tcps_check and $tcps_check eq "true" ) {
  $tcp = "TCPS";
}

my $output       = "";
my @host_aliases = keys %creds;
my $connect_str_sanitized;
if ( !$ORACLE_HOME or !$ORACLE_BASE ) {
  Xorux_lib::status_json( 0, "Some of these variables are not set</br> ORACLE_BASE: $ORACLE_BASE</br> ORACLE_HOME: $ORACLE_HOME" );
  exit 1;
}
unless ( -f "$ORACLE_HOME/sqlplus" or -f "$ORACLE_HOME/bin/sqlplus" ) {
  Xorux_lib::status_json( 0, "There is not sqlplus in $ORACLE_HOME or $ORACLE_HOME/bin" );
  exit 1;
}
my $odb_ic;

if ( -f "$ORACLE_HOME/sqlplus" ) {
  $odb_ic = $ORACLE_HOME;
}
elsif ( -f "$ORACLE_HOME/bin/sqlplus" ) {
  $odb_ic = "$ORACLE_HOME/bin";
}

#    # warn "$host $username $password";
#    my $output = `$perl $bindir/oracleDB-contest.pl "XE" "10.22.111.88" "1521" "Standalone" "LPAR2RRD" "xorux4you"`;
#    #print $output;
#    result(0,"$output");
#   exit;
unless ( -d $sql_dir ) {
  Xorux_lib::status_json( 0, "lpar2rrd/oracledb-sql doesn't exist" );
  exit 1;
}

my $time = time();
my $ft   = filetime();
my %hash;

if ( defined $type and $type eq "Standalone" ) {
  standalone_db( $username, $password, $host, $port, $db_name );
  if (%hash) {
    Xorux_lib::status_json( 1, "Standalone data: OK" );
    exit 0;
  }
  else {
    Xorux_lib::status_json( 0, "Invalid data make sure DB has permissions it needs .</br> </br> ORACLE_BASE: $ORACLE_BASE</br> ORACLE_HOME: $ORACLE_HOME</br> LIBPATH(AIX): $LIBPATH</br> LD_LIBRARY_PATH(Linux): $LD_LIBPATH </br></br> Try this in your CLI if it doesn't work contact you DB administrator </br></br> $odb_ic/sqlplus -S -L $connect_str_sanitized \@$sql_dir\/Standalone_L.sql" );
    exit 1;
  }
}
elsif ( $type and $type eq "RAC" or $type eq "RAC_Multitenant" ) {
  rac( $username, $password, $port, $db_name );

  if (%hash) {
    Xorux_lib::status_json( 1, "RAC data: OK" );
    exit 0;
  }
  else {
    Xorux_lib::status_json( 0, "Invalid data make sure DB has permissions it needs .</br> </br> ORACLE_BASE: $ORACLE_BASE</br> ORACLE_HOME: $ORACLE_HOME</br> LIBPATH(AIX): $LIBPATH</br> LD_LIBRARY_PATH(Linux): $LD_LIBPATH </br></br> Try this in your CLI if it doesn't work contact you DB administrator </br></br> $odb_ic/sqlplus -S -L $connect_str_sanitized \@$sql_dir\/RAC_L.sql" );
    exit 1;
  }
}
elsif ( defined $type and $type eq "Multitenant" ) {
  multitenant( $username, $password, $host, $port, $db_name );
  if (%hash) {
    Xorux_lib::status_json( 1, "Multitenant data: OK" );
    exit 0;
  }
  else {
    Xorux_lib::status_json( 0, "Invalid data make sure DB has permissions it needs .</br> </br> ORACLE_BASE: $ORACLE_BASE</br> ORACLE_HOME: $ORACLE_HOME</br> LIBPATH(AIX): $LIBPATH</br> LD_LIBRARY_PATH(Linux): $LD_LIBPATH </br></br> Try this in your CLI if it doesn't work contact you DB administrator </br></br> $odb_ic/sqlplus -S -L $connect_str_sanitized \@$sql_dir\/Multitenant_L.sql" );
    exit 1;
  }
}
else {
  Xorux_lib::status_json( 0, "TYPE NOT DEFINED" );
  exit 1;
}

sub standalone_db {
  my $username = shift;
  my $password = shift;
  my $ip       = shift;
  my $port     = shift;
  my $db_name  = shift;

  #my $connect_s = "$username/$password"."@"."$ip".":$port/$db_name";
  my $connect_s = "$username/\'$password\'" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $ip . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $db_name . ')))"';
  $connect_str_sanitized = "$username/YOUR_PASSWORD" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $ip . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $db_name . ')))"';

  my @metrics = ("Standalone.sql");

  #tablespaces($connect_s, \@metrics,"Standalone");
  sysmetric_history( $connect_s, "Standalone_L.sql", "Standalone", $ip, $connect_str_sanitized );
}

sub rac {
  my $username = shift;
  my $password = shift;
  my $port     = shift;
  my $db_name  = shift;
  my @hosts    = split( / /, $host );
  my $ip       = $hosts[0];

  #my $connect_s = "$username/$password"."@"."$ip".":$port/$db_name";
  undef %hash;

  my @help_arr = @hosts;
  for my $i ( 0 .. $#help_arr ) {
    my $connect_s = "$username/\'$password\'" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $help_arr[$i] . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $db_name . ')))"';
    $connect_str_sanitized = "$username/YOUR_PASSWORD" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $help_arr[$i] . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $db_name . ')))"';

    #    $connect_s = "$username/$password"."@"."$help_arr[$i]".":$port/$db_name";
    sysmetric_history( $connect_s, "RAC_L.sql", "RAC", $help_arr[$i], $connect_str_sanitized );    #, $instances[$i]->{alias});
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
  $connect_str_sanitized = "$username/YOUR_PASSWORD" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $ip . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $db_name . ')))"';

  sysmetric_history( $connect_s, "Multitenant_L.sql", "Multitenant", $ip, $connect_str_sanitized, $db_name );

  if (@pdbs) {
    foreach my $pdb (@pdbs) {
      $connect_s             = "$username/$password" . "@" . "$ip" . ":$port/$pdb";
      $connect_str_sanitized = "$username/YOUR_PASSWORD" . "@" . '"(DESCRIPTION=(ADDRESS=(PROTOCOL=' . $tcp . ')(HOST=' . $ip . ')(PORT=' . $port . '))(CONNECT_DATA=(SERVICE_NAME=' . $pdb . ')))"';

      sysmetric_history( $connect_s, "PDB_L.sql", "PDB", $ip, $connect_str_sanitized, $pdb );
    }
  }
}

sub sysmetric_history {
  my $connect_s = shift;
  my $file      = shift;
  my $type      = shift;
  my $instname  = "";
  $instname              = shift;
  $connect_str_sanitized = shift;
  my $pdb    = shift;
  my $result = "";

  $result = qx {$odb_ic/sqlplus -S -L $connect_s \@$sql_dir\/$file; echo \"ret:\$?\"};
  if ( $result =~ /ret:1/ ) {
    if ( $result =~ /ret:127/ ) {
      Xorux_lib::status_json( 0, "$instname </br>Command not found, is the instantclient version in variables below correct?</br></br> ORACLE_BASE: $ORACLE_BASE</br> ORACLE_HOME: $ORACLE_HOME</br> LIBPATH(AIX): $LIBPATH</br> LD_LIBRARY_PATH(Linux): $LD_LIBPATH" );
      exit 1;
    }
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

    #$error_message = $err;
    Xorux_lib::status_json( 0, "$instname $err</br> ORACLE_BASE: $ORACLE_BASE</br> ORACLE_HOME: $ORACLE_HOME</br> LIBPATH(AIX): $LIBPATH</br> LD_LIBRARY_PATH(Linux): $LD_LIBPATH </br></br> Try this in your CLI if it doesn't work contact you DB administrator </br></br> $odb_ic/sqlplus -S -L $connect_str_sanitized \@$sql_dir\/$file" );
    exit 1;
  }
  else {
    $result =~ s/ret:0//g;
  }
  $result =~ s/[\n]+//g;
  if ( $type eq "RAC" ) {
    work_result( $result, $type, $instname );
  }
  elsif ( $type eq "PDB" ) {
    work_result( $result, $type, $instname, $pdb );
  }
  else {
    work_result( $result, $type );
  }
}

sub work_result {
  my $result   = shift;
  my $type     = shift;
  my $instname = shift;
  my $pdb      = shift;

  my @res_arr = split( /\|/, $result );
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
  elsif ( $type eq "PDB" ) {
    for my $i ( 0 .. $#res_arr ) {
      my @arr  = split( ";;;", $res_arr[$i] );
      my $name = pop(@arr);
      pop(@arr);
      for my $j ( 0 .. $#arr ) {
        my @line = split( ";", $arr[$j] );
        $line[3] =~ s/,/./g;
        if ( $line[3] =~ /^\./ ) {
          my $added_zero = "0" . "$line[3]";
          $hash{$type}{$pdb}{$name}{ $line[1] } = $added_zero;
        }
        else {
          $hash{$type}{$pdb}{$name}{ $line[1] } = $line[3];
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

