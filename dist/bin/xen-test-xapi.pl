# xen-test-xapi.pl
# test connection & authentication to XAPI web server on a XenServer host

use 5.008_008;

use strict;
use warnings;
use LWP::UserAgent;
use JSON qw(encode_json);
use Xorux_lib;

# get parameters
if ( scalar(@ARGV) < 5 ) {
  print STDERR 'error: expected three parameters <host> <port> <protocol> <username> <password>' . "\n";
  exit 2;
}

my ( $host, $port, $protocol, $username, $password ) = @ARGV;

# sample file to download
my $rrdfile    = 'rrd_updates';
my $start_time = time();
my $db_url     = "$protocol://$host:$port/$rrdfile?start=$start_time&cf=AVERAGE";

my %test_result;

# download dumped RRD as XML
my $ua = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 } );
$ua->timeout(10);
my $req = HTTP::Request->new( GET => $db_url );
$req->content_type('application/xml');
$req->header( 'Accept' => '*/*' );
$req->authorization_basic( "$username", "$password" );
my $res = $ua->request($req);

if ( $res->is_success ) {
  if ( $res->{_content} eq '' ) {
    Xorux_lib::status_json( 0, 'connected to XenServer, but data are empty' );
    exit 1;
  }
  else {
    Xorux_lib::status_json( 1, 'downloaded XenServer data dump from XAPI' );
    exit 0;
  }
}
else {
  Xorux_lib::status_json( 0, $res->status_line );
  exit 1;
}
