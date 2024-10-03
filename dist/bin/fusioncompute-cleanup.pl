# fusioncompute-cleanup.pl
# remove unused data from FusionCompute

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use HostCfg;
use Xorux_lib qw(error file_time_diff);
use FusionComputeDataWrapper;

defined $ENV{INPUTDIR} || warn( " INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('FusionCompute') } == 0 ) {
  exit(0);
}

my $version       = "$ENV{version}";
my $inputdir      = "$ENV{INPUTDIR}";
my $wrkdir        = "$inputdir/data/FusionCompute";
my $vm_dir        = "$wrkdir/VM";
my $host_dir      = "$wrkdir/Host";
my $cluster_dir   = "$wrkdir/Cluster";
my $datastore_dir = "$wrkdir/Datastore";

my $touch_file  = "$inputdir/tmp/fusioncompute_cleanup.touch";
my $cleanup_log = "$inputdir/logs/erased.log-fusioncompute";
my $t3months    = 60 * 60 * 24 * 90;
my $label_json  = FusionComputeDataWrapper::get_labels();

my @vm_files        = <$vm_dir/*.rrd>;
my @host_files      = <$host_dir/*.rrd>;
my @cluster_files   = <$cluster_dir/*.rrd>;
my @datastore_files = <$datastore_dir/*.rrd>;
my $erased_count    = 0;

my $run_touch_file = "$inputdir/tmp/$version-fusioncompute";    # for generating menu

################################################################################

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'fusioncompute-cleanup.pl  : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "fusioncompute-cleanup.pl  : already ran today, skip\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'fusioncompute-cleanup.pl  : removing performance data older than 3 months, ' . localtime() . "\n";

    # also force new menu generation
    # note: technically this should be at the end of the script, if `load.sh` may run concurrently
    `touch $run_touch_file`;
  }
}

open my $LOGH, '>', $cleanup_log || warn( "Could not open file $cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'FusionCompute erase : start ' . localtime() . "\n";

foreach my $file (@vm_files) {
  $file =~ /$vm_dir\/(.*)\.rrd/;
  my $vm_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{vm}{$vm_uuid} ) {
    my @files_to_remove = <$vm_dir/$vm_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "FusionCompute VM to be erased : $file_to_remove\n";
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
      print $LOGH "FusionCompute Host to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@cluster_files) {
  $file =~ /$cluster_dir\/(.*)\.rrd/;
  my $cluster_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{cluster}{$cluster_uuid} ) {
    my @files_to_remove = <$cluster_dir/$cluster_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "FusionCompute Cluster to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@datastore_files) {
  $file =~ /$datastore_dir\/(.*)\.rrd/;
  my $datastore_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{datastore}{$datastore_uuid} ) {
    my @files_to_remove = <$datastore_dir/$datastore_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "FusionCompute Datastore to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

print $LOGH 'FusionCompute erase : finish ' . localtime() . ", erased $erased_count RRD files\n";
close $LOGH;
print 'fusioncompute-cleanup.pl  : finish ' . localtime() . ", erased $erased_count RRD files\n";
exit 0;
