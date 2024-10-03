use strict;
use warnings;
use Xorux_lib qw(error);

defined $ENV{INPUTDIR} || Xorux_lib::error( 'INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir   = $ENV{INPUTDIR};
my $db_file    = "$inputdir/data/_DB/data.db";
my $touch_file = "$inputdir/tmp/db_cleanup.touch";
my $time_days  = 7;

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'db-cleanup.pl : first run, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "db-cleanup.pl  : already ran today, skip\n";
    exit(0);    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'db-cleanup.pl : remove object items that have not been recently updated, ' . localtime() . "\n";
  }
}

# run the database cleanup itself
require SQLiteDataWrapper;
SQLiteDataWrapper::deleteOlderItems( { days => $time_days } );

print 'db-cleanup.pl : finish ' . localtime() . "\n";
exit(0);
