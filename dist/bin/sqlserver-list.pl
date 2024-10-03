use strict;
use warnings;
use HostCfg;

defined $ENV{INPUTDIR} || warn "Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg " && exit 1;
my $inputdir = $ENV{INPUTDIR};
my $bindir   = $ENV{BINDIR};

my %creds = %{ HostCfg::getHostConnections("SQLServer") };

my @host_aliases = keys %creds;
if ( !defined( keys %creds ) || !defined $host_aliases[0] ) {
  print "NO_SQLSERVER_HOSTS_FOUND\n";
}
else {
  foreach my $alias ( keys %creds ) {
    print "$alias ";
  }
}
