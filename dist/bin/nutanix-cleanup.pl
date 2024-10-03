# nutanix-cleanup.pl
# remove unused data from Nutanix

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use HostCfg;
use Xorux_lib qw(error file_time_diff);
use NutanixDataWrapper;

defined $ENV{INPUTDIR} || warn( " INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('Nutanix') } == 0 ) {
  exit(0);
}

my $version       = "$ENV{version}";
my $inputdir      = "$ENV{INPUTDIR}";
my $wrkdir        = "$inputdir/data/NUTANIX";
my $vm_dir        = "$wrkdir/VM";
my $node_dir      = "$wrkdir/HOST";
my $container_dir = "$wrkdir/SC";
my $pool_dir      = "$wrkdir/SP";
my $vdisk_dir     = "$wrkdir/VD";

my $touch_file  = "$inputdir/tmp/nutanix_cleanup.touch";
my $cleanup_log = "$inputdir/logs/erased.log-nutanix";
my $t3months    = 60 * 60 * 24 * 90;
my $label_json  = NutanixDataWrapper::get_labels();

my @vm_files        = <$vm_dir/*.rrd>;
my @node_files      = <$node_dir/*.rrd>;
my @container_files = <$container_dir/*.rrd>;
my @pool_files      = <$pool_dir/*.rrd>;
my @vdisk_files     = <$vdisk_dir/*.rrd>;
my $erased_count    = 0;

my $run_touch_file = "$inputdir/tmp/$version-nutanix";    # for generating menu

################################################################################

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'nutanix-cleanup.pl        : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "nutanix-cleanup.pl        : already ran today, skip\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'nutanix-cleanup.pl        : removing performance data older than 3 months, ' . localtime() . "\n";

    # also force new menu generation
    # note: technically this should be at the end of the script, if `load.sh` may run concurrently
    `touch $run_touch_file`;
  }
}

open my $LOGH, '>', $cleanup_log || warn( "Could not open file $cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'Nutanix erase : start ' . localtime() . "\n";

opendir( my $DIR, $node_dir );
while ( my $entry = readdir $DIR ) {
  next unless -d $node_dir . '/' . $entry;
  next if $entry eq '.' or $entry eq '..';

  # disks
  my @disks_files = <$node_dir/$entry/disk-*.rrd>;
  foreach my $file (@disks_files) {
    $file =~ /$node_dir\/$entry\/(.*)\.rrd/;
    print $file. "\n";
    my $disk_uuid = $1;

    if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{disk}{$disk_uuid} ) {
      my @files_to_remove = <$node_dir/$entry/$disk_uuid.rrd>;

      foreach my $file_to_remove (@files_to_remove) {
        unlink $file_to_remove;
        print $LOGH "Nutanix Disk to be erased : $file_to_remove\n";
        $erased_count++;
      }
    }
  }

  #host
  my $file = "$node_dir/$entry/sys.rrd";
  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{host}{$entry} ) {
    unlink $file;
    print $LOGH "Nutanix Host to be erased : $file\n";
    $erased_count++;
    rmdir "$node_dir/$entry";
  }
}

# vms
foreach my $file (@vm_files) {
  $file =~ /$vm_dir\/(.*)\.rrd/;
  my $vm_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{vm}{$vm_uuid} ) {
    my @files_to_remove = <$vm_dir/$vm_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Nutanix VM to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

# container
foreach my $file (@container_files) {
  $file =~ /$container_dir\/(.*)\.rrd/;
  my $container_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{container}{$container_uuid} ) {
    my @files_to_remove = <$container_dir/$container_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Nutanix storage container to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

# storage pool
foreach my $file (@pool_files) {
  $file =~ /$pool_dir\/(.*)\.rrd/;
  my $pool_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{pool}{$pool_uuid} ) {
    my @files_to_remove = <$pool_dir/$pool_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Nutanix storage pool to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

# vdisk
foreach my $file (@vdisk_files) {
  $file =~ /$vdisk_dir\/(.*)\.rrd/;
  my $vdisk_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{vdisk}{$vdisk_uuid} ) {
    my @files_to_remove = <$vdisk_dir/$vdisk_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Nutanix vdisk to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

print $LOGH 'Nutanix erase : finish ' . localtime() . ", erased $erased_count RRD files\n";
close $LOGH;
print 'nutanix-cleanup.pl        : finish ' . localtime() . ", erased $erased_count RRD files\n";
exit 0;
