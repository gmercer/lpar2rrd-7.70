use strict;
use warnings;
use HostCfg;

defined $ENV{INPUTDIR} || error( " Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $inputdir = $ENV{INPUTDIR};
my $bindir   = $ENV{BINDIR};

my %creds = %{ HostCfg::getHostConnections("PostgreSQL") };

my @host_aliases = keys %creds;
if ( !defined( keys %creds ) || !defined $host_aliases[0] ) {
  print "NO_POSTGRES_HOSTS_FOUND\n";
}
else {
  foreach my $alias ( keys %creds ) {
    print "$alias ";
  }
}

