use strict;
use warnings;
use Data::Dumper;
use Xorux_lib;
use DBI;

if ( scalar(@ARGV) < 6 ) {

  #if ( scalar( @ARGV ) < 3 ) {
  print STDERR "error: expected five parameters <database name> <host> <port> <type> <username> <password> \n";
  exit 2;
}

my ( $db_name, $host, $port, $type, $username, $password ) = @ARGV;
my $alias = "";

#?my $type         = $creds{$alias}{type};
my $inputdir = $ENV{INPUTDIR};
my $DB2_CLI_DRIVER_INSTALL_PATH = $ENV{DB2_CLI_DRIVER_INSTALL_PATH};
my $output   = "";
my %creds;
my $time = time();
my $ft   = filetime();
my %hash;
my %query = (
  "members" => "
    SELECT
      MEMBER,AGENTS_TOP,NUM_POOLED_AGENTS,NUM_ASSOC_AGENTS,NUM_COORD_AGENTS,NUM_LOCKS_HELD,NUM_LOCKS_WAITING,LOCK_ESCALS,LOCK_TIMEOUTS,DEADLOCKS,
      pool_data_l_reads + pool_temp_data_l_reads +pool_index_l_reads + pool_temp_index_l_reads +pool_xda_l_reads + pool_temp_xda_l_reads as LOGICAL_READS,
      pool_data_p_reads + pool_temp_data_p_reads +pool_index_p_reads + pool_temp_index_p_reads +pool_xda_p_reads + pool_temp_xda_p_reads as PHYSICAL_READS,
      POOL_DATA_WRITES + POOL_INDEX_WRITES + POOL_XDA_WRITES as WRITES,DIRECT_READS,DIRECT_WRITES,DIRECT_READ_TIME,POOL_READ_TIME,POOL_WRITE_TIME,
      ROWS_MODIFIED,ROWS_RETURNED,ROWS_READ,ROWS_UPDATED,ROWS_DELETED,ROWS_INSERTED,INT_ROWS_DELETED,INT_ROWS_INSERTED,INT_ROWS_UPDATED,FED_ROWS_DELETED,
      FED_ROWS_INSERTED,FED_ROWS_UPDATED,FED_ROWS_READ,TCPIP_SEND_VOLUME,TCPIP_RECV_VOLUME,IPC_SEND_VOLUME,IPC_RECV_VOLUME,FCM_SEND_VOLUME,FCM_RECV_VOLUME,
      PKG_CACHE_INSERTS,PKG_CACHE_LOOKUPS,TOTAL_APP_COMMITS,TOTAL_APP_ROLLBACKS,DIRECT_WRITE_TIME,
      LOG_DISK_WAIT_TIME,TCPIP_SEND_WAIT_TIME,TCPIP_RECV_WAIT_TIME,IPC_SEND_WAIT_TIME,IPC_RECV_WAIT_TIME,FCM_SEND_WAIT_TIME,FCM_RECV_WAIT_TIME,CF_WAIT_TIME,
      CLIENT_IDLE_WAIT_TIME,LOCK_WAIT_TIME,AGENT_WAIT_TIME,WLM_QUEUE_TIME_TOTAL,
      CONNECTIONS_TOP, TOTAL_CONS,TOTAL_SEC_CONS,APPLS_CUR_CONS
     FROM TABLE(MON_GET_DATABASE(-2))"
);

#If ( !$DB2_CLI_DRIVER_INSTALL_PATH ) {
#  Xorux_lib::status_json( 0, "Some of these variables are not set</br> DB2_CLI_DRIVER_INSTALL_PATH: $DB2_CLI_DRIVER_INSTALL_PATH" );
#  exit 1;
#}

my $module = "DBD::DB2";
my $module_def = 1;
eval "use $module; 1" or $module_def = 0;
if ( !$module_def ) {
  Xorux_lib::status_json(0, "ERROR: $module is not installed. Read more here: https://www.ibm.com/support/pages/db2-perl-database-interface-luw");
}
require DBD::DB2::Constants;
require DBD::DB2;


if ( defined $type and $type eq "Standalone" ) {
  my $res = get_data("PERF", $db_name, $db_name, $host, $port, $username, $password);
  if ( $res and $res ne "err" and $res->{members}->{data}->[0] ) {
    Xorux_lib::status_json( 1, "Connection: OK" );
    exit 0;
  }
  else {
    Xorux_lib::status_json( 0, "Invalid data</br></br> DB2_CLI_DRIVER_INSTALL_PATH: $DB2_CLI_DRIVER_INSTALL_PATH" );
    exit 1;
  }
}
else {
  Xorux_lib::status_json( 0, "TYPE NOT DEFINED" );
  exit 1;
}

sub get_data {
  my $_type     = shift;
  my $_db_name  = shift;
  my $_db       = shift;
  my $_hostname = shift;
  my $_port     = shift;
  my $_user     = shift;
  my $_pass     = shift;



  my $string = "dbi:DB2:DATABASE=$_db; HOSTNAME=$_hostname; PORT=$_port; PROTOCOL=TCPIP; UID=$_user; PWD=$_pass;";
  my $dbh = DBI->connect($string, { PrintError => 0 } );

  my $result;

  my $time_is_now = time;
  my $err         = 0;
  $err = DBI->errstr;

  unless ($dbh) {
    my $err = DBI->errstr;
    Xorux_lib::status_json( 0, "ERROR:</br> $err" );
    exit 1;
  }


  my %_data;

  #trade
  for my $query_name ( keys %query ) {
    my $array_ref = get_query_result( $dbh, $query{$query_name} );
    $_data{$query_name}{data} = $array_ref;
    $_data{$query_name}{info}{db_name} = $_db_name;
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
