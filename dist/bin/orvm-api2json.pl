# ######.pl
# download API data dump from Oracle VM

use 5.008_008;
use strict;
use warnings;
use Data::Dumper;
use HostCfg;
use Xorux_lib qw(error);
use LWP::UserAgent;
use HTTP::Request;
use Time::Local;
use POSIX;

use JSON qw(decode_json encode_json);

my $inputdir = $ENV{INPUTDIR};
require "$inputdir/bin/xml.pl";

my $path_prefix    = "$inputdir/data/OracleVM";
my $xml_path       = "$path_prefix/xml";
my $json_path      = "$path_prefix/iostats";
my $metadata_path  = "$path_prefix/metadata";
my $error_log_orvm = "$inputdir/logs/load_oraclevm.err";
my $SSH            = $ENV{SSH} . " ";

my @server_metrics      = ( "CPU_UTILIZATION",             "MEMORY_USED", "MEMORY_UTILIZATION", "FREE_MEMORY", "FREE_SWAP", "DISK_READ", "DISK_WRITE" );
my @server_metrics_net  = ( "NETWORK_SENT",                "NETWORK_RECEIVED" );
my @server_metrics_disk = ( "DISK_READ",                   "DISK_WRITE" );
my @vm_metrics          = ( "CPU_UTILIZATION",             "CPU_COUNT", "MEMORY_USED", "DISK_READ", "DISK_WRITE" );
my @vm_metrics_net      = ( "NETWORK_SENT",                "NETWORK_RECEIVED" );
my @vm_metrics_disk     = ( "DISK_READ",                   "DISK_WRITE" );
my @fs_metrics          = ( "FILE_SYSTEM_SPACE_AVAILABLE", "FILE_SYSTEM_SPACE_UTILIZATION", "FILE_SYSTEM_SPACE_TOTAL", "FILE_SYSTEM_TOTAL_FILES_SIZE" );
my %data_hash           = ();
my %server_hash         = ();
my %vm_hash             = ();
my %fs_hash             = ();
my $act_time            = time();
my $act_date            = localtime($act_time);

#my $end_date            = localtime($end_timestamp);
#my $start_date          = localtime($start_timestamp);

# create directories in data/
unless ( -d $path_prefix ) {
  mkdir( "$path_prefix", 0755 ) || Xorux_lib::error( " Cannot mkdir $path_prefix: $!" . __FILE__ . ":" . __LINE__ );
}
unless ( -d $xml_path ) {
  mkdir( "$xml_path", 0755 ) || Xorux_lib::error( " Cannot mkdir $xml_path: $!" . __FILE__ . ":" . __LINE__ );
}
unless ( -d $json_path ) {
  mkdir( "$json_path", 0755 ) || Xorux_lib::error( " Cannot mkdir $json_path: $!" . __FILE__ . ":" . __LINE__ );
}
else {
  # clean old files
  my @old_files = <$json_path/*.json>;

  foreach my $file (@old_files) {
    unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ );
  }
}
unless ( -d $metadata_path ) {
  mkdir( "$metadata_path", 0755 ) || Xorux_lib::error( " Cannot mkdir $metadata_path: $!" . __FILE__ . ":" . __LINE__ );
}

if ( !-f $error_log_orvm ) {
  print "create log for rest_api errors: $error_log_orvm\n";
  `touch $error_log_orvm`;
}

my %hosts = %{ HostCfg::getHostConnections("OracleVM") };
my @pids;
my $pid;
my $timeout = 900;

foreach my $host ( keys %hosts ) {

  # fork for each host
  unless ( defined( $pid = fork() ) ) {
    Xorux_lib::error("Error: failed to fork for $host.\n");
    next;
  }
  else {
    if ($pid) {
      push @pids, $pid;
    }
    else {
      local $SIG{ALRM} = sub { die "OracleVM ORACLEVM2JSON: $pid timeouted.\n"; };
      alarm($timeout);

      my ( $hostname, $username, $port ) = ( $hosts{$host}{host}, $hosts{$host}{username}, $hosts{$host}{api_port} );

      if ( $hosts{$host}{auth_api} ) {
        my $password = $hosts{$host}{password};

        #print "$hostname,$port,$username,$password\n";
        oraclevm2json( $hostname, $username, $password, $port );
      }

      #if ( $hosts{$host}{auth_ssh} ) {
      #  my $ssh_key = $hosts{$host}{ssh_key_id};
      #  ssh2json( $hostname, $username, $ssh_key );
      #}

      exit;
    }
  }
}

# wait for forked data retrieval
for $pid (@pids) {
  waitpid( $pid, 0 );
}

use POSIX ":sys_wait_h";

sub oraclevm2json {

  my ( $host, $username, $password, $port ) = @_;
  my $rrdfile = "rrd_updates";
  my $start_time;
  my $end_time;
  my $start_time_to_manager = time;
  $start_time_to_manager = $start_time_to_manager * 1000;    # convert to milisec
                                                             #my $start_time = time() - 20*60; # last 20 minutes
                                                             #$start_time    = $start_time * 1000; # convert to milisec
                                                             #my $end_time   = time () *1000 ; # convert to milisec
  print "=============== START collecting information about OracleVM environment =================\n\n";
  print "Host_IP_address:$host, User:$username\n";
  ####################### REST API INFO
  my $url_stat_rest_api = "https://$host:$port/ovm/core/wsapi/rest/Manager";
  my $xml_file_rest_api = "$xml_path/$rrdfile\_$host\_$start_time_to_manager.xml";
  print "rest_api info url - $url_stat_rest_api\n";
  my $json_rest_api          = new_get_request( $xml_file_rest_api, $url_stat_rest_api, $host, $username, $password );
  my $manager_info_json_file = "$json_path/OracleVM\_$host\_managerinfo\_$start_time_to_manager.json";
  print "result_api: $json_rest_api\n";
  my $json_hash_rest_api;

  if ( $json_rest_api ne "0" ) {
    $json_hash_rest_api = decode_json($json_rest_api);

    #print Dumper $json_hash_rest_api;
    open( JSON_MAN, "> $manager_info_json_file" ) || die "error: cannot save the JSON\n";
    print JSON_MAN "$json_rest_api";
    close(JSON_MAN);
    foreach my $info_api ( @{ $json_hash_rest_api->{'manager'} } ) {
      my $name              = $info_api->{'name'}[0];
      my $timestamp_manager = $info_api->{'managerTime'}[0];
      my $manager_status    = $info_api->{'managerRunState'}[0];
      my $manager_version   = $info_api->{'managerVersion'}[0];
      my $manager_read      = $info_api->{'readOnly'}[0];

      #######################################################################################
      ################## manager time to timestamp
      $timestamp_manager = $timestamp_manager / 1000;
      $timestamp_manager = sprintf "%.0f", $timestamp_manager;
      $start_time        = $timestamp_manager - 20 * 60;         # last 20min ( you can change 1-60min)
      $start_time        = $start_time * 1000;                   # convert to ms
      $end_time          = $timestamp_manager * 1000;            # convert to ms
      ########################################################################################

      my $date_human = strftime( "%Y-%m-%d %H:%M:%S", localtime($timestamp_manager) );
      print "Manager name: $name\n";
      print "Timestamp manager: $timestamp_manager($date_human)\n";
      my $my_time       = time;
      my $my_time_human = strftime( "%Y-%m-%d %H:%M:%S", localtime($my_time) );
      print "Timestamp on LPAR2RRD server: $my_time($my_time_human)\n";
      print "Version: $manager_version\n";
      if ( $manager_status =~ /STARTING/ ) {
        print "Status: $manager_status(setting)";
        print "OracleVM manager is still being set up. Wait about a few minutes on status RUNNING.\n";
        exit;
      }
      elsif ( $manager_status =~ /RUNNING/ ) {
        print "Status: $manager_status\n";
      }
      else {
        print "Status: $manager_status\n";
      }

      #print "Read rights: $manager_read\n";
    }
  }
  else {    #### REST API NO RUNNING
    Xorux_lib::error("Does not work OracleVM rest_api     : $act_time : $act_date");
    print "Does not work OracleVM rest_api\n";
    exit;
  }
  #######################

  print "\n===============SERVER fetching config data=================\n";

  ### Values for collecting values from Server,VM etc
  my $db_url_server     = "https://$host:$port/ovm/core/wsapi/rest/Server";
  my $db_url_vm         = "https://$host:$port/ovm/core/wsapi/rest/Vm";
  my $db_url_serverpool = "https://$host:$port/ovm/core/wsapi/rest/ServerPool";
  my $db_url_repos      = "https://$host:$port/ovm/core/wsapi/rest/Repository";    ### REPOSITORY

  ### XML
  my $xml_server     = "$xml_path/$rrdfile\_server_\_$host\_$start_time.xml";
  my $xml_vm         = "$xml_path/$rrdfile\_vm_\_$host\_$start_time.xml";
  my $xml_serverpool = "$xml_path/$rrdfile\_serverpool_\_$host\_$start_time.xml";
  my $xml_repos      = "$xml_path/$rrdfile\_repos_\_$host\_$start_time.xml";        ### REPOSITORY

  ### JSON
  my $server_info_json_file     = "$json_path/OracleVM\_$host\_serverinfo\_$start_time.json";
  my $vm_info_json_file         = "$json_path/OracleVM\_$host\_vminfo\_$start_time.json";
  my $serverpool_info_json_file = "$json_path/OracleVM\_$host\_serverpoolinfo\_$start_time.json";
  my $repos_info_json_file      = "$json_path/OracleVM\_$host\_repository\_$start_time.json";       ### REPOSITORY

  ### Request on collecting config DATA
  my $server_info_json     = new_get_request( $xml_server,     $db_url_server,     $host, $username, $password );
  my $vm_info_json         = new_get_request( $xml_vm,         $db_url_vm,         $host, $username, $password );
  my $serverpool_info_json = new_get_request( $xml_serverpool, $db_url_serverpool, $host, $username, $password );
  my $repos_info_json      = new_get_request( $xml_repos,      $db_url_repos,      $host, $username, $password );    ### REPOSITORY
  ### Check result from API and save to JSON
  ### SERVER
  my $vm_info_sum;
  my $server_info_sum;
  my $serverpool_info;
  my $repos_info;

  if ( $server_info_json ne "0" ) {
    print "Servers config_info: found\n";
    ### Print config data in JSON to json_file
    open( JSON_SER, "> $server_info_json_file" ) || die "error: cannot save the JSON\n";
    print JSON_SER "$server_info_json";
    close(JSON_SER);

    #print "INFO1:$server_info_json\n";
    $server_info_sum = decode_json($server_info_json);

    #print Dumper $server_info;
  }
  else {
    print "Servers config_info: not found\n";
  }
  ### VM
  if ( $vm_info_json ne "0" ) {
    print "VMs config_info: found\n";
    ### Print config data in JSON to json_file
    open( JSON_VM, "> $vm_info_json_file" ) || die "error: cannot save the JSON\n";
    print JSON_VM "$vm_info_json";
    close(JSON_VM);

    #print "INFO2:$vm_info_json\n";
    $vm_info_sum = decode_json($vm_info_json);

    #print Dumper $vm_info_json;
  }
  else {
    print "VMs config_info: not found\n";
  }
  ### SERVER_POOL
  if ( $serverpool_info_json ne "0" ) {
    print "ServerPools config_info: found\n";

    #print "INFO3:$serverpool_info_json\n";
    $serverpool_info = decode_json($serverpool_info_json);

    #print Dumper $serverpool_info;
  }
  else {
    print "ServerPools config_info: not found\n";
  }
  ### REPOS
  if ( $repos_info_json ne "0" ) {
    print "Servers config_info: found\n";
    ### Print config data in JSON to json_file
    open( JSON_SER, "> $repos_info_json_file" ) || die "error: cannot save the JSON\n";
    print JSON_SER "$repos_info_json";
    close(JSON_SER);

    #print "INFO1:$repos_info_json\n";
    $repos_info = decode_json($repos_info_json);

    #print Dumper $repos_info;
  }
  else {
    print "Repository config_info: not found\n";
  }

  #my $server_info   = decode_json ($server_info_json);
  #my $serverpool_info   = decode_json ($serverpool_info_json);
  ################################## NETWORK INFO
  #my $xml_file_net      = "$xml_path/$rrdfile\_$host\_$start_time.xml";
  #my $url_network = "https://$host:$port/ovm/core/wsapi/rest/Network";
  #my $json_network   = new_get_request ($xml_file_net,$url_network,$host,$username,$password);
  #my $hash_network   = decode_json ($json_network);
  #print Dumper $hash_network;
  #################################################

  print "===============SERVER fetching data=================\n";
  ############################################### CREATE PERF FILES
  ############################### SERVER perf
  my $item1       = "";
  my $xml_file    = "$xml_path/$rrdfile\_$host\_$start_time.xml";
  my $json_file   = "$json_path/OracleVM\_$host\_perf_$start_time.json";
  my $db_url      = "https://$host:$port/ovm/core/wsapi/rest/Server/id";
  my $db_url_stat = "https://$host:$port/ovm/core/wsapi/rest/Statistic";
  my $json_server = new_get_request( $xml_file, $db_url, $host, $username, $password );
  my $hash_server = decode_json($json_server);

  #print Dumper $json_server;
  #print Dumper $hash_server;
  #print "\n";
  if ( $server_info_json ne "0" ) {
    foreach my $metric (@server_metrics) {
      my $first_run          = 0;
      my $last_network_value = "0";
      print "Server request for $metric metric\n";

      #print Dumper $hash_server;
      if ( defined $hash_server->{'simpleId'} && ref( $hash_server->{'simpleId'} ) eq "ARRAY" ) {
        foreach ( @{ $hash_server->{'simpleId'} } ) {
          my $server_uuid     = "";
          my $server_name     = "";
          my $net_name        = "";
          my $param_avg_ornot = "range";
          $server_uuid = $_->{'value'}[0];
          $server_name = $_->{'name'}[0];
          my $uuid = $server_uuid;
          $server_uuid =~ s/://g;
          my $new_db_url = "$db_url_stat/Server/$uuid/$metric/$param_avg_ornot?startTime=$start_time&endTime=$end_time";

          #print "url_server - $new_db_url\n";
          my $server_info = new_get_request( $xml_file, $new_db_url, $host, $username, $password );
          if ( $server_info ne "0" ) {
            my $get_data = decode_json($server_info);

            #print Dumper $get_data;
            #print $get_data->{'value'};
            foreach my $stat ( @{ $get_data->{'statistic'} } ) {

              #print Dumper $stat;
              #print "$stat->{'value'}[0]\n";
              my $value   = $stat->{'value'}[0];
              my $start_t = $stat->{'startTime'}[0];
              if ( $metric eq "CPU_UTILIZATION" ) {
                $value = sprintf '%.4f', $value;
              }
              else { $value = sprintf '%.2f', $value; }
              $item1 = "server";
              if ( $metric eq "CPU_UTILIZATION" ) {
                if ( defined $server_info_sum->{'server'} && ref( $server_info_sum->{'server'} ) eq "ARRAY" ) {
                  foreach ( @{ $server_info_sum->{'server'} } ) {

                    #my $count_proc = $_->{'cpuIds'}[1];
                    my $count_proc = scalar( @{ $_->{cpuIds} } );

                    #my $count_proc = scalar keys %{ $_->{'cpuIds'}};
                    my $host_name            = $_->{'name'}[0];
                    my $cpu_proc_socket      = $_->{'populatedProcessorSockets'}[0];
                    my $cpu_cores_per_socket = $_->{'coresPerProcessorSocket'}[0];
                    my $total_proc_cores     = $_->{'totalProcessorCores'}[0];
                    my $enab_proc_cores      = $_->{'enabledProcessorCores'}[0];
                    my $thread_per_core      = $_->{'threadsPerCore'}[0];

                    #print Dumper $server_info_sum;
                    #print Dumper $count_proc;
                    if ( $host_name eq $server_name ) {
                      my $cpu_test = $enab_proc_cores * $thread_per_core;
                      $data_hash{$item1}{$server_uuid}{$server_name}{$start_t}{COUNT_CORES} = $cpu_cores_per_socket;
                      $data_hash{$item1}{$server_uuid}{$server_name}{$start_t}{COUNT_PROC}  = $count_proc;

                      #print "$hostik_name  - count_proc-$count_proc,,,,$cpu_test\n!!!\n";
                    }
                  }
                }
              }
              $data_hash{$item1}{$server_uuid}{$server_name}{$start_t}{$metric} = $value;
            }
          }
          else {
            print "ERROR Server statistic\n";
          }
        }
      }
    }
    ######################## SERVER net statistic
    my $start_time_net = $start_time - 60000;
    foreach my $metric (@server_metrics_net) {

      #print Dumper $hash_server;
      if ( defined $hash_server->{'simpleId'} && ref( $hash_server->{'simpleId'} ) eq "ARRAY" ) {
        foreach ( @{ $hash_server->{'simpleId'} } ) {
          my $server_uuid = "";
          my $server_name = "";
          my $net_name    = "";
          $server_uuid = $_->{'value'}[0];
          $server_name = $_->{'name'}[0];
          my $uuid = $server_uuid;
          $server_uuid =~ s/://g;

          #$start_time         = $start_time - 60000;
          my $new_db_url  = "$db_url_stat/Server/$uuid/$metric/range?startTime=$start_time_net&endTime=$end_time";
          my $server_info = new_get_request( $xml_file, $new_db_url, $host, $username, $password );
          if ( $server_info ne "0" ) {
            my $get_data = decode_json($server_info);

            #print Dumper $get_data;
            #print $get_data->{'value'};
            foreach my $stat ( @{ $get_data->{'statistic'} } ) {
              my $value   = $stat->{'value'}[0];
              my $start_t = $stat->{'startTime'}[0];
              $net_name = $stat->{'component'}[0];

              #print Dumper $stat;
              $value = sprintf '%.2f', $value;
              if ( $net_name !~ /^net|^eth|^em/ ) { next; }
              $item1 = "server_net";
              push @{ $data_hash{$item1}{$server_uuid}{$net_name}{$start_t} }, $value;
              ############### collecting -60sec data for counting totals
              #my $start_time_count = $start_t - 60000;
              #my $end_time_count  = $start_t - 120000;
              #my $new_db_url_count    = "$db_url_stat/Server/$uuid/$metric/range?startTime=$start_time_count&endTime=$end_time_count";
              #my $server_info_count   = new_get_request ($xml_file,$new_db_url_count,$host,$username,$password);
              #my $get_data_count   =  decode_json ($server_info_count);
            }
          }
          else {
            print "ERROR Server net statistic\n";
          }
        }
      }
    }

    #print Dumper \%data_hash;

    foreach my $metric (@server_metrics_disk) {

      #print Dumper $hash_server;
      if ( defined $hash_server->{'simpleId'} && ref( $hash_server->{'simpleId'} ) eq "ARRAY" ) {
        foreach ( @{ $hash_server->{'simpleId'} } ) {
          my $server_uuid = "";
          my $server_name = "";
          my $net_name    = "";
          $server_uuid = $_->{'value'}[0];
          $server_name = $_->{'name'}[0];
          my $uuid = $server_uuid;
          $server_uuid =~ s/://g;

          #$start_time        = $start_time - 60000;
          my $new_db_url  = "$db_url_stat/Server/$uuid/$metric/range?startTime=$start_time_net&endTime=$end_time";
          my $server_info = new_get_request( $xml_file, $new_db_url, $host, $username, $password );
          if ( $server_info ne "0" ) {
            my $get_data = decode_json($server_info);
            ##print Dumper $get_data;
            #print $get_data->{'value'};
            foreach my $stat ( @{ $get_data->{'statistic'} } ) {
              my $value   = $stat->{'value'}[0];
              my $start_t = $stat->{'startTime'}[0];
              $net_name = $stat->{'component'}[0];

              #print Dumper $stat;
              $value = sprintf '%.2f', $value;

              #if ($net_name !~ /^net|^eth/) { next;}
              $item1 = "server_disk";
              push @{ $data_hash{$item1}{$server_uuid}{$net_name}{$start_t} }, $value;
              ############### collecting -60sec data for counting totals
              #my $start_time_count = $start_t - 60000;
              #my $end_time_count  = $start_t - 120000;
              #my $new_db_url_count    = "$db_url_stat/Server/$uuid/$metric/range?startTime=$start_time_count&endTime=$end_time_count";
              #my $server_info_count   = new_get_request ($xml_file,$new_db_url_count,$host,$username,$password);
              #my $get_data_count   =  decode_json ($server_info_count);
            }
          }
          else {
            print "ERROR Server disk statistic\n";
          }
        }
      }
      else {
        print "ERROR Server disk statistic\n";
      }
    }
  }
  else {
    print "Not found Server IDs\n";
  }

  #open( JSON_FH, "> $json_file" ) || die "error: cannot save the JSON\n";
  #print JSON_FH  "$json_data1\n";
  #close(JSON_FH);
  #print Dumper \%data_hash;
  #exit;

  ################################## VM info to perf files
  my $item2 = "vm";
  $xml_file = "$xml_path/$rrdfile\_$host\_$start_time.xml";

  #$json_file         = "$json_path/OracleVM_$item2\_$host\_perf_$start_time.json";
  $db_url      = "https://$host:$port/ovm/core/wsapi/rest/Vm/id";
  $db_url_stat = "https://$host:$port/ovm/core/wsapi/rest/Statistic";
  my $json_vm = new_get_request( $xml_file, $db_url, $host, $username, $password );
  if ( $json_vm ne "0" ) {
    my $hash_vm = decode_json($json_vm);
    print "\n======================VM fetching data======================\n";
    foreach my $metric (@vm_metrics) {
      if ( defined $hash_vm->{'simpleId'} && ref( $hash_server->{'simpleId'} ) eq "ARRAY" ) {
        foreach ( @{ $hash_vm->{'simpleId'} } ) {
          my $vm_uuid = "";
          my $vm_name = "";
          $vm_uuid = $_->{'value'}[0];
          $vm_name = $_->{'name'}[0];
          my $uuid            = $vm_uuid;
          my $param_avg_ornot = "range";
          my $new_db_url      = "$db_url_stat/Vm/$uuid/$metric/$param_avg_ornot?startTime=$start_time&endTime=$end_time";

          #print "url_vm - $new_db_url\n";
          my $vm_info = new_get_request( $xml_file, $new_db_url, $host, $username, $password );
          if ( $json_vm ne "0" ) {
            my $get_data = decode_json($vm_info);

            #print Dumper $vm_info_sum;
            #print Dumper $get_data;
            foreach my $stat ( @{ $get_data->{'statistic'} } ) {
              my $value   = $stat->{'value'}[0];
              my $start_t = $stat->{'startTime'}[0];
              $value = sprintf '%.2f', $value;
              $data_hash{$item2}{$uuid}{$vm_name}{$start_t}{$metric} = $value;

              #print "$metric-$vm_name,$uuid,$value,$start_t,$end_time\n";
            }
          }
          else {
            print "ERROR VM statistic\n";
          }
        }
      }
    }
    ################################# VM disk's info to perf files
    my $hash_vm_disk = decode_json($json_vm);
    foreach my $metric (@vm_metrics_disk) {
      if ( defined $hash_vm->{'simpleId'} && ref( $hash_server->{'simpleId'} ) eq "ARRAY" ) {
        foreach ( @{ $hash_vm_disk->{'simpleId'} } ) {
          my $vm_uuid = "";
          my $vm_name = "";
          $vm_uuid = $_->{'value'}[0];
          $vm_name = $_->{'name'}[0];
          my $uuid            = $vm_uuid;
          my $param_avg_ornot = "range";
          my $new_db_url      = "$db_url_stat/Vm/$uuid/$metric/$param_avg_ornot?startTime=$start_time&endTime=$end_time";
          my $vm_info         = new_get_request( $xml_file, $new_db_url, $host, $username, $password );

          #print Dumper $vm_info;
          if ( $json_vm ne "0" ) {
            my $get_data = decode_json($vm_info);

            #print Dumper $get_data;
            foreach my $stat ( @{ $get_data->{'statistic'} } ) {
              my $value     = $stat->{'value'}[0];
              my $start_t   = $stat->{'startTime'}[0];
              my $disk_uuid = $stat->{'component'}[0];
              $value = sprintf '%.2f', $value;
              my $item1 = "vm_disk";

              #            $data_hash{$item2}{$uuid}{$vm_name}{$start_t}{$metric} = $value;
              #          push @{ $data_hash{ $item1 }{ $server_uuid }{$net_name}{$start_t} },$value;
              push @{ $data_hash{$item1}{$uuid}{$disk_uuid}{$start_t} }, $value;

              #print "$metric-$vm_name,$uuid,$value,$start_t,$end_time\n";
            }
          }
        }
      }
    }
    ################################# VM net's info to perf files
    my $hash_vm_net = decode_json($json_vm);
    foreach my $metric (@vm_metrics_net) {
      if ( defined $hash_vm->{'simpleId'} && ref( $hash_server->{'simpleId'} ) eq "ARRAY" ) {
        foreach ( @{ $hash_vm_net->{'simpleId'} } ) {
          my $vm_uuid = "";
          my $vm_name = "";
          $vm_uuid = $_->{'value'}[0];
          $vm_name = $_->{'name'}[0];
          my $uuid            = $vm_uuid;
          my $param_avg_ornot = "range";
          my $new_db_url      = "$db_url_stat/Vm/$uuid/$metric/$param_avg_ornot?startTime=$start_time&endTime=$end_time";
          my $vm_info         = new_get_request( $xml_file, $new_db_url, $host, $username, $password );

          if ( $json_vm ne "0" ) {
            my $get_data = decode_json($vm_info);

            #print Dumper $get_data;
            foreach my $stat ( @{ $get_data->{'statistic'} } ) {
              my $value    = $stat->{'value'}[0];
              my $start_t  = $stat->{'startTime'}[0];
              my $net_uuid = $stat->{'component'}[0];
              $value = sprintf '%.2f', $value;
              my $item1 = "vm_net";

              #            $data_hash{$item2}{$uuid}{$vm_name}{$start_t}{$metric} = $value;
              #          push @{ $data_hash{ $item1 }{ $server_uuid }{$net_name}{$start_t} },$value;
              push @{ $data_hash{$item1}{$uuid}{$net_uuid}{$start_t} }, $value;

              #print "$metric-$vm_name,$uuid,$value,$start_t,$end_time\n";
            }
          }
        }
      }
    }
  }
  else {
    print "Not found VM IDs\n";
  }
  ################################## REPOSITORY info to perf files
  #my $item3          = "repos";
  #$xml_file          = "$xml_path/$rrdfile\_$host\_$start_time.xml";
  #$json_file         = "$json_path/OracleVM_$item3\_$host\_perf_$start_time.json";
  #$db_url            = "https://$host:$port/ovm/core/wsapi/rest/Repository/id";
  #$db_url_stat       = "https://$host:$port/ovm/core/wsapi/rest/Statistic";
  #my $json_repos        = new_get_request ($xml_file,$db_url,$host,$username,$password);
  #my $hash_repos        = decode_json ($json_repos);

  #print Dumper \%data_hash;
  #my $start_time_net         = $start_time - 60000;
  #open( JSON_FH, "> $json_file" ) || die "error: cannot save the JSON\n";
  #print "!!$json_data2!!\n";
  #close(JSON_FH);

  ################################## FS info to perf files
  # my $item3          = "filesystem";
  # $xml_file          = "$xml_path/$rrdfile\_$host\_$start_time.xml";
  # $json_file         = "$json_path/OracleVM_$item3\_$host\_perf_$start_time.json";
  # $db_url            = "https://$host:$port/ovm/core/wsapi/rest/FileSystem/id";
  # $db_url_stat       = "https://$host:$port/ovm/core/wsapi/rest/Statistic";
  # my $json_fs        = new_get_request ($xml_file,$db_url,$host,$username,$password);
  # my $hash_fs        = decode_json ($json_fs);
  # my $start_time_fs  = time() - 10*60; # last 10 minutes - capacity statistic
  # $start_time_fs     = $start_time_fs * 1000; # convert to milisec
  # my $end_time_fs    = time () *1000 ; # convert to milisec
  # print "\n======================FS======================\n";
  # print Dumper $hash_fs;
  # print ",,\n";
  #foreach my $metric (@fs_metrics){
  #  if ( defined $hash_fs->{'simpleId'} && ref($hash_fs->{'simpleId'}) eq "ARRAY" ){
  #    foreach ( @{ $hash_fs->{'simpleId'} } ) {
  #      my $vm_uuid      = "";
  #my $fs_name      = "";
  #      $vm_uuid         = $_->{'value'}[0];
  #$fs_name         = $_->{'name'}[0];
  #      my $uuid         = $vm_uuid;
  #      my $param_avg_ornot = "range";
  #      my $new_db_url   = "$db_url_stat/FileSystem/$uuid/$metric/$param_avg_ornot?startTime=$start_time_fs&endTime=$end_time_fs"; #### NEFUNGUJE PRO FILESYSTEM - POUZE KAPACITNI!!! ZMENIT
  #      #print "$new_db_url===\n";
  #      my $vm_info      = new_get_request ($xml_file,$new_db_url,$host,$username,$password);
  #      my $get_data   =  decode_json ($vm_info);
  #print Dumper $get_data;
  #      foreach my $stat( @{ $get_data->{'statistic'} } ) {
  #        my $value = $stat->{'value'}[0];
  #        my $start_t = $stat->{'startTime'}[0];
  #$fs_hash{$uuid}{$start_t}{$metric} = $value;
  #        push @{ $data_hash{$item3}{$uuid}{$start_t} },$value;
  #print "$metric-$fs_name,$uuid,$value,$start_time,$end_time\n";
  #      }
  #    }
  #  }
  #}

  #print Dumper \%data_hash;
  #print Dumper \%fs_hash;
  #my $hash_to_json = %data_hash;
  #my $get_data   =  encode_json ($hash_to_json);

  my $get_data = encode_json( \%data_hash );
  open( JSON_FH, "> $json_file" ) || die "error: cannot save the JSON\n";
  print JSON_FH "$get_data\n";
  close(JSON_FH);

  #print Dumper \%server_hash;
  #print Dumper \%vm_hash;
  #print Dumper \%fs_hash;

}

sub new_get_request {
  my $xml_file = shift;
  my $db_url   = shift;
  my $host     = shift;
  my $username = shift;
  my $password = shift;

  #print "xml_file, $db_url,$host,$username,$password\n";
  my $ua = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 } );

  #print Dumper $ua;
  my $req = HTTP::Request->new( GET => $db_url );

  #print Dumper $req;
  $req->content_type('application/xml');
  $req->header( 'Accept' => '*/*' );
  $req->authorization_basic( "$username", "$password" );
  my $res = $ua->request($req);
  if ( $res->is_success ) {
    if ( $res->{_content} eq "" ) {
      Xorux_lib::status_json( 0, "connected to Oracle VM, but response is empty\n" );
      error("connected to Oracle VM, but response is empty: \"$db_url\"! Exiting...");
      next;
    }
    else {
      print "successfully request - $db_url\n";

      # warn Dumper $res->{_content};
      #exit 0;
    }
  }
  else {
    #Xorux_lib::status_json(0, $res->status_line);
    my $status = "$res->status_line";

    #print Dumper $res;
    if ( $db_url =~ /Manager$/ ) {
      error( "Result from Manager not success (url-$db_url):  $!" . __FILE__ . ":" . __LINE__ );
      error("Message content: \"$res->{_content}\"!");
      exit;
    }
    else {
      error( "Result from OracleVM not success (url-$db_url):  $!" . __FILE__ . ":" . __LINE__ );
      error("Message content: \"$res->{_content}\"!");
      next;
    }
  }

  open( XML_FH, "> $xml_file" ) || die "error: cannot save the received RRD XML file\n";
  print XML_FH "$res->{_content}\n";
  close(XML_FH);

  my $data;
  my $xml_simple = XML::Simple->new( keyattr => [], ForceArray => 1 );

  eval { $data = $xml_simple->XMLin($xml_file); };

  #print "get_request: $@\n";
  if ($@) {
    message("XML parsing error: $@");
    message("XML parsing error. Trying to recover XML with xmllint");

    eval {
      my $linted = `xmllint --recover $xml_file`;
      $data = $xml_simple->XMLin($linted);
    };

    if ($@) {
      Xorux_lib::error( "XML parsing error: " . $@ . __FILE__ . ":" . __LINE__ . " file:" . $xml_file );
      message( "XML parsing error: File: " . $xml_file );
      die "error: invalid XML\n";
    }
  }

  # save as JSON
  my $json_data = encode_json($data);
  unlink $xml_file;
  return $json_data;
}

sub message {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "$act_time: $text\n";

  return 1;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  #print "$act_time: $text : $!\n" if $DEBUG > 2;;

  return 1;
}

