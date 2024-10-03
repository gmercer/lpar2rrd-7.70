# nutanix-apitest.pl
# connection test to Nutanix API

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
use Nutanix;

# get parameters
if ( scalar(@ARGV) < 5 ) {
  print STDERR "error: expected three parameters <host> <port> <protocol> <username> <password> \n";
  exit 2;
}

my ( $host, $port, $protocol, $username, $password ) = @ARGV;

my $nutanix  = Nutanix->new( $protocol, $host, $port, $username, $password );
my $clusters = $nutanix->getClusters('v1');

if ( $clusters->{metadata}{totalEntities} >= 1 ) {
  Xorux_lib::status_json( 1, "Reached " . $clusters->{metadata}{totalEntities} . " clusters" );
}
else {
  Xorux_lib::status_json( 0, "No clusters reached" );
}
