use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;

my ( $host, $port, $message ) = @ARGV;

if ( !defined($port) || $port eq '' ) {
  print "usage:  perl bin/conntest_udp.pl <host> <port> \n";
  exit 2;
}
if ( !defined($message) || $message eq '' ) {
  $message = "ERROR";
}

sub scanUDP {
  my $address = shift;
  my $port    = shift;
  my $socket  = new IO::Socket::INET(
    PeerAddr => $address,
    PeerPort => $port,
    Proto    => 'udp',
  ) or return 0;
  $socket->send( 'Hello', 0 );
  my $select = new IO::Select();
  $select->add($socket);
  my @socket = $select->can_read(1);
  if ( @socket == 1 ) {
    $socket->recv( my $temp, 1, 0 ) or return 0;
    return 1;
  }
  return 1;
}

my $ret = scanUDP( $host, $port );
if ( $ret == 1 ) {
  print "UDP connection to \"$host\" on port \"$port\" is ok\n";
  exit 0;
}

if ( $message =~ m/ERROR/ || $message =~ m/error/ ) {
  print "$message : UDP connection to \"$host\" on port \"$port\" has failed! Open it on firewall.\n";
}
else {
  print "$message : UDP connection to \"$host\" on port \"$port\" has failed! It might need to be open on the firewall.\n";
}
exit 1;
