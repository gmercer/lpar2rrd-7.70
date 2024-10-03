# aws-cleanup.pl
# remove unused data from AWS

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use HostCfg;
use Xorux_lib qw(error file_time_diff);
use AWSDataWrapper;

defined $ENV{INPUTDIR} || warn( " INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

if ( keys %{ HostCfg::getHostConnections('AWS') } == 0 ) {
  exit(0);
}

my $version  = "$ENV{version}";
my $inputdir = "$ENV{INPUTDIR}";
my $wrkdir   = "$inputdir/data/AWS";
my $ec2_dir  = "$wrkdir/EC2";
my $ebs_dir  = "$wrkdir/EBS";
my $rds_dir  = "$wrkdir/RDS";

my $touch_file  = "$inputdir/tmp/aws_cleanup.touch";
my $cleanup_log = "$inputdir/logs/erased.log-aws";
my $t3months    = 60 * 60 * 24 * 90;
my $label_json  = AWSDataWrapper::get_labels();

my @ec2_files    = <$ec2_dir/*.rrd>;
my @ebs_files    = <$ebs_dir/*.rrd>;
my @rds_files    = <$rds_dir/*.rrd>;
my $erased_count = 0;

my $run_touch_file = "$inputdir/tmp/$version-aws";    # for generating menu

################################################################################

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'aws-cleanup.pl            : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print "aws-cleanup.pl            : already ran today, skip\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'aws-cleanup.pl            : removing performance data older than 3 months, ' . localtime() . "\n";

    # also force new menu generation
    # note: technically this should be at the end of the script, if `load.sh` may run concurrently
    `touch $run_touch_file`;
  }
}

open my $LOGH, '>', $cleanup_log || warn( "Could not open file $cleanup_log $! " . __FILE__ . ':' . __LINE__ ) && exit 1;

print $LOGH 'AWS erase : start ' . localtime() . "\n";

foreach my $file (@ec2_files) {
  $file =~ /$ec2_dir\/(.*)\.rrd/;
  my $ec2_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{ec2}{$ec2_uuid} ) {
    my @files_to_remove = <$ec2_dir/$ec2_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "AWS EC2 to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@ebs_files) {
  $file =~ /$ebs_dir\/(.*)\.rrd/;
  my $ebs_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{volume}{$ebs_uuid} ) {
    my @files_to_remove = <$ebs_dir/$ebs_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "AWS EBS to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

foreach my $file (@rds_files) {
  $file =~ /$rds_dir\/(.*)\.rrd/;
  my $rds_uuid = $1;

  if ( Xorux_lib::file_time_diff($file) > $t3months && !exists $label_json->{rds}{$rds_uuid} ) {
    my @files_to_remove = <$rds_dir/$rds_uuid.rrd>;

    foreach my $file_to_remove (@files_to_remove) {
      unlink $file_to_remove;
      print $LOGH "AWS RDS to be erased : $file_to_remove\n";
      $erased_count++;
    }
  }
}

print $LOGH 'AWS erase : finish ' . localtime() . ", erased $erased_count RRD files\n";
close $LOGH;
print 'aws-cleanup.pl            : finish ' . localtime() . ", erased $erased_count RRD files\n";
exit 0;
