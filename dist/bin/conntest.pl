use strict;
use warnings;
use IO::Socket::INET;

my ( $host, $port, $message ) = @ARGV;

if ( !defined($port) || $port eq '' ) {
  print "usage:  perl bin/conntest.pl <host> <port> \n";
  exit 2;
}
if ( !defined($message) || $message eq '' ) {
  $message = "ERROR";
}
my $sock = IO::Socket::INET->new(
  PeerAddr => $host,
  PeerPort => $port,
  Proto    => 'tcp',
  Timeout  => 5
);

if ($sock) {

  #print "Alive!\n";
  print "Connection to \"$host\" on port \"$port\" is ok\n";
  close($sock);
  exit 0;
}
else {
  if ( $message =~ m/ERROR/ || $message =~ m/error/ ) {
    print "$message : connection to \"$host\" on port \"$port\" has failed! Open it on the firewall.\n";
  }
  else {
    print "$message : connection to \"$host\" on port \"$port\" has failed! It might need to be open the firewall.\n";
  }
  exit 1;
}
