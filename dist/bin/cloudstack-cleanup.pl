# cloudstack-cleanup.pl
# remove unused data from CloudStack

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use HostCfg;
use Xorux_lib qw(error file_time_diff);
use CloudstackDataWrapper;

defined $ENV{INPUTDIR} || warn( " INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('Cloudstack') } == 0 ) {
  exit(0);
}

my $version      = "$ENV{version}";
my $inputdir     = "$ENV{INPUTDIR}";
my $wrkdir       = "$inputdir/data/Cloudstack";
my $instance_dir = "$wrkdir/Instance";
my $volume_dir   = "$wrkdir/Volume";
my $host_dir     = "$wrkdir/Host";

my $touch_file  = "$inputdir/tmp/cloudstack_cleanup.touch";
my $cleanup_log = "$inputdir/logs/erased.log-cloudstack";
my $t3months    = 60 * 60 * 24 * 90;
my $label_json  = CloudstackDataWrapper::get_labels();

my @instance_files = <$instance_dir/*.rrd>;
my @volume_files   = <$volume_dir/*.rrd>;
my @host_files     = <$host_dir/*.rrd>;
my $erased_count   = 0;

my $run_touch_file = "$inputdir/tmp/$version-cloudstack";    # for generating menu

################################################################################

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'cloudstack-cleanup.pl     : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "cloudstack-cleanup.pl     : already ran today, skip\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'cloudstack-cleanup.pl     : removing performance data older than 3 months, ' . localtime() . "\n";

    # also force new menu generation
    # note: technically this should be at the end of the script, if `load.sh` may run concurrently
    `touch $run_touch_file`;
  }
}

open my $LOGH, '>', $cleanup_log || warn( "Could not open file $cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'Cloudstack erase : start ' . localtime() . "\n";

foreach my $file (@instance_files) {
  $file =~ /$instance_dir\/(.*)\.rrd/;
  my $instance_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{instance}{$instance_uuid} ) {
    my @files_to_remove = <$instance_dir/$instance_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Cloudstack Instance to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@volume_files) {
  $file =~ /$volume_dir\/(.*)\.rrd/;
  my $volume_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{volume}{$volume_uuid} ) {
    my @files_to_remove = <$volume_dir/$volume_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Cloudstack Volume to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@host_files) {
  $file =~ /$host_dir\/(.*)\.rrd/;
  my $host_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{host}{$host_uuid} ) {
    my @files_to_remove = <$host_dir/$host_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Cloudstack Host to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

print $LOGH 'Cloudstack erase : finish ' . localtime() . ", erased $erased_count RRD files\n";
close $LOGH;
print 'cloudstack-cleanup.pl     : finish ' . localtime() . ", erased $erased_count RRD files\n";
exit 0;
