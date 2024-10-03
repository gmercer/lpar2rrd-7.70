# docker-cleanup.pl
# remove unused data from Docker

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use HostCfg;
use Xorux_lib qw(error file_time_diff);
use DockerDataWrapper;
use Docker;

defined $ENV{INPUTDIR} || warn( " INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $version       = "$ENV{version}";
my $inputdir      = "$ENV{INPUTDIR}";
my $wrkdir        = "$inputdir/data/Docker";
my $container_dir = "$wrkdir/Container";
my $volume_dir    = "$wrkdir/Volume";
my $check_dir     = "$wrkdir/check";

my $touch_file  = "$inputdir/tmp/docker_cleanup.touch";
my $cleanup_log = "$inputdir/logs/erased.log-docker";
my $t1day       = 60 * 60 * 24 * 1;
my $t1month     = 60 * 60 * 24 * 30;
my $label_json  = DockerDataWrapper::get_labels();

my @container_files = <$container_dir/*.rrd>;
my @volume_files    = <$volume_dir/*.rrd>;
my $erased_count    = 0;

my $run_touch_file = "$inputdir/tmp/$version-docker";    # for generating menu

################################################################################

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'docker-cleanup.pl         : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "docker-cleanup.pl         : already ran today, skip\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'docker-cleanup.pl         : removing performance data older than 1 day, ' . localtime() . "\n";

    # also force new menu generation
    # note: technically this should be at the end of the script, if `load.sh` may run concurrently
    `touch $run_touch_file`;
  }
}

my %mapping;
my @hosts = @{ DockerDataWrapper::get_items( { item_type => 'host' } ) };
foreach my $host (@hosts) {
  my ( $host_id, $host_label ) = each %{$host};
  my @containers = @{ DockerDataWrapper::get_items( { item_type => 'container', parent_type => 'host', parent_id => $host_id } ) };
  foreach my $container (@containers) {
    my ( $container_uuid, $container_label ) = each %{$container};
    $mapping{$container_uuid} = $host_id;
  }
  my @volumes = @{ DockerDataWrapper::get_items( { item_type => 'volume', parent_type => 'host', parent_id => $host_id } ) };
  foreach my $volume (@volumes) {
    my ( $volume_uuid, $volume_label ) = each %{$volume};
    $mapping{$volume_uuid} = $host_id;
  }
}

open my $LOGH, '>', $cleanup_log || warn( "Could not open file $cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'docker-cleanup.pl         : start ' . localtime() . "\n";

foreach my $file (@container_files) {
  $file =~ /$container_dir\/(.*)\.rrd/;
  my $container_uuid = $1;

  my $check_file = $check_dir . "/" . $mapping{$container_uuid};
  if ( Xorux_lib::file_time_diff($file) > $t1day && Xorux_lib::file_time_diff($check_file) < $t1day ) {
    my @files_to_remove = <$container_dir/$container_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      Docker::deleteLabel( 'container', $container_uuid );
      Docker::deleteArchitecture( 'container', $container_uuid );
      print $LOGH "Docker container to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@volume_files) {
  $file =~ /$volume_dir\/(.*)\.rrd/;
  my $volume_uuid = $1;

  my $check_file = $check_dir . "/" . $mapping{$volume_uuid};
  if ( Xorux_lib::file_time_diff($file) > $t1day && Xorux_lib::file_time_diff($check_file) < $t1day ) {
    my @files_to_remove = <$volume_dir/$volume_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      Docker::deleteLabel( 'volume', $volume_uuid );
      Docker::deleteArchitecture( 'volume', $volume_uuid );
      print $LOGH "Docker volume to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

@hosts = @{ DockerDataWrapper::get_items( { item_type => 'host' } ) };
foreach my $host (@hosts) {
  my ( $host_id, $host_label ) = each %{$host};
  my $check_file = $check_dir . "/" . $host_id;
  if ( Xorux_lib::file_time_diff($check_file) > $t1month ) {
    my @containers = @{ DockerDataWrapper::get_items( { item_type => 'container', parent_type => 'host', parent_id => $host_id } ) };
    foreach my $container (@containers) {
      my ( $container_uuid, $container_label ) = each %{$container};
      unlink "$container_dir/$container_uuid.rrd";
      Docker::deleteLabel( 'container', $container_uuid );
      Docker::deleteArchitecture( 'container', $container_uuid );
      print $LOGH "Docker container to be erased (host removed): $container_uuid\n";
      $erased_count++;
    }
    my @volumes = @{ DockerDataWrapper::get_items( { item_type => 'volume', parent_type => 'host', parent_id => $host_id } ) };
    foreach my $volume (@volumes) {
      my ( $volume_uuid, $volume_label ) = each %{$volume};
      unlink "$volume_dir/$volume_uuid.rrd";
      Docker::deleteLabel( 'volume', $volume_uuid );
      Docker::deleteArchitecture( 'volume', $volume_uuid );
      print $LOGH "Docker volume to be erased (host removed): $volume_uuid\n";
      $erased_count++;
    }
  }
}

print $LOGH 'Docker erase : finish ' . localtime() . ", erased $erased_count RRD files\n";
close $LOGH;
print 'docker-cleanup.pl         : finish ' . localtime() . ", erased $erased_count RRD files\n";
exit 0;
