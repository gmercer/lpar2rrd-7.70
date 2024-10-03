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
my $output   = "";
my %creds;
my $time = time();
my $ft   = filetime();
my %hash;

my %query = (
  "_dbs"     => "SELECT datid, datname, blks_read, blks_hit, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted, xact_commit, xact_rollback, deadlocks,            temp_files,temp_bytes FROM pg_stat_database;",
  "_cluster" => "SELECT buffers_backend, buffers_clean, buffers_checkpoint, checkpoints_req, checkpoints_timed FROM pg_stat_bgwriter;"
);

if ( defined $type and $type eq "Standalone" ) {
  my $res = get_data("_dbs");
  if ( $res->[0] ) {
    Xorux_lib::status_json( 1, "Standalone data: OK" );
    exit 0;
  }
  else {
    Xorux_lib::status_json( 0, "Invalid data</br>" );
    exit 1;
  }
}
else {
  Xorux_lib::status_json( 0, "TYPE NOT DEFINED" );
  exit 1;
}

sub get_data {
  my $type = shift;
  my $result;
  if ( $type and $query{$type} ) {
    my @array;
    my $dbh = DBI->connect( "DBI:Pg:dbname=$db_name;host=$host;port=$port", "$username", "$password", { PrintError => 1 } );

    unless ($dbh) {
      my $err = DBI->errstr;
      if ( $err =~ /SCRAM/ ) {
        Xorux_lib::status_json( 0, "ERROR:</br> $err</br> </br>Either upgrade libpq to version 10 and above or change users password authentication to md5 and generate new password" );
      }
      else {
        Xorux_lib::status_json( 0, "ERROR:</br> $err" );
      }
      exit 1;
    }

    my $sth = $dbh->prepare( $query{$type} );

    #$sth = $dbh->prepare("show all;");
    $sth->execute();

    while ( my $ref = $sth->fetchrow_hashref() ) {
      push( @array, $ref );
    }

    # clean up
    $dbh->disconnect();

    return \@array;
  }
  return [];
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
