# gcloud-cleanup.pl
# remove unused data from GCloud

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use HostCfg;
use Xorux_lib qw(error file_time_diff);
use GCloudDataWrapper;

defined $ENV{INPUTDIR} || warn( " INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('GCloud') } == 0 ) {
  exit(0);
}

my $version     = "$ENV{version}";
my $inputdir    = "$ENV{INPUTDIR}";
my $wrkdir      = "$inputdir/data/GCloud";
my $compute_dir = "$wrkdir/compute";

my $touch_file  = "$inputdir/tmp/gcloud_cleanup.touch";
my $cleanup_log = "$inputdir/logs/erased.log-gcloud";
my $t3months    = 60 * 60 * 24 * 90;
my $label_json  = GCloudDataWrapper::get_labels();

my @compute_files = <$compute_dir/*.rrd>;
my $erased_count  = 0;

my $run_touch_file = "$inputdir/tmp/$version-gcloud";    # for generating menu

################################################################################

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'gcloud-cleanup.pl            : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "gcloud-cleanup.pl            : already ran today, skip\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'gcloud-cleanup.pl            : removing performance data older than 3 months, ' . localtime() . "\n";

    # also force new menu generation
    # note: technically this should be at the end of the script, if `load.sh` may run concurrently
    `touch $run_touch_file`;
  }
}

open my $LOGH, '>', $cleanup_log || warn( "Could not open file $cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'GCloud erase : start ' . localtime() . "\n";

foreach my $file (@compute_files) {
  $file =~ /$compute_dir\/(.*)\.rrd/;
  my $compute_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{compute}{$compute_uuid} ) {
    my @files_to_remove = <$compute_dir/$compute_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "GCloud Compute to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

print $LOGH 'GCloud erase : finish ' . localtime() . ", erased $erased_count RRD files\n";
close $LOGH;
print 'gcloud-cleanup.pl            : finish ' . localtime() . ", erased $erased_count RRD files\n";
exit 0;
