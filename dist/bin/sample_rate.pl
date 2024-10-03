# usage
# cd /home/lpar2rrd/lpar2rrd
# . etc/lpar2rrd.cfg
# $PERL bin/sample_rate.pl
#

use strict;
use HostCfg;
use Data::Dumper;
my $SSH   = "ssh -q";
my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };
print Dumper \%hosts;
my @host_alias_list;
foreach my $h_alias ( keys %hosts ) {
  push( @host_alias_list, $h_alias );
}

my $hmc_user;

foreach my $host_alias (@host_alias_list) {    #since 23.11.18 use HostCfg, so the origial array @host_list is now @host_alias_list, then set $host to its value
  my $host = $hosts{$host_alias}{host};

  #use from host config 23.11.18 insted of $hmc_user=ENV{HMC_USER} (HD)
  $hmc_user = $hosts{$host_alias}{username};
  if ( $hosts{$host_alias}{auth_api} ) {
    print "Warn: you are using hmc rest api for $host ($host_alias), so ssh test can fail\n";
  }
  my @managednamelist_un = `$SSH $hmc_user\@$host "lssyscfg -r sys -F name,type_model,serial_num" 2>\&1`;
  my @managednamelist    = sort { lc($a) cmp lc($b) } @managednamelist_un;
  my $host_print         = sprintf( "%-20s", $host );

  # get data for all managed system which are conected to HMC
  foreach my $line (@managednamelist) {
    chomp($line);

    my ( $managedname, $model, $serial ) = split( /,/, $line );
    my $managedname_print = sprintf( "%-20s", $managedname );

    print "$host_print:$managedname_print: 5 x step (hmc ret code,ssh ret code): ";
    for ( my $i = 0; $i < 5; $i++ ) {
      my $return = `$SSH $hmc_user\@$host "lslparutil -r config -m $managedname -F sample_rate; echo $?" 2>\&1; echo "$?"`;
      ( my $step, my $hmc_code, my $ssh_code ) = split( /\n/, $return );
      chomp($step);
      chomp($hmc_code);
      chomp($ssh_code);

      #`$SSH $hmc_user\@$host "lslparutil -r config -m \\"$managedname\\" -F sample_rate" 2>\&1 >> xx` ;
      print "$step($hmc_code,$ssh_code),";
    }
    print "\n";
  }
}

