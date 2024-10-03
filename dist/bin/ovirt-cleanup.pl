use 5.008_008;

use strict;
use warnings;
use Xorux_lib qw(error file_time_diff);
use OVirtDataWrapper;

defined $ENV{INPUTDIR} || warn( ' INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir     = $ENV{INPUTDIR};
my $vm_dir       = "$inputdir/data/oVirt/vm";
my $storage_dir  = "$inputdir/data/oVirt/storage";
my $touch_file   = "$inputdir/tmp/oVirt_cleanup.touch";
my $cleanup_log  = "$inputdir/logs/vm_erased.log-ovirt";
my $t3months     = 60 * 60 * 24 * 90;
my $conf         = OVirtDataWrapper::get_conf_section('arch');
my @vm_files     = <$vm_dir/*/sys.rrd>;
my @disk_files   = <$storage_dir/disk-*.rrd>;
my $erased_count = 0;

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'ovirt-cleanup.pl  : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "ovirt-cleanup.pl  : already ran today, skip\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'ovirt-cleanup.pl  : removing VMs data older than 3 months, ' . localtime() . "\n";
  }
}

open my $LOGH, '>>', $cleanup_log || warn( "Could not open file $cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'oVirt erase : start ' . localtime() . "\n";

foreach my $file (@vm_files) {
  $file =~ /$vm_dir\/(.*)\/sys\.rrd/;
  my $vm_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $conf->{vm}{$vm_uuid} ) {
    my @files_to_remove = <$vm_dir\/$vm_uuid/*.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "oVirt erase VM : $file_to_remove\n";
      $erased_count++;
    }

    @files_to_remove = <$vm_dir\/$vm_uuid/*.rrd>;

    if ( scalar @files_to_remove == 0 ) {
      rmdir "$vm_dir\/$vm_uuid/";
      print $LOGH "oVirt erase VM dir : $vm_dir/$vm_uuid/\n";
    }
  }
}

foreach my $file (@disk_files) {
  $file =~ /$storage_dir\/disk-(.*)\.rrd/;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $conf->{disk}{$1} ) {
    unlink $file;
    print $LOGH "oVirt erase VM disk : $file\n";
    $erased_count++;
  }
}

print $LOGH 'oVirt erase : finish ' . localtime() . ", erased file count $erased_count\n";
close $LOGH;
print 'ovirt-cleanup.pl  : finish ' . localtime() . ", erased file count $erased_count\n";
exit 0;
