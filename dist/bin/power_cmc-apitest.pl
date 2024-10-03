use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use Socket;
use JSON;
use Time::Local;
use LWP::UserAgent;
use HTTP::Request;
use RRDp;

use Xorux_lib;

# Decision tree:
# ? real data ?
#---------------------------
# YES: ? collecting from endpoint /inventory/tags is OK ?
#     ---------------------------
#     YES: continue
#     NO: print RETURN message
#         EXIT
#     ---------------------------
# NO: load data from JSON in bin: inventory_tags.json
#---------------------------

# if here, then exists: %inventory_tags

# SETUP data checking variable: data_check = 1

# ? proper JSON structure ?
#---------------------------
# YES: collect data
# NO: data_check = 0
#     fill error data message 
#---------------------------

# ? Collected server data ? and data_check = 1
#---------------------------
# YES: Prepare informative data message
# NO:  data_check = 0
#      fill error data message
#---------------------------

#---------------------------
# FINISH:
#---------------------------
# if connection ok -> print OK message
# if data OK -> print informative data message
# if data NOK-> print error data message
my $real_data = 1;

my %data;
  
# Only purpose of lpar2rrd dir in apitest is to use fake data
my $lpar2rrd_dir;

$lpar2rrd_dir  = "/home/lpar2rrd/lpar2rrd";
#$lpar2rrd_dir = $ENV{"INPUTDIR"} || Xorux_lib::error("INPUTDIR is not defined")     && exit;

my $testing_file = "${lpar2rrd_dir}/bin/usage_tags.json";
if ( -f "$testing_file") {
 $real_data = 0;
}

#------------------------------
# Xorux_lib::
#------------------------------
# PARAMETERS
my $portal_url;
my $CMC_client_id;
my $CMC_client_secret;
my $proxy;

$portal_url        = defined $ARGV[0] ? $ARGV[0] : "";
$CMC_client_id     = defined $ARGV[1] ? $ARGV[1] : "";
$CMC_client_secret = defined $ARGV[2] ? $ARGV[2] : "";
$proxy             = defined $ARGV[3] ? $ARGV[3] : "";

#---------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------
# REQUEST
# NOTE: All API calls are automatically rate limited to a maximum of 10 calls per second.
#-----------------------------------------------------------------------------------
sub general_hash_request {
  my $method = shift;
  my $query = shift;

  my $request_message = '';

  my $ua    = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH',
                                                 verify_hostname => 0,
                                                 SSL_verify_mode => 0 } );

  # PROXY is global variable
  if ($proxy){
    # expected proxy format: http://host:port
    $request_message .= "Connecting to $query with proxy: $proxy <br>";
    $ua->proxy( ['http', 'https', 'ftp'] => $proxy );
  }
  else{
    $request_message .= "Connecting to $query <br>";
  }

  my $req = HTTP::Request->new( $method => $query );

  $req->header( 'X-CMC-Client-Id'     => "$CMC_client_id" );
  $req->header( 'X-CMC-Client-Secret' => "$CMC_client_secret" );
  $req->header( 'Accept'              => 'application/json' );

  my $res = $ua->request($req);

  my %decoded_json;

  eval{

    eval{
      %decoded_json = %{decode_json($res->{'_content'})};
    };
    if($@){

      print "<br>$method $query\n";
      
      if ($proxy){
        print "<br> with proxy: $proxy";
      }

      my $error_message = "";
      #$error_message .= "<br> PROBLEM OCCURED during decode_json HASH with url $query!" ;
      $error_message .= "<br> Message: <br> $res->{'_content'} <br>";

      if ($error_message =~ /503 Service Unavailable/){
        $error_message .= "<br><br>Please check validity of used CMC configuration data.";
      }
      
      print "$error_message";
      exit 0;  
    }

  };
  if($@){
    print "<br>$method $query";
    if ($proxy){
      print "<br> with proxy: $proxy";
    }
    print "<br> Message: <br> $res->{'_content'} <br>";
    my $error_message = "";
    $error_message .= "<br> Message: <br> $res->{'_content'} <br>";

    if ($error_message =~ /503 Service Unavailable/){
      $error_message .= "<br><br>Please check validity of used CMC configuration data.";
    }
    
    exit 0;
  }

  return %decoded_json;
}

#-----------------------------------------------------------------------------------
# TIME HANDLING
# OUT: $StartTS, $EndTS
#-----------------------------------------------------------------------------------
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst );
my $use_time = time();
my $time = $use_time;
my $secs_delay = 600;
my $start_time = $use_time - $secs_delay;
( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($start_time);

my $StartTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, $min );

my $end_time = $use_time;
( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($end_time);

my $EndTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, $min );

my $Frequency = "Minute";


sub file_to_string{
  my $filename = shift;
  my $json;
  open(FH, '<', $filename) or die $!;
  while(<FH>){
     $json .= $_;
  }
  close(FH);
  return $json;
}

#---------------------------------------------------------------------------------
my %name_queries = (
  'inventory_tags'     => {
    'query' => "https://${portal_url}/api/public/v1/ep/inventory/tags",
    'frequency' => 'Hourly',
  },
  'usage_pools'        => {
    'query'  => "https://${portal_url}/api/public/v1/ep/usage/pools",
    'frequency' => 'Hourly',
  },
  'management_console' => {
    'query' => "https://${portal_url}/api/public/v1/inventory/cmc/ManagementConsole",
    'frequency' => 'Hourly',
  },
);

my $connection_result = 1;
my $data_test_result = 1;

my $data_message = '';

my %inventory_tags;
if ($real_data){
  %inventory_tags = general_hash_request("GET",  "https://${portal_url}/api/public/v1/ep/inventory/tags");
}else{
  %inventory_tags = %{decode_json(file_to_string("${lpar2rrd_dir}/bin/inventory_tags.json"))};
}


if (defined $inventory_tags{Tags} && ref($inventory_tags{Tags}) eq 'ARRAY' ){
   
  for (my $i=0; $i<scalar(@{$inventory_tags{Tags}}); $i++){
    for (my $j=0; $j<scalar(@{$inventory_tags{Tags}[$i]{Systems}}); $j++){
      my %subhash = %{$inventory_tags{Tags}[$i]{Systems}[$j]};
      # possibly could be ""
      if (defined $subhash{PoolID} && $subhash{PoolID}){ 
        my $pool_id = $subhash{PoolID};
        my $UUID    = $subhash{UUID};

        $data{Pools}{$pool_id}{Name} = $subhash{PoolName};
        
        $data{Pools}{$pool_id}{Systems}{$UUID}{Name} = $subhash{Name};
        $data{Systems}{$UUID}{Pools}{$pool_id}{Name} = $subhash{PoolName};

        $data{Systems}{$UUID}{Name}                = $subhash{Name};
        $data{Systems}{$UUID}{State}               = $subhash{State};
      }
    }
  }

}
else{
  # BAD JSON FORMAT, NO DATA
  $data_test_result = 0; 
  
  $data_message .= "<br>QUERY: https://${portal_url}/api/public/v1/ep/inventory/tags <br>";
  $data_message .= "No data. <br>";
  $data_message .= "Note that all servers in PEP 2.0  must be tagged in order for the CMC API to return performance metrics. <br>";
  $data_message .= '<br><a href="https://lpar2rrd.com/IBM-Power-Systems-performance-monitoring-installation.php?5.0#PEP2">Installation documentation</a><br>';
}


# NO LOADED DATA
if ( scalar(keys %{$data{Systems}}) eq 0 && $data_test_result) {
  $data_test_result = 0; 
  
  $data_message .= "<br>QUERY: https://${portal_url}/api/public/v1/ep/inventory/tags <br>";
  $data_message .= "No data. <br>";
  $data_message .= "Note that all servers in PEP 2.0  must be tagged in order for the CMC API to return performance metrics. <br>";
  $data_message .= '<br><a href="https://lpar2rrd.com/IBM-Power-Systems-performance-monitoring-installation.php?5.0#PEP2">Installation documentation</a><br>';
}

# USAGE TAGS
my $url_usage_tags = "https://${portal_url}/api/public/v1/ep/usage/tags";

sub create_url_usage_tags {
  my $base_url = shift;
  $base_url .= "?EndTS=${EndTS}&Frequency=${Frequency}&StartTS=${StartTS}";
  return $base_url;
}

# CHECK ARRAY OF METRICS
my $metrics_not_ok = 0;
if ($data_test_result){
  my %usage_tags;
  
  if ($real_data){
    %usage_tags = general_hash_request("GET", create_url_usage_tags($url_usage_tags));
  }else{
    %usage_tags = %{decode_json(file_to_string("${lpar2rrd_dir}/bin/usage_tags.json"))};
  }

  if (defined $usage_tags{Tags}){
    for (my $i=0; $i<scalar(@{$usage_tags{Tags}}); $i++){

      # TAGGED SYSTEMS
      if ($usage_tags{Tags}[$i]{SystemsUsage}){
        for (my $j=0; $j<scalar(@{$usage_tags{Tags}[$i]{SystemsUsage}{Systems}}); $j++){
          my %subhash = %{$usage_tags{Tags}[$i]{SystemsUsage}{Systems}[$j]};
    
          my $UUID                                         = $subhash{UUID};
          if (defined $data{Systems}{$UUID}){
            if (! defined $data{Systems}{$UUID} && defined $subhash{Usage}{Usage}){
              $metrics_not_ok = 1;
              $data{Systems}{$UUID}{Message} = 'Usage data not approachable.';
            }
            else{
              $data{Systems}{$UUID}{Message} = ''; 
            }
          }
        }
      }
    }
  }  
}

my @tagged_pools = keys %{$data{Pools}};

my $url_usage_pools = "https://${portal_url}/api/public/v1/ep/usage/pools";

sub create_url_usage_pools {
  my $base_url = shift;

  $base_url .= "?EndTS=${EndTS}&Frequency=Minute&StartTS=${StartTS}";

  return $base_url;
}

my %usage_pools;
if ($real_data){
  %usage_pools = general_hash_request("GET", create_url_usage_pools($url_usage_pools));
}
else{
  %usage_pools = %{decode_json(file_to_string("${lpar2rrd_dir}/bin/usage_pools.json"))};
}

if (defined $usage_pools{Pools}){
  for (my $i=0; $i<scalar(@{$usage_pools{Pools}}); $i++){
    my $ID = $usage_pools{Pools}[$i]{PoolID};
    # possibly could be ""
    if ($ID){ 
      $data{Pools}{$ID}{Name} = $usage_pools{Pools}[$i]{PoolName};
    }
  }
}
else{
  # BAD JSON FORMAT, NO DATA
  $data_test_result = 0; 
  
  $data_message .= "<br>QUERY: https://${portal_url}/api/public/v1/ep/usage/pools <br>";
  $data_message .= "No pool data. <br>";
}

# for test:
#$data{Pools}{UNTAG}{Name} = 'UNTAGGED_Pool_NAME_x';

my @all_pools = keys %{$data{Pools}};

my %pool_check;
for my $some_pool (@all_pools){
  $pool_check{$some_pool} = 0;
}
for my $tagged_pool (@tagged_pools){
  $pool_check{$tagged_pool} = 1;
}

my @untagged_pools;
my $tagging_problem = 0;
for my $some_pool (keys %pool_check){
  if ($some_pool){
    if (! $pool_check{$some_pool}){
      $tagging_problem = 1;
      push (@untagged_pools, $data{Pools}{$some_pool}{Name});

    }
  }
}


# CREATE MAIN DATA MESSAGE
if ( $data_test_result ){
  if (defined  $data{Pools} && scalar(keys %{$data{Pools}} gt 0)){
    for my $pool_id (sort keys  %{$data{Pools}}){
      my $pool_name = $data{Pools}{$pool_id}{Name};
      
      $data_message .= "Pool: $pool_name <br>";
      $data_message .= "Servers: ";
      if (! keys %{ $data{Pools}{$pool_id}{Systems}}){
        $data_message .= "N/A";
      }
      $data_message .= "<br>";
      my $longest_group_spacing = 20;
 
      for my $UUID (keys %{ $data{Pools}{$pool_id}{Systems}}){
        my $server_name  =  $data{Pools}{$pool_id}{Systems}{$UUID}{Name};
        if (length($server_name) > $longest_group_spacing ){
          $longest_group_spacing = length($server_name);   
        } 
      }  

      $longest_group_spacing += 5;   
      
      for my $UUID (keys %{ $data{Pools}{$pool_id}{Systems}}){
        my $server_name  =  $data{Pools}{$pool_id}{Systems}{$UUID}{Name}; 
        my $name_len = $longest_group_spacing - length($server_name);
        my $spaces = ' 'x$name_len;
        my $name_print = "$server_name".$spaces;
        my $server_state =  "$data{Systems}{$UUID}{State} $data{Systems}{$UUID}{Message}"; 
        $data_message .= "  $name_print $server_state  <br>";
      }
  
      $data_message .= "<br>";
      if ($metrics_not_ok){
        #$data_message .= '<br> Some server data are not approachable.';
      }
    }
  }
  else{
    # NO POOLS FOUND
    $data_test_result = 0;
    $data_message .= "No PEP 2.0 found <br>";
    $data_message .= "Note that all servers in PEP 2.0  must be tagged in order for the CMC API to return performance metrics. <br>";
    $data_message .= '<br><a href="https://lpar2rrd.com/IBM-Power-Systems-performance-monitoring-installation.php?5.0#PEP2">Installation documentation</a><br>';
  }
}

if ($tagging_problem){
  $data_message .= "<br>You have some pools with no tagged servers: @untagged_pools";
  $data_message .= "<br>Note that all servers in PEP 2.0  must be tagged in order for the CMC API to return performance metrics. <br>";
  $data_message .= '<br><a href="https://lpar2rrd.com/IBM-Power-Systems-performance-monitoring-installation.php?5.0#PEP2">Installation documentation</a><br>';
}

my $message;

# PROPER PRINTING
if ( $connection_result ){
  # this is used to decide whether connection is ok
  # First nonspace chars of print of OK result message must be OK 
  $message = " OK <br>";
  print $message;

  print "<b>API data test: </b>";

  if ( $data_test_result ){
    $message = "<span class='noerr'>OK<\/span>";
    $message .= "<pre>$data_message</pre>";
    print $message;
  }
  else{
    $message = "<span class='error'>NOK<\/span>";
    print $message;
    print "$data_message";
  }

}
##   list HMCs
#my $url_management_console = "https://${portal_url}/api/public/v1/inventory/cmc/ManagementConsole";
#my %management_console_data;
#
#my %managed_hmc_data;
#if ($real_data){
#  %managed_hmc_data = general_hash_request("GET", $url_management_console);
#}else{
#  %managed_hmc_data = %{decode_json(file_to_string("${lpar2rrd_dir}/bin/management_console.json"))};
#}
#
#my %hmc_information;
#
#if (defined $managed_hmc_data{HMCs}){
#  for (my $i = 0; $i<scalar(@{$managed_hmc_data{HMCs}}); $i++){
#    my %one_hmc_data = %{$managed_hmc_data{HMCs}[$i]};
#  
#    my $hmc_uuid = $one_hmc_data{UUID};
#    my $hmc_name = $one_hmc_data{Name};
#    my $uvmid    = $one_hmc_data{UVMID};
#
#    $data{HMCs}{$hmc_uuid}{Name} = $managed_hmc_data{HMCs}[$i]{Name};
#    $data{HMCs}{$hmc_uuid}{Configuration}{UVMID} = $managed_hmc_data{HMCs}[$i]{UVMID};
#
#    for (my $j = 0; $j<scalar(@{$one_hmc_data{ManagedSystems}}); $j++){
#      my $UUID = $one_hmc_data{ManagedSystems}[$j]{UUID};
#      my $system_name = $one_hmc_data{ManagedSystems}[$j]{Name};
#
#      if ($data{Systems}{$UUID}){
#        $data{Systems}{$UUID}{HMCs}{$hmc_uuid} = $hmc_name;
#        $data{HMCs}{$hmc_uuid}{Systems}{$UUID} = $system_name; 
#      }
#    }
#  }
#}
#else{
#  print "QUERY: $url_management_console \n";
#  print "No Pools data. \n";
#}

## HMC CHECK
## Check if configured hmcs match hmcs connected to cmc
#use Power_cmc_Power_service;
#use HostCfg;
#
#my %host_hash = %{HostCfg::getHostConnections("IBM Power Systems")};
#
#my %hmc_check;
#my %uvmid_uuid;
#my %uuid_uvmid;
#
#print Dumper %data;
## CMC
#for my $UUID (keys %{$data{HMCs}}){
#  my $UVMID = $data{HMCs}{$UUID}{Configuration}{UVMID};
#
#  $hmc_check{$UVMID}{cmc}  = 1;
#  $hmc_check{$UVMID}{lpar} = 0;
#
#  $uvmid_uuid{$UVMID} = $UUID;
#  $uuid_uvmid{$UUID} = $UVMID;
#}
#
## LPAR2RRD
#for my $alias (keys %{host_hash}){
#  my %subhash = %{$host_hash{$alias}};
#  
#  my ( $protocol, $username, $password, $api_port, $host);
#
#  $protocol = $subhash{proto};
#  $username = $subhash{username};
#  $host     = $subhash{host};
#  $api_port = $subhash{api_port};
#  $password = $subhash{password};
#  
#  my @hmc_console_arr = @{Power_cmc_Power_service::information_call($protocol, $host, $api_port, $username, $password)};
#  
#  my %hmc_console = %hmc_console_arr[0];
#  
#  my $UVMID = $hmc_console{0}{UVMID}{'content'} || "";
#  
#  if (defined $hmc_check{$UVMID}{lpar}){
#    $hmc_check{$UVMID}{lpar} = 1;
#  }
#}
#
#
#my $hmc_message = '';
#my $server_message = '';
#
#my %server_covered;
#
#for my $UUID (keys %{$data{Systems}}){
#  $server_covered{$UUID} = 0;
#}
#
#print Dumper %server_covered;
#for my $UVMID (keys %hmc_check){
#  if ($hmc_check{$UVMID}{lpar} && $hmc_check{$UVMID}{cmc}){
#    my $UUID = $uvmid_uuid{$UVMID};
#    my $hmc_name  = $data{HMCs}{$UUID}{Name};
#    
#    for my $system_UUID (keys %{$data{HMCs}{$UUID}{Systems}}){
#      $server_covered{$UUID} = 1;
#    }
#
#    $hmc_message  .= "HMC $hmc_name Configured <br>";        
#  }
#  elsif (!$hmc_check{$UVMID}{lpar} && $hmc_check{$UVMID}{cmc}){
#    my $UUID = $uvmid_uuid{$UVMID};
#    my $hmc_name  = $data{HMCs}{$UUID}{Name};
#    
#    $hmc_message  .= "HMC $hmc_name NOT Configured <br>";        
#  }
#}
#
## message for uncovered servers
#for my $UUID (keys %server_covered){
#  if (!$server_covered{$UUID}){
#    my $server_name = $data{Systems}{$UUID}{Name};
#    my @hmc_list = ();
#
#    for my $hmc_uuid (keys %{$data{Systems}{$UUID}{HMCs}}){
#
#      my $hmc_name = $data{Systems}{$UUID}{HMCs}{$UUID};
#      push (@hmc_list, $hmc_name);
#
#    }
#
#    $server_message .= "Server not approachable: Server: $server_name UUID: $UUID Managing HMCs: @hmc_list <br>"
#  }
#}
#
#$server_message =~ s/<br>/\\n/g; 
#$hmc_message =~ s/<br>/\\n/g; 
#print "HERE";
#print $hmc_message;
#print $server_message;
exit 0;



