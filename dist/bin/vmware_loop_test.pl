
use strict;
use warnings;
require VMware::VIRuntime;
require VMware::VILib;

my $sdate = `date`;
print "----- VMWARE tree     start: $sdate\n";

main_test();

$sdate = `date`;
print "----- VMWARE tree     finish: $sdate\n";

exit(0);

sub main_test {

  Opts::parse();
  Opts::validate();
  Util::connect();

  #######GET ServiceInstance  CurrentTime this is linear
  my $service_instance = Vim::get_service_instance();
  my $s_time           = $service_instance->CurrentTime();
  print "   ServiceInstance current server time is $s_time\n";

  my $fullName = $service_instance->content->about->fullName;    #
  print "   fullName $fullName \n";

  ########GET THE DATACENTERS with limited properties(important!!!! for speed)##########

  my $dc_view = Vim::find_entity_views( view_type => 'Datacenter', properties => ['name'] );

  #########LOOP THE DATACENTERS#######

  foreach my $each_dc (@$dc_view) {
    if   ($each_dc) { print ''; }
    else            { print 'notfound'; }
    print "   The Name of this Datacenter: " . $each_dc->name . "\n\n";

    print "     Hosts on this Datacenter:\n";

    ######GET THE HOSTS(IMPORTANT include the PARENT property)#######

    my $host_view = Vim::find_entity_views( view_type => 'HostSystem', properties => [ 'name', 'parent', 'hardware' ], begin_entity => $each_dc );
    foreach my $each_host (@$host_view) {
      print "\n\t" . $each_host->name;
      my $hardware_uuid = $each_host->hardware->systemInfo->uuid;
      my $hz            = $each_host->hardware->cpuInfo->hz;
      print " hardware_uuid $hardware_uuid \$hz $hz\n";

      ######GET THE CLUSTERS(IMPORTANT this is going up the chain with mo_ref)#######

      my $cr_view = Vim::get_view( mo_ref => $each_host->parent, view_type => 'ClusterComputeResource' );

      ### IF STATEMENTS ARE IMPORTANT IF A HOST IS NOT IN A CLUSTER PREVENTS PERL FROM THROWING ERROR###

      if ( $cr_view->name ) {
        print "\tCluster Name " . $cr_view->name . "\n";
      }
      else {
        print "\n";
      }
    }
  }

  Util::disconnect();

}

