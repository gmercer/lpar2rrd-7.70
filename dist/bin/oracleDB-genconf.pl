use strict;
use warnings;

use JSON;
use Data::Dumper;
use Date::Parse;

use Xorux_lib qw(error read_json write_json file_time_diff);
use OracleDBMenu;
use OracleDBDataWrapper;
use HostCfg;
use File::Copy;
use File::Glob qw(bsd_glob GLOB_TILDE);
use OracleDBAlerting;
use DatabasesWrapper;

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $sh_out = "";
if (@ARGV) {
  $sh_out = $ARGV[0];
}

my @sh_arr   = split( /,/, $sh_out );
my $sh_alias = $sh_arr[1];
my $sh_type  = $sh_arr[0];

if ( !$sh_alias ) {
  warn( "No OracleDB host retrieved from params." . __FILE__ . ":" . __LINE__ ) && exit 1;
}

my %creds         = %{ HostCfg::getHostConnections("OracleDB") };
my $alias         = $sh_alias;
my $upgrade       = defined $ENV{UPGRADE} ? $ENV{UPGRADE} : 0;
my $version       = "$ENV{version}";
my $inputdir      = $ENV{INPUTDIR};
my $main_data_dir = "$inputdir/data/OracleDB";
my $conf_dir      = "";                                               #"$main_data_dir/$alias/configuration";
my $generate_time = localtime();
my $total_alias   = "";
my $hs_dir        = "$inputdir/tmp/health_status_summary/OracleDB";
my $totals_dir    = "$main_data_dir/Totals";
my $t_percent_alert;
my $archivemode_alert;
my %groups;
my $save_type;
my %tablespace_percent;

if ( $sh_type eq "RAC_Multitenant" ) {
  $save_type = "RAC_Multitenant";
  $sh_type   = "RAC";
}
my %headers = (
  'SGA info'        => [ "Pool name",      "Pool size MB" ],
  'Tablespace info' => [ "TBS size MB",    "TBS allocate size MB", "TBS max size MB" ],
  'Main info'       => [ "LPAR2RRD alias", "DB name", "Unique name", "Instance name", "Version", "Host name", "Status", "Open mode", "Startup", "Archive mode", "Flashback activate", "Logins", "Force logging", "Instance role", "RAM_GB", "VCPUS", "LCPUS", "CDB", "Edition", "Platform", "DBID" ],

  #'Main info' => ["DB name","Unique name","Instance name","Version","Host name","Status","Open mode","Startup","Archive mode","Flashback activate","Logins","Force logging","Instance role","SOCKETS","RAM_GB","VCPUS","LCPUS","CORES","CPUS","CDB","Edition","Platform","DBID"],
  'Health status'              => [ "Status",             "LPAR2RRD alias",  "Instance",     "Last data update", "ERROR" ],
  'IO Read Write per datafile' => [ "Physical Reads",     "Physical Writes", "Read/Write %", "Avg read wait ms", "Avg write wait ms" ],
  'Wait class Main'            => [ "Average wait FG ms", "Average wait ms" ],
  'Data rate per service name' => [ "STAT_NAME", "SERVICE_NAME", "DB blocks" ],
  'Installed DB components'    => [ "DATE",      "STATUS",       "VERSION" ],
  'Upgrade, Downgrade info'        => [ "ID",             "COMMENTS",    "NAMESPACE",         "ACTION",     "VERSION" ],
  'PSU, patches info'              => [ "ACTION",         "DESCRIPTION", "STATUS",            "VERSION",    "PATCH_ID" ],
  'Interconnect info'              => [ "Instance_name",  "Status",      "Bond name",         "IPaddress",  "Is public" ],
  'PDB info'                       => [ "DBID",           "BLOCK_SIZE",  "PDB_TOTAL_SIZE_MB", "RESTRICTED", "APPLICATION_PDB", "APPLICATION_SEED", "PROXY_PDB", "CON_UID", "GUID", "OPEN_MODE" ],
  'gc remaster'                    => [ "Wait time ms",   "Count" ],
  'gc cr block 2-way'              => [ "Wait time ms",   "Count" ],
  'gc current block 2-way'         => [ "Wait time ms",   "Count" ],
  'gc cr block 2-way'              => [ "Wait time ms",   "Count" ],
  'gc current block 2-way'         => [ "Wait time ms",   "Count" ],
  'gc cr block busy'               => [ "Wait time ms",   "Count" ],
  'gc cr block congested'          => [ "Wait time ms",   "Count" ],
  'gc cr grant 2-way'              => [ "Wait time ms",   "Count" ],
  'gc cr grant congested'          => [ "Wait time ms",   "Count" ],
  'gc current block busy'          => [ "Wait time ms",   "Count" ],
  'gc current block congested'     => [ "Wait time ms",   "Count" ],
  'gc current grant 2-way'         => [ "Wait time ms",   "Count" ],
  'gc current grant congested'     => [ "Wait time ms",   "Count" ],
  'gc cr block lost'               => [ "Wait time ms",   "Count" ],
  'gc current block lost'          => [ "Wait time ms",   "Count" ],
  'gc cr failure'                  => [ "Wait time ms",   "Count" ],
  'gc current retry'               => [ "Wait time ms",   "Count" ],
  'gc current split'               => [ "Wait time ms",   "Count" ],
  'gc current multi block request' => [ "Wait time ms",   "Count" ],
  'gc current grant busy'          => [ "Wait time ms",   "Count" ],
  'gc cr disk read'                => [ "Wait time ms",   "Count" ],
  'gc cr multi block request'      => [ "Wait time ms",   "Count" ],
  'gc buffer busy acquire'         => [ "Wait time ms",   "Count" ],
  'gc buffer busy release'         => [ "Wait time ms",   "Count" ],
  'Alert History'                  => [ "CREATION_TIME",  "MESSAGE_LEVEL", "MESSAGE_TYPE", "RESOLUTION", "REASON" ],
  'Identify Primary/Standby'       => [ "DB_UNIQUE_NAME", "CURRENT_SCN" ],
  'Check service'                  => ["STBY_DEST"],
  'Identify service' => [ "TYPE",        "DATABASE_MODE", "STATUS",     "RECOVERY_MODE",       "PROTECTION_MODE", "DESTINATION", "ARCHIVED_SEQ#", "APPLIED_SEQ#" ],
  'Transport delay'  => [ "PRIMARY_seq", "DG_trans_seq",  "DG_app_seq", "Transport_seq__diff", "Applied_seq_diff" ],
  'Online Redo Logs' => [ "Thread",      "Group number",  "Member",     "Size in MiB",         "Status", "Archived", "Type", "RDF", "Sequence" ]
);
my %headers_histogram = (
  viewone => [ 'gc cr block 2-way', 'gc current block 2-way' ],

  viewtwo => [
    'gc cr block busy',
    'gc cr block congested',
    'gc cr grant 2-way',
    'gc cr grant congested',
    'gc current block busy',
    'gc current block congested',
    'gc current grant 2-way',
    'gc current grant congested'
  ],

  viewthree => [
    'gc cr block lost',
    'gc current block lost',
    'gc cr failure',
    'gc current retry'
  ],

  viewfour => [
    'gc current split',
    'gc current multi block request',
    'gc current grant busy',
    'gc cr disk read',
    'gc cr multi block request',
    'gc buffer busy acquire',
    'gc buffer busy release'
  ],

  viewfive => ['gc remaster'],
);

my %new_headers  = ();
my @headers_only = (

  #              'SGA info',
  'Tablespace info',
  'Main info',
  'IO Read Write per datafile',
  'Wait class Main',
  'Installed DB components',
  'Upgrade, Downgrade info',
  'PSU, patches info',
  'Online Redo Logs',
);
my @headers_only_totals = (
  'Tablespace info',
  'Main info',
  'Alert History',
);
my @headers_pdb = (
  'PDB info',
  'Tablespace info',
  'SGA info',
);

my @headers_dg = (
  'Identify Primary/Standby',
  'Check service',
  'Identify service',
  'Transport delay',
);

################################################################################
gen_total_names();
gen_groups();
gen_totals_conf();

#gen_healthstatus();
$total_alias = "";
$alias       = $sh_alias;

$conf_dir = "$main_data_dir/$alias/configuration";

my ( $code, $ref );

if ( -f "$conf_dir/conf.json" ) {
  ( $code, $ref ) = Xorux_lib::read_json("$conf_dir/conf.json");
}

if ($code) {
  my $data = $ref;

  OracleDBAlerting::check_config_data( $alias, get_alerting_data($data, "frequent"), $sh_type );
  #warn Dumper %ENV;
  if ( defined $ENV{BAKOTECH} and $ENV{BAKOTECH} eq "1" ) {
    require OracleDBExport;

    OracleDBExport::export_conf( $data->{$sh_type} );
  }

  my $run_conf = DatabasesWrapper::can_update("$main_data_dir/$alias/gen_conf_hourly", 3600, 1);
  if ( $run_conf ) {    # or $sh_alias eq "RACdev"
                      #print Dumper \$data;

    #    get_totals($data->{Standalone}->{'SGA info'}, "SGA info");
    #undef %totals;
    foreach my $header (@headers_only) {
      if ( $data->{$sh_type}->{$header} ) {
        my $tables = ${ gen_info( $data->{$sh_type}->{$header}, $header ) };
        create_file( $header, $tables );
      }
      else {
        warn "$header   Doesnt exist in $sh_alias conf";
      }
    }
    if ( $data->{$sh_type}->{'SGA info'} ) {
      my $sga = ${ gen_histogram( $data->{$sh_type}->{'SGA info'}, 'SGA info' ) };
      create_file( "SGA info", $sga );
    }
    else {
      warn "SGA info   Doesnt exist in $sh_alias conf";
    }
    if ( $data->{$sh_type}->{'Data rate per service name'} ) {
      my $foo = ${ gen_histogram( $data->{$sh_type}->{'Data rate per service name'}, 'Data rate per service name' ) };
      create_file( "Data rate per service name", $foo );
    }
    else {
      warn "Data rate per service name   Doesnt exist in $sh_alias conf";
    }
    if ( $sh_type eq "RAC" or $sh_type eq "RAC_Multitenant" ) {

      #     foreach my $hist_hdr (@headers_histogram){
      #       my $tables = ${gen_histogram($data->{$sh_type}->{$hist_hdr}, $hist_hdr)};
      #       create_file($hist_hdr, $tables);
      #      }
      #      foreach my $hist_tab (keys %new_headers){
      #       my @arr;
      #       my $hlp = gen_histogram($data->{$sh_type}->{'gc cr block 2-way'}, 'gc cr block 2-way');
      #       push(@arr,$hlp);

      for my $view ( keys %headers_histogram ) {
        my $tables = "";
        foreach my $hist ( @{ $headers_histogram{$view} } ) {
          if ( $data->{$sh_type}->{$hist} ) {
            $tables .= ${ generate_row( \@{ gen_histogram( $data->{$sh_type}->{$hist}, $hist ) } ) };
          }
          else {
            warn("Couldn't create table for: $hist  $sh_alias");
          }
        }
        my @shit = (" ");
        create_file( $sh_type, ${ generate_table( \@shit, \$tables ) }, $view );
      }
      if ( $data->{$sh_type}->{'Interconnect info'} ) {
        my $tables = ${ gen_info( $data->{$sh_type}->{'Interconnect info'}, 'Interconnect info' ) };
        create_file( 'Interconnect info', $tables );
      }
      else {
        warn "Interconnect info   Doesnt exist in $sh_alias conf";
      }

      #       undef @arr;
      #       $hlp = ${gen_histogram($data->{$sh_type}->{'gc current block 2-way'}, 'gc current block 2-way')};
      #       push(@arr,$hlp);
      #        $tables .= ${generate_row(\@{gen_histogram($data->{$sh_type}->{'gc current block 2-way'}, 'gc current block 2-way')})};
      #}
      #      gen_info($data->{$sh_type}->{'Installed DB components'}, "Installed DB components");
      #      create_file("Installed DB components", $foo);

      #gen_info($data->{$sh_type}->{'Update RDBMS info'}, "Update RDBMS info");
    }
    if ( $sh_type eq "Multitenant" or $sh_type eq "RAC_Multitenant" or $save_type eq "RAC_Multitenant" ) {
      my $rows    = "";
      my $db_type = "PDB";
      if ( $data->{$db_type}->{'PDB info'} ) {
        $rows .= ${ gen_info( $data->{$db_type}->{'PDB info'}, 'PDB info', "just_rows" ) };
        if ( $data->{$db_type}->{'PDB info'} ) {
          my $row = ${ gen_info( $data->{$db_type}->{'PDB info'}, 'PDB info', "just_rows" ) };
          $rows .= $row;
        }
        create_file( 'PDB info', ${ generate_table( $headers{'PDB info'}, \$rows ) } );
      }
      else {
        warn "PDB info   Doesnt exist in $sh_alias conf";
      }
      foreach my $header (@headers_pdb) {
        if ( $data->{$header} ) {
          for my $pdb ( keys %{ $data->{$header} } ) {
            my $row = ${ gen_info( $data->{$header}->{$pdb}, $header, "filler", "pdb" ) };
            create_file( $header, $row, "pdb", "_$pdb" );
          }
        }
      }
    }
    my ( $code_dg, $ref_dg );
    if ( -f "$conf_dir/dataguard.json" ) {
      ( $code_dg, $ref_dg ) = Xorux_lib::read_json("$conf_dir/dataguard.json");
    }

    if ($code_dg) {
      my $dg_data = $ref_dg;
      my $tables  = "";
      foreach my $header (@headers_dg) {
        if ( $dg_data->{RAC}->{$header} ) {
          $tables .= ${ gen_info( $dg_data->{RAC}->{$header}, $header ) };
        }
        else {
          warn "$header   Doesnt exist in $sh_alias conf";
        }
      }
      create_file( "Dataguard", $tables );
    }

    my %tbs;
    $tbs{$alias} = ["total",(keys %tablespace_percent)];
    Xorux_lib::write_json( "$main_data_dir/$alias/tablespaces.json", \%tbs ); 


    OracleDBAlerting::check_config_data( $alias, get_alerting_data($data, "hourly"), $sh_type );
  }
}

################################################################################

sub get_alerting_data {
  my $_conf = shift;
  my $frequency = shift;

  my %_data;
  if (defined $frequency and $frequency eq "hourly"){
    if ( $creds{$alias}{type} eq "Standalone" ) {
      for my $current_ip ( keys %{ $_conf->{Standalone}->{"Main info"} } ) {
        if ( defined $_conf->{Standalone}->{"Main info"}->{$current_ip}->[0]->{"Archive mode"} ) {
          my $current_archivemode = $_conf->{Standalone}->{"Main info"}->{$current_ip}->[0]->{"Archive mode"};
          my $arch_bool           = 1;
          if ( $current_archivemode eq "NOARCHIVELOG" ) {
            $arch_bool = 0;
          }
          $_data{Archive_mode}{ $creds{$alias}{host} }{metric_value} = $arch_bool;
        }
      }
    }
    elsif ( $creds{$alias}{type} eq "RAC" ) {
      for my $current_ip ( keys %{ $_conf->{RAC}->{"Main info"} } ) {
        if ( defined $_conf->{RAC}->{"Main info"}->{$current_ip}->[0]->{"Archive mode"} ) {
          my $current_archivemode = $_conf->{RAC}->{"Main info"}->{$current_ip}->[0]->{"Archive mode"};
          my $arch_bool           = 1;
          if ( $current_archivemode eq "NOARCHIVELOG" ) {
            $arch_bool = 0;
          }
          $_data{Archive_mode}{$current_ip}{metric_value} = $arch_bool;
        }
      }
    }
    $_data{Tablespaces_used}{ $creds{$alias}{host} }{total}{metric_value} = $t_percent_alert;
    for my $tablespace (keys %tablespace_percent){
      $_data{Tablespaces_used}{ $creds{$alias}{host} }{$tablespace}{metric_value} = $tablespace_percent{$tablespace};
    }
  }
  my @files = @{ get_healthstatus($sh_alias) };
  foreach my $file (@files) {
    my $status = OracleDBDataWrapper::basename( $file, '.' );
    if ( defined $status ) {
      my $filename = $file;
      $filename =~ s/$hs_dir\///g;
      $filename =~ s/$sh_alias\_//g;
      $filename =~ s/\.ok//g;
      $filename =~ s/\.nok//g;
      my $hs_ip = $filename;
      my $status_bool;
      if ( $status eq "ok" ) {
        $status_bool = 1;
      }
      elsif ( $status eq "nok" ) {
        $status_bool = 0;
      }
      else {
        next;
      }

      $_data{Database_status}{$hs_ip}{metric_value} = $status_bool;
    }
  }

  return \%_data;
}

sub get_healthstatus {
  my $_alias = shift;
  my $dh;
  opendir( $dh, $hs_dir ) or warn "Couldn't open dir '$hs_dir" && return "empty";
  warn Dumper $dh;
  my @files = readdir $dh;
  closedir $dh;

  #  my @files = bsd_glob("$hs_dir/*ok");
  @files = grep( /$alias/, @files );
  return \@files;
}

#this one probably shouldn't be in this file, but still
#it is probably better than finding the right name during graph creation
sub gen_total_names {
  my @dbs = keys %creds;
  my ( $instance_names_total, $host_names_total, $hosts_dbs, $tablespaces_total);
  my %host_metrics = %{ OracleDBDataWrapper::get_host_metrics() };

  #  print Dumper \%host_metrics;
  foreach my $alias (@dbs) {

    #    print $alias."\n";
    my ( $instance_names, $can_read, $ref, $host_names, $can_read_hosts, $host_ref, $can_read_tablespaces, $ref_tablespaces, $current_tablespaces );

    ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$alias/instance_names.json");
    undef $instance_names;
    if ($can_read) {
      $instance_names = $ref;
      for my $ip ( keys %{$instance_names} ) {
        $instance_names_total->{$alias}->{$ip} = $instance_names->{$ip};
      }
    }
    ( $can_read_hosts, $host_ref ) = Xorux_lib::read_json("$main_data_dir/$alias/host_names.json");
    undef $host_names;
    if ($can_read_hosts) {
      $host_names = $host_ref;
      for my $ip ( keys %{$host_names} ) {
        $host_names_total->{$ip} = $host_names->{$ip};
        for my $metric ( keys %host_metrics ) {
          $metric =~ s/ /_/g;
          if ( !$hosts_dbs->{ $host_names->{$ip} } ) {
            $hosts_dbs->{ $host_names->{$ip} } = [];
          }
          push( @{ $hosts_dbs->{ $host_names->{$ip} } }, "$alias-_-$ip-_-$metric.rrd" );
        }
      }
    }
    
    ( $can_read_tablespaces, $ref_tablespaces ) = Xorux_lib::read_json("$main_data_dir/$alias/tablespaces.json");
    undef $current_tablespaces;
    if ($can_read_tablespaces) {
      $current_tablespaces = $ref_tablespaces;
      for my $cur_alias ( keys %{$current_tablespaces} ) {
        $tablespaces_total->{$cur_alias} = $current_tablespaces->{$cur_alias};
      }
    }
  }

  #  print Dumper $instance_names_total;
  #  print Dumper $host_names_total;
  #  print Dumper $hosts_dbs;
  Xorux_lib::write_json( "$totals_dir/instance_names_total.json", $instance_names_total );
  Xorux_lib::write_json( "$totals_dir/host_names_total.json",     $host_names_total );
  Xorux_lib::write_json( "$totals_dir/hosts_dbs.json",            $hosts_dbs );
  Xorux_lib::write_json( "$totals_dir/tablespaces_total.json",    $tablespaces_total );
}

sub gen_groups {
  my %main_folders_subg;
  for my $alias ( keys %creds ) {
    my $main_group = $creds{$alias}{menu_group};
    my $sub_group  = $creds{$alias}{menu_subgroup};
    undef @{ $main_folders_subg{_mgroups}{_OracleDB}{_dbs}{$alias} };
    if ( $creds{$alias}{type} eq "RAC" or $creds{$alias}{type} eq "RAC_Multitenant" ) {
      push( @{ $main_folders_subg{_mgroups}{_OracleDB}{_dbs}{$alias} }, @{ $creds{$alias}{hosts} } );
    }
    else {
      push( @{ $main_folders_subg{_mgroups}{_OracleDB}{_dbs}{$alias} }, $creds{$alias}{host} );
    }
    if ( $main_group and $main_group ne "" ) {
      undef @{ $main_folders_subg{_mgroups}{$main_group}{_dbs}{$alias} };
      if ( $creds{$alias}{type} eq "RAC" or $creds{$alias}{type} eq "RAC_Multitenant" ) {
        push( @{ $main_folders_subg{_mgroups}{$main_group}{_dbs}{$alias} }, @{ $creds{$alias}{hosts} } );
      }
      else {
        push( @{ $main_folders_subg{_mgroups}{$main_group}{_dbs}{$alias} }, $creds{$alias}{host} );
      }
      if ( $sub_group and $sub_group ne "" ) {
        undef @{ $main_folders_subg{_mgroups}{$main_group}{_sgroups}{$sub_group}{_dbs}{$alias} };
        if ( $creds{$alias}{type} eq "RAC" or $creds{$alias}{type} eq "RAC_Multitenant" ) {
          push( @{ $main_folders_subg{_mgroups}{$main_group}{_sgroups}{$sub_group}{_dbs}{$alias} }, @{ $creds{$alias}{hosts} } );
        }
        else {
          push( @{ $main_folders_subg{_mgroups}{$main_group}{_sgroups}{$sub_group}{_dbs}{$alias} }, $creds{$alias}{host} );
        }
      }
    }
    else {
      undef @{ $main_folders_subg{_mgroups}{ $creds{$alias}{type} }{_dbs}{$alias} };
      if ( $creds{$alias}{type} eq "RAC" or $creds{$alias}{type} eq "RAC_Multitenant" ) {
        push( @{ $main_folders_subg{_mgroups}{ $creds{$alias}{type} }{_dbs}{$alias} }, @{ $creds{$alias}{hosts} } );
      }
      else {
        push( @{ $main_folders_subg{_mgroups}{ $creds{$alias}{type} }{_dbs}{$alias} }, $creds{$alias}{host} );
      }
    }
  }
  %groups = %main_folders_subg;
  my $groups_file = "$totals_dir/groups.json";
  if ( -e $groups_file ) {
    backup_file($groups_file);
  }
  Xorux_lib::write_json( $groups_file, \%main_folders_subg );

  #  print Dumper \%main_folders_subg;
}

sub backup_file {

  # expects file name for the file, that's supposed to be moved from iostats_dir, with file
  # name "hostname_datetime.json" to tmpdir
  my $src_file = shift;
  my $source   = "$src_file";
  my $target   = "$source.old";

  move( $source, $target ) or Xorux_lib::error( "Cannot backup data $source: $!" . __FILE__ . ":" . __LINE__ );

  return 1;
}

sub gen_healthstatus {

  #my @host_aliases = keys %creds;
  $alias = "Totals";
  my $rows = "";
  my @files;
  opendir( DH, $hs_dir ) || Xorux_lib::error("Could not open '$hs_dir' for reading '$!'\n") && exit;
  @files = sort( grep /.*\.(ok|nok)/, readdir DH );
  closedir(DH);

  #print Dumper \@files;
  foreach my $file (@files) {
    open( FH, '<', "$hs_dir/$file" ) or warn "Could not open '$hs_dir/$file' for reading" && next;
    my $line = "";
    while (<FH>) {
      $line = $_;
      last;
    }
    my @arr = split( / : /, $line );

    #print Dumper \@arr;
    my ( $status, $lpar_alias, $instance, $time, $error );
    if ( $arr[3] eq "OK" ) {
      $status = "OPEN";
    }
    else {
      $status = "CLOSED";
    }

    #      my $host_url;
    #      my $host_link;
    #      if($creds{$total_alias}{type} eq "RAC"){
    #        $host_url  = OracleDBMenu::get_url( { type => 'configuration_S', host => "not_needed", server => $total_alias } );
    #        $host_link = "<a href=\"$host_url\"><b>$total_alias</b></a>";
    #        push(@arr, $host_link);
    #      }else{
    #        $host_url  = OracleDBMenu::get_url( { type => 'configuration', host => $creds{$total_alias}{host}, server => $total_alias } );
    #        $host_link = "<a href=\"$host_url\"><b>$total_alias</b></a>";#style=\"text-decoration: underline;\"
    #        push(@arr, $host_link);
    #      }
    my $instance_names;
    my ( $can_read, $ref ) = Xorux_lib::read_json("$main_data_dir/$arr[1]/instance_names.json");
    if ($can_read) {
      $instance_names = $ref;
    }
    $lpar_alias = $arr[1];
    $instance   = defined $instance_names->{ $arr[2] } ? $instance_names->{ $arr[2] } : $arr[2];
    $time       = localtime( $arr[4] );
    $error      = defined $arr[5] ? $arr[5] : " ";
    my @row_vals = ( $status, $lpar_alias, $instance, $time, $error );
    close(FH);
    $rows .= ${ generate_row( \@row_vals ) };
  }
  my $tables = ${ generate_table( \@{ $headers{'Health status'} }, \$rows, 'Health status', "info" ) };
  create_file( 'Health status', $tables );

  #    foreach my $n_alias (@host_aliases){
  #      $total_alias = $n_alias;
  #      my ( $code, $ref );
  #      $conf_dir = "$main_data_dir/$n_alias/configuration";
  #
  #      if ( -f "$conf_dir/conf.json" ) {
  #        ( $code, $ref ) = Xorux_lib::read_json( "$conf_dir/conf.json" );
  #      }
  #
  #      if ( $code ) {
  #        my $data = $ref;
  #          if ($data->{$creds{$n_alias}{type}}->{'Main info'}){
  #            $rows{'Health status'} .= ${ gen_info($data->{$creds{$n_alias}{type}}->{'Main info'},'Health status', "just_rows")};
  #          }else{
  #            warn "Main info   Doesnt exist in $n_alias conf";
  #          }
  #      }
  #    }
  #        #print Dumper \%rows;
  #        my $tables = ${generate_table( \@{$headers{'Health status'}},\$rows{'Health status'}, 'Health status',"info")};
  #        create_file('Health status', $tables);
}

sub gen_totals_conf {
  my $checkup_file = "$main_data_dir/Totals/total_conf";
  my $run_conf     = DatabasesWrapper::can_update("$checkup_file", 3600, 1);

  if ($run_conf) {
    my $rows = "";

    #undef %totals;
    for my $group ( keys %{ $groups{_mgroups} } ) {
      my %rows;

      #print Dumper \%{$groups{_mgroups}{$group}{_dbs}};
      %rows = %{ tablerows_per_group( \%{ $groups{_mgroups}{$group}{_dbs} } ) };
      foreach my $header (@headers_only_totals) {
        my $tables = ${ generate_table( \@{ $headers{$header} }, \$rows{$header}, $header, "info" ) };
        create_file( $header, $tables, "filler", "_$group" );
      }
      for my $sub_group ( keys %{ $groups{_mgroups}{$group}{_sgroups} } ) {
        my %rows_sgroup;
        %rows_sgroup = %{ tablerows_per_group( \%{ $groups{_mgroups}{$group}{_sgroups}{$sub_group}{_dbs} } ) };
        foreach my $header (@headers_only_totals) {
          my $tables = ${ generate_table( \@{ $headers{$header} }, \$rows_sgroup{$header}, $header, "info" ) };
          create_file( $header, $tables, "filler", "_$sub_group" );
        }
      }
    }
  }
  else {
    return;
  }
}

sub tablerows_per_group {
  my $aliases_ref = shift;
  my %aliases     = %{$aliases_ref};
  my %rows;

  for my $n_alias ( keys %aliases ) {
    print "$n_alias\n";
    $total_alias = $n_alias;
    $conf_dir    = "$main_data_dir/$n_alias/configuration";
    my ( $code, $ref );

    if ( -f "$conf_dir/conf.json" ) {
      ( $code, $ref ) = Xorux_lib::read_json("$conf_dir/conf.json");
    }

    if ($code) {
      my $data = $ref;
      foreach my $header (@headers_only_totals) {
        if ( $data->{ $creds{$n_alias}{type} }->{$header} ) {
          $rows{$header} .= ${ gen_info( $data->{ $creds{$n_alias}{type} }->{$header}, $header, "just_rows" ) };
          $alias = "Totals";
        }
        else {
          warn "$header   Doesnt exist in $n_alias conf";
        }
      }
    }
  }
  return \%rows;
}

sub gen_info {
  my $hsh          = shift;
  my $type         = shift;
  my $totals_check = shift;
  my $pdb_check    = shift;
  my %hash         = %{$hsh};
  my $rows         = "";
  my %totals;
  my %tbs_percent;

  foreach my $header ( @{ $headers{'Tablespace info'} } ) {
    $totals{$header} = 0;
  }

  #print Dumper \%hash;
  for my $key (%hash) {

    #print "\n$key";
    if ( ref($key) ne "ARRAY" ) {
      my @help_arr = @{ $hash{$key} };
      #warn Dumper \@help_arr;
      for my $i ( 0 .. $#help_arr ) {
        my @arr;
        if ( $key =~ /ERROR at line|invalid identifier/ ) {
          next;
        }
        if ( $type ne "Main info" and $type ne "Health status" and $type ne "Upgrade, Downgrade info" and $type ne "Online Redo Logs" ) {
          push( @arr, $key );
        }
        else {
          #          if($total_alias ne "" and $type ne "Health status"){
          #            my $host_url;
          #            my $host_link;
          #            if($creds{$total_alias}{type} eq "RAC"){
          #              $host_url  = OracleDBMenu::get_url( { type => 'configuration_S', host => "not_needed", server => $total_alias } );
          #              #$host_url  = OracleDBMenu::get_url( { type => 'Overview', host => $aggr_hosts, server => $total_alias } );
          #              $host_link = "<a href=\"$host_url\"><b>$total_alias</b></a>";
          #              push(@arr, $host_link);
          #            }else{
          #              $host_url  = OracleDBMenu::get_url( { type => 'configuration', host => $creds{$total_alias}{host}, server => $total_alias } );
          #              $host_link = "<a href=\"$host_url\"><b>$total_alias</b></a>";#style=\"text-decoration: underline;\"
          #              push(@arr, $host_link);
          #            }
          #          }
        }
        foreach my $header ( @{ $headers{$type} } ) {
          if ( $header eq "LPAR2RRD alias" ) {
            my $host_url;
            my $host_link;
            my $host_alias;
            if ( $total_alias ne "" ) {
              $host_alias = $total_alias;
            }
            else {
              $host_alias = $alias;
            }
            my $odb_id = "";
            if ( $creds{$host_alias}{type} eq "RAC" or $creds{$host_alias}{type} eq "RAC_Multitenant" ) {
              $odb_id   = OracleDBDataWrapper::get_uuid( $host_alias, "RAC" );
              $host_url = OracleDBMenu::get_url( { type => 'configuration_S', id => $odb_id } );

              #$host_url  = OracleDBMenu::get_url( { type => 'Overview', host => $aggr_hosts, server => $total_alias } );
              $host_link = "<a style=\"padding:0px\" href=\"$host_url\">$host_alias</a>";
              push( @arr, $host_link );
            }
            elsif ( $creds{$total_alias}{type} eq "RAC_Multitenant" ) {
              $odb_id   = OracleDBDataWrapper::get_uuid( $host_alias, "RAC" );
              $host_url = OracleDBMenu::get_url( { type => 'configuration_Multitenant', id => $odb_id } );

              #$host_url  = OracleDBMenu::get_url( { type => 'Overview', host => $aggr_hosts, server => $total_alias } );
              $host_link = "<a style=\"padding:0px\" href=\"$host_url\">$host_alias</a>";
              push( @arr, $host_link );
            }
            elsif ( $creds{$host_alias}{type} eq "Multitenant" ) {
              $odb_id    = OracleDBDataWrapper::get_uuid( $host_alias, "Multitenant" );
              $host_url  = OracleDBMenu::get_url( { type => 'configuration_Multitenant', id => $odb_id } );
              $host_link = "<a style=\"padding:0px\" href=\"$host_url\">$host_alias</a>";
              push( @arr, $host_link );
            }
            else {
              $odb_id    = OracleDBDataWrapper::get_uuid( $host_alias, "Standalone" );
              $host_url  = OracleDBMenu::get_url( { type => 'configuration', id => $odb_id } );
              $host_link = "<a style=\"padding:0px\" href=\"$host_url\">$host_alias</a>";         #style=\"text-decoration: underline;\"
              push( @arr, $host_link );
            }
            next;
          }

          #          if($header eq "Last update"){
          #            push(@arr, "$generate_time");
          #            next;
          #          }
          #          if($header eq "ERROR"){
          #            if($hash{$key}[$i]{Status} and $hash{$key}[$i]{Status} eq "CLOSED"){
          #              push(@arr, " ");
          #            }else{
          #              push(@arr, " ");
          #            }
          #            next;
          #         }
          if ( $hash{$key}[$i]{$header} ) {
            $hash{$key}[$i]{$header} =~ s/,/./g;
          }
          if ( defined $hash{$key}[$i]{$header} and $hash{$key}[$i]{$header} =~ /^\./ ) {
            my $added_zero = "0" . "$hash{$key}[$i]{$header}";

            push( @arr, $added_zero );

            if ( $type eq "Tablespace info" ) {
              if ( $header eq "TBS allocate size MB" or $header eq "TBS max size MB" ) {
                $tbs_percent{$header} = $added_zero;
              }
              $totals{$header} += $added_zero;
            }
          }
          else {
            my $addd_zr = $hash{$key}[$i]{$header};
            if ( $type eq "Tablespace info" ) {
              if ( isDigit( $hash{$key}[$i]{$header} ) and $hash{$key}[$i]{$header} ne "" or $hash{$key}[$i]{$header} ne " " ) {
                $totals{$header} += $hash{$key}[$i]{$header};
              }
              else {
                $totals{$header} = "";
              }
              if ( $header eq "TBS allocate size MB" or $header eq "TBS max size MB" ) {
                $tbs_percent{$header} = $addd_zr;
              }
              my $number = sprintf( "%.0f", $addd_zr / 1024 );
              $addd_zr = "$number GiB";

            }
            elsif ( $type eq "IO Read Write per datafile" ) {
              $addd_zr = sprintf( "%2d", $addd_zr );

            }
            elsif ( $type eq "Alert History" and $header eq "CREATION_TIME" ) {
              $addd_zr = "$addd_zr TIMESTAMP";
            }
            elsif ( $type eq "Upgrade, Downgrade info" and $header eq "ID" and (!defined $addd_zr or $addd_zr eq "" )) {
              $addd_zr = "n/a";
            }
            push( @arr, $addd_zr );
          }
        }

        #print Dumper \@arr;
        if ( $type eq "Tablespace info" ) {
          my $denom;
          if ( $tbs_percent{"TBS max size MB"} and $tbs_percent{"TBS allocate size MB"} ) {
            if ( $tbs_percent{"TBS max size MB"} == 0 or $tbs_percent{"TBS max size MB"} eq "0" ) {
              $denom = 1;
            }
            else {
              $denom = $tbs_percent{"TBS max size MB"};
            }
            my $percent = sprintf( "%.0f", ( $tbs_percent{"TBS allocate size MB"} / $tbs_percent{"TBS max size MB"} ) * 100 );
            $tablespace_percent{$arr[0]} = $percent;
            push( @arr, $percent );
          }
        }
        $rows .= ${ generate_row( \@arr, $type ) };
      }
    }
  }

  #print Dumper \%totals;
  if ( $type eq "Tablespace info" ) {

    my @arr_t;
    push( @arr_t, "Total" );
    if ( $total_alias ne "" ) {
      my $aggr_hosts = "aggregated";

      #foreach my $current_host (@{$creds{$total_alias}{hosts}}){
      #  $aggr_hosts .= "_$current_host->{host}";
      #}
      my $host_url  = "";
      my $host_link = "";
      my $odb_id    = "";
      if ( $creds{$total_alias}{type} eq "RAC" ) {
        $odb_id   = OracleDBDataWrapper::get_uuid( $total_alias, "RAC" );
        $host_url = OracleDBMenu::get_url( { type => 'configuration_S', id => $odb_id } );

        #$host_url  = OracleDBMenu::get_url( { type => 'Overview', host => $aggr_hosts, server => $total_alias } );
        $host_link = "<a style=\"padding:0px\" href=\"$host_url\">$total_alias</a>";
        push( @arr_t, $host_link );
      }
      elsif ( $creds{$total_alias}{type} eq "RAC_Multitenant" ) {
        $odb_id   = OracleDBDataWrapper::get_uuid( $total_alias, "RAC" );
        $host_url = OracleDBMenu::get_url( { type => 'configuration_Multitenant', id => $odb_id } );

        #$host_url  = OracleDBMenu::get_url( { type => 'Overview', host => $aggr_hosts, server => $total_alias } );
        $host_link = "<a style=\"padding:0px\" href=\"$host_url\">$total_alias</a>";
        push( @arr_t, $host_link );
      }
      elsif ( $creds{$total_alias}{type} eq "Multitenant" ) {
        $odb_id    = OracleDBDataWrapper::get_uuid( $total_alias, "Multitenant" );
        $host_url  = OracleDBMenu::get_url( { type => 'configuration_Multitenant', id => $odb_id } );
        $host_link = "<a style=\"padding:0px\" href=\"$host_url\">$total_alias</a>";
        push( @arr_t, $host_link );
      }
      else {
        $odb_id    = OracleDBDataWrapper::get_uuid( $total_alias, "Standalone" );
        $host_url  = OracleDBMenu::get_url( { type => 'configuration', id => $odb_id } );
        $host_link = "<a style=\"padding:0px\" href=\"$host_url\">$total_alias</a>";        #style=\"text-decoration: underline;\"
        push( @arr_t, $host_link );
      }
    }
    foreach my $header ( @{ $headers{$type} } ) {
      if ( $totals{$header} and $totals{$header} >= 1000000 ) {
        my $number = sprintf( "%.2f", $totals{$header} / 1024 / 1024 );
        push( @arr_t, "$number TiB" );
      }
      else {
        my $number = sprintf( "%.0f", $totals{$header} / 1024 );
        push( @arr_t, "$number GiB" );
      }
    }
    my $max_size = $totals{"TBS max size MB"};
    if ( $max_size <= 0 ) {
      $max_size = 1;
    }
    my $t_percent = sprintf( "%.0f", ( $totals{"TBS allocate size MB"} / $max_size ) * 100 );
    $t_percent_alert = $t_percent;
    push( @arr_t, $t_percent );
    my $h_rows   = ${ generate_row( \@arr_t, "total" ) };
    my $h_tables = ${ generate_table( \@{ $headers{$type} }, \$rows, "$type", "info", "total", \$h_rows ) };
    if ( $totals_check and $totals_check eq "just_rows" ) {
      $h_rows =~ s/th/td/g;
      return \$h_rows;
    }
    else {
      return \$h_tables;
    }
  }
  my $tables = ${ generate_table( \@{ $headers{$type} }, \$rows, "$type", "info" ) };
  if ( $totals_check and $totals_check eq "just_rows" ) {
    return \$rows;
  }
  else {
    return \$tables;
  }
}

sub gen_histogram {
  my $hsh  = shift;
  my $type = shift;
  my %hash = %{$hsh};
  my %totals;
  my @test_arr;
  my $tables = "";

  #  foreach my $header (@{$headers{$type}}){
  #    $totals{$header} = 0;
  #  }
  #print Dumper \%hash;
  for my $key (%hash) {
    my $rows = "";

    #print "\n$key";
    if ( ref($key) ne "ARRAY" ) {
      my @help_arr = @{ $hash{$key} };

      #print Dumper \@help_arr;
      for my $i ( 0 .. $#help_arr ) {
        my @arr;
        push( @arr, $key );
        foreach my $header ( @{ $headers{$type} } ) {
          $hash{$key}[$i]{$header} =~ s/,/./g;
          if ( $hash{$key}[$i]{$header} =~ /^\./ ) {
            my $added_zero = "0" . "$hash{$key}[$i]{$header}";
            push( @arr, $added_zero );

            #  $totals{$header} += $added_zero;
          }
          else {
            #  if(isDigit($hash{$key}[$i]{$header}) and $hash{$key}[$i]{$header} ne ""){
            #    $totals{$header} += $hash{$key}[$i]{$header};
            #  }else{
            #    $totals{$header} = "";
            #  }
            push( @arr, $hash{$key}[$i]{$header} );
          }
        }
        $rows .= ${ generate_row( \@arr ) };

        #print Dumper \@arr;
      }
      $tables .= ${ generate_table( \@{ $headers{$type} }, \$rows, "$type" ) };
      push( @test_arr, ${ generate_table( \@{ $headers{$type} }, \$rows, "$type" ) } );
    }
  }

  #  my @arr_t;
  #  push(@arr_t, "Grand total");
  #  foreach my $header (@{$headers{$type}}){
  #    push(@arr_t, $totals{$header});
  #  }
  #  my $h_rows = ${generate_row(\@arr_t)};
  if ( $type eq 'SGA info' or $type eq 'Data rate per service name' ) {
    return \$tables;
  }
  else {
    return \@test_arr;
  }
}

sub create_file {
  my $type   = shift;
  my $tables = shift;
  my $temp   = shift;
  my $group  = shift;
  my $file;
  if ( $temp and $temp ne "filler" and $temp ne "pdb" ) {
    $file = OracleDBDataWrapper::get_dir( $temp, $alias );
  }
  elsif ( $group and $temp ne "pdb" ) {
    $file = OracleDBDataWrapper::get_dir( $type, $alias, "filler", $group );
  }
  elsif ( $group and $temp eq "pdb" ) {
    $file = OracleDBDataWrapper::get_dir( $type, $alias, "pdb", $group );
  }
  else {
    $file = OracleDBDataWrapper::get_dir( $type, $alias );
  }
  print $file. "\n";
  if ( $file ne "err" ) {
    open( HOSTH, '>', $file ) || Xorux_lib::error( "Couldn't open file $file $!" . __FILE__ . ":" . __LINE__ );
    print HOSTH $tables;    #, \$h_rows ) };
    print HOSTH "<br>\n";
    if ( $type ne "Health status" ) {
      print HOSTH "It is updated once an hour, last run: " . $generate_time;
    }
    else {
      print HOSTH "Last updated: " . $generate_time;
    }
    close(HOSTH);
  }
}

################################################################################

sub generate_row {
  my $val_ref = shift;
  my $total   = shift;
  my @values  = @{$val_ref};
  my $row     = '';
  if ( $values[0] eq "Total" ) {
    shift @values;
    if ( $total_alias eq "" ) {
      $row .= "<tr>\n";
      $row .= '<th style="padding: 2px">Total</th>';
    }

    foreach my $value (@values) {

      #style="padding-right: 2em"
      my $gb_val = $value;
      if ( $gb_val =~ /TiB/ ) {
        $gb_val =~ s/TiB//g;
        $gb_val = $gb_val * 1024;
      }
      elsif ( $gb_val =~ /GiB/ ) {
        $gb_val =~ s/GiB//g;
      }
      elsif ( $gb_val =~ /TIMESTAMP/ ) {
        $value =~ s/TIMESTAMP//g;
        $gb_val = str2time($value);
      }
      else {
        $gb_val = "";
      }
      $row .= "<th style= \"color:black; text-align:right; padding-right:2em;\" data-text=\"$gb_val\" nowrap=\"\">$value</th>\n";

      #$row .= '<th style= "color:black; text-align:right; padding-right:2em;" nowrap="" data-text="'."$gb_val".'">';
      #$row .= "$value</th>";
      $row .= "\n";
    }
    $row .= "</tr>\n";
  }
  else {
    $row .= "<tr>\n";
    my $counter = 0;
    foreach my $value (@values) {
      $value = '' unless defined $value;
      if ( $value eq "OPEN") {
        if (DatabasesWrapper::get_file_timediff("$conf_dir/conf.json") <= 5000) {
          $row .= "<td class=\"hsok\" style=\"text-align:left; color:black;\" nowrap=\"\"></td>\n";
        }else{
          $row .= "<td class=\"hsnok\" style=\"text-align:left; color:black;\" nowrap=\"\"></td>\n";
        }
      }
      elsif ( $value eq "CLOSED" ) {
        $row .= "<td class=\"hsnok\" style=\"text-align:left; color:black;\" nowrap=\"\"></td>\n";
      }
      elsif ( $value =~ /TIMESTAMP/ ) {
        my $gb_val = "";
        $value =~ s/TIMESTAMP//g;
        $gb_val = str2time($value);
        $row .= "<td style= \"text-align:left;color:black;\" data-text=\"$gb_val\" nowrap=\"\">$value</td>\n";
      }
      else {
        if ( $counter > 0 and $total and $total eq "Tablespace info" ) {
          $row .= "<td style=\"text-align:right; color:black; padding-right:2em;\" nowrap=\"\">$value</td>\n";
        }
        else {
          if ( $counter < 1 ) {
            $counter = 1;
          }
          $row .= "<td style=\"text-align:left; color:black;\" nowrap=\"\">$value</td>\n";
        }
      }
    }
    $row .= "</tr>\n";
  }

  return \$row;
}

sub generate_table {
  my @header    = @{ shift @_ };
  my $rows      = ${ shift @_ };
  my $headline  = shift;
  my $h_check   = shift;
  my $g_totalpr = shift;
  my $g_total   = "empty";
  if ( $g_totalpr and $g_totalpr eq "total" ) {
    $g_total = ${ shift @_ };
  }
  my $acc = "";

  if ( $rows eq '' ) {
    return \$acc;
  }

  $acc .= "<center>\n";
  if ( $h_check and $g_total ne "empty" ) {
    $acc .= "<br><br><b></b>\n";
    $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilters\" data-sortby=\"2\">\n";
  }
  else {
    if ( defined $headline ) {
      if ( $headline eq "SGA info" ) {
        $acc .= "<br><br><b></b><br><br>\n";
        $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\">\n";
      }
      elsif ( $headline eq 'Upgrade, Downgrade info' or $headline eq 'PSU, patches info' ) {
        $acc .= "<br><br><b></b>\n";
        $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\" data-sortby=\"1\">\n";
      }
      elsif ( $headline eq 'Alert History' or $headline eq 'IO Read Write per datafile' ) {
        $acc .= "<br><br><b></b>\n";
        $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\" data-sortby=\"2\">\n";
      }
      else {
        $acc .= "<br><br><b style=\"font-size: 1.2em;\">$headline:</b><br><br>\n";
        $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\">\n";
      }
    }
    else {
      $acc .= "<br>\n";
      $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\">\n";
    }
  }

  $acc .= "<thead>\n";
  $acc .= "<tr>\n";
  if ( defined $headline and ( $headline eq "Main info" or $headline eq "Tablespace info" or $headline eq "online redo logs" or $headline eq "Upgrade, Downgrade info" ) ) {
    if ( $total_alias ne "" and $headline ne "Main info" ) {
      $acc .= "<th class = \"sortable\" style=\"text-align:center; color:black;\" nowrap=\"\">LPAR2RRD Alias</th>\n";
    }
    else {
      if ( $headline eq "Tablespace info" ) {
        $acc .= "<th class = \"sortable\" aria-sort=\"descending\" style=\"text-align:center; color:black;\" nowrap=\"\"></th>\n";
      }
    }
  }
  else {
    unless ( defined $headline and $headline eq "Health status" ) {
      if ( $headline and $headline eq "Alert History" ) {
        $acc .= "<th class = \"sortable\" aria-sort=\"descending\" style=\"text-align:center; color:black;\" nowrap=\"\">INSTANCE</th>\n";
      }
      else {
        $acc .= "<th class = \"sortable\" aria-sort=\"descending\" style=\"text-align:center; color:black;\" nowrap=\"\"></th>\n";
      }
    }
  }

  #  if(defined $headline and $headline eq "Tablespace info"){
  #    if($total_alias ne ""){
  #      $acc .= "<th class = \"sortable\" style=\"text-align:center; color:black;\" nowrap=\"\">LPAR2RRD Alias</th>\n";
  #    }else{
  #      $acc .= "<th class = \"sortable\" aria-sort=\"descending\" style=\"text-align:center; color:black;\" nowrap=\"\"></th>\n";
  #    }
  #  }
  foreach my $column (@header) {
    if ( defined $headline and $headline eq "Tablespace info" ) {
      $column =~ s/MB//g;
      $column =~ s/TBS //g;
    }
    elsif ( defined $headline and $headline eq "Tablespace info" ) {
      $column =~ s/MESSAGE_//g;
    }
    elsif ( defined $headline and $headline eq "Main info" ) {
      $column =~ s/LCPUS/lCPU/g;
      $column =~ s/VCPUS/vCPU/g;
    }
    $acc .= "<th class = \"sortable\" style=\"text-align:center; color:black;\" nowrap=\"\">$column</th>\n";
  }
  if ( defined $headline and $headline eq "Tablespace info" ) {
    $acc .= "<th class = \"sortable\" style=\"text-align:center; color:black;\" nowrap=\"\">Used %</th>\n";
  }
  $acc .= "</tr>\n";
  $acc .= "</thead>\n";
  if ( $g_total ne "empty" ) {
    $acc .= "<tbody>\n";
    $acc .= $g_total;
    $acc .= "</tbody>\n";
  }
  $acc .= "<tbody>\n";

  $acc .= $rows;
  $acc .= "</tbody>\n";
  $acc .= "</table>\n";
  $acc .= "</center>\n";

  return \$acc;
}

sub isDigit {
  my $digit = shift;

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  return 0;
}



