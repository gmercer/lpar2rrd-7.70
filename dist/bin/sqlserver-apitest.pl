use strict;
use warnings;

use SQLServerDataWrapper;
use Data::Dumper;
use Xorux_lib;
use DBI;

if ( scalar(@ARGV) < 6 ) {
  print STDERR "error: expected five parameters <database name> <host> <port> <type> <username> <password> \n";
  exit 2;
}

my ( $db_name, $host, $port, $type, $username, $password ) = @ARGV;

my $inputdir = $ENV{INPUTDIR};
my $home_dir = "$inputdir/data/SQLServer";
my $output   = "";
my $time     = time();
my $ft       = filetime();
my $err;
my %hash;
my $odbc_inst   = "/etc/odbcinst.ini";
my $driver_file = "$home_dir/sqlserver_driver.txt";

my $driver = SQLServerDataWrapper::get_driver();
chomp($driver);

if ( $driver eq "err-incodriver" ) {
  my $cat = `cat $driver_file`;
  Xorux_lib::status_json( 0, "Incorrect driver in the file \"$driver_file\" </br>FILE contents: $cat" );
  exit 1;
}
elsif ( $driver eq "err-driverne" ) {
  my $cat = `cat $odbc_inst`;
  $cat =~ s/\n/<br>/g;
  Xorux_lib::status_json( 0, "Could't find suitable driver in the file \"$odbc_inst\" </br>FILE contents:</br> $cat" );
  exit 1;
}
elsif ( $driver eq "err-instne" ) {
  Xorux_lib::status_json( 0, "File \"$odbc_inst\" doesn't exist. Have you installed unixODBC?" );
  exit 1;
}

if ( defined $type and $type eq "Standalone" ) {
  my $res = get_data( $driver, $host, $db_name, $port, $username, $password );
  if ( $res and $res ne "err" and $res->{virtual}->{data}->[0] ) {
    Xorux_lib::status_json( 1, "Connection: OK" );
    exit 0;
  }
  elsif ( $res eq "err" ) {
    Xorux_lib::status_json( 0, "Invalid data</br>SQLSERVER_DRIVER: $driver </br></br> ERROR: $err" );
    exit 1;
  }
}
else {
  Xorux_lib::status_json( 0, "TYPE NOT DEFINED" );
  exit 1;
}

sub get_data {
  my $_driver   = shift;
  my $_ip       = shift;
  my $_database = shift;
  my $_port     = shift;
  my $_user     = shift;
  my $_password = shift;

  my $dbh = DBI->connect(
    "DBI:ODBC:driver=$_driver;Server=$_ip,$_port;database=$_database;Encrypt=no",
    $_user, $_password, { PrintError => 0, RaiseError => 0 }
  );
  my $time_is_now = time;
  $err = DBI->errstr;

  #warn "ERROR $err";

  if ( !( defined $dbh ) ) {
    return "err";
  }

  my %_data;
  my %queries = %{ get_queries() };

  #trade
  for my $query_name ( keys %queries ) {
    my $array_ref = get_query_result( $dbh, $queries{$query_name} );
    $_data{$query_name}{data} = $array_ref;
    $_data{$query_name}{info}{db_name} = $_database;
  }

  # clean up
  $dbh->disconnect();

  return \%_data;
}

sub get_query_result {
  my $_dbh  = shift;
  my $query = shift;
  my @array;

  #warn $query;
  my $sth = $_dbh->prepare($query);
  $sth->execute();
  while ( my $ref = $sth->fetchrow_hashref() ) {
    push( @array, $ref );
  }

  return \@array;
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

sub get_queries {
  my $virtual = q(
  SELECT name
      ,SUM(num_of_reads) AS 'io_rd'
      ,SUM(num_of_writes) AS 'io_wr'
      ,SUM(num_of_reads + num_of_writes) AS 'io_total'
      ,SUM(num_of_bytes_read / 1024) AS 'data_rd'
      ,SUM(num_of_bytes_written / 1024) AS 'data_wr'
      ,SUM((num_of_bytes_read + num_of_bytes_written) / 1024) AS 'data_total'
      ,CAST(SUM(io_stall_read_ms) / (1.0 + SUM(num_of_reads)) AS NUMERIC(10,1)) AS 'latency_rd'
      ,CAST(SUM(io_stall_write_ms) / (1.0 + SUM(num_of_writes) ) AS NUMERIC(10,1)) AS 'latency_wr'
      ,CAST(SUM(io_stall) / (1.0 + SUM(num_of_reads + num_of_writes)) AS NUMERIC(10,1)) AS 'latency_total'
  FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS I
    INNER JOIN sys.databases AS D  
      ON I.database_id = d.database_id
  GROUP BY name ORDER BY 'name' DESC;
  );

  my %queries = (
    virtual => $virtual,

    #    waitevents  => $waitevents,
  );

  return \%queries;
}
