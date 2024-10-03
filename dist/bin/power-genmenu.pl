# power-genmenu.pl
# generate menu tree from Power RRDs and save it in a JSON file
# replacement for an older equivalent to `find_active_lpar.pl` that generated `menu.txt`

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib qw(error);
use PowerDataWrapper;
use PowerMenu;

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $inputdir      = $ENV{INPUTDIR};
my $main_data_dir = "$inputdir/data";

################################################################################

unless ( -d $main_data_dir ) {

  # print "exiting...\n";
  exit;
}

my $menu_tree  = PowerMenu::create_folder('Power');
my $servers    = gen_servers();
my $hmc_totals = gen_hmc_totals();

if ( scalar @{$servers} ) {
  my $cpu_workload_estimator_page_url     = PowerMenu::get_url( { type => 'cpu_workload_estimator' } );
  my $cpu_workload_estimator_page_url_old = PowerMenu::url_new_to_old( { type => 'cpu_workload_estimator' } );
  my $cpu_workload_estimator_page         = PowerMenu::create_page( 'CPU Workload Estimator', $cpu_workload_estimator_page_url );

  my $resource_configuration_advisor_page_url     = PowerMenu::get_url( { type => 'resource_configuration_advisor' } );
  my $resource_configuration_advisor_page_url_old = PowerMenu::url_new_to_old( { type => 'resource_configuration_advisor' } );
  my $resource_configuration_advisor_page         = PowerMenu::create_page( 'Resource Configuration Advisor', $resource_configuration_advisor_page_url );

  my $heatmap_page_url     = PowerMenu::get_url( { type => 'Heatmap' } );
  my $heatmap_page_url_old = PowerMenu::url_new_to_old( { type => 'Heatmap' } );
  my $heatmap_page         = PowerMenu::create_page( 'Heatmap', $heatmap_page_url );

  my $historical_reports_page_url     = PowerMenu::get_url( { type => 'historical_reports', mode => 'global' } );
  my $historical_reports_page_url_old = PowerMenu::url_new_to_old( { type => 'historical_reports' } );
  my $historical_reports_page         = PowerMenu::create_page( 'Historical Reports', $historical_reports_page_url );

  my $configuration_page_url     = PowerMenu::get_url( { type => 'configuration', item => "servers" } );
  my $configuration_page_url_old = PowerMenu::url_new_to_old( { type => 'configuration' } );
  my $configuration_page         = PowerMenu::create_page( 'Configuration', $configuration_page_url );

  my $top10_global_page_url     = PowerMenu::get_url( { type => 'top10_global', item => "topten" } );
  my $top10_global_page_url_old = PowerMenu::url_new_to_old( { type => "top10_global" } );
  my $top10_global_page         = PowerMenu::create_page( 'LPAR TOP', $top10_global_page_url );

  my $nmon_file_grapher_page_url     = PowerMenu::get_url( { type => 'nmon_file_grapher' } );
  my $nmon_file_grapher_page_url_old = PowerMenu::url_new_to_old( { type => 'nmon_file_grapher' } );
  my $nmon_file_grapher_page         = PowerMenu::create_page( 'NMON file grapher', $nmon_file_grapher_page_url );

  my $rmc_check_page_url     = PowerMenu::get_url( { type => 'rmc_check' } );
  my $rmc_check_page_url_old = PowerMenu::url_new_to_old( { type => 'rmc_check' } );
  my $rmc_check_page         = PowerMenu::create_page( 'RMC check', $rmc_check_page_url );

  $menu_tree->{children} = [ $cpu_workload_estimator_page, $resource_configuration_advisor_page, $heatmap_page, $historical_reports_page, $configuration_page, $top10_global_page, $nmon_file_grapher_page, $rmc_check_page ];

  push @{ $menu_tree->{children} }, $hmc_totals;
  push @{ $menu_tree->{children} }, @{$servers};

  #print as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}

exit 0;

################################################################################

sub gen_hmc_totals {
  my $hmc_folder = PowerMenu::create_folder('HMC Totals');
  my $hmc_data   = PowerDataWrapper::get_items('HMC');
  foreach my $hmc_item ( @{$hmc_data} ) {
    foreach my $hmc_uid ( keys %{$hmc_item} ) {
      my $hmc              = $hmc_item->{$hmc_uid};
      my $hmc_page_url     = PowerMenu::get_url( { type => 'hmc-totals', id => $hmc_uid } );
      my $hmc_page_url_old = PowerMenu::url_new_to_old( { type => 'hmc-totals', id => $hmc_uid } );
      my $hmc_page         = PowerMenu::create_page( $hmc, $hmc_page_url );
      push @{ $hmc_folder->{children} }, $hmc_page;
    }
  }

  return $hmc_folder;
}

sub gen_servers {
  my @server_folders = ();
  my $servers_data   = PowerDataWrapper::get_items('SERVER');

  foreach my $server ( @{$servers_data} ) {
    foreach my $server_uuid ( keys %{$server} ) {
      my $server_label  = $server->{$server_uuid};
      my $server_folder = PowerMenu::create_folder($server_label);
      my $hmc_uid       = PowerDataWrapper::get_server_parent($server_uuid);
      my $hmc           = PowerDataWrapper::get_label( "HMC", $hmc_uid );

      #      $hmc = $hmc->{label} if (defined $hmc->{label});
      # ==== server folder ==== #

      # CPU Pool
      #my $cpu_pool_page_url    = PowerMenu::get_url ( { host => $hmc, server => $server_label, lpar => 'pool', item => 'pool', type => 'pool' } );
      my $cpu_pool_page_url     = PowerMenu::get_url( { type => 'pool', id => $server_uuid } );
      my $cpu_pool_page_url_old = PowerMenu::url_new_to_old( { type => 'pool', id => $server_uuid } );
      my $cpu_pool_page         = PowerMenu::create_page( 'CPU Pool', $cpu_pool_page_url );
      push @{ $server_folder->{children} }, $cpu_pool_page;

      # SharedPools pages
      my $shp_folder  = PowerMenu::create_folder("Shared Pools");
      my @pages_pools = gen_pools( $server_uuid, $server_label, $hmc );
      foreach my $page_arr (@pages_pools) {
        foreach my $page ( @{$page_arr} ) {

          #push (@{ $server_folder->{children}} , $page); # do not push SharedPools to server_folder, create SharedPools folder and push them to this folder instead.
          push( @{ $shp_folder->{children} }, $page );    # push SharedPools folder to server_folder
        }
      }
      push( @{ $server_folder->{children} }, $shp_folder );

      #Memory
      #my $memory_page_url = PowerMenu::get_url ( { host => $hmc, server => $server_label, lpar => 'cod', item => 'memalloc', type => 'memory' } );
      my $memory_page_url     = PowerMenu::get_url( { type => 'memory', id => $server_uuid } );
      my $memory_page_url_old = PowerMenu::url_new_to_old( { type => 'memory', id => $server_uuid } );
      my $memory_page         = PowerMenu::create_page( 'Memory', $memory_page_url );
      push @{ $server_folder->{children} }, $memory_page;

      #Historical Reports - Server
      my $historical_reports_page_url     = PowerMenu::get_url( { type => 'historical_reports', id => $hmc_uid, server => $server_label } );
      my $historical_reports_page_url_old = PowerMenu::url_new_to_old( { type => 'historical_reports', id => $hmc_uid } );
      my $historical_reports_page         = PowerMenu::create_page( 'Historical Reports', $historical_reports_page_url );

      #push @{ $server_folder->{children} }, $historical_reports_page; # do not use historical reports for each server

      #Historical Reports - Server
      #my $topten_page_url = PowerMenu::get_url ( { host => $hmc, server => $server_label, item => 'topten', type => 'topten' } );
      my $topten_page_url     = PowerMenu::get_url( { type => 'topten', id => $server_uuid } );
      my $topten_page_url_old = PowerMenu::url_new_to_old( { type => 'topten', id => $server_uuid } );
      my $topten_page         = PowerMenu::create_page( 'LPAR TOP', $topten_page_url );
      push @{ $server_folder->{children} }, $topten_page;

      my $view_page_url     = PowerMenu::get_url( { type => 'view', id => $server_uuid } );
      my $view_page_url_old = PowerMenu::url_new_to_old( { type => 'view', id => $server_uuid } );
      my $view_page         = PowerMenu::create_page( 'VIEW', $view_page_url );
      push @{ $server_folder->{children} }, $view_page;

      # LPAR subtree
      my $vm_folder = PowerMenu::create_folder("LPAR");
      $vm_folder->{children} = gen_vms( $server_uuid, $server_label, $hmc );
      push @{ $server_folder->{children} }, $vm_folder;

      # INTERFACES subtrees
      my @int_types = ( "LAN", "SAN", "SAS", "HEA", "SRI" );
      foreach my $int_type (@int_types) {
        my $int_type_url = lc($int_type);
        my $int_folder   = PowerMenu::create_folder($int_type);
        my $item_folder  = PowerMenu::create_folder("Items");

        #TOTALS
        #my $totals_page_url = PowerMenu::get_url( { host => $hmc, server => $server_label, lpar => "$int_type_url-totals", item => "power_$int_type_url" } );
        my $totals_page_url     = PowerMenu::get_url( { type => "$int_type_url-aggr", id => $server_uuid } );
        my $totals_page_url_old = PowerMenu::url_new_to_old( { type => "$int_type_url-aggr", id => $server_uuid } );
        my $totals_page         = PowerMenu::create_page( "Totals", $totals_page_url );

        #ITEMS
        my $children = gen_int( $server_uuid, $server_label, $hmc, $int_type );
        $item_folder->{children} = $children;

        #print  "host => $hmc, server => $server_label, lpar =>  $int_type_url-totals , item =>  power_$int_type_url , type =>  interface\n";

        push @{ $int_folder->{children} }, $totals_page if ( defined scalar( @{ $item_folder->{children} } ) );    # push ITEMS to interface folder
        push @{ $int_folder->{children} }, $item_folder if defined($children);                                     # push TOTALS to interface folder (if any items ofc)

        push @{ $server_folder->{children} }, $int_folder if ( defined scalar( @{ $int_folder->{children} } ) );   # push INTERFACE folder to menu tree
      }

      # ======================= #

      push( @server_folders, $server_folder );                                                                     # push server folder into menu tree
    }
  }
  return \@server_folders;
}

sub gen_int {
  my $server_uuid  = shift;
  my $server_label = shift;
  my $hmc          = shift;
  my $type         = shift;
  my $url_type     = lc($type);
  my $ext          = "rrd";
  $ext = "ralm" if $url_type eq "lan";
  $ext = "rasm" if $url_type eq "san";
  $ext = "rapm" if $url_type eq "sas";
  $ext = "rahm" if $url_type eq "hea";
  my @int_pages = ();
  my $int_data  = PowerDataWrapper::get_items( uc($type), $server_uuid );
  if ( !defined $int_data || $int_data eq "" ) { return; }

  foreach my $int ( @{$int_data} ) {
    foreach my $int_uuid ( keys %{$int} ) {
      my $menu_name = $int->{$int_uuid};

      #if (ref($int->{$int_uuid} eq "HASH") && defined $int->{$int_uuid}{label}){
      #  $menu_name = $int->{$int_uuid}{label};
      #}
      #my $int_page_url  = PowerMenu::get_url( { host => $hmc, server => $server_label, lpar => "$menu_name.$ext", item => "power_$url_type", type => "interface" } );
      my $int_page_url     = PowerMenu::get_url( { type => $url_type, id => $int_uuid } );
      my $int_page_url_old = PowerMenu::url_new_to_old( { type => $url_type, id => $int_uuid } );
      my $int_page         = PowerMenu::create_page( "$menu_name", $int_page_url );
      push( @int_pages, $int_page );
    }
  }
  return \@int_pages;

}

sub gen_pools {
  my $server_uuid  = shift;
  my $server_label = shift;
  my $hmc          = shift;
  my @pool_pages   = ();
  foreach my $shp ( @{ PowerDataWrapper::get_items( "POOL", $server_uuid ) } ) {
    foreach my $shp_uuid ( keys %{$shp} ) {
      my $pool_label = $shp->{$shp_uuid};
      my $pool_id    = PowerDataWrapper::get_pool_id( $shp_uuid, $server_uuid );

      #my $pool_page_url = PowerMenu::get_url( { host => $hmc, server => $server_label, lpar => "SharedPool$pool_id", item => 'shpool', type => 'pool' } );
      my $pool_page_url     = PowerMenu::get_url( { type => 'shpool', id => $shp_uuid } );
      my $pool_page_url_old = PowerMenu::url_new_to_old( { type => 'shpool', id => $shp_uuid } );
      my $pool_page         = PowerMenu::create_page( "CPU Pool $pool_id: $pool_label", $pool_page_url );
      push @pool_pages, $pool_page;
    }
  }
  return \@pool_pages;
}

sub gen_vms {
  my $server_uuid  = shift;
  my $server_label = shift;
  my $hmc          = shift;
  my @vm_pages     = ();

  foreach my $vm ( @{ PowerDataWrapper::get_items( "VM", $server_uuid ) } ) {
    foreach my $vm_uuid ( keys %{$vm} ) {
      my $vm_label     = $vm->{$vm_uuid};
      my $vm_label_url = $vm_label;

      #$vm_label_url     =~ s/ /%20/g;
      $vm_label_url = Xorux_lib::urlencode($vm_label_url);

      #$vm_label_url =~ s/%3A/===double-col===/g;
      #$vm_label_url =~ s/%3D%3D%3D/===/g;
      my $vm_page_url     = PowerMenu::get_url( { type => 'vm', id => $vm_uuid } );
      my $vm_page_url_old = PowerMenu::url_new_to_old( { type => 'vm', id => $vm_uuid } );
      my $vm_page         = PowerMenu::create_page( $vm_label, $vm_page_url );

      push @vm_pages, $vm_page;
    }
  }

  return \@vm_pages;
}
