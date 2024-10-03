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

# TODO:
# Preload data, solve undefs, use max time range limit of API
# save result of all requests for development purposes
# maybe module 
my %data_hmc;
my $loc_query;

my $lpar2rrd_dir = $ENV{"INPUTDIR"} || Xorux_lib::error("INPUTDIR is not defined")     && exit;
my $rrdtool = $ENV{RRDTOOL};

# Real data = HTTP requests -> JSON 
# Fake data = JSONs to work with are in bin 
my $real_data = 1;
# Testing file: purpose: minimize error 
my $testing_file = "${lpar2rrd_dir}/bin/inventory_tags.json";
if ( -f "$testing_file") {
  $real_data = 0;
}

# general subroutine to load files
sub file_to_string{
  my $filename = shift;
  my $json;
  print "$filename \n";
  open(FH, '<', $filename) or die $!;
  while(<FH>){
     $json .= $_;
  }
  #print "$filename \n";
  #print Dumper \%{decode_json($json)};
  close(FH);
  return $json;
}



# TODO:
# ENFORCE INTEGRITY: part of metrics is from cmc, part from hmc
#                    if user does not setup hmc user/password.. : what to show?
 

# FOR NOW:  ERROR from CRON -> not using Xorux_lib works
#use Xorux_lib;

# 
# HMC -> CMC
# HMC -> Servers -> Pools

# KEYWORDS: Power Enterprise Pool, Cloud Management Console, Hardware Management Console, 
#           Tag, System, Partition


# Collect information about pool limit: structure:
# pool name -> server -> CPU core limit


#-----------------------------------------------------------------------------------
# CODE STRUCTURE
#-----------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------
# CONNECTION SPECIFICATIONS:
# REQUEST
# TIME HANDLING
#-----------------------------------------------------------------------------------
# INVENTORY TAGS
## Tag is user specified group of VIOSes/Managed Systems/HMCs/Partitions
## Tag creation: https://ibmcmc.zendesk.com/hc/en-us/articles/115001423214-Manage-Tags
## First order specifications: ID, Name, Systems, Partitions

# USAGE POOLS
## Specifications: PoolID, PoolName (per console) + CurrentRemainingCreditBalance
## Metrics: CoreMinute, MemoryMinute, 
##          CoreMeteredMinutes, MemoryMeteredMinutes, 
##          CoreMeteredCredits, MemoryMeteredCredits

# USAGE TAGS
# MANAGED SYSTEMS
#-----------------------------------------------------------------------------------
# SAVE DATA
# READ OR CREATE ENVIRONMENTAL JSON (STRUCTURE: CMC -> POOL_ID -> POOL_NAME)
# SERVER DATA
# RRD CREATE AND UPDATE
#-----------------------------------------------------------------------------------

# $ENV{HTTPS_DEBUG} = 1;

my $SAVER = "";
my $ID;
my $UUID;
#-----------------------------------------------------------------------------------
# CONNECTION SPECIFICATIONS:
#-----------------------------------------------------------------------------------
my $portal_url;
my $CMC_client_id;
my $CMC_client_secret;
my $proxy;

my $console_name;

my $help_string = "";
$help_string .= "ARGUMENTS: \n 1. portal URL \n 2. CMC client ID \n";
$help_string .= " 3. CMC client secret \n 4. (optional)  proxy URL in format: http://host:port \n\n";
    # expected http://host:port

if ($ARGV[0] eq '-h'){
  print $help_string;
  exit;
}


$portal_url        = defined $ARGV[0] ? $ARGV[0] : "";
$CMC_client_id     = defined $ARGV[1] ? $ARGV[1] : "";
$CMC_client_secret = defined $ARGV[2] ? $ARGV[2] : "";
$proxy             = defined $ARGV[3] ? $ARGV[3] : "";
  
$console_name = $portal_url;

if ($proxy eq "-"){
  $proxy = "";
}

#print "PROXY IN power_cmc.pl $proxy";
#warn "PROXY IN power_cmc.pl $proxy";
# ARGV[4] IS USED FOR TESTING
# script.pl test - - proxy test_query
if ($ARGV[0] eq "test"){
  my $testing_query     = defined $ARGV[4] ? $ARGV[4] : "";

  if ($testing_query){
    my $test_result = general_hash_request("GET", $testing_query);
  }else{
    print "Testing query not specified!";
  }
  print "$SAVER";
  exit;
}

if ($portal_url eq ""){
  print "Missing portal url!\n";
  print "$help_string";
  exit;
} elsif ($CMC_client_id eq ""){
  print "Missing cmc client ID!\n";
  print "$help_string";
  exit;
} elsif ($CMC_client_secret eq ""){
  print "Missing CMC client secret as an argument\n";
  print "$help_string";
  exit;
} elsif ($proxy eq ""){
  print "WARNING: Proxy was not specified.\n";
#  print "$help_string";
}

#-----------------------------------------------------------------------------------
# REQUEST
# All API calls are automatically rate limited to a maximum of 10 calls per second.
#-----------------------------------------------------------------------------------
sub general_hash_request {
  my $method = shift;
  my $query = shift; 
  print "$method $query\n"; 
  my $ua    = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH',
                                                 verify_hostname => 0, 
                                                 SSL_verify_mode => 0 } );
  
  # PROXY is global variable
  if ($proxy){
    # expected proxy format: http://host:port
    #print "\n proxy:-${proxy}- \n";
    $ua->proxy( ['http', 'https', 'ftp'] => $proxy );
  }

  my $req = HTTP::Request->new( $method => $query );

  $req->header( 'X-CMC-Client-Id'     => "$CMC_client_id" );
  $req->header( 'X-CMC-Client-Secret' => "$CMC_client_secret" );
  $req->header( 'Accept'              => 'application/json' );
  
  my $res = $ua->request($req);
 
  my %decoded_json;
  
  if ($real_data) {
    eval{
      eval{
        %decoded_json = %{decode_json($res->{'_content'})};
      };
      if($@){
        my $error_message = "";
        $error_message .= "PROBLEM OCCURED during decode_json HASH with url $query!" ;
        $error_message .= "\n --- RESULT->_content --- \n $res->{'_content'} \n";
        print "$error_message";

        error( "$error_message ");

        #Xorux_lib::error($error_message);
        return ()
      }
    };
    if($@){
      print "\n $res->{'_content'} \n";
      error("$res->{'_content'} ");
    }
    return %decoded_json;

  }else{
    # SAVE/PRINT RESULTS
    # This code runs only if fake data are used.
    print "QUERY: $query \n";
    if ($proxy){
      print "PROXY: $proxy \n";
    }
    print "HTTP REQUEST RESULT->_content: \n";
    print "\n";
    print Dumper $res->{'_content'};
    print "\n\n";
    
    return 1; 
  }
}

sub error{
  my $e_message = shift;

  my $error_time = localtime();

  print STDERR "${error_time}: $e_message \n";
}
#-----------------------------------------------------------------------------------
# TIME HANDLING
# OUT: $StartTS, $EndTS
#-----------------------------------------------------------------------------------
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst );
my $use_time = time();
my $time = $use_time;
my $secs_delay = 2600;

my $oldest_timestamp = $use_time - 800000;

my $start_time = $use_time - $secs_delay;
( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($start_time);

my $StartTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, $min );
#print $StartTS;

my $end_time = $use_time;
( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($end_time);

my $EndTS = sprintf( "%4d-%02d-%02dT%02d:%02d:00Z", $year + 1900, $month + 1, $day, $hour, $min );
#print $EndTS;
my $Frequency = "Minute";

sub time2unix{
  # CMC format
  # 2023-04-27T12:00:00.000Z  
  # >> 
  # UNIX format
  # 1682589600
  my $time_string = shift;
  use Time::Local;

  my $unix_time;
  
  if ($time_string =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/){
    $unix_time = timegm(0,$5,$4,$3,$2-1,$1);
  }
  
   #   $unix_time += 864000;
  return $unix_time;
}


sub time_query {
  my $base_url  = shift;
  my $STS       = shift;
  my $ETS       = shift;
  my $freq      = shift;
  
  my $timed_url = "${base_url}?EndTS=${ETS}&Frequency=${freq}&StartTS=${STS}";
  
  return $timed_url;
}

# general directory treatment procedure
sub dir_treat{
  my $dir_path = shift;
  if (! -d "$dir_path") {
    mkdir( "$dir_path", 0755 ) || Xorux_lib::error("Cannot mkdir $dir_path: $!") && exit;
  }
}


sub write_to_file{
  my $file_path = shift;
  my $data_to_write = shift;
  if (! -f "$file_path") {
    qx(touch $file_path);
  }
  open(FH, '>', "$file_path") || Xorux_lib::error( " Can't open: $file_path : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH $data_to_write;
  close(FH);
}


#-----------------------------------------------------------------------------------
# COLLECT CONSOLE DATA
#-----------------------------------------------------------------------------------
my %data;
#---------------------------------------------------------------------------------------------------------
# Console      => Pools       => *PoolID        => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Metrics        => *time => *MetricName  => value
#                                               => Systems        => *UUID => Name         => value
#                                               => Partitions     => *UUID => Name         => value
#
#              => Tags        => *TagID         => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Systems        => *UUID => Name => value
#                                               => Partitions     => *UUID => Name => value
#
#              => Servers     => *ServerUUID    => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Metrics        => *time   => *MetricName  => value
#                                               => Pools          => *PoolID => Name         => value 
#
#              => Partitions  => *PartitionUUID => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Metrics        => *Name => value
#                                               => Pools          => *PoolID 
#
#              => HMCs        => *HMCUUID       => Name           => value
#                                               => Configuration  => *Name => value
#                                               => Systems        => *UUID => Name => value
#                                               => Partitions     => *UUID => Name => value
#---------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------
# :1: INVENTORY TAGS
#-----------------------------------------------------------------------------------
# GET /ep/inventory/tags 
# https://<portal-url>/api/public/v1/ep/inventory/tags/{tag_name}
#-----------------------------------------------------------------------------------
my $pool_name;
my $url_inventory = "https://${portal_url}/api/public/v1/ep/inventory/tags";

# call per pool
sub create_url_inventory_pool {
  my $p_name = shift;
  my $url_inventory_pool = $url_inventory . "/$p_name";
  return $url_inventory_pool;
}

my %inventory_tags;
if ($real_data){
  %inventory_tags = general_hash_request("GET", $url_inventory);
}
else{
  %inventory_tags = %{decode_json(file_to_string("${lpar2rrd_dir}/bin/inventory_tags.json"))};
}

if (defined $inventory_tags{Tags}){

  for (my $i=0; $i<scalar(@{$inventory_tags{Tags}}); $i++){
    # Partitions => [], Systems => []
    my $tag_id = $inventory_tags{Tags}[$i]{ID};
    my $tag_name = $inventory_tags{Tags}[$i]{Name};
    
    $data{Tags}{$tag_id}{Name} = $tag_name;
    
    ## TAGGED PARTITIONS
    #for (my $j=0; $j<scalar(@{$inventory_tags{Tags}[$i]{Partitions}}); $j++){
    #  my %subhash = %{$inventory_tags{Tags}[$i]{Partitions}[$j]};
    #
    #  $UUID                                              = $subhash{UUID};
    #
    #  my $pool_id = $subhash{PoolID};
    #  $data{Pools}{$pool_id}{Name}      = $subhash{PoolName};
    #
    #  $data{Pools}{$pool_id}{Partitions}{$UUID}{Name} = $subhash{Name};
    #  $data{Tags}{$tag_id}{Partitions}{$UUID}{Name}   = $subhash{Name};
    #  $data{Partitions}{$UUID}{Name}                  = $subhash{Name};
    #
    #  $data{Partitions}{$UUID}{Metrics}{proc_available}  = $subhash{ProcessorConfiguration}{AvailableProcessorUnits};
    #  $data{Partitions}{$UUID}{Metrics}{proc_installed}  = $subhash{ProcessorConfiguration}{InstalledProcessorUnits};
    #  $data{Partitions}{$UUID}{Metrics}{mem_available}   = $subhash{MemoryConfiguration}{AvailableMemory};
    #  $data{Partitions}{$UUID}{Metrics}{mem_installed}   = $subhash{MemoryConfiguration}{InstalledMemory};
    # 
    #  $data{Partitions}{$UUID}{Pools}{$pool_id}{Name}    = $subhash{PoolName};
    #  
    #}
    
    # TAGGED SYSTEMS
    if (defined $inventory_tags{Tags}[$i]{Systems} && scalar @{$inventory_tags{Tags}[$i]{Systems}}){
      for (my $j=0; $j<scalar(@{$inventory_tags{Tags}[$i]{Systems}}); $j++){
        my %subhash = %{$inventory_tags{Tags}[$i]{Systems}[$j]};
        #print Dumper %subhash;
        $UUID                                         = $subhash{UUID};
        # ONLY SYSTEMS IN POOL
        # possibly could be ""
        if (defined $subhash{PoolID} && $subhash{PoolID} && $subhash{PoolName}){
          my $pool_id = $subhash{PoolID};
  
          $data{Pools}{$pool_id}{Name} = $subhash{PoolName};
  
          $data{Pools}{$pool_id}{Systems}{$UUID}{Name} = $subhash{Name};
          $data{Systems}{$UUID}{Pools}{$pool_id}{Name} = $subhash{PoolName};
  
          $data{Tags}{$tag_id}{Systems}{$UUID}{Name} = $subhash{Name};
          $data{Systems}{$UUID}{Tags}{$tag_id}{Name} = $tag_name;
  
          $data{Systems}{$UUID}{Name}                = $subhash{Name};
  
          $data{Systems}{$UUID}{Configuration}{proc_available}           = $subhash{ProcessorConfiguration}{AvailableProcessorUnits};
          #$data{Systems}{$UUID}{Configuration}{NumberOfVIOSs}  = $subhash{NumberOfVIOSs};
          $data{Systems}{$UUID}{Configuration}{proc_installed}           = $subhash{ProcessorConfiguration}{InstalledProcessorUnits};
          $data{Systems}{$UUID}{Configuration}{mem_available}            = $subhash{MemoryConfiguration}{AvailableMemory};
          $data{Systems}{$UUID}{Configuration}{mem_installed}            = $subhash{MemoryConfiguration}{InstalledMemory};
  
          $data{Systems}{$UUID}{Configuration}{base_anyoscores}          = $subhash{BaseCores}{BaseAnyOSCores};
          
          $data{Systems}{$UUID}{Configuration}{State}  = $subhash{State};
          #$data{Systems}{$UUID}{Configuration}{NumberOfLPARs}  = $subhash{NumberOfLPARs};
        }
      }
    }
    else{
      $loc_query = $url_inventory;
      error("No tagged systems in tag $tag_name from $loc_query ");
    }

  }
}
else{
  $loc_query = $url_inventory;
  error("No tag data from $loc_query ");
}
#print "SERVER DATA: \n";
#print Dumper \$data{Systems};
#print "TAG DATA: \n";
#print Dumper \$data{Tags};

#-----------------------------------------------------------------------------------
# :2: USAGE POOLS
#-----------------------------------------------------------------------------------
# GET ep/usage/pools 
# https://<portal-url>/api/public/v1/ep/usage/pools/{pool_name}
#   GET POOL NAMES: The available pool names are returned if you do not specify a pool name. 
#-----------------------------------------------------------------------------------
#  QUERY PARAMETERS: 
# StartTS: yyyy-MM-ddTHH:mm:ssZ 
# EndTS: yyyy-MM-ddTHH:mm:ssZ
# Frequency:  Minute  Hourly  Daily  Weekly  Monthly  	
#-----------------------------------------------------------------------------------

my $url_usage_pools = "https://${portal_url}/api/public/v1/ep/usage/pools";
my %data_timed;

# change to something like: append time to query
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

my @tagged_pools = keys %{$data{Pools}};

# From Frequency=Hourly: collect configuration
# From Frequency=Minute: collect performance
if (defined $usage_pools{Pools}){
  
  # NO DATA CATCH
  if (!scalar(@{$usage_pools{Pools}})){
    $loc_query = create_url_usage_pools($url_usage_pools);
    error("No pool data from $loc_query ");
  }
  
  for (my $i=0; $i<scalar(@{$usage_pools{Pools}}); $i++){
    $ID = $usage_pools{Pools}[$i]{PoolID};
    # possibly could be ""
    if ($ID){ 
      $data{Pools}{$ID}{Name} = $usage_pools{Pools}[$i]{PoolName};
      $data_hmc{Pools}{$ID}{Name} = $usage_pools{Pools}[$i]{PoolName};
      $data{Pools}{$ID}{Configuration}{CurrentRemainingCreditBalance} = $usage_pools{Pools}[$i]{CurrentRemainingCreditBalance}; 
    }
  }

}
else{
  $loc_query = create_url_usage_pools($url_usage_pools);
  error("No pool data from $loc_query ");
}

if (defined $usage_pools{Pools}){
  # ERROR CATCH OF USAGE/POOLS IN UPPER CYCLE
  for (my $i=0; $i<scalar(@{$usage_pools{Pools}}); $i++){
    $ID = $usage_pools{Pools}[$i]{PoolID};
    # possibly could be ""
    if ($ID){ 

      if (defined $usage_pools{Pools}[$i]{Usage}{Usage}){

        for (my $j=0; $j<scalar(@{$usage_pools{Pools}[$i]{Usage}{Usage}}); $j++){ 
          my %poolBox = %{$usage_pools{Pools}[$i]{Usage}{Usage}[$j]};

          my $StartTime = $poolBox{StartTime};
          my $unixStartTime = time2unix($StartTime);
          
          # memory minutes
          for my $lpar (keys %{$poolBox{MemoryMinutes}}){
            my $lc_lpar = lc($lpar);
            $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{"mm_$lc_lpar"} = $poolBox{MemoryMinutes}{$lpar};
          }
  
          # core minutes
          for my $lpar (keys %{$poolBox{CoreMinutes}}){
            my $lc_lpar = lc($lpar);
            $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{"cm_$lc_lpar"} = $poolBox{CoreMinutes}{$lpar};
          }

          # core metered minutes
          for my $lpar (keys %{$poolBox{CoreMeteredMinutes}}){
            my $lc_lpar = lc($lpar);
            $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{"cmm_$lc_lpar"} = $poolBox{CoreMeteredMinutes}{$lpar};
          }

          # core metered credits
          for my $lpar (keys %{$poolBox{CoreMeteredCredits}}){
            my $lc_lpar = lc($lpar);
            $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{"cmc_$lc_lpar"} = $poolBox{CoreMeteredCredits}{$lpar};
          }
          $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{mm_minutes} = $poolBox{MemoryMeteredMinutes};
          $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{mm_credits} = $poolBox{MemoryMeteredCredits};
          my @pool_total_credit = (
            'cmc_aix',
            'cmc_ibmi',
            'cmc_rhelcoreos',
            'cmc_rhel',
            'cmc_sles',
            'cmc_linuxvios',
            'mm_credits'
          );
          my $credit_sum = 0;
          my $undef_coutner = 0;
          for my $metric_to_sum (@pool_total_credit){
           # if (defined $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{$metric_to_sum}){
            $credit_sum += $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{$metric_to_sum};
           # }
           # else{
           #   $undef_counter++;
           #   $credit_sum += 0;
           # }
          }
          #if ($undef_counter eq scalar(@pool_total_credit)){
          #  #undef
          #  $credit_sum = $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{cmc_aix};
          #}
          print "$unixStartTime $credit_sum \n";
          $data_timed{Pools}{$ID}{Metrics}{$unixStartTime}{reserve_1} = $credit_sum;
        }
      }
      else{
        $loc_query = create_url_usage_pools($url_usage_pools);
        error("No usage pool data for poolID $ID from $loc_query ");
      }

    }
  }
}
# ERROR CATCH OF USAGE/POOLS IN UPPER CYCLE

# POOL TAGGING INTEGRITY CHECK
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
      my $p_name = $data{Pools}{$some_pool}{Name};
      $tagging_problem = 1;
      push (@untagged_pools, $p_name);
    }
  }
}

if ($tagging_problem){
  print "UNTAGGED POOLS: @untagged_pools";
  error("UNTAGGED POOLS: @untagged_pools ");
}
#print "\n DATA TIMED:";
#print Dumper %data_timed;
#-----------------------------------------------------------------------------------
# :3: USAGE TAGS
#-----------------------------------------------------------------------------------
# GET ep/usage/tags 
# https://<portal-url>/api/public/v1/ep/usage/tags/{tag_name}
#-----------------------------------------------------------------------------------
#  QUERY PARAMETERS: 
# StartTS: yyyy-MM-ddTHH:mm:ssZ 
# EndTS: yyyy-MM-ddTHH:mm:ssZ
# Frequency:  Minute  Hourly  Daily  Weekly  Monthly  	

my $url_usage_tags = "https://${portal_url}/api/public/v1/ep/usage/tags";

# CALL PER TAG
#sub url_usage_tags_tag_specified {
#  my $p_name = shift;
#  my $url .= "/$p_name";
#  return $url;
#}

# same as add time to query
sub create_url_usage_tags {
  my $base_url = shift;
  $base_url .= "?EndTS=${EndTS}&Frequency=${Frequency}&StartTS=${StartTS}";
  return $base_url;
}

my %usage_tags;

if ($real_data){
  %usage_tags = general_hash_request("GET", create_url_usage_tags($url_usage_tags));
}else{
  %usage_tags = %{decode_json(file_to_string("${lpar2rrd_dir}/bin/usage_tags.json"))};
}


if (defined $usage_tags{Tags}){
  if (!scalar(@{$usage_tags{Tags}})){
    $loc_query = create_url_usage_tags($url_usage_tags);
    error( "No tag data from $loc_query ");
  }
  for (my $i=0; $i<scalar(@{$usage_tags{Tags}}); $i++){
    # Partitions => [], Systems => []
    my $tag_id = $usage_tags{Tags}[$i]{ID};
    my $tag_name = $usage_tags{Tags}[$i]{Name};
    
    
    # TAGGED SYSTEMS
    if (defined $usage_tags{Tags}[$i]{SystemsUsage}){
      for (my $j=0; $j<scalar(@{$usage_tags{Tags}[$i]{SystemsUsage}{Systems}}); $j++){
        my %subhash = %{$usage_tags{Tags}[$i]{SystemsUsage}{Systems}[$j]};
          
        $UUID                                         = $subhash{UUID};
        print "DOING: $UUID \n";
        if (defined $data{Systems}{$UUID} && defined $subhash{Usage}{Usage}){
          for (my $k=0; $k<scalar(@{$subhash{Usage}{Usage}}); $k++){ 
            my %system_usage = %{$subhash{Usage}{Usage}[$k]};
            
            my $time_start = $system_usage{StartTime};
            my $timestamp = time2unix($time_start);
   
            $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{utilizedProcUnits} = $system_usage{AverageCoreUsage}{Total};
            $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{proc_installed}    = $data{Systems}{$UUID}{Configuration}{proc_installed};
            $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{base_anyoscores}   = $data{Systems}{$UUID}{Configuration}{base_anyoscores}; 
            $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{mem_available}     = $data{Systems}{$UUID}{Configuration}{mem_available};
            $data_timed{Systems}{$UUID}{Metrics}{$timestamp}{mem_installed}     = $data{Systems}{$UUID}{Configuration}{mem_installed};
          }
        }
      }
    }
  }
}
else{
  $loc_query = create_url_usage_tags($url_usage_tags);
  error( "No tag data from $loc_query ");
}
#-----------------------------------------------------------------------------------
# :4: MANAGED SYSTEM
#-----------------------------------------------------------------------------------
my $url_managed_system = "https://${portal_url}/api/public/v1/inventory/cmc/ManagedSystem";

my %managed_hmc_data;
if ($real_data){
  %managed_hmc_data = general_hash_request("GET", $url_managed_system);
}
else{
  %managed_hmc_data = %{decode_json(file_to_string("${lpar2rrd_dir}/bin/managed_system.json"))};
}

# work with %managed_hmc_data
if (defined $managed_hmc_data{ManagedSystems}){
  for (my $i = 0; $i<scalar(@{$managed_hmc_data{ManagedSystems}}); $i++){
    my %one_server_data = %{$managed_hmc_data{ManagedSystems}[$i]};
    #print Dumper \%one_server_data; 
    $UUID = $one_server_data{UUID};
    #only servers in pools
    if ($data{Systems}{$UUID}){
      $data{Systems}{$UUID}{Name} = $one_server_data{Name};
    
     # # PERFORMANCE FOR RRD
     # $data{Systems}{$UUID}{Metrics}{proc_installed} = $one_server_data{ProcessorConfiguration}{InstalledProcessorUnits};
     # $data{Systems}{$UUID}{Metrics}{proc_available} = $one_server_data{ProcessorConfiguration}{AvailableProcessorUnits};
     # $data{Systems}{$UUID}{Metrics}{mem_installed}  = $one_server_data{MemoryConfiguration}{InstalledMemory};
     # $data{Systems}{$UUID}{Metrics}{mem_available}  = $one_server_data{MemoryConfiguration}{AvailableMemory};
    
      # CONFIGURATION 
      $data{Systems}{$UUID}{Configuration}{proc_installed} = $one_server_data{ProcessorConfiguration}{InstalledProcessorUnits};
      $data{Systems}{$UUID}{Configuration}{proc_available} = $one_server_data{ProcessorConfiguration}{AvailableProcessorUnits};
      $data{Systems}{$UUID}{Configuration}{mem_installed}  = $one_server_data{MemoryConfiguration}{InstalledMemory};
      $data{Systems}{$UUID}{Configuration}{mem_available}  = $one_server_data{MemoryConfiguration}{AvailableMemory};
    
       
      $data{Systems}{$UUID}{Configuration}{State}  = $one_server_data{State};
      $data{Systems}{$UUID}{Configuration}{NumberOfLPARs}  = $one_server_data{NumberOfLPARs};
      $data{Systems}{$UUID}{Configuration}{NumberOfVIOSs}  = $one_server_data{NumberOfVIOSs};
      $data{Systems}{$UUID}{Configuration}{SystemFirmware}  = $one_server_data{SystemFirmware};
      #print "\n XXX: $one_server_data{NumberOfVIOSs}";
      #$data{Systems}{$UUID}{Configuration}{}  = $one_server_data{};
    } 
  }
}
else{
  $loc_query = $url_managed_system;
  error( "No server data from $loc_query ");
}
#print Dumper \%data;
# add configuration to every entry in timed data
for my $pool_id (keys %{$data{Pools}}){
  my @configuration_to_sum = ('proc_available', 'proc_installed', 'mem_available', 'mem_installed', 'base_anyoscores', 'NumberOfLPARs', 'NumberOfVIOSs');

  for my $confitem (@configuration_to_sum){
    #my $checker = 1;
    #for my $UUID (keys %{$data{Pools}{$pool_id}{Systems}}){
    #  if (! defined $data{Systems}{$UUID}{Configuration}{$confitem};
    #}
    
    $data{Pools}{$pool_id}{Configuration}{$confitem} = 0; 
     
    for my $UUID (keys %{$data{Pools}{$pool_id}{Systems}}){
      $data{Pools}{$pool_id}{Configuration}{$confitem}  += $data{Systems}{$UUID}{Configuration}{$confitem};
    }
    for my $UUID (keys %{$data{Pools}{$pool_id}{Systems}}){
      if (! defined $data{Systems}{$UUID}{Configuration}{$confitem}){
        $data{Pools}{$pool_id}{Configuration}{$confitem} = '';
      }
    }
  }
}

#-----------------------------------------------------------------------------------
# :5: MANAGEMENT CONSOLE
#-----------------------------------------------------------------------------------
my $url_management_console = "https://${portal_url}/api/public/v1/inventory/cmc/ManagementConsole";
my %management_console_data;

if ($real_data){
  %managed_hmc_data = general_hash_request("GET", $url_management_console);
}
else{
  %managed_hmc_data = %{decode_json(file_to_string("${lpar2rrd_dir}/bin/management_console.json"))};
}

# get uvmids from cmc

# for hmc get  uvmids from configured hmcs
# $existence_check{$uvmid}


if (defined $managed_hmc_data{HMCs} && scalar(@{$managed_hmc_data{HMCs}})){

  for (my $i = 0; $i<scalar(@{$managed_hmc_data{HMCs}}); $i++){
    my %one_hmc_data = %{$managed_hmc_data{HMCs}[$i]};
  
    my $hmc_uuid = $one_hmc_data{UUID};
  
    $data{HMCs}{$hmc_uuid}{Name} = $managed_hmc_data{HMCs}[$i]{Name};
    $data{HMCs}{$hmc_uuid}{Configuration}{UVMID} = $managed_hmc_data{HMCs}[$i]{UVMID};
     
    for (my $j = 0; $j<scalar(@{$one_hmc_data{ManagedSystems}}); $j++){
      $UUID = $one_hmc_data{ManagedSystems}[$j]{UUID};
      
      if ($data{Systems}{$UUID}){ 
        $data{Systems}{$UUID}{HMCs}{$hmc_uuid} = $one_hmc_data{Name};
        $data{HMCs}{$hmc_uuid}{Systems}{$UUID} = $one_hmc_data{ManagedSystems}[$j]{Name};
      }
    }
  }
}
else{
  $loc_query = $url_management_console;
  error( "No HMC console data from $loc_query ");
}

#-----------------------------------------------------------------------------------
# :6: POWER HMC SERVER DATA
#-----------------------------------------------------------------------------------
# THIS SECTION MUST BE LAST IN COLLECTING ORDER
#-----------------------------------------------------------------------------------
#use Power_cmc_Power_service;
#use HostCfg;
#
#my %host_hash = %{HostCfg::getHostConnections("IBM Power Systems")};
#
#my ( $protocol, $username, $password, $api_port, $host);
#
## Per HMC: collect data from all servers
## hmc_
## per server in cmc: cmc_server matches hmc_server => save
#
#my %uvmid_host;
#my %alias_uvmid;
#
#for my $alias (keys %{host_hash}){
#  my %subhash = %{$host_hash{$alias}};
#
#  $protocol = $subhash{proto};
#  $username = $subhash{username};
#  $host     = $subhash{host};
#  $api_port = $subhash{api_port};
#
#  $password = $subhash{password};
#  print "\n HMC INFORMATION CALL \n";
#  my @hmc_console_arr = @{Power_cmc_Power_service::information_call($protocol, $host, $api_port, $username, $password)};
#  my %hmc_console = %hmc_console_arr[0];
#
#  #print Dumper %hmc_console;
#  #print keys %hmc_console; 
#  my $UVMID = $hmc_console{0}{UVMID}{'content'} || "";
#  $alias_uvmid{$alias}=$UVMID;
#  print "\n------------------------UVMID---------------------------\n$UVMID\n"; 
#}
#
##print Dumper %alias_uvmid;
## what to do about dual hmc?
#for my $hmc_uuid (keys %{$data{HMCs}}){
#  my $UVMID = $data{HMCs}{$hmc_uuid}{Configuration}{UVMID};
#  my $hmc_existence_check = 0;
#  
#  for my $alias (keys %{host_hash}){
#    if (defined ($UVMID) && $alias_uvmid{$alias} eq $UVMID){
#      my %subhash = %{$host_hash{$alias}};
#  
#      $protocol = $subhash{proto};
#      $username = $subhash{username};
#      $host     = $subhash{host};
#      $api_port = $subhash{api_port};
#  
#      $password = $subhash{password};
#  
#      $hmc_existence_check = 1;
#      
#    }
#  }
#  
#  # load data from all servers on HMC
#  if (defined ($UVMID) && $UVMID){
#    # Use HMC connection data and desired metrics list
#    # returns 
#    # %collection: (*UUID => *MetricName => value)
#    print "\n DATA CALL \n";
#    $data{HMCs}{$hmc_uuid}{Configuration}{host} = $host;
#    
#    my ($collection_ref, $collection_timestamped_ref) = Power_cmc_Power_service::data_call($protocol, $host, $api_port, $username, $password);
#    
#    my %collection = %{$collection_ref};
#    my %collection_timestamped = %{$collection_timestamped_ref};
#      
#    #print "\n-------------------------------------------------------------------------\n";
#    #print Dumper %collection;
#    #print "\n-------------------------------------------------------------------------\n";
#    #print Dumper %collection_timestamped;
#    #print "\n-------------------------------------------------------------------------\n";
#    
#    for my $server_uuid (keys %{$data{Systems}}){
#      if (defined $collection{$server_uuid}){
#        for my $MetricName (keys %{$collection{$server_uuid}}){
#          $data{Systems}{$server_uuid}{Metrics}{$MetricName} = $collection{$server_uuid}{$MetricName};
#        }
#      }
#    }
#    
#    for my $server_uuid (keys %{$data{Systems}}){
#      for my $timestamp (keys %{$collection_timestamped{$server_uuid}}){
#        if (defined $collection_timestamped{$server_uuid}{$timestamp}){
#          my @metrics = ('proc_available', 'proc_installed', 'mem_available', 'mem_installed', 'base_anyoscores');
#          for my $metric (@metrics){
#            $data_hmc{Systems}{$server_uuid}{Metrics}{$timestamp}{$metric}  =  $data{Systems}{$server_uuid}{Configuration}{$metric};
#          }
#          for my $MetricName (keys %{$collection_timestamped{$server_uuid}{$timestamp}}){
#            $data_hmc{Systems}{$server_uuid}{Metrics}{$timestamp}{$MetricName} = $collection_timestamped{$server_uuid}{$timestamp}{$MetricName};
#          }
#        }
#      }
#    }
#
#  }
#  else{
#    my $name_of_checked = $data{HMCs}{$hmc_uuid}{Name};
#    print "HMC ${name_of_checked} (UUID: $hmc_uuid) is not in hosts.cfg.";
#  }
#}
#

#-----------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------
# SAVE DATA
#-----------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------
# DIRECTORIES
#-----------------------------------------------------------------------------------
my $datadir = "${lpar2rrd_dir}/data";
my $PEPdir = $datadir . "/PEP2";
my $console_dir = $PEPdir . "/$console_name";
my $consoles_file = $PEPdir . "/console_section_id_name.json";
my $console_history_file = "$console_dir/history.json";

dir_treat($datadir);
dir_treat($PEPdir);
dir_treat($console_dir);

#---------------------------------------------------------------------------------------------------------
# READ OR CREATE ENVIRONMENTAL JSON (STRUCTURE: CMC -> POOL_ID -> POOL_NAME)
#---------------------------------------------------------------------------------------------------------
my %console_id_name;

# add file_treat?
if ( -f "$consoles_file") {
  %console_id_name = %{decode_json(file_to_string("$consoles_file"))};
  delete $console_id_name{$console_name};
}

my %console_history;
if ( -f "$console_history_file") {
  %console_history = %{decode_json(file_to_string("$console_history_file"))};
}

my %rounding_rules = (
  "Systems" => {
    'mem_installed' => 1,
    'mem_available' => 1,
  },
  "Pools" => {
    'mem_installed' => 1,
    'mem_available' => 1,
  }

);
my %multipliers = (
  "Systems" => {
    'mem_installed' => 0.001,
    'mem_available' => 0.001,
  },
  "Pools" => {
    'mem_installed' => 0.001,
    'mem_available' => 0.001,
  }

);

for my $section (keys %rounding_rules){
  for my $id (keys %{$data{$section}}){  
    for my $conf_name (keys %{$multipliers{$section}}){
      my $multiplied_value = $data{$section}{$id}{Configuration}{$conf_name} * $multipliers{$section}{$conf_name};

      my $round_to = $rounding_rules{$section}{$conf_name};

      my $rounded_value = (sprintf "%.${round_to}f",$multiplied_value);

      $data{$section}{$id}{Configuration}{$conf_name} = $rounded_value;
    }
  }
}
# Prepare environmental json
for my $section (sort keys %data){
  # Pools, Tags, Systems, Partitions
  for my $id (keys %{$data{$section}}){
    
    $console_id_name{$console_name}{$section}{$id}{Name} = $data{$section}{$id}{Name};
    
    for my $conf_name (keys %{$data{$section}{$id}{Configuration}}){
      $console_id_name{$console_name}{$section}{$id}{Configuration}{$conf_name} = $data{$section}{$id}{Configuration}{$conf_name};
    }
    
    # ADDITIONAL STRUCTURE - Topology
    for my $group ('Systems', 'Partitions', 'Tags', 'Pools', 'HMCs'){
      if ($section ne $group){
        for my $managed_system (keys %{$data{$section}{$id}{$group}}){
          $console_id_name{$console_name}{$section}{$id}{$group}{$managed_system}=$data{$section}{$id}{$group}{$managed_system}
        }
      }
    }
  }
}

for my $id (keys %{$data{"Pools"}}){
  my @sys_list = keys %{$data{"Pools"}{$id}{Systems}};
  
  # Rename into account
  for my $uuid (@sys_list){
    $console_history{"Pools"}{$id}{Systems}{$uuid} = $data{Systems}{$uuid}{Name};
    $console_history{"Pools"}{$id}{Name} = $data{Pools}{$id}{Name};
  }
}

for my $uuid (keys %{$data{"Systems"}}){
  $console_history{"Systems"}{$uuid} = $data{Systems}{$uuid}{Name};
}
  

# possible sub: hash to json to file
my $json      = JSON->new->utf8->pretty;
my $json_data = $json->encode(\%console_id_name);
write_to_file($consoles_file, $json_data);

my $json_h      = JSON->new->utf8->pretty;
my $json_data_h = $json->encode(\%console_history);
write_to_file($console_history_file, $json_data_h);
#-----------------------------------------------------------------------------------
# METRICS
#-----------------------------------------------------------------------------------
my ( %data_to_save );
%data_to_save = (
#  'Partitions' => [
#    'proc_available', 'proc_installed', 
#    'mem_available', 'mem_installed'
#  ]
);
#
#            "CoreMeteredCredits": {
#              "AIX": 0,
#              "IBMi": 0,
#              "RHELCoreOS": 0,
#              "RHEL": 0,
#              "SLES": 0,
#              "LinuxVIOS": 0,
#              "AnyOS": 0,
#              "Total": 0
#            },
#
#            "CoreMeteredMinutes": {
#              "AIX": 0,
#              "IBMi": 0,
#              "RHELCoreOS": 0,
#              "RHEL": 0,
#              "SLES": 0,
#              "LinuxVIOS": 0,
#              "AnyOS": 0,
#              "Total": 0
#            },
#


my %timestamped_data_to_save = (
  'Pools' => [
    'cm_aix', 'cm_otherlinux',
    'cm_sles', 'cm_vios', 'cm_ibmi',
    'cm_rhel', 'cm_rhelcoreos', 'cm_total',

    'cmc_aix', 'cmc_linuxvios', 'cmc_anyos',
    'cmc_sles', 'cmc_vios', 'cmc_ibmi',
    'cmc_rhel', 'cmc_rhelcoreos', 'cmc_total',
    
    'cmm_aix', 'cmm_linuxvios', 'cmm_anyos',
    'cmm_sles', 'cmm_vios', 'cmm_ibmi',
    'cmm_rhel', 'cmm_rhelcoreos', 'cmm_total',
    
    'mm_aix', 'mm_otherlinux', 
    'mm_sles', 'mm_vios', 'mm_ibmi', 
    'mm_rhel', 'mm_rhelcoreos', 'mm_total',
    
    'mm_systemother',
    'mm_credits', 'mm_minutes',
    
    'reserve_1', 'reserve2',
    'reserve_3', 'reserve4',
    'reserve_5', 'reserve6',
    'reserve_7', 'reserve8',
    'reserve_9', 'reserve10',
     
  ],
  'Systems' => [
    'proc_available', 'proc_installed', 
    'mem_available', 'mem_installed',

    'base_anyoscores',

    'utilizedProcUnits', 'totalProcUnits',
  ]
);
#print Dumper %data_timed;

for my $section (keys %timestamped_data_to_save){
  for $UUID (keys %{$data{$section}}){
    my $rrd_file_name = "${section}_${UUID}.rrd";
    my $rrd = "$console_dir/$rrd_file_name";
    print "$rrd"; 
    my $timestamp  = $oldest_timestamp;

    if (! -f $rrd) {
      rrdCreate($rrd, $timestamp, @{$timestamped_data_to_save{$section}});
    }
  }
}

for my $section (keys %timestamped_data_to_save){
  for $UUID (keys %{$data_timed{$section}}){
    
    my $rrd_file_name = "${section}_${UUID}.rrd";
    my $rrd = "$console_dir/$rrd_file_name";
    my $last_update_time = rrdLast_timestamp($rrd);

    #print Dumper sort keys %{$data_timed{$section}{$UUID}};
    for my $timestamp (sort keys %{$data_timed{$section}{$UUID}{Metrics}}){
      if ($timestamp > $last_update_time){
        my @data_line = ();
        
        for my $metric (@{$timestamped_data_to_save{$section}}){
          if (defined $data_timed{$section}{$UUID}{Metrics}{$timestamp}{$metric}){
            push (@data_line, $data_timed{$section}{$UUID}{Metrics}{$timestamp}{$metric});
          }else{
            push (@data_line, 'U');
          }
        }
        
        #print "\n${section} ${UUID} $rrd \n";   
        
        my $rrd_created_now = 0;
  
        if (! -f $rrd) {
          rrdCreate($rrd, $timestamp, @{$timestamped_data_to_save{$section}});
          $rrd_created_now = 1;
        }
        print "$timestamp @data_line \n"; 
        if ( !  $rrd_created_now){
          #print "\n $timestamp - $last_update_time \n";
          $" = ':';
          #print("@data_line \n");
          my $last_upd_timestamp = rrdUpdate($rrd, $timestamp, "@data_line");
          $" = ' ';
        }
      }
    }
  }
}

for my $section (keys %data_to_save){
  for $UUID (keys %{$data{$section}}){
    my @data_line = ();
    
    for my $metric (@{$data_to_save{$section}}){
      if (defined $data{$section}{$UUID}{Metrics}{$metric}){
        push (@data_line, $data{$section}{$UUID}{Metrics}{$metric});
      }else{
        push (@data_line, 'U');
      }
    }
    
    #print "\n${section} ${UUID} $data{$section}{$UUID}{Name} \n";   
    
    my $rrd_file_name = "${section}_${UUID}.rrd";
     
    my $rrd = "$console_dir/$rrd_file_name";
    my $rrd_created_now = 0;
  
    if (! -f $rrd) {
      rrdCreate($rrd, $time, @{$data_to_save{$section}});
      $rrd_created_now = 1;
    }
    
    if ( !  $rrd_created_now){
      $" = ':';
      #print("@data_line \n");
      my $last_upd_timestamp = rrdUpdate($rrd, $time, "@data_line");
      $" = ' ';
    }
  }
}


#-----------------------------------------------------------------------------------
# RRD CREATE AND UPDATE
#-----------------------------------------------------------------------------------
sub rrdLast_timestamp {
  my $rrd   = shift;
  my $ltime;
  my $last_rec = "";
  my $rrd_read;
  my $rrd_state;

  RRDp::start "$rrdtool";

  eval {
    RRDp::cmd qq(last "$rrd" );
    $last_rec = RRDp::read;
  };
  if ($@) {
    RRDp::end;
    return ( "" );
  }
  #print "$rrd";
  #print "\n last time: ${$last_rec}\n";
  my $last_time = ${$last_rec};
  RRDp::end;
  return ($last_time);
}

sub rrdUpdate {
  my $rrd   = shift;
  my $time  = shift;
  my $stats = shift;
  my $ltime;
  my $last_rec = "";
  my $rrd_read;
  my $rrd_state;
  my $last_time = rrdLast_timestamp($rrd);

  RRDp::start "$rrdtool";

  #if ( Xorux_lib::isdigit($time) && Xorux_lib::isdigit($last_time) && $time > $last_time ) {
  if ( $time > $last_time ) {
    RRDp::cmd qq(update "$rrd" $time:$stats);
    my $answer = RRDp::read;
    RRDp::end;
    return ( $time );
  }

  RRDp::end;
  return ( "" );
}

sub rrdCreate {
  my $rrd     = shift;
  my $time    = shift;
  my @header = @_;

  RRDp::start "$rrdtool";

  my $rrd_time = $time ;
  my $RRD_string;

  my $step    = 60;
  my $prop;
  $prop->{heartbeat}         = 1380;     # says the time interval when RRDTOOL consideres a gap in input data, usually 3 * 5 + 2 = 17mins
  $prop->{first_rra}         = 1;        # 1min
  $prop->{second_rra}        = 60;       # 1h
  $prop->{third_rra}         = 72*5;       # 5 h
  $prop->{forth_rra}         = 288*5;      # 1day
  $prop->{one_min_sample}  = 25920*5;    # 90 days
  $prop->{one_hour_sample}   = 4320*5;     # 180 days
  $prop->{five_hours_sample} = 1734*5;     # 361 days, in fact 6 hours
  $prop->{one_day_sample}    = 1080*5;     # ~ 3 years


  $RRD_string = "create $rrd --start $rrd_time --step $step ";

  for my $variable_name (@header) {
    $RRD_string .= "DS:$variable_name:GAUGE:$prop->{heartbeat}:0:10000000000 ";
  }

  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{first_rra}:$prop->{one_min_sample} ";
  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{second_rra}:$prop->{one_hour_sample} ";
  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{third_rra}:$prop->{five_hours_sample} ";
  $RRD_string .= "RRA:AVERAGE:0.5:$prop->{forth_rra}:$prop->{one_day_sample} ";
  #print ("\n $RRD_string \n");
  print "\n\n$RRD_string";
  RRDp::cmd qq($RRD_string);
  #my $answer = RRDp::read;

#  if ( !Xorux_lib::create_check("file: $rrd, $prop->{five_mins_sample}, $prop->{one_hour_sample}, $prop->{five_hours_sample}, $prop->{one_day_sample}") ) {
#    Xorux_lib::error( "create_rrd err : unable to create $rrd (filesystem is full?) at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    return 1;
  #}
 #RRDp::end;
 #return 0;
}


exit 0;

