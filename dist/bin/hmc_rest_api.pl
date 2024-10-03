print "hmc_rest_api.pl pid:$$\n";
use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;
use JSON qw(decode_json);
use File::Temp;
use File::stat;
use Math::BigInt;
use HTTP::Date;
use POSIX;
use Date::Parse;
use HostCfg;
use PowerDataWrapper;
use File::Copy;
use Xorux_lib;

my $timeout = 1200;
if ( defined $ENV{REST_API_TIMEOUT} && $ENV{REST_API_TIMEOUT} ) { $timeout = $ENV{REST_API_TIMEOUT}; print "Rest API TIMEOUT set to : $timeout\n"; }

my $start_time_id = time;
my ( $sec,  $min,  $hour,  $mday,  $mon,  $year,  $wday,  $yday,  $isdst )  = localtime();
my ( $sec2, $min2, $hour2, $mday2, $mon2, $year2, $wday2, $yday2, $isdst2 ) = gmtime();
my $CURR_TZ = $hour - $hour2;
$CURR_TZ = sprintf( "%01d", $CURR_TZ );
my $debug     = parameter("debug");
my $all       = parameter("all");
my $separator = ";";
$separator = $ENV{CSV_SEPARATOR} if ( $ENV{CSV_SEPARATOR} );

my $days30 = 2592000;

$Data::Dumper::Sortkeys = sub {
  [ reverse sort { $b cmp $a } keys %{ $_[0] } ]
};

my $performance_folder;
my $proto       = "https";
my $host        = "undefined";
my $port        = 12443;
my $arg         = "conf-perf";
my $work_folder = $ENV{INPUTDIR};
my $tmp_folder = "$work_folder/tmp";
my $login_id;
my $login_pwd;
require "$work_folder/bin/xml.pl";

#update power_conf.json
#my $configuration = PowerDataWrapper::get_conf();
#$configuration = PowerDataWrapper::update_conf($configuration);

my ( $SRV, $CNF ) = PowerDataWrapper::init();

if ( defined $ARGV[0] ) { $host = $ARGV[0]; }
if ( defined $ARGV[1] ) { $arg  = $ARGV[1]; }

print "Started hmc_rest_api.pl pid:$$ $host\n";

my $excluded_servers_conf;

my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };

my $hmc_list_size = scalar keys %hosts;

if ( $hmc_list_size > 0 ) {

  #  This will reveal all powers with passwords.
  #  print Dumper \%hosts;
  foreach my $alias ( keys %hosts ) {
    if ( $host eq "undefined" || $host eq $hosts{$alias}{host} ) {
      $port                  = $hosts{$alias}{api_port};
      $login_id              = $hosts{$alias}{username};
      $login_pwd             = $hosts{$alias}{password};
      $host                  = $hosts{$alias}{host};
      $excluded_servers_conf = $hosts{$alias}{exclude};
    }
    elsif ( $host eq "undefined" || ( defined $hosts{$alias}{hmc2} && $host eq $hosts{$alias}{hmc2} ) ) {
      $port                  = $hosts{$alias}{api_port};
      $login_id              = $hosts{$alias}{username};
      $login_pwd             = $hosts{$alias}{password};
      $host                  = $hosts{$alias}{hmc2};
      $excluded_servers_conf = $hosts{$alias}{exclude};
    }
  }
}
else {
  print "Loading HMC LIST configuration from hosts.json was NOT successful, try again after 5 seconds\n";
  sleep 5;
  %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };
  foreach my $alias ( keys %hosts ) {
    if ( $host eq "undefined" || $host eq $hosts{$alias}{host} ) {
      print "HMC !! : $host\n";
      $port                  = $hosts{$alias}{api_port};
      $login_id              = $hosts{$alias}{username};
      $login_pwd             = $hosts{$alias}{password};
      $host                  = $hosts{$alias}{host};
      $excluded_servers_conf = $hosts{$alias}{exclude};
    }
  }
}

my $timeStampFile = "$work_folder/tmp/ts.txt";
my $lastStart     = "$work_folder/tmp/lastStart.txt";
my $lastConfig    = "$work_folder/tmp/lastConfig.txt";

my $dataFolder = "$work_folder/data";
my $webdir     = $ENV{WEBDIR};

#my $SERVERS          = PowerDataWrapper::get_servers();
my $exclude_hmc_port = exclude_hmc_port($host);
print "Rest API       : Exclude HMC Rest API port:$port\n" if $exclude_hmc_port;

if ( defined $ENV{PROXY_RECEIVE} && $ENV{PROXY_RECEIVE} ) {
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create main configuration table\n";
  config_table_main();
  print "PROXY INSTANCE - RECEIVE ($ENV{PROXY_RECEIVE}) - end hmc_rest_api.pl\n";
  exit(0);
}

if ( !defined $login_id || $login_id eq "" ) {
  error("Rest API       : Exiting, not defined (or bad) login_id:\"$login_id\"");
  exit(1);
}
if ( !defined $login_pwd || $login_pwd eq "" ) {
  error("Rest API       : Exiting, not defined (or bad) login_pwd:\"$login_pwd\" for $host");
  exit(1);
}

print "Host Config loaded pid:$$ $host\n";

if ( !( -d "$dataFolder" ) ) {
  mkdir("$dataFolder") or error("Cant create folder $dataFolder") && exit;
}
if ( !( -d "$tmp_folder" ) ) {
  mkdir("$tmp_folder") or error("Cant create folder $tmp_folder") && exit;
}
if ( !( -d "$tmp_folder/restapi" ) ) {
  mkdir("$tmp_folder/restapi") or error("Cant create folder $tmp_folder/restapi") && exit;
}

#if (!(-d "$dataFolder/POWER")){
#  mkdir ("$dataFolder/POWER") or error ("Cant create folder $dataFolder/POWER") && exit;
#}
#if (!(-d "$dataFolder/POWER/vm")){
#  mkdir ("$dataFolder/POWER/vm") or error ("Cant create folder $dataFolder/POWER/vm") && exit;
#}
#if (!(-d "$dataFolder/POWER/pool")){
#  mkdir ("$dataFolder/POWER/pool") or error ("Cant create folder $dataFolder/POWER/pool") && exit;
#}

my $env_dir = $dataFolder;

my $message_if_error = "\nmissing some parameters: <host> <port> <user> <pwd> <inputdir>\n";

if ( !defined $host        || $host eq "" )        { print "host missing\n$message_if_error"; }
if ( !defined $port        || $port eq "" )        { print "port missing $message_if_error"; }
if ( !defined $login_id    || $login_id eq "" )    { print "user missing $message_if_error"; }
if ( !defined $login_pwd   || $login_pwd eq "" )   { print "password missing $message_if_error"; }
if ( !defined $work_folder || $work_folder eq "" ) { print "inputdir $message_if_error\n"; error("errors in parameters"); }

#print "Done testing PowerDataWrapper\n";
#exit;

my $sessionFile = "$tmp_folder/restapi/session_$host\_0_$start_time_id.tmp";    # for HMC
my $APISession  = "";

my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0, SSL_cipher_list => 'DEFAULT:!DH' }, protocols_allowed => [ 'https', 'http' ], keep_alive => 0 );

#my $result = logoff_all();
my $result;
eval {
  $APISession = getSession();
  my $sess_str = $APISession;
  $sess_str =~ s/-//g;
  $sess_str =~ s/_//g;
  $sess_str =~ s/=//g;
  print "Session : $sess_str\n";
};
if ($@) {
  print "Get Session Error : $@\n";
}

my $aix = `uname -a|grep AIX|wc -l`;
chomp($aix);
if ($aix) {
  my $max = `lsattr -El sys0 -a maxuproc`;
  print "AIX Max Processes (lsattr -El sys0 -a maxuproc) : $max\n";
}

sub cut_rest_api_link {
  my $link = shift;
  $link =~ s/^.*rest/rest/g;
  return $link;
}

# ******** M A I N   F U N C T I O N *******#

#my $file_list = downloadPerffilesFromHMC();
#loadDataToRRDFiles($file_list);

my $hmc_info_rest_api = {};
eval { $hmc_info_rest_api = callAPI("rest/api/uom/ManagementConsole"); };
if ($@) {
  print "Rest API error 1111 : $@\n";
  exit(1);
}
my $h       = $hmc_info_rest_api->{entry}{content}{'ManagementConsole:ManagementConsole'};
my @M       = ( "BaseVersion", "BIOS", "ManagementConsoleName" );
my $data_ok = 0;

open( my $version_file, ">", "$tmp_folder/HMC-version-$host-API.txt" ) || error( "Cannot open $tmp_folder/HMC-version-$host-API.txt" . " File: " . __FILE__ . ":" . __LINE__ );
print $version_file $h->{BaseVersion}{'content'} if defined $h->{BaseVersion}{'content'};
close($version_file);
foreach my $m (@M) {
  if ( !defined $h->{$m}{content} ) {
    next;
  }
  else {
    $data_ok++;
    print "$m: $h->{$m}{content}\n";
  }
}

if ( !$data_ok ) {
  error( "Rest API       : Did not get valid data from HMC. Exiting..." . " File: " . __FILE__ . ":" . __LINE__ );
  logoff( $APISession, $sessionFile );
  exit(1);
}

print "Version:\n";
print " Version: $h->{'VersionInfo'}{'Version'}{'content'}\n";
print " Release: $h->{'VersionInfo'}{'Release'}{'content'}\n";
print " BuildLevel: $h->{'VersionInfo'}{'BuildLevel'}{'content'}\n";
print " Maintenance: $h->{'VersionInfo'}{'Maintenance'}{'content'}\n";
print " ServicePackName: $h->{'VersionInfo'}{'ServicePackName'}{'content'}\n";
print " Release: $h->{'VersionInfo'}{'Release'}{'content'}\n";

print "MachineTypeModelAndSerialNumber:\n";
print " MachineType: $h->{'MachineTypeModelAndSerialNumber'}{'MachineType'}{'content'}\n";
print " SerialNumber: $h->{'MachineTypeModelAndSerialNumber'}{'SerialNumber'}{'content'}\n";
print " Model: $h->{'MachineTypeModelAndSerialNumber'}{'Model'}{'content'}\n";

print "ManagementConsoleNetworkInterface:\n";
if ( ref( $h->{'NetworkInterfaces'}{ManagementConsoleNetworkInterface} ) eq "HASH" ) {
  my $item = $h->{'NetworkInterfaces'}{ManagementConsoleNetworkInterface};
  print " InterfaceName: $item->{'InterfaceName'}{'content'}\n";
  print " NetworkAddress: $item->{'NetworkAddress'}{'content'}\n";
}
elsif ( ref( $h->{'NetworkInterfaces'}{ManagementConsoleNetworkInterface} ) eq "ARRAY" ) {
  foreach my $item ( @{ $h->{'NetworkInterfaces'}{ManagementConsoleNetworkInterface} } ) {
    print " InterfaceName: $item->{'InterfaceName'}{'content'}\n";
    print " NetworkAddress: $item->{'NetworkAddress'}{'content'}\n";
  }
}
print "\n";

print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Servers Check\n";
my $SERVERS;
eval { $SERVERS = getServerIDs(); };
#if ($@) {
#  print "Rest API       : Failed to get server IDs $host\n";
#}

if ( !defined $SERVERS || $SERVERS eq "" || ref($SERVERS) ne "HASH" ) {
  error("Rest API       : Exiting, do not see any servers @ $host");
  logoff( $APISession, $sessionFile );
  exit;
}
my $ent_pool_cfg_file = "$work_folder/tmp/restapi/HMC_ENTERPRISE_POOL_conf.json";
my $ent_pool_cfg      = {};
$ent_pool_cfg = Xorux_lib::read_json($ent_pool_cfg_file) if ( -f $ent_pool_cfg_file );
my $ent_pool_html = create_html_enterprise( $ent_pool_cfg, "GB" );
if ( defined $ent_pool_html && is_digit($ent_pool_html) && $ent_pool_html == 1 ) {
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Created Enterprise Pool Config\n";
}

foreach my $key_id ( keys %{$SERVERS} ) {
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $SERVERS->{$key_id}{name} found\n";
}

#print "Debug - 0a\n";
my $lastTimeStamp;

my $DATA;

print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create main configuration table\n";
config_table_main();

#print "Debug - 0b\n";
foreach my $key ( values %{$SERVERS} ) {
  my $folder_to_create = "$env_dir/$key->{name}";
  my $model            = "$key->{MachineType}{'content'}-$key->{'Model'}{'content'}";
  my $serial           = $key->{'SerialNumber'}{'content'};
  my $wrkdir           = $env_dir;
  my $managedname      = $key->{name};

  #  print "Debug - 1:$model 2:$serial 3:$managedname\n";
  if ( !( -d $folder_to_create ) ) {

    #    print "Debug - 2 folder_to_create do not exist, so creating it:$folder_to_create\n";
    # when managed system is renamed then find the original nale per a sym link with model*serial
    #   and rename it in lpar2rrd as well
    if ( -l "$wrkdir/$model*$serial" ) {
      my $link = readlink("$wrkdir/$model*$serial");

      #my $base = basename($link);
      # basename without direct function
      my @link_l = split( /\//, $link );
      my $base   = "";
      foreach my $m (@link_l) {
        $base = $m;
      }

      print "system renamed : $host:$managedname from $base to $managedname, behave as upgrade : $link\n";
      if ( -d "$link" ) {
        print "system renamed : mv $link $wrkdir/$managedname\n";
        rename( "$link", "$wrkdir/$managedname" ) || error( " Cannot mv $link $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      unlink("$wrkdir/$model*$serial") || error( " Cannot rm $wrkdir/$model*$serial: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

      print "LN -S test : symlink( $wrkdir/$managedname, $wrkdir/$model*$serial ) \n";
      symlink( "$wrkdir/$managedname", "$wrkdir/$model*$serial" ) || error( " Cannot ln -s $wrkdir/$managedname $wrkdir/$model*$serial: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }
    else {
      print "mkdir          : $host:$managedname $wrkdir/$managedname\n";
      mkdir( "$wrkdir/$managedname", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

      print "mkdir          : $host:$managedname $wrkdir/$managedname/$host\n";
      mkdir( "$wrkdir/$managedname/$host", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }

    my $adapters    = "adapters";
    my $dir_to_make = "$wrkdir/$managedname/$host/$adapters";
    if ( !-d "$dir_to_make" ) {
      print "mkdir          : $host:$managedname $dir_to_make\n";
      mkdir( "$dir_to_make", 0755 ) || error( " Cannot mkdir $dir_to_make: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }
  }

  # check wherher the symlink is linked to the right targed
  # there could be an issue with symlink prior 3.37 ($managedname dirs could be created from HEA stuff without care about renaming)
  my $managedname_linked = "";
  my $link               = "";
  my $link_expected      = "$wrkdir/$model*$serial";

  #  print "Debug - 3 link_expected:$link_expected\n";
  if ( -l "$link_expected" ) {
    $link = readlink("$link_expected");

    # basename without direct function
    my @link_l             = split( /\//, $link );
    my $managedname_linked = "";
    foreach my $m (@link_l) {
      $managedname_linked = $m;
    }
    if ( $managedname =~ m/^$managedname_linked$/ ) {

      # ok, symlink target is properly linked
    }

  }
  else {
    print "symlink correct: $host:$managedname : $link : $link_expected\n";
    unlink($link_expected);
  }

  $folder_to_create = "$folder_to_create/$host";

  #  print "Debug - 4 folder_to_create_an2 - $folder_to_create\n";
  if ( !( -d $folder_to_create ) ) {
    mkdir("$folder_to_create") || error( "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : cannot create directory $folder_to_create" ) && exit;
  }
  my $folder_to_create_iostat = "$folder_to_create/iostat/";

  #  print "Debug - 5 folder_to_create_an3 - $folder_to_create_iostat\n";
  if ( !( -d $folder_to_create_iostat ) ) {
    mkdir("$folder_to_create_iostat") || error( "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : cannot create directory $folder_to_create_iostat" ) && exit;
  }

  #  print "Debug - 6 work/tmp/name:$work_folder/tmp/$key->{name}\n";
  if ( !( -d "$work_folder/tmp/$key->{name}" ) ) {
    mkdir("$work_folder/tmp/$key->{name}") || error( "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : cannot create directory $work_folder/tmp/$key->{name}" ) && exit;
  }
}

# forking etsting
my @pole;
my $servercount             = 0;
my $index                   = 0;
my $celkem_serveru          = scalar( values %{$SERVERS} );
my $lim                     = 48;
my $restricted_role_applied = 0;
if ( defined $ENV{REST_API_SERVER_LIMIT}   && $ENV{REST_API_SERVER_LIMIT} ne "" )   { $lim                     = $ENV{REST_API_SERVER_LIMIT}; }
if ( defined $ENV{RESTRICTED_ROLE_APPLIED} && $ENV{RESTRICTED_ROLE_APPLIED} ne "" ) { $restricted_role_applied = $ENV{RESTRICTED_ROLE_APPLIED}; }

#print "Debug - 7 servers:$celkem_serveru RestAPIServerLim:$lim\n";

my @excluded_servers;
my $exclude_list = $excluded_servers_conf;
foreach my $server ( @{$exclude_list} ) {
  if ( $server->{exclude_data_fetch} ) {
    push( @excluded_servers, $server->{name} );
  }
}

#print "Debug missing server: xxx\n";
#print Dumper $SERVERS;
#foreach (keys %{$SERVERS}){
#  my $s = $SERVERS->{$_};
#  print "SERVER A\n";
#  print Dumper $s;
#}

foreach my $server ( values %{$SERVERS} ) {
  if ( $index % $lim == 0 ) {
    $servercount++;
  }
  push( @pole, $server );
  $index++;
}

#print "Debug missing server: xxx2\n";
#print Dumper \@pole;

#print "Debug missing server: xxx2 done \n";
#foreach (@pole){
#  print "SERVER B\n";
#  print Dumper $_;
#}

my $right_after_midnight = last_conf_check();

#print "Debug - 8 last_conf_check:$right_after_midnight\n";
my $network_configuration = {};
my $env_config            = {};
my $vscsi_info            = ();

my $env_path = "$work_folder/tmp/restapi/env_conf_$host.json";

my $net_path = "$work_folder/tmp/restapi/net_conf_$host.json";

if ( $arg =~ m/conf/ ) {

  #  print "Debug - 9a env_conf creating\n";
  eval { ( $env_config, $network_configuration ) = environment_configuration(); };
  if ($@) {
    error("Rest API     : Debug Error : $@");
  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : env_conf.json writing\n";

  #  Xorux_lib::write_json($env_path, $env_config) if defined $env_config;
  check_and_write( $env_path, $env_config, 0 );

  #   Xorux_lib::write_json($net_path, $network_configuration) if defined $network_configuration;
  check_and_write( $net_path, $network_configuration, 0 );
}
else {
  $env_config = Xorux_lib::read_json($env_path) if ( -f $env_path );
}

foreach my $file (<$work_folder/data/*\/*\/hmc_touch>) {

  #unlink($file);
}

#$sessionFile = "$work_folder/data/session_$host\_1_$start_time_id.tmp"; # for each server
#$APISession = getSession();

print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create IBMi lpars file in tmp\n";
my $ibmi;
foreach my $key ( keys %{ $CNF->{vms} } ) {
  my $vm = $CNF->{vms}{$key};
  if ( defined $vm->{os_version} && $vm->{os_version} =~ m/^IBM i/ ) {
    push @{$ibmi}, $vm->{label} if ( $vm->{label} ne "" );
  }
}
check_and_write( "$work_folder/tmp/restapi/ibmi_list.json", $ibmi, 0 );

for ( my $sc = 0; $sc < $servercount; $sc++ ) {
  my @array;
  for ( my $i = ( $sc * $lim ); $i < ( $sc * $lim ) + $lim; $i++ ) {
    if ( !defined $pole[$i]->{'id'} ) { next; }
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} processing..\n";
    my $t = open( my $hmc_touch, ">", "$work_folder/data/$pole[$i]->{'name'}/$host/hmc_touch-tmp" ) || error( "Cannot open $work_folder/data/$pole[$i]->{'name'}/$host/hmc_touch-tmp" . " File: " . __FILE__ . ":" . __LINE__ );
    print $hmc_touch time;
    close($hmc_touch);
    copy( "$work_folder/data/$pole[$i]->{'name'}/$host/hmc_touch-tmp", "$work_folder/data/$pole[$i]->{'name'}/$host/hmc_touch" ) || error( "Cannot: cp $work_folder/data/$pole[$i]->{'name'}/$host/hmc_touch-tmp to $work_folder/data/$pole[$i]->{'name'}/$host/hmc_touch: $!" . __FILE__ . ":" . __LINE__ );
    unlink("$work_folder/data/$pole[$i]->{'name'}/$host/hmc_touch-tmp");
    if ( grep( /^$pole[$i]->{'name'}$/, @excluded_servers ) ) {
      print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Excluding $host $pole[$i]->{'name'} from Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "  data fetch\n";
      next;
    }
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} Start\n";
    my $pid = fork;
    push( @array, $pid );
    if ( !defined $pid ) {
      error( "Rest API :       Fork not succesfull : $host $pole[$i]->{'name'} " . __FILE__ . ":" . __LINE__ );
      exit(1);
    }
    if ( $pid == 0 ) {
      setpgrp( 0, 0 );
      print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} PID start : $pid\n";
      print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} Create session\n";

      # PERFORMANCE
      if ( $arg =~ m/perf/ ) {
        eval {
          local $SIG{ALRM} = sub { die "died in SIG ALRM: $arg $pole[$i]->{'name'} $host "; };
          alarm($timeout);



          my $how_old_is_config = 0;

          if ( -e "$env_dir/$pole[$i]->{'name'}/$host/CONFIG.json" ) {
            open( my $fh, "<", "$env_dir/$pole[$i]->{'name'}/$host/CONFIG.json" ) || error( "Cannot read $env_dir/$pole[$i]->{'name'}/$host/CONFIG.json at " . __FILE__ . ":" . __LINE__ ) && return 1;
            my $last_update = stat($fh);
            close($fh);
            my $act_time = time();
            $last_update       = $last_update->[9];
            $how_old_is_config = $act_time - $last_update;
            if ( $how_old_is_config < 3600 ) {
              print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} OK Actual configuration $env_dir/$pole[$i]->{'name'}/$host/CONFIG.json\n";
            }
          }

          #elsif (!(-e "$env_dir/$pole[$i]->{'name'}/$host/CONFIG.json") || $how_old_is_config > 3600){ # if there is not CONFIG.json or old CONFIG.json, create it.
          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} $env_dir/$pole[$i]->{'name'}/$host/CONFIG.json create..\n";

          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} Create config jsons in tmp\n";
          createConfigJsonsTmp( $pole[$i]->{'id'}, "$pole[$i]->{'name'}" );

          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} Create CONFIG.json\n";
          my $cfg_content = createCONFIGjson( $pole[$i]->{'id'}, $pole[$i]->{'name'} );

          #}

          ( $DATA->{jsons}{ $pole[$i]->{'id'} }, $DATA->{vios}{ $pole[$i]->{'id'} } ) = LTMjsons( $pole[$i]->{'id'}, $pole[$i]->{'name'} );
          my $CONFIG      = {};
          my $CONFIG_file = "$env_dir/$pole[$i]->{'name'}/$host/CONFIG.json";
          $CONFIG = Xorux_lib::read_json($CONFIG_file) if ( -f $CONFIG_file );
          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} Finished downloading data rest api $pole[$i]->{'id'}\n";

          $lastTimeStamp = createPerffile( $pole[$i]->{'id'}, $pole[$i]->{'name'}, $CONFIG );
        };
        alarm(0);
        if ($@) {
          print "ERROR : $@\n";
          error( "Rest  API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : eval error performance : $@\n" );
          print "Killing all child processes perf $$\n";
          kill -15, $$;    # clean up
          sleep(3);
        }
      }

      # /PERFORMANCE

      # CONFIG
      if ( $arg =~ m/conf/ ) {

        eval {

          local $SIG{ALRM} = sub { die "died in SIG ALRM: $arg $pole[$i]->{'name'} $host "; };
          alarm($timeout);

          #        print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : $host $pole[$i]->{'name'} Create IBMi lpars file in tmp\n";
          #        my $ibmi;
          #        foreach my $key (keys %{$CNF->{vms}}){
          #          my $vm = $CNF->{vms}{$key};
          #          if (defined $vm->{os_version} && $vm->{os_version} =~ m/^IBM i/){
          #            push @{$ibmi}, $vm->{label} if ($vm->{label} ne "");
          #          }
          #        }
          #        print "DEBUG 2\n";
          #        check_and_write("$work_folder/tmp/restapi/ibmi_list.json", $ibmi, 0);

          # This creates every load_hmc_rest_api.sh run

          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} Create HMC_CONFIG_FILES in tmp, need to create CONFIG.json\n";

          #createConfigJsonsTmp("$pole[$i]->{'id'}", "$pole[$i]->{'name'}");

          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} Create CONFIG.json\n";

          #print "DEBUG 3\n";
          my $cfg_json_content = createCONFIGjson( "$pole[$i]->{'id'}", "$pole[$i]->{'name'}" );

          #print "DEBUG 4\n";

          #This creates html files, cpu-pools-mapping.txt etc once a day, after midnight
          print " *** Creating configuration, once a day ***\n";

          print " *** $pole[$i]->{'id'}\", \"$pole[$i]->{'name'}\", \"$env_dir/$pole[$i]->{'name'}/$host/cpu.cfg\", $cfg_json_content ***\n";

          #print Dumper $cfg_json_content;
          eval {
            print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create $pole[$i]->{'name'}/$host/cpu.cfg \n";
            create_cpu_cfg( "$pole[$i]->{'id'}", "$pole[$i]->{'name'}", "$env_dir/$pole[$i]->{'name'}/$host/cpu.cfg", $cfg_json_content );
          };
          if ($@) {
            print STDERR "DEBUG 4 Error $pole[$i]->{'id'} $pole[$i]->{'name'} $env_dir/$pole[$i]->{'name'}/$host/cpu.cfg : $@\n";
          }

          if ($right_after_midnight) {

            print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} NPIV\n";
            my $preferencesVios = preferencesVios( $pole[$i]->{'id'}, $pole[$i]->{'name'} );

            #Xorux_lib::write_json("$work_folder/tmp/restapi/preferences_vios_$pole[$i]->{'id'}.json", $preferencesVios);

            my $npiv = getServerNPIV( $pole[$i]->{'id'}, $pole[$i]->{'name'}, $preferencesVios );
            #print "NPIV FOR $pole[$i]->{'id'}, $pole[$i]->{'name'}\n";
            #print Dumper $npiv;
            Xorux_lib::write_json( "$work_folder/tmp/restapi/npiv_info_$pole[$i]->{'id'}.json", $npiv ) if defined $npiv;

            print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create $pole[$i]->{'name'}/$host/cpu-pools-mapping.txt. \n";
            create_cpu_pool_mapping( "$pole[$i]->{'id'}", "$pole[$i]->{'name'}", "$env_dir/$pole[$i]->{'name'}/$host/cpu-pools-mapping.txt" );

            print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create config html - new configuration\n";
            create_config_html( "$pole[$i]->{'id'}", "$pole[$i]->{'name'}", $cfg_json_content, $host, $env_config );

            print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create config html cpu\n";
            create_config_cpu_pool_html( "$pole[$i]->{'id'}", "$pole[$i]->{'name'}", $cfg_json_content, "$host", "undef_NaN" );    #CPU Pool

            print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create config html memory\n";
            create_config_memory_html( "$pole[$i]->{'id'}", "$pole[$i]->{'name'}", $cfg_json_content, "$host" );                   #Memory

            my $cpu_pools_mapping;
            if ( -e "$env_dir/$pole[$i]->{'name'}/$host/cpu-pools-mapping.txt" ) {
              open( $cpu_pools_mapping, "<", "$env_dir/$pole[$i]->{'name'}/$host/cpu-pools-mapping.txt" ) || error( "Cannot open $env_dir/$pole[$i]->{'name'}/$host/cpu-pools-mapping.txt" . " File: " . __FILE__ . ":" . __LINE__ );
              my @lines_mapping = <$cpu_pools_mapping>;

              #print STDERR Dumper \@lines_mapping;
              foreach my $mapped_pool (@lines_mapping) {
                ( my $id_pool, my $name_pool ) = split( ",", $mapped_pool );                                                       #Shared Pools that are in cpu-pools-mapping.txt
                print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create config html cpu pool $name_pool";
                create_config_cpu_pool_html( $pole[$i]->{'id'}, $pole[$i]->{'name'}, $cfg_json_content, $host, $id_pool );
              }
              close($cpu_pools_mapping);
            }

            #          unlink("$work_folder/tmp/restapi/last_configuration");
            #          open(my $fh, ">", "$work_folder/tmp/restapi/last_configuration");
            #          close($fh);
          }
          else {
            print "DEBUG 6b - bad!\n";
          }
        };
        alarm(0);
        if ($@) {
          error( "Rest  API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : eval error configuration : $@\n" );
          print "Killing all child processes conf $$\n";
          kill -15, $$;    # clean up
          sleep(3);
        }
      }

      print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $pole[$i]->{'name'} PID end : $pid\n";

      #print "PID end $host $pole[$i]->{'name'} : $pid\n";
      exit(0);
    }
    if ( $i > $celkem_serveru ) {

      last;
    }
  }
  foreach my $pid (@array) {
    waitpid( $pid, 0 );
  }
}

=cut
my @metadata_files = <$work_folder/data/POWER/metadata_*>;
foreach my $metadata_file (@metadata_files){
  print "METADATA FILE : $metadata_file\n";
  (undef, my $host, my $uuid_server) = split("_", $metadata_file);
  ($uuid_server, undef) = split ('\.', $uuid_server);
  print "METADATA FILE : $host $uuid_server\n";
  my $metadata_file_content = Xorux_lib::read_json($metadata_file);
  my $arch_section = $metadata_file_content->{architecture};

  foreach my $vm_uuid (keys %{$arch_section->{vm}}){
    $metadata_out->{architecture}{vm}{$vm_uuid}{pool} = $arch_section->{vm}{$vm_uuid}{pool};
    $metadata_out->{architecture}{vm}{$vm_uuid}{server} = $arch_section->{vm}{$vm_uuid}{server};
  }
  foreach my $pool_uuid (keys %{$arch_section->{pool}}){
    $metadata_out->{architecture}{pool}{$pool_uuid}{pool_id} = $arch_section->{pool}{$pool_uuid}{pool_id};
    $metadata_out->{architecture}{pool}{$pool_uuid}{uuid} = $arch_section->{pool}{$pool_uuid}{uuid};
    $metadata_out->{architecture}{pool}{$pool_uuid}{name} = $arch_section->{pool}{$pool_uuid}{name};
    $metadata_out->{architecture}{pool}{$pool_uuid}{server} = $arch_section->{pool}{$pool_uuid}{server};
  }
}
=cut

if ( $arg =~ m/conf/ ) {

  #create_html_env_config ($env_config, $network_configuration);
  #print "END create_html_env_config ($env_config, $network_configuration)\n";

  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create csv config files\n";
  create_csv_files_configuration($host);

  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : RMC Check\n";
  rmc_check();

  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create main configuration table\n";

  #config_table_main();

  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Create enterprise pool config table\n";
  enterprise_pool_hmc("GB");

  my @vscsi_files = <$work_folder/tmp/restapi/vscsi_info_*.json>;
  my $vscsi_conf  = {};
  foreach my $file (@vscsi_files) {
    ( undef, my $uid ) = split( "vscsi_info_", $file );
    ( $uid, undef ) = split( '\.', $uid );
    $vscsi_conf->{$uid} = Xorux_lib::read_json($file) if ( -f $file );
  }
  check_and_write( "$work_folder/tmp/restapi/vscsi_conf_$host.json", $vscsi_conf, 0 );

  #  Xorux_lib::write_json("$work_folder/tmp/restapi/vscsi_conf_$host.json", $vscsi_conf) if defined $vscsi_conf;

  my @npiv_files = <$work_folder/tmp/restapi/npiv_info_*.json>;
  my $npiv_conf  = {};
  foreach my $file (@npiv_files) {
    ( undef, my $uid ) = split( "npiv_info_", $file );
    ( $uid, undef ) = split( '\.', $uid );
    $npiv_conf->{$uid} = Xorux_lib::read_json($file) if ( -f $file );
  }

  my @env_conf_files = <$work_folder/tmp/restapi/env_conf_*.json>;
  my $env_config_merged;
  foreach my $file (@env_conf_files) {
    ( undef, my $host ) = split( "env_conf_", $file );
    ( $host, undef ) = split( '\.', $host );
    my $env_conf_per_host = {};
    $env_conf_per_host = Xorux_lib::read_json($file) if ( -f $file );
    foreach my $server ( keys %{$env_conf_per_host} ) {
      my $LAN_aliases_file = "$work_folder/data/$server/$host/LAN_aliases.json";
      my $SAN_aliases_file = "$work_folder/data/$server/$host/SAN_aliases.json";
      my $SAS_aliases_file = "$work_folder/data/$server/$host/SAS_aliases.json";
      my $LAN_aliases      = {};
      my $SAN_aliases      = {};
      my $SAS_aliases      = {};
      $LAN_aliases = Xorux_lib::read_json($LAN_aliases_file) if ( -f $LAN_aliases_file );
      $SAN_aliases = Xorux_lib::read_json($SAN_aliases_file) if ( -f $SAN_aliases_file );
      $SAS_aliases = Xorux_lib::read_json($SAS_aliases_file) if ( -f $SAS_aliases_file );
      my $A;
      foreach my $a ( keys %{$LAN_aliases} ) { $A->{$a} = $LAN_aliases->{$a}; }
      foreach my $a ( keys %{$SAN_aliases} ) { $A->{$a} = $SAN_aliases->{$a}; }
      foreach my $a ( keys %{$SAS_aliases} ) { $A->{$a} = $SAS_aliases->{$a}; }
      $env_config_merged->{$server} = $env_conf_per_host->{$server};
    }
  }
  check_and_write( "$work_folder/tmp/restapi/env_conf.json", $env_config_merged, 0 );

  print "write npiv conf : $work_folder/tmp/restapi/npiv_conf.json\n";
  check_and_write( "$work_folder/tmp/restapi/npiv_conf.json", $npiv_conf, 0 );

  print "write vscsi conf : $work_folder/tmp/restapi/vscsi_conf.json\n";
  check_and_write( "$work_folder/tmp/restapi/vscsi_conf.json", $vscsi_conf, 0 );

  if ( -e "$work_folder/load_hmc_rest_api_conf.out" ) {
    copy( "$work_folder/load_hmc_rest_api_conf.out", "$work_folder/logs/load_hmc_rest_api_conf_midnight.out" ) || error( "Cannot: cp $work_folder/logs/load_hmc_rest_api_conf.out to $work_folder/logs/load_hmc_rest_api_conf_midnight.out: $!" . __FILE__ . ":" . __LINE__ );
  }

  `touch $work_folder/tmp/restapi/last_configuration`;
}

$result = logoff_all();

print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Done\n";
print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $result\n";
print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : load_hmc_rest_api.sh exit\n";

#if ($@ || 1) {
#  print "killing proceses - clean up - $$\n";
#  kill -15, $$;    # clean up
#  sleep(3);
#  RRDp::end;       # it must be behind kill as it might hang itself
#  if ( $@ =~ /died in SIG ALRM/ ) {
#   my $act_time = localtime();
#   error( "Rest API Error : hanging processes : $timeout seconds " . __FILE__ . ":" . __LINE__ );
#   exit(1);
#  }
#  else {
#    error( "Rest API Error : hanging processes: $@ " . __FILE__ . ":" . __LINE__ );
#    exit(1);
#  }
#} ## end if ($@)

exit(1);

# *****  E N D   O F   M A I N   F U N C T I O N ********************************************************************************************************************#

sub last_conf_check {
  my $go          = 0;
  my $hh_to_check = "00";
  if ( -e "$work_folder/tmp/restapi/last_configuration" ) {
    open( my $fh, "<", "$work_folder/tmp/restapi/last_configuration" );
    my $last_update = stat($fh);
    close($fh);
    my $act_time = time();
    $last_update = $last_update->[9];
    my $first_date  = strftime( "%F %H:%M:%S", localtime($last_update) );
    my $h           = strftime( "%H",          localtime($act_time) );
    my $second_date = strftime( "%F %H:%M:%S", localtime($act_time) );

    #2019-01-11 15:29:33
    my $diff = $act_time - $last_update;

    #print "$act_time - $last_update = $diff\n";
    #print "$h == $hh_to_check && $diff > 7200\n";
    if ( ( $h eq $hh_to_check && ( $diff > 7200 ) ) || $diff > 86400 ) {
      $go = 1;
      unlink("$work_folder/tmp/restapi/last_configuration");
    }
  }
  else {
    $go = 1;

    #`touch $work_folder/tmp/restapi/last_configuration`;
  }
  return $go;
}

sub logoff_all {

  #return "No logoff, develop debug\n";
  my $s_count   = 0;
  my $s_success = 0;
  my $s_failed  = 0;
  my @files     = (<$work_folder/tmp/restapi/session*$host*>);
  print "Session files\n";
  print Dumper \@files;
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Logging out of sessions from $host\n";

  foreach my $file (@files) {
    print "Logoff sessin : $file, index:$s_count\n";
    $s_count++;
    my $file_created_ago = Xorux_lib::file_time_diff($file);
    if ($file_created_ago <= 1800){
      next;
    }
    open( my $fh, "<", $file ) || error( "Cannot open $file" . " File: " . __FILE__ . ":" . __LINE__ ) && next;
    my $s       = readline($fh);
    my $created = stat($fh);
    $created = $created->[9];
    close($fh);
    my $res = logoff( $s, $file );

    if ( $res->{_rc} == 204 ) {
      print "Logoff OK : $file\n";
      $s_success++;
      unlink($file);    #savely logged out, inserted DELETE request to HMC with actual session and it responded with sucess
    }
    elsif ( $res->{_rc} == 401 ) {    #this should not happen, HMC keeps sessions active for weeks even months, so every session should be logged off after this cycle finishes. It may be some forced closed session from Management Console with root access. If this happens, try to logoff it again a few seconds later to be sure it's not on the server, if not, remove the session file. If any other error, print message to output
      my $res2 = logoff( $s, $file );
      if ( $res2->{_rc} == 204 ) {
        print "Logoff OK : $file\n";
        $s_success++;
        unlink($file);
      }
      else {
        $s_failed++;
        print("Logoff failed : $file : Problem with logoff from HMC, session expired, removing $file because it was logged of from Managment Console probably.\n");
        if ( ( time - $created ) > ( 5 * 60 ) ) {

          unlink($file);
        }
      }
    }
    elsif ( $res->{_rc} == 503 ) {
      print "Logoff HMC probably off or restarting.. Wait a while.\n";
    }
    else {
      print "Logoff Unknow error, check this HMC response:\n";
      $s_failed++;
      print Dumper $res;
    }
  }
  return "Logoff Result: Total:$s_count/Success:$s_success/Fail:$s_failed\n";
}

sub createConfigJsonsTmp {
  my $uid        = shift;
  my $servername = shift;
  my $cfg_epoch;
  my $act_epoch;
  my $CONF_server;
  my $UUID_SERVER;
  my $servers   = PowerDataWrapper::get_servers();
  my $ftd_lpars = Xorux_lib::file_time_diff("$work_folder/tmp/restapi/HMC_LPARS_$servername\_conf.json");

  #  if ( $ftd_lpars && $ftd_lpars < 3 ){
  #    print "Rest API       ". strftime("%F %H:%M:%S", localtime(time)) ."        : Do not create configuration more than every 5 minutes, skip createConfigJsonsTmp : last generated $ftd_lpars seconds ago\n";
  #    return 0;
  #  }
  foreach my $uuid ( keys %{$servers} ) {
    if ( $servers->{$uuid}{REST_UUID} && $servers->{$uuid}{REST_UUID} eq $uid ) {
      $UUID_SERVER = $uuid;
    }
  }
  if ( $uid eq "" ) {
    print "I need server UID to get config and create configuration file\n";
    return;
  }
  ( my $conf, my $asmc, my $aspc, my $buses, my $slots ) = getConfigurationFromServer($uid);
  my $lparConf = getConfigurationFromLpars( $uid, $servername );
  my @wm       = ( "SystemName", "MachineType", "Model", "SerialNumber", "PrimaryIPAddress", "SecondaryIPAddress", "State", "DetailedState", "SystemTime" );
  foreach my $metric ( sort keys %{$conf} ) {
    $CONF_server->{$metric} = $conf->{$metric};
  }
  foreach my $metric ( sort keys %{$asmc} ) {
    $CONF_server->{$metric} = $asmc->{$metric};
  }
  foreach my $metric ( sort keys %{$aspc} ) {
    $CONF_server->{$metric} = $aspc->{$metric};
  }

  #print  "Physical IO per bus\n";
  if ( ref($buses) eq "HASH" ) {
    foreach my $bus_id ( sort keys %{$buses} ) {
      foreach my $metric ( sort keys %{ $buses->{$bus_id} } ) {
        $CONF_server->{physIOPerBuses}{$bus_id}{$metric} = $buses->{$bus_id}{$metric};
      }
    }
  }

  #print "*Physical IO per slot\n";
  if ( ref($slots) eq "HASH" ) {
    foreach my $slot_id ( sort keys %{$slots} ) {
      eval {
        foreach my $metric ( sort keys %{ $slots->{$slot_id} } ) {
          if ( $metric eq "FeatureCodes" ) {
            my $out = "";
            foreach my $item ( @{ $slots->{$slot_id}{$metric} } ) {
              my $fc = $item->{content};
              if ( $out ne "" ) {
                $out = "$out, $fc";
              }
              else {
                $out = "$fc";
              }
            }
            $CONF_server->{physIOPerSlot}{$slot_id}{$metric} = $out;
          }
          else {
            $CONF_server->{physIOPerSlot}{$slot_id}{$metric} = $slots->{$slot_id}{$metric};
          }
        }
      };
      if ($@) { next; }
    }
  }

  #  Xorux_lib::write_json("$work_folder/tmp/restapi/HMC_SERVER_$servername\_conf.json", $CONF_server) if defined $CONF_server;
  check_and_write( "$work_folder/tmp/restapi/HMC_SERVER_$servername\_conf.json", $CONF_server, 0 );
  my $CONF_lpar;
  my $CONF_profiles;
  my $lpar_deep;

  foreach my $lparId ( sort keys %{ $lparConf->{is_lpar} } ) {
    my $lparName = $lparConf->{is_lpar}{$lparId}{'PartitionName'};
    my $Id       = $lparConf->{is_lpar}{$lparId}{'PartitionUUID'};
    if ( !defined $lparName || $lparName eq "" ) { next; }

    my $lpar_deep = {};
    eval {
    $lpar_deep = callAPI("rest/api/uom/ManagedSystem/$uid/LogicalPartition/$lparId");
      if ( ref($lpar_deep) ne "HASH" ) {
        print "Rest API !     " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : No data from $servername ($host) rest/api/uom/ManagedSystem/$uid/LogicalPartition/$lparId\n";
        print Dumper $lpar_deep;
        next;
      }
    };
    if ($@) {
      print "Rest API error 1112 : $@";
    }
    my $lpar_profile = {};
    eval {
      $lpar_profile = callAPI("rest/api/uom/ManagedSystem/$uid/LogicalPartition/$lparId");
    };
    my $associated_lpar_profile_link = $lpar_profile->{'content'}{'LogicalPartition:LogicalPartition'}{'AssociatedPartitionProfile'}{'href'};
    my $asp_content = callAPI($associated_lpar_profile_link);
    if ( defined $lpar_deep->{'content'}{'LogicalPartition:LogicalPartition'} ) {
      $lpar_deep = $lpar_deep->{'content'}{'LogicalPartition:LogicalPartition'};
    }
    else {
      error("API Error at rest/api/uom/ManagedSystem/$uid/LogicalPartition/$lparId") && next;
    }
    my $lparNameHash = $lparName;
    $lparNameHash =~ s/\//\&\&1/g;
    my $UUID_LPAR = PowerDataWrapper::md5_string("$UUID_SERVER $lparNameHash");
    my $pool_url  = "";
    $pool_url = $lpar_deep->{'ProcessorPool'}{'href'} if defined $lpar_deep->{'ProcessorPool'}{'href'};
    my $shp = {};
    if ( defined $pool_url && $pool_url ne "" ) {
      $shp = callAPI($pool_url);
    }
    else {
      #      warn ("Rest API       Not defined URL in ".__FILE__.":".__LINE__."\n");
    }
    $CONF_lpar->{$lparName} = list_config( $lpar_deep, "lpar_conf" );
    if ( ref($shp) eq "HASH" ) {
      $CONF_lpar->{$lparName}{SharedProcessorPoolName} = $shp->{'content'}{'SharedProcessorPool:SharedProcessorPool'}{'PoolName'}{'content'} if defined( $shp->{'content'}{'SharedProcessorPool:SharedProcessorPool'}{'PoolName'}{'content'} );
    }
    $CONF_lpar->{$lparName}{UUID} = $UUID_LPAR;

    #Volume ids for Xormon, tab VOLUMES in lpar's site
    my $lpar_dir_path = PowerDataWrapper::get_filepath_rrd_vm( $lparName, $servername, "" );
    my $id_txt_file   = "$lpar_dir_path/id.txt";
    my $hostname_txt_file   = "$lpar_dir_path/hostname.txt";
    print "ID_TXT LPAR : $id_txt_file\n";
    if ( -e $id_txt_file ) {
      open( my $id_txt, "<", $id_txt_file ) || warn "Cannot open file $id_txt_file at " . __FILE__ . ":" . __LINE__ . "\n";
      my @lines = <$id_txt>;
      close($id_txt);
      my @types  = ();
      my @uuids  = ();
      my @labels = ();
      my @capacities = ();
      foreach my $line (@lines) {
        chomp($line);
        my @arr = split( ":", $line );
        if ( defined $arr[0] && $arr[0] ne '' ) { push( @types,  $arr[0] ); }
        if ( defined $arr[1] && $arr[1] ne '' ) { push( @uuids,  lc $arr[1] ); }
        if ( defined $arr[2] && $arr[2] ne '' ) { push( @labels, $arr[2] ); }
        if ( defined $arr[3] && $arr[3] ne '' ) { push( @capacities, $arr[3] ); }
      }
      $CONF_lpar->{$lparName}{disk_types}  = join( " ", @types );
      $CONF_lpar->{$lparName}{disk_uids}   = join( " ", @uuids );
      $CONF_lpar->{$lparName}{disk_labels} = join( " ", @labels );
      $CONF_lpar->{$lparName}{disk_capacities} = join( " ", @capacities );
    }
    if (-e $hostname_txt_file){
      open( my $hostname_txt, "<", $hostname_txt_file ) || warn "Cannot open file $hostname_txt_file at " . __FILE__ . ":" . __LINE__ . "\n";
      my $hostname = readline($hostname_txt);
      close($hostname_txt);
      $CONF_lpar->{$lparName}{hostname} = $hostname;
    }
    $CONF_lpar->{$lparName}{profile_name} = $asp_content->{'content'}{'LogicalPartitionProfile:LogicalPartitionProfile'}{'ProfileName'}{'content'};
  }
  foreach my $lparId ( sort keys %{ $lparConf->{is_vios} } ) {
    my $lparName = $lparConf->{is_vios}{$lparId}{'PartitionName'};
    eval { $lpar_deep = callAPI("rest/api/uom/ManagedSystem/$uid/VirtualIOServer/$lparId"); };
    if ($@) {
      print "Rest API error 1113 : $@";
      $lpar_deep = {};
    }
    if ( ref($lpar_deep) ne "HASH" ) {
      print "Rest API !     " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : No data from $servername ($host) rest/api/uom/ManagedSystem/$uid/VirtualIOServer/$lparId at " . __FILE__ . ":" . __LINE__ . "\n";
      next;
    }
    if ( defined $lpar_deep->{'content'}{'VirtualIOServer:VirtualIOServer'} ) {
      $lpar_deep = $lpar_deep->{'content'}{'VirtualIOServer:VirtualIOServer'};
    }
    else {
      error("API Error at rest/api/uom/ManagedSystem/$uid/VirtualIOServer/$lparId") && next;
    }


    my $vios_profile = {};
    eval {
      $vios_profile = callAPI("rest/api/uom/ManagedSystem/$uid/VirtualIOServer/$lparId");
    };
    my $associated_vios_profile_link = $vios_profile->{'content'}{'VirtualIOServer:VirtualIOServer'}{'AssociatedPartitionProfile'}{'href'};
    my $asp_content = callAPI($associated_vios_profile_link);

    my $lparNameHash = $lparName;
    $lparNameHash =~ s/\//\&\&1/g;

    my $UUID_LPAR = PowerDataWrapper::md5_string("$UUID_SERVER $lparNameHash");

    #print "Creating UUID : $lparNameHash => $UUID_LPAR\n";

    my $pool_url = "";
    $pool_url = $lpar_deep->{'ProcessorPool'}{'href'};
    my $shp = {};
    if ( defined $pool_url ) {
      $shp = callAPI($pool_url);
    }
    else {
      #      warn ("Rest API       Not defined URL in ".__FILE__.":".__LINE__."\n");
    }
    $CONF_lpar->{$lparName} = list_config( $lpar_deep, "lpar_conf" );
    if ( ref($shp) eq "HASH" ) {
      $CONF_lpar->{$lparName}{SharedProcessorPoolName} = $shp->{'content'}{'SharedProcessorPool:SharedProcessorPool'}{'PoolName'}{'content'} if defined( $shp->{'content'}{'SharedProcessorPool:SharedProcessorPool'}{'PoolName'}{'content'} );
    }

    #print "ADD UUID to conf :$UUID_LPAR for $lparNameHash vs. $lparName\n";
    $CONF_lpar->{$lparName}{UUID} = $UUID_LPAR;

    #Volume ids for Xormon, tab VOLUMES in lpar's site
    my $lpar_dir_path = PowerDataWrapper::get_filepath_rrd_vm( $lparName, $servername, "" );
    my $id_txt_file   = "$lpar_dir_path/id.txt";
    my $hostname_txt_file   = "$lpar_dir_path/hostname.txt";
    print "ID_TXT VIOS : $id_txt_file\n";
    if ( -e $id_txt_file ) {
      open( my $id_txt, "<", $id_txt_file ) || warn "Cannot open file $id_txt_file at " . __FILE__ . ":" . __LINE__ . "\n";
      my @lines = <$id_txt>;
      close($id_txt);
      my @types  = ();
      my @uuids  = ();
      my @labels = ();
      foreach my $line (@lines) {
        chomp($line);
        my @arr = split( ":", $line );
        if ( defined $arr[0] && $arr[0] ne '' ) { push( @types,  $arr[0] ); }
        if ( defined $arr[1] && $arr[1] ne '' ) { push( @uuids,  lc $arr[1] ); }
        if ( defined $arr[2] && $arr[2] ne '' ) { push( @labels, $arr[2] ); }
      }
      $CONF_lpar->{$lparName}{disk_types}  = join( " ", @types );
      $CONF_lpar->{$lparName}{disk_uids}   = join( " ", @uuids );
      $CONF_lpar->{$lparName}{disk_labels} = join( " ", @labels );
    }
    if (-e $hostname_txt_file){
      open( my $hostname_txt, "<", $hostname_txt_file ) || warn "Cannot open file $hostname_txt_file at " . __FILE__ . ":" . __LINE__ . "\n";
      my $hostname = readline($hostname_txt);
      close($hostname_txt);
      $CONF_lpar->{$lparName}{hostname} = $hostname;
    }
    $CONF_lpar->{$lparName}{profile_name} = $asp_content->{'content'}{'LogicalPartitionProfile:LogicalPartitionProfile'}{'ProfileName'}{'content'};
  }
  if ( -e "$work_folder/tmp/restapi/preferences_vios_$uid.json" && Xorux_lib::file_time_diff("$work_folder/tmp/restapi/preferences_vios_$uid.json") <= 3600 ) {
    my $preferences_vios_file = "$work_folder/tmp/restapi/preferences_vios_$uid.json";
    my $preferences_vios      = {};
    $preferences_vios = Xorux_lib::read_json($preferences_vios_file) if ( -f $preferences_vios_file );
    foreach my $vios ( @{$preferences_vios} ) {
      my $lpar_deep_vios = $vios;
      my $lparName       = $lpar_deep_vios->{PartitionName}{content};
      $CONF_lpar->{$lparName} = list_config( $lpar_deep_vios, "lpar_conf" );
    }
  }

  my $sharedPoolsConf = getConfigurationFromSharedPools( $uid, $UUID_SERVER );
  check_and_write( "$work_folder/tmp/restapi/HMC_LPARS_$servername\_conf.json",        $CONF_lpar,       0 );
  check_and_write( "$work_folder/tmp/restapi/HMC_SHP_$servername\_conf.json",          $sharedPoolsConf, 0 );
  check_and_write( "$work_folder/tmp/restapi/HMC_LPARPROFILES_$servername\_conf.json", $CONF_profiles,   0 );

  return 0;
}

sub check_and_write {
  my $file     = shift;
  my $conf     = shift;
  my $req_time = shift;

  if ( !defined $file || $file eq "" ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Check and write skip, not defined \$file\n";
    return 1;
  }
  elsif ( !defined $conf || $conf eq "" ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Check and write skip, not defined \$conf\n";
    return 1;
  }
  elsif ( !defined $req_time || $req_time eq "" ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Check and write skip, not defined \$req_time\n";
    return 1;
  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Check and write .. $file, $conf, $req_time\n";
  if ( $req_time == 0 ) { $req_time = 300; }
  my $ftd = Xorux_lib::file_time_diff($file);
  if ( ( !$ftd || $ftd > $req_time ) && ( defined $file && defined $conf && defined $req_time ) ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Write to file : $file ($ftd)\n";
    Xorux_lib::write_json( $file, $conf ) if ( defined $conf );

    #check_and_write($file, $conf, 0);
    return 0;
  }
  else {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Check and write not successfull $! $file, $req_time, $conf\n";
    return 1;
  }
}

sub getConfigurationFromLpars {
  my $uid         = shift;
  my $servername  = shift;
  my $CONFIG_path = "$work_folder/data/$servername/$host/CONFIG.json";
  my $CONFIG      = {};
  $CONFIG = Xorux_lib::read_json($CONFIG_path) if ( -f $CONFIG_path );
  my $out;
  my $conf_lpar;
  my $interface_info;
  my $physical_volumes_info;
  my $conf_lpars;
  my $vscsi_info = ();
  my $conf;
  my $restricted_lpars = giveMeRestrictedLpars($CONFIG);
  eval { $conf_lpar = callAPI("rest/api/uom/ManagedSystem/$uid/LogicalPartition"); };

  if ($@) {
    print "Rest API error 1114 : $@";
  }
  if ( $conf_lpar ne "-1" && defined $conf_lpar->{'entry'}{'content'} ) {
    my $lp       = $conf_lpar->{'entry'}{'content'}{'LogicalPartition:LogicalPartition'};
    my $Id       = $lp->{PartitionUUID}{content};
    my $lparName = $lp->{'PartitionName'}{'content'};
    my $lparId   = $conf_lpar->{'id'};
    foreach my $metric ( sort keys %{$lp} ) {
      if ( ref( $lp->{$metric} ) eq "HASH" && defined $lp->{$metric}{'content'} ) {
        $out->{is_lpar}{$Id}{$metric} = $lp->{$metric}{'content'};
      }
    }
  }
  elsif ( $conf_lpar ne "-1" && defined $conf_lpar->{'entry'} ) {
    foreach my $lparId ( keys %{ $conf_lpar->{entry} } ) {
      my $lp       = $conf_lpar->{'entry'}{$lparId}{'content'}{'LogicalPartition:LogicalPartition'};
      my $Id       = $lp->{PartitionUUID}{content};
      my $ind      = $lp->{PartitionID}{content};
      my $lparName = $lp->{'PartitionName'}{'content'};
      $conf_lpars->{$ind} = $lp;
      foreach my $metric ( sort keys %{$lp} ) {
        if ( ref( $lp->{$metric} ) eq "HASH" && defined $lp->{$metric}{'content'} ) {
          $out->{is_lpar}{$Id}{$metric} = $lp->{$metric}{'content'};
        }
      }
    }
  }
  else {
    print "Rest API problem lpars\n";
    print Dumper $conf_lpar;
  }
  eval { $conf = callAPI("rest/api/uom/ManagedSystem/$uid/VirtualIOServer"); };
  if ($@) {
    print "Rest API error 1115 : $@";
    print $conf if ( defined $conf && $conf ne "" );
  }
  my @LPs;
  if ( ref($conf) eq "HASH" && defined $conf->{'entry'}{'content'}{'VirtualIOServer:VirtualIOServer'} ) {
    my $lp = $conf->{'entry'}{'content'}{'VirtualIOServer:VirtualIOServer'};
    push( @LPs, $lp );
  }
  elsif ( ref($conf) eq "HASH" ) {
    foreach my $Id ( keys %{ $conf->{entry} } ) {
      if ( $Id eq "content" ) {
        next;
      }
      my $lp = $conf->{'entry'}{$Id}{'content'}{'VirtualIOServer:VirtualIOServer'};
      $lp->{servername} = $servername;
      if ( !( defined $lp ) ) {
        next;
      }
      push( @LPs, $lp );
      my $lparId   = $lp->{PartitionUUID}{content};
      my $lparName = $lp->{'PartitionName'}{'content'};
      if ( $lparId eq "content" ) { next; }
      foreach my $metric ( sort keys %{$lp} ) {
        if ( ref( $lp->{$metric} ) eq "HASH" && defined $lp->{$metric}{'content'} ) {
          $out->{is_vios}{$lparId}{$metric} = $lp->{$metric}{'content'};
        }
      }
    }
  }
  else {
    print "Rest API problem vioses\n";
    print Dumper $conf;
  }

  #check_and_write ("$work_folder/tmp/restapi/allinterface_info_$uid.json", \@LPs, 0 );

  foreach my $lp (@LPs) {
    #  if (ref($conf) eq "HASH" && defined $conf->{'entry'}{'content'}{'VirtualIOServer:VirtualIOServer'}){
    #    my $lp = $conf->{'entry'}{'content'}{'VirtualIOServer:VirtualIOServer'};
    my $lparId   = $lp->{PartitionUUID}{content};
    my $lparName = $lp->{'PartitionName'}{'content'};
    if ( !( $restricted_lpars->{$lparName}{available} ) && ( defined $restricted_lpars->{error_in_loading_lpars} && $restricted_lpars->{error_in_loading_lpars} eq "undefined_lpars" ) ) {
      if ($restricted_role_applied) {
        print "skipping lpar with no permission\n";
        next;
      }
    }
    if ( $lparId eq "content" ) { next; }
    foreach my $metric ( sort keys %{$lp} ) {
      if ( ref( $lp->{$metric} ) eq "HASH" && defined $lp->{$metric}{'content'} ) {
        $out->{is_vios}{$lparId}{$metric} = $lp->{$metric}{'content'};
      }
    }

    my @VSCSIMappings;
    my $VSCSIMappings = force_me_array_ref( $lp->{'VirtualSCSIMappings'} );
    print "VSCSI mapping\n";

    #print Dumper $VSCSIMappings;
    foreach my $item ( @{$VSCSIMappings} ) {
      my $mapping = force_me_array_ref( $item->{VirtualSCSIMapping} );
      foreach my $map ( @{$mapping} ) {
        my $act_map;
        my @server_ad_metrics = ( "AdapterName", "BackingDeviceName", "LocationCode", "UniqueDeviceID", "VirtualSlotNumber", "RemoteSlotNumber" );
        foreach my $sm (@server_ad_metrics) { $act_map->{'ServerAdapter'}{$sm} = $map->{'ServerAdapter'}{$sm}{'content'} if ( defined $map->{'ServerAdapter'}{$sm}{'content'} ); }

        my @client_ad_metrics = ( "ServerLocationCode", "LocationCode", "VirtualSlotNumber", "RemoteSlotNumber", "LocalPartitionID", "RemoteLogicalPartitionID", "RequiredAdapter" );
        foreach my $cm (@client_ad_metrics) { $act_map->{'ClientAdapter'}{$cm} = $map->{'ClientAdapter'}{$cm}{'content'} if ( defined $map->{'ClientAdapter'}{$cm}{'content'} ); }

        my @storage_metrics = ( "PartitionSize", "DiskCapacity", "DiskName", "DiskLabel" );
        foreach my $sm (@storage_metrics) { $act_map->{'Storage'}{'VirtualDisk'}{$sm} = $map->{'Storage'}{'VirtualDisk'}{$sm}{'content'} if ( defined $map->{'Storage'}{'VirtualDisk'}{$sm}{'content'} ); }

        my @physical_volume_metrics = ( "LocationCode", "PersistentReserveKeyValue", "ReservePolicy", "ReservePolicyAlgorithm", "UniqueDeviceID", "AvailableForUsage", "VolumeCapacity", "VolumeName", "VolumeState", "VolumeUniqueID", "IsFibreChannelBacked", "StorageLabel", "DescriptorPage83" );
        foreach my $pm (@physical_volume_metrics) { $act_map->{'Storage'}{'PhysicalVolume'}{$pm} = $map->{'Storage'}{'PhysicalVolume'}{$pm}{'content'} if ( defined $map->{'Storage'}{'PhysicalVolume'}{$pm}{'content'} ); }

        $act_map->{ServerAdapter}{RemoteLogicalPartitionName} = $lparName;
        $act_map->{ServerAdapter}{SystemName}                 = $servername;
        my $partitionname = "";
        $partitionname = $conf_lpars->{ $act_map->{'ClientAdapter'}{'LocalPartitionID'} }{PartitionName}{content} if defined $act_map->{'ClientAdapter'}{'LocalPartitionID'};
        $act_map->{'Partition'} = $partitionname;
        push( @{$vscsi_info}, $act_map );
      }
    }
    my $FreeAgg = force_me_array_ref( $lp->{'FreeIOAdaptersForLinkAggregation'}{'IOAdapterChoice'} );
    foreach my $adapter ( @{$FreeAgg} ) {
      $adapter = $adapter->{'IOAdapter'};
      my $phys_loc = $adapter->{'PhysicalLocation'}{'content'};
      $interface_info->{$phys_loc}{'DeviceName'}  = $adapter->{'DeviceName'}{'content'};
      $interface_info->{$phys_loc}{'Description'} = $adapter->{'Description'}{'content'} if !defined $interface_info->{$phys_loc}{'Description'};
      $interface_info->{$phys_loc}{'AdapterID'}   = $adapter->{'AdapterID'}{'content'};
    }
    my $FreeSEA = force_me_array_ref( $lp->{'FreeEthenetBackingDevicesForSEA'}{'IOAdapterChoice'} );
    foreach my $adapter ( @{$FreeSEA} ) {
      $adapter = $adapter->{'EthernetBackingDevice'};
      my ( $PhysicalLocation, $DeviceName, $Description, $InterfaceName, $State ) = ( "", "", "", "", "" );
      $PhysicalLocation = $adapter->{'PhysicalLocation'}{'content'}             if defined $adapter->{'PhysicalLocation'}{'content'};
      $DeviceName       = $adapter->{'DeviceName'}{'content'}                   if defined $adapter->{'DeviceName'}{'content'};                      # ent1
      $Description      = $adapter->{'Description'}{'content'}                  if defined $adapter->{'Description'}{'content'};                     #4 port ...
      $InterfaceName    = $adapter->{'IPInterface'}{'InterfaceName'}{'content'} if defined $adapter->{'IPInterface'}{'InterfaceName'}{'content'};    # en1
      $State            = $adapter->{'IPInterface'}{'State'}{'content'}         if defined $adapter->{'IPInterface'}{'State'}{'content'};            #active
      $interface_info->{$PhysicalLocation}{'DeviceName'}    = $DeviceName;
      $interface_info->{$PhysicalLocation}{'Description'}   = $Description if !defined $interface_info->{$PhysicalLocation}{'Description'};
      $interface_info->{$PhysicalLocation}{'InterfaceName'} = $InterfaceName;
      $interface_info->{$PhysicalLocation}{'State'}         = $State;
    }
    my $SharedEthAdapters = force_me_array_ref( $lp->{'SharedEthernetAdapters'}{'SharedEthernetAdapter'} );
    my @SEA;
    foreach my $a ( @{$SharedEthAdapters} ) {
      if ( ref($a) eq "HASH" ) {
        push( @SEA, $a );
      }
      elsif ( ref($a) eq "ARRAY" ) {
        @SEA = @{$a};
      }
      foreach my $adapter (@SEA) {
        my $PhysicalLocation = "";
        my $DeviceName       = "";
        my $InterfaceName    = "";
        my $State            = "";
        my $IPAdress         = "";
        $PhysicalLocation = $adapter->{'BackingDeviceChoice'}{'EthernetBackingDevice'}{'PhysicalLocation'}{'content'} if defined $adapter->{'BackingDeviceChoice'}{'EthernetBackingDevice'}{'PhysicalLocation'}{'content'};
        $DeviceName       = $adapter->{'DeviceName'}{'content'}                                                       if defined $adapter->{'DeviceName'}{'content'};
        $InterfaceName    = $adapter->{'IPInterface'}{'InterfaceName'}{'content'}                                     if defined $adapter->{'IPInterface'}{'InterfaceName'}{'content'};                                       # en1
        $State            = $adapter->{'IPInterface'}{'State'}{'content'}                                             if defined $adapter->{'IPInterface'}{'State'}{'content'};                                               #active
        $IPAdress         = $adapter->{'IPInterface'}{'IPAdress'}{'content'}                                          if defined $adapter->{'IPInterface'}{'IPAdress'}{'content'};
        $interface_info->{$PhysicalLocation}{'DeviceName'}    = $DeviceName;
        $interface_info->{$PhysicalLocation}{'InterfaceName'} = $InterfaceName;
        $interface_info->{$PhysicalLocation}{'State'}         = $State;
        $interface_info->{$PhysicalLocation}{'IPAdress'}      = $IPAdress;
      }
    }

    #  }
  }

  #  elsif (ref($conf) eq "HASH"){
  #    foreach my $Id (keys %{$conf->{entry}}){
  #      if ($Id eq "content"){
  #        next;
  #      }
  #      my $lp = $conf->{'entry'}{$Id}{'content'}{'VirtualIOServer:VirtualIOServer'};
  #      if (!(defined $lp)){
  #        next;
  #      }
  #      my $lparId = $lp->{PartitionUUID}{content};
  #      if ($lparId eq "content"){next;}
  #      foreach my $metric (sort keys %{$lp}){
  #        if (ref($lp->{$metric}) eq "HASH" && defined $lp->{$metric}{'content'}){
  #          $out->{is_vios}{$lparId}{$metric} = $lp->{$metric}{'content'};
  #        }
  #      }
  #    }
  #  }
  #  Xorux_lib::write_json("$work_folder/tmp/restapi/interface_info_$uid.json", $interface_info) if defined $interface_info;
  #  Xorux_lib::write_json("$work_folder/tmp/restapi/vscsi_info_$uid.json", $vscsi_info) if defined $vscsi_info;
  check_and_write( "$work_folder/tmp/restapi/vscsi_info_$uid.json",     $vscsi_info,     0 );
  if ( ref($out) ne "HASH" ) { $out = {}; }
  return $out;
}

sub printConfigurationContentIfAvailable {
  my $hash     = shift;
  my $confHash = shift;
  if ( !defined $hash || ref($hash) ne "HASH" ) {
    print "printConfigurtaionContentIfAvailable expects first argumets a hash\n";
    return $confHash;
  }
  my @metrics = keys %{$hash};
  foreach my $metric ( sort @metrics ) {
    if ( ref( $hash->{$metric} ) eq "HASH" && defined $hash->{$metric}{content} ) {
      $confHash->{$metric} = $hash->{$metric}{content};
    }
    else {
      next;
    }
  }
  return $confHash;
}

sub getConfigurationFromSharedPools {
  my $uid         = shift;
  my $UUID_SERVER = shift;
  my $conf;
  my $out = {};
  eval {
    $conf = callAPI("rest/api/uom/ManagedSystem/$uid/SharedProcessorPool");
    if ( ref($conf) ne "HASH" && $conf eq "-1" ) {
      return $out;
    }
  };
  if ($@) {
    print "Rest API error 1116 : $@";
  }
  if ( ref($conf) eq "HASH" ) {
    foreach my $poolId ( keys %{ $conf->{'entry'} } ) {
      if ( ref( $conf->{'entry'}{$poolId}{'content'}{'SharedProcessorPool:SharedProcessorPool'} ) ne "HASH" ) {
        next;
      }
      my $shp      = $conf->{'entry'}{$poolId}{'content'}{'SharedProcessorPool:SharedProcessorPool'};
      my $poolName = $shp->{'PoolName'}{'content'};
      my $Id       = $shp->{'PoolID'}{'content'};
      if ( $poolName =~ m/SharedPool[0-9]*/ && !( $shp->{'CurrentReservedProcessingUnits'}{'content'} || $shp->{'AvailableProcUnits'}{'content'} || $shp->{'MaximumProcessingUnits'}{'content'} || $shp->{'PendingReservedProcessingUnits'}{'content'} ) ) {
        next;
      }
      foreach my $metric ( keys %{$shp} ) {
        if ( ref( $shp->{$metric} ) eq "HASH" && defined $shp->{$metric}{'content'} ) {
          $out->{$poolId}{$metric} = $shp->{$metric}{'content'};
        }
      }
      $out->{$poolId}{UUID} = PowerDataWrapper::md5_string("$UUID_SERVER $Id");
    }
  }
  return $out;
}

sub getConfigurationFromServer {
  my $uid = shift;

  #SYSTEM OVERVIEW
  my $confHash = {};
  my $config;
  eval {
    $config = callAPI("rest/api/uom/ManagedSystem/$uid");
    if ( ref($config) eq "HASH" ) {
      $config = $config->{'content'}{'ManagedSystem:ManagedSystem'};
    }
    elsif ( ref($config) ne "HASH" && $config eq "-1" ) {
      return $confHash;
    }
  };
  if ($@) {
    print "Rest API error 1117 : $@";
  }
  my $CONF_server = list_config( $config, "server" );
  if ( !defined $config ) {
    print "Cannot get system configuration, somethings wrong. URL: $proto://$host/rest/api/uom/ManagedSystem/$uid/";
    return {};
  }
  $confHash = printConfigurationContentIfAvailable( $config->{'AssociatedIPLConfiguration'},      $confHash );
  $confHash = printConfigurationContentIfAvailable( $config->{'AssociatedSystemCapabilities'},    $confHash );
  $confHash = printConfigurationContentIfAvailable( $config->{'EnergyManagementConfiguration'},   $confHash );
  $confHash = printConfigurationContentIfAvailable( $config->{'MachineTypeModelAndSerialNumber'}, $confHash );
  $confHash = printConfigurationContentIfAvailable( $config->{'AssociatedSystemIOConfiguration'}, $confHash );
  my $string = "";
  foreach my $value ( @{ $config->{'AssociatedSystemProcessorConfiguration'}{'SupportedPartitionProcessorCompatibilityModes'} } ) {
    if ( $string eq "" ) {
      $string = $value->{'content'};
    }
    else {
      $string = "$string,$value->{'content'}";
    }
  }
  $confHash->{'SupportedPartitionProcessorCompatibilityModes'} = $string;
  $string                                                      = "";
  $confHash                                                    = printConfigurationContentIfAvailable( $config, $confHash );
  my $asmc;
  $asmc = printConfigurationContentIfAvailable( $config->{'AssociatedSystemMemoryConfiguration'}, $asmc );
  my $aspc;
  $aspc = printConfigurationContentIfAvailable( $config->{'AssociatedSystemProcessorConfiguration'}, $aspc );

  my $adapters = $config->{'AssociatedSystemIOConfiguration'}{'IOAdapters'}{'IOAdapterChoice'};
  my $ioac;
  foreach my $adapter ( @{$adapters} ) {
    my $a          = $adapter->{'IOAdapter'};
    my $deviceName = $a->{'DeviceName'}{'content'};
    foreach my $metric ( keys %{$a} ) {
      if ( ref( $a->{$metric} ) eq "HASH" && defined $a->{$metric}{content} ) {
        $ioac->{$deviceName}{$metric} = $a->{$metric}{content};
      }
    }
  }
  my $iobuses = $config->{'AssociatedSystemIOConfiguration'}{'IOBuses'}{'IOBus'};
  my $buses;
  my $slots;
  foreach my $bus ( @{$iobuses} ) {
    $buses->{ $bus->{IOBusID}{content} }{BusDynamicReconfigurationConnectorIndex} = $bus->{BusDynamicReconfigurationConnectorIndex}{content};
    $buses->{ $bus->{IOBusID}{content} }{BusDynamicReconfigurationConnectorName}  = $bus->{BusDynamicReconfigurationConnectorName}{content};
    $buses->{ $bus->{IOBusID}{content} }{BackplanePhysicalLocation}               = $bus->{BackplanePhysicalLocation}{content};
    printConfigurationContentIfAvailable( $bus->{'IOSlots'}{'IOSlot'}, $slots );
    $slots->{ $bus->{'IOBusID'}{'content'} }{IOBusID} = $bus->{'IOBusID'}{'content'};

    #$slots->{$bus->{'IOBusID'}{'content'}}{'FeatureCodes'} = $bus->{'IOSlots'}{'IOSlot'}{'FeatureCodes'};
  }
  if ( !defined $confHash || $confHash eq "" || $confHash eq "-1" ) { $confHash = {}; }
  if ( !defined $asmc     || $asmc eq ""     || $asmc eq "-1" )     { $asmc     = {}; }
  if ( !defined $aspc     || $aspc eq ""     || $aspc eq "-1" )     { $aspc     = {}; }
  if ( !defined $buses    || $buses eq ""    || $buses eq "-1" )    { $buses    = {}; }
  if ( !defined $slots    || $slots eq ""    || $slots eq "-1" )    { $slots    = {}; }
  return ( $confHash, $asmc, $aspc, $buses, $slots );
}

sub logoff {
  my $session          = shift;
  my $file             = shift;
  my $tmp_session_file = $file;
  my ( undef, $sf_host, $sf_id, $sf_time ) = split( "_", $tmp_session_file );
  $sf_time =~ s/\..*//g;
  $sf_time = strftime( "%F %H:%M:%S", localtime($sf_time) );
  my $url = $proto . '://' . $host . ':' . $port . '/rest/api/web/Logon';
  my $req = HTTP::Request->new( DELETE => $url );
  $req->header( 'X-API-Session' => $session );
  my $data = $browser->request($req);

  if ( $data->is_success ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host logoff $sf_id created:$sf_time\n";
  }
  else {
    #warn ("Logoff not succesful $tmp_session_file, URL:$url, data: $data->{_content}\n");
  }
  return $data;
}

# this function gets the last timestamp that have been processed or create one.
sub getPreviousTimeStamp {
  my $previous_ts;
  if ( -e $timeStampFile ) {
    open( my $ts, "<", $timeStampFile ) or error( "Cannot open $timeStampFile" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
    $previous_ts = readline($ts);
    close($ts);
  }
  else {
    $previous_ts = "0000-00-00T00:00:00+0000";
  }
  return $previous_ts;
}

#find servers
sub getServerIDs {
  my $ids;
  my $url = 'rest/api/pcm/preferences';
  my $servers;
  eval { $servers = callAPI($url); };
  if ($@) {
    print "Rest API error 1118 : $@";
  }
  if ( ref($servers) ne "HASH" ) {
    error( "No data for $host : $url. " . " File: " . __FILE__ . ":" . __LINE__ );
    return -1;
  }
  my $hmc_time = $servers->{entry}{published};
  my $hmc_time_epoch = str2time($hmc_time);

  if ( !defined $hmc_time || $hmc_time eq "" ) {
    error( "Not defined HMC Time for $host. " . __FILE__ . ":" . __LINE__ );
    $hmc_time = 0;
  }
  $hmc_time =~ s/\.[0-9][0-9][0-9]\+/+/g;
  $hmc_time =~ s/T/ /g;
  ( $hmc_time, undef ) = split( '\.', $hmc_time );
  my $tz             = substr( $hmc_time, 19, 3 );


  #$hmc_time_epoch += (-$tz*3600);
  my $hmc_time_for = strftime( "%F %H:%M:%S", localtime($hmc_time_epoch) );

  my $act_time_epoch = time;
  my $act_time_for   = strftime( "%F %H:%M:%S", localtime($act_time_epoch) );

  my $hmc_time_gap = $hmc_time_epoch - $act_time_epoch;

  if ( $hmc_time_gap >= 3500 || $hmc_time_gap <= -3500 ) {
    error( "TIME Error ($hmc_time_gap different) : $act_time_for($act_time_epoch), hmc_time:$hmc_time_for($hmc_time_epoch). Correct the timezone on your HMC ($host) and restart HMC. " . " File: " . __FILE__ . ":" . __LINE__ );
  }

  print "HMC Time       $hmc_time\n";
  if ( defined $servers->{error} ) {
    print "Error in function \"getServerIDs\" - Cannot get preferences data from hmc: $proto" . "://" . $host . "/" . $url;
    print Dumper $servers->{error};
    return -1;
  }
  my $out;
  my $i = 0;
  my $name;
  if ( !defined $servers->{entry} ) { print "Expected different response\n"; return; }
  $servers = $servers->{entry}{content}{'ManagementConsolePcmPreference:ManagementConsolePcmPreference'}{ManagedSystemPcmPreference};
  my @servers_arr;
  if ( ref($servers) eq "HASH" ) {
    push( @servers_arr, $servers );

    #$out->{$i}{id} = $servers->{Metadata}{Atom}{AtomID};
    #$out->{$i}{hmc_time} = $hmc_time;
    #$out->{$i}{name} = $servers->{SystemName}{content};
    #$out->{$i}{MachineType}  = $servers->{MachineTypeModelSerialNumber}{MachineType};
    #$out->{$i}{Model}  = $servers->{MachineTypeModelSerialNumber}{Model};
    #$out->{$i}{SerialNumber}  = $servers->{MachineTypeModelSerialNumber}{SerialNumber};
  }
  elsif ( ref($servers) eq "ARRAY" ) {
    @servers_arr = @{$servers};
  }
  else {
    error( "Expected hash or array, got" . ref($servers) );
  }
  foreach my $hash (@servers_arr) {

    if ( !defined $hash->{MachineTypeModelSerialNumber}{MachineType}{content} || !defined $hash->{MachineTypeModelSerialNumber}{Model}{content} ) {
      next;
    }

    my $uid = $hash->{Metadata}{Atom}{AtomID};
    $out->{$i}{id}                    = $uid;
    $out->{$i}{hmc_time}              = $hmc_time;
    $out->{$i}{name}                  = $hash->{SystemName}{content};
    $out->{$i}{MachineType}{content}  = $hash->{MachineTypeModelSerialNumber}{MachineType}{content};
    $out->{$i}{Model}{content}        = $hash->{MachineTypeModelSerialNumber}{Model}{content};
    $out->{$i}{SerialNumber}{content} = $hash->{MachineTypeModelSerialNumber}{SerialNumber}{content};
    $out->{$i}{UUID}                  = PowerDataWrapper::md5_string("$hash->{MachineTypeModelSerialNumber}{SerialNumber}{content} $hash->{MachineTypeModelSerialNumber}{MachineType}{content}-$hash->{MachineTypeModelSerialNumber}{Model}{content}");
    $i++;
  }

  #Xorux_lib::write_json("$work_folder/tmp/restapi/HMC_INFO_$host.json", $out) if defined $out;
  #Xorux_lib::write_json("$ENV{WEBDIR}/HMC_INFO_$host.json", $out) if defined $out;
  check_and_write( "$work_folder/tmp/restapi/HMC_INFO_$host.json", $out, 0 );
  check_and_write( "$ENV{WEBDIR}/HMC_INFO_$host.json",             $out, 0 );
  return $out;
}

#generate actual timestamp in format "YYMMDD_HHMM"
sub act_timeStamp {
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
  $year += 1900;
  $mon++;
  if ( $hour < 10 ) { $hour = "0" . $hour; }
  if ( $min < 10 )  { $min  = "0" . $min; }
  if ( $mday < 10 ) { $mday = "0" . $mday; }
  if ( $mon < 10 )  { $mon  = "0" . $mon; }
  my $timestamp = "$year" . "$mon" . "$mday" . "_" . "$hour" . "$min";
  return $timestamp;
}

#returns hash of links to json files from one server with ID = $uid
sub LTMjsons {
  my $error;
  my $ts_error;
  my $ts_ze_souboru = getPreviousTimeStamp();
  my $uid_server    = shift;
  my $servername    = shift;
  if ( !defined $uid_server ) {
    error("Error while parsing server UUID. Try again") && return 1;
  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $servername LongTermMonitor Fetch\n";
  my $content;
  eval { $content = callAPI("rest/api/pcm/ManagedSystem/$uid_server/RawMetrics/LongTermMonitor"); };
  if ($@) {
    print "Rest API error 1119 : $@";
  }
  if ( $content eq "-1" ) {
    error( "No data fetched from $servername ($host) rest/api/pcm/ManagedSystem/$uid_server/RawMetrics/LongTermMonitor" . " File: " . __FILE__ . ":" . __LINE__ );
    return -1;
  }
  my $countp     = 0;
  my $counto     = 0;
  my $json_error = 0;
  my $decoded_jsons;
  my $decoded_jsons_c_vios;
  my @timeStamps;
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $servername LongTermMonitor Data Parsing\n";
  my @keys = keys %{ $content->{'entry'} };

  foreach my $key (@keys) {
    if ( $content->{'entry'}{$key}{'category'}{'term'} eq "phyp" ) {
      if ( parameter("debug-jsons") ) {
        print "\tPHYP $countp\t$content->{'entry'}{$key}{'title'}{'content'}\n";
        $countp++;
      }
      my $json = $content->{'entry'}{$key}{'link'}{'href'};
      if ( $json =~ /http/ ) {
        $json =~ s/^.*rest/rest/g;

        #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "DEBUG REST : $json url start\n";
        print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : processing phyp ltm json on $servername ($host) : $json\n";
        my $decoded = callAPIjson($json);

        #Xorux_lib::write_json("$work_folder/data/$servername/$host/iostat/ltm_phyp.json", $decoded) if defined $decoded;
        check_and_write( "$work_folder/data/$servername/$host/iostat/ltm_phyp.json", $decoded, 0 ) if ( $key eq $keys[-1] );
        my $timeStamp = $decoded->{'systemUtil'}{'utilSample'}{'timeStamp'};
        if ( !defined $timeStamp ) {
          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : No timestamp at $json\n";
          print Dumper $decoded->{'systemUtil'}{'utilSample'};
          $ts_error = 1;
          next;
        }
        $decoded_jsons->{$timeStamp} = $decoded;

        #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "DEBUG REST : $json url done\n";
      }
      else {
        error( "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : This should be url to perf phyp json: $json" );
        next;
      }
    }
    else {
      my $json = $content->{'entry'}{$key}{'link'}{'href'};
      if ( $json =~ /http/ ) {
        $json =~ s/^.*rest/rest/g;

        #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "DEBUG REST : $json url start\n";
        print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : processing vios ltm json on $servername ($host) : $json\n";
        my $decoded = callAPIjson($json);

        #Xorux_lib::write_json("$work_folder/data/$servername/$host/iostat/ltm_vios.json", $decoded) if defined $decoded;
        check_and_write( "$work_folder/data/$servername/$host/iostat/ltm_vios.json", $decoded, 0 ) if ( $key eq $keys[-1] );
        if ( defined $decoded->{'systemUtil'}{'utilSample'}{'errorInfo'}[0] ) {
          print( "Rest API 01    " . strftime( "%F %H:%M:%S", localtime(time) ) . "       : Error URL : $json Last syserror: $! \n" );

          #warn ( "Rest API 01    " . strftime("%F %H:%M:%S", localtime(time)) . "       : Error URL : $json Last syserror: $! \n");
          my $index = 0;
          foreach my $error ( @{ $decoded->{'systemUtil'}{'utilSample'}{'errorInfo'} } ) {
            print( "Rest API 01    " . strftime( "%F %H:%M:%S", localtime(time) ) . "       : Error n.#$index on $servername ($host) :" );

            #warn ( "Rest API 01    " . strftime("%F %H:%M:%S", localtime(time)) . "       : Error n.#$index on $servername ($host) :");
            foreach my $key ( keys %{$error} ) {
              print(" $key : $error->{$key}'}\n");

              #warn (" $key : $error->{$key}'}\n" );
            }
            print("\n");

            #warn ( "\n" );
            $index++;
          }
        }
        my $timeStamp = $decoded->{'systemUtil'}{'utilSample'}{'timeStamp'};
        if ( !defined $timeStamp ) {
          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : No timestamp at $json\n";
          print Dumper $decoded->{'systemUtil'}{'utilSample'};
          $ts_error = 1;
          next;
        }
        $decoded_jsons_c_vios->{$timeStamp} = $decoded;

        #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "DEBUG REST : $json url done\n";
      }
      else {
        error( "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : This should be url to perf vios json: $json" );
      }
    }
  }
  if ($ts_error) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : HMC REST API run OK but some timestamps are not processes - no information\n";
  }
  my $processed = {};

  #  my $processed = get_processed_metrics($uid_server);
  my $last_ts;
  my $processed_out;
  foreach my $key ( keys %{ $processed->{entry} } ) {
    my $item                = $processed->{entry}{$key};
    my $managed_system_link = $item->{link}{href};
    $managed_system_link = cut_rest_api_link($managed_system_link);
    if ( $managed_system_link =~ m/LogicalPartition/ ) {
      my $lpar           = callAPI($managed_system_link);
      my $lpar_json_link = $lpar->{entry}{link}{href};
      $lpar_json_link = cut_rest_api_link($lpar_json_link);
      my $lpar_json_content = callAPIjson($lpar_json_link);
      foreach my $sample ( @{ $lpar_json_content->{systemUtil}{utilSamples} } ) {
        foreach my $lparsutil ( @{ $sample->{lparsUtil} } ) {
          my $upd_ts = tz_correction( $sample->{sampleInfo}{timeStamp} );
          $processed_out->{ $lparsutil->{name} }{$upd_ts} = $lparsutil;
          $last_ts = $sample->{sampleInfo}{timeStamp};
        }
      }
    }
    else {
      my $lpar_json_content = callAPIjson($managed_system_link);
      foreach my $sample ( @{ $lpar_json_content->{systemUtil}{utilSamples} } ) {
        foreach my $viosutil ( @{ $sample->{viosUtil} } ) {
          my $upd_ts = tz_correction( $sample->{sampleInfo}{timeStamp} );
          $processed_out->{ $viosutil->{name} }{$upd_ts} = $viosutil;
        }
      }
    }
  }

  #my $file_tmp = "$work_folder/data/$servername/$host/iostat/processed_metrics_$uid_server\_tmp.json";
  #my $file     = "$work_folder/data/$servername/$host/iostat/processed_metrics_$uid_server.json";
  #Xorux_lib::write_json( $file_tmp, $processed_out );
  #copy ($file_tmp, $file) || error( "Cannot: cp  $file_tmp to $file : $!" . __FILE__ . ":" . __LINE__ );
  #unlink($file_tmp) || error( "Cannot rm  $file_tmp : $!" . __FILE__ . ":" . __LINE__ );

  if ( $json_error > 0 ) {
    error( "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Problem with JSON read should be caused by running load_data_hmc_rest_api.sh too quicky, connection error or no content on HMC" );
  }

  foreach my $stamp ( sort @timeStamps ) {
    if ( $debug eq "1" ) {
      print "ignored $stamp because it's older than $ts_ze_souboru\n";
    }
  }
  return ( $decoded_jsons, $decoded_jsons_c_vios );
}

sub parameter {
  my $tested = shift;
  if (@ARGV) {
    foreach my $param (@ARGV) {
      if ( $param eq "--$tested" ) {
        return 1;
      }
    }
  }
  else { return 0; }
}

sub preferencesVios {
  my $uid_server = shift;
  my $servername = shift;
  my $done;
  my $out;
  my $url = "rest/api/uom/ManagedSystem/$uid_server/VirtualIOServer";
  my $prefs_vios;
  my @vios_uuids;
  eval { $prefs_vios = callAPI($url); };

  if ($@) {
    print "Rest API error 1120 : $url : ErrMsg:$@ \n";
  }
  if ( !defined $prefs_vios || $prefs_vios eq "" || $prefs_vios eq "-1" ) { print "Can't get vios preferences from $url\n"; return; }

  if ( defined $prefs_vios->{corrupted_xml} ) {
    my @lines = split( "\n", $prefs_vios->{corrupted_xml} );
    foreach my $line (@lines) {
      if ( $line =~ m/VirtualIOServer\/[1-9]/ || $line =~ m/VirtualIOServer\/[A-Z]/ ) {
        ( undef, my $UUID_vios ) = split( "VirtualIOServer\/", $line );
        $UUID_vios = substr( $UUID_vios, 0, 36 );
        if ( !defined $done->{$UUID_vios} ) {
          push( @vios_uuids, $UUID_vios );
          $done->{$UUID_vios} = 1;
        }
      }
    }
  }
  my $vioses;
  if ( defined $vios_uuids[0] ) {
    foreach my $vios_uuid (@vios_uuids) {
      my $pref_vios_guess = callAPI("$url/$vios_uuid");
      print "vios url: $url/$vios_uuid\n";
      $pref_vios_guess = $pref_vios_guess->{'content'}{'VirtualIOServer:VirtualIOServer'};
      push( @{$vioses}, $pref_vios_guess ) if defined $pref_vios_guess;
    }
  }
  if ( defined $prefs_vios->{'error'} ) {
    print "Error in vioses, 1119\n";
    return;
  }

  # this is tricky, if there is only one vios, then the structure is different than the situation with more vioses... (#1 vs. #2)

  # One VIOS on the server
  if ( defined $prefs_vios->{'entry'}{'content'}{'VirtualIOServer:VirtualIOServer'} ) {    #1
    push( @{$vioses}, $prefs_vios->{'entry'}{'content'}{'VirtualIOServer:VirtualIOServer'} );
  }

  # More VIOSes on the server
  else {
    foreach my $viosId ( keys %{ $prefs_vios->{'entry'} } ) {
      push( @{$vioses}, $prefs_vios->{'entry'}{$viosId}{'content'}{'VirtualIOServer:VirtualIOServer'} );
    }
  }
  return $vioses;
}

sub preferencesLpar {
  my $uid_server = shift;
  my $servername = shift;
  my $prefs_lpars;
  eval { $prefs_lpars = callAPI("rest/api/uom/ManagedSystem/$uid_server/LogicalPartition"); };
  if ($@) {
    print "Rest API error 1121 : $@\n";
  }

  if ( !defined $prefs_lpars || $prefs_lpars eq "" || $prefs_lpars eq "-1" ) { error("Can't get lpar preferences from $proto://$host/rest/api/uom/ManagedSystem/$uid_server/LogicalPartition") && return 1; }
  my $preferences;
  my $out;
  $prefs_lpars = $prefs_lpars->{entry};
  my $prev_id = "";
  my $url;
  foreach my $lparId ( keys %{$prefs_lpars} ) {
    if ( ref( $prefs_lpars->{$lparId} ) ne "HASH" ) { next; }
    $url = $prefs_lpars->{$lparId}{link}{href};
    if ( !defined $url || !( $url =~ /^http/ ) ) {
      $url = $prefs_lpars->{link}{href};
      if ( !defined $url ) {
        next;
      }
    }

    my $urltemp = $url;

    ( undef, my $id_lpar ) = split( "LogicalPartition/", $url );
    if ( $prev_id ne "" && $prev_id eq $id_lpar ) {
      next;
    }
    $prev_id = $id_lpar;
    my $lparName = $prefs_lpars->{$id_lpar}{'content'}{'LogicalPartition:LogicalPartition'}{'PartitionName'}{'content'};
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $servername Fetching $lparName\n";
    $preferences->{$id_lpar} = $prefs_lpars->{$id_lpar}{'content'}{'LogicalPartition:LogicalPartition'};

    my $processorConf = $preferences->{$id_lpar}{'PartitionProcessorConfiguration'};
    my $memoryConf    = $preferences->{$id_lpar}{'PartitionMemoryConfiguration'};
    $out->{$lparName}{processor}{curr_proc_units} = $processorConf->{'CurrentSharedProcessorConfiguration'}{'AllocatedVirtualProcessors'}{'content'};
    if ( defined $processorConf->{'CurrentSharedProcessorConfiguration'}{'CurrentProcessingUnits'}{'content'} ) {
      $out->{$lparName}{processor}{curr_procs} = $processorConf->{'CurrentSharedProcessorConfiguration'}{'CurrentProcessingUnits'}{'content'};
    }
    elsif ( defined $processorConf->{'CurrentDedicatedProcessorConfiguration'}{'CurrentProcessors'}{'content'} ) {
      $out->{$lparName}{processor}{curr_procs} = $processorConf->{'CurrentDedicatedProcessorConfiguration'}{'CurrentProcessors'}{'content'};
    }
    $out->{$lparName}{processor}{curr_min_procs}    = $processorConf->{'CurrentDedicatedProcessorConfiguration'}{'CurrentMinimumProcessors'}{'content'};
    $out->{$lparName}{processor}{curr_max_procs}    = $processorConf->{'CurrentDedicatedProcessorConfiguration'}{'CurrentMaximumProcessors'}{'content'};
    $out->{$lparName}{processor}{curr_sharing_mode} = $processorConf->{'CurrentSharingMode'}{'content'};

    my $tmp_mem_mode;
    if   ( $memoryConf->{'SharedMemoryEnabled'}{'content'} eq "true" ) { $tmp_mem_mode = "shared"; }
    else                                                               { $tmp_mem_mode = "ded"; }
    $out->{$lparName}{memory}{mem_mode} = $tmp_mem_mode;
    $out->{$lparName}{memory}{curr_mem} = $memoryConf->{CurrentMemory}{'content'};
  }
  return $out;
}

# returns hash structure with lparsutil, viosutil
#   AND decode all needed jsons and because it's quicker than decoded them again
#   in sharedmemorypool and sharedprocessorpool functions

sub sharedMemoryPool {
  my $uid              = shift;
  my $decoded_ltmjsons = shift;
  my $out;
  foreach my $timeStamp ( reverse sort keys %{$decoded_ltmjsons} ) {
    my $decoded = $decoded_ltmjsons->{$timeStamp};
    my $ts      = $decoded->{systemUtil}{utilSample}{timeStamp};
    my $new_ts  = tsToPerffileFormat( $ts, 0 );
    my $item    = $decoded->{systemUtil}{utilSample}{sharedMemoryPool};
    foreach my $sample ( @{$item} ) {
      foreach my $metric ( keys %{$sample} ) {
        if ( defined $metric && $metric ne "" ) {
          $out->{$new_ts}{$metric} = $sample->{$metric};
        }
        else {
          $out->{$new_ts}{metric_name} = undef;
        }
      }
    }
  }
  return $out;
}

sub memory {
  my $decoded_ltmjsons = shift;
  my $out;
  foreach my $timeStamp ( reverse sort keys %{$decoded_ltmjsons} ) {
    my $availableMem = $decoded_ltmjsons->{$timeStamp}{systemUtil}{utilSample}{memory}{availableMem};
    if ( !defined $availableMem || $availableMem eq "" ) { $availableMem = 0; }
    my $configurableMem = $decoded_ltmjsons->{$timeStamp}{systemUtil}{utilSample}{memory}{configurableMem};
    if ( !defined $configurableMem || $configurableMem eq "" ) { $configurableMem = 0; }
    my $memFirmware = $decoded_ltmjsons->{$timeStamp}{systemUtil}{utilSample}{systemFirmware}{assignedMem};
    if ( !defined $memFirmware || $memFirmware eq "" ) { $memFirmware = 0; }
    my $new_ts = tsToPerffileFormat( $timeStamp, 0 );
    $out->{$new_ts}{availableMem}          = $availableMem;
    $out->{$new_ts}{configurableMem}       = $configurableMem;
    $out->{$new_ts}{assignedMemToFirmware} = $memFirmware;
  }
  return $out;
}

sub sharedProcessorPoolForOneServer {
  my $decoded_ltmjsons = shift;
  my $uid              = shift;
  my $ttt;
  eval { $ttt = callAPI("rest/api/uom/ManagedSystem/$uid/SharedProcessorPool"); };
  if ($@) {
    print "Rest API error 1122 : $@\n";
  }
  my $shared_pools;
  if ( ref($ttt) eq "HASH" ) {
    foreach my $hashid ( keys %{ $ttt->{entry} } ) {
      my $shpm = $ttt->{entry}{$hashid}{content}{'SharedProcessorPool:SharedProcessorPool'};

      #print "Shared Pool output API\n";
      #print Dumper $shpm;
      if ( $ttt->{entry}{$hashid}{content}{'SharedProcessorPool:SharedProcessorPool'}{'PoolName'}{'content'} =~ /^SharedPool[0-9][0-9]/ ) {

        print "SKIP $ttt->{entry}{$hashid}{content}{'SharedProcessorPool:SharedProcessorPool'}{'PoolName'}{'content'} for $uid\n";
        next;
      }
      my $name_tmp = $ttt->{entry}{$hashid}{content}{'SharedProcessorPool:SharedProcessorPool'}{'PoolName'}{'content'};
      $shared_pools->{$name_tmp}{AvailableProcUnits}             = $shpm->{AvailableProcUnits}{content};
      $shared_pools->{$name_tmp}{MaximumProcessingUnits}         = $shpm->{MaximumProcessingUnits}{content};
      $shared_pools->{$name_tmp}{CurrentReservedProcessingUnits} = $shpm->{CurrentReservedProcessingUnits}{content};
      $shared_pools->{$name_tmp}{PendingReservedProcessingUnits} = $shpm->{PendingReservedProcessingUnits}{content};
    }
  }
  else {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $uid no shared pools found\n";
    print Dumper $ttt;
  }
  my $out;
  my $utilized_pool_cycles_total = 0;
  my $assigned_proc_cycles_total;
  my $totalPool;
  my $maxProcUnits, my $borrowedPoolProcUnits;
  my $ts_from_file = getPreviousTimeStamp();
  foreach my $timeStamp ( reverse sort keys %{$decoded_ltmjsons} ) {
    my $decoded = $decoded_ltmjsons->{$timeStamp};
    my $ts      = $decoded->{systemUtil}{utilSample}{timeStamp};
    $ts = tsToPerffileFormat( $ts, 0 );
    my $item           = $decoded->{systemUtil}{utilSample}{sharedProcessorPool};
    my $processor      = $decoded->{systemUtil}{utilSample}{processor};
    my $availProcUnits = $processor->{availableProcUnits};
    foreach my $pool ( @{$item} ) {
      my $poolId   = $pool->{id};
      my $poolName = $pool->{name};
      $out->{$ts}{$poolId}{assignedProcCycles}    = $pool->{assignedProcCycles};
      $out->{$ts}{$poolId}{utilizedPoolCycles}    = $pool->{utilizedPoolCycles};
      $out->{$ts}{$poolId}{borrowedPoolProcUnits} = $pool->{borrowedPoolProcUnits};
      $out->{$ts}{$poolId}{id}                    = $pool->{id};
      $out->{$ts}{$poolId}{maxProcUnits}          = $pool->{maxProcUnits};
      $out->{$ts}{$poolId}{reservedPoolUnits}     = $shared_pools->{$poolName}{CurrentReservedProcessingUnits};

      if ( defined $utilized_pool_cycles_total && $utilized_pool_cycles_total ne "" ) {
        $utilized_pool_cycles_total += $pool->{utilizedPoolCycles};
      }
      else {
        $utilized_pool_cycles_total = "";
      }
      if ( $poolName eq "DefaultPool" ) {
        $maxProcUnits               = $pool->{maxProcUnits};
        $borrowedPoolProcUnits      = $pool->{borrowedPoolProcUnits};
        $assigned_proc_cycles_total = $pool->{assignedProcCycles};
      }
    }
    $totalPool->{$ts}{utilizedPoolCycles}    = "$utilized_pool_cycles_total";
    $totalPool->{$ts}{assignedProcCycles}    = "$assigned_proc_cycles_total";
    $totalPool->{$ts}{borrowedPoolProcUnits} = "$borrowedPoolProcUnits";
    $totalPool->{$ts}{maxProcUnits}          = $maxProcUnits - $borrowedPoolProcUnits;
    $totalPool->{$ts}{availableProcUnits}    = $availProcUnits;
    if ( $debug eq "1" ) {
      print "TEST: utilized:$utilized_pool_cycles_total\tassigned:$assigned_proc_cycles_total\tmaxPU:$maxProcUnits\tborrowed:$borrowedPoolProcUnits\n\n";
    }
    $utilized_pool_cycles_total = "0";
    $assigned_proc_cycles_total = "0";
  }
  return ( $out, $totalPool );
}

sub tsToPerffileFormat {
  my $ts = shift;
  $ts = tz_correction($ts);
  return $ts;

  if ( length($ts) < 17 ) {
    return 1;
  }

  #print "TS HONZA : $ts\n";
  my $new  = shift;
  my $year = substr( $ts, 0, 4 );
  my $mon  = substr( $ts, 5, 2 );
  my $day  = substr( $ts, 8, 2 );
  my $hour = substr( $ts, 11, 2 );
  my $min  = substr( $ts, 14, 2 );
  my $sec  = substr( $ts, 17, 2 );
  my $out  = "$mon/$day/$year $hour:$min:$sec";

  if ($new) {
    $out = tz_correction($ts);
  }
  return $out;

}

#create perffiles per one server
sub createPerffile {
  my $uid              = shift;
  my $serverName       = shift;
  my $CONFIG           = shift;
  my $vscsi_info       = shift;
  my $restricted_lpars = giveMeRestrictedLpars($CONFIG);
  ( my $hash, my $sriovhash, my $firstTimeStamp, my $lastTimeStamp ) = LTMdata( $uid, $serverName );
  if ( !defined $hash || $hash eq "1" ) {
    error( "No lpars found from LTMdata for $serverName" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
  }

  my $decoded_ltmjsons = $DATA->{jsons}{$uid};
  my $decvios          = $DATA->{vios}{$uid};

  #my $serverName = $decoded_ltmjsons->{$firstTimeStamp}{systemUtil}{utilInfo}{name};
  my $act_ts = act_timeStamp();
  if ( !defined $serverName || $serverName eq "" ) {
    error( "HMC not responded with correct servername. Server is probably restarting or shut down???" . " File: " . __FILE__ . ":" . __LINE__ );
    exit;
  }
  $performance_folder = "$env_dir/$serverName/$host";
  if ( ref($hash) eq "HASH" && defined $hash->{error} ) {
    print "Data from long term monitor failed.";
    return -1;
  }

  #  print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : $host $serverName Get Lpar Preferences and Performance\n";
  #  my $preferences = preferencesLpar($uid, $serverName);
  #  print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : $host $serverName Get Vios Preferences and Performance\n";
  #  my $preferences_vios = preferencesVios($uid, $serverName);
  #  $preferences_vios = "";
  #  if (!defined $preferences_vios || $preferences_vios eq "" || $preferences_vios == -1){
  #    print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : $host $serverName Skipping virtual io server on $uid - not available\n";
  #  }
  #  else{
  #    foreach my $key (keys %{$preferences_vios}){
  #      $preferences->{$key} = $preferences_vios->{$key};
  #    }
  #  }
  if ( $debug eq "1" ) {
    print "FTS: $firstTimeStamp\n";
    print "LTS: $lastTimeStamp\n";
  }
  my $test         = 1;
  my $ts_from_file = getPreviousTimeStamp();
  my $i            = 0;
  ########## CONVERT DATA TO GAUGES ##########
  my $last_timestamp_processed = "";
  my $reversed_lpars           = $hash;
  if ( defined $ENV{HMC_JSONS} ) {
    if ( $ENV{HMC_JSONS} == 1 ) {

      #Xorux_lib::write_json("$performance_folder/iostat/HMC_$host"."_lpars_perf_$act_ts.json", $reversed_lpars) if defined $reversed_lpars;
      check_and_write( "$performance_folder/iostat/HMC_$host" . "_lpars_perf_$act_ts.json", $reversed_lpars, 0 );
    }
  }
  my $reversed_sriov;
  my $arr_formated_sriov;
  foreach my $lpar ( keys %{$sriovhash} ) {
    foreach my $id ( keys %{ $sriovhash->{$lpar} } ) {
      my $physLoc                = $id;
      my $droppedReceivedPackets = 0;
      my $droppedSentPackets     = 0;
      my $errorIn                = 0;
      my $errorOut               = 0;
      my $receivedBytes          = 0;
      my $receivedPackets        = 0;
      my $sentBytes              = 0;
      my $sentPackets            = 0;
      my @timestamps             = keys %{ $sriovhash->{$lpar}{$id} };
      my $tst                    = 1;
      my $epoch_prev             = "";

      foreach my $ts ( sort @timestamps ) {
        my $arr_ts_sample;
        my $epoch_new  = str2time($ts);
        my $epoch_diff = $epoch_new - $epoch_prev if ( $epoch_prev ne "" );
        $epoch_prev = $epoch_new;
        my $new_ts = tsToPerffileFormat( $ts, 1 );
        if ( !defined $epoch_diff || $epoch_diff eq "" || $epoch_diff == 0 ) { next; }
        my $sriovPort               = $sriovhash->{$lpar}{$id}{$ts};
        my $configurationType       = $sriovPort->{'configurationType'};
        my $drcIndex                = $sriovPort->{'drcIndex'};
        my $droppedReceivedPacketsG = ( $sriovPort->{'droppedReceivedPackets'} - $droppedReceivedPackets ) / $epoch_diff;
        my $droppedSentPacketsG     = ( $sriovPort->{'droppedSentPackets'} - $droppedSentPackets ) / $epoch_diff;
        my $errorInG                = ( $sriovPort->{'errorIn'} - $errorIn ) / $epoch_diff;
        my $errorOutG               = ( $sriovPort->{'errorOut'} - $errorOut ) / $epoch_diff;
        my $physicalDrcIndex        = $sriovPort->{'physicalDrcIndex'};
        my $physicalPortId          = $sriovPort->{'physicalPortId'};
        my $receivedBytesG          = ( $sriovPort->{'receivedBytes'} - $receivedBytes ) / $epoch_diff;
        $receivedBytesG /= 1024;
        my $receivedPacketsG = ( $sriovPort->{'receivedPackets'} - $receivedPackets ) / $epoch_diff;
        my $sentBytesG       = ( $sriovPort->{'sentBytes'} - $sentBytes ) / $epoch_diff;
        $sentBytesG /= 1024;
        my $sentPacketsG   = ( $sriovPort->{'sentPackets'} - $sentPackets ) / $epoch_diff;
        my $vnicDeviceMode = $sriovPort->{'vnicDeviceMode'};

        if ( $tst == 0 ) {
          push( @{$arr_ts_sample}, $new_ts );
          push( @{$arr_ts_sample}, $lpar );
          push( @{$arr_ts_sample}, $physLoc );
          push( @{$arr_ts_sample}, $configurationType );
          push( @{$arr_ts_sample}, $drcIndex );
          push( @{$arr_ts_sample}, $droppedReceivedPacketsG );
          push( @{$arr_ts_sample}, $droppedSentPacketsG );
          push( @{$arr_ts_sample}, $errorInG );
          push( @{$arr_ts_sample}, $errorOutG );
          push( @{$arr_ts_sample}, $physicalDrcIndex );
          push( @{$arr_ts_sample}, $physicalPortId );
          push( @{$arr_ts_sample}, $receivedBytesG );
          push( @{$arr_ts_sample}, $receivedPacketsG );
          push( @{$arr_ts_sample}, $sentBytesG );
          push( @{$arr_ts_sample}, $sentPacketsG );
          push( @{$arr_ts_sample}, $vnicDeviceMode );

          push( @{$arr_formated_sriov}, $arr_ts_sample );
        }
        $droppedReceivedPackets = $sriovPort->{'droppedReceivedPackets'};
        $droppedSentPackets     = $sriovPort->{'droppedSentPackets'};
        $errorIn                = $sriovPort->{'errorIn'};
        $errorOut               = $sriovPort->{'errorOut'};
        $receivedBytes          = $sriovPort->{'receivedBytes'};
        $receivedPackets        = $sriovPort->{'receivedPackets'};
        $sentBytes              = $sriovPort->{'sentBytes'};
        $sentPackets            = $sriovPort->{'sentPackets'};
        $tst                    = 0;
      }
    }
  }
  $reversed_sriov = $arr_formated_sriov;
  if ( defined $ENV{HMC_JSONS} ) {
    if ( $ENV{HMC_JSONS} == 1 ) {

      #Xorux_lib::write_json("$performance_folder/iostat/HMC_$host"."_sriov_perf_$act_ts.json", $reversed_sriov) if defined $reversed_sriov;
      check_and_write( "$performance_folder/iostat/HMC_$host" . "_sriov_perf_$act_ts.json", $reversed_sriov, 0 );
    }
  }

  ( my $sharedPool, my $poolTotal ) = sharedProcessorPoolForOneServer( $decoded_ltmjsons, $uid );

  if ( defined $ENV{HMC_JSONS} ) {
    if ( $ENV{HMC_JSONS} == 1 ) {

      #Xorux_lib::write_json("$performance_folder/iostat/HMC_$host"."_pool_conf_$act_ts.json", $poolTotal) if defined $poolTotal;
      #Xorux_lib::write_json("$performance_folder/iostat/HMC_$host"."_poolsh_conf_$act_ts.json", $sharedPool) if defined $sharedPool;
      check_and_write( "$performance_folder/iostat/HMC_$host" . "_pool_conf_$act_ts.json",   $poolTotal,  0 );
      check_and_write( "$performance_folder/iostat/HMC_$host" . "_poolsh_conf_$act_ts.json", $sharedPool, 0 );
    }
  }
  if ( $sharedPool eq "" ) {
    print "shared processor pool data is not available\n";
    return -1;
  }
  foreach my $timeStamp ( reverse sort keys %{$sharedPool} ) {
    foreach my $poolName ( keys %{ $sharedPool->{$timeStamp} } ) {
      if ( $debug eq "1" ) {
        print "\tWriting new data($poolName) from $timeStamp\n";
        print "poolname:$poolName\ttimestamp:$timeStamp\n";
      }
      my $assignedProcCycles = $sharedPool->{$timeStamp}{$poolName}{assignedProcCycles};
      my $id                 = $sharedPool->{$timeStamp}{$poolName}{id};
      if ( !defined $id ) { next; }
      my $utilizedPoolCycles = $sharedPool->{$timeStamp}{$poolName}{utilizedPoolCycles};

      #print $fh "$timeStamp,$id,$assignedProcCycles,$utilizedPoolCycles\n";

    }
  }

  #close($fh);

  #$fileName = "pool.in-m";
  #open ($fh, ">","$performance_folder/$fileName") || error("Cannot create $performance_folder/$fileName" .  " File: ".__FILE__.":".__LINE__);
  #open (my $fh2, ">","$performance_folder/pool.in-alrt-no") || error("Cannot create $performance_folder/pool.in-alrt-no" .  " File: ".__FILE__.":".__LINE__);

  #pool
  #if (parameter("header")){
  #  print $fh "Pool:\n";
  #  print $fh "\tInterval Start:$firstTimeStamp\n\tInterval End:$lastTimeStamp\n\tInterval Length:$intervalLength\n";
  #  print $fh "----------------------------------------\ntimestamp,assignedProcCycles,utilizedPoolCycles,maxProcUnits,borrowedPoolProcUnits\n";
  #}
  #foreach my $timeStamp(reverse sort keys %{$poolTotal}){
  #  print $fh "$timeStamp,$poolTotal->{$timeStamp}{assignedProcCycles},$poolTotal->{$timeStamp}{utilizedPoolCycles},$poolTotal->{$timeStamp}{maxProcUnits},$poolTotal->{$timeStamp}{borrowedPoolProcUnits},$poolTotal->{$timeStamp}{availableProcUnits}\n";
  #  print $fh2 "$timeStamp,$poolTotal->{$timeStamp}{assignedProcCycles},$poolTotal->{$timeStamp}{utilizedPoolCycles},$poolTotal->{$timeStamp}{maxProcUnits},$poolTotal->{$timeStamp}{borrowedPoolProcUnits},$poolTotal->{$timeStamp}{availableProcUnits}\n";
  #}
  #close($fh);
  #close($fh2);
  #$fileName = "mem_sh.in-m";
  #open ($fh, ">","$performance_folder/$fileName") || error("Cannot create $performance_folder/$fileName" .  " File: ".__FILE__.":".__LINE__);

  my $smp = sharedMemoryPool( $uid, $decoded_ltmjsons );

  #if (parameter("header")){
  #print $fh "Shared Memory Pool Statistics:\n";
  #print $fh "\tInterval Start:$firstTimeStamp\n\tInterval End:$lastTimeStamp\n\tInterval Length:$intervalLength\n";
  #print $fh "----------------------------------------\n";
  #print $fh "timestamp,id,assignedMemToLpars,assignedMemToSysFirmware,mappedIOMemToLpars,totalIOMem,totalMem\n";
  #}
  #foreach my $timeStamp (reverse sort keys %{$smp}){
  #  if ($debug eq "1"){
  #    print "\tWriting new data (Shared Memory Pool) from $timeStamp\n";
  #  }
  #  my $assignedMemToLpars = $smp->{$timeStamp}{assignedMemToLpars};
  #  my $assignedMemToSysFirmware = $smp->{$timeStamp}{assignedMemToSysFirmware};
  #  my $id = $smp->{$timeStamp}{id};
  #  my $mappedIOMemToLpars = $smp->{$timeStamp}{mappedIOMemToLpars};
  #  my $totalIOMem = $smp->{$timeStamp}{totalIOMem};
  #  my $totalMem = $smp->{$timeStamp}{totalMem};
  #  print $fh "$timeStamp,$id,$assignedMemToLpars,$assignedMemToSysFirmware,$mappedIOMemToLpars,$totalIOMem,$totalMem\n";
  #}
  #close($fh);

  #$fileName = "mem.in-m";
  #open ($fh, ">","$performance_folder/$fileName") || error("Cannot create $performance_folder/$fileName" .  " File: ".__FILE__.":".__LINE__);
  my $memoryHash = memory($decoded_ltmjsons);
  if ( defined $ENV{HMC_JSONS} ) {
    if ( $ENV{HMC_JSONS} == 1 ) {

      #Xorux_lib::write_json("$performance_folder/iostat/HMC_$host"."_mem_conf_$act_ts.json", $memoryHash) if defined $memoryHash;
      check_and_write( "$performance_folder/iostat/HMC_$host" . "_mem_conf_$act_ts.json", $memoryHash, 0 );
    }
  }

  #foreach my $timeStamp (reverse sort keys %{$memoryHash}){
  #  if ($debug eq "1"){
  #    print "\tWriting new data (Memory) from $timeStamp\n";
  #  }
  #  print $fh "$timeStamp,$memoryHash->{$timeStamp}{availableMem},$memoryHash->{$timeStamp}{configurableMem},$memoryHash->{$timeStamp}{assignedMemToFirmware}\n";
  #}
  #close($fh);

  #$fileName = "adapters.in-m";
  my $genericAdapters;
  my $fiberChannelAdapters;
  my $genericPhysicalAdapters;
  my $heAdapters;
  my $hmc_rest_debug_file = "$work_folder/tmp/restapi/$host-$uid-adapters.debug";
  my $hmc_rest_debug;
  if ( $ENV{HMC_REST_DEBUG} ) {
    open( $hmc_rest_debug, ">>", $hmc_rest_debug_file ) || error( "Cannot open $hmc_rest_debug_file" . " File: " . __FILE__ . ":" . __LINE__ );
  }
  if ( defined $decvios && $decvios ne "" ) {
    my $initial = 1;
    my $err_msgs;
    my $ts_back = "";
    foreach my $timeStamp ( reverse sort keys %{$decvios} ) {
      my $new_ts = tsToPerffileFormat( $timeStamp, 0 );
      foreach my $errorInfo ( @{ $decvios->{$timeStamp}{systemUtil}{utilSample}{errorInfo} } ) {
        if ( defined $errorInfo->{errId} && !defined( $err_msgs->{ $errorInfo->{errId} } ) ) {
          print "Rest API Error " . strftime( "%F %H:%M:%S", localtime(time) ) . ": $errorInfo->{errId} : $errorInfo->{errMsg} in File: " . __FILE__ . ":" . __LINE__ . "\n";
          $err_msgs->{ $errorInfo->{errId} } = $errorInfo->{errMsg};
        }
      }
      foreach my $vios ( @{ $decvios->{$timeStamp}{systemUtil}{utilSample}{viosUtil} } ) {
        my $lparName = "";
        $lparName = $vios->{name} if ( defined $vios->{name} && $vios->{name} ne "" );
        if ( defined $restricted_lpars->{$lparName}{available} && !( $restricted_lpars->{$lparName}{available} ) && !( defined $restricted_lpars->{error_in_loading_lpars} ) ) {
          if ($restricted_role_applied) {
            print "skipping lpar with no permission\n";
            next;
          }
        }
        if ( defined $vios->{name} ) {

          #Generic Adapters
          foreach my $ga ( @{ $vios->{network}{genericAdapters} } ) {
            if ( $ga->{physicalLocation} =~ m/\-V/ && $ga->{physicalLocation} !~ m/\-P/ ) { next; }
            $genericAdapters->{ $vios->{name} }{ $ga->{id} }{$timeStamp}{receivedBytes}    = $ga->{receivedBytes};
            $genericAdapters->{ $vios->{name} }{ $ga->{id} }{$timeStamp}{receivedPackets}  = $ga->{receivedPackets};
            $genericAdapters->{ $vios->{name} }{ $ga->{id} }{$timeStamp}{sentBytes}        = $ga->{sentBytes};
            $genericAdapters->{ $vios->{name} }{ $ga->{id} }{$timeStamp}{sentPackets}      = $ga->{sentPackets};
            $genericAdapters->{ $vios->{name} }{ $ga->{id} }{$timeStamp}{droppedPackets}   = $ga->{droppedPackets};
            $genericAdapters->{ $vios->{name} }{ $ga->{id} }{$timeStamp}{type}             = $ga->{type};
            $genericAdapters->{ $vios->{name} }{ $ga->{id} }{$timeStamp}{physicalLocation} = $ga->{physicalLocation};
            if ( $ENV{HMC_REST_DEBUG} ) { print $hmc_rest_debug "$timeStamp $ga->{physicalLocation} $ga->{receivedBytes} $ga->{sentBytes} $ga->{receivedPackets} $ga->{sentPackets}\n"; }
          }

          #Fiber Channel Adapters
          foreach my $fcs ( @{ $vios->{storage}{fiberChannelAdapters} } ) {
            if ( $fcs->{'wwpn'} eq "0000000000000000" ) { next; }    #every adapter has to have wwpn, if not it is something wrong (API error)
            $fiberChannelAdapters->{ $vios->{'name'} }{ $fcs->{'id'} }{$timeStamp}{'numOfReads'}       = $fcs->{'numOfReads'};
            $fiberChannelAdapters->{ $vios->{'name'} }{ $fcs->{'id'} }{$timeStamp}{'numOfWrites'}      = $fcs->{'numOfWrites'};
            $fiberChannelAdapters->{ $vios->{'name'} }{ $fcs->{'id'} }{$timeStamp}{'readBytes'}        = $fcs->{'readBytes'};
            $fiberChannelAdapters->{ $vios->{'name'} }{ $fcs->{'id'} }{$timeStamp}{'writeBytes'}       = $fcs->{'writeBytes'};
            $fiberChannelAdapters->{ $vios->{'name'} }{ $fcs->{'id'} }{$timeStamp}{'runningSpeed'}     = $fcs->{'runningSpeed'};
            $fiberChannelAdapters->{ $vios->{'name'} }{ $fcs->{'id'} }{$timeStamp}{'wwpn'}             = $fcs->{'wwpn'};
            $fiberChannelAdapters->{ $vios->{'name'} }{ $fcs->{'id'} }{$timeStamp}{'physicalLocation'} = $fcs->{'physicalLocation'};
            if ( $ENV{HMC_REST_DEBUG} ) { print $hmc_rest_debug "$timeStamp $fcs->{'physicalLocation'} $fcs->{readBytes} $fcs->{writeBytes} $fcs->{numOfReads} $fcs->{numOfWrites}\n"; }
            my $fiberChannelAdaptersVFC = 0;                         #prepare for future implementation

            if ( $fiberChannelAdaptersVFC == 1 ) {
              foreach my $vfchost ( @{ $fcs->{'ports'} } ) {
                $fiberChannelAdapters->{ $vios->{'name'} }{ $vfchost->{'id'} }{$timeStamp}{'numOfReads'}       = $vfchost->{'numOfReads'};
                $fiberChannelAdapters->{ $vios->{'name'} }{ $vfchost->{'id'} }{$timeStamp}{'numOfWrites'}      = $vfchost->{'numOfWrites'};
                $fiberChannelAdapters->{ $vios->{'name'} }{ $vfchost->{'id'} }{$timeStamp}{'readBytes'}        = $vfchost->{'readBytes'};
                $fiberChannelAdapters->{ $vios->{'name'} }{ $vfchost->{'id'} }{$timeStamp}{'writeBytes'}       = $vfchost->{'writeBytes'};
                $fiberChannelAdapters->{ $vios->{'name'} }{ $vfchost->{'id'} }{$timeStamp}{'runningSpeed'}     = $vfchost->{'runningSpeed'};
                $fiberChannelAdapters->{ $vios->{'name'} }{ $vfchost->{'id'} }{$timeStamp}{'wwpn'}             = $vfchost->{'wwpn'};
                $fiberChannelAdapters->{ $vios->{'name'} }{ $vfchost->{'id'} }{$timeStamp}{'physicalLocation'} = $vfchost->{'physicalLocation'};
              }
            }
          }
          foreach my $gpa ( @{ $vios->{storage}{genericPhysicalAdapters} } ) {
            if ( $gpa->{id} =~ /fscsi/ ) {
              next;
            }
            else {
              #             open (my $hmc_rest_debug, ">>", "$work_folder/tmp/$gpa->{physicalLocation}.debug");
              $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'physicalLocation'} = $gpa->{physicalLocation};
              $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'numOfReads'}       = $gpa->{numOfReads};
              $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'numOfWrites'}      = $gpa->{numOfWrites};
              $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'readBytes'}        = $gpa->{readBytes};
              $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'writeBytes'}       = $gpa->{writeBytes};
              $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'type'}             = $gpa->{type};
            }
            if ( $ENV{HMC_REST_DEBUG} ) { print $hmc_rest_debug "$timeStamp $gpa->{physicalLocation} $gpa->{readBytes} $gpa->{writeBytes} $gpa->{numOfReads} $gpa->{numOfWrites}\n"; }

            #            close($hmc_rest_debug);
          }
          foreach my $gpa ( @{ $vios->{storage}{genericVirtualAdapters} } ) {
            next;
            if ( $gpa->{id} =~ /fscsi/ ) {
              next;
            }
            $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'physicalLocation'} = $gpa->{physicalLocation};
            $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'numOfReads'}       = $gpa->{numOfReads};
            $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'numOfWrites'}      = $gpa->{numOfWrites};
            $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'readBytes'}        = $gpa->{readBytes};
            $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'writeBytes'}       = $gpa->{writeBytes};
            $genericPhysicalAdapters->{ $vios->{'name'} }{ $gpa->{id} }{$timeStamp}{'type'}             = $gpa->{type};
          }
        }
      }
      $ts_back = $timeStamp;
    }
    my $reversed_lan;
    my $reversed_gpa;
    my $reversed_san;
    my $arr_formated_san;
    my $lan_aliases;
    my $san_aliases;
    my $sas_aliases;
    my $arr_formated_lan;

    foreach my $v_name ( keys %{$genericAdapters} ) {
      foreach my $adapter_id ( keys %{ $genericAdapters->{$v_name} } ) {
        my $receivedBytes   = 0;
        my $receivedPackets = 0;
        my $sentBytes       = 0;
        my $sentPackets     = 0;
        my $droppedPackets  = 0;
        my $tst             = 1;
        my $epoch_prev      = "";
        foreach my $timestamp ( sort keys %{ $genericAdapters->{$v_name}{$adapter_id} } ) {
          my $type       = $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{type};
          my $epoch_new  = str2time($timestamp);
          my $epoch_diff = $epoch_new - $epoch_prev if ( $epoch_prev ne "" );
          $epoch_prev = $epoch_new;
          my $new_ts = tsToPerffileFormat( $timestamp, 1 );
          if ( !defined $epoch_diff || $epoch_diff eq "" || $epoch_diff == 0 ) { next; }
          my $receivedBytesG   = ( $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{receivedBytes} - $receivedBytes ) / $epoch_diff;
          my $receivedPacketsG = ( $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{receivedPackets} - $receivedPackets ) / $epoch_diff;
          my $sentBytesG       = ( $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{sentBytes} - $sentBytes ) / $epoch_diff;
          my $sentPacketsG     = ( $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{sentPackets} - $sentPackets ) / $epoch_diff;
          my $droppedPacketsG  = ( $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{droppedPackets} - $droppedPackets ) / $epoch_diff;
          my $location         = $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{physicalLocation};

          if ( $tst == 0 ) {
            my $arr_ts_sample;
            push( @{$arr_ts_sample}, $new_ts );
            push( @{$arr_ts_sample}, $v_name );
            push( @{$arr_ts_sample}, $adapter_id );

            push( @{$arr_ts_sample}, $type );

            #$reversed_lan->{$new_ts}{$v_name}{$adapter_id}{type} = $type;

            push( @{$arr_ts_sample}, $droppedPacketsG );

            #$reversed_lan->{$new_ts}{$v_name}{$adapter_id}{droppedPacketsG} = $droppedPacketsG;

            push( @{$arr_ts_sample}, $sentPacketsG );

            #$reversed_lan->{$new_ts}{$v_name}{$adapter_id}{sentPacketsG} =$sentPacketsG;

            push( @{$arr_ts_sample}, $receivedPacketsG );

            #$reversed_lan->{$new_ts}{$v_name}{$adapter_id}{receivedPacketsG} = $receivedPacketsG;

            push( @{$arr_ts_sample}, $sentBytesG / 1024 );

            #$reversed_lan->{$new_ts}{$v_name}{$adapter_id}{sentBytesG} = $sentBytesG/1024;

            push( @{$arr_ts_sample}, $receivedBytesG / 1024 );

            #$reversed_lan->{$new_ts}{$v_name}{$adapter_id}{receivedBytesG} = $receivedBytesG/1024;

            push( @{$arr_ts_sample}, $location );

            #$reversed_lan->{$new_ts}{$v_name}{$adapter_id}{physicalLocation} = $location;

            ( undef, undef, my $location_without_prefix ) = split( '\.', $location );
            if (!defined $location_without_prefix ) { $location_without_prefix = ""; }
            $lan_aliases->{$location_without_prefix}{partition} = $v_name;
            $lan_aliases->{$location_without_prefix}{UUID}      = PowerDataWrapper::md5_string($location);
            $lan_aliases->{$location_without_prefix}{alias}     = $adapter_id;
            push( @{$arr_formated_lan}, $arr_ts_sample ) if defined $arr_ts_sample->[0];
          }
          $receivedBytes   = $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{receivedBytes};
          $receivedPackets = $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{receivedPackets};
          $sentBytes       = $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{sentBytes};
          $sentPackets     = $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{sentPackets};
          $droppedPackets  = $genericAdapters->{$v_name}{$adapter_id}{$timestamp}{droppedPackets};
          $tst             = 0;
        }
      }
    }
    $reversed_lan = $arr_formated_lan;
    if ( defined $ENV{HMC_JSONS} ) {
      if ( $ENV{HMC_JSONS} == 1 ) {

        #Xorux_lib::write_json("$performance_folder/iostat/HMC_$host"."_lan_perf_$act_ts.json", $reversed_lan) if defined $reversed_lan;
        #Xorux_lib::write_json("$performance_folder/LAN_aliases.json", $lan_aliases) if defined $lan_aliases;
        check_and_write( "$performance_folder/iostat/HMC_$host" . "_lan_perf_$act_ts.json", $reversed_lan, 0 );
        check_and_write( "$performance_folder/LAN_aliases.json",                            $lan_aliases,  0 );
      }
    }

    #SANKA
    foreach my $san_name ( keys %{$fiberChannelAdapters} ) {
      foreach my $adapter_id ( keys %{ $fiberChannelAdapters->{$san_name} } ) {
        my $numOfReads   = 0;
        my $numOfWrites  = 0;
        my $writeBytes   = 0;
        my $readBytes    = 0;
        my $runningSpeed = 0;
        my $tst          = 1;
        my $epoch_prev   = "";
        foreach my $timestamp ( sort keys %{ $fiberChannelAdapters->{$san_name}{$adapter_id} } ) {
          my $arr_ts_sample;
          my $epoch_new  = str2time($timestamp);
          my $epoch_diff = $epoch_new - $epoch_prev if ( $epoch_prev ne "" );
          $epoch_prev = $epoch_new;
          my $new_ts = tsToPerffileFormat( $timestamp, 1 );
          if ( !defined $epoch_diff || $epoch_diff eq "" || $epoch_diff == 0 ) { next; }
          my $numberOfReads_vfchost = 0;
          my $physicalLocation      = $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{physicalLocation};
          my $numOfReadsG           = ( $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{numOfReads} - $numOfReads ) / $epoch_diff;
          my $numOfWritesG          = ( $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{numOfWrites} - $numOfWrites ) / $epoch_diff;
          my $readBytesG            = ( $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{readBytes} - $readBytes ) / $epoch_diff;
          my $writeBytesG           = ( $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{writeBytes} - $writeBytes ) / $epoch_diff;
          my $runningSpeedG         = ( $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{runningSpeed} - $runningSpeed ) / $epoch_diff;
          my $wwpn                  = $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{wwpn};

          if ( $tst == 0 ) {
            push( @{$arr_ts_sample}, $new_ts );
            push( @{$arr_ts_sample}, $san_name );
            push( @{$arr_ts_sample}, $adapter_id );

            push( @{$arr_ts_sample}, $physicalLocation );

            #$reversed_san->{$new_ts}{$san_name}{$adapter_id}{physicalLocation} = $physicalLocation;

            push( @{$arr_ts_sample}, $numOfReadsG );

            #$reversed_san->{$new_ts}{$san_name}{$adapter_id}{numOfReadsG} = $numOfReadsG;

            push( @{$arr_ts_sample}, $numOfWritesG );

            #$reversed_san->{$new_ts}{$san_name}{$adapter_id}{numOfWritesG} = $numOfWritesG;

            push( @{$arr_ts_sample}, $readBytesG / 1024 );

            #$reversed_san->{$new_ts}{$san_name}{$adapter_id}{readBytesG} = $readBytesG/1024;

            push( @{$arr_ts_sample}, $writeBytesG / 1024 );

            #$reversed_san->{$new_ts}{$san_name}{$adapter_id}{writeBytesG} = $writeBytesG/1024;

            push( @{$arr_ts_sample}, $runningSpeedG );

            #$reversed_san->{$new_ts}{$san_name}{$adapter_id}{runningSpeedG} = $runningSpeedG;

            push( @{$arr_ts_sample}, $wwpn );

            #$reversed_san->{$new_ts}{$san_name}{$adapter_id}{wwpn} = $wwpn;

            ( undef, undef, my $location_without_prefix ) = split( '\.', $physicalLocation );
            if (!defined $location_without_prefix ) { $location_without_prefix = ""; }
            $san_aliases->{$location_without_prefix}{partition} = $san_name;
            $san_aliases->{$location_without_prefix}{UUID}      = PowerDataWrapper::md5_string($physicalLocation);
            $san_aliases->{$location_without_prefix}{alias}     = $adapter_id;
            $san_aliases->{$location_without_prefix}{wwpn}      = $wwpn;
          }
          push( @{$arr_formated_san}, $arr_ts_sample ) if defined $arr_ts_sample;
          $numOfReads   = $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{numOfReads};
          $numOfWrites  = $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{numOfWrites};
          $writeBytes   = $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{writeBytes};
          $readBytes    = $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{readBytes};
          $runningSpeed = $fiberChannelAdapters->{$san_name}{$adapter_id}{$timestamp}{runningSpeed};
          $tst          = 0;
        }
      }
    }
    $reversed_san = $arr_formated_san;
    if ( defined $ENV{HMC_JSONS} ) {
      if ( $ENV{HMC_JSONS} == 1 ) {

        #Xorux_lib::write_json("$performance_folder/iostat/HMC_$host"."_san_perf_$act_ts.json", $reversed_san) if defined $reversed_san;
        #Xorux_lib::write_json("$performance_folder/SAN_aliases.json", $san_aliases) if defined $san_aliases;
        check_and_write( "$performance_folder/iostat/HMC_$host" . "_san_perf_$act_ts.json", $reversed_san, 0 );
        check_and_write( "$performance_folder/SAN_aliases.json",                            $san_aliases,  0 );
      }
    }

    #Physical Generic Adapters
    my $arr_formated_sas;
    foreach my $gpa_name ( keys %{$genericPhysicalAdapters} ) {
      foreach my $adapter_id ( keys %{ $genericPhysicalAdapters->{$gpa_name} } ) {

        #if ( $adapter_id =~ m/fscsi/ ) {next;} #this is shown in general physical adapters san  and it's same as generic adapters in lan ===> may not be true
        my $writeBytes  = 0;
        my $readBytes   = 0;
        my $numOfReads  = 0;
        my $numOfWrites = 0;
        my $tst         = 1;
        my $epoch_prev  = "";
        foreach my $timestamp ( sort keys %{ $genericPhysicalAdapters->{$gpa_name}{$adapter_id} } ) {
          my $epoch_new  = str2time($timestamp);
          my $epoch_diff = $epoch_new - $epoch_prev if ( $epoch_prev ne "" );
          $epoch_prev = $epoch_new;
          my $new_ts = tsToPerffileFormat( $timestamp, 1 );
          if ( !defined $epoch_diff || $epoch_diff eq "" || $epoch_diff == 0 ) { next; }
          my $numOfReadsG      = ( $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{numOfReads} - $numOfReads ) / $epoch_diff;
          my $numOfWritesG     = ( $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{numOfWrites} - $numOfWrites ) / $epoch_diff;
          my $readBytesG       = ( $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{readBytes} - $readBytes ) / $epoch_diff;
          my $writeBytesG      = ( $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{writeBytes} - $writeBytes ) / $epoch_diff;
          my $type             = $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{type};
          my $physicalLocation = $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{physicalLocation};

          if ( $tst == 0 ) {
            my $arr_ts_sample;
            push( @{$arr_ts_sample}, $new_ts );
            push( @{$arr_ts_sample}, $gpa_name );
            push( @{$arr_ts_sample}, $adapter_id );

            push( @{$arr_ts_sample}, $physicalLocation );

            #$reversed_gpa->{$new_ts}{$gpa_name}{$adapter_id}{physicalLocation} = $physicalLocation;

            push( @{$arr_ts_sample}, $type );

            #$reversed_gpa->{$new_ts}{$gpa_name}{$adapter_id}{type} = $type;

            push( @{$arr_ts_sample}, $numOfReadsG );

            #$reversed_gpa->{$new_ts}{$gpa_name}{$adapter_id}{numOfReadsG} = $numOfReadsG;

            push( @{$arr_ts_sample}, $numOfWritesG );

            #$reversed_gpa->{$new_ts}{$gpa_name}{$adapter_id}{numOfWritesG} = $numOfWritesG;

            push( @{$arr_ts_sample}, $readBytesG / 1024 );

            #$reversed_gpa->{$new_ts}{$gpa_name}{$adapter_id}{readBytesG} = $readBytesG/1024;

            push( @{$arr_ts_sample}, $writeBytesG / 1024 );

            #$reversed_gpa->{$new_ts}{$gpa_name}{$adapter_id}{writeBytesG} = $writeBytesG/1024;

            ( undef, undef, my $location_without_prefix ) = split( '\.', $physicalLocation );
            if (!defined $location_without_prefix ) { $location_without_prefix = ""; }
            $sas_aliases->{$location_without_prefix}{partition} = $gpa_name;
            $sas_aliases->{$location_without_prefix}{UUID}      = PowerDataWrapper::md5_string($physicalLocation);
            $sas_aliases->{$location_without_prefix}{alias}     = $adapter_id;
            push( @{$arr_formated_sas}, $arr_ts_sample );
          }
          $numOfReads  = $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{numOfReads};
          $numOfWrites = $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{numOfWrites};
          $readBytes   = $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{readBytes};
          $writeBytes  = $genericPhysicalAdapters->{$gpa_name}{$adapter_id}{$timestamp}{writeBytes};
          $tst         = 0;
        }
      }
    }
    $reversed_gpa = $arr_formated_sas;
    if ( defined $ENV{HMC_JSONS} ) {
      if ( $ENV{HMC_JSONS} == 1 ) {

        #Xorux_lib::write_json("$performance_folder/iostat/HMC_$host"."_gpa_perf_$act_ts.json", $reversed_gpa) if defined $reversed_gpa;
        #Xorux_lib::write_json("$performance_folder/SAS_aliases.json", $sas_aliases) if defined $sas_aliases;
        check_and_write( "$performance_folder/iostat/HMC_$host" . "_gpa_perf_$act_ts.json", $reversed_gpa, 0 );
        check_and_write( "$performance_folder/SAS_aliases.json",                            $sas_aliases,  0 );
      }
    }
  }
  if ( $ENV{HMC_REST_DEBUG} ) {
    close($hmc_rest_debug);
  }

  my $reversed_hea;
  if ( defined $decoded_ltmjsons ) {
    my $err_msgs;
    foreach my $timestamp ( sort keys %{$decoded_ltmjsons} ) {
      foreach my $errorInfo ( @{ $decoded_ltmjsons->{$timestamp}{systemUtil}{utilSample}{errorInfo} } ) {
        if ( defined $errorInfo->{errId} && !$err_msgs->{ $errorInfo->{errId} } ) {
          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $serverName Phyp Error: $errorInfo->{errId}: $errorInfo->{errMsg}\n";
          $err_msgs->{ $errorInfo->{errId} } = $errorInfo->{errMsg};
        }
      }
      foreach my $heAdapter ( @{ $decoded_ltmjsons->{$timestamp}{systemUtil}{utilSample}{network}{heAdapters} } ) {
        foreach my $port ( @{ $heAdapter->{'physicalPorts'} } ) {
          my $physicalLocation = $port->{physicalLocation};
          my $receivedBytes    = $port->{receivedBytes};
          my $receivedPackets  = $port->{receivedPackets};
          my $sentPackets      = $port->{sentPackets};
          my $sentBytes        = $port->{sentBytes};
          $heAdapters->{$physicalLocation}{$timestamp}{receivedBytes}   = $port->{receivedBytes};
          $heAdapters->{$physicalLocation}{$timestamp}{receivedPackets} = $port->{receivedPackets};
          $heAdapters->{$physicalLocation}{$timestamp}{sentPackets}     = $port->{sentPackets};
          $heAdapters->{$physicalLocation}{$timestamp}{sentBytes}       = $port->{sentBytes};
          $heAdapters->{$physicalLocation}{$timestamp}{droppedPackets}  = $port->{droppedPackets};
        }
      }
    }
    my $arr_formated_hea;
    foreach my $ha ( keys %{$heAdapters} ) {
      my $receivedBytes   = 0;
      my $sentBytes       = 0;
      my $receivedPackets = 0;
      my $sentPackets     = 0;
      my $tst             = 1;
      my $epoch_prev      = "";
      foreach my $ts ( sort keys %{ $heAdapters->{$ha} } ) {
        my $arr_ts_sample;
        my $epoch_new  = str2time($ts);
        my $epoch_diff = $epoch_new - $epoch_prev if ( $epoch_prev ne "" );
        $epoch_prev = $epoch_new;
        my $new_ts = tsToPerffileFormat( $ts, 1 );
        if ( !defined $epoch_diff || $epoch_diff eq "" || $epoch_diff == 0 ) { next; }
        my $receivedBytesG   = ( $heAdapters->{$ha}{$ts}{receivedBytes} - $receivedBytes ) / $epoch_diff;
        my $receivedPacketsG = ( $heAdapters->{$ha}{$ts}{receivedPackets} - $receivedPackets ) / $epoch_diff;
        my $sentBytesG       = ( $heAdapters->{$ha}{$ts}{sentBytes} - $sentBytes ) / $epoch_diff;
        my $sentPacketsG     = ( $heAdapters->{$ha}{$ts}{sentPackets} - $sentPackets ) / $epoch_diff;

        if ( $tst == 0 ) {
          push( @{$arr_ts_sample}, $new_ts );
          push( @{$arr_ts_sample}, $ha );

          push( @{$arr_ts_sample}, $receivedBytesG / 1024 );

          #$reversed_hea->{$new_ts}{$ha}{receivedBytesG} = $receivedBytesG/1024;
          push( @{$arr_ts_sample}, $receivedPacketsG );

          #$reversed_hea->{$new_ts}{$ha}{receivedPacketsG} = $receivedPacketsG;
          push( @{$arr_ts_sample}, $sentBytesG / 1024 );

          #$reversed_hea->{$new_ts}{$ha}{sentBytesG} = $sentBytesG/1024;
          push( @{$arr_ts_sample}, $sentPacketsG );

          #$reversed_hea->{$new_ts}{$ha}{sentPacketsG} = $sentPacketsG;
          push( @{$arr_formated_hea}, $arr_ts_sample );
        }
        $receivedBytes   = $heAdapters->{$ha}{$ts}{receivedBytes};
        $receivedPackets = $heAdapters->{$ha}{$ts}{receivedPackets};
        $sentBytes       = $heAdapters->{$ha}{$ts}{sentBytes};
        $sentPackets     = $heAdapters->{$ha}{$ts}{sentPackets};
        $tst             = 0;
      }
    }
    $reversed_hea = $arr_formated_hea;
  }
  if ( defined $ENV{HMC_JSONS} ) {
    if ( $ENV{HMC_JSONS} == 1 ) {

      #Xorux_lib::write_json("$performance_folder/iostat/HMC_$host"."_hea_perf_$act_ts.json", $reversed_hea) if defined $reversed_hea;
      check_and_write( "$performance_folder/iostat/HMC_$host" . "_hea_perf_$act_ts.json", $reversed_hea, 0 );
    }
  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $serverName Perffiles OK\n";
  $decoded_ltmjsons = "";
  return $lastTimeStamp;
}

# get lpars ids to analyze them
sub getLparIDs {
  my $mainServerID = shift;
  my $apicmd       = "rest/api/uom/ManagedSystem/$mainServerID";
  my $data;
  eval { $data = callAPI($apicmd); };
  if ($@) {
    print "Rest API error 1123 : $@\n";
  }
  if ( defined $data->{error} || $data eq "-1" ) {
    print "cannot retrieve data from server with ID:$mainServerID\n";
    return -1;
  }
  my $array = $data->{'content'}{'ManagedSystem:ManagedSystem'}{'AssociatedLogicalPartitions'}{"link"};
  return $array;
}

#if not opened session yet, this will authorize client and save session to file.
sub getSession {
  my $error;
  my $url;
  $url = $proto . '://' . $host . ':' . $port . '/rest/api/web/Logon';
  $url = $proto . '://' . $host . '/rest/api/web/Logon' if $exclude_hmc_port;
  my $token = <<_REQUEST_;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<LogonRequest xmlns="http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/" schemaVersion="V1_0">
  <UserID kb="CUR" kxe="false">$login_id</UserID>
  <Password kb="CUR" kxe="false">$login_pwd</Password>
</LogonRequest>
_REQUEST_
  my $req = HTTP::Request->new( PUT => $url );
  $req->content_type('application/vnd.ibm.powervm.web+xml');
  $req->content_length( length($token) );
  $req->header( 'Accept' => '*/*' );
  $req->content($token);
  my $response = $browser->request($req);

  if ( $response->is_success ) {
    my $ref     = XMLin( $response->content );
    my $session = $ref->{'X-API-Session'}{content};
    if ( $session eq "" ) {
      error( "Invalid session" . " File: " . __FILE__ . ":" . __LINE__ );
      return -1;
    }
    else {
      my $fh;
      if ( open( $fh, ">", "$sessionFile" ) ) {
        print $fh $session;
        close($fh);
        return $session;
      }
      else {
        error( "Cannot create $sessionFile and store session. Logging off and returning." . " File: " . __FILE__ . ":" . __LINE__ );
        sleep(1);
        logoff( $session, $sessionFile );
        return 1;
      }
    }
  }
  else {
    my $error_body = XMLin( $response->content );
    if ( defined $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'} ) {

      #error ("! Rest API  :  Cannot get session!!\n! Error : $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'} : $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'Message'}{'content'}\n! $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'ReasonCode'}{'content'}\n! HMC $host will not be shown in data.\n");
      if ( $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'} eq "500" ) {

        #error ("! Rest API is supported since HMC V8, if you're using older HMC, swich to SSH CLI in Web->Setting->IBM Power Systems in this HMC:$host\n");
      }
      print("! Rest API  :  Cannot get session!!\n! Error : $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'} : $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'Message'}{'content'}\n! $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'ReasonCode'}{'content'}\n! HMC $host will not be shown in data.\n");
      if ( $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'} eq "500" ) {
        print("! Rest API is supported since HMC v8. Swich to HMC CLI (SSH) option on older HMC in Web->Setting->IBM Power Systems in this HMC:$host\n");
      }
      print "\n";
    }
    if ( $response->{_msg} =~ m/negotiation failed/ ) {
      print "API Error: See http://www.lpar2rrd.com/https.htm to resolve problem\n";
    }
    $error_body = XMLin( $response->content );
    if ( defined $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'} ) {

      #error ("! Rest API  :  Cannot get session!!\n! Error : $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'} : $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'Message'}{'content'}\n! $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'ReasonCode'}{'content'}\n! HMC $host will not be shown in data.\n");
      if ( $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'} eq "500" ) {

        #error ("! Rest API is supported since HMC V8, if you're using older HMC, swich to SSH CLI in Web->Setting->IBM Power Systems in this HMC:$host\n");
      }
      print("! Rest API  :  Cannot get session!!\n! Error : $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'} : $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'Message'}{'content'}\n! $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'ReasonCode'}{'content'}\n! HMC $host will not be shown in data.\n");
      if ( $error_body->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'} eq "500" ) {
        print("! Rest API is supported since HMC v8. Swich to HMC CLI (SSH) option on older HMC in Web->Setting->IBM Power Systems in this HMC:$host\n");
      }
      print "\n";
      exit;
    }
    print "API Error: $response->{_rc} $response->{_msg}\n";
    print "API Error: $response->{_content}\n";
    return $error_body;
  }
}

# gets xml from rest api command and returns it
sub callAPI {
  my $url = shift;
  my $output_hash = {};
  my $error;
  if ( !defined $url || $url eq "" ) {
    print "No url given to callAPI()\n";
    return {};
  }
  if ($exclude_hmc_port) {
    if    ( $url =~ /^rest/ )   { $url = "$proto://$host/$url"; }
    elsif ( $url =~ /^\/rest/ ) { $url = "$proto://$host" . $url; }
    else                        { $url = $url; }
  }
  else {
    if    ( $url =~ /^rest/ )   { $url = "$proto://$host:$port/$url"; }
    elsif ( $url =~ /^\/rest/ ) { $url = "$proto://$host:$port" . $url; }
    else                        { $url = $url; }
  }
  my $data;
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : * start callAPI $url\n";
  my $req = HTTP::Request->new( GET => $url );
  $req->content_type('application/xml');
  $req->header( 'Accept'        => '*/*' );
  $req->header( 'X-API-Session' => $APISession );
  $data = $browser->request($req);

  if ( $data->is_success ) {
    if ( $data->{_content} eq "" ) {
      print( "Rest API !     " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : No HMC Data for $url" . " File: " . __FILE__ . ":" . __LINE__ . "\n" );
      print Dumper $data;
      return {};
    }
    else {
      eval {
        my $out = XMLin( $data->content );
        $output_hash = $out;
      };
      if ($@) {
        print "Corrupted XML on $url:\nCorrupted XML content:\n";
        print Dumper $data->content;
        return { "corrupted_xml" => $data->content };
      }
    }
  }
  else {
    print( "API Error (general) at $host at $url" . " File: " . __FILE__ . ":" . __LINE__ . "\n" );

    # there are some error messages, we can compare and give a solution when they appear.
    #if ($data->{_content} =~ m/*matches this pattern/){}

    #1 This is really important setting. Our user is not able to get data through http(s) protocol without this permission, which Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "  needs.
    if ( $data->{_content} =~ m/user does not have the role authority to perform the request/ ) {
      error( "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host : $url : IMPORTANT SETTINGS: Allow remote access via the web : GUI --> Manage User Profiles and Access --> select lpar2rrd --> modify --> user properties --> Allow remote access via the web" . " File: " . __FILE__ . ":" . __LINE__ );
      return -1;
    }

    #2 some hmc problem appeard, ssh works, Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "  and Management Console not in all cases, just performace shows problems.. SRVE0190E
    elsif ( $data->{_content} =~ m/FileNotFoundException/ && $data->{_content} =~ m/SRVE0190E/ ) {
      print "******* WARNING *******\n";
      print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host : $data->{_content}";
      print "******* WARNING *******\n";
      error( $data->{_content} . " File: " . __FILE__ . ":" . __LINE__ );
      return -1;
    }

    #3 bug in vios firmware, use IBM support link to resolve issue
    elsif ( $data->{_content} =~ m/Error occurred while querying for VirtualMediaRepository/ ) {
      my $x = XMLin( $data->content );
      print "Error $host $x->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'}:$x->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'ReasonCode'}{'content'}:$x->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'Message'}{'content'}\nat $url\n";
      print "To resolve issue: http://www-01.ibm.com/support/docview.wss?uid=isg3T1024482\n";
      return -1;
    }
    elsif ( $data->{_content} =~ m/MC has just restarted or UUID not found in PCM. Try again after sometime/ ) {
      my $x = XMLin( $data->content );
      print "Error $host $x->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'}:$x->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'ReasonCode'}{'content'}:$x->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'Message'}{'content'}\nat $url\n";
      print "Some services are not running. Ask support about this issue\n";
      return -1;
    }

    #elsif ($data->{_content} =~ m/*matches this pattern/){}
    #elsif ($data->{_content} =~ m/*matches this pattern/){}
    #elsif ($data->{_content} =~ m/*matches this pattern/){}
    #elsif ($data->{_content} =~ m/*matches this pattern/){}
    #elsif ($data->{_content} =~ m/*matches this pattern/){}
    #elsif ($data->{_content} =~ m/*matches this pattern/){}
    #elsif ($data->{_content} =~ m/*matches this pattern/){}
    #elsif ($data->{_content} =~ m/*matches this pattern/){}
    #elsif ($data->{_content} =~ m/*matches this pattern/){}
    else {
      eval {
        my $data_hash = XMLin( $data->content );
      };
      if ($@){
        print "Error when trying to convert XML data to json. Data:\n";
        print Dumper $data->content;
      }
=begin
      print "Not success at $url\n";
      print Dumper $data_hash;
      if ( !defined $data_hash ) {
        return -1;
      }
      if ( defined $data_hash->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'} || defined $data_hash->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'Message'}{'content'} ) {
        error( "$data_hash->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'HTTPStatus'}{'content'}:$data_hash->{'content'}{'HttpErrorResponse:HttpErrorResponse'}{'Message'}{'content'}" . " File: " . __FILE__ . ":" . __LINE__ );
      }
      return $data_hash;
=cut
    }
  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : ->  end callAPI $url\n";
  return $output_hash;
}

# expects rest api url "https://ip:port/RESTAPICMD" or  "/RESTAPICMD" or  "RESTAPICMD"
# Example: "https://1.1.1.1:12443/rest/api/pcm/ManagedSystem/"
# Example: "/rest/api/pcm/ManagedSystem/"
# Example: "rest/api/pcm/ManagedSystem/"
# then gets json from href to json and returns it. Its probably decoded to hash right after this function is called
sub callAPIjson {
  my $url = shift;
  my $error;
  my $out = {};
  if ($exclude_hmc_port) {
    if    ( $url =~ /^rest/ )   { $url = "$proto://$host/$url"; }
    elsif ( $url =~ /^\/rest/ ) { $url = "$proto://$host" . $url; }
  }
  else {
    if    ( $url =~ /^rest/ )   { $url = "$proto://$host:$port/$url"; }
    elsif ( $url =~ /^\/rest/ ) { $url = "$proto://$host:$port" . $url; }
  }
  my $req = HTTP::Request->new( GET => $url );
  $req->content_type('application/json');
  $req->header( 'Accept'        => '*/*' );
  $req->header( 'X-API-Session' => $APISession );
  my $data = $browser->request($req);
  if ( !$data->is_success ) {

    #error("sub callAPIjson error at $url" .  " File: ".__FILE__.":".__LINE__);
    return {};
  }
  eval {
    my $decoded = ( decode_json( $data->content ) );
    $out = $decoded if ( defined $decoded );
  };
  if ($@) {
    error( "Error when decoding json : $@ : $data->content" . " File: " . __FILE__ . ":" . __LINE__ );

    #next;
    return {};
  }
  return $out;
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);
  print STDERR "$act_time $text\n";
  return 1;
}

sub LTMdata {
  my $uid_server = shift;
  my $serverName = shift;
  ( my $decoded_jsons, my $decvios ) = ( $DATA->{jsons}{$uid_server}, $DATA->{vios}{$uid_server} );
  my $prefs_lpars;
  my $out;
  my $arr_formated_perffile;
  my $sriovhash;
  my $sriovPhysicalPorts;
  my $test           = 0;
  my $ts_from_file   = getPreviousTimeStamp();
  my $firstTimeStamp = $ts_from_file;
  my $lastTimeStamp;
  my $ts_counter                   = 0;
  my $new_ts_counter               = 0;
  my $previous_timestamp_processed = "";
  my $test_json_create             = 1;
  my $sriov_aliases;
  my $performance_folder = "$env_dir/$serverName";
  my $CONFIG             = {};
  my $CONFIG_path        = "$performance_folder/$host/CONFIG.json";
  $CONFIG = Xorux_lib::read_json($CONFIG_path) if ( -f $CONFIG_path );
  my $CONFIG_lpars;
  $CONFIG_lpars = $CONFIG->{lpar} if ( defined $CONFIG->{lpar} );
  my $restricted_lpars = giveMeRestrictedLpars($CONFIG);

  if ( !defined $decoded_jsons || $decoded_jsons eq "-1" ) {
    error( "No data in \$decoded_jsons for $serverName. ($host) Probably LongTermMonitor is off. Maybe incorrect timezone???" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
  }
  foreach my $timeStamp ( sort keys %{$decoded_jsons} ) {
    my $new_ts = tsToPerffileFormat( $timeStamp, 0 );
    if ( $timeStamp ne "" ) {
      $lastTimeStamp = $timeStamp;
    }
    else {
      print "last timestamp is not defined\n";
    }
    if ( $debug eq "1" ) {
      print "TS-actually-processed:$timeStamp\n";
    }
    $ts_counter++;
    if ( defined 1 ) {
      $new_ts_counter++;
      if ( $test == 0 ) {
        $firstTimeStamp = $timeStamp;
        $test++;
      }
      my $ts = $decoded_jsons->{$timeStamp}{systemUtil}{utilSample}{timeStamp};

      #LPARSUTIL - data for each logical Partition, cpu, memory, adapters
      foreach my $item ( @{ $decoded_jsons->{$timeStamp}{systemUtil}{utilSample}{lparsUtil} } ) {
        my $act_ts_sample;
        my $lparName = $item->{name};
        if ( !( $restricted_lpars->{$lparName}{available} ) && !( defined $restricted_lpars->{error_in_loading_lpars} ) ) {
          if ($restricted_role_applied) {
            print "skipping lpar with no permission\n";
            next;
          }
        }
        my $fcsPhysLocForLpar;

        #Store the information which SR-IOV Logical Port belongs to which Logical Partition
        if ( defined $item->{'network'}{'sriovLogicalPorts'} ) {
          foreach my $logport ( @{ $item->{'network'}{'sriovLogicalPorts'} } ) {
            ( undef, undef, my $shortLoc ) = split( '\.', $logport->{physicalLocation} );
            $sriov_aliases->{$shortLoc} = $lparName;
          }
        }

        #Performance data LPAR
        push( @{$act_ts_sample}, $new_ts );
        push( @{$act_ts_sample}, $lparName );

        push( @{$act_ts_sample}, $item->{processor}{donatedProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{utilizedCappedProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{utilizedUnCappedProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{entitledProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{idleProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{mode} );
        push( @{$act_ts_sample}, $item->{processor}{maxVirtualProcessors} );
        push( @{$act_ts_sample}, $item->{processor}{maxProcUnits} );
        push( @{$act_ts_sample}, $item->{memory}{backedPhysicalMem} );
        push( @{$act_ts_sample}, $item->{memory}{logicalMem} );
        push( @{$act_ts_sample}, $item->{memory}{mappedIOMem} );

        if ( ref($CONFIG_lpars) eq "HASH" ) {
          my $curr_proc_units;
          $curr_proc_units = $CONFIG_lpars->{$lparName}{CurrentProcessingUnits};
          $curr_proc_units = $CONFIG_lpars->{$lparName}{CurrentProcessors} if ( !defined $CONFIG_lpars->{$lparName}{CurrentProcessingUnits} );
          $curr_proc_units = $CONFIG_lpars->{$lparName}{DesiredProcessingUnits} if ( !defined $CONFIG_lpars->{$lparName}{CurrentProcessingUnits} && !defined $CONFIG_lpars->{$lparName}{CurrentProcessors} );

          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{CurrentMemory} );
          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{CurrentProcessingUnits} );
          push( @{$act_ts_sample}, $curr_proc_units );
          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{CurrentProcessors} );
          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{SharingMode} );
          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{AllocatedVirtualProcessors} );
        }

        #SR-IOV assigned to Logical Partitions
        my $sriovLogicalPorts = $item->{'network'}{'sriovLogicalPorts'};
        if ( defined $sriovLogicalPorts && $sriovLogicalPorts ne "" ) {
          if ( ref($sriovLogicalPorts) eq "ARRAY" ) {
            foreach my $sriovPort ( @{$sriovLogicalPorts} ) {
              my $sriovPhysicalLocation = $sriovPort->{physicalLocation};
              if ( defined $sriovPort->{'configurationType'} )      { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{configurationType}      = $sriovPort->{'configurationType'}; }
              if ( defined $sriovPort->{'drcIndex'} )               { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{drcIndex}               = $sriovPort->{'drcIndex'}; }
              if ( defined $sriovPort->{'droppedReceivedPackets'} ) { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{droppedReceivedPackets} = $sriovPort->{'droppedReceivedPackets'}; }
              if ( defined $sriovPort->{'droppedSentPackets'} )     { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{droppedSentPackets}     = $sriovPort->{'droppedSentPackets'}; }
              if ( defined $sriovPort->{'errorIn'} )                { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{errorIn}                = $sriovPort->{'errorIn'}; }
              if ( defined $sriovPort->{'errorOut'} )               { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{errorOut}               = $sriovPort->{'errorOut'}; }
              if ( defined $sriovPort->{'physicalDrcIndex'} )       { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{physicalDrcIndex}       = $sriovPort->{'physicalDrcIndex'}; }
              if ( defined $sriovPort->{'physicalPortId'} )         { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{physicalPortId}         = $sriovPort->{'physicalPortId'}; }
              if ( defined $sriovPort->{'receivedBytes'} )          { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{receivedBytes}          = $sriovPort->{'receivedBytes'}; }
              if ( defined $sriovPort->{'receivedPackets'} )        { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{receivedPackets}        = $sriovPort->{'receivedPackets'}; }
              if ( defined $sriovPort->{'sentBytes'} )              { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{sentBytes}              = $sriovPort->{'sentBytes'}; }
              if ( defined $sriovPort->{'sentPackets'} )            { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{sentPackets}            = $sriovPort->{'sentPackets'}; }
              if ( defined $sriovPort->{'vnicDeviceMode'} )         { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{vnicDeviceMode}         = $sriovPort->{'vnicDeviceMode'}; }
            }
          }    #end if SRIOV is array
          elsif ( ref($sriovLogicalPorts) eq "HASH" ) {    #just in case of unexpected situation
            print "SRIOV port in hash - different form than expected\n";
            print Dumper $sriovLogicalPorts;
          }
          else {                                           # just in case of unexpected situation
            print "SRIOV is in different form than expected\n";
            print Dumper $sriovLogicalPorts;
          }
        }    #end if defined $sriovLogicalPorts
        push( @{$arr_formated_perffile}, $act_ts_sample );
      }    #end foreach my $item in lparsutil

      #VIOSUTIL - data for each vios Partition, cpu, memory, adapters
      foreach my $item ( @{ $decoded_jsons->{$timeStamp}{systemUtil}{utilSample}{viosUtil} } ) {
        my $act_ts_sample;
        my $lparName = $item->{name};
        my $lparId   = $item->{uuid};
        if ( !( $restricted_lpars->{$lparName}{available} ) && !( defined $restricted_lpars->{error_in_loading_lpars} ) ) {
          if ($restricted_role_applied) {
            print "skipping lpar with no permission\n";
            next;
          }
        }
        if ( defined $item->{network}{sriovLogicalPorts} ) {
          foreach my $sriovPort ( @{ $item->{network}{sriovLogicalPorts} } ) {
            my $sriovPhysicalLocation = $sriovPort->{physicalLocation};
            my $lparId                = "";
            if ( defined $sriovPort->{'clientPartitionUUID'} ) {
              $lparId = $sriovPort->{'clientPartitionUUID'};
            }
            my $lparName;
            if ( defined $lparId && $lparId ne "" ) {
              $lparName = find_lpar_name_from_uuid( $lparId, $CONFIG );
            }
            else {
              #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : not defined clientPartitionUUID for $sriovPhysicalLocation\n";
              #next;
              $lparName = "not_assigned";
            }
            ( undef, undef, my $shortLoc ) = split( '\.', $sriovPort->{physicalLocation} );
            $sriov_aliases->{$shortLoc} = $lparName;
            if ( defined $sriovPort->{'configurationType'} )      { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{configurationType}      = $sriovPort->{'configurationType'}; }
            if ( defined $sriovPort->{'drcIndex'} )               { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{drcIndex}               = $sriovPort->{'drcIndex'}; }
            if ( defined $sriovPort->{'droppedReceivedPackets'} ) { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{droppedReceivedPackets} = $sriovPort->{'droppedReceivedPackets'}; }
            if ( defined $sriovPort->{'droppedSentPackets'} )     { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{droppedSentPackets}     = $sriovPort->{'droppedSentPackets'}; }
            if ( defined $sriovPort->{'errorIn'} )                { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{errorIn}                = $sriovPort->{'errorIn'}; }
            if ( defined $sriovPort->{'errorOut'} )               { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{errorOut}               = $sriovPort->{'errorOut'}; }
            if ( defined $sriovPort->{'physicalDrcIndex'} )       { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{physicalDrcIndex}       = $sriovPort->{'physicalDrcIndex'}; }
            if ( defined $sriovPort->{'physicalPortId'} )         { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{physicalPortId}         = $sriovPort->{'physicalPortId'}; }
            if ( defined $sriovPort->{'receivedBytes'} )          { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{receivedBytes}          = $sriovPort->{'receivedBytes'}; }
            if ( defined $sriovPort->{'receivedPackets'} )        { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{receivedPackets}        = $sriovPort->{'receivedPackets'}; }
            if ( defined $sriovPort->{'sentBytes'} )              { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{sentBytes}              = $sriovPort->{'sentBytes'}; }
            if ( defined $sriovPort->{'sentPackets'} )            { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{sentPackets}            = $sriovPort->{'sentPackets'}; }
            if ( defined $sriovPort->{'vnicDeviceMode'} )         { $sriovhash->{$lparName}{$sriovPhysicalLocation}{$timeStamp}{vnicDeviceMode}         = $sriovPort->{'vnicDeviceMode'}; }
          }
        }

        #Performance data VIOS
        push( @{$act_ts_sample}, $new_ts );
        push( @{$act_ts_sample}, $lparName );

        push( @{$act_ts_sample}, $item->{processor}{donatedProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{utilizedCappedProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{utilizedUnCappedProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{entitledProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{idleProcCycles} );
        push( @{$act_ts_sample}, $item->{processor}{mode} );
        push( @{$act_ts_sample}, $item->{processor}{maxVirtualProcessors} );
        push( @{$act_ts_sample}, $item->{processor}{maxProcUnits} );
        push( @{$act_ts_sample}, $item->{memory}{backedPhysicalMem} );
        push( @{$act_ts_sample}, $item->{memory}{logicalMem} );
        push( @{$act_ts_sample}, $item->{memory}{mappedIOMem} );

        if ( ref($CONFIG_lpars) eq "HASH" ) {
          my $curr_proc_units;
          $curr_proc_units = $CONFIG_lpars->{$lparName}{CurrentProcessingUnits};
          $curr_proc_units = $CONFIG_lpars->{$lparName}{CurrentProcessors} if ( !defined $CONFIG_lpars->{$lparName}{CurrentProcessingUnits} );
          $curr_proc_units = $CONFIG_lpars->{$lparName}{DesiredProcessingUnits} if ( !defined $CONFIG_lpars->{$lparName}{CurrentProcessingUnits} && !defined $CONFIG_lpars->{$lparName}{CurrentProcessors} );
          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{CurrentMemory} );
          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{CurrentProcessingUnits} );
          push( @{$act_ts_sample}, $curr_proc_units );
          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{CurrentProcessors} );
          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{SharingMode} );
          push( @{$act_ts_sample}, $CONFIG_lpars->{$lparName}{AllocatedVirtualProcessors} );
        }
        push( @{$arr_formated_perffile}, $act_ts_sample );
      }    #end foreach my $item in viosutil

    }
    $previous_timestamp_processed = $timeStamp;
  }

  #Xorux_lib::write_json("$performance_folder/$host/sriov_aliases.json", $sriov_aliases) if defined $sriov_aliases;
  check_and_write( "$performance_folder/$host/sriov_aliases.json", $sriov_aliases, 0 );
  $out = $arr_formated_perffile;
  if ( !defined $out ) {
    print "error, hash has not been created totalTS:$ts_counter\tnewTS:$new_ts_counter\n";
  }
  return ( $out, $sriovhash, $firstTimeStamp, $lastTimeStamp );
}

sub list_config {
  my $in  = shift;
  my $par = shift;
  my $hash_conf;
  if ( $par eq "profile_conf" ) {
    my @out;
    my $tmp;
    $tmp = subprint_conf($in);
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    foreach my $o (@out) {
      my $profileName = $in->{'ProfileName'}{'content'};
      foreach my $metric ( keys %{$o} ) {
        $hash_conf->{$profileName}{$metric} = $o->{$metric};
      }
    }
  }
  if ( $par eq "shared_pools" ) {
    foreach my $shp_id ( keys %{$in} ) {
      foreach my $metric ( sort keys %{ $in->{$shp_id} } ) {
        $hash_conf->{sharedPool}{$metric} = $in->{$shp_id}{$metric};
      }
    }
    print "\n";
  }
  if ( $par eq "lpar_conf" ) {
    my $lpar_name = $in->{'PartitionName'}{'content'};
    my $lpar_id   = $in->{'PartitionID'}{'content'};
    my @out;
    my $tmp;
    $tmp = subprint_conf($in);
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{AssociatedManagedSystem} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionProcessorConfiguration} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionMemoryConfiguration} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{ProcessorPool} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionCapabilities} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionIOConfiguration} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{TaggedIO} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionMemoryConfiguration} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionProcessorConfiguration} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionProcessorConfiguration}{CurrentSharedProcessorConfiguration} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionProcessorConfiguration}{SharedProcessorConfiguration} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionProcessorConfiguration}{CurrentDedicatedProcessorConfiguration} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionProcessorConfiguration}{DedicatedProcessorConfiguration} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }
    $tmp = subprint_conf( $in->{PartitionProfiles} );
    if ( ref($tmp) eq "HASH" && $tmp ne "" && $tmp ne "-1" ) { push( @out, $tmp ); }

    foreach my $o (@out) {
      foreach my $metric ( keys %{$o} ) {
        $hash_conf->{$metric} = $o->{$metric};
      }
    }
  }
  if ( $par eq "lpars" ) {
    foreach my $lpar_id ( keys %{$in} ) {
      my $lpar_name = $in->{$lpar_id}{PartitionName};
      foreach my $metric ( sort keys %{ $in->{$lpar_id} } ) {
        $hash_conf->{$lpar_name}{$metric} = $in->{$lpar_id}{$metric};
      }
    }
  }
  if ( $par eq "server" ) {
    foreach my $key ( sort keys %{$in} ) {
      if ( $key eq "Atom" || $key eq "link" || $key eq "Metadata" ) {
        next;
      }
      eval {
        if ( defined $in->{$key}{content} ) {
          $hash_conf->{$key} = $in->{$key}{content};
        }
      };
      if ( defined $in->{$key} && ref( $in->{$key} ) eq "HASH" ) {
        foreach my $key2 ( sort keys %{ $in->{$key} } ) {
          eval {
            if ( ref( $in->{$key}{$key2} ) eq "HASH" && defined $in->{$key}{$key2}{content} ) {
              $hash_conf->{$key2} = $in->{$key}{$key2}{content};
            }
          };
        }
      }
    }
  }
  return $hash_conf;
}

sub create_cpu_cfg {

  my $item;
  $item->{PartitionName} = "lpar_name";

  #$item->{} = "lpar_id=2"
  $item->{SharedProcessorPoolID} = "pend_shared_proc_pool_id";

  #$item->{} = "curr_shared_proc_pool_name"
  $item->{currentProcessorMode}            = "curr_proc_mode";
  $item->{MinimumProcessingUnits}          = "curr_min_proc_units";
  $item->{DesiredProcessingUnits}          = "curr_proc_units";
  $item->{CurrentMaximumProcessingUnits}   = "curr_max_proc_units";
  $item->{CurrentMinimumVirtualProcessors} = "curr_min_procs";
  $item->{AllocatedVirtualProcessors}      = "curr_procs";
  $item->{CurrentMaximumVirtualProcessors} = "curr_max_procs";
  $item->{CurrentSharingMode}              = "curr_sharing_mode";
  $item->{CurrentUncappedWeight}           = "curr_uncap_weight";

  #$item->{} = "pend_shared_proc_pool_id";
  #$item->{} = "pend_shared_proc_pool_name";
  $item->{pendingProcessorMode}            = "pend_proc_mode";
  $item->{CurrentMinimumProcessingUnits}   = "pend_min_proc_units";
  $item->{CurrentProcessingUnits}          = "pend_proc_units";
  $item->{CurrentMaximumProcessingUnits}   = "pend_max_proc_units";
  $item->{CurrentMinimumVirtualProcessors} = "pend_min_procs";
  $item->{DesiredVirtualProcessors}        = "pend_procs";
  $item->{MaximumVirtualProcessors}        = "pend_max_procs";
  $item->{SharingMode}                     = "pend_sharing_mode";
  $item->{UncappedWeight}                  = "pend_uncap_weight";
  $item->{RuntimeProcessingUnits}          = "run_proc_units";
  $item->{RunProcessors}                   = "run_procs";
  $item->{RuntimeUncappedWeight}           = "run_uncap_weight";
  $item->{PartitionID}                     = "lpar_id";

  my $uid     = shift;    #rest api server UUID
  my $name    = shift;    #server name
  my $cfgpath = shift;
  my $config  = shift;
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : create cpu cfg $name $cfgpath\n";
  open( my $cfg, ">", "$cfgpath-tmp" ) || error( "Cannot open $cfgpath-tmp" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
  my $hmc_time = "";
  $hmc_time = $config->{info}{1}{hmc_time} if ( defined $config->{info}{1}{hmc_time} );
  my $lpars = {};
  $lpars = $config->{lpar} if ( defined $config->{lpar} );

  foreach my $lpar_name ( keys %{$lpars} ) {
    my $lpar_name_file = $lpar_name;
    $lpar_name_file =~ s/\//\&\&1/g;
    open( my $cfg_lpar, ">", "$cfgpath-$lpar_name_file-tmp" ) || error( "Cannot open $cfgpath-$lpar_name_file-tmp" . " File: " . __FILE__ . ":" . __LINE__ ) && next;
    my $curr_proc_mode = "";
    my $pend_proc_mode = "";
    my $c              = $lpars->{$lpar_name};
    if ( defined $c->{CurrentSharedProcessorPoolID} ) {
      $curr_proc_mode = "shared";
      $pend_proc_mode = "shared";
    }
    else {
      $curr_proc_mode = "ded";
      $pend_proc_mode = "ded";
    }
    my $PartitionID                     = "null";
    my $SharedProcessorPoolID           = "null";
    my $MinimumProcessingUnits          = "null";
    my $DesiredProcessingUnits          = "null";
    my $CurrentMaximumProcessingUnits   = "null";
    my $AllocatedVirtualProcessors      = "null";
    my $CurrentMaximumVirtualProcessors = "null";
    my $CurrentMinimumVirtualProcessors = "null";
    my $DesiredVirtualProcessors        = "null";
    my $MaximumVirtualProcessors        = "null";
    my $MinimumVirtualProcessors        = "null";
    my $CurrentSharingMode              = "null";
    my $CurrentUncappedWeight           = "null";
    my $CurrentMinimumProcessingUnits   = "null";
    my $CurrentProcessingUnits          = "null";
    my $CurrentProcessors               = "null";
    my $SharingMode                     = "null";
    my $UncappedWeight                  = "null";
    my $RuntimeProcessingUnits          = "null";
    my $RunProcessors                   = "null";
    my $RuntimeUncappedWeight           = "null";
    if ( defined $c->{PartitionID} )                   { $PartitionID                   = $c->{PartitionID}; }
    if ( defined $c->{SharedProcessorPoolID} )         { $SharedProcessorPoolID         = $c->{SharedProcessorPoolID}; }
    if ( defined $c->{MinimumProcessingUnits} )        { $MinimumProcessingUnits        = $c->{MinimumProcessingUnits}; }
    if ( defined $c->{DesiredProcessingUnits} )        { $DesiredProcessingUnits        = $c->{DesiredProcessingUnits}; }
    if ( defined $c->{CurrentMaximumProcessingUnits} ) { $CurrentMaximumProcessingUnits = $c->{CurrentMaximumProcessingUnits}; }
    if ( defined $c->{CurrentMinimumProcessingUnits} ) { $CurrentMinimumProcessingUnits = $c->{CurrentMinimumProcessingUnits}; }

    #if (defined $c->{CurrentMaximumVirtualProcessors}){ $CurrentProcessors = $c->{CurrentMaximumVirtualProcessors};}
    #if (defined $c->{CurrentMinimumVirtualProcessors}){ $CurrentProcessors = $c->{CurrentMinimumVirtualProcessors};}
    if ( defined $c->{CurrentProcessors} )          { $CurrentProcessors = $c->{CurrentProcessors}; }
    if ( defined $c->{DesiredVirtualProcessors} )   { $CurrentProcessors = $c->{DesiredVirtualProcessors}; }
    if ( defined $c->{AllocatedVirtualProcessors} ) { $CurrentProcessors = $c->{AllocatedVirtualProcessors}; }

    #if (defined $c->{MaximumVirtualProcessors}){ $CurrentProcessors = $c->{MaximumVirtualProcessors};}
    #if (defined $c->{MinimumVirtualProcessors}){ $CurrentProcessors = $c->{MinimumVirtualProcessors};}
    if ( defined $c->{CurrentMaximumVirtualProcessors} ) { $CurrentMaximumVirtualProcessors = $c->{CurrentMaximumVirtualProcessors}; }
    if ( defined $c->{CurrentSharingMode} )              { $CurrentSharingMode              = $c->{CurrentSharingMode}; }
    if ( defined $c->{CurrentUncappedWeight} )           { $CurrentUncappedWeight           = $c->{CurrentUncappedWeight}; }
    if ( defined $c->{CurrentMinimumProcessingUnits} )   { $CurrentMinimumProcessingUnits   = $c->{CurrentMinimumProcessingUnits}; }
    if ( defined $c->{CurrentProcessingUnits} )          { $CurrentProcessingUnits          = $c->{CurrentProcessingUnits}; }
    if ( defined $c->{CurrentMaximumProcessingUnits} )   { $CurrentMaximumProcessingUnits   = $c->{CurrentMaximumProcessingUnits}; }
    if ( defined $c->{CurrentMinimumVirtualProcessors} ) { $CurrentMinimumVirtualProcessors = $c->{CurrentMinimumVirtualProcessors}; }
    if ( defined $c->{DesiredVirtualProcessors} )        { $DesiredVirtualProcessors        = $c->{DesiredVirtualProcessors}; }
    if ( defined $c->{MaximumVirtualProcessors} )        { $MaximumVirtualProcessors        = $c->{MaximumVirtualProcessors}; }
    if ( defined $c->{SharingMode} )                     { $SharingMode                     = $c->{SharingMode}; }
    if ( defined $c->{UncappedWeight} )                  { $UncappedWeight                  = $c->{UncappedWeight}; }
    if ( defined $c->{RuntimeProcessingUnits} )          { $RuntimeProcessingUnits          = $c->{RuntimeProcessingUnits}; }
    if ( defined $c->{RunProcessors} )                   { $RunProcessors                   = $c->{RunProcessors}; }
    if ( defined $c->{RuntimeUncappedWeight} )           { $RuntimeUncappedWeight           = $c->{RuntimeUncappedWeight}; }

    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : create cpu cfg $name $lpar_name : curr_procs=$CurrentProcessors curr_proc_units=$DesiredProcessingUnits\n";
    print $cfg "lpar_name=$lpar_name,lpar_id=$PartitionID,curr_shared_proc_pool_id=$SharedProcessorPoolID,curr_shared_proc_pool_name=,curr_proc_mode=$curr_proc_mode,curr_min_proc_units=$MinimumProcessingUnits,curr_proc_units=$DesiredProcessingUnits,curr_max_proc_units=$CurrentMaximumProcessingUnits,curr_min_procs=$CurrentMinimumVirtualProcessors,curr_procs=$CurrentProcessors,curr_max_procs=$CurrentMaximumVirtualProcessors,curr_sharing_mode=$CurrentSharingMode,curr_uncap_weight=$CurrentUncappedWeight,pend_shared_proc_pool_id=,pend_shared_proc_pool_name=,pend_proc_mode=$pend_proc_mode,pend_min_proc_units=$CurrentMinimumProcessingUnits,pend_proc_units=$CurrentProcessingUnits,pend_max_proc_units=$CurrentMaximumProcessingUnits,pend_min_procs=$CurrentMinimumVirtualProcessors,pend_procs=$DesiredVirtualProcessors,pend_max_procs=$MaximumVirtualProcessors,pend_sharing_mode=$SharingMode,pend_uncap_weight=$UncappedWeight,run_proc_units=$RuntimeProcessingUnits,run_procs=$RunProcessors,run_uncap_weight=$RuntimeUncappedWeight\n";

    #cpu.cfg-lpar values in array to print
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : create cpu cfg $name $lpar_name html under lpar perf graphs\n";
    my @values_in_array_to_print = ( "PartitionState", "SharedProcessorPoolName", "SharedProcessorPoolID", "CurrentProcessingUnits", "SharingMode", "CurrentUncappedWeight" );
    my $translate;
    $translate->{PartitionState}         = "state";
    $translate->{CurrentProcessorMode}   = "curr_proc_mode";
    $translate->{CurrentProcessingUnits} = "curr_proc_units";
    $translate->{SharingMode}            = "curr_sharing_mode";
    print $cfg_lpar "<B>Current CPU configuration:</B><TABLE class=\"tabconfig\">\n";

    foreach my $metric (@values_in_array_to_print) {
      my $value = $c->{$metric} || "";
      if ( defined $value ) {
        my $lnk = "";
        $lnk = "lpar2rrd-cgi/detail.sh?host=$host&server=$name&lpar=SharedPool$c->{SharedProcessorPoolID}&item=shpool" if ( defined $c->{SharedProcessorPoolID} && $c->{SharedProcessorPoolID} ne "" );
        if ( $metric eq "SharedProcessorPoolName" ) { $value = "<a href=\"/$lnk\">$c->{SharedProcessorPoolName}</a>" if ( defined $c->{SharedProcessorPoolName} && $c->{SharedProcessorPoolName} ne "" ); }
        if ( $value eq "keep idle procs" )          { $value = "keep_idle_procs"; }
        if ( $value eq "sre idle procs always" )    { $value = "share_idle_procs_always"; }

        #$value = lc $value;
        if ( defined $translate->{$metric} ) { $metric = $translate->{$metric}; }
        print $cfg_lpar "<TR><TD><font size=\"-1\">$metric</font></TD><TD><font size=\"-1\">$value</font></TD></TR>\n" if ( $value ne "" );
      }
    }
    print $cfg_lpar "<TR><TD><font size=\"-1\">curr_proc_mode</font></TD><TD><font size=\"-1\">$curr_proc_mode</font></TD></TR>\n";
    print $cfg_lpar "<TR><TD><font size=\"-1\">curr_procs</font></TD><TD><font size=\"-1\">$CurrentProcessors</font></TD></TR>\n";
    print $cfg_lpar "</TABLE>\n<font size=\"-1\">HMC time : " . $hmc_time . "</font><br><br>\n";
    close($cfg_lpar);

    #copy( , ) || error( "Cannot: cp : $!" .      __FILE__ . ":" . __LINE__ );
    copy( "$cfgpath-$lpar_name_file-tmp", "$cfgpath-$lpar_name_file" ) || error( "Cannot: cp $cfgpath-$lpar_name_file-tmp to $cfgpath-$lpar_name_file : $!" . __FILE__ . ":" . __LINE__ );
    unlink("$cfgpath-$lpar_name_file-tmp");
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : create cpu cfg html $name $lpar_name done!\n";

  }
  close($cfg);
  if ( -e "$cfgpath-tmp" ) {
    copy( "$cfgpath-tmp", "$cfgpath" ) || error( "Cannot: cp $cfgpath-tmp to $cfgpath : $!" . __FILE__ . ":" . __LINE__ );
    unlink("$cfgpath-tmp");
  }
  return 0;
}

sub create_cpu_pool_mapping {
  my $uid          = shift;    #rest api server UUID
  my $name         = shift;    #server name
  my $cfgpath_orig = shift;

  #print "DEBUG 21 - $uid, $name\n";
  eval {
    my $cfgpath_tmp = "$cfgpath_orig-tmp-" . $$;
    print "cfgpath_orig : $cfgpath_orig\n";
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : create cpu pools mapping $name $cfgpath_tmp!\n";
    open( my $cpu_pool_mapping, ">", $cfgpath_tmp ) || error( "Cannot open $cfgpath_tmp" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;

    my $conf = callAPI("rest/api/uom/ManagedSystem/$uid/SharedProcessorPool");
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : conf after API call = $conf!\n";
    print "Shared Pools Response\n";
    my $cpu_pool_mapping_json;
    if ( ref($conf) eq "HASH" && defined $conf->{entry} ) {

      #$conf->{'entry'} = {};
      print "Shared Pools Response is HASH\n";
      if ( ref( $conf->{'entry'} ne "HASH" ) ) {
        warn "Shared Pools content is not a hash : $name $uid $cfgpath_orig\n";
        warn Dumper $conf;
        return 0;
      }
      if ( scalar keys %{ $conf->{'entry'} } == 0 ) {
        warn "No shared pools, do not creating cpu pools mapping file : $name $uid $cfgpath_orig\n";

        #warn Dumper $conf;
        return 0;
      }
      foreach my $poolId ( keys %{ $conf->{'entry'} } ) {
        print "STARTED POOL ID on $name : $poolId\n";
        my $pool;
        my $shp      = $conf->{'entry'}{$poolId}{'content'}{'SharedProcessorPool:SharedProcessorPool'};
        my $poolName = $shp->{'PoolName'}{'content'};
        my $poolID   = $shp->{'PoolID'}{'content'};
        $pool->{PoolName} = $poolName;
        $pool->{PoolID}   = $poolID;
        $pool->{Max} = $shp->{'MaximumProcessingUnits'}{'content'};

        #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : processing SharedPool:$poolName $poolId on $name $host | Active? = $shp->{AssignedPartitions}\n";
        if ( $poolName ne "DefaultPool" && (!defined $shp->{AssignedPartitions} && $pool->{Max} == 0) ) {    # not active, do not have assigned partitions
          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : cpu pools mapping $name - $poolName poolID:$poolID skipping, no active partitions\n";
          next;
        }
        else {
          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : cpu pools mapping $name - $poolName poolID:$poolID add to file\n";
          print $cpu_pool_mapping "$poolID,$poolName\n";
          push( @{$cpu_pool_mapping_json}, $pool );
        }
      }
    }
    else {
      print "Rest API : SharedProcessorPool is not a hash " . __FILE__ . ":" . __LINE__ . "\n";
    }

    #Xorux_lib::write_json("$work_folder/tmp/restapi/HMC_CPU-POOLS-MAPPING_$name\_conf.json", $cpu_pool_mapping_json) if defined $cpu_pool_mapping_json;
    check_and_write( "$work_folder/tmp/restapi/HMC_CPU-POOLS-MAPPING_$name\_conf.json", $cpu_pool_mapping_json, 0 );
    close($cpu_pool_mapping);
    my $ftd_orig = Xorux_lib::file_time_diff($cfgpath_orig);
    if ( $ftd_orig >= 300 || !-e $cfgpath_orig ) {
      print "Rest API       " . "copy $cfgpath_tmp to $cfgpath_orig\n";
      copy( "$cfgpath_tmp", "$cfgpath_orig" ) || error( " Cannot mv $cfgpath_tmp to $cfgpath_orig: $!" . __FILE__ . ":" . __LINE__ ) && return;
    }
    else {
      print "cpu pools skip $cfgpath_orig\n";
    }
    unlink($cfgpath_tmp);
  };
  if ($@) {
    warn "something went wrong when creating cpu pools mapping, error:";
    warn Dumper $@;
  }

  return 0;
}

sub createCONFIGjson {
  my $config;
  my $uid        = shift;
  my $serverName = shift;
  my $path       = "$env_dir/$serverName/$host/CONFIG.json";
  my @par;
  my $out_conf;

  my $all_server_info = {};
  my $server_conf     = {};
  my $lpar_conf       = {};
  my $lpar_prof_conf  = {};
  my $shp_conf        = {};
  my $ent_pool        = {};

  $all_server_info = Xorux_lib::read_json("$work_folder/tmp/restapi/HMC_INFO_$host.json") if ( -f "$work_folder/tmp/restapi/HMC_INFO_$host.json" );
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $serverName createCONFIGjson $path!\n";
  $server_conf = Xorux_lib::read_json("$work_folder/tmp/restapi/HMC_SERVER_$serverName\_conf.json") if ( -f "$work_folder/tmp/restapi/HMC_SERVER_$serverName\_conf.json" );
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $serverName createCONFIGjson server_conf = $server_conf!\n";
  $lpar_conf = Xorux_lib::read_json("$work_folder/tmp/restapi/HMC_LPARS_$serverName\_conf.json") if ( -f "$work_folder/tmp/restapi/HMC_LPARS_$serverName\_conf.json" );
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $serverName createCONFIGjson lpar_conf = $lpar_conf!\n";
  $lpar_prof_conf = Xorux_lib::read_json("$work_folder/tmp/restapi/HMC_LPARPROFILES_$serverName\_conf.json") if ( -f "$work_folder/tmp/restapi/HMC_LPARPROFILES_$serverName\_conf.json" );
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $serverName createCONFIGjson lpar_prof_conf = $lpar_prof_conf!\n";
  $shp_conf = Xorux_lib::read_json("$work_folder/tmp/restapi/HMC_SHP_$serverName\_conf.json") if ( -f "$work_folder/tmp/restapi/HMC_SHP_$serverName\_conf.json" );
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $serverName createCONFIGjson shp_conf = $shp_conf!\n";
  $ent_pool = Xorux_lib::read_json("$work_folder/tmp/restapi/HMC_ENTERPRISE_POOL_conf.json") if ( -f "$work_folder/tmp/restapi/HMC_ENTERPRISE_POOL_conf.json" );
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $host $serverName createCONFIGjson ent_pool = $ent_pool!\n";
  $config->{info}                                = $all_server_info;
  $config->{server}                              = $server_conf;
  $config->{lpar}                                = $lpar_conf;
  $config->{lpar_profiles}                       = $lpar_prof_conf;
  $config->{shared_pools}                        = $shp_conf;
  $config->{ent_pool}                            = $ent_pool;
  $config->{server}{CurrentProcessingUnitsTotal} = 0;

  foreach my $lpar ( keys %{$lpar_conf} ) {
    my $curr_proc = 0;
    if ( $lpar_conf->{$lpar}{PartitionState} eq 'not activated' || $lpar_conf->{$lpar}{PartitionState} eq 'error' ) { next; }
    $curr_proc = $lpar_conf->{$lpar}{CurrentProcessingUnits} if ( defined $lpar_conf->{$lpar}{CurrentProcessingUnits} );
    $curr_proc = $lpar_conf->{$lpar}{CurrentProcessors}      if ( !defined $lpar_conf->{$lpar}{CurrentProcessingUnits} && defined $lpar_conf->{$lpar}{CurrentProcessors} );
    $config->{server}{CurrentProcessingUnitsTotal} += $curr_proc;
  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Curr proc units total $serverName $host = $config->{server}{CurrentProcessingUnitsTotal}\n";

  #Xorux_lib::write_json($path, $config) if defined $config;
  check_and_write( $path, $config, 0 );

  #  unlink("$work_folder/tmp/HMC_INFO_$host.json");
  #  unlink("$work_folder/tmp/HMC_SERVER_$uid\_conf.json");
  #  unlink("$work_folder/tmp/HMC_LPARS_$uid\_conf.json");
  #  unlink("$work_folder/tmp/HMC_LPARPROFILES_$uid\_conf.json");
  #  unlink("$work_folder/tmp/HMC_SHP_$uid\_conf.json");
  #  unlink("$work_folder/tmp/HMC_ENTERPRISE_POOL_conf.json");
  return $config;
}

sub config_out {

  #API provided metrics that no dot match the old names from lslparutil. Some scripts are depended on this so we keep the old names for now.
  my $dict;

  #server
  $dict->{SerialNumber}     = "serial_num";
  $dict->{PrimaryIPAddress} = "ipaddr";
  $dict->{State}            = "state";
  $dict->{DetailedState}    = "detailed_state";
  $dict->{SystemTime}       = "sys_time";

  #pool processor
  $dict->{"ConfigurableSystemProcessorUnits"}            = "configurable_sys_proc_units";
  $dict->{"CurrentAvailableSystemProcessorUnits"}        = "curr_avail_sys_proc_units";
  $dict->{"PendingAvailableSystemProcessorUnits"}        = "pend_avail_sys_proc_units";
  $dict->{"InstalledSystemProcessorUnits"}               = "installed_sys_proc_units";
  $dict->{"DeconfiguredSystemProcessorUnits"}            = "deconfig_sys_proc_units";
  $dict->{"MinimumProcessorUnitsPerVirtualProcessor"}    = "min_proc_units_per_virtual_proc";
  $dict->{"MaximumAllowedVirtualProcessorsPerPartition"} = "max_virtual_procs_per_lpar";

  #shared pools
  $dict->{"PoolName"}                       = "name";
  $dict->{"PoolID"}                         = "shared_proc_pool_id";
  $dict->{"CurrentReservedProcessingUnits"} = "curr_reserved_pool_proc_units";
  $dict->{"MaximumProcessingUnits"}         = "max_pool_proc_units";

  #memory
  $dict->{"ConfigurableSystemMemory"}     = "configurable_sys_mem";
  $dict->{"PendingAvailableSystemMemory"} = "pend_avail_sys_mem";
  $dict->{"CurrentAvailableSystemMemory"} = "curr_avail_sys_mem";
  $dict->{"InstalledSystemMemory"}        = "installed_sys_mem";
  $dict->{"DeconfiguredSystemMemory"}     = "deconfig_sys_mem";
  $dict->{"SYSTEM_FIRMWARE_MEM"}          = "sys_firmware_mem";
  $dict->{"MemoryRegionSize"}             = "mem_region_size";

  #lpars
  $dict->{"PartitionName"}                                           = "name";
  $dict->{"PartitionID"}                                             = "lpar_id";
  $dict->{"PartitionType"}                                           = "lpar_env";
  $dict->{"PartitionState"}                                          = "state";
  $dict->{"ResourceMonitoringControlOperatingSystemShutdownCapable"} = "resource_config";
  $dict->{"OperatingSystemVersion"}                                  = "os_version";
  $dict->{"LogicalSerialNumber"}                                     = "logical_serial_num";

  my $uid        = shift;
  my $serverName = shift;
  my $conf       = shift;
  my $fh         = shift;
  my @tmp_s_m    = (
    "SystemName",
    "SystemTime",
    "State",
    "SerialNumber",
    "Model",
    "MachineType",
    "WWPNPrefix",
    "SystemFirmware",
    "PrimaryIPAddress",
    "SecondaryIPAddress",
    "Hostname",
    "CapacityOnDemandProcessorCapable",
    "ConfigurableSystemProcessorUnits",
    "CurrentAvailableSystemProcessorUnits",
    "CurrentMaximumAllowedProcessorsPerPartition",
    "CurrentMaximumProcessorsPerAIXOrLinuxPartition",
    "CurrentMaximumProcessorsPerIBMiPartition",
    "CurrentMaximumProcessorsPerVirtualIOServerPartition",
    "CurrentMaximumVirtualProcessorsPerAIXOrLinuxPartition",
    "CurrentMaximumVirtualProcessorsPerIBMiPartition",
    "CurrentMaximumVirtualProcessorsPerVirtualIOServerPartition",
    "DeconfiguredSystemProcessorUnits",
    "InstalledSystemProcessorUnits",
    "LogicalPartitionProcessorCompatibilityModeCapable",
    "MaximumAllowedVirtualProcessorsPerPartition",
    "MaximumProcessorUnitsPerIBMiPartition",
    "MaximumSharedProcessorCapablePartitionID",
    "MinimumProcessorUnitsPerVirtualProcessor",
    "PendingAvailableSystemProcessorUnits",
    "ServiceProcessorAutonomicIPLCapable",
    "ServiceProcessorConcurrentMaintenanceCapable",
    "ServiceProcessorFailoverCapable",
    "ServiceProcessorFailoverEnabled",
    "ServiceProcessorFailoverReason",
    "ServiceProcessorFailoverState",
    "ServiceProcessorVersion",
    "SharedProcessorPoolCapable",
    "SharedProcessorPoolCount",
    "ActiveMemoryDeduplicationCapable",
    "ActiveMemoryExpansionCapable",
    "ActiveMemoryMirroringCapable",
    "ActiveMemorySharingCapable",
    "AllowedMemoryRegionSize",
    "CapacityOnDemandMemoryCapable",
    "ConfigurableSystemMemory",
    "ConfiguredMirroredMemory",
    "CurrentAvailableMirroredMemory",
    "CurrentAvailableSystemMemory",
    "CurrentLogicalMemoryBlockSize",
    "CurrentMemoryMirroringMode",
    "CurrentMirroredMemory",
    "DeconfiguredSystemMemory",
    "DefaultHardwarePagingTableRatioForDedicatedMemoryPartition",
    "HardwareMemoryCompressionCapable",
    "HardwareMemoryEncryptionCapable",
    "HugePageMemoryCapable",
    "HugePageMemoryOverrideCapable",
    "InstalledSystemMemory",
    "MaximumMemoryPoolCount",
    "MaximumMirroredMemoryDefragmented",
    "MaximumPagingVirtualIOServersPerSharedMemoryPool",
    "MemoryDefragmentationState",
    "MemoryMirroringCapable",
    "MemoryMirroringState",
    "MemoryRegionSize",
    "MemoryUsedByHypervisor",
    "MirrorableMemoryWithDefragmentation",
    "MirrorableMemoryWithoutDefragmentation",
    "MirroredMemoryUsedByHypervisor",
    "PendingAvailableSystemMemory",
    "PendingLogicalMemoryBlockSize",
    "PendingMemoryMirroringMode",
    "PendingMemoryRegionSize",
    "TemporaryMemoryForLogicalPartitionMobilityInUse"
  );

  if ( !( -e "$work_folder/tmp/restapi/server_detail_metrics.json" ) ) {
    check_and_write( "$work_folder/tmp/restapi/server_detail_metrics.json", \@tmp_s_m, 0 );
  }
  my $overview_server_metrics_file = "$work_folder/tmp/restapi/server_detail_metrics.json";
  my $overview_server_metrics      = {};
  my $cfg_file_path                = "$env_dir/$serverName/$host/config.html";
  my $cfg_file_path_tmp            = "$cfg_file_path-tmp";
  $overview_server_metrics = Xorux_lib::read_json($overview_server_metrics_file) if ( -f $overview_server_metrics_file );
  open( my $cfg, ">", "$cfg_file_path_tmp" ) || error( "Cannot open $cfg_file_path_tmp" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;

  #  open (my $detail, ">", "$env_dir/$serverName/$host/detail.html");
  #  open (my $overview, ">", "$env_dir/$serverName/$host/overview.html");

  #SERVER OVERVIEW
  foreach my $metric ( sort keys %{ $conf->{server} } ) {
    if ( ref( $conf->{server}{$metric} ) ne "HASH" ) {
      if ( defined $dict->{$metric} && $dict->{$metric} ne "" && $dict->{$metric} ne "value" ) {
        print $cfg "$dict->{$metric} $conf->{server}{$metric}\n";

        #print "writing to $cfg_file_path_tmp\t$dict->{$metric} $conf->{server}{$metric}\n";
      }
      else {
        print $cfg "$metric $conf->{server}{$metric}\n";
      }
    }
  }
  foreach my $metric ( keys %{ $conf->{server} } ) {
    if ( ref( $conf->{server}{$metric} ) eq "HASH" ) {
      foreach my $id ( keys %{ $conf->{server}{$metric} } ) {
        foreach my $metric2 ( keys %{ $conf->{server}{$metric}{$id} } ) {
          if ( $metric2 =~ m/ID/ ) {
            next;
          }
          else {
            print $cfg "$metric2 $conf->{server}{$metric}{$id}{$metric2}\n";

            #print "writing to $env_dir/$serverName/$host/config.html\t$metric2 $conf->{server}{$metric}{$id}{$metric2}\n";
          }
        }
      }
    }
  }
  foreach my $lpar ( keys %{ $conf->{lpar} } ) {
    print $cfg "$dict->{'PartitionName'} $conf->{lpar}{$lpar}{'PartitionName'}\n";
    print $cfg "$dict->{'OperatingSystemVersion'} $conf->{lpar}{$lpar}{'OperatingSystemVersion'}\n";
    foreach my $metric ( keys %{ $conf->{lpar}{$lpar} } ) {
      next if ( $metric eq 'OperatingSystemVersion' || $metric eq 'PartitionName' );
      if ( defined $conf->{lpar}{$lpar}{$metric} ) {
        if ( defined $dict->{$metric} ) {
          print $cfg "$dict->{$metric} $conf->{lpar}{$lpar}{$metric}\n";
        }
        else {
          print $cfg "$metric $conf->{lpar}{$lpar}{$metric}\n";
        }
      }
    }
  }

  foreach my $pool ( keys %{ $conf->{shared_pools} } ) {
    print $cfg "$dict->{PoolName} $conf->{shared_pools}{$pool}{PoolName}\n"                                             if defined $conf->{shared_pools}{$pool}{PoolName};
    print $cfg "$dict->{PoolID} $conf->{shared_pools}{$pool}{PoolID}\n"                                                 if defined $conf->{shared_pools}{$pool}{PoolID};
    print $cfg "$dict->{MaximumProcessingUnits} $conf->{shared_pools}{$pool}{MaximumProcessingUnits}\n"                 if defined $conf->{shared_pools}{$pool}{MaximumProcessingUnits};
    print $cfg "$dict->{CurrentReservedProcessingUnits} $conf->{shared_pools}{$pool}{CurrentReservedProcessingUnits}\n" if defined $conf->{shared_pools}{$pool}{CurrentReservedProcessingUnits};
  }

  ### DETAILED TABLE ###
  print $fh "<div class=\"server_detail\">";
  print $fh "
  <TABLE class=\"tabconfig tablesorter\">
    <thead>
      <TR>
        <TH align=\"left\" class=\"sortable\" valign=\"left\">Detailed</TH>
        <TH align=\"left\" class=\"sortable\" valign=\"left\">Value</TH>
      </TR>
    </thead>
    <tbody>";
  foreach my $metric ( sort keys %{ $conf->{server} } ) {
    if ( ref( $conf->{server}{$metric} ) ne "HASH" ) {
      print $fh "
      <TR>
        <TD align=\"left\">$metric</TD>
        <TD align=\"left\">$conf->{server}{$metric}</TD>
      </TR>";
    }
  }
  print $fh "</tbody>
    </TABLE>
  ";
  print $fh "</div>\n";
  ### END DETAILED TABLE ###

  ### OVERVIEW TABLE ###
  print $fh "<div class=\"server_overview\">";
  print $fh "
  <TABLE class=\"tabconfig tablesorter\">
    <thead>
      <TR>
        <TH align=\"left\" class=\"sortable\" valign=\"left\">Overview</TH>
        <TH align=\"left\" class=\"sortable\" valign=\"left\">Value</TH>
      </TR>
    </thead>
    <tbody>";
  foreach my $metric ( @{$overview_server_metrics} ) {
    my $value = "undef";
    if ( defined $conf->{server}{$metric} ) {
      $value = $conf->{server}{$metric};
    }
    print $fh "<TR>  <TD align=\"left\">   $metric   </TD><TD align=\"left\">    $value    </TD></TR>\n";
  }
  print $fh "
    </tbody>
  </TABLE>
  </div>";
  ### END OVERVIEW TABLE ###

  close($cfg);
  rename( "$cfg_file_path_tmp", "$cfg_file_path" ) || error( "Cannot: mv $cfg_file_path_tmp to $cfg_file_path : $!" . __FILE__ . ":" . __LINE__ );

  #  close($detail);
  #  close($overview);
  #  `cp "$env_dir/$serverName/$host/detail.html" "$ENV{WEBDIR}/$host/$serverName/detail.html"`;
  #  `cp "$env_dir/$serverName/$host/overview.html" "$ENV{WEBDIR}/$host/$serverName/overview.html"`;
  copy( "$env_dir/$serverName/$host/config.html", "$ENV{WEBDIR}/$host/$serverName/config.html" ) || error( "Cannot: cp $env_dir/$serverName/$host/config.html $ENV{WEBDIR}/$host/$serverName/: $!" . __FILE__ . ":" . __LINE__ );
  copy( "$env_dir/$serverName/$host/config.html", "$ENV{WEBDIR}/$host/$serverName/config.cfg" )  || error( "Cannot: cp $env_dir/$serverName/$host/config.html $ENV{WEBDIR}/$host/$serverName/config.cfg: $!" . __FILE__ . ":" . __LINE__ );

  #print "hmctot debug $env_dir/$serverName/$host/config.html to $env_dir/$serverName/$host/config.cfg\n";
  copy( "$env_dir/$serverName/$host/config.html", "$env_dir/$serverName/$host/config.cfg" ) || error( "Cannot: cp $env_dir/$serverName/$host/config.html $env_dir/$serverName/$host/config.cfg: $!" . __FILE__ . ":" . __LINE__ );

  #  `cp "$env_dir/$serverName/$host/config.html" "$ENV{WEBDIR}/$host/$serverName/config.cfg"`;
  #  `cp "$env_dir/$serverName/$host/config.html" "$env_dir/$serverName/$host/config.cfg"`;
}

sub create_config_cpu_pool_html {
  my $uid                = shift;
  my $servername         = shift;
  my $conf               = shift;
  my $host               = shift;
  my $pool_identificator = shift;
  my $fh;
  my $cpu_html_path     = "";
  my $cpu_html_path_tmp = "";

  if ( $pool_identificator eq "undef_NaN" ) {

    #    if (-e "$work_folder/data/$servername/$host/cpu.html"){
    #      open ($fh, "<", "$work_folder/data/$servername/$host/cpu.html") || error ("Cannot read $work_folder/data/$servername/$host/cpu.html at ".__FILE__.":".__LINE__) && return 1;
    #      my $last_update = stat($fh);
    #      close ($fh);
    #      my $act_time = time();
    #      $last_update = $last_update->[9];
    #      my $time_diff = $act_time - $last_update;
    #      if ($time_diff <= 3600){
    #        return;
    #      }
    #    }
    $cpu_html_path     = "$work_folder/data/$servername/$host/cpu.html";
    $cpu_html_path_tmp = "$cpu_html_path-tmp";
    open( $fh, ">", "$cpu_html_path_tmp" ) || error( "Cannot read $cpu_html_path_tmp at " . __FILE__ . ":" . __LINE__ ) && return 1;
  }
  else {
    if ( -e "$work_folder/data/$servername/$host/cpu_pool_$pool_identificator.html" ) {

      #      open ($fh, "<", "$work_folder/data/$servername/$host/cpu_pool_$pool_identificator.html") || error ("Cannot read $work_folder/data/$servername/$host/cpu_pool_$pool_identificator.html at ".__FILE__.":".__LINE__) && return 1;
      #      my $last_update = stat($fh);
      #      close ($fh);
      #      my $act_time = time();
      #      $last_update = $last_update->[9];
      #      my $time_diff = $act_time - $last_update;
      #      if ($time_diff <= 3600){
      #        return;
      #      }
    }
    $cpu_html_path     = "$work_folder/data/$servername/$host/cpu_pool_$pool_identificator.html";
    $cpu_html_path_tmp = "$cpu_html_path-tmp";
    open( $fh, ">", "$cpu_html_path_tmp" ) || error( "Cannot read $work_folder/data/$servername/$host/cpu_pool_$pool_identificator.html at " . __FILE__ . ":" . __LINE__ ) && return 1;
  }
  my $lpars = $conf->{lpar};
  print $fh '<TABLE class="tabconfig tablesorter" data-sortby="-1">
  <thead>
   <TR>
     <TH class="sortable" valign="center">LPAR</TH>
     <TH align="center" class="sortable" valign="center">Mode</TH>
     <TH align="center" class="sortable" valign="center">Min</TH>
     <TH align="center" class="sortable" valign="center">Assigned</TH>
     <TH align="center" class="sortable" valign="center">Max</TH>
     <TH align="center" class="sortable" valign="center">min VP</TH>
     <TH align="center" class="sortable" valign="center">Virtual</TH>
     <TH align="center" class="sortable" valign="center">max VP</TH>
     <TH align="center" class="sortable" valign="center">Sharing<br>mode</TH>
     <TH align="center" class="sortable" valign="center">Uncap<br>weight</TH>
     <TH align="center" class="sortable" valign="center">Pool</TH>
     <TH align="center" class="sortable" valign="center">Pool ID</TH>
     <TH align="center" class="sortable" valign="center">OS</TH>
   </TR>
  </thead>
  <tbody>';
  foreach my $lpar_name ( keys %{$lpars} ) {
    if ( $pool_identificator ne "undef_NaN" ) {
      if ( defined $lpars->{$lpar_name}{'CurrentSharedProcessorPoolID'} && $lpars->{$lpar_name}{'CurrentSharedProcessorPoolID'} ne "" ) {
        if ( $lpars->{$lpar_name}{'CurrentSharedProcessorPoolID'} ne $pool_identificator || !defined $lpars->{$lpar_name}{'CurrentSharedProcessorPoolID'} ) {
          next;
        }
      }
    }
    my $curr_min_vp                = "";
    my $curr_vp                    = "";
    my $curr_max_vp                = "";
    my $mode                       = "";
    my $pool_id                    = "";
    my $curr_min_proc_units        = "";
    my $curr_proc_units            = "";
    my $curr_max_proc_units        = "";
    my $curr_shared_proc_pool_name = "";
    my $uncap_weight               = "";
    my $sharing_mode = defined $lpars->{$lpar_name}{'SharingMode'} ? $lpars->{$lpar_name}{'SharingMode'} : "";
    my $os_version = defined $lpars->{$lpar_name}{'OperatingSystemVersion'} ? $lpars->{$lpar_name}{'OperatingSystemVersion'} : "";

    if   ( defined $lpars->{$lpar_name}{'UncappedWeight'} ) { $uncap_weight = $lpars->{$lpar_name}{'UncappedWeight'}; }
    else                                                    { $uncap_weight = "null"; }
    if   ( defined $lpars->{$lpar_name}{'CurrentMinimumProcessingUnits'} ) { $curr_min_proc_units = $lpars->{$lpar_name}{'CurrentMinimumProcessingUnits'}; }
    else                                                                   { $curr_min_proc_units = "null"; }
    if   ( defined $lpars->{$lpar_name}{'CurrentProcessingUnits'} ) { $curr_proc_units = $lpars->{$lpar_name}{'CurrentProcessingUnits'}; }
    else                                                            { $curr_proc_units = "null"; }
    if   ( defined $lpars->{$lpar_name}{'CurrentMaximumProcessingUnits'} ) { $curr_max_proc_units = $lpars->{$lpar_name}{'CurrentMaximumProcessingUnits'}; }
    else                                                                   { $curr_max_proc_units = "null"; }

    if ( defined $lpars->{$lpar_name}{'CurrentMinimumVirtualProcessors'} ) {
      $curr_min_vp = $lpars->{$lpar_name}{'CurrentMinimumVirtualProcessors'};
    }
    elsif ( defined $lpars->{$lpar_name}{'CurrentMinimumProcessors'} ) {
      $curr_min_vp = $lpars->{$lpar_name}{'CurrentMinimumProcessors'};
    }
    if ( defined $lpars->{$lpar_name}{'AllocatedVirtualProcessors'} ) {
      $curr_vp = $lpars->{$lpar_name}{'AllocatedVirtualProcessors'};
    }
    elsif ( defined $lpars->{$lpar_name}{'CurrentProcessors'} ) {
      $curr_vp = $lpars->{$lpar_name}{'CurrentProcessors'};
    }
    if ( defined $lpars->{$lpar_name}{'CurrentMaximumVirtualProcessors'} ) {
      $curr_max_vp = $lpars->{$lpar_name}{'CurrentMaximumVirtualProcessors'};
    }
    elsif ( defined $lpars->{$lpar_name}{'CurrentMaximumProcessors'} ) {
      $curr_max_vp = $lpars->{$lpar_name}{'CurrentMaximumProcessors'};
    }
    if ( defined $lpars->{$lpar_name}{'CurrentSharedProcessorPoolID'} ) { $curr_shared_proc_pool_name = pool_id_to_name( $lpars->{$lpar_name}{'CurrentSharedProcessorPoolID'}, $servername, $host ); $mode = "shared"; $pool_id = $lpars->{$lpar_name}{'CurrentSharedProcessorPoolID'}; }
    else                                                                { $curr_shared_proc_pool_name = "null"; $mode = "ded"; }
    if ( !defined $pool_id && $pool_identificator ne "undef_NaN" ) { next; }
    if ( !defined $pool_id ) {
      $pool_id = "null";
    }
    print $fh "
    <TR>
      <TD><B>$lpar_name</B></TD>
      <TD align=\"center\">$mode</TD>
      <TD align=\"center\">$curr_min_proc_units</TD>
      <TD align=\"center\">$curr_proc_units</TD>
      <TD align=\"center\">$curr_max_proc_units</TD>
      <TD align=\"center\">$curr_min_vp</TD>
      <TD align=\"center\">$curr_vp</TD>
      <TD align=\"center\">$curr_max_vp</TD>
      <TD align=\"center\">$sharing_mode</TD>
      <TD align=\"center\">$uncap_weight</TD>
      <TD align=\"center\">$curr_shared_proc_pool_name</TD>
      <TD align=\"center\">$pool_id</TD>
      <TD align=\"center\" nowrap>$os_version</TD>
    </TR>\n" if (defined $pool_id && $pool_id ne "");
  }
  print $fh "
     </tbody>
    </TABLE>";
  close($fh);
  rename( "$cpu_html_path_tmp", "$cpu_html_path" ) || error( " Cannot mv $cpu_html_path_tmp to $cpu_html_path : $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  return 0;
}

sub create_config_cpu_sh_pool_html {
  return 1;
}

sub create_config_memory_html {
  my $uid        = shift;
  my $servername = shift;
  my $conf       = shift;
  my $host       = shift;
  my $fh;
  if ( -e "$work_folder/data/$servername/$host/mem.html" ) {

    #    open ($fh, "<", "$work_folder/data/$servername/$host/mem.html") || error("Cannot open $env_dir/$servername/$host/mem.html" .  " File: ".__FILE__.":".__LINE__) && return 1;
    #    my $last_update = stat($fh);
    #    close ($fh);
    #    my $act_time = time();
    #    $last_update = $last_update->[9];
    #    my $time_diff = $act_time - $last_update;
    #    if ($time_diff <= 3600){
    #      return;
    #    }
  }
  open( $fh, ">", "$work_folder/data/$servername/$host/mem.html" ) || error( "Cannot open $env_dir/$servername/$host/mem.html" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
  my $lpars = $conf->{lpar};
  print $fh '<BR>
<CENTER>
<TABLE class="tabconfig tablesorter">
<thead>
<TR>
<TH class="sortable">LPAR</TH>
<TH align="center" class="sortable">Min</TH>
<TH align="center" class="sortable">Assigned</TH>
<TH align="center" class="sortable">Max</TH>
<TH align="center" class="sortable">Running</TH>
</TR>
</thead>
<tbody>
';
  foreach my $lpar_name ( keys %{$lpars} ) {
    if ( !defined $lpars->{$lpar_name}{'MinimumMemory'} ) { $lpars->{$lpar_name}{'MinimumMemory'} = ""; }
    if ( !defined $lpars->{$lpar_name}{'CurrentMemory'} ) { $lpars->{$lpar_name}{'CurrentMemory'} = ""; }
    if ( !defined $lpars->{$lpar_name}{'MaximumMemory'} ) { $lpars->{$lpar_name}{'MaximumMemory'} = ""; }
    if ( !defined $lpars->{$lpar_name}{'RuntimeMemory'} ) { $lpars->{$lpar_name}{'RuntimeMemory'} = ""; }
    $lpars->{$lpar_name}{'MinimumMemory'} /= 1024 if ($lpars->{$lpar_name}{'MinimumMemory'} ne "");
    $lpars->{$lpar_name}{'CurrentMemory'} /= 1024 if ($lpars->{$lpar_name}{'CurrentMemory'} ne "");
    $lpars->{$lpar_name}{'MaximumMemory'} /= 1024 if ($lpars->{$lpar_name}{'MaximumMemory'} ne "");
    $lpars->{$lpar_name}{'RuntimeMemory'} /= 1024 if ($lpars->{$lpar_name}{'RuntimeMemory'} ne "");
    print $fh "<TR> <TD><B>$lpar_name</B></TD> <TD align=\"center\">$lpars->{$lpar_name}{'MinimumMemory'}</TD><TD align=\"center\">$lpars->{$lpar_name}{'CurrentMemory'}</TD> <TD align=\"center\">$lpars->{$lpar_name}{'MaximumMemory'}</TD><TD align=\"center\">$lpars->{$lpar_name}{'RuntimeMemory'}</TD></TR>\n";
  }
  print $fh "</tbody></TABLE></CENTER><br>(all in GB)<BR>\n";
  close($fh);
  return 1;
}

sub pool_id_to_name {
  my $pool_id    = shift;
  my $servername = shift;
  my $host       = shift;
  my $pool_name  = "";
  if ( -e "$work_folder/data/$servername/$host/cpu-pools-mapping.txt" ) {
    open( my $pool_mapping, "<", "$work_folder/data/$servername/$host/cpu-pools-mapping.txt" ) || error( "Cannot open $work_folder/data/$servername/$host/cpu-pools-mapping.txt" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
    my @lines = <$pool_mapping>;
    foreach my $line (@lines) {
      ( my $pool_id_file, my $pool_name_file ) = split( ",", $line );
      if ( $pool_id_file == $pool_id ) {
        $pool_name = $pool_name_file;
      }
    }
    close($pool_mapping);
  }
  else { $pool_name = $pool_id; }
  return $pool_name;
}

sub create_config_html {
  my $uid        = shift;
  my $servername = shift;
  my $conf       = shift;
  my $host       = shift;
  my $env_config = shift;

  #  my $conf = Xorux_lib::read_json($CONFIG_path) if (-e $CONFIG_path);
  my $SERVER   = $conf->{'server'};
  my $SHP      = $conf->{'shared_pools'};
  my $LPARS    = $conf->{'lpar'};
  my $INFO     = $conf->{'info'};
  my $host_url = urlencode($host);

  if ( !-d "$webdir" ) {
    mkdir( "$webdir", 0755 ) || error( " Cannot mkdir $webdir: $!" . __FILE__ . ":" . __LINE__ ) && return;
  }
  if ( !-d "$webdir/$host" ) {
    mkdir( "$webdir/$host", 0755 ) || error( " Cannot mkdir $webdir/$host: $!" . __FILE__ . ":" . __LINE__ ) && return;
  }
  if ( !-d "$webdir/$host/$servername" ) {
    mkdir( "$webdir/$host/$servername", 0755 ) || error( " Cannot mkdir $webdir/$host/$servername: $!" . __FILE__ . ":" . __LINE__ ) && return;
  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : new_config_server creating start\n";
  my $new_config_server_path     = "$webdir/$host/$servername/new_config_server.html";
  my $new_config_server_path_tmp = "$webdir/$host/$servername/new_config_server.html-tmp";
  open( my $fh, ">", "$new_config_server_path_tmp" ) || error( "Cannot open $new_config_server_path_tmp" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
  my $managedname_url = urlencode($servername);
  my $id              = $uid;
  my $server_link     = "<A HREF=\"/lpar2rrd-cgi/detail.sh?host=$host_url&server=$managedname_url&lpar=pool&item=pool&entitle=0&gui=1&none=none\">$servername</A>";
  print $fh "<div>\n";
  print $fh "<div class=\"server_quick\">";
  if ( ref($SERVER) ne "HASH" ) { $SERVER = {}; }
  ### QUICK LOOK TABLE ###
  print $fh "<table style=\"margin-top:20px;\" class=\"tabcfgsumext\">
    <thead>
      <tr>
        <th colspan=\"3\" style=\"text-align:center;\">$server_link</th>
      </tr>
    </thead>
    <tr>
      <td colspan=\"3\">
        <table class=\"tabcfgsum\">
        <thead>
          <tr>
            <th class=\"columnalignleft\"></th>
            <th class=\"columnalignmiddle\">EC</th>
            <th class=\"columnalignright\">MEM</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class=\"columnalignleft\">TOTAL</td>
            <td class=\"columnalignmiddle\">$SERVER->{'ConfigurableSystemProcessorUnits'}</td>
            <td class=\"columnalignright\">$SERVER->{'ConfigurableSystemMemory'}</td>
          </tr>
          <tr>
            <td class=\"columnalignleft\">FREE</td>
            <td class=\"columnalignmiddle\">$SERVER->{'CurrentAvailableSystemProcessorUnits'}</td>
            <td class=\"columnalignright\">$SERVER->{'CurrentAvailableSystemMemory'}</td>
          </tr>
         </tbody>
      </table>
    </td>
  </tr>
  <tr>
    <td colspan=\"1\">
      <table class=\"tabcfgsum\">
        <thead>
          <tr>
            <th class=\"columnalignleft\">CPU pools:</th>
            <th class=\"columnalignmiddle\" >Reserved</th>
            <th class=\"columnalignmiddle\" >Max</th>
          </tr>
        </thead>
        <tbody>";
  foreach my $shared_pool_id ( keys %{$SHP} ) {
    my $shp                      = $SHP->{$shared_pool_id};
    my $curr_reserved_proc_units = "null";
    my $MaximumProcessingUnits   = "null";
    my $pool_id                  = "null";
    my $pool_name                = "null";
    if ( defined $shp->{'CurrentReservedProcessingUnits'} && $shp->{'CurrentReservedProcessingUnits'} ne "" ) { $curr_reserved_proc_units = $shp->{'CurrentReservedProcessingUnits'}; }
    if ( defined $shp->{'MaximumProcessingUnits'}         && $shp->{'MaximumProcessingUnits'} ne "" )         { $MaximumProcessingUnits   = $shp->{'MaximumProcessingUnits'}; }
    if ( defined $shp->{'PoolID'}                         && $shp->{'PoolID'} ne "" )                         { $pool_id                  = $shp->{'PoolID'}; }
    if ( defined $shp->{'PoolName'}                       && $shp->{'PoolName'} ne "" )                       { $pool_name                = $shp->{'PoolName'}; }
    print "  adding $pool_name ($curr_reserved_proc_units, $MaximumProcessingUnits) to new_config_server $servername/$host\n";
    print $fh "<tr>
                        <td class=\"columnalignleft\" bgcolor=\"\">
                          <a href=\"/lpar2rrd-cgi/detail.sh?host=$host_url&server=$managedname_url&lpar=SharedPool$pool_id&item=pool&entitle=0&amp;none=none\">$pool_name</a>
                        </td>
                        <td class=\"columnalignright\" bgcolor=\"\" colspan=\"1\">$curr_reserved_proc_units</td>
                        <td class=\"columnalignright\" bgcolor=\"\" colspan=\"1\">$MaximumProcessingUnits</td>
                       </tr>
          "
  }
  print $fh "</tbody>
        </table>
      </td>
    </tr>
    <tr>
      <td colspan=\"3\">
        <table class=\"tabcfgsum tablesorter tablesortercfgsum tablesorter-ice tablesorter5fc1e9382d4a7 hasFilters\" role=\"grid\">
          <thead>
            <tr role=\"row\" class=\"tablesorter-headerRow\">
              <th class=\"sortable columnalignleft tablesorter-header tablesorter-headerUnSorted\" data-column=\"0\" tabindex=\"0\" scope=\"col\" role=\"columnheader\" aria-disabled=\"false\" unselectable=\"on\" aria-sort=\"none\" aria-label=\"LPAR: No sort applied, activate to apply a descending sort\" style=\"user-select: none;\">
                <div class=\"tablesorter-header-inner\">LPAR</div>
              </th>
              <th class=\"sortable columnalignmiddle tablesorter-header tablesorter-headerDesc\" data-column=\"1\" tabindex=\"0\" scope=\"col\" role=\"columnheader\" aria-disabled=\"false\" unselectable=\"on\" aria-sort=\"descending\" aria-label=\"EC: Descending sort applied, activate to apply an ascending sort\" style=\"user-select: none;\">
                <div class=\"tablesorter-header-inner\">EC</div>
              </th>
              <th class=\"sortable columnalignright tablesorter-header tablesorter-headerUnSorted\" data-column=\"2\" tabindex=\"0\" scope=\"col\" role=\"columnheader\" aria-disabled=\"false\" unselectable=\"on\" aria-sort=\"none\" aria-label=\"MEM: No sort applied, activate to apply a descending sort\" style=\"user-select: none;\">
                <div class=\"tablesorter-header-inner\">MEM</div>
              </th>
            </tr>
            <tr role=\"search\" class=\"tablesorter-filter-row tablesorter-ignoreRow hideme\">
              <td data-column=\"0\"><input type=\"search\" placeholder=\"\" class=\"tablesorter-filter\" data-column=\"0\" aria-label=\"Filter &quot;LPAR&quot; column by...\" data-lastsearchtime=\"1537444775637\"></td>
              <td data-column=\"1\"><input type=\"search\" placeholder=\"\" class=\"tablesorter-filter\" data-column=\"1\" aria-label=\"Filter &quot;EC&quot; column by...\" data-lastsearchtime=\"1537444775637\"></td>
              <td data-column=\"2\"><input type=\"search\" placeholder=\"\" class=\"tablesorter-filter\" data-column=\"2\" aria-label=\"Filter &quot;MEM&quot; column by...\" data-lastsearchtime=\"1537444775637\"></td>
            </tr>
          </thead>
          <tbody aria-live=\"polite\" aria-relevant=\"all\">";

  foreach my $lpar_name ( keys %{$LPARS} ) {
    my $lpar    = $LPARS->{$lpar_name};
    my $bgcolor = "";
    if ( $lpar->{'PartitionState'} eq "running" ) {
      $bgcolor = "#80FF80";    #green - running
    }
    elsif ( $lpar->{'PartitionState'} eq "not activated" ) {
      $bgcolor = "#FF8080";    #red - not running
    }
    else {
      $bgcolor = "#FFFF80";    #yellow - error?
    }
    my $proc_units = "null";
    my $run_mem    = "null";
    if ( defined $lpar->{'DesiredProcessingUnits'} && $lpar->{'DesiredProcessingUnits'} ne "" ) {
      $proc_units = $lpar->{'DesiredProcessingUnits'};
    }
    if ( defined $lpar->{'CurrentProcessors'} && $lpar->{'CurrentProcessors'} ne "" ) {
      $proc_units = $lpar->{'CurrentProcessors'};
    }
    if ( defined $lpar->{'RuntimeMemory'} ) { $run_mem = $lpar->{'RuntimeMemory'}; }
    print "adding lpar $lpar_name $servername $host\n";
    print $fh "
            <tr role=\"row\">
              <td class=\"columnalignleft\" bgcolor=\"$bgcolor\"><a href=\"/lpar2rrd-cgi/detail.sh?host=$host_url&server=$managedname_url&lpar=$lpar_name&item=lpar&entitle=0&amp;none=none\">$lpar_name</a></td>
              <td class=\"columnalignmiddle\" bgcolor=\"$bgcolor\">$proc_units</td>
              <td class=\"columnalignright\" bgcolor=\"$bgcolor\">$run_mem</td>
            </tr>
            ";
  }
  print $fh "
          </tbody>
        </table>
      </td>
    </tr>
</table>";
  print $fh "</table>";
  print $fh "</div>\n";
  ### END QUICK LOOK TABLE ###
  #print "debug hmc total start: $servername @ $host\n";
  config_out( $id, $servername, $conf, $fh );

  #print "  debug hmc total end: $servername @ $host\n";
  interface_conf_server( $env_config, $fh, $servername );
  print $fh "</div>\n";
  close($fh);
  rename( "$new_config_server_path_tmp", "$new_config_server_path" ) || error( " Cannot mv $new_config_server_path_tmp to $new_config_server_path : $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : new_config_server creating end\n";
  return 0;
}

sub config_table_main {
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : config_table_main creating start\n";
  my @files = <$work_folder/tmp/restapi/HMC_INFO_*.json>;
  my $servers_printed;
  my $days            = 7;
  my $days_in_seconds = $days * 24 * 3600;
  my $last_updated    = Xorux_lib::file_time_diff("$webdir/config_table_main.html");

  #if ($last_updated &&  $last_updated <= 300){
  #  print "Rest API     : do not generate config_table_main now\n";
  #  return (0);
  #}
  open( my $main_table, ">", "$webdir/config_table_main.html-tmp" ) || error( "Cannot open $webdir/config_table_main.html-tmp" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
  print $main_table '<TABLE class="tabconfig tablesorter powersrvcfg" data-sortby="-1">

  <thead>
   <TR>
     <TH align="center" class="sortable">Server</TH>
     <TH align="center" class="sortable" valign="center">Cores</TH>
     <TH align="center" class="sortable" valign="center">Cores Free</TH>
     <TH align="center" class="sortable" valign="center">Memory</TH>
     <TH align="center" class="sortable" valign="center">Memory Free</TH>
     <TH align="center" valign="center">Quick info</TH>
     <TH align="center" valign="center">Overview</TH>
     <TH align="center" valign="center">Detail</TH>
     <TH align="center" valign="center">Interfaces</TH>
     <TH align="center" valign="center">Firmware</TH>
     <TH align="center" valign="center">Model-Machine Type</TH>
     <TH align="center" valign="center">Serial</TH>
   </TR>
  </thead>
  <tbody>';
  my $check_data = 0;
  my $check_server;
  foreach my $file (@files) {

    open( my $fh, "<", $file ) || error( "Cannot read $file at " . __FILE__ . ":" . __LINE__ ) && next;
    my $last_update = stat($fh);
    close($fh);
    my $act_time = time();
    $last_update = $last_update->[9];
    my $how_old_is_file = $act_time - $last_update;
    if ( $how_old_is_file > $days_in_seconds ) {
      error("Rest API     unlink $file because not updated $days days. Old : $how_old_is_file\n");
      unlink($file);
      next;
    }
    else {
      #ok, read and print every server from $file into config_table_main.html
    }
    my $HMC_INFO = {};
    $HMC_INFO = Xorux_lib::read_json($file) if ( -f $file );
    foreach my $i ( keys %{$HMC_INFO} ) {
      my $s    = $HMC_INFO->{$i};
      my $err  = 0;
      my $name = $s->{name};
      if ( defined $check_server->{$name} && $check_server->{$name} ) {
        next;    #redundant
      }
      ( undef, my $host_from_name ) = split( "HMC_INFO_", $file );
      ( $host_from_name, undef ) = split( '\.json', $host_from_name );
      my $id          = $s->{id};
      my $CONFIG      = {};
      my $CONFIG_path = "$work_folder/data/$name/$host_from_name/CONFIG.json";

      #print "CONFIG_TABLE_MAIN : 0 : $CONFIG_path\n";
      my $old_config = Xorux_lib::file_time_diff($CONFIG_path);
      if ( !( -e $CONFIG_path ) ) {
        print "!Rest API   No config $CONFIG_path found\n";
        $err = 1;
      }

      #      if ($err || (defined $servers_printed->{$name} && $servers_printed->{$name} )){ #open CONFIG.json it exists, print its servers (that are unique) to config_table_main.html. Otherwise skip this host.
      #        print "Rest API   : Server $name is already in table, ok, skipping\n";
      #        next;
      #      }
      #      else{
      $CONFIG = Xorux_lib::read_json($CONFIG_path) if ( -f $CONFIG_path && defined $old_config && $old_config <= 86400 );

      #print "CONFIG_TABLE_MAIN:debug:$CONFIG_path:$old_config\n";
      if ( ref($CONFIG) eq "HASH" && defined $CONFIG->{server} ) {
        my $ConfigurableSystemMemory     = "";
        my $CurrentAvailableSystemMemory = "";
        $ConfigurableSystemMemory     = $CONFIG->{server}{ConfigurableSystemMemory} / 1024     if defined $CONFIG->{server}{ConfigurableSystemMemory};
        $CurrentAvailableSystemMemory = $CONFIG->{server}{CurrentAvailableSystemMemory} / 1024 if defined $CONFIG->{server}{CurrentAvailableSystemMemory};
        print $main_table "
        <TR>
        <TD><B>$name</B></TD>
        <TD align=\"center\">$CONFIG->{server}{ConfigurableSystemProcessorUnits}</TD>
        <TD align=\"center\">$CONFIG->{server}{CurrentAvailableSystemProcessorUnits}</TD>
        <TD align=\"center\">$ConfigurableSystemMemory GB</TD>
        <TD align=\"center\">$CurrentAvailableSystemMemory GB</TD>
        <TD align=\"center\"><a class=\"server_quick\"      href=\"/lpar2rrd-cgi/detail.sh?source=$host_from_name/$name/new_config_server.html\">quick_info</a></TD>
        <TD align=\"center\"><a class=\"server_overview\" href=\"/lpar2rrd-cgi/detail.sh?source=$host_from_name/$name/new_config_server.html\">overview_link</a></TD>
        <TD align=\"center\"><a class=\"server_detail\"   href=\"/lpar2rrd-cgi/detail.sh?source=$host_from_name/$name/new_config_server.html\">detail_link</a></TD>
        <TD align=\"center\"><a class=\"server_interface\"   href=\"/lpar2rrd-cgi/detail.sh?source=$host_from_name/$name/new_config_server.html\">interface_link</a></TD>
        <TD align=\"center\">$CONFIG->{server}{SystemFirmware}</TD>
        <TD align=\"center\">$CONFIG->{server}{Model}-$CONFIG->{server}{MachineType}</TD>
        <TD align=\"center\">$CONFIG->{server}{SerialNumber}</TD>
        </TR>\n";
        $servers_printed->{$name} = "true";
        $check_data++;
        $check_server->{$name} = 1;
      }
      undef $CONFIG;

      #      }
    }
  }
  print $main_table "
  </tbody>
  </TABLE>
  <BR>";
  close($main_table);
  if ( $check_data && $last_updated >= 300 || $last_updated == 0 ) {
    copy( "$webdir/config_table_main.html-tmp", "$webdir/config_table_main.html" );
  }
  else {
    print "Do not copy config_table_main due the condictions : $check_data : $last_updated : $last_updated\n";
  }
  if ( $check_data == 0 ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Error when generating config_table_main.html - no data\n";
  }

  #  unlink ("$webdir/config_table_main_$$.html");
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : config_table_main creating end\n";
  return 1;
}

sub urlencode {
  my $s = shift;
  $s =~ s/([^a-zA-Z0-9!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  return $s;
}

sub subprint_conf {
  my $in = shift;
  my $out;
  if ( !defined $in || $in eq "" ) {
    return -1;
  }
  if ( ref($in) eq "HASH" ) {
    foreach my $metric ( keys %{$in} ) {
      eval {
        if ( ref( $in->{$metric} ) eq "HASH" && defined $in->{$metric}{content} ) {
          my $value = $in->{$metric}{content};
          $out->{$metric} = $value;
        }
        else {
          if ( ref( $in->{$metric} ) eq "HASH" ) {

            #there should be another metrics that can be used. Unhash for view another available sections in STDOUT.
            #print "next: $metric\n";
          }
          else {
            #do not use these
          }
        }
      };
      if ($@) {
        next;
      }
    }
  }
  else {
    print "Not a hash in subprint_conf subroutine in " . __FILE__ . " at " . __LINE__ . "\n";
  }
  return $out;
}

sub enterprise_pool_hmc {
  my $mem_units     = shift;
  my $ent_pool_json = callAPI("rest/api/uom/PowerEnterprisePool");
  if ( ref($ent_pool_json) eq "HASH" && defined $ent_pool_json->{'entry'} ) {
    $ent_pool_json = $ent_pool_json->{'entry'};
  }
  else {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : No Enterprise Pool found, returning\n";
    print Dumper $ent_pool_json;
    return -1;
  }
  my $divide;
  if ( $mem_units eq "MB" ) { $divide = 1; }
  if ( $mem_units eq "GB" ) { $divide = 1000; }
  if ( $mem_units eq "TB" ) { $divide = 1000000; }
  my $out;
  my $ent_pool      = $ent_pool_json->{content}{'PowerEnterprisePool:PowerEnterprisePool'};
  my $ent_pool_name = $ent_pool->{PoolName}{content};

  if ( defined $ent_pool && $ent_pool ne "" && ref($ent_pool) eq "HASH" ) {
    foreach my $metric ( keys %{$ent_pool} ) {
      eval {
        if ( defined $ent_pool->{$metric}{content} ) {
          my $value = $ent_pool->{$metric}{content};
          if ( $metric =~ m/Memory/ && is_digit($value) ) {
            $value = $value / $divide;
            $value = sprintf( "%d", $value );
          }
          $out->{$ent_pool_name}{$metric} = $value;
        }
      };
    }
    foreach my $m_console ( @{ $ent_pool->{PowerEnterprisePoolManagementConsoles}{PowerEnterprisePoolManagementConsole} } ) {
      foreach my $metric ( keys %{$m_console} ) {
        eval {
          if ( defined $m_console->{$metric}{content} ) {
            my $value = $m_console->{$metric}{content};
            if ( $metric =~ m/Memory/ && is_digit($value) ) {
              $value = $value / $divide;
              $value = sprintf( "%d", $value );
            }
            $out->{$ent_pool_name}{Consoles}{ $m_console->{ManagementConsoleName}{content} }{$metric} = $value;
          }
        }
      }
    }
    my $i = 0;
    foreach my $pool_member ( @{ $ent_pool->{PowerEnterprisePoolMembers}{link} } ) {
      $i++;
      my $pool_member_link = $pool_member->{href};
      my $pool_member      = callAPI($pool_member_link);
      foreach my $metric ( keys %{ $pool_member->{content}{'PowerEnterprisePoolMember:PowerEnterprisePoolMember'} } ) {
        my $p_member = $pool_member->{content}{'PowerEnterprisePoolMember:PowerEnterprisePoolMember'};
        eval {
          if ( defined $p_member->{$metric}{content} ) {
            my $value = $p_member->{$metric}{content};
            if ( $metric =~ m/Memory/ && is_digit($value) ) {
              $value = $value / $divide;
              $value = sprintf( "%d", $value );
            }
            $out->{$ent_pool_name}{Member}{ $p_member->{ManagedSystemName}{content} }{$metric} = $value;
          }
        }
      }
    }
  }

  #Xorux_lib::write_json("$work_folder/tmp/restapi/HMC_ENTERPRISE_POOL_conf.json", $out) if defined $out;
  check_and_write( "$work_folder/tmp/restapi/HMC_ENTERPRISE_POOL_conf.json", $out, 0 );
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Enterprise Pool .json Finished\n";
  return $out;

}

sub create_html_enterprise {
  my $ent       = shift;
  my $mem_units = shift;
  my $html_file = "$webdir/enterprise_pool.html";
  open( my $fh, ">", $html_file ) || error( "Cannot open $html_file" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
  print $fh "<TABLE style=\"80%\" class=\"tabconfig tablesorter\">
      <thead>
        <TR>
          <TH class=\"sortable\" valign=\"center\">Enteprise Pool</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Total Cores</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Available Cores</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Total Memory</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Available Memory</TH>
        </TR>      </thead>
      <tbody>";
  foreach my $ent_pool_name ( keys %{$ent} ) {
    my $ent_pool = $ent->{$ent_pool_name};
    print $fh "<TR>
       <TD><B>$ent_pool_name</B></TD>
       <TD align=\"center\">$ent_pool->{TotalMobileCoDProcUnits}</TD>
       <TD align=\"center\">$ent_pool->{AvailableMobileCoDProcUnits}</TD>
       <TD align=\"center\">$ent_pool->{TotalMobileCoDMemory} $mem_units</TD>
       <TD align=\"center\">$ent_pool->{AvailableMobileCoDMemory} $mem_units</TD>
       </TR>";

  }
  if ( scalar( keys %{$ent} ) == 0 ) {
    print $fh "<TR>
       <TD><B>No Enterprise Pool found</B></TD>
       <TD align=\"center\">NaN</TD>
       <TD align=\"center\">NaN</TD>
       <TD align=\"center\">NaN</TD>
       <TD align=\"center\">NaN</TD>
       </TR>";
  }
  print $fh "</tbody>
      </TABLE>
  <BR>";

  foreach my $ent_pool_name ( keys %{$ent} ) {
    my $ent_pool = $ent->{$ent_pool_name};
    print $fh "<TABLE style=\"80%\" class=\"tabconfig tablesorter\">
      <thead>
        <TR>
          <TH class=\"sortable\" valign=\"center\">$ent_pool_name Members</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Installed Cores</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Cores</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Inactive Cores</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Installed Memory</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Memory</TH>
          <TH align=\"center\" class=\"sortable\" valign=\"center\">Inactive Memory</TH>
        </TR>      </thead>
      <tbody>";

    foreach my $pool_member_name ( keys %{ $ent_pool->{Member} } ) {
      my $member_hash = $ent_pool->{Member}{$pool_member_name};
      print $fh "<TR>
          <TD><B>$pool_member_name</B></TD>
          <TD align=\"center\">$member_hash->{ManagedSystemInstalledProcUnits}</TD>
          <TD align=\"center\">$member_hash->{MobileCoDProcUnits}</TD>
          <TD align=\"center\">$member_hash->{InactiveProcUnits}</TD>
          <TD align=\"center\">$member_hash->{ManagedSystemInstalledMemory} $mem_units</TD>
          <TD align=\"center\">$member_hash->{MobileCoDMemory} $mem_units</TD>
          <TD align=\"center\">$member_hash->{InactiveMemory} $mem_units</TD>
        </TR>";

    }
    print $fh "</tbody>
      </TABLE>";

    #  <BR>";

    print $fh "<BR>\n";
  }
  return 1;
  close($fh);
}

sub tz_correction {

  #2018-10-18T04:07:00+0000
  my $ts    = shift;
  my $epoch = str2time($ts);
  my $out   = strftime( "%F %H:%M:%S", localtime($epoch) );
  return $out;
}

sub find_lpar_name_from_uuid {
  my $uuid   = shift;
  my $CONFIG = shift;
  if ( ref($CONFIG) eq "HASH" ) {
    foreach my $lparName ( keys %{ $CONFIG->{lpar} } ) {
      if ( $uuid eq $CONFIG->{lpar}{$lparName}{PartitionUUID} ) {
        return $lparName;
      }
    }
  }
  else {
    print "Empty config find_lpar_name_from_uuid $uuid\n";
  }
}

sub rmc_check {
  my $do_rmc_check_at = "00";
  my $time            = time;
  if ( defined $ENV{RMC_CHECK_HOUR_REST_API} && $ENV{RMC_CHECK_HOUR_REST_API} ne "" ) {
    $do_rmc_check_at = $ENV{RMC_CHECK_HOUR_REST_API};
  }
  my $act_time      = strftime( "%F %X", localtime );
  my $rmc_test_file = Xorux_lib::file_time_diff("$work_folder/tmp/restapi/rmc_last.txt");
  if ( !$rmc_test_file || $rmc_test_file >= 86000 ) {
    print "RMC RUN";
  }
  elsif ($rmc_test_file) {
    open( my $rmc_read, "<", "$work_folder/tmp/restapi/rmc_last.txt" ) || error( "Cannot open $work_folder/tmp/restapi/rmc_last.txt" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
    my $last_rmc_run       = readline($rmc_read);
    my $last_rmc_run_epoch = readline($rmc_read);
    close($rmc_read);
    if ( !( $act_time =~ m/.*$do_rmc_check_at:[0-5][0-9]:[0-5][0-9]/ && ( $time - $last_rmc_run_epoch > 3600 ) ) ) {
      print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : RMC skipping, waiting for next $do_rmc_check_at:00. Last RMC Check done: $last_rmc_run\n";
      return;    #not this time, just after midnight
    }
    print "RMC RUN\n";
  }
  open( my $rmc_last, ">", "$work_folder/tmp/restapi/rmc_last.txt" ) || error( "Cannot open $work_folder/tmp/restapi/rmc_last.txt" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
  print $rmc_last "$act_time\n";
  print $rmc_last $time;
  close($rmc_last);

  open( my $rmc, ">", "$ENV{WEBDIR}/gui-rmc.html" ) || error( "Cannot open $work_folder/ww/gui-rmc.html" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;
  print $rmc "<center><h3>List of LPARs with no active RMC connection</h3></center>\n";
  print $rmc "<center> <table class=\"tabconfig\">\n";
  print $rmc "<tr><th>LPAR</th><th>SERVER</th><th>HMC</th><th>RMC state</th><th>RMC IP</th></tr>\n";
  my @files = ( "LAN_aliases", "SAN_aliases", "SAS_aliases" );
  foreach my $key_id ( keys %{$SERVERS} ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : $SERVERS->{$key_id}{name} RMC Check\n";
    my $CONFIG      = {};
    my $CONFIG_path = "$work_folder/data/$SERVERS->{$key_id}{name}/$host/CONFIG.json";
    $CONFIG = Xorux_lib::read_json($CONFIG_path) if ( -f $CONFIG_path );
    foreach my $lparname ( keys %{ $CONFIG->{lpar} } ) {
      foreach my $file (@files) {
        my $path    = "$work_folder/data/$SERVERS->{$key_id}{name}/$host/$file.json";
        my $aliases = {};
        $aliases = Xorux_lib::read_json($path) if ( -f $path );
        foreach my $physical_location ( keys %{$aliases} ) {
          my $act_partition = $aliases->{$physical_location}{partition};
          if ( $CONFIG->{lpar}{$lparname}{ResourceMonitoringControlState} ne "active" && ( $act_partition eq $lparname ) ) {
            error( "RMC is inactive on $lparname and detected some interfaces, RMC should be enabled to monitor them." . " File: " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      if ( $CONFIG->{lpar}{$lparname}{ResourceMonitoringControlState} ne "active" && $CONFIG->{lpar}{$lparname}{PartitionState} ne "not activated" ) {
        my $name      = "";
        my $rmc_state = "";
        my $rmc_ip    = "";
        $name      = $SERVERS->{$key_id}{name}                                  if defined $SERVERS->{$key_id}{name};
        $rmc_state = $CONFIG->{lpar}{$lparname}{ResourceMonitoringControlState} if defined $CONFIG->{lpar}{$lparname}{ResourceMonitoringControlState};
        $rmc_ip    = $CONFIG->{lpar}{$lparname}{ResourceMonitoringIPAdress}     if defined $CONFIG->{lpar}{$lparname}{ResourceMonitoringIPAdress};
        print "$lparname $CONFIG->{lpar}{$lparname}{PartitionState} $rmc_state\n";
        print $rmc "<tr><td>$lparname</td><td>$name</td><td>$host</td><td>$rmc_state</td><td>$rmc_ip</td></tr>\n";
      }
    }
  }
  print $rmc "</table></center><br>\n";
  print $rmc "Report has been created at: " . $act_time . "<br>\n";
  print $rmc "<a href=\"http://aix4admins.blogspot.cz/2012/01/rmc-resource-monitoring-and-control-rmc.html\" target=\"_blank\">RMC</a> is a distributed framework and architecture that allows the HMC to communicate with a managed logical partition.RMC daemons should be running on a partition in order to be able to do DLPAR operations on HMC.<br><br>You can use <a href=\"http://www-01.ibm.com/support/docview.wss?uid=isg3T1020611\">this link</a> for RMC troubleshooting.<br>\n";
  close($rmc);
}

sub create_csv_files_configuration {
  my $host  = "";
  my @files = <$work_folder/tmp/restapi/HMC_INFO_*.json>;

  #print "DEBUG ALL FILES:\n";
  #print Dumper \@files;

  my $server_csv_file     = "$webdir/server-config-rest.csv";
  my $lpar_csv_file       = "$webdir/lpar-config-rest.csv";
  my $npiv_csv_file       = "$webdir/npiv-config-rest.csv";
  my $vscsi_csv_file      = "$webdir/vscsi-config-rest.csv";
  my $interfaces_csv_file = "$webdir/interfaces-config-rest.csv";

  open( my $server_csv,     ">", $server_csv_file )     || error( "Cannot open $server_csv_file" . " File: " . __FILE__ . ":" . __LINE__ )     && return 1;
  open( my $lpar_csv,       ">", $lpar_csv_file )       || error( "Cannot open $lpar_csv_file" . " File: " . __FILE__ . ":" . __LINE__ )       && return 1;
  open( my $npiv_csv,       ">", $npiv_csv_file )       || error( "Cannot open $npiv_csv_file" . " File: " . __FILE__ . ":" . __LINE__ )       && return 1;
  open( my $vscsi_csv,      ">", $vscsi_csv_file )      || error( "Cannot open $vscsi_csv_file" . " File: " . __FILE__ . ":" . __LINE__ )      && return 1;
  open( my $interfaces_csv, ">", $interfaces_csv_file ) || error( "Cannot open $interfaces_csv_file" . " File: " . __FILE__ . ":" . __LINE__ ) && return 1;

  print $server_csv "HMC;server;type_model;serial;configurable_sys_proc_units;configurable_sys_mem[MB];curr_avail_sys_mem[MB];CPU pool name;reserved CPU units;maximum CPU units;installed_sys_proc_units;curr_avail_sys_proc_units\n";
  print $lpar_csv "HMC;server;lpar_name;curr_shared_proc_pool_name;curr_proc_mode;curr_procs;curr_proc_units;curr_sharing_mode;curr_uncap_weight;lpar_id;default_profile;min_proc_units;desired_proc_units;max_proc_units;curr_min_proc_units;curr_max_proc_units;min_procs;desired_procs;max_procs;curr_min_procs;curr_max_procs;min_mem;desired_mem;max_mem;curr_min_mem;curr_mem;curr_max_mem;state;lpar_env;os_version;hostname\n";

  #NPIV
  my $header = [ "Server", "MapPort", "LocalPartition", "ConnPartition", "ConnVirtualSlotNumber", "LocationCode", "WWPNs", "PhysPortAvailablePorts", "PhysPortTotalPorts", "PhysPortPortName", "PhysPortWWPN", "PhysPortLocationCode" ];
  foreach my $h ( @{$header} ) {
    print $npiv_csv "$h$separator";
  }
  print $npiv_csv "\n";
  my $file_npiv_conf = "$work_folder/tmp/restapi/npiv_conf.json";
  my $npiv           = Xorux_lib::read_json($file_npiv_conf) if ( -f $file_npiv_conf );
  foreach my $server_uid ( keys %{$npiv} ) {
    my $server_uid_short = substr( $server_uid, 0, 5 );
    if ( $server_uid eq "" ) { next; }
    if ( ref( $npiv->{$server_uid} ) eq "ARRAY" ) {
      foreach my $map ( @{ $npiv->{$server_uid} } ) {
        if   ( defined $map->{SystemName} ) { print $npiv_csv "$map->{SystemName}$separator"; }
        else                                { print $npiv_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{MapPort} ) { print $npiv_csv "$map->{ServerAdapter}{MapPort}$separator"; }
        else                                            { print $npiv_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{LocalPartition} ) { print $npiv_csv "$map->{ServerAdapter}{LocalPartition}$separator"; }
        else                                                   { print $npiv_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{ConnectingPartition} ) { print $npiv_csv "$map->{ServerAdapter}{ConnectingPartition}$separator"; }
        else                                                        { print $npiv_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{ConnectingVirtualSlotNumber} ) { print $npiv_csv "$map->{ServerAdapter}{ConnectingVirtualSlotNumber}$separator"; }
        else                                                                { print $npiv_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{VirtualSlotNumber} ) { print $npiv_csv "$map->{ServerAdapter}{VirtualSlotNumber}$separator"; }
        else                                                      { print $npiv_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{LocationCode} ) { print $npiv_csv "$map->{ServerAdapter}{LocationCode}$separator"; }
        else                                                 { print $npiv_csv "$separator"; }
        if   ( defined $map->{ClientAdapter}{WWPNs} ) { print $npiv_csv "$map->{ClientAdapter}{WWPNs}$separator"; }
        else                                          { print $npiv_csv "$separator"; }
        if   ( defined $map->{Port}{AvailablePorts} ) { print $npiv_csv "$map->{Port}{AvailablePorts}$separator"; }
        else                                          { print $npiv_csv "$separator"; }
        if   ( defined $map->{Port}{TotalPorts} ) { print $npiv_csv "$map->{Port}{TotalPorts}$separator"; }
        else                                      { print $npiv_csv "$separator"; }
        if   ( defined $map->{Port}{PortName} ) { print $npiv_csv "$map->{Port}{PortName}$separator"; }
        else                                    { print $npiv_csv "$separator"; }
        if   ( defined $map->{Port}{WWPN} ) { print $npiv_csv "$map->{Port}{WWPN}$separator"; }
        else                                { print $npiv_csv "$separator"; }
        if   ( defined $map->{Port}{LocationCode} ) { print $npiv_csv "$map->{Port}{LocationCode}"; }
        else                                        { print $npiv_csv ""; }
        print $npiv_csv "\n";
      }
    }
  }

  #VSCI

  $header = [ "Server", "VIOS", "VIOSAdapter", "ServerSlot", "ClientLPAR", "ClientSlot", "BackingDevice", "VirtualDiskName", "Partition", "Capacity[GB]", "Label", "VolumeName", "Capacity[GB]", "State", "LocationCode" ];
  foreach my $h ( @{$header} ) {
    print $vscsi_csv "$h$separator";
  }
  print $vscsi_csv "\n";
  my $file_vscsi_conf = "$work_folder/tmp/restapi/vscsi_conf.json";
  my $vscsi           = Xorux_lib::read_json($file_vscsi_conf) if ( -f $file_npiv_conf );
  foreach my $server_uid ( keys %{$vscsi} ) {
    if ( $server_uid eq "" ) { next; }
    if ( ref( $vscsi->{$server_uid} ) eq "ARRAY" ) {
      foreach my $map ( @{ $vscsi->{$server_uid} } ) {
        $map->{Storage}{VirtualDisk}{PartitionSize}     = sprintf( "%.1f", $map->{Storage}{VirtualDisk}{PartitionSize} )            if defined $map->{Storage}{VirtualDisk}{PartitionSize};
        $map->{Storage}{VirtualDisk}{DiskCapacity}      = sprintf( "%.1f", $map->{Storage}{VirtualDisk}{DiskCapacity} )             if defined $map->{Storage}{VirtualDisk}{DiskCapacity};
        $map->{Storage}{PhysicalVolume}{VolumeCapacity} = sprintf( "%.1f", $map->{Storage}{PhysicalVolume}{VolumeCapacity} / 1024 ) if defined $map->{Storage}{PhysicalVolume}{VolumeCapacity};
        if ( !defined $map->{Storage}{VirtualDisk}{DiskLabel} ) {
          $map->{Storage}{VirtualDisk}{DiskLabel} = "";
        }
        if   ( defined $map->{ServerAdapter}{SystemName} ) { print $vscsi_csv "$map->{ServerAdapter}{SystemName}$separator"; }
        else                                               { print $vscsi_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{RemoteLogicalPartitionName} ) { print $vscsi_csv "$map->{ServerAdapter}{RemoteLogicalPartitionName}$separator"; }
        else                                                               { print $vscsi_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{AdapterName} ) { print $vscsi_csv "$map->{ServerAdapter}{AdapterName}$separator"; }
        else                                                { print $vscsi_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{VirtualSlotNumber} ) { print $vscsi_csv "$map->{ServerAdapter}{VirtualSlotNumber}$separator"; }
        else                                                      { print $vscsi_csv "$separator"; }
        if   ( defined $map->{Partition} ) { print $vscsi_csv "$map->{Partition}$separator"; }
        else                               { print $vscsi_csv "$separator"; }
        if   ( defined $map->{ClientAdapter}{VirtualSlotNumber} ) { print $vscsi_csv "$map->{ClientAdapter}{VirtualSlotNumber}$separator"; }
        else                                                      { print $vscsi_csv "$separator"; }
        if   ( defined $map->{ServerAdapter}{BackingDeviceName} ) { print $vscsi_csv "$map->{ServerAdapter}{BackingDeviceName}$separator"; }
        else                                                      { print $vscsi_csv "$separator"; }
        if   ( defined $map->{Storage}{VirtualDisk}{DiskName} ) { print $vscsi_csv "$map->{Storage}{VirtualDisk}{DiskName}$separator"; }
        else                                                    { print $vscsi_csv "$separator"; }
        if   ( defined $map->{Storage}{VirtualDisk}{PartitionSize} ) { print $vscsi_csv "$map->{Storage}{VirtualDisk}{PartitionSize}$separator"; }
        else                                                         { print $vscsi_csv "$separator"; }
        if   ( defined $map->{Storage}{VirtualDisk}{DiskCapacity} ) { print $vscsi_csv "$map->{Storage}{VirtualDisk}{DiskCapacity}$separator"; }
        else                                                        { print $vscsi_csv "$separator"; }
        if   ( defined $map->{Storage}{VirtualDisk}{DiskLabel} ) { print $vscsi_csv "$map->{Storage}{VirtualDisk}{DiskLabel}$separator"; }
        else                                                     { print $vscsi_csv "$separator"; }
        if   ( defined $map->{Storage}{PhysicalVolume}{VolumeName} ) { print $vscsi_csv "$map->{Storage}{PhysicalVolume}{VolumeName}$separator"; }
        else                                                         { print $vscsi_csv "$separator"; }
        if   ( defined $map->{Storage}{PhysicalVolume}{VolumeCapacity} ) { print $vscsi_csv "$map->{Storage}{PhysicalVolume}{VolumeCapacity}$separator"; }
        else                                                             { print $vscsi_csv "$separator"; }
        if   ( defined $map->{Storage}{PhysicalVolume}{VolumeState} ) { print $vscsi_csv "$map->{Storage}{PhysicalVolume}{VolumeState}$separator"; }
        else                                                          { print $vscsi_csv "$separator"; }
        if   ( defined $map->{Storage}{PhysicalVolume}{LocationCode} ) { print $vscsi_csv "$map->{Storage}{PhysicalVolume}{LocationCode}$separator"; }
        else                                                           { print $vscsi_csv "$separator"; }
        print $vscsi_csv "\n";
      }
    }
  }

  #INTERFACES

  my $file_interface_conf = "$work_folder/tmp/restapi/env_conf.json";
  my $env                 = Xorux_lib::read_json($file_interface_conf) if ( -f $file_interface_conf );
  $header = [ "Server", "DeviceName", "Partition", "Ports", "WWPN", "Description" ];
  foreach my $h ( @{$header} ) {
    print $interfaces_csv "$h$separator";
  }
  print $interfaces_csv "\n";

  foreach my $server ( keys %{$env} ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : interfaces creating for $server\n";
    foreach my $serial ( keys %{ $env->{$server} } ) {
      foreach my $box_code ( keys %{ $env->{$server}{$serial} } ) {
        my $B  = $env->{$server}{$serial}{$box_code};
        my $DN = "";
        $DN = $B->{DeviceName} if defined $B->{DeviceName};
        my $DC = "";
        $DC = $B->{Description} if defined $B->{Description};
        my $PN = "";
        $PN = $B->{PartitionName} if defined $B->{PartitionName};
        my $b_devicename    = "";
        my $b_partitionname = "";
        my $b_description   = "";
        $b_devicename    = $DN;
        $b_partitionname = $PN;
        $b_description   = $DC;

        if ( defined $B->{Trunk} ) {
          ( undef, undef, my $k ) = split( '\.', $DN );
          my $trunks     = "";
          my $wwpns      = "";
          my $partitions = "";
          my @TR;
          if ( defined $B->{Trunk} && ref( $B->{Trunk} ) eq "HASH" ) {
            @TR = ( sort keys %{ $B->{Trunk} } );
          }
          foreach my $trunk_loc (@TR) {
            $trunks .= $trunk_loc;
            if ( defined $B->{Trunk}{$trunk_loc}{en_name} ) {
              $trunks .= " / $B->{Trunk}{$trunk_loc}{en_name}";
            }
            if ( defined $B->{Trunk}{$trunk_loc}{name} ) {
              $trunks .= " / $B->{Trunk}{$trunk_loc}{name}";
            }
            $trunks .= " | ";
            $wwpns  .= "$B->{Trunk}{$trunk_loc}{wwpn} | " if defined $B->{Trunk}{$trunk_loc}{wwpn};
            if ( !defined $partitions || $partitions eq "" ) {
              $partitions = "$B->{Trunk}{$trunk_loc}{partition}" if defined $B->{Trunk}{$trunk_loc}{partition};
            }
            elsif ( defined $B->{Trunk}{$trunk_loc}{partition} && $partitions =~ m/$B->{Trunk}{$trunk_loc}{partition}/ ) {
              next;
            }
            else {
              $partitions .= "$B->{Trunk}{$trunk_loc}{partition}" if defined $B->{Trunk}{$trunk_loc}{partition};
            }
          }
          print $interfaces_csv "$server$separator$DN$separator$partitions$separator$trunks$separator$wwpns$separator$DC\n";
        }
        else {
          print $interfaces_csv "$server$separator$DN$separator$PN$separator$separator$separator$separator$DC\n";
        }
      }
    }
  }

  foreach my $file (@files) {    # forech hmc_info (foreach host)
    ( undef, my $host_from_file ) = split( "HMC_INFO_", $file );
    ( $host_from_file, undef ) = split( '\.json', $host_from_file );
    my $HMC_INFO = {};
    $HMC_INFO = Xorux_lib::read_json($file) if ( -f $file );
    foreach my $i ( keys %{$HMC_INFO} ) {    # foreach server
      my $s           = $HMC_INFO->{$i};
      my $CONFIG_path = "$work_folder/data/$s->{name}/$host_from_file/CONFIG.json";
      my $CONFIG_old  = Xorux_lib::file_time_diff($CONFIG_path);
      if ( $CONFIG_old == 0 || $CONFIG_old >= 864000 ) {
        print "ACT skip $CONFIG_old due to its ts\n";
        next;
      }
      my $CONFIG = {};
      $CONFIG = Xorux_lib::read_json($CONFIG_path) if ( -f $CONFIG_path );
      my $act_server = $CONFIG->{'server'};
      print $server_csv "$host_from_file;$s->{name};$s->{MachineType}{content}-$s->{Model}{content};$s->{SerialNumber}{content};" . ( $act_server->{ConfigurableSystemProcessorUnits} ) . ";" . ( $act_server->{ConfigurableSystemMemory} ) . ";$act_server->{CurrentAvailableSystemMemory};;;;$act_server->{InstalledSystemProcessorUnits};$act_server->{CurrentAvailableSystemProcessorUnits}\n";
      foreach my $poolId ( keys %{ $CONFIG->{shared_pools} } ) {
        my $shp = $CONFIG->{shared_pools}{$poolId};
        if ( $shp->{PoolName} ne "DefaultPool" ) {
          print $server_csv "$host_from_file;$s->{name};$s->{MachineType}{content}-$s->{Model}{content};$s->{SerialNumber}{content};;;;$shp->{PoolName};$shp->{CurrentReservedProcessingUnits};$shp->{MaximumProcessingUnits};;\n";
        }
      }
      foreach my $ln ( keys %{ $CONFIG->{'lpar'} } ) {
        if (! defined $CONFIG->{'lpar'}{$ln}{CurrentSharingMode}){
          $CONFIG->{'lpar'}{$ln}{CurrentSharingMode} = "undefined";
        }
        my $curr_proc_mode = "uncap";
        if ( !( $CONFIG->{'lpar'}{$ln}{CurrentSharingMode} =~ m/uncap/ ) ) {
          $curr_proc_mode = "shared";
        }
        $ln =~ s/;//g;
        my $SharedProcessorPoolID           = "";
        my $SharedProcessorPoolName         = "";
        my $CurrentProcessors               = "";
        my $CurrentProcessingUnits          = "";
        my $CurrentSharingMode              = "";
        my $CurrentUncappedWeight           = "";
        my $PartitionID                     = "";
        my $MinimumProcessingUnits          = "";
        my $MaximumProcessingUnits          = "";
        my $DesiredProcessingUnits          = "";
        my $CurrentMinimumProcessingUnits   = "";
        my $CurrentMaximumProcessingUnits   = "";
        my $MinimumProcessors               = "";
        my $MaximumProcessors               = "";
        my $CurrentMinimumProcessors        = "";
        my $MinimumMemory                   = "";
        my $DesiredMemory                   = "";
        my $MaximumMemory                   = "";
        my $DesiredProcessors               = "";
        my $CurrentMaximumProcessors        = "";
        my $CurrentMinimumMemory            = "";
        my $CurrentMemory                   = "";
        my $CurrentMaximumMemory            = "";
        my $PartitionState                  = "";
        my $OperatingSystemVersion          = "";
        my $AllocatedVirtualProcessors      = "";
        my $MaximumVirtualProcessors        = "";
        my $MinimumVirtualProcessors        = "";
        my $CurrentMaximumVirtualProcessors = "";
        my $CurrentMinimumVirtualProcessors = "";
        my $DesiredVirtualProcessors        = "";
        my $profile_name = "";
        my $hostname = "";

        $profile_name           = $CONFIG->{'lpar'}{$ln}{profile_name}             if ( defined $CONFIG->{'lpar'}{$ln}{profile_name} );
        $hostname           = $CONFIG->{'lpar'}{$ln}{hostname}             if ( defined $CONFIG->{'lpar'}{$ln}{hostname} );
        $SharedProcessorPoolID           = $CONFIG->{'lpar'}{$ln}{SharedProcessorPoolID}             if ( defined $CONFIG->{'lpar'}{$ln}{SharedProcessorPoolID} );
        $SharedProcessorPoolName         = $CONFIG->{'lpar'}{$ln}{SharedProcessorPoolName}           if ( defined $CONFIG->{'lpar'}{$ln}{SharedProcessorPoolName} );
        $CurrentProcessors               = $CONFIG->{'lpar'}{$ln}{CurrentProcessors}                 if ( defined $CONFIG->{'lpar'}{$ln}{CurrentProcessors} );
        $CurrentProcessingUnits          = $CONFIG->{'lpar'}{$ln}{CurrentProcessingUnits}            if ( defined $CONFIG->{'lpar'}{$ln}{CurrentProcessingUnits} );
        $CurrentSharingMode              = $CONFIG->{'lpar'}{$ln}{CurrentSharingMode}                if ( defined $CONFIG->{'lpar'}{$ln}{CurrentSharingMode} );
        $CurrentUncappedWeight           = $CONFIG->{'lpar'}{$ln}{CurrentUncappedWeight}             if ( defined $CONFIG->{'lpar'}{$ln}{CurrentUncappedWeight} );
        $PartitionID                     = $CONFIG->{'lpar'}{$ln}{PartitionID}                       if ( defined $CONFIG->{'lpar'}{$ln}{PartitionID} );
        $MinimumProcessingUnits          = $CONFIG->{'lpar'}{$ln}{MinimumProcessingUnits}            if ( defined $CONFIG->{'lpar'}{$ln}{MinimumProcessingUnits} );
        $MaximumProcessingUnits          = $CONFIG->{'lpar'}{$ln}{MaximumProcessingUnits}            if ( defined $CONFIG->{'lpar'}{$ln}{MaximumProcessingUnits} );
        $DesiredProcessingUnits          = $CONFIG->{'lpar'}{$ln}{DesiredProcessingUnits}            if ( defined $CONFIG->{'lpar'}{$ln}{DesiredProcessingUnits} );
        $CurrentMinimumProcessingUnits   = $CONFIG->{'lpar'}{$ln}{CurrentMinimumProcessingUnits}     if ( defined $CONFIG->{'lpar'}{$ln}{CurrentMinimumProcessingUnits} );
        $CurrentMaximumProcessingUnits   = $CONFIG->{'lpar'}{$ln}{CurrentMaximumProcessingUnits}     if ( defined $CONFIG->{'lpar'}{$ln}{CurrentMaximumProcessingUnits} );
        $MinimumProcessors               = $CONFIG->{'lpar'}{$ln}{MinimumProcessors}                 if ( defined $CONFIG->{'lpar'}{$ln}{MinimumProcessors} );
        $MaximumProcessors               = $CONFIG->{'lpar'}{$ln}{MaximumProcessors}                 if ( defined $CONFIG->{'lpar'}{$ln}{MaximumProcessors} );
        $DesiredProcessors               = $CONFIG->{'lpar'}{$ln}{DesiredProcessors}                 if ( defined $CONFIG->{'lpar'}{$ln}{DesiredProcessors} );
        $CurrentMinimumProcessors        = $CONFIG->{'lpar'}{$ln}{CurrentMinimumProcessors}          if ( defined $CONFIG->{'lpar'}{$ln}{CurrentMinimumProcessors} );
        $CurrentMaximumProcessors        = $CONFIG->{'lpar'}{$ln}{CurrentMaximumProcessors}          if ( defined $CONFIG->{'lpar'}{$ln}{CurrentMaximumProcessors} );
        $MinimumMemory                   = $CONFIG->{'lpar'}{$ln}{MinimumMemory}                     if ( defined $CONFIG->{'lpar'}{$ln}{MinimumMemory} );
        $DesiredMemory                   = $CONFIG->{'lpar'}{$ln}{DesiredMemory}                     if ( defined $CONFIG->{'lpar'}{$ln}{DesiredMemory} );
        $MaximumMemory                   = $CONFIG->{'lpar'}{$ln}{MaximumMemory}                     if ( defined $CONFIG->{'lpar'}{$ln}{MaximumMemory} );
        $CurrentMinimumMemory            = $CONFIG->{'lpar'}{$ln}{CurrentMinimumMemory}              if ( defined $CONFIG->{'lpar'}{$ln}{CurrentMinimumMemory} );
        $CurrentMemory                   = $CONFIG->{'lpar'}{$ln}{CurrentMemory}                     if ( defined $CONFIG->{'lpar'}{$ln}{CurrentMemory} );
        $CurrentMaximumMemory            = $CONFIG->{'lpar'}{$ln}{CurrentMaximumMemory}              if ( defined $CONFIG->{'lpar'}{$ln}{CurrentMaximumMemory} );
        $PartitionState                  = $CONFIG->{'lpar'}{$ln}{PartitionState}                    if ( defined $CONFIG->{'lpar'}{$ln}{PartitionState} );
        $OperatingSystemVersion          = $CONFIG->{'lpar'}{$ln}{OperatingSystemVersion}            if ( defined $CONFIG->{'lpar'}{$ln}{OperatingSystemVersion} );
        $AllocatedVirtualProcessors      = $CONFIG->{'lpar'}{$ln}{AllocatedVirtualProcessors}        if ( defined $CONFIG->{'lpar'}{$ln}{AllocatedVirtualProcessors} );
        $CurrentMaximumVirtualProcessors = $CONFIG->{'lpar'}{$ln}{"CurrentMaximumVirtualProcessors"} if ( defined $CONFIG->{'lpar'}{$ln}{CurrentMaximumVirtualProcessors} );
        $CurrentMinimumVirtualProcessors = $CONFIG->{'lpar'}{$ln}{"CurrentMinimumVirtualProcessors"} if ( defined $CONFIG->{'lpar'}{$ln}{CurrentMinimumVirtualProcessors} );
        $DesiredVirtualProcessors        = $CONFIG->{'lpar'}{$ln}{"DesiredVirtualProcessors"}        if ( defined $CONFIG->{'lpar'}{$ln}{DesiredVirtualProcessors} );
        $MaximumVirtualProcessors        = $CONFIG->{'lpar'}{$ln}{"MaximumVirtualProcessors"}        if ( defined $CONFIG->{'lpar'}{$ln}{MaximumVirtualProcessors} );
        $MinimumVirtualProcessors        = $CONFIG->{'lpar'}{$ln}{"MinimumVirtualProcessors"}        if ( defined $CONFIG->{'lpar'}{$ln}{MinimumVirtualProcessors} );

        if ( $CurrentProcessingUnits eq "" && $CurrentProcessors ne "" )          { $CurrentProcessingUnits = $CurrentProcessors; }
        if ( $CurrentProcessors eq ""      && $AllocatedVirtualProcessors ne "" ) { $CurrentProcessors      = $AllocatedVirtualProcessors; }

        print $lpar_csv "$host_from_file;$s->{name};$ln;$SharedProcessorPoolName;$curr_proc_mode;$CurrentProcessors;$CurrentProcessingUnits;$CurrentSharingMode;$CurrentUncappedWeight;$PartitionID;$profile_name;$MinimumProcessingUnits;$DesiredProcessingUnits;$MaximumProcessingUnits;$CurrentMinimumProcessingUnits;$CurrentMaximumProcessingUnits;$MinimumProcessors;$DesiredProcessors;$MaximumProcessors;$CurrentMinimumProcessors;$CurrentMaximumProcessors;$MinimumMemory;$DesiredMemory;$MaximumMemory;$CurrentMinimumMemory;$CurrentMemory;$CurrentMaximumMemory;$PartitionState;;$OperatingSystemVersion;$hostname\n";
      }
      undef $CONFIG;
    }
  }

  close($server_csv);
  close($lpar_csv);
  close($npiv_csv);
  close($vscsi_csv);
  close($interfaces_csv);
}

sub environment_configuration {
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration DEBUG - servername / server_id - 1\n";
  my $ManagedSystem = callAPI("rest/api/uom/ManagedSystem");
  if ( ref($ManagedSystem) ne "HASH" ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : Return -1 from environment_configuration because respond is not valid\n";
    print Dumper $ManagedSystem;
    return -1;
  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration DEBUG - servername / server_id - 2\n";
  my $out             = "";
  my $adapter_box_loc = {};
  my $vlany;
  my $network_conf = {};
  my @server_ids   = ();
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration DEBUG - servername / server_id - 3\n";

  if ( ref( $ManagedSystem->{entry} ) ne "HASH" ) {
    warn "Rest API       " . "ManagedSystem ref is not hash, this is the response:\n";
    warn Dumper $ManagedSystem;
  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration DEBUG - servername / server_id - 4\n";
  my $ManagedSystemsContent = {};
  if ( defined $ManagedSystem->{'entry'}{'id'} ) {
    my $server_id = $ManagedSystem->{'entry'}{'id'};
    push @server_ids, $server_id;
    $ManagedSystemsContent->{$server_id} = $ManagedSystem->{'entry'}{'content'}{'ManagedSystem:ManagedSystem'};
  }
  else {
    @server_ids = keys %{ $ManagedSystem->{entry} };
    foreach my $s_id (@server_ids) {
      $ManagedSystemsContent->{$s_id} = $ManagedSystem->{'entry'}{$s_id}{'content'}{'ManagedSystem:ManagedSystem'};
    }
  }
  foreach my $server_id (@server_ids) {

    #    my $shared_detail = callAPI("rest/api/uom/ManagedSystem/$server_id/NetworkBridge/");
    #    print Dumper $shared_detail;
    #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - servername / server_id - 5\n";
    my $interface_info      = {};
    my $interface_info_file = "$work_folder/tmp/restapi/interface_info_$server_id.json";
    $interface_info = Xorux_lib::read_json($interface_info_file) if ( -f $interface_info_file );
    my $IO         = {};
    my $servername = "";
    $IO         = $ManagedSystemsContent->{$server_id}{'AssociatedSystemIOConfiguration'} if ( defined $ManagedSystemsContent->{$server_id}{'AssociatedSystemIOConfiguration'} );
    $servername = $ManagedSystemsContent->{$server_id}{'SystemName'}{'content'}           if ( defined $ManagedSystemsContent->{$server_id}{'SystemName'}{'content'} );
    if ( ref($IO) ne "HASH" || $servername eq "" ) { print localtime(time) . __FILE__ . ":" . __LINE__ . " : " . "Skipping IO for $server_id at $host\n"; next; }
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - $servername / server_id\n";
    my $server_serial;
    my $LAN_aliases_file = "$work_folder/data/$servername/$host/LAN_aliases.json";
    my $SAN_aliases_file = "$work_folder/data/$servername/$host/SAN_aliases.json";
    my $SAS_aliases_file = "$work_folder/data/$servername/$host/SAS_aliases.json";
    my $LAN_aliases      = {};
    my $SAN_aliases      = {};
    my $SAS_aliases      = {};
    $LAN_aliases = Xorux_lib::read_json($LAN_aliases_file) if ( -f $LAN_aliases_file );
    $SAN_aliases = Xorux_lib::read_json($SAN_aliases_file) if ( -f $SAN_aliases_file );
    $SAS_aliases = Xorux_lib::read_json($SAS_aliases_file) if ( -f $SAS_aliases_file );
    my $A;
    foreach my $a ( keys %{$LAN_aliases} ) { $A->{$a} = $LAN_aliases->{$a}; }
    foreach my $a ( keys %{$SAN_aliases} ) { $A->{$a} = $SAN_aliases->{$a}; }
    foreach my $a ( keys %{$SAS_aliases} ) { $A->{$a} = $SAS_aliases->{$a}; }

    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - IOSlots\n";
    my $IOSlotsArray = force_me_array_ref( $IO->{IOSlots}{IOSlot} );
    my $WWPNPrefix   = $IO->{'WWPNPrefix'}{'content'};
    foreach my $IOSlot ( @{$IOSlotsArray} ) {

      #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 6\n";
      my $PartitionName                           = $IOSlot->{'PartitionName'}{'content'};                              #
      my $IOUnitPhysicalLocation                  = $IOSlot->{'IOUnitPhysicalLocation'}{'content'};                     #"U78C0.001.DBJB578"
      my $SlotDynamicReconfigurationConnectorName = $IOSlot->{'SlotDynamicReconfigurationConnectorName'}{'content'};    #"U78C0.001.DBJB578-P2-T3"
      my $PartitionID                             = $IOSlot->{'PartitionID'}{'content'};                                #1
      my $SlotPhysicalLocationCode                = $IOSlot->{'SlotPhysicalLocationCode'}{'content'};                   #C8 / C8-T7?
      my $PCIClass                                = $IOSlot->{'PCIClass'}{'content'};
      my $Description                             = $IOSlot->{'Description'}{'content'};

      #my $box_loc_name = $SlotDynamicReconfigurationConnectorName;
      my $box_loc_name = $IOSlot->{'RelatedIOAdapter'}{'IOAdapter'}{'DeviceName'}{'content'};

      #my $box_loc_name = $SlotDynamicReconfigurationConnectorName;
      $box_loc_name =~ s/$IOUnitPhysicalLocation-//g;

      #     print "IO SLOT $SlotDynamicReconfigurationConnectorName $SlotPhysicalLocationCode = $PartitionName\n"; print Dumper $IOSlot;
      #     print "IO SLOT OUT: $PartitionName $IOUnitPhysicalLocation $SlotDynamicReconfigurationConnectorName $PartitionID $SlotPhysicalLocationCode $PCIClass $WWPNPrefix\n";
      $adapter_box_loc->{$servername}{$IOUnitPhysicalLocation}{$box_loc_name}{PartitionName}                           = $PartitionName;
      $adapter_box_loc->{$servername}{$IOUnitPhysicalLocation}{$box_loc_name}{IOUnitPhysicalLocation}                  = $IOUnitPhysicalLocation;
      $adapter_box_loc->{$servername}{$IOUnitPhysicalLocation}{$box_loc_name}{SlotDynamicReconfigurationConnectorName} = $SlotDynamicReconfigurationConnectorName;
      $adapter_box_loc->{$servername}{$IOUnitPhysicalLocation}{$box_loc_name}{PartitionID}                             = $PartitionID;
      $adapter_box_loc->{$servername}{$IOUnitPhysicalLocation}{$box_loc_name}{SlotPhysicalLocationCode}                = $SlotPhysicalLocationCode;
      $adapter_box_loc->{$servername}{$IOUnitPhysicalLocation}{$box_loc_name}{PCIClass}                                = $PCIClass;
      $adapter_box_loc->{$servername}{$IOUnitPhysicalLocation}{$box_loc_name}{Description}                             = $Description;
      $adapter_box_loc->{$servername}{$IOUnitPhysicalLocation}{$box_loc_name}{WWPNPrefix}                              = $WWPNPrefix;
      $adapter_box_loc->{$servername}{$IOUnitPhysicalLocation}{$box_loc_name}{DeviceName}                              = $SlotDynamicReconfigurationConnectorName;
    }
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - IOBuses\n";
    my $IOBusesArray = force_me_array_ref( $IO->{IOBuses}{IOBus} );
    foreach my $IOBus ( @{$IOBusesArray} ) {

      #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 7\n";
      next;    #not implemented yet
      if ( defined $IOBus && ref($IOBus) eq "HASH" ) {
        my $BackplanePhysicalLocation               = "";
        my $IOBusID                                 = "";
        my $BusDynamicReconfigurationConnectorName  = "";
        my $IOSlot                                  = "";
        my $PartitionName                           = "";
        my $IOUnitPhysicalLocation                  = "";
        my $SlotDynamicReconfigurationConnectorName = "";
        my $PartitionID                             = "";
        $IOBusID                                 = $IOBus->{'IOBusID'}{'content'}                                  if defined $IOBus->{'IOBusID'}{'content'};
        $BackplanePhysicalLocation               = $IOBus->{'BackplanePhysicalLocation'}{'content'}                if defined $IOBus->{'BackplanePhysicalLocation'}{'content'};
        $BusDynamicReconfigurationConnectorName  = $IOBus->{'BusDynamicReconfigurationConnectorName'}{'content'}   if defined $IOBus->{'BusDynamicReconfigurationConnectorName'}{'content'};
        $IOSlot                                  = $IOBus->{'IOSlots'}{'IOSlot'}                                   if defined $IOBus->{'IOSlots'}{'IOSlot'};
        $PartitionName                           = $IOSlot->{'PartitionName'}{'content'}                           if defined $IOSlot->{'PartitionName'}{'content'};
        $IOUnitPhysicalLocation                  = $IOSlot->{'IOUnitPhysicalLocation'}{'content'}                  if defined $IOSlot->{'IOUnitPhysicalLocation'}{'content'};
        $SlotDynamicReconfigurationConnectorName = $IOSlot->{'SlotDynamicReconfigurationConnectorName'}{'content'} if defined $IOSlot->{'SlotDynamicReconfigurationConnectorName'}{'content'};
        $PartitionID                             = $IOSlot->{'PartitionID'}{'content'}                             if defined $IOSlot->{'PartitionID'}{'content'};
      }
    }
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - IOAdapters\n";
    my $IOAdapterChoiceArr = force_me_array_ref( $IO->{IOAdapters}{IOAdapterChoice} );
    foreach my $IOAdapter ( @{$IOAdapterChoiceArr} ) {

      #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 8\n";
      $IOAdapter = $IOAdapter->{IOAdapter};
      my $DeviceName     = "";
      my $UniqueDeviceID = "";
      my $Description    = "";
      my $box_loc_name   = "";
      my $server_def     = "";
      my $server_serial  = "";
      $DeviceName     = $IOAdapter->{'DeviceName'}{'content'}     if defined $IOAdapter->{'DeviceName'}{'content'};
      $UniqueDeviceID = $IOAdapter->{'UniqueDeviceID'}{'content'} if defined $IOAdapter->{'UniqueDeviceID'}{'content'};
      $Description    = $IOAdapter->{'Description'}{'content'}    if defined $IOAdapter->{'Description'}{'content'};
      $box_loc_name = substr( $DeviceName, 18 );
      $server_def   = substr( $DeviceName, 0, 17 );
      $server_serial = $DeviceName;
      $server_serial =~ s/-$box_loc_name//g;
      $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{Description}    = $Description if !defined $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{Description};
      $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{DeviceName}     = $DeviceName;
      $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{UniqueDeviceID} = $UniqueDeviceID;
      ( undef, undef, my $alias_mapping_name ) = split( '\.', $server_def );
      $alias_mapping_name = "$alias_mapping_name-$box_loc_name";

      foreach my $alias_in_file ( keys %{$A} ) {
        if ( $alias_in_file =~ "$alias_mapping_name-" ) {
          $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{Trunk}{$alias_in_file}{name}      = $A->{$alias_in_file}{alias};
          $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{Trunk}{$alias_in_file}{partition} = $A->{$alias_in_file}{partition};
          $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{Trunk}{$alias_in_file}{wwpn}      = $A->{$alias_in_file}{wwpn};
        }
      }
    }
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - Interface Info\n";

    #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 9\n";
    if ( defined $interface_info && ref($interface_info) eq "HASH" ) {
      foreach my $phys_loc ( keys %{$interface_info} ) {

        #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 10\n";
        print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - Interface Info - Phys Loc:$phys_loc\n";
        if ( !defined $phys_loc || $phys_loc eq "" ) {
          print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - Interface Info - Phys Loc WRONG\n";
          next;
        }
        my $box_loc_name  = substr( $phys_loc, 18 );
        my $device_name_C = $phys_loc;
        my $server_serial = $phys_loc;
        $server_serial =~ s/-P.*//g;
        $device_name_C =~ s/-T.*//g;
        $box_loc_name  =~ s/-T.*//g;
        my $short_phys_loc = $phys_loc;
        ( undef, undef, $short_phys_loc ) = split( '\.', $short_phys_loc );
        $short_phys_loc = "" if (!defined $short_phys_loc);
        $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{DeviceName}  .= " $device_name_C"                            if ( !defined $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{DeviceName} || $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{DeviceName} eq "" );
        $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{Description} .= " $interface_info->{$phys_loc}{Description}" if ( defined $interface_info->{$phys_loc}{Description} && ( !defined $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{Description} || $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{Description} eq "" ) );
        $adapter_box_loc->{$servername}{$server_serial}{$box_loc_name}{Trunk}{$short_phys_loc}{en_name} = $interface_info->{$phys_loc}{InterfaceName};
      }
    }
    else {
      print "Rest API !     " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - no Interface Info\n";
    }
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - Adapters on $servername\n";

    #print Dumper $adapter_box_loc;

    #  print "Virtual Switches on $server_id\n";

    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - VirtSwitchArr\n";

    #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 11\n";
    my $VirtSwitchArr = force_me_array_ref( $IO->{'AssociatedSystemVirtualNetwork'}{'VirtualSwitches'}{'link'} );
    foreach my $item ( @{$VirtSwitchArr} ) {
      next;

      #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 12\n";
      my $link   = $item->{'href'};
      my $Switch = callAPI($link);
      if ( ref($Switch) ne "HASH" ) {
        next;
      }

      #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 13\n";
      $Switch = $Switch->{'content'}{'VirtualSwitch:VirtualSwitch'};
      my $SwitchID    = "";
      my $SwitchName  = "";
      my $SwitchVlans = "";
      $SwitchID   = $Switch->{'SwitchID'}{'content'}   if defined $Switch->{'SwitchID'}{'content'};
      $SwitchName = $Switch->{'SwitchName'}{'content'} if defined $Switch->{'SwitchName'}{'content'};
      if ( defined $Switch->{'VirtualNetworks'} ) {
        $SwitchVlans = $Switch->{'VirtualNetworks'};
        my $SwitchVLANS = force_me_array_ref( $SwitchVlans->{'link'} );
        foreach my $VLAN ( @{$SwitchVLANS} ) {
          my $vlan_content = callAPI( $VLAN->{'href'} );
          if ( ref($vlan_content) ne "HASH" ) {
            next;
          }
          if ( !defined $vlan_content || $vlan_content == -1 ) {
            print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : SKIP vlan $VLAN\n";
            next;
          }
          $vlan_content                                                                                                                              = $vlan_content->{'content'}{'VirtualNetwork:VirtualNetwork'};
          $network_conf->{$servername}{'VirtualSwitch'}{$SwitchName}{'SwitchVlans'}{ $vlan_content->{'NetworkName'}{'content'} }{'TaggedNetwork'}    = $vlan_content->{'TaggedNetwork'}{'content'};
          $network_conf->{$servername}{'VirtualSwitch'}{$SwitchName}{'SwitchVlans'}{ $vlan_content->{'NetworkName'}{'content'} }{'NetworkVLANID'}    = $vlan_content->{'NetworkVLANID'}{'content'};
          $network_conf->{$servername}{'VirtualSwitch'}{$SwitchName}{'SwitchVlans'}{ $vlan_content->{'NetworkName'}{'content'} }{'VswitchID'}        = $vlan_content->{'VswitchID'}{'content'};
          $network_conf->{$servername}{'VirtualSwitch'}{$SwitchName}{'SwitchVlans'}{ $vlan_content->{'NetworkName'}{'content'} }{'AssociatedSwitch'} = callAPI( $vlan_content->{'AssociatedSwitch'}{'href'} )->{'content'}{'VirtualSwitch:VirtualSwitch'}{'SwitchName'}{'content'};
          $network_conf->{$servername}{'VirtualSwitch'}{$SwitchName}{'SwitchID'}                                                                     = $SwitchID;
        }
      }
    }
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration DEBUG - $servername / $server_id - 14\n";

    #  print "Virtual Networks on $server_id\n";
    my $vnet;
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - VirtNetArr\n";

    my $VirtNetArr = force_me_array_ref( $IO->{'AssociatedSystemVirtualNetwork'}{'VirtualNetworks'}{'link'} );
    eval {
      foreach my $item ( @{$VirtNetArr} ) {

        #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 15\n";
        my $link        = $item->{'href'};
        my $VirtNetwork = callAPI($link);
        if ( ref($VirtNetwork) ne "HASH" ) {
          next;
        }
        my $VN = $VirtNetwork->{content}{'VirtualNetwork:VirtualNetwork'};
        $vnet->{ $VN->{NetworkName}{content} } = $VN;
      }
    };
    if ($@) {
      print "Rest API Error : VirtNetArray ($servername @ $host)\n";
    }

    #Xorux_lib::write_json("$work_folder/tmp/restapi/$servername\__vnet__$host.json", $vnet);
    check_and_write( "$work_folder/tmp/restapi/$servername\__vnet__$host.json", $vnet, 0 );

    #   print "SEA on $server_id\n";
    my $sea;
    my $loadgroups;
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - SEAArr\n";
    my $NBridgeArr = force_me_array_ref( $IO->{'AssociatedSystemVirtualNetwork'}{'NetworkBridges'}{'link'} );
    eval {
      foreach my $item ( @{$NBridgeArr} ) {

        #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 15\n";
        my $link    = $item->{'href'};
        my $NBridge = callAPI($link);
        print "SEA0\n";
        if ( ref($NBridge) ne "HASH" ) {
          next;
        }
        my $SEA = force_me_array_ref( $NBridge->{content}{'NetworkBridge:NetworkBridge'}{'SharedEthernetAdapters'} );
        foreach my $sea_adapter ( @{$SEA} ) {
          my $sea_arr = force_me_array_ref( $sea_adapter->{SharedEthernetAdapter} );
          foreach my $sea_adap ( @{$sea_arr} ) {
            $sea->{ $sea_adap->{DeviceName}{content} } = $sea_adap;
          }
        }

        my $LOAD = force_me_array_ref( $NBridge->{content}{'NetworkBridge:NetworkBridge'}{'LoadGroups'} );
        foreach my $load_group ( @{$LOAD} ) {
          my $TRUNK = force_me_array_ref( $load_group->{LoadGroup}{TrunkAdapters} );
          foreach my $tr ( @{$TRUNK} ) {
            my $trunk_arr = force_me_array_ref( $tr->{TrunkAdapter} );
            foreach my $trunk_adap ( @{$trunk_arr} ) {
              $loadgroups->{ $trunk_adap->{DeviceName}{content} } = $trunk_adap;
            }
          }
        }
      }
    };
    if ($@) {
      print "Rest API Error : SEAArray ($servername @ $host) : $@\n";
    }

    #Xorux_lib::write_json("$work_folder/tmp/restapi/$servername\__sea__$host.json", $sea) if (defined $sea && $sea ne "");
    check_and_write( "$work_folder/tmp/restapi/$servername\__sea__$host.json", $sea, 0 );

    #Xorux_lib::write_json("$work_folder/tmp/restapi/$servername\__loadgroups__$host.json", $loadgroups) if (defined $loadgroups && $loadgroups ne "");
    check_and_write( "$work_folder/tmp/restapi/$servername\__loadgroups__$host.json", $loadgroups, 0 );

    #print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 17\n";

=cut
    foreach my $item (@{$NetBridgeArr}){
      next;
      print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 18\n";
      my $link = $item->{'href'};
      my $NetBridge = callAPI($link);
      if (ref ($NetBridge) ne "HASH"){
        next;
      }
      $NetBridge = $NetBridge->{'content'}{'NetworkBridge:NetworkBridge'};
      my $FailoverEnabled = $NetBridge->{'FailoverEnabled'}{'content'} if defined $NetBridge->{'FailoverEnabled'}{'content'};
      my $LoadBalancingEnabled = $NetBridge->{'LoadBalancingEnabled'}{'content'} if defined $NetBridge->{'LoadBalancingEnabled'}{'content'};
      my $PortVLANID = $NetBridge->{'PortVLANID'}{'content'} if defined $NetBridge->{'PortVLANID'}{'content'};
      my $UniqueDeviceID = $NetBridge->{'UniqueDeviceID'}{'content'} if defined $NetBridge->{'UniqueDeviceID'}{'content'};
      my $LoadGroups = $NetBridge->{'LoadGroups'};
      my $SharedEthernet = $NetBridge->{'SharedEthernetAdapters'};
      my $LoadGrps = force_me_array_ref($LoadGroups);
      #Load Groups in NetworkBridge
      foreach my $LG (@{$LoadGrps}){
  print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 19\n";
        my $Group = $LG->{'LoadGroup'};
        my $TrunkAdapters = force_me_array_ref($Group->{'TrunkAdapters'});
        #Trunk Adapters in LoadGroup
  print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 20\n";
        foreach my $Trunk (@{$TrunkAdapters}){
  print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 21\n";
          #print Dumper $Trunk->{TrunkAdapter};
          my $TrunkAdapterTwo = force_me_array_ref($Trunk->{TrunkAdapter});
  print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 22\n";
          foreach my $two (@{$TrunkAdapterTwo}){
  print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 23\n";
            my $AllowedOperatingSystemMACAddresses = $two->{'AllowedOperatingSystemMACAddresses'}{'content'} if defined $two->{'AllowedOperatingSystemMACAddresses'}{'content'};
            my $DeviceName = $two->{'DeviceName'}{'content'} if defined $two->{'DeviceName'}{'content'};
            my $DynamicReconfigurationConnectorName = $two->{'DynamicReconfigurationConnectorName'}{'content'} if defined $two->{'DynamicReconfigurationConnectorName'}{'content'};
            my $LocationCode = $two->{'LocationCode'}{'content'} if defined $two->{'LocationCode'}{'content'};
            my $MACAddress = $two->{'MACAddress'}{'content'} if defined $two->{'MACAddress'}{'content'};
            my $PortVLANID = $two->{'PortVLANID'}{'content'} if defined $two->{'PortVLANID'}{'content'};
            my $TrunkPriority = $two->{'TrunkPriority'}{'content'} if defined $two->{'TrunkPriority'}{'content'};
            my $VirtualSlotNumber = $two->{'VirtualSlotNumber'}{'content'} if defined $two->{'VirtualSlotNumber'}{'content'};
            my $VirtualSwitchID = $two->{'VirtualSwitchID'}{'content'} if defined $two->{'VirtualSwitchID'}{'content'};
            $network_conf->{$servername}{'Trunk'}{$DeviceName}{DynamicReconfigurationConnectorName} = $DynamicReconfigurationConnectorName;
            $network_conf->{$servername}{'Trunk'}{$DeviceName}{LocationCode} = $LocationCode;
            $network_conf->{$servername}{'Trunk'}{$DeviceName}{MACAddress} = $MACAddress;
            $network_conf->{$servername}{'Trunk'}{$DeviceName}{PortVLANID} = $PortVLANID;
            $network_conf->{$servername}{'Trunk'}{$DeviceName}{TrunkPriority} = $TrunkPriority;
            $network_conf->{$servername}{'Trunk'}{$DeviceName}{VirtualSlotNumber} = $VirtualSlotNumber;
            $network_conf->{$servername}{'Trunk'}{$DeviceName}{VirtualSwitchID} = $VirtualSwitchID;
            $network_conf->{$servername}{'Trunk'}{$DeviceName}{DynamicReconfigurationConnectorName} = $DynamicReconfigurationConnectorName;
            $network_conf->{$servername}{'Trunk'}{$DeviceName}{DynamicReconfigurationConnectorName} = $DynamicReconfigurationConnectorName;
            print "trunk $DeviceName loc_code:$LocationCode mac:$MACAddress vlanId:$PortVLANID Vslot:$VirtualSlotNumber switchId:$VirtualSwitchID\n";
          }
        }
      }
      my $SharedEthernetAdapters = force_me_array_ref($SharedEthernet);
  print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 24\n";
      foreach my $SharedEthernetAdapter (@{$SharedEthernetAdapters}){
  print "Rest API       " . strftime("%F %H:%M:%S", localtime(time)) . "        : environment Configuration DEBUG - $servername / $server_id - 25\n";
        my $SEAs = force_me_array_ref($SharedEthernetAdapter->{'SharedEthernetAdapter'});
        foreach my $SharedEthernetAdapter (@{$SEAs}){
          #my $AssignedVirtualIOServer = $SharedEthernetAdapter->{'AssignedVirtualIOServer'}{'href'};
          my $ConfigurationState = $SharedEthernetAdapter->{'ConfigurationState'}{'content'};
          my $DeviceName = $SharedEthernetAdapter->{'DeviceName'}{'content'};
          my $HighAvailabilityMode = $SharedEthernetAdapter->{'HighAvailabilityMode'}{'content'};
          my $IPInterface = $SharedEthernetAdapter->{'IPInterface'}{'InterfaceName'}{'content'};
          my $IsPrimary = $SharedEthernetAdapter->{'IsPrimary'}{'content'};
          my $JumboFramesEnabled = $SharedEthernetAdapter->{'JumboFramesEnabled'}{'content'};
          my $LargeSend = $SharedEthernetAdapter->{'LargeSend'}{'content'};
          my $PortVLANID = $SharedEthernetAdapter->{'PortVLANID'}{'content'};
          my $QualityOfServiceMode = $SharedEthernetAdapter->{'QualityOfServiceMode'}{'content'};
          my $QueueSize = $SharedEthernetAdapter->{'QueueSize'}{'content'};
          my $ThreadModeEnabled = $SharedEthernetAdapter->{'ThreadModeEnabled'}{'content'};
          #$network_conf->{$servername}{'SEA'}{$DeviceName}{AssignedVirtualIOServer} = $AssignedVirtualIOServer;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{ConfigurationState} = $ConfigurationState;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{HighAvailabilityMode} = $HighAvailabilityMode;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{IPInterface} = $IPInterface;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{IsPrimary} = $IsPrimary;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{JumboFramesEnabled} = $JumboFramesEnabled;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{LargeSend} = $LargeSend;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{PortVLANID} = $PortVLANID;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{QualityOfServiceMode} = $QualityOfServiceMode;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{QueueSize} = $QueueSize;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{ThreadModeEnabled} = $ThreadModeEnabled;
          $network_conf->{$servername}{'SEA'}{$DeviceName}{UniqueDeviceID} = $UniqueDeviceID;
        }
      }
    }
=cut

  }
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : environment Configuration - Done\n";

  #print Dumper $adapter_box_loc;
  print "environment configuration sub end\n";
  return ( $adapter_box_loc, $network_conf );
}

sub create_html_env_config {
  my $env = shift;
  my $net = shift;
  my $html_out;
  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : interfaces creating start\n";
  open( my $fh, ">", "$webdir/interfaces_$host\_tmp.html" ) || error( "Cannot open file $webdir/interfaces_$host\_tmp.html at " . __FILE__ . ":" . __LINE__ ) && return 1;
  print $fh '<TABLE class="tabconfig tablesorter" data-sortby="1 2">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">Device Name</TH>
     <TH align="center" class="sortable" valign="center">Partition</TH>
     <TH align="center" class="sortable" valign="center">Ports</TH>
     <TH align="center" class="sortable" valign="center">WWPN</TH>
     <TH align="center" class="sortable" valign="center">Description</TH>
   </TR>
  </thead>
  <tbody>';
  foreach my $server ( keys %{$env} ) {
    print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : interfaces creating for $server\n";
    foreach my $serial ( keys %{ $env->{$server} } ) {
      foreach my $box_code ( keys %{ $env->{$server}{$serial} } ) {
        my $B  = $env->{$server}{$serial}{$box_code};
        my $DN = "";
        $DN = $B->{DeviceName} if defined $B->{DeviceName};
        my $DC = "";
        $DC = $B->{Description} if defined $B->{Description};
        my $PN = "";
        $PN = $B->{PartitionName} if defined $B->{PartitionName};
        my $b_devicename    = "";
        my $b_partitionname = "";
        my $b_description   = "";
        $b_devicename    = $DN;
        $b_partitionname = $PN;
        $b_description   = $DC;

        if ( defined $B->{Trunk} ) {
          ( undef, undef, my $k ) = split( '\.', $DN );
          my $trunks     = "";
          my $wwpns      = "";
          my $partitions = "";
          my @TR;
          if ( defined $B->{Trunk} && ref( $B->{Trunk} ) eq "HASH" ) {
            @TR = ( sort keys %{ $B->{Trunk} } );
          }
          foreach my $trunk_loc (@TR) {
            $trunks .= $trunk_loc;
            if ( defined $B->{Trunk}{$trunk_loc}{en_name} ) {
              $trunks .= " / $B->{Trunk}{$trunk_loc}{en_name}";
            }
            if ( defined $B->{Trunk}{$trunk_loc}{name} ) {
              $trunks .= " / $B->{Trunk}{$trunk_loc}{name}";
            }
            $trunks .= "<br>";
            $wwpns  .= "$B->{Trunk}{$trunk_loc}{wwpn}<br>" if defined $B->{Trunk}{$trunk_loc}{wwpn};
            if ( !defined $partitions || $partitions eq "" ) {
              $partitions = "$B->{Trunk}{$trunk_loc}{partition}" if defined $B->{Trunk}{$trunk_loc}{partition};
            }
            elsif ( defined $B->{Trunk}{$trunk_loc}{partition} && $partitions =~ m/$B->{Trunk}{$trunk_loc}{partition}/ ) {
              next;
            }
            else {
              $partitions .= "$B->{Trunk}{$trunk_loc}{partition}" if defined $B->{Trunk}{$trunk_loc}{partition};
            }
          }
          print $fh "<TR> <TD>$server</TD> <TD>$DN</TD> <TD>$partitions</TD> <TD>$trunks</TD> <TD>$wwpns</TD>  <TD>$DC</TD> </TR>\n";
        }
        else {
          print $fh "<TR>   <TD>$server</TD> <TD>$DN</TD> <TD>$PN</TD>         <TD></TD>        <TD></TD>        <TD>$DC</TD> </TR>\n";
        }
      }
    }
  }
  print $fh "
     </tbody>
    </TABLE>";

=begin comment shared and trunk
  print $fh '<TABLE class="tabconfig tablesorter">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">Shared Adapter</TH>
     <TH class="sortable" valign="center">Bridge ID</TH>
     <TH class="sortable" valign="center">PortVLANID</TH>
     <TH align="center" class="sortable" valign="center">ConfigurationState</TH>
     <TH align="center" class="sortable" valign="center">HighAvailabilityMode</TH>
     <TH align="center" class="sortable" valign="center">IsPrimary</TH>
     <TH align="center" class="sortable" valign="center">JumboFramesEnabled</TH>
     <TH align="center" class="sortable" valign="center">LargeSend</TH>
     <TH align="center" class="sortable" valign="center">QualityOfServiceMode</TH>
     <TH align="center" class="sortable" valign="center">QueueSize</TH>
     <TH align="center" class="sortable" valign="center">ThreadModeEnabled</TH>
   </TR>
  </thead>
  <tbody>';

  foreach my $netBridgeId (keys %{$net}){
    foreach my $ent (keys %{$net->{$netBridgeId}{SEA}}){
      print $fh "
      <TR>
        <TD align=\"center\">$ent / $net->{$netBridgeId}{SEA}{$ent}{'IPInterface'}</TD>
        <TD align=\"center\">$netBridgeId</TD>
        <TD align=\"center\">$net->{$netBridgeId}{'PortVLANID'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{SEA}{$ent}{'ConfigurationState'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{SEA}{$ent}{'HighAvailabilityMode'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{SEA}{$ent}{'IsPrimary'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{SEA}{$ent}{'JumboFramesEnabled'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{SEA}{$ent}{'LargeSend'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{SEA}{$ent}{'QualityOfServiceMode'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{SEA}{$ent}{'QueueSize'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{SEA}{$ent}{'ThreadModeEnabled'}</TD>
      </TR>\n";
    }
  }

  print $fh "
     </tbody>
    </TABLE>
   </CENTER>";


  print $fh '<TABLE class="tabconfig tablesorter">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">Trunk Adapter</TH>
     <TH align="center" class="sortable" valign="center">DynamicReconfigurationConnectorName</TH>
     <TH align="center" class="sortable" valign="center">LocationCode</TH>
     <TH align="center" class="sortable" valign="center">MACAddress</TH>
     <TH align="center" class="sortable" valign="center">PortVLANID</TH>
     <TH align="center" class="sortable" valign="center">TrunkPriority</TH>
     <TH align="center" class="sortable" valign="center">VirtualSlotNumber</TH>
     <TH align="center" class="sortable" valign="center">VirtualSwitchID</TH>
   </TR>
  </thead>
  <tbody>';

  foreach my $netBridgeId (keys %{$net}){
    foreach my $trunk (keys %{$net->{$netBridgeId}{Trunk}}){
      print Dumper $net->{$netBridgeId}{Trunk}{$trunk};
      print $fh "
      <TR>
        <TD align=\"center\">$trunk</TD>
        <TD align=\"center\">$net->{$netBridgeId}{Trunk}{$trunk}{'DynamicReconfigurationConnectorName'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{Trunk}{$trunk}{'LocationCode'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{Trunk}{$trunk}{'MACAddress'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{Trunk}{$trunk}{'PortVLANID'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{Trunk}{$trunk}{'TrunkPriority'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{Trunk}{$trunk}{'VirtualSlotNumber'}</TD>
        <TD align=\"center\">$net->{$netBridgeId}{Trunk}{$trunk}{'VirtualSwitchID'}</TD>
      </TR>\n";
    }
  }

  print $fh "
     </tbody>
    </TABLE>
   </CENTER>";
=cut

  print "Rest API       " . strftime( "%F %H:%M:%S", localtime(time) ) . "        : interfaces creating end\n";
  close($fh);
  my $res = copy_or_error( "$webdir/interfaces_$host\_tmp.html", "$webdir/interfaces_$host.html" );
  if ( !$res ) {    #if copy was succesful
    unlink("$webdir/interfaces_$host\_tmp.html");
  }
  return 0;
}

sub copy_or_error {
  my $a = shift;
  my $b = shift;
  copy( "$a", "$b" ) || error( "Cannot: cp $a to $b: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  return 0;
}

sub interface_conf_server {
  my $env           = shift;
  my $main_table_fh = shift;
  my $server        = shift;
### foreach server do the same to separate file ###

  print $main_table_fh "<div class=\"server_interface\">";
  print $main_table_fh '<TABLE class="tabconfig tablesorter">
  <thead>
   <TR>
     <TH align="center" class="sortable" valign="center">Server</TH>
     <TH align="center" class="sortable" valign="center">Device Name</TH>
     <TH align="center" class="sortable" valign="center">Ports</TH>
     <TH align="center" class="sortable" valign="center">Partition</TH>
     <TH align="center" class="sortable" valign="center">Description</TH>
   </TR>
  </thead>
  <tbody>';
  foreach my $serial ( keys %{ $env->{$server} } ) {
    foreach my $box_code ( keys %{ $env->{$server}{$serial} } ) {
      my $B = $env->{$server}{$serial}{$box_code};

      #print "B adapter\n";
      #print Dumper $B;
      my $DN = "";
      $DN = $B->{DeviceName} if defined $B->{DeviceName};
      my $DC = "";
      $DC = $B->{Description} if defined $B->{Description};
      my $PN = "";
      $PN = $B->{PartitionName} if defined $B->{PartitionName};
      if ( defined $B->{Trunk} ) {
        ( undef, undef, my $k ) = split( '\.', $DN );
        my $trunks = "";
        my @TR;
        if ( defined $B->{Trunk} && ref( $B->{Trunk} ) eq "HASH" ) {
          @TR = ( sort keys %{ $B->{Trunk} } );
        }
        foreach my $trunk_loc (@TR) {
          $trunks .= $trunk_loc;
          if ( defined $B->{Trunk}{$trunk_loc}{en_name} ) {
            $trunks .= " / $B->{Trunk}{$trunk_loc}{en_name}";

            #$trunks .= " ($B->{Trunk}{$trunk_loc}{name})" if defined $B->{Trunk}{$trunk_loc}{name};
            #$trunks .= "<br>";
          }
          if ( defined $B->{Trunk}{$trunk_loc}{name} ) {
            $trunks .= " / $B->{Trunk}{$trunk_loc}{name}";

            #$trunks .= "<br>";
          }

          #$trunks .= "$trunk_loc / $B->{Trunk}{$trunk_loc}{en_name} / $B->{Trunk}{$trunk_loc}{name}<br>";
          $trunks .= "<br>";
        }
        print $main_table_fh "
        <TR>
          <TD>$server</TD>
          <TD>$DN</TD>
          <TD>$trunks</TD>
          <TD>$PN</TD>
          <TD>$DC</TD>
        </TR>\n";
      }
      else {
        print $main_table_fh "
      <TR>
         <TD>$server</TD>
         <TD>$DN</TD>
         <TD></TD>
         <TD>$PN</TD>
         <TD>$DC</TD>
        </TR>\n";
      }
    }
  }
  print $main_table_fh "
    </tbody>
    </TABLE>";
  print $main_table_fh "</div>";

}

sub giveMeRestrictedLpars {
  if ( !$restricted_role_applied ) {
    return {};
  }
  my $CONFIG = shift;
  my $out;
  if ( ref($CONFIG) ne "HASH" ) {
    $out->{error_in_loading_lpars} = "undefined_lpars";
    return $out;
  }
  foreach my $lpar ( keys %{ $CONFIG->{lpar} } ) {
    $out->{$lpar}{available} = "true";
  }
  return $out;
}

sub force_me_array_ref {
  my $in  = shift;
  my $out = [];
  if ( ref($in) eq "HASH" ) {
    push( @{$out}, $in );
  }
  elsif ( ref($in) eq "ARRAY" ) {
    @{$out} = @{$in};
  }
  return $out;
}

sub getServerNPIV {
  my $uid        = shift;
  my $servername = shift;
  my $vioses     = shift;
  my $npiv;
  #print "DEBUG NPIV vioses all\n";
  #print Dumper $vioses;
  if ( ref($vioses) ne "ARRAY" ) {
    return {};
  }
  foreach my $vio ( @{$vioses} ) {
    #print "NPIV DEBUG VIOS\n";
    #print Dumper $vio;

    #print Dumper keys %{$vio};
    if ( ref($vio) ne "HASH" ) {
      next;
    }
    my $VirtualFibreMappings;
    $VirtualFibreMappings = force_me_array_ref( $vio->{'VirtualFibreChannelMappings'}{'VirtualFibreChannelMapping'} );
    foreach my $item ( @{$VirtualFibreMappings} ) {
      my $mapping = force_me_array_ref($item);
      foreach my $map ( @{$mapping} ) {
        #print "NPIV DEBUG mapping\n";
        #print Dumper $map;
        my $act_map;

        my @port_metrics = ( "LocationCode", "PortName", "UniqueDeviceID", "WWPN", "AvailablePorts", "TotalPorts" );
        foreach my $m (@port_metrics) { $act_map->{Port}{$m} = $map->{Port}{$m}{'content'} if defined $map->{Port}{$m}{'content'}; }

        my @client_metrics = ( "AdapterType", "DynamicReconfigurationConnectorName", "LocationCode", "LocalPartitionID", "RequiredAdapter", "VariedOn", "VirtualSlotNumber", "ConnectingPartitionID", "ConnectingVirtualSlotNumber", "WWPNs" );
        foreach my $m (@client_metrics) {
          $act_map->{ClientAdapter}{$m} = $map->{ClientAdapter}{$m}{'content'} if defined $map->{ClientAdapter}{$m}{'content'};
        }
        my $LocalPartitionID = $map->{ClientAdapter}{LocalPartitionID}{content};
        $act_map->{ClientAdapter}{LocalPartition} = PowerDataWrapper::lpar_id_to_name( $CNF, $servername, $LocalPartitionID ) if ( defined $LocalPartitionID );
        my $ConnectingPartitionID = $map->{ClientAdapter}{ConnectingPartitionID}{content};

        $act_map->{ClientAdapter}{ConnectingPartition} = PowerDataWrapper::lpar_id_to_name( $CNF, $servername, $ConnectingPartitionID ) if ( defined $ConnectingPartitionID );

        my @server_metrics = ( "AdapterType", "DynamicReconfigurationConnectorName", "LocationCode", "LocalPartitionID", "RequiredAdapter", "VariedOn", "VirtualSlotNumber", "ConnectingPartitionID", "ConnectingVirtualSlotNumber", "UniqueDeviceID", "MapPort" );
        foreach my $m (@server_metrics) { $act_map->{ServerAdapter}{$m} = $map->{ServerAdapter}{$m}{'content'} if defined $map->{ServerAdapter}{$m}{'content'}; }
        my $ServerLogicalPartitionID = $map->{ServerAdapter}{LocalPartitionID}{content};
        $act_map->{ServerAdapter}{LocalPartition} = PowerDataWrapper::lpar_id_to_name( $CNF, $servername, $ServerLogicalPartitionID ) if ( defined $ServerLogicalPartitionID );

        my $ServerConnectingPartitionID = $map->{ServerAdapter}{ConnectingPartitionID}{content};
        $act_map->{ServerAdapter}{ConnectingPartition} = PowerDataWrapper::lpar_id_to_name( $CNF, $servername, $ServerConnectingPartitionID ) if ( defined $ServerConnectingPartitionID );
        $act_map->{SystemName} = $servername;

        push( @{$npiv}, $act_map );
      }
    }
    print "End sub NPIV\n";
  }
  return $npiv;
}

sub initPowerMetadata {
  my $metadata;

  $metadata->{architecture}{hmc}    = {};
  $metadata->{architecture}{server} = {};
  $metadata->{architecture}{pool}   = {};
  $metadata->{architecture}{vm}     = {};

  $metadata->{labels}{hmc}    = {};
  $metadata->{labels}{server} = {};
  $metadata->{labels}{pool}   = {};
  $metadata->{labels}{vm}     = {};

  return $metadata;
}

sub get_processed_metrics {
  my $uid_server = shift;
  my $url        = "$proto://$host/rest/api/pcm/ManagedSystem/$uid_server/ProcessedMetrics";
  my $out        = callAPI($url);
  return $out;
}

sub is_digit {
  my $digit = shift;

  if ( !defined($digit) ) {
    return 0;
  }
  if ( $digit eq '' ) {
    return 0;
  }
  if ( $digit eq 'U' ) {
    return 0;    # 6.02-1, changed t false, why ot was true before?
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

  #if (($digit * 1) eq $digit){
  #  # is a number
  #  return 1;
  #}

  # NOT a number
  return 0;
}

sub exclude_hmc_port {
  my $in = shift;
  if ( !defined $ENV{HMC_REST_API_PORT_AVOID} ) { return 0; }
  my $hmcs     = $ENV{HMC_REST_API_PORT_AVOID};
  my @hmc_list = split( " ", $hmcs );
  foreach my $h (@hmc_list) {
    if ( $h eq $in ) {
      return 1;
    }
  }

  return 0;
}

sub downloadPerffilesFromHMC {
  my $hmc_ip = $host;
  my $frames = downloadHMCFrames();
  my @file_list;
  my @pid_arr;
  while ( my $a = shift( @{$frames} ) ) {
    my $SystemName                  = $a->{'SystemName'}{'content'};
    my $AssociatedManagedSystemLink = $a->{'AssociatedManagedSystem'}{'href'};
    my $FrameUUID                   = $a->{'Metadata'}{'Atom'}{'AtomID'};
    my $ltm_url                     = "rest/api/pcm/ManagedSystem/$FrameUUID/RawMetrics/LongTermMonitor";
    my $ltm                         = callAPI($ltm_url);

    #process ltm json links
    my $links_hash = $ltm->{'entry'};
    my @uuids      = keys %{$links_hash};
    while ( my $sample_uuid = shift(@uuids) ) {
      my $ltm_json_url = $links_hash->{$sample_uuid}{'link'}{'href'};
      my $ltm_json     = callAPIjson($ltm_json_url);
      print "uid lnk : $sample_uuid\n";
      my $filename = "$work_folder/data/$SystemName/$hmc_ip/iostat/$sample_uuid.json";
      push( @file_list, $filename );
      Xorux_lib::write_json( $filename, $ltm_json );
    }

  }
  return \@file_list;
}

sub loadDataToRRDFiles {
  my $files = shift;
  while ( my $file = shift( @{$files} ) ) {
    my $file_content = Xorux_lib::read_json($file) if ( -f $file );
    print "Delete file $file\n";
    unlink($file);
  }
  return 0;
}

sub downloadHMCFrames {
  my $hmc_ip      = $host;
  my $url         = "rest/api/pcm/preferences";
  my $preferences = callAPI($url);

  return $preferences->{'entry'}{'content'}{'ManagementConsolePcmPreference:ManagementConsolePcmPreference'}{'ManagedSystemPcmPreference'} if ( defined $preferences->{'entry'}{'content'}{'ManagementConsolePcmPreference:ManagementConsolePcmPreference'}{'ManagedSystemPcmPreference'} );
  return {};
}

###################################################
