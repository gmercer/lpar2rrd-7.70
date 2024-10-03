package Power_cmc_Power_service;

use strict;
use warnings;

use LWP;
use JSON;
use Data::Dumper;
use FindBin;                
use lib "$FindBin::Bin/"; # use lib in this folder
use lib "../../../perl-modules";

use Power_cmc_Power;
#use Xormon;

use HTTP::Date;
require "xml.pl";

my $hw_type = 'power';

my $power;
my $data = "";
my $cfg; 
# CALL FROM power_cmc.pl 
#       %cfg=(protocol, hmc, port, "", username, password, "hostcfguuId"), @metricNames
# RETURN rank 3 hash: 
#       ( *UUID => *metricName => value )


sub information_call {
  my ($protocol, $host, $api_port, $username, $password) = @_;
  #print "$protocol, $host, $api_port, $username, $password \n";
  
  $power = Power_cmc_Power->new($protocol, $host, $api_port, "", $username, $password, "hostcfguuId");
  #$power = Power->new("https", "vhmc9.int.xorux.com", 12443, "", "lpar2rrd", "ibm4you.", "hostcfguuId");
  #$power = Power->new("https", "10.22.11.79", 12443, "", "lpar2rrd", "ibm4you.", "hostcfguuId");

  my $SessionToken = getSessionToken($power);
  
  my $ret_val = Power_cmc_Power::getHmcs($power);
  
  my $rc_logout = $power->logout($power->{'APISession'});

  return ( $ret_val );
}
sub data_call {
  my ($protocol, $host, $api_port, $username, $password) = @_;
  #print "$protocol, $host, $api_port, $username, $password \n";
  
  $power = Power_cmc_Power->new($protocol, $host, $api_port, "", $username, $password, "hostcfguuId");
  #$power = Power->new("https", "vhmc9.int.xorux.com", 12443, "", "lpar2rrd", "ibm4you.", "hostcfguuId");
  #$power = Power->new("https", "10.22.11.79", 12443, "", "lpar2rrd", "ibm4you.", "hostcfguuId");

  my $SessionToken = getSessionToken($power);
  my ($collect_ref, $collection_timestamped_ref) = collect_server_data($power);

  my %collect = %{$collect_ref};
  my %collection_timestamped = %{$collection_timestamped_ref};

  my $rc_logout = $power->logout($power->{'APISession'});

  #print Dumper %collect;
  #print Dumper %collection_timestamped;

  return ( \%collect, \%collection_timestamped );
}


my $starter = "0"; 
if ($starter) {
  ############################# INIT SECTION ####################################
  
  my $SessionToken = getSessionToken($power);
  
  ############################### AGENT SECTION ###############################

  # get data from technology and save to DB
  print "\n api2json \n";
  my $rc = api2json($cfg, $power);
  
  if ($rc != 201){
     # Xormon::log("API Error : " . "Problem with api2json function");
  }

  ############################### END AGENT SECTION ###############################
  my $servers = $power->getServers();

  # status code
  my $status;
  if ($rc eq "201") {
      $status = "successful";
  } elsif ($rc eq "401") {
      $status = "unauthorized";
  } else {
      $status = "error";
  }


  my $rc_logout = $power->logout($power->{'APISession'});

  my %data = ('SessionToken' => "session_logged_out" );
  print Dumper %data;

  exit();
} 

sub collect_server_data {
  my ($power) = @_;

    my @architecture;
    my @status;
    my %conf_out;
    my %collection;
    my %collection_timestamped;
    my $architecture_lpar_check;
    my %sharedMemoryPools;
    my %sharedProcessorPools;

    #getServers
    #Xormon::log("API       : " . "Get server from $data->{host} ($data->{hostalias})");
    my $servers = $power->getServers();
    my $server_uids;
    for (@{$servers}) {
        my $server = $_;
        my $server_uid = $server->{'Metadata'}{'Atom'}{'AtomID'};
        push @{$server_uids}, $server_uid;
    }
    #add call per server
    ####### PERFORMANCE #######
    my $samples;
    
    my $i = 0;
    
    for my $server_uid (@{$server_uids}){
        #Processed Metrics
        my $processedMetricsServer = $power->getServerProcessed($server_uid);
    
        #print Dumper $processedMetricsServer;
        
        $samples->{$server_uid} = $processedMetricsServer;
    
        for (keys %{ $processedMetricsServer }){
            my $sample_uid = $_;
            my $sample = $processedMetricsServer->{$sample_uid};

            #print Dumper $sample;
            #Xormon::log("API       : " . "Fetch $sample->{'title'}{'content'} of $server_uid");

            #ManagedSystem Performance Data
             
            if ( ref($sample) eq 'HASH' && $sample->{'category'}{'term'} eq "ManagedSystem") {
                #$sample->{'category'}{'frequency'} = '300';
                #Xormon::log("API       : " . "Fetch performance data $sample->{'category'}{'term'} of $server_uid");
                my $dat = $power->ManagedSystemPerformanceToData(
                                        $sample,    $server_uid,              \@architecture, 
                                        \@status,   $architecture_lpar_check, \%sharedMemoryPools, 
                                        \%sharedProcessorPools);
                
                #print "\n COLLECTED DATA --------------------------------------------------------------------------------\n";
                #print Dumper $dat;
                
                my @uuids_server = keys %{$dat->{power}{server}};
                my $uuid_server = $uuids_server[0];
                
                my @timestamps  = keys %{$dat->{power}{server}{$uuid_server}};
                @timestamps = sort @timestamps ;
                  
                #print "TIMESTAMPS SORTED: ";
                #print "@timestamps";
                 
                #print "\n SAMPLE_:::\n";
                #print Dumper $sample;
                my $last_timestamp = $timestamps[-1];
                #print "\n $timestamps[-1] \n";
                # FOR timestamps: sum last 10 values
                my %data_block = %{$dat->{power}{server}{$uuid_server}{$last_timestamp}};
                 
                for my $key (keys  %data_block){
                  my $key_sum = 0;
                  my $current_timestamp = $timestamps[-$i];
                  $key_sum += $dat->{power}{server}{$uuid_server}{$current_timestamp}{$key};
                  #for my $i (1..10){
                  #  my $current_timestamp = $timestamps[-$i];
                  #  $key_sum += $dat->{power}{server}{$uuid_server}{$current_timestamp}{$key};
                  #}
                  $collection{$uuid_server}{$key} = $key_sum;
                }
                for my $timestamp (@timestamps){
                  for my $key (keys  %data_block){
                    my $key_sum = 0;
                    $collection_timestamped{$uuid_server}{$timestamp}{$key} = $dat->{power}{server}{$uuid_server}{$timestamp}{$key};
                  }
                }
                #print Dumper \%data_block;
            }
        }
    }
    
    return (\%collection, \%collection_timestamped ) ;
}

sub api2json {
    my ($data, $power) = @_;
   
    my @architecture;
    my @status;
    my %conf_out;
    my %collection;
    my $architecture_lpar_check;

    #getServers
    #Xormon::log("API       : " . "Get server from $data->{host} ($data->{hostalias})");
    my $servers = $power->getServers();

    print Dumper $servers;

    my $server_uids;
    for (@{$servers}) {
        my $server = $_;
        my $server_uid = $server->{'Metadata'}{'Atom'}{'AtomID'};
        my $server_label = $server->{'SystemName'}{'content'};

        #healt status to db item properties
        $conf_out{$server_uid}{'AggregationEnabled'} = $server->{'AggregationEnabled'}{'content'};
        $conf_out{$server_uid}{'LongTermMonitorEnabled'} = $server->{'LongTermMonitorEnabled'}{'content'};
        $conf_out{$server_uid}{'ShortTermMonitorEnabled'} = $server->{'ShortTermMonitorEnabled'}{'content'};
        $conf_out{$server_uid}{'EnergyMonitorEnabled'} = $server->{'EnergyMonitorEnabled'}{'content'};
        $conf_out{$server_uid}{'EnergyMonitoringCapable'} = $server->{'EnergyMonitoringCapable'}{'content'};
        $conf_out{$server_uid}{'ComputeLTMEnabled'} = $server->{'ComputeLTMEnabled'}{'content'};
    
        push @{$server_uids}, $server_uid;
    }

    ####### PERFORMANCE #######

    #getServersPerformanceData Processed
    my $samples;
    my %sharedMemoryPools;
    my %sharedProcessorPools;
    
    my $i = 0;
    
    for my $server_uid (@{$server_uids}){
        
        #Processed Metrics
        my $processedMetricsServer = $power->getServerProcessed($server_uid);
    
        print Dumper $processedMetricsServer;
        
        $samples->{$server_uid} = $processedMetricsServer;
    
        for (keys %{ $processedMetricsServer }){
            my $sample_uid = $_;
            my $sample = $processedMetricsServer->{$sample_uid};

            #print Dumper $sample;
            #Xormon::log("API       : " . "Fetch $sample->{'title'}{'content'} of $server_uid");

            #ManagedSystem Performance Data
            
            if ($sample->{'category'}{'term'} eq "ManagedSystem") {
                #Xormon::log("API       : " . "Fetch performance data $sample->{'category'}{'term'} of $server_uid");
                my $dat = $power->ManagedSystemPerformanceToData($sample, $server_uid, \@architecture, \@status, $architecture_lpar_check, \%sharedMemoryPools, \%sharedProcessorPools);
                
                print Dumper $dat;
                
                my @uuids_server = keys %{$dat->{power}{server}};
                my $uuid_server = $uuids_server[0];
                
                my @timestamps = keys %{$dat->{power}{server}{$uuid_server}};
                @timestamps = sort @timestamps;
                print "@timestamps";

                my $last_timestamp = $timestamps[-1];
                print "\n $timestamps[-1] \n";
              
                my %data_block = %{$dat->{power}{server}{$uuid_server}{$last_timestamp}};
                

                print Dumper \%data_block;
            }
        }
    }
    return 201;
}


sub getSessionToken {
    my ($power) = @_;
    my $token = 0;

    # Authorize by credentials
    #Xormon::log("API       : " . "Login to HMC");
    my $auth = $power->authCredentials();
    my %data = ('SessionToken' => $auth );
    $power->{'APISession'} = $data{'SessionToken'};
    $token = $power->{'APISession'};
    
    # Return the new API session token
    if ( $token eq "invalid_session_token" ) {
        #Xormon::error("API Error : " . "Login was not successful. Wrong username or password. Also HMC can be unavailable/restarting.");
        exit 0;
    }

    return $token;
}
1;  
