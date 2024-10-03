# usage
# cd /home/lpar2rrd/lpar2rrd
# perl bin/delete_vmware_cluster.pl <cluster_name>
#
# all clusters of this name are found and offered to be deleted

use strict;
use warnings;
use File::Basename;

# there must be one param

if ( scalar @ARGV != 1 ) {
  print "Cluster name has not been found in command line.\n";
  print "call this script this way: perl bin/delete_vmware_cluster.pl <cluster_name>\n";
  exit;
}

my @clusters = `ls data/*/cluster_*/cluster_name*`;
if ( !defined $clusters[0] ) {
  print "no clusters have been found\n";
  exit;
}

my $found = 0;    # 1 when the cluster has not been found
foreach (@clusters) {
  my $cluster = $_;

  # print "\$cluster $cluster\n";
  next if ( $cluster !~ /$ARGV[0]$/ );
  print "found & prepare to delete cluster: $cluster\n";
  my $dir = dirname $cluster;

  # print "\$dir $dir\n";
  if ( !defined $dir or $dir eq "" ) {
    print "cannot find dir of cluster $ARGV[0]\n";
    next;
  }
  my $vcenter_name = `ls $dir/vcenter_name_*`;

  # print "\$vcenter_name $vcenter_name\n";
  $vcenter_name = basename $vcenter_name;
  chomp $vcenter_name;
  $vcenter_name =~ s/vcenter_name_//;
  print "Do you really want to delete cluster: $ARGV[0] from vCenter $vcenter_name? (yes/no):";
  my $answer = <STDIN>;
  chomp $answer;
  if ( $answer eq "yes" ) {
    print "deleting cluster $ARGV[0] under path $dir/\n";
    my $result = `rm -rf $dir`;
    my $res    = $?;

    # print "\$result ,$result, ,$?,\n";
    if ( $result eq "" and $res == 0 ) {
      print "deleting has been successfull!\n";
    }
    else {
      print "possible error when deleting above mentioned cluster\n";
    }
  }
  else {
    print "cluster $dir has not been deleted\n";
  }

  $found++;
}

if ( !$found ) {
  print "no cluster with name $ARGV[0] has been found\n";
}
