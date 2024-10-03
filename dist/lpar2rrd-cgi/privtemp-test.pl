#!/usr/bin/perl

use strict;
use warnings;

print "Content-type: text/plain\n\n";

# print "PID: $$\n";
# my $ppid = getppid();
# print "PPID: $ppid\n";

my $lines = `cat "/proc/$$/mountinfo"`;

# print $lines;

if ($lines =~ /systemd-private/) {
	print "Private temp found\n";
}
else {
	print "Private temp not found\n";
}
