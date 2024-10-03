# fusioncompute-apitest.pl
# connection test to FusionCompute API

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
use FusionCompute;

# get parameters
if ( scalar(@ARGV) < 6 ) {
  print STDERR "error: expected three parameters <host> <port> <protocol> <username> <password> <type>\n";
  exit 2;
}

my ( $host, $port, $protocol, $username, $password, $type, $version ) = @ARGV;

my $encrypted = 1;
eval {
  require Digest::SHA;
  $password = Digest::SHA::sha256_hex($password);
};

if ($@) {
  $encrypted = 0;
}

my $fusioncompute = FusionCompute->new( $protocol, $host, $port, $version );
my $auth          = $fusioncompute->auth( $username, $password, $type, $encrypted );

my $sites = $fusioncompute->listSites();

if (!defined $sites) {
  Xorux_lib::status_json( 0, "Can not find sites, bad credentials or user type" );
}

if ( defined $sites->{sites}[0] ) {
  Xorux_lib::status_json( 1, "Connected to FusionCompute" );
}
else {
  if ( defined $sites->{errorDes} ) {
    Xorux_lib::status_json( 0, $sites->{errorDes} );
  }
  else {
    Xorux_lib::status_json( 0, "Can not find sites, bad credentials or user type" );
  }
}
