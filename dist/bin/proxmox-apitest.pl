# proxmox-apitest.pl
# connection test to Proxmox API

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
use Proxmox;

# get parameters
if ( scalar(@ARGV) < 5 ) {
  print STDERR "error: expected three parameters <host> <port> <protocol> <username> <password> <domain>\n";
  exit 2;
}

my ( $host, $port, $protocol, $username, $password ) = @ARGV;

my $proxmox = Proxmox->new( $protocol, $host, $port );
my $auth    = $proxmox->authCredentials( $username, $password, 'pve' );

my $nodes = $proxmox->getNodes();
if ( defined $nodes->{data}[0] ) {
  my $count = scalar @{ $nodes->{data} };
  Xorux_lib::status_json( 1, "Connected to Proxmox, found $count nodes" );
}
else {
  Xorux_lib::status_json( 0, "Connected to Proxmox, but no nodes reached" );
}
