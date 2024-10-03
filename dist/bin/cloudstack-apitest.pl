# cloudstack-apitest.pl
# connection test to CloudStack API

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use HostCfg;
use LWP::UserAgent;
use HTTP::Request;
use JSON qw(decode_json encode_json);
use POSIX ":sys_wait_h";
use POSIX;
use JSON;
use Xorux_lib;
use Cloudstack;

# get parameters
if ( scalar(@ARGV) < 5 ) {
  print STDERR "error: expected three parameters <host> <port> <protocol> <username> <password> \n";
  exit 2;
}

my ( $host, $port, $protocol, $username, $password ) = @ARGV;

my $cloudstack = Cloudstack->new( "apitest", $protocol, $host . ":" . $port );
my $session    = $cloudstack->auth( $username, $password );

my $hosts = $cloudstack->getHosts();

if ( defined $hosts->{listhostsresponse}{host}[0] ) {
  my $count = scalar @{ $hosts->{listhostsresponse}{host} };
  Xorux_lib::status_json( 1, "Connected to CloudStack, found $count hosts" );
}
else {
  Xorux_lib::status_json( 0, "Connected to CloudStack, but no hosts reached" );
}
