#!/usr/bin/perl -pi
# multi-line in place substitute
use strict;
use warnings;

BEGIN { undef $/; }

my $new_sub = 'sub escape_char {
    # Old versions of utf8::is_utf8() didn\'t properly handle magical vars (e.g. $1).
    # The following forces a fetch to occur beforehand.
    my $dummy = substr($_[0], 0, 0);

    if (utf8::is_utf8($_[0])) {
        my $s = shift;
        utf8::encode($s);
        unshift(@_, $s);
    }

    return join \'\', @URI::Escape::escapes{split //, $_[0]};
}';

s/sub escape_char \{.*^\}/$new_sub/smg;
