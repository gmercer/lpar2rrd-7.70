# gcloud-apitest.pl

use 5.008_008;

use strict;
use warnings;

use GoogleCloud;
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

  my $lpar = $cfg_hash->{platforms}->{GCloud}->{aliases}->{$alias};

  my $gcloud = GoogleCloud->new( $alias, $lpar->{credentials}, 0 );

  my $token = $gcloud->testToken();
  if ( length $token <= 10 ) {
    Xorux_lib::status_json( 0, "No authorization token is generated. Bad credentials or missing Google SDK" );
  }
  else {
    my $error = $gcloud->testInstances();
    if ( $error eq "0" ) {
      Xorux_lib::status_json( 1, "Test completed!" );
    }
    else {
      Xorux_lib::status_json( 0, "No instances! Bad credentials file?" );
    }
  }

}
