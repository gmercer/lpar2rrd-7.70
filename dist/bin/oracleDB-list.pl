use strict;
use warnings;
use HostCfg;
use XoruxEdition;

defined $ENV{INPUTDIR} || error( " Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $inputdir     = $ENV{INPUTDIR};
my $bindir       = $ENV{BINDIR};
my $log_err_file = "$inputdir/html/.b";

my %creds   = %{ HostCfg::getHostConnections("OracleDB") };
my $log_err = "L_ERR";

my $log_err_v = premium();

my @host_aliases = keys %creds;
if ( !defined( keys %creds ) || !defined $host_aliases[0] ) {
  print "NO_ORACLEDB_HOSTS_FOUND\n";
}
else {
  my $error = 0;
  foreach my $alias ( keys %creds ) {
    if ( $creds{$alias}{type} eq "Standalone" ) {
      print "$creds{$alias}{type},$alias,$creds{$alias}{host} ";
    }
    elsif ( $creds{$alias}{type} eq "Multitenant" ) {
      print "$creds{$alias}{type},$alias,$creds{$alias}{host} ";
    }
    else {
      if ( ( ( length($log_err_v) + 1 ) == length($log_err) || !-e $log_err_file ) && $error >= 1 ) {
      }
      else {
        print "$creds{$alias}{type},$alias ";
      }
      $error++;
    }
  }
}

