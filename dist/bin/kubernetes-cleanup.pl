# kubernetes-cleanup.pl
# remove unused data from Kubernetes

use 5.008_008;

use strict;
use warnings;

use RRDDump;
use Data::Dumper;
use HostCfg;
use Xorux_lib qw(error file_time_diff);
use KubernetesDataWrapper;

defined $ENV{INPUTDIR} || warn( " INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('Kubernetes') } == 0 ) {
  exit(0);
}

my $version       = "$ENV{version}";
my $inputdir      = "$ENV{INPUTDIR}";
my $wrkdir        = "$inputdir/data/Kubernetes";
my $node_dir      = "$wrkdir/Node";
my $pod_dir       = "$wrkdir/Pod";
my $container_dir = "$wrkdir/Container";
my $network_dir   = "$wrkdir/Network";
my $last_file     = "$wrkdir/last.json";

my $touch_file   = "$inputdir/tmp/kubernetes_cleanup.touch";
my $touch_c_file = "$inputdir/tmp/kubernetes_containers_cleanup.touch";
my $cleanup_log  = "$inputdir/logs/erased.log-kubernetes";
my $t3months     = 60 * 60 * 24 * 90;
my $t1months     = 60 * 60 * 24 * 30;
my $t1day        = 60 * 60 * 24;
my $t7days       = 60 * 60 * 24 * 7;
my $label_json   = KubernetesDataWrapper::get_conf_label();

my @node_files      = <$node_dir/*.rrd>;
my @pod_files       = <$pod_dir/*.rrd>;
my @container_files = <$container_dir/*.rrd>;
my $erased_count    = 0;

my $run_touch_file = "$inputdir/tmp/$version-kubernetes";    # for generating menu

################################################################################

my $updated = KubernetesDataWrapper::get_conf_update_time();
if ( time() - $updated >= 86400 ) {
  print 'kubernetes-cleanup.pl  : skipped\n';
  exit(0);
}

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'kubernetes-cleanup.pl  : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "kubernetes-cleanup.pl  : already ran today, skip\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'kubernetes-cleanup.pl  : removing performance data older than 3 months, ' . localtime() . "\n";

    # also force new menu generation
    # note: technically this should be at the end of the script, if `load.sh` may run concurrently
    `touch $run_touch_file`;
  }
}

my $clean_zero = 0;
if ( !-f $touch_c_file ) {
  `touch $touch_c_file`;
  print 'kubernetes-cleanup.pl  : first containers clean after install, ' . localtime() . "\n";
  $clean_zero = 1;
}

open my $LOGH, '>', $cleanup_log || warn( "Could not open file $cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'Kubernetes erase : start ' . localtime() . "\n";

if (( stat $last_file )[9] > $t7days) {
  unlink $last_file;
  print $LOGH "Last file removed\n";
}

opendir my $dh, $network_dir
  or warn "$0: opendir: $!";

my $removed_directories = 0;
while ( defined( my $dir_name = readdir $dh ) ) {
  next unless -d "$network_dir/$dir_name";
  next if $dir_name eq ".";
  next if $dir_name eq "..";

  if ( !defined $label_json->{label}{pod}{$dir_name} ) {

    my @network_files = <$network_dir/$dir_name/*.rrd>;
    foreach my $network_file (@network_files) {
      $network_file =~ /$network_dir\/$dir_name\/(.*)\.rrd/;
      my $network_uuid            = $1;
      my @network_files_to_remove = <$network_dir/$dir_name/$network_uuid.rrd>;
      foreach my $network_file_to_remove (@network_files_to_remove) {
        unlink $network_file_to_remove;
        print $LOGH "Kubernetes Pod network to be erased : $network_file_to_remove\n";
        $erased_count++;
      }
    }

    rmdir( $network_dir . "/" . $dir_name );
    $removed_directories++;
  }
}
if ( $removed_directories >= 1 ) {
  print $LOGH "Kubernetes Pod Network dir erased : $removed_directories\n";
}

foreach my $file (@node_files) {
  $file =~ /$node_dir\/(.*)\.rrd/;
  my $node_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{label}{node}{$node_uuid} ) {
    my @files_to_remove = <$node_dir/$node_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Kubernetes Node to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@pod_files) {
  $file =~ /$pod_dir\/(.*)\.rrd/;
  my $pod_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t1day && !exists $label_json->{label}{pod}{$pod_uuid} || ( stat $file )[9] <= $t1day && !exists $label_json->{label}{pod}{$pod_uuid} ) {
    my @files_to_remove = <$pod_dir/$pod_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Kubernetes Pod to be erased : $file_to_remove\n";
      $erased_count++;

      my @network_files = <$network_dir/$pod_uuid/*.rrd>;
      foreach my $network_file (@network_files) {
        $network_file =~ /$network_dir\/$pod_uuid\/(.*)\.rrd/;
        my $network_uuid            = $1;
        my @network_files_to_remove = <$network_dir/$pod_uuid/$network_uuid.rrd>;
        foreach my $network_file_to_remove (@network_files_to_remove) {
          unlink $network_file_to_remove;
          print $LOGH "Kubernetes Pod network to be erased : $network_file_to_remove\n";
          $erased_count++;
        }
        rmdir( $network_dir . "/" . $pod_uuid );
        print $LOGH "Kubernetes Pod network dir to be erased : $network_dir/$pod_uuid\n";
      }
    }
  }

  if ( $clean_zero eq "1" ) {

    #delete rrd with cpu 0
    my $rrd = "$pod_dir/$pod_uuid.rrd";
    if ( -f $rrd ) {
      my $dump = RRDDump->new($rrd);
      my $data = $dump->get_average_by_interval( 'memory', 30 );
      if ( !defined $data || $data eq "0" || $data =~ m/nan/ || $data =~ m/NaN/ ) {
        print "RRD: $rrd, average memory value: $data\n";
        unlink $rrd;
        print $LOGH "Kubernetes Pod (empty) to be erased : $rrd\n";
        $erased_count++;
      }
    }
  }
}

foreach my $file (@container_files) {
  $file =~ /$container_dir\/(.*)\.rrd/;
  my $container_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t1day && !exists $label_json->{label}{container}{$container_uuid} || ( stat $file )[9] <= $t1day && !exists $label_json->{label}{container}{$container_uuid} ) {
    my @files_to_remove = <$container_dir/$container_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "Kubernetes Container to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }

  if ( $clean_zero eq "1" ) {

    #delete rrd with cpu 0
    my $rrd = "$container_dir/$container_uuid.rrd";
    if ( -f $rrd ) {
      my $dump = RRDDump->new($rrd);
      my $data = $dump->get_average_by_interval( 'memory', 30 );
      if ( !defined $data || $data eq "0" || $data =~ m/nan/ || $data =~ m/NaN/ ) {
        print "RRD: $rrd, average memory value: $data\n";
        unlink $rrd;
        print $LOGH "Kubernetes Container (empty) to be erased : $rrd\n";
        $erased_count++;
      }
    }
  }
}

print $LOGH 'Kubernetes erase : finish ' . localtime() . ", erased $erased_count RRD files\n";
close $LOGH;
print 'kubernetes-cleanup.pl  : finish ' . localtime() . ", erased $erased_count RRD files\n";
exit 0;
