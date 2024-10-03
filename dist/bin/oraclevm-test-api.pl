# xen-test-xapi.pl
# test connection & authentication to XAPI web server on a XenServer host

use strict;
use warnings;
use LWP::UserAgent;
use JSON qw(encode_json);
use Data::Dumper;
use Xorux_lib;

# get parameters
if ( scalar(@ARGV) < 5 ) {
  print STDERR "error: expected three parameters <host> <port> <protocol> <username> <password> \n";
  exit 2;
}

my ( $host, $port, $protocol, $username, $password ) = @ARGV;

# sample file to download
my $url = "https://$host:$port/ovm/core/wsapi/rest/Manager";

my %test_result;

# download dumped RRD as XML
my $ua = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 } );
$ua->timeout(5);
my $req = HTTP::Request->new( GET => $url );
$req->content_type('application/xml');
$req->header( 'Accept' => '*/*' );
$req->authorization_basic( "$username", "$password" );
my $res = $ua->request($req);

if ( $res->is_success ) {
  if ( $res->{_content} eq "" ) {
    Xorux_lib::status_json( 0, "connected to Oracle VM, but response is empty" );
    exit 1;
  }
  else {
    Xorux_lib::status_json( 1, "successfully connected" );

    # warn Dumper $res->{_content};
    exit 0;
  }
}
else {
  Xorux_lib::status_json( 0, $res->status_line );
  exit 1;
}
