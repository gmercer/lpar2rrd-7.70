use 5.008_008;

use strict;
use warnings;

use Kubernetes;
use HostCfg;
use Data::Dumper;
use JSON;
use MIME::Base64;
use Xorux_lib;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $cfgdir   = "$inputdir/etc/web_config";

# get parameters
if ( scalar(@ARGV) < 5 ) {
  print STDERR "error: expected three parameters <host> <token> <protocol> <alias> <platform>\n";
  exit 2;
}

my ( $host, $token, $protocol, $alias, $platform ) = @ARGV;

&testConnection();

sub testConnection {
  my $kubernetes = Kubernetes->new( 'fake', $host, $token, $protocol );

  my $test = $kubernetes->apiTest();

  my $namespaces = $kubernetes->getNamespaces();

  if ( scalar @{$namespaces} >= 1 ) {
    my $cfg_json = '';
    if ( open( my $fh, '<', "$cfgdir/hosts.json" ) ) {
      while ( my $row = <$fh> ) {
        chomp $row;
        $cfg_json .= $row;
      }
      close($fh);
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

    @{ $cfg_hash->{platforms}->{$platform}->{aliases}->{$alias}->{'available_namespaces'} } = @{$namespaces};

    my $json_print = JSON->new->allow_nonref;
    if ( open( my $cfg, ">$cfgdir/hosts.json" ) ) {
      print $cfg $json_print->pretty->encode( \%{$cfg_hash} );
      close $cfg;
    }
    else {
      warn( localtime() . ": Cannot open the file hosts.json ($!)" ) && next;
      next;
    }
  }

  if ( defined $test->{items}[0] ) {
    my $count = scalar @{ $test->{items} };
    Xorux_lib::status_json( 1, "Connected to Kubernetes, found $count nodes" );
  }
  else {
    Xorux_lib::status_json( 0, "No nodes reached" );
  }
}
