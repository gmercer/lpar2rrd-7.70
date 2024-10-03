# xen-cleanup.pl
# remove unused data from XenServers

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use Xorux_lib qw(error file_time_diff);
use XenServerDataWrapperOOP;

defined $ENV{INPUTDIR} || warn( " INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $version            = "$ENV{version}";
my $inputdir           = $ENV{INPUTDIR};
my $wrkdir             = "$inputdir/data";
my $metadata_dir       = "$inputdir/data/XEN_iostats/metadata";
my $host_dir           = "$inputdir/data/XEN";
my $vm_dir             = "$inputdir/data/XEN_VMs";
my $touch_file         = "$inputdir/tmp/xenserver_cleanup.touch";
my $cleanup_log        = "$inputdir/logs/vm_erased.log-xenserver";
my $t3months           = 60 * 60 * 24 * 90;
my $xenserver_metadata = XenServerDataWrapperOOP->new();
my $conf               = $xenserver_metadata->get_conf_section('labels');
my @metadata_files     = <$metadata_dir/*.json>;
my @host_files         = <$host_dir/*/*.rrd>;
my @vm_files           = <$vm_dir/*.rrd>;
my $erased_count       = 0;
my $run_touch_file     = "$inputdir/tmp/$version-xenserver";                # for generating menu

################################################################################

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'xen-cleanup.pl  : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print 'xen-cleanup.pl  : already ran today, skip' . "\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'xen-cleanup.pl  : removing performance data older than 3 months, ' . localtime() . "\n";

    # also force new menu generation
    # note: technically this should be at the end of the script, if `load.sh` may run concurrently
    `touch $run_touch_file`;
  }
}

open my $LOGH, '>', $cleanup_log || warn( 'Could not open file ' . "$cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'XenServer erase : start ' . localtime() . "\n";

foreach my $file (@metadata_files) {
  unlink $file;
  print $LOGH 'XenServer erase metadata : ' . "$file\n";
}

foreach my $file (@vm_files) {
  $file =~ /$vm_dir\/(.*)\.rrd/;
  my $vm_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $conf->{vm}{$vm_uuid} ) {
    my @files_to_remove = <$vm_dir/$vm_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH 'XenServer VM to be erased : ' . $file_to_remove . "\n";
      $erased_count++;
    }
  }
}

foreach my $file (@host_files) {
  $file =~ /$host_dir\/(.*)\/(.*)\.rrd/;
  my $host_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $conf->{host}{$host_uuid} ) {
    unlink $file;
    print $LOGH 'XenServer erase host data : ' . $file . "\n";
    $erased_count++;

    my @files_to_remove = <$host_dir/$host_uuid/*.rrd>;

    if ( scalar @files_to_remove == 0 ) {
      rmdir "$host_dir/$host_uuid/";
      print $LOGH 'XenServer erase host dir : ' . $host_dir . '/' . $host_uuid . '/' . "\n";
    }
  }
}

print $LOGH 'XenServer erase : finish ' . localtime() . ', erased ' . $erased_count . ' RRD files' . "\n";
close $LOGH;
print 'xen-cleanup.pl  : finish ' . localtime() . ', erased ' . $erased_count . ' RRD files' . "\n";
exit 0;
