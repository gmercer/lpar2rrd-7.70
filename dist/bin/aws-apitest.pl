# aws-apitest.pl

use 5.008_008;

use strict;
use warnings;

use AmazonWebServices;
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
if ( scalar(@ARGV) < 4 ) {
  print STDERR "error: expected four parameters <host> <alias> <aws_access_key_id> <aws_secret_access_key> \n";
  exit 2;
}

my ( $host, $alias, $aws_access_key_id, $aws_secret_access_key ) = @ARGV;

&loadRegions();

sub loadRegions() {
  my $aws = AmazonWebServices->new('300');
  $aws->set_aws_access_key_id($aws_access_key_id);
  $aws->set_aws_secret_access_key($aws_secret_access_key);

  my $all_regions = $aws->get_all_regions();

  if ( ref($all_regions) eq 'ARRAY' ) {

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

    @{ $cfg_hash->{platforms}->{AWS}->{aliases}->{$alias}->{'available_regions'} } = @{$all_regions};

    my $json_print = JSON->new->allow_nonref;
    if ( open( CFG, ">$cfgdir/hosts.json" ) ) {
      print CFG $json_print->pretty->encode( \%{$cfg_hash} );
      close CFG;
    }
    else {
      warn( localtime() . ": Cannot open the file hosts.json ($!)" ) && next;
      next;
    }
    Xorux_lib::status_json( 1, "Regions updated" );
  }
  else {
    Xorux_lib::status_json( 0, "Bad Credentials" );
  }

}
