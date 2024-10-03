# orvm-genmenu.pl
# generate menu tree from oVirt RRDs and save it in a JSON file
# replacement for an older equivalent to `find_active_lpar.pl` that generated `menu.txt`

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib;
use OracleVmDataWrapperOOP;
use OracleVmDataWrapper;
use OracleVmMenu;

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $webdir   = $ENV{WEBDIR};
my $host_dir = "$inputdir/data/OracleVM";
my $vm_dir   = "$inputdir/data/OracleVM/vm";

################################################################################

unless ( -d $host_dir ) {
  exit;
}

my $orvm_metadata = OracleVmDataWrapperOOP->new( { acl_check => 0 } );

my $menu_tree        = OracleVmMenu::create_folder('OracleVM');
my $oraclevm_servers = gen_orvm();

#print Dumper $oraclevm_servers;
#print "=================\n";
if ( scalar @{$oraclevm_servers} ) {
  my $configuration_page_url = OracleVmMenu::get_url( { type => 'configuration' } );
  my $configuration_page     = OracleVmMenu::create_page( 'Configuration', $configuration_page_url );
  my $heatmap_page_url       = OracleVmMenu::get_url( { type => 'heatmap' } );
  my $heatmap_page           = OracleVmMenu::create_page( 'Heatmap', $heatmap_page_url );
  my $topten_page_url        = OracleVmMenu::get_url( { type => 'topten_oraclevm' } );
  my $topten_page            = OracleVmMenu::create_page( 'VM TOP', $topten_page_url );
  my $histrep_page_url       = OracleVmMenu::get_url( { type => 'histrep-oraclevm' } );
  my $histrep_page           = OracleVmMenu::create_page( 'Historical reports', $histrep_page_url );
  $menu_tree->{children} = [ $heatmap_page, $configuration_page, $topten_page, $histrep_page ];
  push @{ $menu_tree->{children} }, @{$oraclevm_servers};

  #print as JSON
  my $json      = JSON->new->utf8->pretty;
  my $json_data = $json->encode($menu_tree);
  print $json_data;
}

#### Generate serverpool and vm summary statistic to CSV in www
gen_csv_configuration();

exit 0;

################################################################################
sub gen_orvm {
  my @orvm_folders = ();

  foreach my $orvm_uuid ( @{ $orvm_metadata->get_uuids('manager') } ) {
    my $orvm_label    = $orvm_metadata->get_label( 'manager', $orvm_uuid );
    my $search_string = "$orvm_label";
    my $orvm_folder   = OracleVmMenu::create_folder($orvm_label);

    # Create totals all serverpools
    my $totals_url  = OracleVmMenu::get_url( { type => 'total_serverpools', total_serverpools => $orvm_uuid } );
    my $totals_page = OracleVmMenu::create_page( 'Totals', $totals_url, $search_string );
    push @{ $orvm_folder->{children} }, $totals_page;

    # Generate all Server pool of ORVM
    push( @{ $orvm_folder->{children} }, @{ gen_server_pools( $orvm_uuid, "$orvm_label" ) } );

    push @orvm_folders, $orvm_folder;

  }

  #print Dumper @serverpool_folders;
  return \@orvm_folders;

}

sub gen_server_pools {
  my $orvm_uuid          = shift;
  my $orvm_label         = shift;
  my @serverpool_folders = ();

  #foreach my $serverpool_uuid ( @{ $orvm_metadata->get_uuids( 'server_pool' ) } ) {
  foreach my $serverpool_uuid ( @{ $orvm_metadata->get_arch( $orvm_uuid, 'manager_s', 'server_pool' ) } ) {

    # serverpool folder
    my $serverpool_label      = $orvm_metadata->get_label( 'server_pool', $serverpool_uuid );
    my $search_string         = "$serverpool_label";
    my $serverpool_folder     = OracleVmMenu::create_folder( $serverpool_label, $serverpool_label );
    my $server_total_page_url = OracleVmMenu::get_url( { type => 'total_server', total_server => $serverpool_uuid } );
    my $server_total_page     = OracleVmMenu::create_page( 'Totals', $server_total_page_url, $search_string );
    push @{ $serverpool_folder->{children} }, $server_total_page;

    #push   @serverpool_folders, $server_total_page;
    #$serverpool_folder->{children} = gen_server( $serverpool_uuid, "$serverpool_label" );
    #push @serverpool_folders, $serverpool_folder;

    # Server of this server_pool
    my $servers_array_ref = gen_servers( $serverpool_uuid, "$serverpool_label" );

    #print Dumper $servers_array_ref;
    if ( scalar @{$servers_array_ref} ) {

      # VM folder
      my $server_folder = OracleVmMenu::create_folder( 'Server', $search_string );
      $server_folder->{children} = $servers_array_ref;
      push @{ $serverpool_folder->{children} }, $server_folder;
    }

    push @serverpool_folders, $serverpool_folder;

    # VMs of this server_pool
    my $vms_array_ref = gen_vms( $serverpool_uuid, $search_string );

    #print Dumper $vms_array_ref;
    if ( scalar @{$vms_array_ref} ) {

      # VM folder
      my $vm_folder = OracleVmMenu::create_folder( 'VM', $search_string );
      $vm_folder->{children} = $vms_array_ref;
      push @{ $serverpool_folder->{children} }, $vm_folder;
    }
  }

  #print Dumper @serverpool_folders;
  return \@serverpool_folders;
}

sub gen_servers {
  my $serverpool_uuid = shift;
  my $search_acc      = shift;
  my @server_pages    = ();
  foreach my $server_uuid ( @{ $orvm_metadata->get_arch( $serverpool_uuid, 'server_pool', 'server' ) } ) {

    # server folder
    #print "$server_uuid\n";
    my $server_label    = $orvm_metadata->get_label( 'server', $server_uuid );
    my $search_string   = "$search_acc $server_label";
    my $server_page_url = OracleVmMenu::get_url( { type => 'server', server => $server_uuid } );
    my $server_page     = OracleVmMenu::create_page( $server_label, $server_page_url, $search_string );
    push @server_pages, $server_page;

    #push @{ $server_folder->{children} }, $server_total_page;
  }
  return \@server_pages;
}

sub gen_vms {
  my $serverpool_uuid = shift;
  my $search_acc      = shift;
  my @vm_pages        = ();
  foreach my $vm_uuid ( @{ $orvm_metadata->get_arch( $serverpool_uuid, 'server_pool', 'vm' ) } ) {
    my $vm_label = $orvm_metadata->get_label( 'vm', $vm_uuid );

    #my $vm_mapping    = $orvm_metadata->get_mapping( $vm_uuid );
    my $search_string = "$search_acc $vm_label";
    my $vm_page_url   = OracleVmMenu::get_url( { type => 'vm', vm => $vm_uuid } );
    my $vm_page       = OracleVmMenu::create_page( $vm_label, $vm_page_url, $search_string );
    push @vm_pages, $vm_page;
  }
  return \@vm_pages;
}

################################################################################
############### print serverpool and vm to csv file (configuration)

sub gen_csv_configuration {
  my $mapping_server_pool = OracleVmDataWrapper::get_conf_section('arch-server_pool');
  my $mapping_server_vm   = OracleVmDataWrapper::get_conf_section('arch-vm_server');
  my $server_config       = OracleVmDataWrapper::get_conf_section('spec-server');
  my $vm_config           = OracleVmDataWrapper::get_conf_section('spec-vm');
  my $csv_serverpool      = "$webdir/orvm_serverpool.csv";
  my $csv_vm              = "$webdir/orvm_vm.csv";
  open( my $fw1, '>', "$csv_serverpool" ) || warn( localtime() . ": Cannot open file for results $csv_serverpool: $!" . __FILE__ . ':' . __LINE__ ) && exit;
  open( my $fw2, '>', "$csv_vm" )         || warn( localtime() . ": Cannot open file for results $csv_vm: $!" . __FILE__ . ':' . __LINE__ )         && exit;
  print $fw1 "Server Pool;Server;Hostname;Address;Total Memory [GiB];Socket count;CPU model;Hypervisor type;Hypervisor name;Product name;Bios version\n";
  print $fw2 "Server Pool;Server;VM;Memory [GiB];Cpu Count;Operating system;Domain type\n";

  ###############################################
  ########### Server pool part

  my @servers = @{ OracleVmDataWrapper::get_items( { item_type => 'server' } ) };

  unless ( scalar @servers > 0 ) {
    close($fw2);
  }
  foreach my $server_uuid (@servers) {
    my $cell_server_pool = 'NA';
    foreach my $server_pool ( sort keys %{$mapping_server_pool} ) {
      if ( grep( /$server_uuid/, @{ $mapping_server_pool->{$server_pool} } ) ) {
        my $server_pool_label = $orvm_metadata->get_label( 'server_pool', $server_pool );
        my $server_pool_link  = OracleVmMenu::get_url( { type => 'server_pool-aggr', server_pool => $server_pool } );
        $cell_server_pool = "$server_pool_label";
      }
    }
    my $server_label = $orvm_metadata->get_label( 'server', $server_uuid );
    my $server_link  = OracleVmMenu::get_url( { type => 'server', server => $server_uuid } );
    my $cell_server  = "$server_label";

    my $hostname     = exists $server_config->{$server_uuid}{hostname}        ? $server_config->{$server_uuid}{hostname}        : 'NA';
    my $address      = exists $server_config->{$server_uuid}{ip_address}      ? $server_config->{$server_uuid}{ip_address}      : 'NA';
    my $total_memory = exists $server_config->{$server_uuid}{total_memory}    ? $server_config->{$server_uuid}{total_memory}    : 'NA';
    my $socket_count = exists $server_config->{$server_uuid}{cpu_sockets}     ? $server_config->{$server_uuid}{cpu_sockets}     : 'NA';
    my $cpu_type     = exists $server_config->{$server_uuid}{cpu_type}        ? $server_config->{$server_uuid}{cpu_type}        : 'NA';
    my $hyp_type     = exists $server_config->{$server_uuid}{hypervisor_type} ? $server_config->{$server_uuid}{hypervisor_type} : 'NA';
    my $hyp_name     = exists $server_config->{$server_uuid}{hypervisor_name} ? $server_config->{$server_uuid}{hypervisor_name} : 'NA';
    my $prod_name    = exists $server_config->{$server_uuid}{product_name}    ? $server_config->{$server_uuid}{product_name}    : 'NA';
    my $bios_version = exists $server_config->{$server_uuid}{bios_version}    ? $server_config->{$server_uuid}{bios_version}    : 'NA';

    print $fw1 "$cell_server_pool;$cell_server;$hostname;$address;$total_memory;$socket_count;$cpu_type;$hyp_type;$hyp_name;$prod_name;$bios_version\n";

  }
  close($fw1);
  #############################################
  ########### VM part

  my @vms = @{ OracleVmDataWrapper::get_items( { item_type => 'vm' } ) };
  unless ( scalar @vms > 0 ) {
    close($fw2);
  }
  foreach my $vm_uuid (@vms) {
    my $cell_server_pool = my $cell_server = 'NA';
    foreach my $server ( keys %{$mapping_server_vm} ) {
      if ( grep( /$vm_uuid/, @{ $mapping_server_vm->{$server} } ) ) {
        my $server_label = $orvm_metadata->get_label( 'server', $server );
        my $server_link  = OracleVmMenu::get_url( { type => 'server', server => $server } );
        $cell_server = "$server_label";

        foreach my $server_pool ( sort keys %{$mapping_server_pool} ) {
          if ( grep( /$server/, @{ $mapping_server_pool->{$server_pool} } ) ) {
            my $server_pool_label = $orvm_metadata->get_label( 'server_pool', $server_pool );
            my $server_pool_link  = OracleVmMenu::get_url( { type => 'server_pool-aggr', server_pool => $server_pool } );
            $cell_server_pool = "$server_pool_label";
          }
        }
      }
    }

    my $vm_label = $orvm_metadata->get_label( 'vm', $vm_uuid );
    my $vm_link  = OracleVmMenu::get_url( { type => 'vm', vm => $vm_uuid } );
    my $cell_vm  = "$vm_label";

    my $memory      = exists $vm_config->{$vm_uuid}{memory}      ? $vm_config->{$vm_uuid}{memory}      : 'NA';
    my $cpu_count   = exists $vm_config->{$vm_uuid}{cpu_count}   ? $vm_config->{$vm_uuid}{cpu_count}   : 'NA';
    my $os_type     = exists $vm_config->{$vm_uuid}{os_type}     ? $vm_config->{$vm_uuid}{os_type}     : 'NA';
    my $domain_type = exists $vm_config->{$vm_uuid}{domain_type} ? $vm_config->{$vm_uuid}{domain_type} : 'NA';

    print $fw2 "$cell_server_pool;$cell_server;$cell_vm;$memory;$cpu_count;$os_type;$domain_type\n";
  }

  close($fw2);
}
