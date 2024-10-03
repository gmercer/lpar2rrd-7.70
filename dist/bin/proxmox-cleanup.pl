# proxmox-cleanup.pl
# remove unused data from Proxmox

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use HostCfg;
use Xorux_lib qw(error file_time_diff);
use ProxmoxDataWrapper;

defined $ENV{INPUTDIR} || warn( " INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('Proxmox') } == 0 ) {
  exit(0);
}

my $version     = "$ENV{version}";
my $inputdir    = "$ENV{INPUTDIR}";
my $wrkdir      = "$inputdir/data/Proxmox";
my $vm_dir      = "$wrkdir/VM";
my $node_dir    = "$wrkdir/Node";
my $lxc_dir     = "$wrkdir/LXC";
my $storage_dir = "$wrkdir/Storage";

my $touch_file  = "$inputdir/tmp/proxmox_cleanup.touch";
my $cleanup_log = "$inputdir/logs/erased.log-proxmox";
my $t3months    = 60 * 60 * 24 * 90;
my $label_json  = ProxmoxDataWrapper::get_labels();

my @vm_files      = <$vm_dir/*.rrd>;
my @node_files    = <$node_dir/*.rrd>;
my @lxc_files     = <$lxc_dir/*.rrd>;
my @storage_files = <$storage_dir/*.rrd>;
my $erased_count  = 0;

my $run_touch_file = "$inputdir/tmp/$version-proxmox";    # for generating menu

################################################################################

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'proxmox-cleanup.pl        : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "proxmox-cleanup.pl        : already ran today, skip\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'proxmox-cleanup.pl        : removing performance data older than 3 months, ' . localtime() . "\n";

    # also force new menu generation
    # note: technically this should be at the end of the script, if `load.sh` may run concurrently
    `touch $run_touch_file`;
  }
}

open my $LOGH, '>', $cleanup_log || warn( "Could not open file $cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'Proxmox erase : start ' . localtime() . "\n";

foreach my $file (@vm_files) {
  $file =~ /$vm_dir\/(.*)\.rrd/;
  my $vm_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{vm}{$vm_uuid} ) {
    my @files_to_remove = <$vm_dir/$vm_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Proxmox VM to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@node_files) {
  $file =~ /$node_dir\/(.*)\.rrd/;
  my $node_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{node}{$node_uuid} ) {
    my @files_to_remove = <$node_dir/$node_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Proxmox Node to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@lxc_files) {
  $file =~ /$lxc_dir\/(.*)\.rrd/;
  my $lxc_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{lxc}{$lxc_uuid} ) {
    my @files_to_remove = <$lxc_dir/$lxc_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Proxmox LXC to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@storage_files) {
  $file =~ /$storage_dir\/(.*)\.rrd/;
  my $storage_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{storage}{$storage_uuid} ) {
    my @files_to_remove = <$storage_dir/$storage_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Proxmox Storage to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

print $LOGH 'Proxmox erase : finish ' . localtime() . ", erased $erased_count RRD files\n";
close $LOGH;
print 'proxmox-cleanup.pl        : finish ' . localtime() . ", erased $erased_count RRD files\n";
exit 0;
