# azure-apitest.pl

use 5.008_008;

use strict;
use warnings;

use Azure;
use Data::Dumper;
use HostCfg;
use LWP::UserAgent;
use HTTP::Request;
use JSON qw(decode_json encode_json);
use POSIX ":sys_wait_h";
use POSIX;
use JSON;
use Xorux_lib;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $cfgdir   = "$inputdir/etc/web_config";

# get parameters
if ( scalar(@ARGV) < 2 ) {
  print STDERR "error: expected four parameters <host> <alias> \n";
  exit 2;
}

my ( $host, $alias ) = @ARGV;

&testConnection();

sub testConnection() {

  # read file
  my $cfg_json = '';
  if ( open( FH, '<', "$cfgdir/hosts.json" ) ) {
    while ( my $row = <FH> ) {
      chomp $row;
      $cfg_json .= $row;
    }
    close(FH);
  }
  else {
    warn( localtime() . ": Cannot open the file hosts.json ($!)" ) && next;
    next;
  }

  # decode JSON
  my $cfg_hash = decode_json($cfg_json);
  if ( ref($cfg_hash) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file hosts.json: missing data" ) && next;
  }

  my $lpar = $cfg_hash->{platforms}->{Azure}->{aliases}->{$alias};

  my $token = testToken( $lpar->{tenant}, $lpar->{client}, $lpar->{secret} );

  #my $token = 1;

  if ( length $token <= 10 ) {
    Xorux_lib::status_json( 0, "No authorization token is generated. Bad credentials" );
  }
  else {
    Xorux_lib::status_json( 1, "Test completed!" );
  }

}

sub testToken() {
  my $tenant = shift;
  my $client = shift;
  my $secret = shift;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  my %data;
  $data{grant_type}    = "client_credentials";
  $data{client_id}     = $client;
  $data{client_secret} = $secret;
  $data{resource}      = "https://management.azure.com/";

  my $response = $ua->post( "https://login.microsoftonline.com/$tenant/oauth2/token", \%data );

  if ( $response->is_success ) {
    my $resp = $json->decode( $response->content );

    #print Dumper($resp);

    return $resp->{access_token};
  }
  else {
    return 0;
  }

}
