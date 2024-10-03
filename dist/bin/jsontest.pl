# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=perl
use strict;
use warnings;

use JSON::PP qw(encode_json decode_json);

my $filename;

if (@ARGV) {
  $filename = $ARGV[0];
}

if ( $filename && open( FILE, "<$filename" ) ) {
  eval {
    #my $json = new JSON;
    #my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode(<FILE>);
    local $/;

    #my %alerts = %{ decode_json <FILE> };
    #decode_json <FILE>;
    my $json_text   = <FILE>;
    my $perl_scalar = decode_json($json_text);
    print "Tested JSON file [$filename] contains no syntax errors\n";
  };
  if ($@) {
    print "[[JSON ERROR]] JSON parser crashed! $@\n";
  }
}

