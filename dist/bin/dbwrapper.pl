# generates JSON menu parts for fancyTree JS component (see https://github.com/mar10/fancytree)
use strict;
use warnings;

use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;

use JSON 'decode_json';
use Xorux_lib qw(parse_url_params);

require SQLiteDataWrapper;

my $basedir = $ENV{INPUTDIR} ||= "/home/lpar2rrd/lpar2rrd";

print "Content-type: application/json\n\n";

my $params = getURLparams();

# print STDERR Dumper ("dbwrapper.pl 19 params",\$params);
if ( $params->{procname} ) {
  my $result = SQLiteDataWrapper->can( $params->{procname} )->($params);

  # print STDERR Dumper("22 result",\$result);
  print JSON->new->utf8(0)->pretty()->encode($result);
  exit;
}

### get URL parameters (could be GET or POST) and put them into hash %PAR
sub getURLparams {
  my ( $buffer, $PAR );

  if ( $ENV{'REQUEST_METHOD'} && lc $ENV{'REQUEST_METHOD'} eq "post" ) {
    read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
  }
  else {
    if ( $ENV{'QUERY_STRING'} ) {
      $buffer = $ENV{'QUERY_STRING'};
    }
  }

  # Split information into name/value pairs
  if ($buffer) {
    if ( $buffer =~ m/^\{.*\}$/ ) {
      return decode_json($buffer);
    }
    else {
      $PAR = Xorux_lib::parse_url_params($buffer);
    }
  }
  return $PAR;
}
