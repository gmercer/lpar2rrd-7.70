
use strict;
use warnings;

#use POSIX;
use CGI::Carp qw(fatalsToBrowser);
use ACL;    # use module ACL.pm
use File::Glob qw(bsd_glob GLOB_TILDE);
use Data::Dumper;
use Xorux_lib;
use JSON;
use File::Basename;
use HostCfg;

# data wrappers for new health status
use AWSDataWrapper;
use GCloudDataWrapper;
use AzureDataWrapper;
use NutanixDataWrapper;
use OracleDBDataWrapper;
use PostgresDataWrapper;
use SQLServerDataWrapper;
use Db2DataWrapper;

# for health status url
use AWSMenu;
use GCloudMenu;
use AzureMenu;
use NutanixMenu;
use OracleDBMenu;
use PostgresMenu;
use SQLServerMenu;
use Db2Menu;

my $useacl = ACL::useACL;

my $basedir   = $ENV{INPUTDIR};
my $wrkdir    = "$basedir/data";
my $tmpdir    = $ENV{TMPDIR_LPAR} ||= "$basedir/tmp";
my $devicecfg = "$basedir/etc/web_config/hostcfg.json";
my $act_time  = time();
my $demo      = 0;
if ( defined $ENV{DEMO} && $ENV{DEMO} ne '' ) {
  $demo = $ENV{DEMO};
}

my $urlparams = Xorux_lib::parse_url_params( $ENV{QUERY_STRING} );

# new health status
# structure: { hw_type: string; subsystem: string; item_id: string; item_label: string; status: enum(ok, nok, unknown) }
if ( defined $urlparams->{cmd} and $urlparams->{cmd} eq "status" ) {
  my @health_statuses;    #global
  my %weight = ( 'ok' => 1, 'unknown' => 2, 'nok' => 3 );

  print "Content-type: application/json\n\n";

  # Amazon Web Services
  if ( keys %{ HostCfg::getHostConnections('AWS') } != 0 ) {
    my @health_statuses_aws;
    my $config_ec2 = AWSDataWrapper::get_conf_section('spec-ec2');

    my @regions = @{ AWSDataWrapper::get_items( { item_type => 'region' } ) };
    foreach my $region (@regions) {
      my ( $region_id, $region_label ) = each %{$region};

      my @region_children;
      my @ec2_children;
      my $region_status = 'ok';

      my @ec2s = @{ AWSDataWrapper::get_items( { item_type => 'ec2', parent_type => 'region', parent_id => $region_id } ) };
      foreach my $ec2 (@ec2s) {
        my ( $ec2_uuid, $ec2_label ) = each %{$ec2};

        if ( !defined $config_ec2->{$ec2_uuid} ) {
          next;
        }

        my $hs     = ( $config_ec2->{$ec2_uuid}{State} eq "running" || $config_ec2->{$ec2_uuid}{State} eq "stopped" ) ? 'ok' : 'nok';
        my $status = { 'hw_type' => 'AWS', 'subsystem' => 'EC2', 'item_id' => $ec2_uuid, 'item_label' => $config_ec2->{$ec2_uuid}{Name}, status => $hs };

        if ( $weight{$hs} > $weight{$region_status} ) {
          $region_status = $hs;
        }

        push( @ec2_children, $status );
      }

      my $ec2_folder = { 'hw_type' => 'AWS', 'subsystem' => 'EC2', 'status' => $region_status, 'children' => \@ec2_children };
      push( @region_children, $ec2_folder );

      my $url         = AWSMenu::get_url( { type => 'health' } );
      my $region_hash = { 'hw_type' => 'AWS', 'url' => $url, 'subsystem' => 'REGION', 'item_id' => $region_id, 'item_label' => $region_label, status => $region_status, 'children' => \@region_children };

      push( @health_statuses_aws, $region_hash );
      push( @health_statuses,     $region_hash );
    }

    if ( defined $urlparams->{hw_type} && $urlparams->{hw_type} eq "AWS" ) {
      print encode_json( \@health_statuses_aws );
      exit();
    }
  }

  # end Amazon Web Services

  # Google Cloud
  if ( keys %{ HostCfg::getHostConnections('GCloud') } != 0 ) {
    my @health_statuses_gcloud;
    my $config_compute = GCloudDataWrapper::get_conf_section('spec-compute');

    my @regions = @{ GCloudDataWrapper::get_items( { item_type => 'region' } ) };
    foreach my $region (@regions) {
      my ( $region_id, $region_label ) = each %{$region};

      my @region_children;
      my @compute_children;
      my $region_status = 'ok';

      my @computes = @{ GCloudDataWrapper::get_items( { item_type => 'compute', parent_type => 'region', parent_id => $region_id } ) };
      foreach my $compute (@computes) {
        my ( $compute_uuid, $compute_label ) = each %{$compute};

        if ( !defined $config_compute->{$compute_uuid} ) {
          next;
        }

        my $hs     = ( $config_compute->{$compute_uuid}{status} eq "REPAIRING" ) ? 'nok' : 'ok';
        my $status = { 'hw_type' => 'GCLOUD', 'subsystem' => 'COMPUTE', 'item_id' => $compute_uuid, 'item_label' => $config_compute->{$compute_uuid}{name}, status => $hs };

        if ( $weight{$hs} > $weight{$region_status} ) {
          $region_status = $hs;
        }

        push( @compute_children, $status );
      }

      my $compute_folder = { 'hw_type' => 'GCLOUD', 'subsystem' => 'COMPUTE', 'status' => $region_status, 'children' => \@compute_children };
      push( @region_children, $compute_folder );

      my $url         = GCloudMenu::get_url( { type => 'configuration' } );
      my $region_hash = { 'hw_type' => 'GCLOUD', 'url' => $url, 'subsystem' => 'REGION', 'item_id' => $region_id, 'item_label' => $region_label, status => $region_status, 'children' => \@region_children };

      push( @health_statuses_gcloud, $region_hash );
      push( @health_statuses,        $region_hash );
    }

    if ( defined $urlparams->{hw_type} && $urlparams->{hw_type} eq "GCLOUD" ) {
      print encode_json( \@health_statuses_gcloud );
      exit();
    }
  }

  # end Google Cloud

  # Microsoft Azure
  if ( keys %{ HostCfg::getHostConnections('Azure') } != 0 ) {
    my @health_statuses_azure;
    my $config_vm = AzureDataWrapper::get_conf_section('spec-vm');

    my @locations = @{ AzureDataWrapper::get_items( { item_type => 'location' } ) };
    foreach my $location (@locations) {
      my ( $location_id, $location_label ) = each %{$location};

      my @location_children;
      my @vm_children;
      my $location_status = 'ok';

      my @vms = @{ AzureDataWrapper::get_items( { item_type => 'vm', parent_type => 'location', parent_id => $location_id } ) };
      foreach my $vm (@vms) {
        my ( $vm_uuid, $vm_label ) = each %{$vm};

        if ( !defined $config_vm->{$vm_uuid} ) {
          next;
        }

        my $hs     = ( $config_vm->{$vm_uuid}{status} eq "VM running" || $config_vm->{$vm_uuid}{status} eq "VM deallocated" ) ? 'ok' : 'nok';
        my $status = { 'hw_type' => 'AZURE', 'subsystem' => 'VM', 'item_id' => $vm_uuid, 'item_label' => $config_vm->{$vm_uuid}{name}, status => $hs };

        if ( $weight{$hs} > $weight{$location_status} ) {
          $location_status = $hs;
        }

        push( @vm_children, $status );
      }

      my $vm_folder = { 'hw_type' => 'AZURE', 'subsystem' => 'VM', 'status' => $location_status, 'children' => \@vm_children };
      push( @location_children, $vm_folder );

      my $url           = AzureMenu::get_url( { type => 'statuses' } );
      my $location_hash = { 'hw_type' => 'AZURE', 'url' => $url, 'subsystem' => 'LOCATION', 'item_id' => $location_id, 'item_label' => $location_label, status => $location_status, 'children' => \@location_children };

      push( @health_statuses_azure, $location_hash );
      push( @health_statuses,       $location_hash );

    }

    if ( defined $urlparams->{hw_type} && $urlparams->{hw_type} eq "AZURE" ) {
      print encode_json( \@health_statuses_azure );
      exit();
    }
  }

  # end Microsoft Azure

  # Nutanix
  if ( keys %{ HostCfg::getHostConnections('Nutanix') } != 0 ) {
    my @health_statuses_nutanix;

    my @pools   = @{ NutanixDataWrapper::get_items( { item_type => 'pool' } ) };
    my $healths = NutanixDataWrapper::get_conf_section('health');

    foreach my $pool (@pools) {
      my ( $pool_uuid, $pool_label ) = each %{$pool};
      my $url = NutanixMenu::get_url( { type => "health", health => $pool_uuid } );

      my $pool_status = 'ok';
      foreach my $health_key ( keys %{ $healths->{$pool_uuid}->{summary} } ) {
        if ( $healths->{$pool_uuid}->{summary}->{$health_key}->{Warning} > 0 ) {
          $pool_status = 'nok';
        }
        elsif ( $healths->{$pool_uuid}->{summary}->{$health_key}->{Critical} > 0 ) {
          $pool_status = 'nok';
        }
        elsif ( $healths->{$pool_uuid}->{summary}->{$health_key}->{Error} > 0 ) {
          $pool_status = 'nok';
        }
      }

      my $pool_hash = { 'hw_type' => 'NUTANIX', 'url' => $url, 'subsystem' => 'POOL', 'item_id' => $pool_uuid, 'item_label' => $pool_label, status => $pool_status, 'children' => [] };
      push( @health_statuses_nutanix, $pool_hash );
      push( @health_statuses,         $pool_hash );
    }

    if ( defined $urlparams->{hw_type} && $urlparams->{hw_type} eq "NUTANIX" ) {
      print encode_json( \@health_statuses_nutanix );
      exit();
    }
  }

  # end Nutanix

  # OracleDB
  if ( keys %{ HostCfg::getHostConnections('OracleDB') } != 0 ) {
    my $xm_url    = "/lpar2rrd-cgi/health-status.sh?platform=OracleDB&type=healthstatus";
    my @files     = bsd_glob "$basedir/tmp/health_status_summary/OracleDB/*ok";
    my %creds     = %{ HostCfg::getHostConnections("OracleDB") };
    my $DB_info   = OracleDBDataWrapper::get_instance_names_total();
    my $groups_pa = OracleDBDataWrapper::get_groups_pa();
    my %hs_odb;
    my @health_statuses_odb;
    if ( defined $files[0] and $DB_info ne "" and $groups_pa ne "" ) {
      foreach my $file (@files) {
        my $status = OracleDBDataWrapper::basename( $file, '.' );
        $file =~ s/$basedir\/tmp\/health_status_summary\/OracleDB\///g;
        $file =~ s/\.ok//g;
        $file =~ s/\.nok//g;
        my $ip_info  = OracleDBDataWrapper::basename( $file, '_' );
        my @ip_parts = split( ",", $ip_info );
        my $ip       = $ip_parts[0];
        $file =~ s/_$ip_info//g;
        my $server = $file;
        my $type   = $creds{$server}{type};
        my %temp_hash;

        if ( defined $creds{$server} ) {
          if ( $hs_odb{$server}{status} and $hs_odb{$server}{status} eq "nok" ) {

          }
          else {
            $hs_odb{$server}{status} = $status;
          }
          $temp_hash{status}     = $status;
          $temp_hash{hw_type}    = "OracleDB";
          $temp_hash{item_label} = $DB_info->{$server}->{$ip};
          if ( $type eq "RAC" ) {
            $temp_hash{item_id}                       = OracleDBDataWrapper::get_uuid( $server, "instance" );
            $temp_hash{subsystem}                     = "INSTANCE";
            $hs_odb{$server}{children}[0]{item_label} = "Instances";
            push( @{ $hs_odb{$server}{children}[0]{children} }, \%temp_hash );
          }
          elsif ( $type eq "Multitenant" ) {
            $temp_hash{item_label}                    = $ip_parts[1];
            $temp_hash{item_id}                       = OracleDBDataWrapper::get_uuid( $server, "pdbs" );
            $temp_hash{subsystem}                     = "PDBS";
            $hs_odb{$server}{children}[0]{item_label} = "PDBs";
            push( @{ $hs_odb{$server}{children}[0]{children} }, \%temp_hash );
          }
        }
        if ( !defined $hs_odb{$server}{hw_type} ) {
          $hs_odb{$server}{hw_type}    = "ORACLEDB";
          $hs_odb{$server}{item_label} = $server;
          $hs_odb{$server}{item_id}    = OracleDBDataWrapper::get_uuid( $server, $type );
          $hs_odb{$server}{subsystem}  = uc($type);
        }
      }
      my %full_hs;
      for my $db ( keys %hs_odb ) {
        if ( !defined $full_hs{ $groups_pa->{$db}->{label} }{hw_type} ) {
          $full_hs{ $groups_pa->{$db}->{label} }{item_label} = $groups_pa->{$db}->{label};
          $full_hs{ $groups_pa->{$db}->{label} }{SUBSYSTEM}  = "ODB_FOLDER";
          $full_hs{ $groups_pa->{$db}->{label} }{hw_type}    = "ORACLEDB";
          $full_hs{ $groups_pa->{$db}->{label} }{item_id}    = $groups_pa->{$db}->{mgroup};
          $full_hs{ $groups_pa->{$db}->{label} }{url}        = $xm_url;
        }
        push( @{ $full_hs{ $groups_pa->{$db}->{label} }{children} }, $hs_odb{$db} );
      }
      for my $group ( keys %full_hs ) {
        push( @health_statuses,     $full_hs{$group} );
        push( @health_statuses_odb, $full_hs{$group} );
      }
      if ( defined $urlparams->{hw_type} && $urlparams->{hw_type} eq "ORACLEDB" ) {
        print encode_json( \@health_statuses_odb );
        exit();
      }
    }
  }

  #end OracleDB

  # PostgreSQL
  if ( keys %{ HostCfg::getHostConnections('PostgreSQL') } != 0 ) {
    my $xm_url  = "/lpar2rrd-cgi/health-status.sh?platform=PostgreSQL&type=healthstatus";
    my @files   = bsd_glob "$basedir/tmp/health_status_summary/PostgreSQL/*ok";
    my %creds   = %{ HostCfg::getHostConnections("PostgreSQL") };
    my $DB_info = OracleDBDataWrapper::get_instance_names_total();
    my %hs_pstgrs;
    my @health_statuses_pstgrs;

    if ( defined $files[0] and $DB_info ne "" ) {
      foreach my $file (@files) {
        my $status = PostgresDataWrapper::basename( $file, '.' );
        $file =~ s/$basedir\/tmp\/health_status_summary\/PostgreSQL\///g;
        $file =~ s/\.ok//g;
        $file =~ s/\.nok//g;
        my $ip = PostgresDataWrapper::basename( $file, '_' );
        $file =~ s/_$ip//g;
        my $server = $file;
        my %temp_hash;

        if ( defined $creds{$server} ) {
          if ( $hs_pstgrs{$server}{status} and $hs_pstgrs{$server}{status} eq "nok" ) {

          }
          else {
            $hs_pstgrs{$server}{status} = $status;
          }
          $temp_hash{status}     = $status;
          $temp_hash{hw_type}    = "PostgreSQL";
          $temp_hash{item_label} = $ip;
          $temp_hash{item_id}    = PostgresDataWrapper::get_uuid( $server, $ip, "label" );
          $temp_hash{subsystem}  = "DB";
          push( @{ $hs_pstgrs{$server}{children} }, \%temp_hash );
        }
        if ( !defined $hs_pstgrs{$server}{hw_type} ) {
          $hs_pstgrs{$server}{hw_type}    = "POSTGRES";
          $hs_pstgrs{$server}{item_label} = $server;
          $hs_pstgrs{$server}{subsystem}  = "HOST";
          $hs_pstgrs{$server}{url}        = $xm_url;
          $hs_pstgrs{$server}{item_id}    = PostgresDataWrapper::get_uuid( $server, $ip, "cluster" );
        }
      }
    }
    for my $db ( keys %hs_pstgrs ) {
      push( @health_statuses,        $hs_pstgrs{$db} );
      push( @health_statuses_pstgrs, $hs_pstgrs{$db} );
    }
    if ( defined $urlparams->{hw_type} && $urlparams->{hw_type} eq "POSTGRES" ) {
      print encode_json( \@health_statuses_pstgrs );
      exit();
    }
  }

  # end PostgreSQL

  # SQLServer
  if ( keys %{ HostCfg::getHostConnections('SQLServer') } != 0 ) {
    my $xm_url  = "/lpar2rrd-cgi/health-status.sh?platform=SQLServer&type=healthstatus";
    my @files   = bsd_glob "$basedir/tmp/health_status_summary/SQLServer/*ok";
    my %creds   = %{ HostCfg::getHostConnections("SQLServer") };
    my %hs_sqls;
    my @health_statuses_sqls;

    if ( defined $files[0] ) {
      foreach my $file (@files) {
        my $status = SQLServerDataWrapper::basename( $file, '.' );
        $file =~ s/$basedir\/tmp\/health_status_summary\/SQLServer\///g;
        $file =~ s/\.ok//g;
        $file =~ s/\.nok//g;
        my $ip = SQLServerDataWrapper::basename( $file, '_' );
        $file =~ s/_$ip//g;
        my $server = $file;
        my %temp_hash;

        if ( defined $creds{$server} ) {
          if ( $hs_sqls{$server}{status} and $hs_sqls{$server}{status} eq "nok" ) {

          }
          else {
            $hs_sqls{$server}{status} = $status;
          }
          $temp_hash{status}     = $status;
          $temp_hash{hw_type}    = "SQLServer";
          $temp_hash{item_label} = $ip;
          $temp_hash{item_id}    = SQLServerDataWrapper::get_uuid( $server, $ip, "label" );
          $temp_hash{subsystem}  = "DB";
          push( @{ $hs_sqls{$server}{children} }, \%temp_hash );
        }
        if ( !defined $hs_sqls{$server}{hw_type} ) {
          $hs_sqls{$server}{hw_type}    = "SQLServer";
          $hs_sqls{$server}{item_label} = $server;
          $hs_sqls{$server}{subsystem}  = "HOST";
          $hs_sqls{$server}{url}        = $xm_url;
          $hs_sqls{$server}{item_id}    = SQLServerDataWrapper::get_uuid( $server, $ip, "cluster" );
        }
      }
    }
    for my $db ( keys %hs_sqls ) {
      push( @health_statuses,        $hs_sqls{$db} );
      push( @health_statuses_sqls, $hs_sqls{$db} );
    }
    if ( defined $urlparams->{hw_type} && $urlparams->{hw_type} eq "SQLSERVER" ) {
      print encode_json( \@health_statuses_sqls );
      exit();
    }
  }

  # end SQLServer

  # DB2
  if ( keys %{ HostCfg::getHostConnections('DB2') } != 0 ) {
    my $xm_url  = "/lpar2rrd-cgi/health-status.sh?platform=DB2&type=healthstatus";
    my @files   = bsd_glob "$basedir/tmp/health_status_summary/DB2/*ok";
    my %creds   = %{ HostCfg::getHostConnections("DB2") };
    my %hs_db2;
    my @health_statuses_db2;

    if ( defined $files[0]) {
      foreach my $file (@files) {
        my $status = Db2DataWrapper::basename( $file, '.' );
        $file =~ s/$basedir\/tmp\/health_status_summary\/DB2\///g;
        $file =~ s/\.ok//g;
        $file =~ s/\.nok//g;
        my $ip = Db2DataWrapper::basename( $file, '_' );
        $file =~ s/_$ip//g;
        my $server = $file;
        my %temp_hash;

        if ( defined $creds{$server} ) {
          if ( $hs_db2{$server}{status} and $hs_db2{$server}{status} eq "nok" ) {

          }
          else {
            $hs_db2{$server}{status} = $status;
          }
          #$temp_hash{status}     = $status;
          #$temp_hash{hw_type}    = "DB2";
          #$temp_hash{item_label} = $ip;
          #$temp_hash{item_id}    = Db2DataWrapper::get_uuid( $server, $ip, "label" );
          #$temp_hash{subsystem}  = "DB";
          #push( @{ $hs_db2{$server}{children} }, \%temp_hash );
        }
        if ( !defined $hs_db2{$server}{hw_type} ) {
          $hs_db2{$server}{hw_type}    = "DB2";
          $hs_db2{$server}{item_label} = $server;
          $hs_db2{$server}{subsystem}  = "HOST";
          $hs_db2{$server}{url}        = $xm_url;
          $hs_db2{$server}{item_id}    = Db2DataWrapper::get_uuid( $server, $ip, "cluster" );
        }
      }
    }
    for my $db ( keys %hs_db2 ) {
      push( @health_statuses,     $hs_db2{$db} );
      push( @health_statuses_db2, $hs_db2{$db} );
    }
    if ( defined $urlparams->{hw_type} && $urlparams->{hw_type} eq "DB2" ) {
      print encode_json( \@health_statuses_db2 );
      exit();
    }
  }
  print encode_json( \@health_statuses );
  exit();
}

# end new health status

if ( !-d "$tmpdir/health_status_summary" ) {
  print "Content-type: application/json\n\n";
  my $status = { status => "OK" };
  print encode_json($status);
}
if ( !$ENV{QUERY_STRING} ) {
  print "Content-type: text/plain\n\n";
  warn("empty query string, exiting...") && exit;
}

my $platform = $urlparams->{platform};
if ( !$platform ) {
  print "Content-type: text/plain\n\n";
  warn("platform not specified, exiting...") && exit;
}

my @items = <$tmpdir/health_status_summary/$platform/*>;

if ( defined $urlparams->{cmd} and $urlparams->{cmd} eq "isok" ) {
  print "Content-type: application/json\n\n";

  # print "[\n";      # envelope begin
  my @files  = bsd_glob "${basedir}/tmp/health_status_summary/$platform/*.nok";
  my $status = { status => "OK" };
  if (@files) {
    $status = { status => "NOK" };
    if ( $urlparams->{platform} eq "Nutanix" ) {
      my $central = grep ( /Nutanix_central\.nok$/, @files );
      if ($central) {
        $status->{bad_central} = \1;
        @files = grep ( !/Nutanix_central\.nok$/, @files );
      }
      @{ $status->{bad_clusters} } = ( map basename( $_, ".nok" ), @files );
    }
  }
  print encode_json($status);

  # print "\n]\n";    # envelope end
}
elsif ( $urlparams->{platform} eq "OracleDB" ) {
  my @hosts;
  push @hosts, "<thead><tr><th>Status</th><th>LPAR2RRD alias</th><th>Instance</th><th>Last data update</th><th>Error</th></tr></thead><tbody>\n";
  my $st_idx            = 0;
  my $san_idx           = 0;
  my $totals_dir        = "$wrkdir/OracleDB/Totals";
  my $alert_history_dir = "$totals_dir/configuration/alrthst__OracleDB.html";

  # load configured devices
  my %devices;
  if ( -f $devicecfg ) {
    %devices = %{ Xorux_lib::read_json("$devicecfg") };
  }

  foreach my $file (@items) {
    chomp $file;

    open( FILE, "<$file" ) || error( "Couldn't open file $file $!" . __FILE__ . ":" . __LINE__ ) && exit;
    my $component_line = <FILE>;
    close(FILE);

    if ( !defined $component_line || $component_line eq '' ) { next; }    # some trash or non working device

    my ( $type, $name, $instance, $status, $log_time, $reason ) = split( " : ", $component_line );

    $reason ||= "";

    my $st;
    my $ok_class  = "hsok";
    my $nok_class = "hsnok";
    my $na_class  = "hsna";

    my $sortval;

    if ( $status eq "NOT_OK" ) {
      $st      = $nok_class;
      $sortval = 1;
    }
    else {    # do this only if status is not red
              # test disabled HW
      if ( $demo eq "1" ) {
        $log_time =~ s/ //g;
        $log_time =~ s/\://g;
        $log_time =~ s/\\//g;
        $log_time =~ s/n//g;
      }
      my $time_diff = $act_time - $log_time;

      if ( $status eq "OK" )    { $st = $ok_class; $sortval = 3; }
      if ( $time_diff > 10800 ) { $st = $na_class; $sortval = 2; }    # set status to gray for non updated hosts/switches (after 3 hours)
      if ( $time_diff > 172800 ) {                                    # ignore 2 days old file
                                                                      # if is device still configured then do not ignore it, just set grey status
        if ( $type eq $platform && exists $devices{platforms}{$platform}{aliases}{$name} ) {
          print "here";
          $st      = $na_class;
          $sortval = 2;
        }
        else {
          next;
        }
      }
    }

    # my $title = "$status" . ( $reason ? " - $reason" : "" ) . " (" . epoch2human($log_time) .")";
    #my $lastseen = epoch2human($log_time);

    #last data update
    my $last_rec = "";
    if ( -f "$wrkdir/$name/last_rec" ) {
      open( LREC, "<$wrkdir/$name/last_rec" ) || error( "Couldn't open file $wrkdir/$name/last_rec $!" . __FILE__ . ":" . __LINE__ ) && exit;
      my $last_rec_line = <LREC>;
      chomp $last_rec_line;
      close(LREC);
      if ( defined $last_rec_line && isdigit($last_rec_line) && $last_rec_line > 1000000000 ) {
        $last_rec = epoch2human($last_rec_line);
      }
    }

    my $line = "<tr><td class=\"$st\" data-sortValue='$sortval' title='$reason'></td><td>$name</td><td>$instance</td><td>" . epoch2human($log_time) . "</td><td>$reason</td></tr>";

    #if ( ACL::canShow( "S", "", $name ) ) {
    push( @hosts, "$line\n" );
    $st_idx++;

    #}

  }

  print "Content-type: text/html\n\n";

  print <<_MARKER_;
<div id='tabs' style='text-align: center;'>
  <ul>
    <li><a href='#tabs-1'>Health status</a></li>
    <li><a href='#tabs-2'>Alert History</a></li>
  </ul>
<div id='tabs-1' style='display: inline-block'>
_MARKER_

  print "<center><div class=\"hsdiv\">\n";

  if ( $st_idx > 0 ) {
    print <<_MARKER_;
  <p><table id="health_status" class="">
    @hosts
  </tbody></table></p>
_MARKER_
  }

  if ( $demo eq "1" ) {
    print "</div>\n";
    print "<br><br>This is the demo site, not all hosts have detailed HW status available\n";
    print "</center></div>\n";
  }
  else {
    print "</div></center></div>\n";
  }
  print <<_MARKER_;
  <div id='tabs-2' style='display: inline-block'>
  <center><div>\n
_MARKER_
  if ( -f $alert_history_dir ) {
    open( FH, '<', $alert_history_dir ) or warn "Couldn't open Alert History file.";
    while (<FH>) {
      print $_;
    }
    close(FH);
  }
  else {
    print "<p>Alert History isn\'t created yet.</p>";
  }
  print '</div></center></div>';
}
elsif ( $urlparams->{platform} eq "PostgreSQL" ) {
  my @hosts;
  push @hosts, "<thead><tr><th>Status</th><th>LPAR2RRD alias</th><th>Database</th><th>Last data update</th><th>Error</th></tr></thead><tbody>\n";
  my $st_idx  = 0;
  my $san_idx = 0;

  # load configured devices
  my %devices;
  if ( -f $devicecfg ) {
    %devices = %{ Xorux_lib::read_json("$devicecfg") };
  }

  foreach my $file (@items) {
    chomp $file;

    open( FILE, "<$file" ) || error( "Couldn't open file $file $!" . __FILE__ . ":" . __LINE__ ) && exit;
    my $component_line = <FILE>;
    close(FILE);

    if ( !defined $component_line || $component_line eq '' ) { next; }    # some trash or non working device

    my ( $type, $name, $instance, $status, $log_time, $reason ) = split( " : ", $component_line );

    $reason ||= "";

    my $st;
    my $ok_class  = "hsok";
    my $nok_class = "hsnok";
    my $na_class  = "hsna";

    my $sortval;

    if ( $status eq "NOT_OK" ) {
      $st      = $nok_class;
      $sortval = 1;
    }
    else {    # do this only if status is not red
              # test disabled HW
      my $time_diff = $act_time - $log_time;

      if ( $status eq "OK" )    { $st = $ok_class; $sortval = 3; }
      if ( $time_diff > 10800 ) { $st = $na_class; $sortval = 2; }    # set status to gray for non updated hosts/switches (after 3 hours)
      if ( $time_diff > 172800 ) {                                    # ignore 2 days old file
                                                                      # if is device still configured then do not ignore it, just set grey status
        if ( $type eq $platform && exists $devices{platforms}{$platform}{aliases}{$name} ) {
          print "here";
          $st      = $na_class;
          $sortval = 2;
        }
        else {
          next;
        }
      }
    }

    # my $title = "$status" . ( $reason ? " - $reason" : "" ) . " (" . epoch2human($log_time) .")";
    #my $lastseen = epoch2human($log_time);

    #last data update
    my $last_rec = "";
    if ( -f "$wrkdir/$name/last_rec" ) {
      open( LREC, "<$wrkdir/$name/last_rec" ) || error( "Couldn't open file $wrkdir/$name/last_rec $!" . __FILE__ . ":" . __LINE__ ) && exit;
      my $last_rec_line = <LREC>;
      chomp $last_rec_line;
      close(LREC);
      if ( defined $last_rec_line && isdigit($last_rec_line) && $last_rec_line > 1000000000 ) {
        $last_rec = epoch2human($last_rec_line);
      }
    }

    my $line = "<tr><td class=\"$st\" data-sortValue='$sortval' title='$reason'></td><td>$name</td><td>$instance</td><td>" . epoch2human($log_time) . "</td><td>$reason</td></tr>";

    #if ( ACL::canShow( "S", "", $name ) ) {
    push( @hosts, "$line\n" );
    $st_idx++;

    #}

  }

  print "Content-type: text/html\n\n";

  print <<_MARKER_;
<div id='tabs' style='text-align: center;'>
  <ul>
    <li><a href='#tabs-1'>Health status</a></li>
  </ul>
<div id='tabs-1' style='display: inline-block'>
_MARKER_

  print "<center><div class=\"hsdiv\">\n";

  if ( $st_idx > 0 ) {
    print <<_MARKER_;
  <p><table id="health_status" class="">
    @hosts
  </tbody></table></p>
_MARKER_
  }

  if ( $demo eq "1" ) {
    print "</div>\n";
    print "<br><br>This is the demo site, not all hosts have detailed HW status available\n";
    print "</center></div>\n";
  }
  else {
    print "</div></center></div>\n";
  }
  print '</div></center></div>';
}
elsif ( $urlparams->{platform} eq "SQLServer" or $urlparams->{platform} eq "DB2" ) {
  my @hosts;
  push @hosts, "<thead><tr><th>Status</th><th>LPAR2RRD alias</th><th>Database</th><th>Last data update</th><th>Error</th></tr></thead><tbody>\n";
  my $st_idx  = 0;
  my $san_idx = 0;

  # load configured devices
  my %devices;
  if ( -f $devicecfg ) {
    %devices = %{ Xorux_lib::read_json("$devicecfg") };
  }

  foreach my $file (@items) {
    chomp $file;

    open( FILE, "<$file" ) || error( "Couldn't open file $file $!" . __FILE__ . ":" . __LINE__ ) && exit;
    my $component_line = <FILE>;
    close(FILE);

    if ( !defined $component_line || $component_line eq '' ) { next; }    # some trash or non working device

    my ( $type, $name, $instance, $status, $log_time, $reason ) = split( " : ", $component_line );

    $reason ||= "";

    my $st;
    my $ok_class  = "hsok";
    my $nok_class = "hsnok";
    my $na_class  = "hsna";

    my $sortval;

    if ( $status eq "NOT_OK" ) {
      $st      = $nok_class;
      $sortval = 1;
    }
    else {    # do this only if status is not red
              # test disabled HW
      my $time_diff = $act_time - $log_time;

      if ( $status eq "OK" )    { $st = $ok_class; $sortval = 3; }
      if ( $time_diff > 10800 ) { $st = $na_class; $sortval = 2; }    # set status to gray for non updated hosts/switches (after 3 hours)
      if ( $time_diff > 172800 ) {                                    # ignore 2 days old file
                                                                      # if is device still configured then do not ignore it, just set grey status
        if ( $type eq $platform && exists $devices{platforms}{$platform}{aliases}{$name} ) {
          print "here";
          $st      = $na_class;
          $sortval = 2;
        }
        else {
          next;
        }
      }
    }

    # my $title = "$status" . ( $reason ? " - $reason" : "" ) . " (" . epoch2human($log_time) .")";
    #my $lastseen = epoch2human($log_time);

    #last data update
    my $last_rec = "";
    if ( -f "$wrkdir/$name/last_rec" ) {
      open( LREC, "<$wrkdir/$name/last_rec" ) || error( "Couldn't open file $wrkdir/$name/last_rec $!" . __FILE__ . ":" . __LINE__ ) && exit;
      my $last_rec_line = <LREC>;
      chomp $last_rec_line;
      close(LREC);
      if ( defined $last_rec_line && isdigit($last_rec_line) && $last_rec_line > 1000000000 ) {
        $last_rec = epoch2human($last_rec_line);
      }
    }

    my $line = "<tr><td class=\"$st\" data-sortValue='$sortval' title='$reason'></td><td>$name</td><td>$instance</td><td>" . epoch2human($log_time) . "</td><td>$reason</td></tr>";

    #if ( ACL::canShow( "S", "", $name ) ) {
    push( @hosts, "$line\n" );
    $st_idx++;

    #}

  }

  print "Content-type: text/html\n\n";

  print <<_MARKER_;
<div id='tabs' style='text-align: center;'>
  <ul>
    <li><a href='#tabs-1'>Health status</a></li>
  </ul>
<div id='tabs-1' style='display: inline-block'>
_MARKER_

  print "<center><div class=\"hsdiv\">\n";

  if ( $st_idx > 0 ) {
    print <<_MARKER_;
  <p><table id="health_status" class="">
    @hosts
  </tbody></table></p>
_MARKER_
  }

  if ( $demo eq "1" ) {
    print "</div>\n";
    print "<br><br>This is the demo site, not all hosts have detailed HW status available\n";
    print "</center></div>\n";
  }
  else {
    print "</div></center></div>\n";
  }
  print '</div></center></div>';
}

### ERROR HANDLING
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);
  print STDERR "$act_time: $text : $!\n";
  return 1;
}

sub isdigit {
  my $digit = shift;

  if ( !defined($digit) || $digit eq '' ) {
    return 0;
  }

  if ( $digit =~ m/^-+$/ ) {
    return 0;
  }

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/^-//;
  $digit_work =~ s/e//;
  $digit_work =~ s/\+//;
  $digit_work =~ s/\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  # NOT a number
  return 0;
}

sub epoch2human {

  # Output: 2015:02:05T19:54:07.000000+0100
  my ( $tm, $tz ) = @_;                                                                  # epoch, TZ offset (+0100)
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($tm);
  my $y   = $year + 1900;
  my $m   = $mon + 1;
  my $mcs = 0;
  my $str = sprintf( "%4d/%02d/%02d %02d:%02d:%02d", $y, $m, $mday, $hour, $min, $sec );
  return ($str);
}
