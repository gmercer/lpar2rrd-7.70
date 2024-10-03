use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib qw(error read_json);
use OracleDBDataWrapper;
use OracleDBMenu;
use HostCfg;
use XoruxEdition;

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;
my %creds         = %{ HostCfg::getHostConnections("OracleDB") };
my $inputdir      = $ENV{INPUTDIR};
my $bindir        = $ENV{BINDIR};
my $main_data_dir = "$inputdir/data/OracleDB";
my $tmp_dir       = "$inputdir/tmp";
my $count_file    = "$tmp_dir/OracleDB_count.txt";
my $log_err_file  = "$inputdir/html/.b";
my $log_err       = "L_ERR";


my $totals_dir    = "$main_data_dir/Totals";

my @standalones;
my @RACs;
my @Multitenants;
my $instance_names;
my %arc;
################################################################################

unless ( -d $main_data_dir ) {
  exit;
}

if ( !keys %creds ) {
  exit 0;
}

fill_arrays();

@standalones = sort { lc($a) cmp lc($b) } @standalones;
@RACs        = sort { lc($a) cmp lc($b) } @RACs;

my $standalone_count  = $#standalones + 1;
my $RAC_count         = $#RACs + 1;
my $Multitenant_count = $#Multitenants + 1;

open my $fh, '>', $count_file;
print $fh "OracleDB Standalone : $standalone_count\n";
print $fh "OracleDB RAC : $RAC_count\n";
print $fh "OracleDB Multitenant : $Multitenant_count\n";
close $fh;

my $menu_tree        = OracleDBMenu::create_folder('OracleDB');
my $hosts_tree       = OracleDBMenu::create_folder('Hosts');
my $host_items       = OracleDBMenu::create_folder('Items');
my $standalone_tree  = OracleDBMenu::create_folder('Standalone');
my $RAC              = OracleDBMenu::create_folder('RAC');
my $multitenant_tree = OracleDBMenu::create_folder('Multitenant');
my %sub_folders;
my %main_folders;
my %main_folders_subg;

my $host_names_all = get_hosts();
my $hosts_total    = OracleDBMenu::create_page( "Total", OracleDBMenu::get_url( { type => 'hosts_Total', host => "not_needed", server => "hostname" } ), "Hosts Total" );

for my $host_name ( keys %{$host_names_all} ) {
  my $uuid = OracleDBDataWrapper::md5_string("$host_name");
  my $page = OracleDBMenu::create_page( $host_name, OracleDBMenu::get_url( { type => 'host_metrics', host => $host_name, server => "hostname", id => $uuid } ), "Hosts $host_name" );
  push( @{ $host_items->{children} }, $page );
  $arc{$uuid}{server} = "hostname";
  $arc{$uuid}{host}   = $host_name;
  $arc{$uuid}{type}   = "Items";
  $arc{$uuid}{label}  = $host_name;
}
push( @{ $hosts_tree->{children} }, $hosts_total, $host_items );

foreach my $si_alias (@standalones) {
  my $host   = $creds{$si_alias}{host};
  my $server = $si_alias;
  my $uuid   = OracleDBDataWrapper::get_dbuuid($si_alias);

  my $main_group          = $creds{$si_alias}{menu_group};
  my $sub_group           = $creds{$si_alias}{menu_subgroup};
  my $dataguard           = $creds{$si_alias}{dataguard};
  my $dataguard_instances = OracleDBMenu::create_folder("Data Guard");

  my $overview_page = OracleDBMenu::create_page( 'Overview', OracleDBMenu::get_url( { type => 'Overview', host => $host, server => $server } ), "$server Overview" );
  my $act_instance  = OracleDBMenu::create_folder( $server, "$main_group $sub_group $server" );
  my $conf_page     = OracleDBMenu::create_page( 'Configuration', OracleDBMenu::get_url( { type => 'configuration', host => $host, server => $server, id => $uuid } ), "$main_group $sub_group $server Configuration" );
  my $waitclass_pg  = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "$host", server => $server } ), "$main_group $sub_group $server Wait class" );

  #  my $services_pg   = OracleDBMenu::create_page( 'Services', OracleDBMenu::get_url( { type => 'Services', host => "not_needed", server => $server } ), "$server Services");
  my $datafls_page = OracleDBMenu::create_page( 'Datafiles', OracleDBMenu::get_url( { type => 'datafiles', host => "not_needed", server => $server } ), "$server Datafiles" );
  my $capacity     = OracleDBMenu::create_page( 'Capacity',  OracleDBMenu::get_url( { type => 'Capacity',  host => "$host",      server => $server } ), "$main_group $sub_group $server Capacity" );

  my $services_pg = OracleDBMenu::create_page( 'Services', OracleDBMenu::get_url( { type => 'Services', host => "$host", server => $server } ), "$main_group $sub_group $server Services" );

  if ( $dataguard and $dataguard->[0]->{hosts}->[0] and $dataguard->[0]->{hosts}->[0] ne "" ) {
    $conf_page = OracleDBMenu::create_page( 'Configuration', OracleDBMenu::get_url( { type => 'configuration_dg', host => $host, server => $server } ), "$main_group $sub_group $server Configuration" );
    my @dg_list = @{$dataguard};
    for my $i ( 0 .. $#dg_list ) {
      my @hosts              = @{ $dg_list[$i]->{hosts} };
      my $dataguard_instance = OracleDBMenu::create_folder("DG-$i");
      foreach my $dg_host (@hosts) {
        $dataguard_instance->{children} = [ $overview_page, $conf_page, $datafls_page, $capacity, cpu_info( "$uuid", $dg_host, $server ), io( "$uuid", $dg_host, $server ), data( "$uuid", $dg_host, $server ), sga_data( "$uuid", $dg_host, $server ), session_info( "$uuid", $dg_host, $server ), sql_query( "$uuid", $dg_host, $server ), network( "$uuid", $dg_host, $server ), ratio( "$uuid", $dg_host, $server ), disk_latency( "$uuid", $dg_host, $server ), $waitclass_pg, $services_pg ];
        last;
      }
      push( @{ $dataguard_instances->{children} }, $dataguard_instance );

      #print Dumper \@hosts;
    }
  }

  $act_instance->{children} = [ $overview_page, $conf_page, $datafls_page, $capacity, cpu_info( "$uuid", $host, $server ), io( "$uuid", $host, $server ), data( "$uuid", $host, $server ), sga_data( "$uuid", $host, $server ), session_info( "$uuid", $host, $server ), sql_query( "$uuid", $host, $server ), network( "$uuid", $host, $server ), ratio( "$uuid", $host, $server ), disk_latency( "$uuid", $host, $server ), $waitclass_pg, $services_pg ];

  if ( $dataguard and $dataguard->[0]->{hosts}->[0] and $dataguard->[0]->{hosts}->[0] ne "" ) {
    push( @{ $act_instance->{children} }, $dataguard_instances );
  }

  if ( $main_group and $main_group ne "" ) {
    if ( !$main_folders{$main_group} ) {
      $main_folders{$main_group} = OracleDBMenu::create_folder( $main_group, $main_group );
    }
    if ( $sub_group and $sub_group ne "" ) {
      if ( !$sub_folders{$sub_group} ) {
        $sub_folders{$sub_group} = OracleDBMenu::create_folder( $sub_group, "$main_group $sub_group" );
      }
      push( @{ $sub_folders{$sub_group}->{children} }, $act_instance );
      $main_folders_subg{$main_group}{$sub_group} = 1;
    }
    else {
      push( @{ $main_folders{$main_group}->{children} }, $act_instance );
    }
  }
  else {
    push( @{ $standalone_tree->{children} }, $act_instance );
  }
  if ( $uuid ne "" ) {
    $arc{$uuid}{server} = $server;
    $arc{$uuid}{host}   = $host;
    $arc{$uuid}{type}   = "Standalone";
    $arc{$uuid}{alias}  = $si_alias;
  }
}

foreach my $si_alias (@RACs) {
  my $server = $si_alias;
  my $can_read;
  my $log_err_v = premium();
  my $ref;

  ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$server/instance_names.json");
  undef $instance_names;
  $instance_names = $ref;

  my $parent = OracleDBDataWrapper::get_dbuuid($si_alias);
  if ( $parent ne "" ) {
    $arc{$parent}{server}   = $server;
    $arc{$parent}{alias}    = $si_alias;
    $arc{$parent}{type}     = "RAC";
    $arc{$parent}{children} = [];
  }
  my $act_instance        = OracleDBMenu::create_folder( $server, $server );
  my $rac_instances       = OracleDBMenu::create_folder("Instances");
  my $global_cache        = OracleDBMenu::create_folder("Global cache");
  my $total               = OracleDBMenu::create_folder("Total");
  my $total_pdb           = OracleDBMenu::create_folder("Total");
  my $dataguard           = $creds{$si_alias}{dataguard};
  my $dataguard_instances = OracleDBMenu::create_folder("Data Guard");

  my $conf_page    = OracleDBMenu::create_page( 'Configuration', OracleDBMenu::get_url( { type => 'configuration_S', host => "not_needed", server => $server, id => $parent } ), "$server Configuration" );
  my $datafls_page = OracleDBMenu::create_page( 'Datafiles',     OracleDBMenu::get_url( { type => 'datafiles',       host => "not_needed", server => $server } ),                "$server Datafiles" );

  #  my $waitclass_page  = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'waitclass', host => "not_needed", server => $server } ));
  my $waitclass_page = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "not_needed", server => $server } ), "$server Wait class" );

  #  my $datafiles_page = OracleDBMenu::create_page( 'Datafiles', OracleDBMenu::get_url( { type => 'IO_Read_Write_per_datafile', host => "not_needed", server => $server } ));
  my $services_page = OracleDBMenu::create_page( 'Services', OracleDBMenu::get_url( { type => 'Services', host => "not_needed", server => $server } ), "$server Services" );

  my $aggr_hosts = "aggregated";

  my $cr_index = 0;
  foreach my $current_host ( @{ $creds{$si_alias}{hosts} } ) {

    my $host = $current_host;
    $aggr_hosts .= "_$host";
    my $rac_instance;
    my $host_menu;
    if ( $can_read and $instance_names->{$host} ) {
      $host_menu = $instance_names->{$host};
    }
    else {
      $host_menu = $host;
    }
    my $child = OracleDBDataWrapper::md5_string("$si_alias,$current_host");
    if ( $parent ne "" ) {
      $arc{$child}{server}     = $server;
      $arc{$child}{host}       = $current_host;
      $arc{$child}{alias}      = $si_alias;
      $arc{$child}{type}       = "instance";
      $arc{$child}{parents}[0] = $parent;
      $arc{$child}{label}      = $host_menu;
      push( @{ $arc{$parent}{children} }, $child );
    }
    $rac_instance = OracleDBMenu::create_folder( $host_menu, "$server $host_menu" );
    my $waitclass_pg = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "$host", server => $server } ), "$server $host_menu Wait class" );

    if ( $creds{$si_alias}{type} ne "RAC_Multitenant" ) {
      $rac_instance->{children} = [ cpu_info( "$child", $host, $server, $host_menu ), io( "$child", $host, $server, $host_menu ), data( "$child", $host, $server, $host_menu ), sga_data( "$child", $host, $server, $host_menu ), session_info( "$child", $host, $server, $host_menu ), sql_query( "$child", $host, $server, $host_menu ), network( "$child", $host, $server, $host_menu ), ratio( "$child", $host, $server, $host_menu ), disk_latency( "$child", $host, $server, $host_menu ), $waitclass_pg ];

    }
    else {
      my $overview_page = OracleDBMenu::create_page( 'Overview', OracleDBMenu::get_url( { type => 'Overview', host => $host, server => $server } ), "$server Overview" );
      my $PDBs          = OracleDBMenu::create_folder( "PDBs", "PDBs" );
      my $conf_page     = OracleDBMenu::create_page( 'Configuration', OracleDBMenu::get_url( { type => 'configuration_Multitenant', host => $host, server => $server, id => $parent } ), "$server Configuration" );
      my $waitclass_pg  = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "$host", server => $server } ), "$server Wait class" );
      my $datafls_page  = OracleDBMenu::create_page( 'Datafiles', OracleDBMenu::get_url( { type => 'datafiles', host => "not_needed", server => $server } ), "$server Datafiles" );
      my $capacity      = OracleDBMenu::create_page( 'Capacity', OracleDBMenu::get_url( { type => 'Capacity', host => "$host", server => $server } ), "$server Capacity" );

      #  my $services_pg   = OracleDBMenu::create_page( 'Services', OracleDBMenu::get_url( { type => 'Services', host => "not_needed", server => $server } ), "$server Services");
      #print Dumper OracleDBMenu::get_url( { type => 'configuration', host => $host, server => $server } );
      #print "\nseparator\n";
      my $services_pg = OracleDBMenu::create_page( 'Services', OracleDBMenu::get_url( { type => 'Services', host => "$host", server => $server } ), " $server Services" );

      #print Dumper $conf_page;
      my @pdbs;
      if ( $creds{$si_alias}{services} ) {
        @pdbs = @{ $creds{$si_alias}{services}[$cr_index] };
        shift(@pdbs);
        my $aggr_hosts = "aggregated";
        my ( $can_read_pdb, $ref_pdb ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
        my $pdb_names = $ref_pdb;

        foreach my $current_host (@pdbs) {

          my $host_pdb = $current_host;
          my $host     = "$creds{$si_alias}{hosts}[$cr_index],$current_host";
          $aggr_hosts .= "_$host";
          my $pdb_instance;
          my $host_menu;
          my $child_pdb = OracleDBDataWrapper::md5_string("$si_alias,$current_host");

          my $conf_pdb = OracleDBMenu::create_page( 'Configuration', OracleDBMenu::get_url( { type => 'configuration_PDB', host => "groups_$host", server => $server } ), "$server Configuration" );
          if ( $can_read_pdb and $pdb_names->{$host_pdb} ) {
            $host_menu = $pdb_names->{$host_pdb};
          }
          else {
            $host_menu = $host;
          }

          if ( $parent ne "" and $child_pdb ne "" ) {
            $arc{$child_pdb}{server}     = $server;
            $arc{$child_pdb}{host}       = $host;
            $arc{$child_pdb}{alias}      = $si_alias;
            $arc{$child_pdb}{type}       = "pdbs";
            $arc{$child_pdb}{parents}[0] = $parent;
            $arc{$child_pdb}{label}      = $host_menu;
            push( @{ $arc{$parent}{children} }, $child_pdb );
          }
          $pdb_instance = OracleDBMenu::create_folder( $host_menu, "$server $host_menu" );
          my $waitclass_pg = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "$creds{$si_alias}{hosts}[0]_PDB_$host", server => $server } ), "$server $host_menu Wait class" );

          $pdb_instance->{children} = [ $conf_pdb, io( "", $host, $server, $host_menu ), data( "", $host, $server, $host_menu ), sga_data( "", $host, $server, $host_menu ), session_info( "", $host, $server, $host_menu, "PDB" ), sql_query( "", $host, $server, $host_menu ), network( "", $host, $server, $host_menu ), ratio( "", $host, $server, $host_menu ), disk_latency( "", "$host", $server, $host_menu ), $waitclass_pg ];
          push( @{ $PDBs->{children} }, $pdb_instance );
        }

        my $ses_page          = OracleDBMenu::create_page( 'Session',   OracleDBMenu::get_url( { type => 'aggr_Session_info', host => $aggr_hosts, server => $server } ), "$server Session" );
        my $aggr_ratio_page   = OracleDBMenu::create_page( 'Ratio',     OracleDBMenu::get_url( { type => 'aggr_Ratio',        host => $aggr_hosts, server => $server } ), "$server Ratio" );
        my $aggr_network_page = OracleDBMenu::create_page( 'Network',   OracleDBMenu::get_url( { type => 'aggr_Network',      host => $aggr_hosts, server => $server } ), "$server Network" );
        my $aggr_sql_page     = OracleDBMenu::create_page( 'SQL query', OracleDBMenu::get_url( { type => 'aggr_SQL_query',    host => $aggr_hosts, server => $server } ), "$server SQL query" );
        my $waitclass_page_T = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "not_needed", server => $server } ), "$server Wait class" );
        if ( $cr_index == 0 ) {
          push( @{ $total_pdb->{children} }, io( "", $aggr_hosts, $server ), data( "", $aggr_hosts, $server ), sga_data( "", $aggr_hosts, $server ), $ses_page, $aggr_sql_page, $aggr_network_page, $aggr_ratio_page, disk_latency( "", $aggr_hosts, $server ), $waitclass_page_T );
        }
      }
      $rac_instance->{children} = [ $overview_page, $conf_page, $datafls_page, $capacity, cpu_info( "$child", $host, $server ), io( "$child", $host, $server ), data( "$child", $host, $server ), network( "$child", $host, $server ), ratio( "$child", $host, $server ), disk_latency( "$child", $host, $server ), $waitclass_pg, $services_pg, $total_pdb, $PDBs ];
    }
    push( @{ $rac_instances->{children} }, $rac_instance );
    $cr_index++;
  }
  if ( $parent ne "" ) {
    $arc{$parent}{host} = $aggr_hosts;
  }
  my $intercon_page = OracleDBMenu::create_page( 'Interconnect', OracleDBMenu::get_url( { type => 'Interconnect', host => $aggr_hosts, server => $server } ), "$server Interconnect" );

  my $gchvone_page      = OracleDBMenu::create_page( 'View 1',    OracleDBMenu::get_url( { type => 'viewone',           host => $aggr_hosts, server => $server } ), "$server View 1" );
  my $gchvtwo_page      = OracleDBMenu::create_page( 'View 2',    OracleDBMenu::get_url( { type => 'viewtwo',           host => $aggr_hosts, server => $server } ), "$server View 2" );
  my $gchvthree_page    = OracleDBMenu::create_page( 'View 3',    OracleDBMenu::get_url( { type => 'viewthree',         host => $aggr_hosts, server => $server } ), "$server View 3" );
  my $gchvfour_page     = OracleDBMenu::create_page( 'View 4',    OracleDBMenu::get_url( { type => 'viewfour',          host => $aggr_hosts, server => $server } ), "$server View 4" );
  my $gchvfive_page     = OracleDBMenu::create_page( 'View 5',    OracleDBMenu::get_url( { type => 'viewfive',          host => $aggr_hosts, server => $server } ), "$server View 5" );
  my $overview_page     = OracleDBMenu::create_page( 'Overview',  OracleDBMenu::get_url( { type => 'Overview',          host => $aggr_hosts, server => $server } ), "$server Overview" );
  my $ses_page          = OracleDBMenu::create_page( 'Session',   OracleDBMenu::get_url( { type => 'aggr_Session_info', host => $aggr_hosts, server => $server } ), "$server Session" );
  my $aggr_ratio_page   = OracleDBMenu::create_page( 'Ratio',     OracleDBMenu::get_url( { type => 'aggr_Ratio',        host => $aggr_hosts, server => $server } ), "$server Ratio" );
  my $aggr_network_page = OracleDBMenu::create_page( 'Network',   OracleDBMenu::get_url( { type => 'aggr_Network',      host => $aggr_hosts, server => $server } ), "$server Network" );
  my $aggr_sql_page     = OracleDBMenu::create_page( 'SQL query', OracleDBMenu::get_url( { type => 'aggr_SQL_query',    host => $aggr_hosts, server => $server } ), "$server SQL query" );
  my @host_parts;

  if ( $aggr_hosts =~ /aggregated_/ ) {
    @host_parts = split( /_/, $aggr_hosts );
  }
  my $capacity = OracleDBMenu::create_page( 'Capacity', OracleDBMenu::get_url( { type => 'Capacity', host => "$host_parts[1]", server => $server } ), "$server Capacity" );

  if ( $dataguard and $dataguard->[0]->{hosts}->[0] and $dataguard->[0]->{hosts}->[0] ne "" ) {
    $conf_page = OracleDBMenu::create_page( 'Configuration', OracleDBMenu::get_url( { type => 'configuration_dg', host => "not_needed", server => $server } ), "$server Configuration" );

  }
  push( @{ $global_cache->{children} }, cache( $aggr_hosts, $server ), $gchvone_page, $gchvtwo_page, $gchvthree_page, $gchvfour_page, $gchvfive_page );
  push( @{ $act_instance->{children} }, $overview_page, $conf_page, $intercon_page, $datafls_page, $capacity, $global_cache, $total );
  push( @{ $act_instance->{children} }, $rac_instances );
  if ( $dataguard and $dataguard->[0]->{hosts}->[0] and $dataguard->[0]->{hosts}->[0] ne "" ) {
    push( @{ $act_instance->{children} }, $dataguard_instances );
  }
  my $services_page_T = OracleDBMenu::create_page( 'Services', OracleDBMenu::get_url( { type => 'Services', host => "not_needed", server => $server } ), "$server Services" );
  if ( $creds{$si_alias}{type} ne "RAC_Multitenant" ) {
    my $waitclass_page_T = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "not_needed", server => $server } ), "$server Wait class" );
    push( @{ $total->{children} }, cpu_info( "", $aggr_hosts, $server ), io( "", $aggr_hosts, $server ), data( "", $aggr_hosts, $server ), sga_data( "", $aggr_hosts, $server ), $ses_page, $aggr_sql_page, $aggr_network_page, $aggr_ratio_page, disk_latency( "", $aggr_hosts, $server ), $waitclass_page_T, $services_page_T );
  }
  else {
    my $waitclass_page_T = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "_PDB_", server => $server } ), "$server Wait class" );
    push( @{ $total->{children} }, cpu_info( "", $aggr_hosts, $server ), io( "", $aggr_hosts, $server ), data( "", $aggr_hosts, $server ), sga_data( "", $aggr_hosts, $server ), $aggr_sql_page, $aggr_network_page, $aggr_ratio_page, disk_latency( "", $aggr_hosts, $server ), $waitclass_page_T, $services_page_T );
  }
  my $main_group = $creds{$si_alias}{menu_group};
  my $sub_group  = $creds{$si_alias}{menu_subgroup};

  if ( $main_group and $main_group ne "" ) {
    if ( !$main_folders{$main_group} ) {
      $main_folders{$main_group} = OracleDBMenu::create_folder($main_group);
    }
    if ( $sub_group and $sub_group ne "" ) {
      if ( !$sub_folders{$sub_group} ) {
        $sub_folders{$sub_group} = OracleDBMenu::create_folder($sub_group);
      }
      push( @{ $sub_folders{$sub_group}->{children} }, $act_instance );
      $main_folders_subg{$main_group}{$sub_group} = 1;
    }
    else {
      push( @{ $main_folders{$main_group}->{children} }, $act_instance );
    }
  }
  else {
    push( @{ $RAC->{children} }, $act_instance );
  }
  if ( ( length($log_err_v) + 1 ) == length($log_err) || !-e $log_err_file ) {
    last;
  }
}

foreach my $si_alias (@Multitenants) {
  my $host                = $creds{$si_alias}{host};
  my $server              = $si_alias;
  my $main_group          = $creds{$si_alias}{menu_group};
  my $sub_group           = $creds{$si_alias}{menu_subgroup};
  my $parent              = OracleDBDataWrapper::get_dbuuid("$si_alias");
  my $total               = OracleDBMenu::create_folder("Total");
  my $dataguard           = $creds{$si_alias}{dataguard};
  my $dataguard_instances = OracleDBMenu::create_folder("Data Guard");

  if ( $parent ne "" ) {
    $arc{$parent}{server}   = $server;
    $arc{$parent}{alias}    = $si_alias;
    $arc{$parent}{host}     = $host;
    $arc{$parent}{type}     = "Multitenant";
    $arc{$parent}{children} = [];
  }
  my $overview_page = OracleDBMenu::create_page( 'Overview', OracleDBMenu::get_url( { type => 'Overview', host => $host, server => $server, id => "$parent" } ), "$server Overview" );
  my $act_instance  = OracleDBMenu::create_folder( $server, "$main_group $sub_group $server" );
  my $PDBs          = OracleDBMenu::create_folder( "PDBs", "$main_group $sub_group PDBs" );
  my $conf_page     = OracleDBMenu::create_page( 'Configuration', OracleDBMenu::get_url( { type => 'configuration_Multitenant', host => $host, server => $server, id => $parent } ), "$main_group $sub_group $server Configuration" );
  my $waitclass_pg  = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "$host", server => $server } ), "$main_group $sub_group $server Wait class" );
  my $datafls_page  = OracleDBMenu::create_page( 'Datafiles', OracleDBMenu::get_url( { type => 'datafiles', host => "not_needed", server => $server } ), "$server Datafiles" );
  my $capacity      = OracleDBMenu::create_page( 'Capacity', OracleDBMenu::get_url( { type => 'Capacity', host => "$host", server => $server } ), "$main_group $sub_group $server Capacity" );

  #  my $services_pg   = OracleDBMenu::create_page( 'Services', OracleDBMenu::get_url( { type => 'Services', host => "not_needed", server => $server } ), "$server Services");
  #print Dumper OracleDBMenu::get_url( { type => 'configuration', host => $host, server => $server } );
  #print "\nseparator\n";
  my $services_pg = OracleDBMenu::create_page( 'Services', OracleDBMenu::get_url( { type => 'Services', host => "$host", server => $server } ), "$main_group $sub_group $server Services" );

  #print Dumper $conf_page;
  my @pdbs;
  if ( $creds{$si_alias}{services} ) {
    @pdbs = @{ $creds{$si_alias}{services} };
    my $aggr_hosts = "aggregated";
    my ( $can_read_pdb, $ref_pdb ) = Xorux_lib::read_json("$main_data_dir/$server/pdb_names.json");
    my $pdb_names = $ref_pdb;

    foreach my $current_host (@pdbs) {
      my $child = OracleDBDataWrapper::md5_string("$si_alias,$current_host");
      if ( $parent ne "" ) {
        $arc{$child}{server}     = $server;
        $arc{$child}{host}       = $current_host;
        $arc{$child}{alias}      = $si_alias;
        $arc{$child}{type}       = "pdbs";
        $arc{$child}{parents}[0] = $parent;
        push( @{ $arc{$parent}{children} }, $child );
      }
      my $host = $current_host;
      $aggr_hosts .= "_$host";
      my $pdb_instance;
      my $host_menu;
      my $conf_pdb = OracleDBMenu::create_page( 'Configuration', OracleDBMenu::get_url( { type => 'configuration_PDB', host => "groups_$current_host", server => $server } ), "$main_group $sub_group $server Configuration" );
      if ( $can_read_pdb and $pdb_names->{$host} ) {
        $host_menu = $pdb_names->{$host};
      }
      else {
        $host_menu = $host;
      }
      if ( $parent ne "" ) {
        $arc{$child}{label} = $host_menu;
      }
      $pdb_instance = OracleDBMenu::create_folder( $host_menu, "$server $host_menu" );
      my $waitclass_pg = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "$creds{$si_alias}{host}_PDB_$host", server => $server } ), "$server $host_menu Wait class" );

      $pdb_instance->{children} = [ $conf_pdb, io( "$child", $host, $server, $host_menu ), data( "$child", $host, $server, $host_menu ), sga_data( "$child", $host, $server, $host_menu ), session_info( "$child", $host, $server, $host_menu, "PDB" ), sql_query( "$child", $host, $server, $host_menu ), network( "$child", $host, $server, $host_menu ), ratio( "$child", $host, $server, $host_menu ), disk_latency( "$child", $host, $server, $host_menu ), $waitclass_pg ];
      push( @{ $PDBs->{children} }, $pdb_instance );
    }

    my $ses_page          = OracleDBMenu::create_page( 'Session',   OracleDBMenu::get_url( { type => 'aggr_Session_info', host => $aggr_hosts, server => $server } ), "$server Session" );
    my $aggr_ratio_page   = OracleDBMenu::create_page( 'Ratio',     OracleDBMenu::get_url( { type => 'aggr_Ratio',        host => $aggr_hosts, server => $server } ), "$server Ratio" );
    my $aggr_network_page = OracleDBMenu::create_page( 'Network',   OracleDBMenu::get_url( { type => 'aggr_Network',      host => $aggr_hosts, server => $server } ), "$server Network" );
    my $aggr_sql_page     = OracleDBMenu::create_page( 'SQL query', OracleDBMenu::get_url( { type => 'aggr_SQL_query',    host => $aggr_hosts, server => $server } ), "$server SQL query" );
    my $waitclass_page_T  = OracleDBMenu::create_page( 'Wait class', OracleDBMenu::get_url( { type => 'Wait_class_Main', host => "not_needed", server => $server } ), "$server Wait class" );

    push( @{ $total->{children} }, io( "", $aggr_hosts, $server ), data( "", $aggr_hosts, $server ), sga_data( "", $aggr_hosts, $server ), $ses_page, $aggr_sql_page, $aggr_network_page, $aggr_ratio_page, disk_latency( "", $aggr_hosts, $server ), $waitclass_page_T );

  }
  if ( $dataguard and $dataguard->[0]->{hosts}->[0] and $dataguard->[0]->{hosts}->[0] ne "" ) {
    $conf_page = OracleDBMenu::create_page( 'Configuration', OracleDBMenu::get_url( { type => 'configuration_dg', host => "not_needed", server => $server } ), "$main_group $sub_group $server Configuration" );
  }

  $act_instance->{children} = [ $overview_page, $conf_page, $datafls_page, $capacity, cpu_info( "$parent", $host, $server ), io( "$parent", $host, $server ), data( "$parent", $host, $server ), network( "$parent", $host, $server ), ratio( "$parent", $host, $server ), disk_latency( "$parent", $host, $server ), $waitclass_pg, $services_pg, $total, $PDBs ];

  if ( $dataguard and $dataguard->[0]->{hosts}->[0] and $dataguard->[0]->{hosts}->[0] ne "" ) {
    push( @{ $act_instance->{children} }, $dataguard_instances );
  }
  if ( $main_group and $main_group ne "" ) {
    if ( !$main_folders{$main_group} ) {
      $main_folders{$main_group} = OracleDBMenu::create_folder( $main_group, $main_group );
    }
    if ( $sub_group and $sub_group ne "" ) {
      if ( !$sub_folders{$sub_group} ) {
        $sub_folders{$sub_group} = OracleDBMenu::create_folder( $sub_group, "$main_group $sub_group" );
      }
      push( @{ $sub_folders{$sub_group}->{children} }, $act_instance );
      $main_folders_subg{$main_group}{$sub_group} = 1;
    }
    else {
      push( @{ $main_folders{$main_group}->{children} }, $act_instance );
    }
  }
  else {
    push( @{ $multitenant_tree->{children} }, $act_instance );
  }
}

fill_mainfolders();

my $t_conf_page     = OracleDBMenu::create_page( 'Total',         OracleDBMenu::get_url( { type => 'configuration_Total', host => "groups__OracleDB", server => "not_needed" } ) );
my $health_sts_page = OracleDBMenu::create_page( 'Health Status', OracleDBMenu::get_url( { type => 'healthstatus',        host => "not_needed",       server => "not_needed" } ) );
my $topten_page     = OracleDBMenu::create_page( 'DB TOP',        OracleDBMenu::get_url( { type => 'topten_oracledb',     host => "not_needed",       server => "not_needed" } ) );
$menu_tree->{children} = [ $t_conf_page, $health_sts_page, $topten_page, $hosts_tree ];
for my $main_folder ( keys %main_folders ) {
  my $t_cnf_page = OracleDBMenu::create_page( 'Total', OracleDBMenu::get_url( { type => 'configuration_Total', host => "groups_$main_folder,", server => "not_needed" } ) );
  unshift( @{ $main_folders{$main_folder}->{children} }, $t_cnf_page );
  push( @{ $menu_tree->{children} }, $main_folders{$main_folder} );
}

if ( $standalone_tree->{children}->[0] ) {
  push( @{ $menu_tree->{children} }, $standalone_tree );
}

if ( $RAC->{children}->[0] ) {
  push( @{ $menu_tree->{children} }, $RAC );
}

if ( $multitenant_tree->{children}->[0] ) {
  push( @{ $menu_tree->{children} }, $multitenant_tree );
}

#print as JSON
Xorux_lib::write_json( "$tmp_dir/menu_oracledb.json", $menu_tree );
print ":)";
Xorux_lib::write_json( "$totals_dir/arc.json", \%arc );

exit 0;
################################################################################

sub fill_mainfolders {

  for my $main_grp ( keys %main_folders_subg ) {
    for my $sub_grp ( keys %{ $main_folders_subg{$main_grp} } ) {
      my $t_conf_page = OracleDBMenu::create_page( 'Total', OracleDBMenu::get_url( { type => 'configuration_Total', host => "groups_$main_grp,$sub_grp", server => "not_needed" } ) );
      unshift( @{ $sub_folders{$sub_grp}->{children} }, $t_conf_page );
      push( @{ $main_folders{$main_grp}->{children} }, $sub_folders{$sub_grp} );
    }
  }
}

sub cpu_info {
  my $type      = shift;
  my $host      = shift;
  my $server    = shift;
  my $host_menu = shift;
  $host_menu = defined $host_menu ? $host_menu : "";
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $agg        = "";

  if ( $host =~ m/^aggregated/ ) {
    $agg = "aggr_";
  }

  my $cpu_usage = OracleDBMenu::create_page( 'CPU', OracleDBMenu::get_url( { type => "$agg" . "CPU_info", host => $host, server => $server, id => "$type" } ), "$main_group $sub_group $server $host_menu CPU" );

  return $cpu_usage;
}

sub network {
  my $type      = shift;
  my $host      = shift;
  my $server    = shift;
  my $host_menu = shift;
  $host_menu = defined $host_menu ? $host_menu : "";
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $network_page = OracleDBMenu::create_page( 'Network', OracleDBMenu::get_url( { type => "Network", host => $host, server => $server, id => "$type" } ), "$main_group $sub_group $server  $host_menu Network" );

  return $network_page;
}

sub session_info {
  my $type         = shift;
  my $host         = shift;
  my $server       = shift;
  my $host_menu    = shift;
  my $pdb          = shift;
  my $session_info = 'Session_info';
  if ($pdb) {
    $session_info .= "_PDB";
  }
  $host_menu = defined $host_menu ? $host_menu : "";
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $sesinfo    = OracleDBMenu::create_page( 'Session', OracleDBMenu::get_url( { type => "$session_info", host => $host, server => $server, id => "$type" } ), "$main_group $sub_group $server $host_menu Session" );

  return $sesinfo;
}

sub sql_query {
  my $type      = shift;
  my $host      = shift;
  my $server    = shift;
  my $host_menu = shift;
  $host_menu = defined $host_menu ? $host_menu : "";
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $sql_q      = OracleDBMenu::create_page( 'SQL query', OracleDBMenu::get_url( { type => "SQL_query", host => $host, server => $server, id => "$type" } ), "$main_group $sub_group $server $host_menu SQL query" );

  return $sql_q;
}

sub ratio {
  my $type      = shift;
  my $host      = shift;
  my $server    = shift;
  my $host_menu = shift;
  $host_menu = defined $host_menu ? $host_menu : "";
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $ratio      = OracleDBMenu::create_page( 'Ratio', OracleDBMenu::get_url( { type => "Ratio", host => $host, server => $server, id => "$type" } ), "$main_group $sub_group $server $host_menu Ratio" );

  return $ratio;
}

sub cache {
  my $host      = shift;
  my $server    = shift;
  my $host_menu = shift;
  $host_menu = defined $host_menu ? $host_menu : "";
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $cache      = OracleDBMenu::create_page( 'Global cache', OracleDBMenu::get_url( { type => 'Cache', host => $host, server => $server } ), "$main_group $sub_group $server $host_menu Global cache" );

  return $cache;
}

sub disk_latency {
  my $type      = shift;
  my $host      = shift;
  my $server    = shift;
  my $host_menu = shift;
  $host_menu = defined $host_menu ? $host_menu : "";
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $cache      = OracleDBMenu::create_page( 'Latency', OracleDBMenu::get_url( { type => 'Disk_latency', host => $host, server => $server, id => "$type" } ), "$main_group $sub_group $server $host_menu Latency" );

  return $cache;
}

sub io {
  my $type      = shift;
  my $host      = shift;
  my $server    = shift;
  my $host_menu = shift;
  $host_menu = defined $host_menu ? $host_menu : "";
  my $agg = "";
  if ( $host =~ m/^aggregated/ ) {
    $agg = "aggr_";
  }
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $io         = OracleDBMenu::create_page( 'IO', OracleDBMenu::get_url( { type => $agg . "Data_rate", host => $host, server => $server, id => "$type" } ), "$main_group $sub_group $server $host_menu IO" );

  return $io;
}

sub data {
  my $type      = shift;
  my $host      = shift;
  my $server    = shift;
  my $agg       = "";
  my $host_menu = shift;
  $host_menu = defined $host_menu ? $host_menu : "";
  if ( $host =~ m/^aggregated/ ) {
    $agg = "aggr_";
  }
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $data       = OracleDBMenu::create_page( 'Data', OracleDBMenu::get_url( { type => $agg . "Datarate", host => $host, server => $server, id => "$type" } ), "$main_group $sub_group $server $host_menu Data" );

  return $data;
}

sub sga_data {
  my $type      = shift;
  my $host      = shift;
  my $server    = shift;
  my $host_menu = shift;
  $host_menu = defined $host_menu ? $host_menu : "";
  my $main_group = defined $creds{$server}{menu_group}    ? $creds{$server}{menu_group}    : "";
  my $sub_group  = defined $creds{$server}{menu_subgroup} ? $creds{$server}{menu_subgroup} : "";
  my $therest    = OracleDBMenu::create_page( 'SGA data', OracleDBMenu::get_url( { type => "Data_rate_r", host => $host, server => $server, id => "$type" } ), "$main_group $sub_group $server $host_menu SGA data" );

  return $therest;
}

sub get_hosts {
  my @host_aliases = keys %creds;
  my %hosts;

  for my $alias ( keys %creds ) {
    my ( $can_read_hst, $ref_hst, $host_names );
    ( $can_read_hst, $ref_hst ) = Xorux_lib::read_json("$main_data_dir/$alias/host_names.json");

    if ($can_read_hst) {
      $host_names = $ref_hst;
      if ( $creds{$alias}{type} eq "Standalone" or $creds{$alias}{type} eq "Multitenant" ) {
        if ( $host_names->{ $creds{$alias}{host} } and $host_names->{ $creds{$alias}{host} } ne "" ) {
          my $host_name = $host_names->{ $creds{$alias}{host} };
          $hosts{$host_name}{ $creds{$alias}{host} } = 1;
        }
      }
      elsif ( $creds{$alias}{type} eq "RAC" or $creds{$alias}{type} eq "RAC_Multitenant" ) {
        my @instances = @{ $creds{$alias}{hosts} };
        foreach my $instance (@instances) {
          if ( $host_names->{$instance} ) {
            my $host_name = $host_names->{$instance};
            $hosts{$host_name}{$instance} = 1;
          }
        }
      }
    }
  }
  return \%hosts;
}

sub fill_arrays {
  my @host_aliases = keys %creds;
  my $log_err_v    = premium();

  if ( !defined( keys %creds ) || !defined $host_aliases[0] ) {
    warn "No OracleDB host found couldn't generate menu. Please save Host Configuration in GUI first";
    exit(0);
  }

  for my $alias ( keys %creds ) {
    if ( $creds{$alias}{type} eq "Standalone" ) {
      push( @standalones, $alias );
    }
    if ( $creds{$alias}{type} eq "Multitenant" ) {
      push( @Multitenants, $alias );
    }
  }

  for my $alias ( keys %creds ) {
    if ( $creds{$alias}{type} eq "RAC" or $creds{$alias}{type} eq "RAC_Multitenant" ) {
      push( @RACs, $alias );
      if ( ( length($log_err_v) + 1 ) == length($log_err) || !-e $log_err_file ) {
        last;
      }
    }
  }
}
