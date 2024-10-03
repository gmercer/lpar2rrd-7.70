# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

use warnings;
use strict;
use Date::Parse;
use File::Compare;
use LoadDataModule;
use File::Copy;
use POSIX qw(strftime);
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;
use JSON;
use File::Temp;
use HostCfg;
use Xorux_lib;
use XoruxEdition;
use PowerDataWrapper;

#use IO::Socket::SSL;
#use lib qw (/opt/freeware/lib/perl/5.8.0);
# no longer need to use "use lib qw" as the library PATH is already in PERL5LIB env var (lpar2rrd.cfg)

# set unbuffered stdout
$| = 1;

my $fast_processing = 1;    # do not create lpar graph in advance, greate then on demand via cgi-bin

my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };

# get cmd line params
my $version       = "";
my $version_patch = "";
my $upgrade       = 0;

$version       = "$ENV{version}"       if defined $ENV{version};
$version_patch = "$ENV{version_patch}" if defined $ENV{version_patch};
$upgrade       = $ENV{UPGRADE}         if defined $ENV{UPGRADE};
my $host     = $ENV{HMC};
my $hea      = $ENV{HEA};
my $hmc_user = $ENV{HMC_USER};
my $webdir   = $ENV{WEBDIR};
my $bindir   = $ENV{BINDIR};
my $basedir  = $ENV{INPUTDIR};
my $tmpdir   = "$basedir/tmp";

if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $tmp_restapi_dir = "$tmpdir/restapi";
if ( !-d $tmp_restapi_dir ) {
  print "mkdir          : $host: $tmp_restapi_dir\n";
  mkdir( "$tmp_restapi_dir", 0755 ) || error( " Cannot mkdir $tmp_restapi_dir: $!" . __FILE__ . ":" . __LINE__ );
}
my $rrdtool                 = $ENV{RRDTOOL};
my $DEBUG                   = $ENV{DEBUG};
my $pic_col                 = $ENV{PICTURE_COLOR};
my $STEP                    = $ENV{SAMPLE_RATE};
my $HWINFO                  = $ENV{HWINFO};
my $CONFIG_HISTORY          = $basedir . "/data";              # do not change that as subdir tree is not created automatically here but via main loop
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $SYS_CHANGE              = $ENV{SYS_CHANGE};
my $STEP_HEA                = $ENV{STEP_HEA};
my $SSH                     = $ENV{SSH} . " -q ";              # doubles -q from lpar2rrd.cfg, just to be sure ...
my $json_on                 = 0;
my $save_files              = 0;
my $restapi                 = 0;
if ( defined $ENV{KEEP_OUT_FILES} ) { $save_files = $ENV{KEEP_OUT_FILES}; }

my $YEAR_REFRESH  = 86400;                                     # 24 hour, minimum time in sec when yearly graphs are updated (refreshed)
my $MONTH_REFRESH = 39600;                                     # 11 hour, minimum time in sec when monthly graphs are updated (refreshed)
my $WEEK_REFRESH  = 18000;                                     # 5 hour, minimum time in sec when weekly  graphs are updated (refreshed)

my $excluded_servers_conf;
foreach my $hmc_alias ( keys %hosts ) {
  if ( $hosts{$hmc_alias}{host} eq $host || $hosts{$hmc_alias}{hmc2} eq $host ) {
    if ( defined $hosts{$hmc_alias}{ssh_key_id} && $hosts{$hmc_alias}{ssh_key_id} ne "" ) {
      $SSH = $hosts{$hmc_alias}{ssh_key_id};
    }
    if ( defined $hosts{$hmc_alias}{auth_api} && $hosts{$hmc_alias}{auth_api} ) {
      $restapi = $json_on = 1;
    }
    else {
      $restapi = $json_on = 0;

      #my $configuration = PowerDataWrapper::get_conf();
      #$configuration = PowerDataWrapper::update_conf($configuration);
    }
    if ( defined $hosts{$hmc_alias}{username} && $hosts{$hmc_alias}{username} ne "" ) {
      $hmc_user = $hosts{$hmc_alias}{username};
    }
    $excluded_servers_conf = $hosts{$hmc_alias}{exclude};
  }
}
if ( !defined $SSH || $SSH eq "" || $SSH !~ m/ssh/ ) { $SSH = "ssh -q"; }

#2021-06-17T07:52:00.000Z
my $TZ_HMC  = 0;    #  = `$SSH $hmc_user\@$host "date '+%z'"`;
my $TS_HMC  = 0;    #  = `$SSH $hmc_user\@$host "date '+%Y-%m-%dT%H:%M:%S%z'"`;
my $TS_HMCB = 0;    # = `$SSH $hmc_user\@$host "date '+%m/%d/%Y %H:%M:%S'"`;
if ( !$restapi ) {
  $TZ_HMC  = `$SSH $hmc_user\@$host "date '+%z'"`;
  $TS_HMC  = `$SSH $hmc_user\@$host "date '+%Y-%m-%dT%H:%M:%S%z'"`;
  $TS_HMCB = `$SSH $hmc_user\@$host "date '+%m/%d/%Y %H:%M:%S'"`;
}
my $TZ_LOCAL = `date '+%z'`;

chomp( $TZ_HMC, $TZ_LOCAL );
chomp($TS_HMC);
chomp($TS_HMCB);

my @servers_to_exclude;
my $exc_ser = $excluded_servers_conf;
foreach my $server_hash ( @{$exc_ser} ) {
  if ( $server_hash->{exclude_data_load} ) {
    push( @servers_to_exclude, $server_hash->{name} );
  }
}

# do not use: PasswordAuthentication=no due to reflection ssh which does not support that!!!
# uncoment&adjust if you want to use your own ssh identification file
#my $SSH = $ENV{SSH}." -i ".$ENV{HOME}."/.ssh/lpar2rrd -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey";
my $lpm = $ENV{LPM};
my $h   = "";
$h = $ENV{HOSTNAME} if defined $ENV{HOSTNAME};
my $cpu_max_filter = 100;    # my $cpu_max_filter = 100;  # max 10k peak in % is allowed (in fact it cannot by higher than 1k now when 1 logical CPU == 0.1 entitlement)
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}
my $load_daily = 0;          # do not load daily data from the HMC as default since 4.60
if ( defined $ENV{LOAD_DAILY} ) {
  $load_daily = $ENV{LOAD_DAILY};
}

my $delimiter = "XORUX";     # this is for rrdtool print lines for clickable legend

#print "++ $host $hmc_user $basedir $webdir $STEP\n";
my $wrkdir = "$basedir/data";

# Global definitions
my $input                   = "";
my $input_mem               = "";
my $input_pool              = "";
my $input_pool_mem          = "";
my $input_pool_sh           = "";
my $input_cod               = "";
my $input_sriov             = "";
my $input_lan               = "";
my $input_j_lpars           = "";
my $input_fcs               = "";
my $input_gpa               = "";
my $input_hea               = "";
my $input_shell             = "";
my $input_mem_shell         = "";
my $input_pool_shell        = "";
my $input_pool_mem_shell    = "";
my $input_pool_sh_shell     = "";
my $input_cod_shell         = "";
my $pool_list_file          = "pool_list.txt";
my $loadhours               = "";
my $loadmins                = "";
my $type_sam                = "";
my $managedname             = "";
my $step                    = "";
my $NO_TIME_MULTIPLY        = 6;                            # increased since 3.63
my $no_time                 = $STEP * $NO_TIME_MULTIPLY;    # says the time interval when RRDTOOL consideres a gap in input data 6 mins now!
                                                            # looks like 60sec sample rate is stored on HMC just for last 2 days (there in no doc so far)
                                                            # INIT_LOAD_IN_HOURS_BACK should be generally high enough  (one year back =~ 9000 hours), it is in hours!!!
                                                            #my $INIT_LOAD_IN_HOURS_BACK="9000";
my $INIT_LOAD_IN_HOURS_BACK = "48";                         # not need more as 1 minute samples are no longer there, daily are not more used since 4.60
my $UPDATE_DAILY            = 86400;                        # for update config (documentation) files
my $CFG_REFRESH             = 7000;                         # update of lpar cfg
my $PARALLELIZATION         = 5;

#$UPDATE_DAILY=60;
my @pool_list = "";

# Random colors for disk charts
my @managednamelist_un = "";
my @managednamelist    = "";
my $HMC                = 1;                                 # if HMC then 1, if IVM/SDMC then 0
my $SDMC               = 0;
my $IVM                = 0;
my $FSM                = 0;                                 # so far only for setting lslparutil AMS parames
my @lpar_trans         = "";                                # lpar translation names/ids for IVM systems
my $MAX_ROWS           = 2450;                              # new HMC like 8.8.x has fix limitation 2500 rows set in hmc.properties
my $restrict_rows      = " -n $MAX_ROWS";                   # workaround for HMC < 7.2.3 to do not exhaust memory
my $timerange          = " --minutes 120 ";                 # it must be global var, placing there some default just to be sure ...

# last timestamp files --> must be for each load separated
my $last_file          = "last.txt";
my $last_file_pool     = "last-pool.txt";
my $last_file_mem      = "last-mem.txt";
my $last_file_sh_mem   = "last-sh-mem.txt";
my $last_file_sh_pool  = "last-sh-pool.txt";
my $last_file_cod      = "last-cod.txt";
my $last_file_lan      = "last-lan.txt";
my $last_file_fcs      = "last-fcs.txt";
my $last_file_gpa      = "last-gpa.txt";
my $last_file_hea      = "last-hea.txt";
my $last_file_sriov    = "last-sriov.txt";
my $last_file_j_lpars  = "last-j-lpars.txt";
my $last_rec           = "";
my $sec                = "";
my $ivmmin             = "";
my $ivmh               = "";
my $ivmd               = "";
my $ivmm               = "";
my $ivmy               = "";
my $wday               = "";
my $yday               = "";
my $isdst              = "";
my $timeout_save       = 7200;                 # timeout for downloading whole server/lpar cfg from the HMC (per 1 server), it prevents hanging
                                               # latest HMC 8.8.3 could have a problem with 30mins therefore extened it to 2 hours since 4.81
my $server_count       = 0;
my @pid                = "";
my $cycle_count        = 1;
my @poollistagg        = "";
my @poolall            = "";
my $DELETED_LPARS_TIME = 8640000;              # 10 days
my @lpm_excl_vio       = "";
my $view_suff          = "view";
my $mem_params         = "";
my $idle_param         = "";

# disable Tobi's promo
#my $disable_rrdtool_tag = "COMMENT: ";
#my $disable_rrdtool_tag_agg = "COMMENT:\" \"";
my $disable_rrdtool_tag     = "--interlaced";    # just nope string, it is deprecated anyway
my $disable_rrdtool_tag_agg = "--interlaced";    # just nope string, it is deprecated anyway
my $rrd_ver                 = $RRDp::VERSION;
if ( isdigit($rrd_ver) && $rrd_ver > 1.35 ) {
  $disable_rrdtool_tag     = "--disable-rrdtool-tag";
  $disable_rrdtool_tag_agg = "--disable-rrdtool-tag";
}

# keep here green - yellow - red - blue ...
my @color     = ( "#FF0000", "#0000FF", "#8fcc66", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#FF00FF", "#800080", "#FDD017", "#0000A0", "#3BB9FF", "#008000", "#800000", "#C0C0C0", "#ADD8E6", "#F778A1", "#800517", "#736F6E", "#F52887", "#C11B17", "#5CB3FF", "#A52A2A", "#FF8040", "#2B60DE", "#736AFF", "#1589FF", "#98AFC7", "#8D38C9", "#307D7E", "#F6358A", "#151B54", "#6D7B8D", "#33cc33", "#FF0080", "#F88017", "#2554C7", "#00a900", "#D4A017", "#306EFF", "#151B8D", "#9E7BFF", "#EAC117", "#99cc00", "#15317E", "#6C2DC7", "#FBB917", "#86b300", "#15317E", "#254117", "#FAAFBE", "#357EC7", "#4AA02C", "#38ACEC" );
my $color_max = 53;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     # 0 - 53 is 54 colors

my @keep_color_lpar = "";

rrdtool_graphv();

### graph or graphv
my $graph_cmd = "graph";
if ( -f "$tmpdir/graphv" ) {
  $graph_cmd = "graphv";    # if exists - call this function
}

# run touch tmp/$version-run once a day (first run after the midnight) to force recreation of the GUI
my $version_file = "$basedir/tmp/$version";
if ( -e $version_file ) {
  my $run_time = ( stat($version_file) )[9];
  ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
  ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
  if ( $aday != $png_day ) {
    once_a_day($version_file);
  }
}
else {
  once_a_day($version_file);
}

my $ret = graph_without_load_data();
if ( $ret == 1 ) {
  exit 0;
}

my $prem = premium();
print "LPAR2RRD $prem version $version ($version_patch)\n" if $DEBUG;
print "Host           : $h\n"                              if $DEBUG;
print "HMC            : $host\n"                           if $DEBUG;
print "PID            : $$\n"                              if $DEBUG;
my $date     = "";
my $act_time = localtime();
print "date start     : $host $act_time\n" if $DEBUG;

if ( !-d "$webdir" ) {
  error( " Pls set correct path to Web server pages, it does not exist here: $webdir" . __FILE__ . ":" . __LINE__ ) && return 0;
}

cfg_config_change();

# start RRD via a pipe
use RRDp;
RRDp::start "$rrdtool";

my $rrdtool_version = 'Unknown';
$_ = `$rrdtool`;
if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
  $rrdtool_version = $1;
}
print "RRDp    version: $RRDp::VERSION \n";
print "RRDtool version: $rrdtool_version\n";

#my $perlv= $^V;
#my $perlv2= $];
print "Perl version   : $] \n";

#generate demo files from anonymized data
if ( $ENV{DEMO} ) {
  print "TEST 1\n";

  #add or remove there servers shown at demo
  push @managednamelist, 'Power770,9117-MMC,44K8102';
  push @managednamelist, 'Power-E880,9117-MMC,44K8102';

  #hmc for servers, ajdust if needed
  $host = "hmc1";
  my $time = time();

  frame_multi( "day",   "m", "d", "MINUTE:60:HOUR:2:HOUR:4:0:%H" );
  frame_multi( "week",  "m", "w", "HOUR:8:DAY:1:DAY:1:86400:%a" );
  frame_multi( "month", "m", "m", "DAY:1:DAY:2:DAY:2:0:%d" );
  frame_multi( "year",  "m", "y", "MONTH:1:MONTH:1:MONTH:1:0:%b" );
  multiview_hmc( $host, "lpar-multi", "d", "m", $time, "day",   "MINUTE:60:HOUR:2:HOUR:4:0:%H" );
  multiview_hmc( $host, "lpar-multi", "w", "m", $time, "week",  "HOUR:8:DAY:1:DAY:1:86400:%a" );
  multiview_hmc( $host, "lpar-multi", "m", "m", $time, "month", "DAY:1:DAY:2:DAY:2:0:%d" );
  multiview_hmc( $host, "lpar-multi", "y", "m", $time, "year",  "MONTH:1:MONTH:1:MONTH:1:0:%b" );
  frame_multi_total( "day",   "m", "d", "MINUTE:60:HOUR:2:HOUR:4:0:%H" );
  frame_multi_total( "week",  "m", "w", "HOUR:8:DAY:1:DAY:1:86400:%a" );
  frame_multi_total( "month", "m", "m", "DAY:1:DAY:2:DAY:2:0:%d" );
  frame_multi_total( "year",  "m", "y", "MONTH:1:MONTH:1:MONTH:1:0:%b" );
  exit;
}

#  do not save data on instance that provides data to another instance. show data only on the remote server
if ( defined $ENV{PROXY_SEND} && $ENV{PROXY_SEND} == 1 ) {
  exit;
}

#  save data on instance that provides data to another instance and show them in GUI on both servers
if ( defined $ENV{PROXY_SEND} && $ENV{PROXY_SEND} == 2 ) {

}

#  load data on remote instance site
if ( defined $ENV{PROXY_RECEIVE} && $ENV{PROXY_RECEIVE} ) {
  print "Loading HMC data provided by remote proxy instance - all other than HMC REST API sources will be ignored\n";
}

my ( $SERV, $CONF ) = PowerDataWrapper::init();

load_hmc();

# close RRD pipe
RRDp::end;

$date = localtime();
print "date end       : $host $date\n" if $DEBUG;

exit(0);

sub load_hmc {

  my $timeout = 120;
  my $model   = "";
  my $serial  = "";
  my $line    = "";
  my $hmcv    = "";

  if ( defined $ENV{HMC_TIMEOUT} && isdigit( $ENV{HMC_TIMEOUT} ) ) {
    $timeout = $ENV{HMC_TIMEOUT};
  }

  # set alarm on first SSH command to make sure it does not hang
  eval {
    local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
    alarm($timeout);

    # get list of serveres managed through HMC
    if ( !$restapi ) {
      @managednamelist_un = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lssyscfg -r sys -F name,type_model,serial_num" 2>\&1`;

      if ( !defined $managednamelist_un[0] || $managednamelist_un[0] eq '' ) {
        error("HMC/SDMC/IVM name: $host either has not been resolved or ssh key based access is not allowed or other communication error");
        exit(1);
      }

      if ( $managednamelist_un[0] =~ "no address associated with hostname" || $managednamelist_un[0] =~ "Could not resolve hostname" ) {
        error("HMC/SDMC/IVM : $managednamelist_un[0]");
        exit(1);
      }

      # sorting non case sensitive
      @managednamelist = sort { lc($a) cmp lc($b) } @managednamelist_un;
    }
    alarm(0);
  };

  if ($@) {
    if ( !$restapi ) {
      if ( $@ =~ /died in SIG ALRM/ ) {
        error("$SSH $hmc_user\@$host command timed out after : $timeout seconds\nCheck why it takes so long, might be some network or authentification problems on the HMC\n# ssh $hmc_user\@$host \"lssyscfg -r sys -F name\"\nContinue with the other HMCs");
        exit(1);
      }
      else {
        error("lpar2rrd failed: $@");
        exit(1);
      }
    }
  }
  my $out_servers_cli;
  my $i = 0;
  if ( !$restapi ) {
    foreach my $managedserver (@managednamelist_un) {
      chomp($managedserver);
      my ( $name, $a, $serial ) = split( ",", $managedserver );
      my ( $machine_type, $model ) = split( "-", $a );
      $out_servers_cli->{$i}{SerialNumber}{content} = $serial;
      $out_servers_cli->{$i}{name}                  = $name;
      $out_servers_cli->{$i}{MachineType}{content}  = "$machine_type";
      $out_servers_cli->{$i}{Model}{content}        = "$model";
      $out_servers_cli->{$i}{UUID}                  = PowerDataWrapper::md5_string("$serial $machine_type-$model");
      $i++;
    }
    my $file_path = "$basedir/tmp/restapi/HMC_INFO_$host.json";
    Xorux_lib::write_json( $file_path, $out_servers_cli ) if ( defined $out_servers_cli && Xorux_lib::file_time_diff($file_path) > 3600 || Xorux_lib::file_time_diff($file_path) == 0 );
  }
  if ($restapi) {
    undef(@managednamelist);
    my $rest_api_managednamelist_json = {};
    if ( -e "$basedir/tmp/restapi/HMC_INFO_$host.json" ) {
      $rest_api_managednamelist_json = Xorux_lib::read_json("$basedir/tmp/restapi/HMC_INFO_$host.json");
      print Dumper $rest_api_managednamelist_json;
    }
    foreach my $i ( keys %{$rest_api_managednamelist_json} ) {
      my $server        = $rest_api_managednamelist_json->{$i};
      my $server_string = "$server->{name},$server->{MachineType}{content}-$server->{Model}{content},$server->{SerialNumber}{content}";
      if ( !( grep( /^$server_string$/, @managednamelist_un ) ) ) {
        push( @managednamelist_un, $server_string );
      }
    }
    @managednamelist = sort { lc($a) cmp lc($b) } @managednamelist_un;
  }
  my $managed_ok;
  my $managedname_exl = "";
  my @m_excl          = "";
  my $once            = 0;
  my $hmcv_num        = "";
  my $date_local      = localtime();    # never call localtime() in function argument!!

  # get data for all managed system which are conected to HMC
  foreach $line (@managednamelist) {
    chomp($line);

    if ( $line =~ m/Error:/ || $line =~ m/Permission denied/ ) {
      error("problem connecting to $host : $line");
      exit(1);
    }

    if ( $line !~ ".*,.*,.*" ) {

      # it must look like : PWR6A-9117-MMA-SN103A4B0,9117-MMA,103A4B0, --> exclude banners
      next;
    }

    if ( $line =~ /No results were found/ ) {
      print "$host does not contain any managed system\n" if $DEBUG;
      return 0;
    }
    ( $managedname, $model, $serial ) = split( /,/, $line );
    if ( length($serial) < 6 || length($serial) > 8 ) {
      next;    # wrong entry from the HMC, looks like some trash
      print "$host:$managedname : problem with server name and serial, skipping it ($line)\n" if $DEBUG;
    }

    if ( is_IP($managedname) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }
    my $exclude_this_server = is_server_excluded_from_rest( $managedname, $excluded_servers_conf );

    if ($exclude_this_server) {
      $restapi = 0;
      $json_on = 0;
    }
    else {
      if ( is_host_rest($host) ) {
        $restapi = 1;
        $json_on = 1;
      }
      else {
        $restapi = 0;
        $json_on = 0;
      }
    }
    print "managed system : $host:$managedname (type_model*serial : $model*$serial)\n" if $DEBUG;

    rename_server( $host, $managedname, $model, $serial );

    # create sym link model*serial for recognizing of renamin managed systems
    # it must be here due to skipping some server (exclude, not running utill collection) and saving cfg
    if ( !-d "$wrkdir" ) {
      print "mkdir          : $host:$managedname $wrkdir\n" if $DEBUG;
      LoadDataModule::touch("$host:$managedname $wrkdir");
      mkdir( "$wrkdir", 0755 ) || error( " Cannot mkdir $wrkdir: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    if ( !-d "$wrkdir/$managedname" ) {
      print "mkdir          : $host:$managedname $wrkdir/$managedname\n" if $DEBUG;
      LoadDataModule::touch("$wrkdir/$managedname");
      mkdir( "$wrkdir/$managedname", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    if ( !-l "$wrkdir/$model*$serial" ) {
      print "ln -s          : $host:$managedname $wrkdir/$managedname $wrkdir/$model*$serial \n" if $DEBUG;
      LoadDataModule::touch("$wrkdir/$model*$serial");
      symlink( "$wrkdir/$managedname", "$wrkdir/$model*$serial" ) || error( " Cannot ln -s $wrkdir/$managedname $wrkdir/$model*$serial: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    if ( !-d "$wrkdir/$managedname/$host" ) {
      print "mkdir          : $host:$managedname $wrkdir/$managedname/$host\n" if $DEBUG;
      LoadDataModule::touch("$wrkdir/$managedname/$host");
      mkdir( "$wrkdir/$managedname/$host", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname/$host: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }
    my $adapters    = "adapters";
    my $dir_to_make = "$wrkdir/$managedname/$host/$adapters";
    if ( !-d "$dir_to_make" ) {
      print "mkdir          : $host:$managedname $dir_to_make\n" if $DEBUG;
      LoadDataModule::touch("$dir_to_make");
      mkdir( "$dir_to_make", 0755 ) || error( " Cannot mkdir $dir_to_make: $!" . __FILE__ . ":" . __LINE__ ) && next;
    }

    $managed_ok = 1;
    @pool_list  = "";    # clean pool_list for each managed name
    if ( $managed_systems_exclude ne '' ) {
      @m_excl = split( /:/, $managed_systems_exclude );
      foreach $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managedname =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
          last;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      print "managed system : $host:$managedname is excluded in load.sh, continuing with the others ...\n" if $DEBUG;
      save_cfg_data( $managedname, $date_local, $upgrade, $serial, $model );    # it is necessary to have all server in cfg page
      next;
    }

    # Check whether utilization data collection is enabled
    if ($restapi) {
      $step = $STEP;
    }
    else {
      $step = `$SSH $hmc_user\@$host "lslparutil -r config -m \\"$managedname\\" -F sample_rate"`;
    }
    chomp($step);

    if ( !defined($step) || $step eq '' || isdigit($step) == 0 && !$restapi ) {
      error( "$host:$managedname step=$step , sample rate has not been received correctly, wait 10 sec and try again " . __FILE__ . ":" . __LINE__ );
      sleep(10);

      # try the 2nd attempt
      $step = `$SSH $hmc_user\@$host "lslparutil -r config -m \\"$managedname\\" -F sample_rate"`;
      chomp($step);
      error( "$host:$managedname step=$step , sample rate has not been received correctly: $SSH $hmc_user\@$host \"lslparutil -r config -m $managedname -F sample_rate\"  " . __FILE__ . ":" . __LINE__ );
      my @step_array = `$SSH $hmc_user\@$host "lslparutil -r config -m \\"$managedname\\" -F sample_rate"`;
      my $step_indx  = 0;
      foreach my $step_item (@step_array) {
        chomp($step_item);
        error( "$host:$managedname step_line[$step_indx]=$step_item ($step), sample rate has not been received correctly " . __FILE__ . ":" . __LINE__ );
        $step_indx++;
      }
      next;
    }

    # etc/.magic setup, for DHL to keep 60sec no matter how servers are set
    if ( defined $ENV{FIX_STEP} && $ENV{FIX_STEP} == 1 ) {
      print "fixed step def : $host:$managedname fix step:$STEP, server step:$step\n" if $DEBUG;
      $step = $STEP;
    }

    if ( $once == 0 && !$restapi ) {

      # Find out version of HMC (just first 3 digits and figure out if
      # it is bigger than 733 what is the version since are supported
      # enhanced sampe rates
      my @sourcev = `$SSH $hmc_user\@$host "lshmc -v" 2>/dev/null|egrep "RM |DS "|tail -2`;

      #chomp($sourcev[0]);

      my $ivmv       = 1;
      my $hmcv_print = "";
      foreach my $mmm (@sourcev) {
        $ivmv = 0;
      }
      if ( $ivmv == 1 ) {
        $hmcv = "0";
      }
      else {
        if ( !$sourcev[1] eq '' ) {
          $hmcv = "$sourcev[1]";
          chomp($hmcv);
          $hmcv =~ s/.*RM V//g;
          my $hmc_main_version = $hmcv;
          ( $hmc_main_version, my $subversion ) = split( "R", $hmc_main_version );
          $subversion =~ s/\.//g;
          $hmcv_print = "V$hmc_main_version" . "R" . "$subversion";
          write_hmc_version( $hmcv_print, $host );
          $hmcv = $hmcv_print;

        }
        else {
          $hmcv = "0";
        }
      }

      if ( !$sourcev[0] eq '' ) {
        $sourcev[0] =~ s/^\*DS //;
      }

      if ( !$sourcev[0] eq '' && ( $sourcev[0] =~ m/SDMC/ || $sourcev[0] =~ m/FSM/ ) ) {
        $HMC  = 0;    # looks like SDMC system
        $SDMC = 1;    # lshmc is on new SDMC available
        if ( $sourcev[0] =~ m/SDMC/ ) {
          print "Looks like SDMC: $host:$hmcv\n" if $DEBUG;
        }
        else {
          $FSM = 1;
          print "Looks like FSM : $host:$hmcv\n" if $DEBUG;
        }
      }

      if ( $ivmv == 1 || length($hmcv) < 3 ) {

        # old way, keeping it there ....
        $HMC      = 0;                                                                                                                             # looks like IVM system
        $hmcv_num = 700;
        $SDMC     = `$SSH $hmc_user\@$host "if test -r /usr/smrshbin ; then echo \"PLATFORM=1\" ; else echo \"PLATFORM=0\" ; fi"|grep PLATFORM`;
        chomp($SDMC);
        $SDMC =~ s/PLATFORM=//g;
        if ( $SDMC == 1 ) {
          print "Looks like SDMC: $host $hmcv_print\n" if $DEBUG;
        }
        else {
          $IVM = 1;
          print "Looks like IVM : $host $hmcv_print\n" if $DEBUG;
        }

      }
      else {
        $hmcv =~ s/ //g;
        ( my $hmc_main_version, my $hmc_subversion ) = split( "R", $hmcv_print );
        $hmc_main_version =~ s/^V//g;
        $hmc_subversion   =~ s/\.//g;

        #$hmcv_num = substr( $hmcv, 0, 3 ); #remove the previous hmcv and check the main version e.g.10 and then add two digits from the subversion 1.1 = 1011 (fix idle cycles). HD
        $hmcv_num = $hmc_main_version . substr( $hmc_subversion, 0, 2 );

        #print "DEBUG : $hmcv_num $hmcv\n";
        print "HMC version    : $host $hmcv_print\n" if $DEBUG;
      }
      $once = 1;

      if ( $hmcv_num > 772 ) {

        # for support of CPU dedicated partitions, V7 R7.3.0 (May 20, 2011)
        $idle_param = ",idle_cycles";
      }

      if ( $HMC == 1 && ( $hmcv_num > 734 || $FSM == 1 ) ) {

        # set params for lslparutil and AMS available from HMC V7R3.4.0 Service Pack 2 (05-21-2009)
        $mem_params = ",mem_mode,curr_mem,phys_run_mem,curr_io_entitled_mem,mapped_io_entitled_mem,mem_overage_cooperation";
      }
      else {
        if ( $HMC == 0 ) {
          $mem_params = ",mem_mode,curr_mem,phys_run_mem,curr_io_entitled_mem,mapped_io_entitled_mem,mem_overage_cooperation";
        }
        else {
          print "HMC version    : $host $hmcv $hmcv_num - no AMS ready : $HMC - $SDMC\n" if $DEBUG;
        }
      }
    }

    my $check = $HMC + $IVM + $SDMC;
    if ( $check != 1 ) {
      error("Wrongly identified source, exiting, contact the support: $HMC - $IVM - $SDMC");
      exit(0);
    }

    if ( $HMC == 0 && !$restapi ) {

      # IVM/SDMC translation ids to names
      @lpar_trans = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lssyscfg -r lpar -m \\"$managedname\\" -F lpar_id,name" 2>\&1| egrep "^[0-9]"`;

      # save that to lpar_trans.txt
      open FH, ">$wrkdir/$managedname/$host/lpar_trans.txt" or error( "can't open '$wrkdir/$managedname/$host/lpar_trans.txt': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      foreach (@lpar_trans) {
        print FH $_;
      }
      close FH;
    }

    if ( $step != $STEP ) {
      print "*****WARNING*****WARNING*****WARNING*****\n";
      if ( $step == 0 ) {
        print "Utilization data collection is disabled for managed system : $host:$managedname to enable it run : \n";
        print "ssh hscroot\@$host \"chlparutil -r config -m $managedname -s $STEP\"\n";
        print "*****WARNING*****WARNING*****WARNING*****\n";

        # go for next managed system / hmc server
        save_cfg_data( $managedname, $date_local, $upgrade, $serial, $model );    # it is necessary to have all server in cfg page
        next;
      }
      else {

        if ( $hmcv_num >= 733 ) {
          print "Utilization data collection is set to \"$step\" for managed system : $host:$managedname\n";
          print "lpar2rrd tool is configured for $STEP seconds interval\n";
          print "Your HMC supports it as its version is higher than 7.3.3\n";
          print "Ignore this message if you want to use 3600s sample rate anyway\n";
          print "ssh hscroot\@$host \"chlparutil -r config -m $managedname -s $STEP\"\n";
          print "*****WARNING*****WARNING*****WARNING*****\n";

          # go for next managed system / hmc server
          #next;
        }
      }
    }

    if ( $IVM == 1 ) {

      # create a file "IVM" to be able install_html check whether it is IVM or not
      if ( !-f "$wrkdir/$managedname/$host/IVM" ) {
        open( FH, "> $wrkdir/$managedname/$host/IVM" ) || error( " Can't create $wrkdir/$managedname/$host/IVM : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        print FH "IVM\n";
        close(FH);
      }
    }
    else {
      # just to be sure, sometimes happens than HMC based is signed for ever as IVM due to some error
      if ( -f "$wrkdir/$managedname/$host/IVM" ) {
        unlink("$wrkdir/$managedname/$host/IVM");
      }
    }
    LoadDataModule::smdc_touch( $SDMC, $wrkdir, $managedname, $host, $act_time );

    $input          = "$wrkdir/$managedname/$host/in";
    $input_mem      = "$wrkdir/$managedname/$host/mem.in";
    $input_pool     = "$wrkdir/$managedname/$host/pool.in";
    $input_pool_mem = "$wrkdir/$managedname/$host/mem_sh.in";
    $input_pool_sh  = "$wrkdir/$managedname/$host/pool_sh.in";
    $input_cod      = "$wrkdir/$managedname/$host/cod.in";
    $input_sriov    = "$wrkdir/$managedname/$host/sriov.in";
    $input_lan      = "$wrkdir/$managedname/$host/adapters.in";
    $input_fcs      = "$wrkdir/$managedname/$host/fcs_ada.in";
    $input_gpa      = "$wrkdir/$managedname/$host/gpa_ada.in";
    $input_hea      = "$wrkdir/$managedname/$host/hea_ada.in";

    # _shell variables for usage in shell cmd lines, must be to avoid a roblem with spaces in managed names
    # usage only for shell, means in ssh ...., perl natively has no problem with that
    $input_shell          = $input;
    $input_mem_shell      = $input_mem;
    $input_pool_shell     = $input_pool;
    $input_pool_mem_shell = $input_pool_mem;
    $input_pool_sh_shell  = $input_pool_sh;
    $input_cod_shell      = $input_cod;
    $input_shell          =~ s/ /\\ /g;
    $input_mem_shell      =~ s/ /\\ /g;
    $input_pool_shell     =~ s/ /\\ /g;
    $input_pool_mem_shell =~ s/ /\\ /g;
    $input_pool_sh_shell  =~ s/ /\\ /g;
    $input_cod_shell      =~ s/ /\\ /g;

    # allow collection data : chlparutil -r config  -m managed_system -s 3600

    # for 1hour sample rate --> suffix "h", for 1min and other suffix "m"
    if ( $step == 3600 ) {
      $type_sam = "h";
    }
    else {
      $type_sam = "m";
    }

    # must be here otherwise en error for 1h sample rates when creating RRD DB
    # it was fixed in 2.05
    $no_time = $step * $NO_TIME_MULTIPLY;

    $loadhours = 0;    # must be here before rrd_check

    rrd_check( $managedname, $host );

    print "sample rate    : $host:$managedname $step seconds\n" if $DEBUG;

    # here must be local time on HMC, need Unix time and date in text to have complete time
    my $date;
    if ($restapi) {
      $date = strftime "%m/%d/%Y %H:%M:%S", localtime( time() );
    }
    else {
      $date = `$SSH $hmc_user\@$host " date \'+%m/%d/%Y %H:%M:%S\'"`;
    }
    chomp($date);
    my $t = str2time($date);    # ignore date +%s on purpose!!!
                                #print "DATE: $t -- $date \n" ;

    my $time_act = strftime "%d/%m/%y %H:%M:%S", localtime( time() );
    print "HMC date       : $host:$managedname $date (local time: $time_act) \n" if $DEBUG;

    # set defaults for IVM
    ( $sec, $ivmmin, $ivmh, $ivmd, $ivmm, $ivmy, $wday, $yday, $isdst ) = localtime( $t - 432000 );    # just last 5 days for IVM
    $ivmy += 1900;
    $ivmm += 1;

    my $last_rec_file = "";

    my $where = "file";
    if ( !$loadhours && !$restapi ) {                                                                  # all except the initial load --> check rrd_check
      if ( -f "$wrkdir/$managedname/$host/$last_file" ) {
        $where = "$last_file";

        # read timestamp of last record
        # this is main loop how to get corectly timestamp of last record!!!
        open( FHLT, "< $wrkdir/$managedname/$host/$last_file" ) || error( " Can't open $wrkdir/$managedname/$host/$last_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        foreach my $line1 (<FHLT>) {
          chomp($line1);
          $last_rec_file = $line1;
        }
        print "last rec 1     : $host:$managedname $last_rec_file $wrkdir/$managedname/$host/$last_file\n";
        close(FHLT);
        my $ret = substr( $last_rec_file, 0, 1 );
        if ( $last_rec_file eq '' || $ret =~ /\D/ ) {

          # in case of an issue with last file, remove it and use default 140 min? for further run ...
          error("Wrong input data, deleting file : $wrkdir/$managedname/$host/$last_file : $last_rec_file");
          unlink("$wrkdir/$managedname/$host/$last_file");

          # place ther last 2h when an issue with last.txt
          $loadhours = 2;
          $loadmins  = 120;
          $last_rec  = $t - 7200;
        }
        else {
          $last_rec  = str2time($last_rec_file);
          $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
          $loadhours++;
          $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
        }
      }
      else {
        # old not accurate way how to get last time stamp, keeping it here as backup if above temp fails for any reason
        if ( -f "$wrkdir/$managedname/$host/mem.rr$type_sam" ) {
          $where = "mem.rr$type_sam";

          # find out last record in the db (hourly)
          RRDp::cmd qq(last "$wrkdir/$managedname/$host/mem.rr$type_sam" );
          my $last_rec_raw = RRDp::read;
          chomp($$last_rec_raw);
          $last_rec  = $$last_rec_raw;
          $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
          $loadhours++;
          $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
          ( my $sec, $ivmmin, $ivmh, $ivmd, $ivmm, $ivmy, my $wday, my $yday, my $isdst ) = localtime($last_rec);
          $ivmy += 1900;
          $ivmm += 1;

          if ( $loadhours < 0 ) {                                        # Do not know why, but it sometimes happens!!!
            if ( -f "$wrkdir/$managedname/$host/pool.rr$type_sam" ) {

              # find out last record in the db (hourly)
              RRDp::cmd qq(last "$wrkdir/$managedname/$host/pool.rr$type_sam" );
              my $last_rec_raw = RRDp::read;
              chomp($$last_rec_raw);
              $last_rec  = $$last_rec_raw;
              $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
              $loadhours++;
              $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
              error("++2 $loadhours -- $last_rec -- $t");
            }
          }
        }
        else {
          if ( -f "$wrkdir/$managedname/$host/pool.rr$type_sam" ) {
            $where = "pool.rr$type_sam";

            # find out last record in the db (hourly)
            RRDp::cmd qq(last "$wrkdir/$managedname/$host/pool.rr$type_sam" );
            my $last_rec_raw = RRDp::read;
            chomp($$last_rec_raw);
            $last_rec  = $$last_rec_raw;
            $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
            $loadhours++;
            $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
          }
          else {
            $where     = "init";
            $loadmins  = $INIT_LOAD_IN_HOURS_BACK * 60;
            $loadhours = $INIT_LOAD_IN_HOURS_BACK;
          }
        }
      }
    }
    else {
      $where = "init";
      my $loadsecs = $INIT_LOAD_IN_HOURS_BACK * 3600;
      $last_rec = $t - $loadsecs;
    }

    if ( ( $loadhours <= 0 || $loadmins <= 0 ) && !$restapi ) {    # something wrong is here
      error("Last rec issue: $last_file:  $loadhours - $loadmins -  $last_rec -- $last_rec_file : $date : $t : 01");

      # place some reasonable defaults
      $loadhours = 2;
      $loadmins  = 120;
      $last_rec  = time();
      $last_rec  = $last_rec - 7200;
    }

    ( $sec, $ivmmin, $ivmh, $ivmd, $ivmm, $ivmy, $wday, $yday, $isdst ) = localtime($last_rec);
    $ivmy += 1900;
    $ivmm += 1;
    print "last rec 2     : $host:$managedname min:$loadmins , hour:$loadhours, $ivmm/$ivmd/$ivmy $ivmh:$ivmmin : $where\n" if $DEBUG;

    # data load must be before configuration load
    eval { hmc_load_data( $t, $managedname, $host, $last_rec, $t, $hmcv_num, $exclude_this_server, $model, $serial ); };
    if ($@) {
      print "ERROR:     $managedname, $host data load in " . __FILE__ . " at line " . __LINE__ . "\n";
      print "$@\n";
    }

    $date = localtime();
    print "date load      : $host:$managedname $date\n" if $DEBUG;

    my $ret = 0;

    # set alarm on first SSH command to make sure it does not hang
    eval {
      local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
      alarm($timeout_save);
      $ret = save_cfg_data( $managedname, $date, $upgrade, $serial, $model );
      alarm(0);
    };
    if ($@) {
      if ( $@ =~ /died in SIG ALRM/ ) {
        error( "$host:$managedname: save_cfg_data took more than $timeout_save sec, it has bee interupted to do not hang " . __FILE__ . ":" . __LINE__ );
        error( "$host:$managedname: when it happens regulary every day then contact LPAR2RRD support as the HMC might not provide required config data " . __FILE__ . ":" . __LINE__ );
        next;
      }
    }
    if ( $ret == 2 ) {
      next;    # server is switched off ???
    }

    lpm_exclude_vio( $host, $managedname, $wrkdir );

  }
  for ( my $j = 0; $j < $server_count; $j++ ) {
    print "Wait for chld  : $host $j \n" if $DEBUG;
    waitpid( $pid[$j], 0 );
  }
  print "All chld finish: $host \n" if $DEBUG;

  # Include HW info
  if ($HWINFO) {

    # set alarm on first SSH command to make sure it does not hang
    eval {
      local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
      alarm($timeout_save);
      get_cfg_server("gui-");    # must be here , it goes through servers itself
      alarm(0);
    };
    if ($@) {
      if ( $@ =~ /died in SIG ALRM/ ) {
        error( "$host:$managedname: save_cfg_data took more than $timeout_save sec, it has bee interupted to do not hang " . __FILE__ . ":" . __LINE__ );
        error( "$host:$managedname: when it happens regulary every day then contact LPAR2RRD support as the HMC might not provide required config data " . __FILE__ . ":" . __LINE__ );
        next;
      }
    }
  }

  my $time = time();

  # Total CPU per HMC --> must be exactly here
  @managednamelist = sort { lc($a) cmp lc($b) } @managednamelist_un;    # just to be sure!!!
                                                                        # against: semi-panic: attempt to dup freed string at ....

  # it creates cmd files only
  frame_multi( "day",   "m", "d", "MINUTE:60:HOUR:2:HOUR:4:0:%H" );
  frame_multi( "week",  "m", "w", "HOUR:8:DAY:1:DAY:1:86400:%a" );
  frame_multi( "month", "m", "m", "DAY:1:DAY:2:DAY:2:0:%d" );
  frame_multi( "year",  "m", "y", "MONTH:1:MONTH:1:MONTH:1:0:%b" );
  multiview_hmc( $host, "lpar-multi", "d", "m", $time, "day",   "MINUTE:60:HOUR:2:HOUR:4:0:%H" );
  multiview_hmc( $host, "lpar-multi", "w", "m", $time, "week",  "HOUR:8:DAY:1:DAY:1:86400:%a" );
  multiview_hmc( $host, "lpar-multi", "m", "m", $time, "month", "DAY:1:DAY:2:DAY:2:0:%d" );
  multiview_hmc( $host, "lpar-multi", "y", "m", $time, "year",  "MONTH:1:MONTH:1:MONTH:1:0:%b" );
  frame_multi_total( "day",   "m", "d", "MINUTE:60:HOUR:2:HOUR:4:0:%H" );
  frame_multi_total( "week",  "m", "w", "HOUR:8:DAY:1:DAY:1:86400:%a" );
  frame_multi_total( "month", "m", "m", "DAY:1:DAY:2:DAY:2:0:%d" );
  frame_multi_total( "year",  "m", "y", "MONTH:1:MONTH:1:MONTH:1:0:%b" );

  return 0;
}

# This is jus for internal debug purposes
sub graph_without_load_data {

  return 0;

  if ( $DEBUG == 2 ) {
    $step = 60;
    $STEP = 60;

    # start RRD via a pipe
    use RRDp;
    RRDp::start "$rrdtool";

    # find out existing RRD databases for particular hostname
    opendir( DIR, "$wrkdir/" ) || error( " directory does not exists : $wrkdir" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @managednames = readdir(DIR);
    closedir(DIR);

    foreach my $managedname_act (@managednames) {
      chomp($managedname_act);
      if ( $managedname_act =~ m/^\./ ) {
        next;
      }
      $managedname = $managedname_act;

      #print "Server :  $managedname\n";
      opendir( DIR, "$wrkdir/$managedname" ) || error( " directory does not exists : $wrkdir/$managedname" . __FILE__ . ":" . __LINE__ ) && return 0;
      my @hosts = readdir(DIR);
      closedir(DIR);
      foreach my $host_act (@hosts) {
        chomp($host_act);
        if ( $host_act =~ m/^\./ ) {
          next;
        }
        $host = $host_act;
        if ( -f "$wrkdir/$managedname/$host/IVM" ) {
          $IVM = 1;
          $HMC = 0;
        }
        else {
          $IVM = 0;
          $HMC = 1;
        }
        print "HMC $host : $managedname : IVM:$IVM HMC:$HMC\n";

        #$type_sam="m";
        #rrd_find ($managedname,$host);
        #$type_sam="d";
        #rrd_find ($managedname,$host);
        #hea_run  ($managedname);
        #fcs_run  ($managedname);
      }
    }

    # HMC multi ...
    #@managednamelist = ("POWER520-1,,","POWER520-2,,","POWER520-3,,","POWER520-4,,","POWER750-1,,","POWER770-1,,","POWER770-2,,","POWER770-3,,","POWER770-4,,","POWER770-5,,");
    #my @hosts = ("hmca","hmcb");

    #my $host_act = "";
    #foreach $host_act (@hosts) {
    #  chomp ($host_act);
    #  $host=$host_act;
    #  $type_sam="m";
    #  my $ret_multi = frame_multi ("day","m","d","MINUTE:60:HOUR:2:HOUR:4:0:%H",@managednamelist);
    #  if ( $ret_multi == 0 ) {
    #    frame_multi ("week","m","w","HOUR:8:DAY:1:DAY:1:86400:%a",@managednamelist);
    #    frame_multi ("4 weeks","m","m","DAY:1:DAY:2:DAY:2:0:%d",@managednamelist);
    #    frame_multi ("year","m","y","MONTH:1:MONTH:1:MONTH:1:0:%b",@managednamelist);
    #  }
    #}

    # close RRD pipe
    RRDp::end;
    return 1;
  }
  return 0;
}

sub load_data_and_graph {
  my $exclude_this_server = shift;
  my $model               = shift;
  my $serial              = shift;
  if ($exclude_this_server) {
    $json_on = 0;
  }
  print "Starting load_data* for $managedname @ $host - API:$json_on, Save Files: $save_files\n";

  # there is no on purpose checking return code to avoid that a problem with one source affects everything
  if (defined $ENV{FIX_CPU_TOTAL_GAPS} && $ENV{FIX_CPU_TOTAL_GAPS} == 1){
    LoadDataModule::load_data_h( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $json_on, $save_files, $model, $serial, $TZ_HMC, $TZ_LOCAL );
  } elsif (defined $ENV{FIX_CPU_TOTAL_GAPS} && $ENV{FIX_CPU_TOTAL_GAPS} == 2){
    LoadDataModule::load_data_old( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $json_on, $save_files, $model, $serial, $TZ_HMC, $TZ_LOCAL );
  } elsif (defined $ENV{FIX_CPU_TOTAL_GAPS} && $ENV{FIX_CPU_TOTAL_GAPS} == 3){
    LoadDataModule::load_data_old2( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $json_on, $save_files, $model, $serial, $TZ_HMC, $TZ_LOCAL );
  }
  else {
    LoadDataModule::load_data( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file, $no_time, $SSH, $hmc_user, $json_on, $save_files, $model, $serial, $TZ_HMC, $TZ_LOCAL );
  }

  # Load & crate graphs
  LoadDataModule::load_data_sriov( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_sriov, $input_sriov, $no_time, $json_on, $save_files, $TZ_HMC, $TZ_LOCAL );
  LoadDataModule::load_data_lan( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_lan, $input_lan, $no_time, $json_on, $save_files, $TZ_HMC, $TZ_LOCAL );

  LoadDataModule::load_data_fcs( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_fcs, $input_fcs, $no_time, $json_on, $save_files, $TZ_HMC, $TZ_LOCAL );

  LoadDataModule::load_data_gpa( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_gpa, $input_gpa, $no_time, $json_on, $save_files, $TZ_HMC, $TZ_LOCAL );

  LoadDataModule::load_data_hea( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_hea, $input_hea, $no_time, $json_on, $save_files, $TZ_HMC, $TZ_LOCAL );

  LoadDataModule::load_data_mem( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_mem, $input_mem, $no_time, $json_on, $save_files, $TZ_HMC, $TZ_LOCAL );

  LoadDataModule::load_data_cod( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_cod, $input_cod, $no_time, $TZ_HMC, $TZ_LOCAL );

  LoadDataModule::load_data_pool( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_pool, $input_pool, $no_time, $json_on, $save_files, $TZ_HMC, $TZ_LOCAL );
  print "End load_data*  for HMC($HMC) $managedname @ $host - API:$json_on, Save Files: $save_files\n";

  if ( $HMC == 1 || $SDMC == 1 ) {    # IVM does nt have it
    LoadDataModule::load_data_pool_sh( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_sh_pool, $input_pool_sh, $SSH, $hmc_user, \@pool_list, $pool_list_file, $no_time, $json_on, $save_files, $TZ_HMC, $TZ_LOCAL );

  }
  LoadDataModule::load_data_pool_mem( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@lpar_trans, $last_file_sh_mem, $input_pool_mem, $no_time, $json_on, $save_files, $TZ_HMC, $TZ_LOCAL );    # it has to be always last one !!!
  return 0;
}

sub hmc_load_data {
  my $hmc_utime = shift;

  #my $loadhours = shift; # it must be GLOBAL variable
  my $managedname = shift;
  my $host        = shift;

  #my $sec = shift;
  #my $ivmmin = shift;
  #my $ivmh = shift;
  #my $ivmd = shift;
  #my $ivmm = shift;
  #my $ivmy = shift;
  #my $wday = shift;
  #my $yday = shift;
  #my $isdst = shift;
  my $last_rec            = shift;
  my $t                   = shift;
  my $hmcv_num            = shift;
  my $exclude_this_server = shift;
  my $model               = shift;
  my $serial              = shift;

  if ( $loadhours == $INIT_LOAD_IN_HOURS_BACK ) {

    # just to be sure ....
    $loadmins = $INIT_LOAD_IN_HOURS_BACK * 60;
  }

  if ( $loadhours <= 0 || $loadmins <= 0 ) {    # workaround as this sometimes is negative , need to check it out ...
    if ( !$last_rec eq '' && !$restapi ) {
      error("$act_time: time issue 1   : $host:$managedname hours:$loadhours mins:$loadmins Last saved record (HMC lslparutil time) : $last_rec ; HMC time : $t");
    }
    $loadhours = 3;
    $loadmins  = 140;
  }

  # workaround for HMC < 7.7.2 when it crashes in usage --minutes
  $timerange = " --minutes " . $loadmins . " ";

  #$timerange = " -h ".$loadhours." " ;
  # -h obviously did not help ......

  my $loadsecs        = $loadmins * 60;
  my $hmc_start_utime = $hmc_utime - $loadsecs;

  # in 4.02 it has been moved here from LoadData..., the problem had yearly CPU pool aggregated graphs (HMC based : rrd only)a
  print "LPAR2RRD test   : serial:$serial model:$model\n";
  my $UUID_SERVER = PowerDataWrapper::md5_string("$serial $model");
  procpoolagg( $host, $managedname, $UUID_SERVER ) if ( !$restapi );

  if ( $loadmins > 0 ) {

    if ( $loadhours != $INIT_LOAD_IN_HOURS_BACK ) {
      print "download data  : $host:$managedname last $loadmins  minute(s) ($loadhours hours)\n" if $DEBUG;
    }

    #
    # Load lpar data - it must be always first due to last file already loaded (last.txt)
    #

    print "fetching HMC   : $host:$managedname lpar data\n" if $DEBUG;
    if ( $step == 3600 ) {
      if ( $loadhours >= 1 ) {
        if ( $HMC == 1 && $restapi == 0 ) {    #snad?
          if ( $hmcv_num < 700 ) {
            print "HMC VERSION UNDER 700\n";
            `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s $type_sam -r lpar -h $loadhours -m \\"$managedname\\" -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles  --filter \"event_types=sample\"" > $input_shell-$type_sam`;
          }
          else {
            print "HMC VERSION ABOVE 700\n";
            print "lslparutil -s $type_sam -r lpar -h $loadhours $restrict_rows -m $managedname -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,shared_cycles_while_active$mem_params$idle_param --filter event_types=sample\n";

            `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s $type_sam -r lpar -h $loadhours $restrict_rows -m \\"$managedname\\" -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,shared_cycles_while_active$mem_params$idle_param --filter \"event_types=sample\"" > $input_shell-$type_sam`;
          }
        }
        if ( $IVM == 1 ) {
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r lpar --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,lpar_id,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,donated_cycles$mem_params" > $input_shell-$type_sam`;
        }
        if ( $SDMC == 1 ) {
          LoadDataModule::sdmc_lpar_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_shell-$type_sam", $type_sam, 0, "", $mem_params );

          # firt 0 means that t is called from alerting --> HMC data input file must have "alert" suffix"
          # here must be 1
        }
      }
    }
    else {
      if ( $HMC == 1 && !$restapi ) {
        #
        # here is the workaround for HMC < 7.2.3 for the problem with exhasting the memory during lslparutil
        #
        my $rowCount   = $MAX_ROWS;
        my $rowTotal   = 0;
        my $mins       = 0;
        my $line2      = "";
        my $repeat     = 0;
        my $unixt_prev = 0;           # workaround to brake endless loop after daylight saving time
        while ( $rowCount == $MAX_ROWS ) {
          $repeat++;
          if ( $rowTotal == 0 ) {

            #print "--- $timerange  : $restrict_rows\n" if $DEBUG ;
            print "fetching HMC 0 : $host:$managedname $timerange  : $restrict_rows\n" if $DEBUG;
            `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r lpar $timerange $restrict_rows -m \\"$managedname\\" -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,shared_cycles_while_active$mem_params$idle_param  --filter \"event_types=sample\"" > $input_shell-$type_sam`;
          }
          else {
            ( my $time_end, my $lpar, my $curr_proc_units, my $curr_procs, my $curr_sharing_mode, my $entitled_cycles, my $capped_cycles, my $uncapped_cycles, my $shared_cycles_while_active ) = split( /,/, $line2 );
            my $unixt = str2time($time_end);

            # trick as skip endless loop after daylight saving time
            if ( $unixt_prev > 0 && $unixt > $unixt_prev ) {
              $unixt = $unixt_prev - 3600;
            }
            $unixt_prev = $unixt;

            #print "--- $unixt - $rowCount : $line2 \n" if $DEBUG ;
            ( my $sec, my $hmcmin, my $hmch, my $hmcd, my $hmcm, my $hmcy, my $wday, my $yday, my $isdst ) = localtime($unixt);
            $hmcy += 1900;
            $hmcm++;    # month + 1, it starts from 0 in unix

            #print "DEGUG == $unixt : $hmc_start_utime\n";
            if ( $unixt <= $hmc_start_utime ) {
              print "end time reach : $host:$managedname $hmcy-$hmcm-$hmcd $hmch:$hmcmin(to be downloaded) - $time_end(downloaded): $unixt < $hmc_start_utime\n";
              last;     #already Rdownloaded required time range
            }

            print "fetching HMC   : $host:$managedname lpar data : next $MAX_ROWS : $hmcy-$hmcm-$hmcd $hmch:$hmcmin - $time_end\n" if $DEBUG;
            `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r lpar $restrict_rows --endyear $hmcy --endmonth $hmcm --endday $hmcd --endhour $hmch --endminute $hmcmin -m \\"$managedname\\" -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,shared_cycles_while_active$mem_params$idle_param  --filter \"event_types=sample\"" >> $input_shell-$type_sam`;
          }
          open( FH, "< $input-$type_sam" ) || error( " Can't open $input-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          $rowCount = 0;
          while ( my $l = <FH> ) {
            chomp($l);
            $rowCount++;
            $line2 = $l;
          }
          close(FH);
          $rowTotal = $rowCount;
          $rowCount = $rowCount / $repeat;
        }
        print "fetched        : $host:$managedname $rowTotal rows\n" if $DEBUG;
      }

      # else{
      #   #restApiCodeHere
      #   if ($justOnce == 1){ #this code does fetch data in fork so it's needed to run it just once.
      #     # just load existing data when jsons are not used. This require to have load.sh in crontab at least every 20 minutes (Rest Api guarantee datfrom latest 30 minutes)
      #     if ($json_on != 1){
      #       print "Fetching HMC Rest Api Data to in-m files\n";
      #       `/bin/bash /home/lpar2rrd/lpar2rrd/bin/start_hmc_rest_api.sh $ENV{HMC} $ENV{HMC_PORT} $ENV{HMC_USER} $ENV{HMC_PASSWORD} $ENV{INPUTDIR}`;
      #       print "HMC Rest Api Data Fetched and written to in-m files.\n";
      #     }
      #     $justOnce = 0;
      #   }
      # }

      if ( $IVM == 1 ) {
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r lpar --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,lpar_id,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,donated_cycles$mem_params" > $input_shell-$type_sam`;
      }
      if ( $SDMC == 1 ) {
        LoadDataModule::sdmc_lpar_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_shell-$type_sam", $type_sam, 0, "", $mem_params );

        # first 0 means that t is called from alerting --> HMC data input file must have "alert" suffix"
        # here must be 1
      }
    }

    #
    # Load CPU pool data
    #

    print "fetching HMC   : $host:$managedname pool data\n" if $DEBUG;

    # refresh last timestamp by actual one for that , it modifies $loadhours, $loadmins and IVM/SDMC ... days ...
    last_timestamp( $wrkdir, $managedname, $host, $last_file_pool, "pool", $t );

    if ( $step == 3600 ) {
      if ( $loadhours >= 1 ) {
        if ( $HMC == 1 && $restapi == 0 ) {
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s $type_sam -r pool  -h $loadhours $restrict_rows  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units,curr_avail_pool_proc_units  --filter \"event_types=sample\"" > $input_pool_shell-$type_sam`;

          print "fetching HMC   : $host:$managedname shared pool data\n" if $DEBUG;
          last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_pool, "SharedPool0", $t );
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s $type_sam -r procpool  -h $loadhours $restrict_rows -m \\"$managedname\\" -F time,shared_proc_pool_id,total_pool_cycles,utilized_pool_cycles  --filter \"event_types=sample\"" > $input_pool_sh_shell-$type_sam`;
        }
        if ( $IVM == 1 ) {
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r pool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units,curr_avail_pool_proc_units" > $input_pool_shell-$type_sam`;
        }
        if ( $SDMC == 1 ) {
          LoadDataModule::sdmc_pool_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_shell-$type_sam", $type_sam );
          print "fetching HMC   : $host:$managedname shared pool data\n" if $DEBUG;
          last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_pool, "SharedPool0", $t );
          LoadDataModule::sdmc_procpool_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_sh_shell-$type_sam", $type_sam );
        }
      }
    }
    else {
      if ( $HMC == 1 && $restapi == 0 ) {
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r pool $timerange $restrict_rows -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units,curr_avail_pool_proc_units  --filter \"event_types=sample\"" > $input_pool_shell-$type_sam`;

        print "fetching HMC   : $host:$managedname shared pool data\n" if $DEBUG;
        last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_pool, "SharedPool0", $t );
        print "fetching HMC   : $host:$managedname shared pool data\n" if $DEBUG;
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r procpool $timerange $restrict_rows -m \\"$managedname\\" -F time,shared_proc_pool_id,total_pool_cycles,utilized_pool_cycles  --filter \"event_types=sample\"" > $input_pool_sh_shell-$type_sam`;
      }
      if ( $IVM == 1 ) {
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r pool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units,curr_avail_pool_proc_units" > $input_pool_shell-$type_sam`;
      }
      if ( $SDMC == 1 ) {
        LoadDataModule::sdmc_pool_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_shell-$type_sam", $type_sam, 0 );
        print "fetching HMC   : $host:$managedname shared pool data\n" if $DEBUG;
        last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_pool, "SharedPool0", $t );
        LoadDataModule::sdmc_procpool_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_sh_shell-$type_sam", $type_sam, 0 );
      }
    }

    #
    # Load memory data
    #

    print "fetching HMC   : $host:$managedname mem data\n" if $DEBUG;

    # refresh last timestamp by actual one for that , it modifies $loadhours, $loadmins and IVM/SDMC ... days ...
    last_timestamp( $wrkdir, $managedname, $host, $last_file_mem, "mem", $t );

    if ( $step == 3600 ) {
      if ( $loadhours >= 1 ) {
        if ( $HMC == 1 && $restapi == 0 ) {
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s $type_sam -r sys -h $loadhours  $restrict_rows -m \\"$managedname\\" -F time,curr_avail_sys_mem,configurable_sys_mem,sys_firmware_mem --filter \"event_types=sample\"" > $input_mem_shell-$type_sam`;
          if ( $hmcv_num > 734 || $FSM == 1 ) {

            # set params for lslparutil and AMS available from HMC V7R3.4.0 Service Pack 2 (05-21-2009)
            last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_mem, "mem-pool", $t );
            `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s $type_sam -r mempool -h $loadhours  $restrict_rows -m \\"$managedname\\" -F time,curr_pool_mem,lpar_curr_io_entitled_mem,lpar_mapped_io_entitled_mem,lpar_run_mem,sys_firmware_pool_mem --filter \"event_types=sample\"" > $input_pool_mem_shell-$type_sam`;
          }
        }
        if ( $IVM == 1 ) {
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r sys --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,curr_avail_sys_mem,configurable_sys_mem,sys_firmware_mem " > $input_mem_shell-$type_sam`;
          last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_mem, "mem-pool", $t );
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r mempool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,curr_pool_mem,lpar_curr_io_entitled_mem,lpar_mapped_io_entitled_mem,lpar_run_mem,sys_firmware_pool_mem " > $input_pool_mem_shell-$type_sam`;
        }
        if ( $SDMC == 1 ) {
          LoadDataModule::sdmc_sys_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_mem_shell-$type_sam", $type_sam, 0 );
          last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_mem, "mem-pool", $t );
          LoadDataModule::sdmc_pool_mem_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_mem_shell-$type_sam", $type_sam, 0 );
        }
      }
    }
    else {
      if ( $HMC == 1 && !$restapi ) {
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r sys $timerange $restrict_rows -m \\"$managedname\\" -F time,curr_avail_sys_mem,configurable_sys_mem,sys_firmware_mem --filter \"event_types=sample\"" > $input_mem_shell-$type_sam`;
        if ( $hmcv_num > 734 || $FSM == 1 ) {
          last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_mem, "mem-pool", $t );
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r mempool $timerange $restrict_rows -m \\"$managedname\\" -F time,curr_pool_mem,lpar_curr_io_entitled_mem,lpar_mapped_io_entitled_mem,lpar_run_mem,sys_firmware_pool_mem --filter \"event_types=sample\"" > $input_pool_mem_shell-$type_sam`;
        }
      }
      if ( $IVM == 1 ) {
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r sys --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,curr_avail_sys_mem,configurable_sys_mem,sys_firmware_mem" > $input_mem_shell-$type_sam`;
        last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_mem, "mem-pool", $t );
        `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r mempool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,curr_pool_mem,lpar_curr_io_entitled_mem,lpar_mapped_io_entitled_mem,lpar_run_mem,sys_firmware_pool_mem " > $input_pool_mem_shell-$type_sam`;
      }
      if ( $SDMC == 1 ) {
        LoadDataModule::sdmc_sys_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_mem_shell-$type_sam", $type_sam, 0 );
        last_timestamp( $wrkdir, $managedname, $host, $last_file_sh_mem, "mem-pool", $t );
        LoadDataModule::sdmc_pool_mem_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_mem_shell-$type_sam", $type_sam, 0 );
      }
    }

    #
    # Load CoD data
    #

    print "fetching HMC   : $host:$managedname CoD data\n" if $DEBUG;

    # refresh last timestamp by actual one for that , it modifies $loadhours, $loadmins and IVM/SDMC ... days ...
    last_timestamp( $wrkdir, $managedname, $host, $last_file_cod, "cod", $t );

    if ( $step == 3600 ) {
      if ( $loadhours >= 1 ) {
        if ( $HMC == 1 && !$restapi ) {
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s $type_sam -r all -h $loadhours  $restrict_rows -m \\"$managedname\\" -F time,used_proc_min,unreported_proc_min --filter \"event_types=utility_cod_proc_usage\"" > $input_cod_shell-$type_sam`;
        }

        # not sure if IVM supports that event_types=utility_cod_proc_usage --> have not found in IVM man
        #if ( $IVM == 1 ){
        #  `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r all --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,used_proc_min,unreported_proc_min " > $input_cod_shell-$type_sam` ;
        #}
        if ( $SDMC == 1 ) {
          LoadDataModule::sdmc_cod_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_cod_shell-$type_sam", $type_sam, 0 );
        }
      }
    }
    else {
      if ( $HMC == 1 ) {
        if ( !$restapi ) {
          `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -s s -r all $timerange $restrict_rows -m \\"$managedname\\" -F time,used_proc_min,unreported_proc_min --filter \"event_types=utility_cod_proc_usage\"" > $input_cod_shell-$type_sam`;
        }
      }

      # not sure if IVM supports that event_types=utility_cod_proc_usage --> have not found in IVM man
      #if ( $IVM == 1 ){
      #  `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r all --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,used_proc_min,unreported_proc_min" > $input_cod_shell-$type_sam` ;
      #}
      if ( $SDMC == 1 ) {
        LoadDataModule::sdmc_cod_load( $SSH, $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_cod_shell-$type_sam", $type_sam, 0 );
      }
    }

    if ( $cycle_count == $PARALLELIZATION ) {
      print "No fork        : $host:$managedname : $server_count\n" if $DEBUG;
      load_data_and_graph( $exclude_this_server, $model, $serial );
      $cycle_count = 0;
    }
    else {
      $pid[$server_count] = fork();
      if ( not defined $pid[$server_count] ) {
        error("$host:$managedname could not fork");
      }
      elsif ( $pid[$server_count] == 0 ) {
        print "Fork           : $host:$managedname : $server_count\n" if $DEBUG;
        RRDp::end;
        RRDp::start "$rrdtool";
        load_data_and_graph( $exclude_this_server, $model, $serial );
        print "Fork exit      : $host:$managedname : $server_count\n" if $DEBUG;
        RRDp::end;
        exit(0);
      }
      print "Parent continue: $host:$managedname $pid[$server_count]\n";
      $server_count++;
    }
    $cycle_count++;
  }
  else {
    my $t1 = localtime($last_rec);
    my $t2 = localtime($t);
    error("$act_time: time issue 2   : $host:$managedname hours:$loadhours mins:$loadmins Last saved record (HMC lslparutil time) : $last_rec ; HMC time : $t - $t1 - $t2");
  }

}

sub rrd_check {
  my $managedname = shift;
  my $host        = shift;
  my $count       = 0;

  # Check whether do initial or normal load
  if ( -f "$wrkdir/$managedname/$host/pool.rrm" ) {
    $count = 1;
  }
  else {
    if ( -f "$wrkdir/$managedname/$host/pool.rrh" ) {
      $count = 1;
    }
  }

  if ( $count == 0 ) {
    print "There is no RRD: $host:$managedname attempting to do initial load, be patient, it might take some time\n" if $DEBUG;

    # get last 2ays
    # it is for initial load
    $loadhours = $INIT_LOAD_IN_HOURS_BACK;
    $loadmins  = $INIT_LOAD_IN_HOURS_BACK * 60;
  }
  return 0;
}

sub save_config {
  my $managedname  = shift;
  my $date         = shift;
  my $upgrade      = shift;
  my $out_file     = "$CONFIG_HISTORY/$managedname/$host/config.cfg";
  my $out_file_tmp = "$CONFIG_HISTORY/$managedname/$host/config.cfg-tmp";
  if ($restapi) {
    $out_file     = "$CONFIG_HISTORY/$managedname/$host/config_by_hw_cfg_sys.cfg";
    $out_file_tmp = "$CONFIG_HISTORY/$managedname/$host/config_by_hw_cfg_sys.cfg-tmp";
    return;
  }
  my $out_file_shell     = $out_file;
  my $out_file_tmp_shell = $out_file_tmp;
  $out_file_tmp_shell =~ s/ /\\ /g;
  $out_file_shell     =~ s/ /\\ /g;
  my $lpar        = "";
  my $hw_cfg_lpar = "$bindir/hw_cfg_lpar.sh";
  my $hw_cfg_sys  = "$bindir/hw_cfg_sys.sh";

  #if ( ! -f "$hw_cfg_lpar" ) {
  #  $hw_cfg_lpar="true"
  #}
  #if ( ! -f "hw_cfg_sys" ) {
  #  $hw_cfg_lpar="true"
  #}

  # do not update cfg file if less than 1 day
  if ( -f "$out_file" && $upgrade == 0 ) {
    my $png_time = ( stat("$out_file") )[9];
    ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
    ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($png_time);
    if ( $aday == $png_day ) {
      return 0;
    }
    else {
      print "cfg refresh    : $aday != $png_day\n" if $DEBUG;
    }
  }
  print "config save    : $host:$managedname once a day ... \n" if $DEBUG;
  print "cfg save sys   : $host:$managedname \n"                if $DEBUG;

  if ( $IVM == 1 ) {

    # save CPU speed for CPU workload estimator
    `$SSH $hmc_user\@$host "ioscli lsdev -dev proc0 -attr frequency|tail -1" > $wrkdir/$managedname/$host/cpu_speed.txt`;
  }

  LoadDataModule::touch("config save");

  # read hw_cfg_sys.sh
  open( FHS, "< $hw_cfg_sys" ) || error( " Cannot open  $hw_cfg_sys: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  my $cmd_sys = "";
  while ( my $line = <FHS> ) {
    $cmd_sys = $cmd_sys . $line;
  }
  close(FHS);
  $cmd_sys =~ s/\$managedname/$managedname/g;

  #$cmd_sys =~ s/\$managedname/\\"$managedname\\"/g;
  # with above uncomented do not work systems with space inside
  #print "$cmd_sys\n";

  # read hw_cfg_lpar.sh
  #  open(FHL, "< $hw_cfg_lpar") || error(" Cannot open  $hw_cfg_lpar: $!".__FILE__.":".__LINE__) && return 0;
  #  my $cmd_lpar     = "";
  #  my $cmd_lpar_glb = "";
  #  while (my $line = <FHL>) {
  #    $cmd_lpar_glb = $cmd_lpar_glb.$line;
  #  }
  #  close (FHL);
  #  $cmd_lpar_glb =~ s/\$managedname/$managedname/g;
  #$cmd_lpar_glb =~ s/\$managedname/\\"$managedname\\"/g;
  # with above uncomented do not work systems with space inside
  #print "$cmd_lpar_glb\n";

  # get list of lpars
  my @lparlist;
  if ( $IVM == 1 ) {

    # IVM does not support "sort"
    @lparlist = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lssyscfg -r lpar -m \\"$managedname\\" -F name|sed 's/ /%20/g'"`;
  }
  elsif ( !$restapi ) {
    @lparlist = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lssyscfg -r lpar -m \\"$managedname\\" -F name|sort -f|sed 's/ /%20/g'"`;
  }

  `echo "<HTML> <HEAD> <TITLE>LPAR2RRD Configuration</TITLE> </HEAD> \
<BODY BGCOLOR=#D3D2D2 TEXT=#000000 LINK=#0000FF VLINK= #000080 ALINK=#FF0000 > \
<PRE>" > $out_file_tmp_shell`;

  #`ssh $hmc_user\@$host ". $hw_cfg_sys $managedname" |
  # sed -e 's/sys_time=[0-9][0-9]\\\/[0-9][0-9]\\\/[0-9][0-9][0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9],//g' \
  if ( $IVM == 1 ) {

    # IVM does not support "sort"
    $cmd_sys =~ s/|sort -nk 2 -t=//g;
    $cmd_sys =~ s/|sort -f//g;
    $cmd_sys =~ s/|sort//g;
  }
  `$SSH $hmc_user\@$host "$cmd_sys"  >> $out_file_tmp_shell`;

  #  foreach $lpar (@lparlist) {
  #    chomp($lpar);
  #    $cmd_lpar = $cmd_lpar_glb;
  #    # workaround for lpars which have a space within the name
  #    $cmd_lpar =~ s/\$lpar_space/$lpar/g;
  #    $lpar =~ s/%20/ /g;
  #    $lpar =~ s/\&\&1/\//g; # for those which have a slash
  #    $cmd_lpar =~ s/\$lpar/$lpar/g;
  #    if ( $IVM == 1 ) {
  #      # IVM does not support "sort"
  #      $cmd_lpar =~ s/|sort -nk 2 -t=//g;
  #      $cmd_lpar =~ s/|sort -f//g;
  #      $cmd_lpar =~ s/|sort//g;
  #    }
  #    print "cfg save       : $host:$managedname:$lpar\n";

  #in 1st echo line is necessary to back-slash all ';'
  #echo "</PRE><A NAME="aix4%20test%20/%#;%20/#"></A><HR><CENTER><B> LPAR : "aix4 test /%#; /#" </B></CENTER><HR><PRE>"
  #
  #  (my $cmd_lpar_preface, my $cmd_lpar_main) = split ('</PRE><A NAME=',$cmd_lpar);
  #  (my $cmd_lpar_text_to_replace,my $cmd_lpar_main_not_replace) = split ('</B></CENTER><HR><PRE>',$cmd_lpar_main);
  #  $cmd_lpar_text_to_replace =~ s/;/\\;/g;
  #  $cmd_lpar = $cmd_lpar_preface.'</PRE><A NAME=';
  #  $cmd_lpar .= $cmd_lpar_text_to_replace.'</B></CENTER><HR><PRE>'.$cmd_lpar_main_not_replace;

  #   `$SSH $hmc_user\@$host "$cmd_lpar" 2>/dev/null| \
  #	sed -e 's/^lpar_name=.*,lpar_id=[1-9],//g'  -e 's/^lpar_name=.*,lpar_id=[1-9][0-9],//g'  | \
  #	sed -e 's/,lpar_name=.*,lpar_id=[1-9],/,/g' -e 's/,lpar_name=.*,lpar_id=[1-9][0-9],/,/g' >> $out_file_tmp_shell`;
  #	# must be 2 x sed, 4 x "-e" is does not work !!!
  #  }
  #  `echo "</PRE></BODY></HTML>" >> $out_file_tmp_shell`;

######### CFG_SAVE FOR SERVER
  open( CFG_TMP, ">> $out_file_tmp" ) || error( "Cannot open $out_file_tmp: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my @lpar_config_all    = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lssyscfg -m '$managedname' -r lpar"`;
  my @lpar_profiles      = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lssyscfg -m '$managedname' -r prof"`;
  my @cpu_res            = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r proc --level lpar"`;
  my @mem_res            = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r mem --level lpar"`;
  my @phys_adap          = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r io --rsubtype slot"`;
  my @log_hea            = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r hea --rsubtype logical --level port"`;
  my @log_hea_per_sys    = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r hea --rsubtype logical --level sys"`;
  my @vir_slots          = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r virtualio --rsubtype slot --level slot"`;
  my @vir_serial         = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r virtualio --rsubtype serial --level lpar"`;
  my @vir_vasi           = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r virtualio --rsubtype vasi --level lpar "`;
  my @vir_ethernet       = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r virtualio --rsubtype eth --level lpar"`;
  my @vir_scsi           = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r virtualio --rsubtype scsi --level lpar"`;
  my @vir_slots_per_lpar = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r virtualio --rsubtype slot --level lpar"`;
  my @vir_opt            = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r virtualio --rsubtype virtualopti --level lpar"`;
  my @hca_adap           = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m '$managedname' -r hca --level lpar"`;

  foreach my $lpar_config (@lpar_config_all) {
    my $lpar_conf = ( split /,/, $lpar_config )[0];
    my $lpar_name = substr( $lpar_conf, 5 );
    print "cfg save       : $host:$managedname:$lpar_name\n";
    print CFG_TMP "</PRE><A NAME=$lpar_name></A><HR><CENTER><B> LPAR : $lpar_name </B></CENTER><HR><PRE>\n";
    print CFG_TMP "</PRE><B>LPAR config:</B><PRE>\n";

    my ($lpar_config_text) = grep /^name=$lpar_name,lpar_id=/, @lpar_config_all;
    if ( !defined($lpar_config_text) || $lpar_config_text eq '' ) {
      next;
    }
    print CFG_TMP "$lpar_config_text";

    # get name of current profile
    my $curr_profile = $lpar_config_text;
    $curr_profile =~ s/^.*,curr_profile=//;
    $curr_profile =~ s/,.*$//;

    print CFG_TMP "</PRE><B>LPAR profiles:</B><PRE>\n";

    my $lpar_id = ( split /,/, $lpar_config )[1];
    $lpar_id =~ s/lpar_id=//g;

    # default profile only
    foreach my $lpar_profiles_text ( grep /,lpar_name=$lpar_name,/, @lpar_profiles ) {
      if ( $lpar_profiles_text !~ m/^name=$curr_profile,/ ) {
        next;
      }
      $lpar_profiles_text =~ s/lpar_name=$lpar_name,//g;
      $lpar_profiles_text =~ s/lpar_id=$lpar_id,//g;
      chomp $lpar_profiles_text;
      print CFG_TMP "$lpar_profiles_text\n";
    }

    # rest of profiles
    foreach my $lpar_profiles_text ( grep /,lpar_name=$lpar_name,/, @lpar_profiles ) {
      if ( $lpar_profiles_text =~ m/^name=$curr_profile,/ ) {
        next;
      }
      $lpar_profiles_text =~ s/lpar_name=$lpar_name,//g;
      $lpar_profiles_text =~ s/lpar_id=$lpar_id,//g;
      chomp $lpar_profiles_text;
      print CFG_TMP "$lpar_profiles_text\n";
    }

    print CFG_TMP "</PRE><B>CPU resources:</B><PRE>\n";

    my ($cpu_res_text) = grep /^lpar_name=$lpar_name,/, @cpu_res;
    $cpu_res_text =~ s/^lpar_name=$lpar_name,lpar_id=$lpar_id,//;
    chomp $cpu_res_text;
    print CFG_TMP "$cpu_res_text\n";

    print CFG_TMP "</PRE><B>Memory resources [MB]:</B><PRE>\n";

    my ($mem_res_text) = grep /^lpar_name=$lpar_name,/, @mem_res;
    $mem_res_text =~ s/^lpar_name=$lpar_name,lpar_id=$lpar_id,//;
    chomp $mem_res_text;
    print CFG_TMP "$mem_res_text\n";

    print CFG_TMP "</PRE><B>Physical adapters:</B><PRE>\n";

    if ( grep /,lpar_name=$lpar_name,/, @phys_adap ) {
      my (@phys_adap_text) = grep /,lpar_name=$lpar_name,/, @phys_adap;
      foreach my $phys_adap_text (@phys_adap_text) {
        $phys_adap_text =~ s/,lpar_name=$lpar_name,lpar_id=$lpar_id//;
        chomp $phys_adap_text;
        print CFG_TMP "$phys_adap_text\n";
      }
    }
    else {
      print CFG_TMP"No results were found.\n";
    }

    print CFG_TMP "</PRE><B>Logical HEA: </B><PRE>\n";

    if ( grep /,lpar_id=$lpar_id,/, @log_hea ) {
      my (@log_hea_text) = grep /,lpar_id=$lpar_id,/, @log_hea;
      foreach my $log_hea_text (@log_hea_text) {
        chomp $log_hea_text;
        print CFG_TMP "$log_hea_text\n";
      }
    }
    else {
      print CFG_TMP"No results were found.\n";
    }

    print CFG_TMP "</PRE><B>Logical HEA per system:</B><PRE>\n";

    if ( grep /,lpar_name=$lpar_name,/, @log_hea_per_sys ) {
      my (@log_hea_per_sys_text) = grep /,lpar_name=$lpar_name,/, @log_hea_per_sys;
      foreach my $log_hea_per_sys_text (@log_hea_per_sys_text) {
        chomp $log_hea_per_sys_text;
        print CFG_TMP "$log_hea_per_sys_text\n";
      }
    }
    else {
      print CFG_TMP"No results were found.\n";
    }

    print CFG_TMP "</PRE><B>Virtual slots:</B><PRE>\n";

    my @vir_slots_text = grep /,lpar_name=$lpar_name,/, @vir_slots;
    foreach my $vir_slots_text (@vir_slots_text) {
      $vir_slots_text =~ s/,lpar_name=$lpar_name,lpar_id=$lpar_id//;

      #my $lpar_unsorted_slots = (split /,/, $vir_slots_text)[0];
      chomp $vir_slots_text;
      print CFG_TMP "$vir_slots_text\n";
    }

    print CFG_TMP "</PRE><B>Virtual serial:</B><PRE>\n";

    my @vir_serial_text = grep /^lpar_name=$lpar_name,/, @vir_serial;
    foreach my $vir_serial_text (@vir_serial_text) {
      $vir_serial_text =~ s/^lpar_name=$lpar_name,lpar_id=$lpar_id,//;
      chomp $vir_serial_text;
      print CFG_TMP "$vir_serial_text\n";
    }

    print CFG_TMP "</PRE><B>Virtual VASI:</B><PRE>\n";

    #my @vir_vasi_text = grep /HSCL8022 This command/, @vir_vasi;
    print CFG_TMP"HSCL8022 This command is only supported for POWER6 servers.\n";

    #if (grep /HSCL8022 This command/, @vir_vasi){
    #  print "CHYBA!!!\n";
    #}
    #print CFG_TMP"@vir_vasi_text";

    print CFG_TMP "</PRE><B>Virtual Ethernet:</B><PRE>\n";

    my @vir_ethernet_text = grep /^lpar_name=$lpar_name,/, @vir_ethernet;
    foreach my $vir_ethernet_text (@vir_ethernet_text) {
      $vir_ethernet_text =~ s/^lpar_name=$lpar_name,lpar_id=$lpar_id,//;
      chomp $vir_ethernet_text;
      print CFG_TMP "$vir_ethernet_text\n";
    }

    print CFG_TMP "</PRE><B>Virtual SCSI:</B><PRE>\n";

    my @vir_scsi_text = grep /^lpar_name=$lpar_name,/, @vir_scsi;
    foreach my $vir_scsi_text (@vir_scsi_text) {
      $vir_scsi_text =~ s/^lpar_name=$lpar_name,lpar_id=$lpar_id,//;
      chomp $vir_scsi_text;
      print CFG_TMP "$vir_scsi_text\n";
    }

    print CFG_TMP "</PRE><B>Virtual slots per lpar:</B><PRE>\n";

    my @vir_slots_per_lpar_text = grep /^lpar_name=$lpar_name,/, @vir_slots_per_lpar;
    foreach my $vir_slots_per_lpar_text (@vir_slots_per_lpar_text) {
      $vir_slots_per_lpar_text =~ s/^lpar_name=$lpar_name,lpar_id=$lpar_id,//;
      chomp $vir_slots_per_lpar_text;
      print CFG_TMP "$vir_slots_per_lpar_text\n";
    }

    print CFG_TMP "</PRE><B>Virtual OptiConnec:</B><PRE>\n";

    my @vir_opt_text = grep /No results were found/, @vir_opt;
    print CFG_TMP "@vir_opt_text";

    print CFG_TMP "</PRE><B>HCA adapters:</B><PRE>\n";

    my @hca_adap_text = grep /No results were found/, @hca_adap;
    print CFG_TMP "@hca_adap_text";

  }
  print CFG_TMP"</PRE></BODY></HTML>\n";
  close(CFG_TMP);

  print "cfg save form  : $host:$managedname \n" if $DEBUG;

  # copy $out_file_tmp to $out_file and devide some very long rows into more rows to be better readable in the web
  open( FHR, "< $out_file_tmp" ) || error( " Cannot open  $out_file_tmp: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  open( FHW, "> $out_file" )     || error( " Cannot open  $out_file: $!" . __FILE__ . ":" . __LINE__ )     && return 0;
  my $count           = 0;
  my $count_prof      = 0;
  my $line_prev       = "";
  my $count_no_result = 0;

  while ( my $line = <FHR> ) {
    chomp($line);

    # count == 2 is only for LPAR profiles  & CPU pools where can be more than 1 profile and it should be devided into more rows
    if ( $count == 2 ) {
      if ( $line =~ m/^name=/ ) {
        if ($count_prof) {
          print FHW "\n\n";
        }
      }
      $count_prof++;
    }
    if ( $line =~ "LPAR profiles:" ) {
      $count      = 2;
      $count_prof = 0;
      print FHW "$line\n";
      next;
    }

    if ( $line =~ "Memory - AMS:" || $line =~ "Memory - AMS - paging:" || $line =~ "Virtual VASI:" || $line =~ "Virtual slots per lpar:" || $line =~ "Physical IO per io pool level sys:" || $line =~ "Physical IO per io pool level pool:" || $line =~ "Ethernet:" || $line =~ "HEA logical:" || $line =~ "HEA physical per system:" || $line =~ "Logical HEA per system:" || $line =~ "Virtual SCSI:" || $line =~ "Virtual Ethernet:" || $line =~ "Logical HEA:" || $line =~ "CPU pools:" || $line =~ "Physical adapters:" || $line =~ "Physical IO per slot children:" || $line =~ "Physical IO per taggedio:" || $line =~ "HEA physical per port:" || $line =~ "HEA physical per port group:" || $line =~ "HEA logical per port:" || $line =~ "HCA adapters:" || $line =~ "SNI adapters:" || $line =~ "Virtual OptiConnec:" || $line_prev =~ "Firmware:" || $line_prev =~ "SR-IOV adapters:" || $line_prev =~ "SR-IOV ethernet logical ports:" || $line_prev =~ "SR-IOV ethernet physical ports:" || $line_prev =~ "SR-IOV converged ethernet physical ports:" || $line_prev =~ "SR-IOV unconfigured logical ports:" || $line_prev =~ "SR-IOV recoverable logical ports:" || $line_prev =~ "Capabilities:" ) {
      $line_prev       = $line;
      $count_no_result = 1;
      next;
    }

    if ($count_no_result) {
      if ( $line =~ "HSCL" || $line =~ "VIOSE0" || $line =~ "The managed system does not support hardware discovery." || $line =~ "The managed system does not support multiple shared processor pools." || $line =~ "No results were found." || $line =~ m/The command entered is either missing/ ) {
        $count_no_result = 0;
        next;
      }
      print FHW "$line_prev\n";
      $count_no_result = 0;
      if ( $line_prev =~ "Memory - AMS:" || $line_prev =~ "Memory - AMS - paging:" || $line_prev =~ "Virtual OptiConnec:" || $line_prev =~ "Virtual slots per lpar:" || $line_prev =~ "Physical IO per io pool level sys:" || $line_prev =~ "<B>Ethernet:" || $line_prev =~ "CPU pools:" || $line_prev =~ "CPU pool:" || $line_prev =~ "System overview:" || $line_prev =~ "CPU resources:" || $line_prev =~ "LPAR config:" || $line_prev =~ "LPAR profiles:" || $line_prev =~ "CPU resources:" || $line_prev =~ "CPU totally:" || $line_prev =~ "Memory resources " || $line_prev =~ "Memory:" || $line_prev =~ "Firmware:" ) {
        $count = 1;
      }
      if ( $line_prev =~ "CPU pools:" ) {
        $count      = 2;
        $count_prof = 1;
      }
    }

    if ( $line =~ "Memory - AMS:" || $line =~ "Memory - AMS - paging:" || $line =~ "Virtual OptiConnec:" || $line =~ "Virtual slots per lpar:" || $line =~ "Physical IO per io pool level sys:" || $line =~ "<B>Ethernet:" || $line =~ "CPU pools:" || $line =~ "CPU pool:" || $line =~ "System overview:" || $line =~ "CPU resources:" || $line =~ "LPAR config:" || $line =~ "LPAR profiles:" || $line =~ "CPU resources:" || $line =~ "CPU totally:" || $line =~ "Memory resources " || $line =~ "Memory:" || $line =~ "Firmware:" ) {
      $count = 1;
      print FHW "$line\n";
      next;
    }

    # Formating output
    if ( $count > 0 ) {
      my @list      = split( /,/, $line );
      my $comma     = 0;
      my $enter     = 0;
      my $end_comma = 0;
      foreach my $item (@list) {
        chomp($item);
        my $last = substr( $item, 1, 1 );
        if ( ( $item =~ "=" ) && ( $item !~ m/^"/ ) && ( $item !~ m/"$/ ) ) {
          ( my $left_c, my $right_c ) = split( /=/, $item );
          my $result = "";
          if ( ( $count == 2 ) && ( $left_c =~ m/^name=/ ) ) {
            $result = sprintf( "%-36s = </PRE><B>%s</B><PRE>\n", $left_c, $right_c );
          }
          else {
            $result = sprintf( "%-36s = %s\n", $left_c, $right_c );
          }
          if ( $result =~ m/"$/ ) {
            $comma = 0;
            $enter = 1;
          }
          $result =~ s/=/ /g;
          if ( $enter == 1 ) {
            $enter = 0;
            print FHW "$result";
          }
          else {
            print FHW "$result";
          }
          next;
        }
        else {
          if ( ( $comma == 0 ) && ( $item =~ "^\"" ) ) {
            if ( $item =~ "^\"" ) {
              $comma = 1;
            }
            if ( $item =~ "=" ) {
              ( my $left_c, my $right_c ) = split( /=/, $item );
              my $result = sprintf( "%-36s = %s", $left_c, $right_c );
              if ( $result =~ m/"$/ ) {
                $comma = 0;
                $enter = 1;
              }
              $result =~ s/^"//g;
              $result =~ s/"$//g;
              $result =~ s/ =/   /g;
              $result =~ s/=/ /g;
              if ( $enter == 1 ) {
                $enter = 0;
                print FHW "$result\n";
              }
              else {
                print FHW "$result";
              }
              next;
            }
            else {
              my $result = sprintf( "%-36s", $item );
              if ( $result =~ m/"$/ ) {
                $comma = 0;
                $enter = 1;
              }
              $result =~ s/^"//g;
              $result =~ s/"$//g;
              $result =~ s/ =/  =/g;
              if ( $enter == 1 ) {
                $enter = 0;
                print FHW "$result\n";
              }
              else {
                print FHW "$result";
              }
              next;
            }
          }
          else {
            if ( ( $comma == 1 ) && ( ( $item !~ m/^"/ ) || ( $item =~ m/""$/ ) || ( $item =~ m/""""$/ ) ) && ( $item !~ m/=/ ) ) {
              if ( $item =~ m/"$/ ) {
                $comma = 0;
                $enter = 1;
              }
              while ( $item =~ m/^"/ ) {
                $item =~ s/^"//g;
              }
              while ( $item =~ m/"$/ ) {
                $item =~ s/"$//g;
              }
              $item =~ s/ =/  =/g;
              if ( $enter == 1 ) {
                $enter = 0;
                print FHW "\n                                       $item\n";
              }
              else {
                print FHW "\n                                       $item";
              }
              next;
            }
            else {
              if ( ( $comma == 1 ) && ( $item =~ m/^"/ ) ) {
                if ( ( $item =~ m/^""/ ) || ( $item =~ m/^""""/ ) ) {
                  if ( $item =~ m/"$/ ) {
                    $comma = 0;
                    $enter = 1;
                  }
                  $item =~ s/=/ /g;
                  if ( $enter == 1 ) {
                    $enter = 0;
                    print FHW "$item\n";
                  }
                  else {
                    print FHW "$item";
                  }
                  next;
                }
                ( my $left_c, my $right_c ) = split( /=/, $item );
                my $result = sprintf( "\n%-36s = %s", $left_c, $right_c );
                if ( $result =~ m/"$/ ) {
                  $comma = 0;
                  $enter = 1;
                }
                $result =~ s/^"//g;
                $result =~ s/"$//g;
                $result =~ s/ =/   /g;
                $result =~ s/=/ /g;
                if ( $enter == 1 ) {
                  $enter = 0;
                  print FHW "$result\n";
                }
                else {
                  print FHW "$result";
                }
                next;
              }
              else {
                if ( $item =~ m/"$/ ) {
                  $comma = 0;
                  $enter = 1;
                }
                $item =~ s/^"//g;
                $item =~ s/"$//g;
                $item =~ s/ =/   /g;
                $item =~ s/=/ /g;
                if ( $enter == 1 ) {
                  $enter = 0;
                  print FHW "$item\n";
                }
                else {
                  print FHW "$item";
                }
                print FHW "$item\n";
                next;
              }
            }
          }
          if ( $item =~ m/"$/ ) {
            $comma = 0;
            $enter = 1;
            $item =~ s/^"//g;
            $item =~ s/"$//g;
            $item =~ s/ =/   /g;
            $item =~ s/=/ /g;
            if ( $enter == 1 ) {
              $enter = 0;
              print FHW "$item\n";
            }
            else {
              print FHW "$item";
            }
            next;
          }
        }
      }
      if ( $comma == 1 ) {
        print FHW "\n";
      }
      if ( $count != 2 ) {
        print FHW "\n";
      }
      if ( $count == 2 ) {
        next;
      }
      $count = 0;
    }
    else {
      #$line =~ s/,/ /g;
      print FHW "$line\n";
    }
  }
  print FHW "\n</PRE><A HREF=\"http://www.lpar2rrd.com\">Created by LPAR2RRD $version</A><PRE>\n";
  print FHW "$date\n";
  close(FHW);
  close(FHR);
  unlink("$out_file_tmp") || error( " Cannot rm $out_file_tmp : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  return 1;
}

sub save_cpu_cfg_global {
  my $managedname = shift;
  my $time        = shift;
  my $upgrade     = shift;
  my $UUID_SERVER = shift;
  my $cpu_cfg     = "$wrkdir/$managedname/$host/cpu.html";
  my $mem_cfg     = "$wrkdir/$managedname/$host/mem.html";
  my $lpm_excl    = "$wrkdir/$managedname/$host/lpm-exclude.txt";
  my $act_time    = time();
  my @results     = "";
  print "HMC LPARS 1\n";

  if ( !-d "$wrkdir/$managedname/$host" ) {
    error("$wrkdir/$managedname/$host does not exist");
    return 0;
  }
  print "HMC LPARS 2\n";

  # do not update chart every run
  if ( -f "$cpu_cfg" && $upgrade == 0 ) {
    my $png_time = ( stat("$cpu_cfg") )[9];
    ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
    ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($png_time);
    if ( $aday == $png_day ) {
      print "HMC LPARS KO: $cpu_cfg,$upgrade,$png_time\n";

      #      return 0;
    }
    else {
      print "cfg cpu refresh: $aday != $png_day\n" if $DEBUG;
    }
  }
  print "HMC LPARS 3\n";

  print "fetching HMC   : $host:$managedname CPU/MEM global config\n" if $DEBUG;
  if ( -f "$mem_cfg" ) {

    # backup old one, crate a new one a do diff, if there is any then --> install_html.sh
    if ( -f "$mem_cfg-old" ) {
      unlink("$mem_cfg-old");
    }
    rename( "$mem_cfg", "$mem_cfg-old" );
  }
  print "HMC LPARS 4\n";

  if ( -f "$cpu_cfg" ) {

    # backup old one, crate a new one a do diff, if there is any then --> install_html.sh
    if ( -f "$cpu_cfg-old" ) {
      unlink("$cpu_cfg-old");
    }
    rename( "$cpu_cfg", "$cpu_cfg-old" );
  }

  if ( $lpm == 1 ) {

    # creates file with list of VIO servers, they have to be excluded from LPM
    open( FHW, "> $lpm_excl" ) || error( " Cannot open  $lpm_excl: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @results = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lssyscfg -m \\"$managedname\\" -r lpar -F name,lpar_env"`;
    foreach my $lpm_line (@results) {
      ( my $lpar_name, my $lpar_env ) = split( /,/, $lpm_line );
      if ( !$lpar_env eq '' && $lpar_env =~ m/vioserver/ ) {
        print FHW "$lpar_name\n";
      }
    }
    close(FHW);
  }

  my $cpu_pool_err = 0;
  my @cli_proc_conf;
  my @cli_mem_conf;    # = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r mem --level lpar"`;

  my @cli_conf;
  if ( $IVM == 1 ) {

    # does not support curr_shared_proc_pool_name
    $cpu_pool_err  = 1;
    @results       = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r proc --level lpar -F lpar_name,curr_proc_mode,curr_min_proc_units,curr_proc_units,curr_max_proc_units,curr_procs,curr_sharing_mode,curr_uncap_weight"`;
    @cli_proc_conf = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r proc --level lpar"`;
    @cli_mem_conf  = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r mem --level lpar"`;
  }
  else {
    @results       = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r proc --level lpar -F lpar_name,curr_proc_mode,curr_min_proc_units,curr_proc_units,curr_max_proc_units,curr_min_procs,curr_procs,curr_max_procs,curr_sharing_mode,curr_uncap_weight,curr_shared_proc_pool_name"`;
    @cli_proc_conf = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r proc --level lpar"`;
    @cli_mem_conf  = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r mem --level lpar"`;
  }

  if ( $results[0] =~ "HSCL" || $results[0] =~ "VIOSE0" ) {

    # something wrong with the input data
    error("$host:$managedname : $results[0] : lshwres -m $managedname -r proc --level lpar -F lpar_name,cur ...");
    return 1;
  }
  my $res;
  if ( $results[0] =~ /An invalid attribute was entered/ ) {

    # POWER5 do not support curr_shared_proc_pool_name
    #print "ERROR with $managedname : curr_shared_proc_pool_name is not valid for this frame.\n";
    $cpu_pool_err  = 1;
    @results       = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r proc --level lpar -F lpar_name,curr_proc_mode,curr_min_proc_units,curr_proc_units,curr_max_proc_units,curr_procs,curr_sharing_mode,curr_uncap_weight"`;
    @cli_proc_conf = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r proc --level lpar"`;
    @cli_mem_conf  = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r mem --level lpar"`;

    #print "DB_TEST : $SSH $hmc_user\@$host \" LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \"$managedname\" -r proc --level lpar -F lpar_name,curr_proc_mode,curr_min_proc_units,curr_proc_units,curr_max_proc_units,curr_procs,curr_sharing_mode,curr_uncap_weight\n";

  }
  my $out_cli_conf;
  push @cli_conf, @cli_proc_conf;
  push @cli_conf, @cli_mem_conf;
  foreach my $lpar_line (@cli_conf) {
    my $lpar_line_b = $lpar_line;
    my ( $lpar_name, $shared, undef, undef, undef, undef, undef, undef, $mode, $weight, $pool_name ) = split( ",", $lpar_line );
    my @line_metrics_values = split( ",", $lpar_line );
    $lpar_name = $line_metrics_values[0];
    $lpar_name =~ s/^lpar_name=//g;
    foreach my $metric_value (@line_metrics_values) {
      my ( $metric, $value ) = split( "=", $metric_value );
      $out_cli_conf->{$lpar_name}{$metric} = $value;
    }

    #vios-770,shared,0.1,0.5,2.0,1,2,4,uncap,128,DefaultPool
    #lpar_name,curr_proc_mode,curr_min_proc_units,curr_proc_units,curr_max_proc_units,curr_min_procs,curr_procs,curr_max_procs,curr_sharing_mode,curr_uncap_weight,curr_shared_proc_pool_name
    my @vals = split( ",", $lpar_line_b );

    $pool_name =~ s/\n//g if ( defined $pool_name && $pool_name ne "" );
    my $UUID_LPAR = PowerDataWrapper::md5_string("$UUID_SERVER $lpar_name");
    $out_cli_conf->{$lpar_name}{SharedProcessorPoolName} = $pool_name && $pool_name ne "null";
    $out_cli_conf->{$lpar_name}{UUID}                    = $UUID_LPAR;

    #    $out_cli_conf->{$lpar_name}{PartitionName}=$vals[0] if defined $vals[0] && $vals[0] ne "null";
    #    $out_cli_conf->{$lpar_name}{CurrentProcessorMode}=$vals[1] if defined $vals[1] && $vals[1] ne "null";
    #    $out_cli_conf->{$lpar_name}{CurrentMinimumProcessingUnits}=$vals[2] if defined $vals[2] && $vals[2] ne "null";
    #    $out_cli_conf->{$lpar_name}{CurrentProcessingUnits}=$vals[3] if defined $vals[3] && $vals[3] ne "null";
    #    $out_cli_conf->{$lpar_name}{CurrentMaximumProcessingUnits}=$vals[4] if defined $vals[4] && $vals[4] ne "null";
    #    $out_cli_conf->{$lpar_name}{CurrentMinimumProcessors}=$vals[5] if defined $vals[5] && $vals[5] ne "null";
    #    $out_cli_conf->{$lpar_name}{CurrentProcessors}=$vals[6] if defined $vals[6] && $vals[6] ne "null";
    #    $out_cli_conf->{$lpar_name}{CurrentMaximumProcessingUnits}=$vals[7] if defined $vals[7] && $vals[7] ne "null";
    #    $out_cli_conf->{$lpar_name}{CurrentSharingMode}=$vals[8] if defined $vals[8] && $vals[8] ne "null";
    #    $out_cli_conf->{$lpar_name}{CurrentUncappedWeight}=$vals[9] if defined $vals[9] && $vals[9] ne "null";
    #$out_cli_conf->{$lpar_name}{SharedProcessorPoolNAME}=$vals[10] if defined $vals[10] && $vals[10] !~ m/null/;
    #print "TESTa : -$vals[10]- \n";
    #Volume ids for Xormon, tab VOLUMES in lpar's site
    my $lpar_dir_path     = PowerDataWrapper::get_filepath_rrd_vm( $lpar_name, $managedname, "" );
    my $id_txt_file       = "$lpar_dir_path/id.txt";
    my $hostname_txt_file = "$lpar_dir_path/hostname.txt";
    print "ID_TXT LPAR : $id_txt_file\n";
    if ( -e $id_txt_file ) {
      open( my $id_txt, "<", $id_txt_file ) || warn "Cannot open file $id_txt_file at " . __FILE__ . ":" . __LINE__ . "\n";
      my @lines = <$id_txt>;
      close($id_txt);
      my @types      = ();
      my @uuids      = ();
      my @labels     = ();
      my @capacities = ();
      foreach my $line (@lines) {
        chomp($line);
        my @arr = split( ":", $line );
        if ( defined $arr[0] && $arr[0] ne '' ) { push( @types,      $arr[0] ); }
        if ( defined $arr[1] && $arr[1] ne '' ) { push( @uuids,      lc $arr[1] ); }
        if ( defined $arr[2] && $arr[2] ne '' ) { push( @labels,     $arr[2] ); }
        if ( defined $arr[3] && $arr[3] ne '' ) { push( @capacities, $arr[3] ); }
      }
      $out_cli_conf->{$lpar_name}{disk_types}      = join( " ", @types );
      $out_cli_conf->{$lpar_name}{disk_uids}       = join( " ", @uuids );
      $out_cli_conf->{$lpar_name}{disk_labels}     = join( " ", @labels );
      $out_cli_conf->{$lpar_name}{disk_capacities} = join( " ", @capacities );
    }
    if ( -e $hostname_txt_file ) {
      open( my $hostname_txt, "<", $hostname_txt_file ) || warn "Cannot open file $hostname_txt_file at " . __FILE__ . ":" . __LINE__ . "\n";
      my $hostname = readline($hostname_txt);
      close($hostname_txt);
      $out_cli_conf->{$lpar_name}{hostname} = $hostname;
    }
  }
  my $file_path = "$basedir/tmp/restapi/HMC_LPARS_$managedname\_conf.json";
  Xorux_lib::write_json( $file_path, $out_cli_conf ) if ( defined $out_cli_conf && Xorux_lib::file_time_diff($file_path) > 3600 || Xorux_lib::file_time_diff($file_path) == 0 );
  my $report = FormatResults(@results);
  open( FHW, "> $cpu_cfg" ) || error( " Cannot open  $cpu_cfg: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  #print FHW "<BR><CENTER><TABLE border=\"0\" cellpadding=\"0\" cellspacing=\"0\">\n";
  print FHW "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">\n";
  if ( $cpu_pool_err == 1 ) {
    print FHW "<thead><TR> <TH class=\"sortable\" valign=\"center\">LPAR&nbsp;&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Mode&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Min&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Assigned&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Max&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Virtual&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Sharing&nbsp;&nbsp;&nbsp;<br>mode</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Uncap&nbsp;&nbsp;&nbsp;<br>weight</TH><TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;OS&nbsp;&nbsp;&nbsp;</TH></TR>\n</thead><tbody>\n";
  }
  else {
    print FHW "<thead><TR> <TH class=\"sortable\" valign=\"center\">LPAR&nbsp;&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Mode&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Min&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Assigned&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Max&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;min VP&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Virtual&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;max VP&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Sharing&nbsp;&nbsp;&nbsp;<br>mode</TH> <TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Uncap&nbsp;&nbsp;&nbsp;<br>weight</TH><TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;Pool&nbsp;&nbsp;&nbsp;</TH><TH align=\"center\" class=\"sortable\" valign=\"center\">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;OS&nbsp;&nbsp;&nbsp;</TH></TR>\n</thead><tbody>\n";
  }

  # Check whether AIX or another OS due to "grep -p" which supports only AIX
  my $uname = `uname -a`;
  chomp($uname);
  my $aix = 0;
  my @u_a = split( / /, $uname );
  foreach my $u (@u_a) {
    if ( $u =~ "AIX" ) {
      $aix = 1;
    }
  }

  # Loop for adding OS
  foreach my $line ( split( /\n/, $report ) ) {
    my $os   = "";
    my $lpar = "";
    chomp($line);
    $line =~ s/0.0.0.0.0.0//g;
    if ( -f "$basedir/data/$managedname/$host/config.cfg" ) {
      ( my $trash, $lpar ) = split( /<TD/, $line );
      $lpar =~ s/<B>//;
      $lpar =~ s/<\/B><\/TD> //;
      $lpar =~ s/^>//;
      if ( $aix == 1 ) {

        # AIX with grep -p support
        $os = `egrep -p \"^name\.\*    $lpar\" $basedir/data/"$managedname"/"$host"/config.cfg|egrep \"^os_vers\"|head -1`;
      }
      else {
        #        $os = `egrep \"^name\.\*    $lpar\" $basedir/data/"$managedname"/"$host"/config.cfg|egrep \"^os_vers\"|head -1`;
        $os = `grep -A 30 "^name.*    $lpar" $basedir/data/"$managedname"/"$host"/config.cfg | grep "os_version"|head -1`;
      }
      chomp($os);
      $os =~ s/^os_version//g;
      $os =~ s/  //g;
      $os =~ s/ /&nbsp;/g;
    }
    else {
      $os = "";
    }
    $os =~ s/Unknown//;

    #print "$basedir/data/$managedname/$host/config.cfg -- $line ++++  $lpar $os $aix -- \n";
    $line =~ s/<\/TR>//;
    print FHW "$line <TD align=\"center\" nowrap>&nbsp;$os&nbsp;</TD></TR>\n";
  }
  print FHW "</tbody></TABLE></CENTER><BR><BR>\n";
  close(FHW);

  # Memory
  @results = `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r mem --level lpar -F lpar_name,curr_min_mem,curr_mem,curr_max_mem,run_mem"`;
  $report  = FormatResults(@results);
  open( FHW, "> $mem_cfg" ) || error( " Cannot open  $mem_cfg: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FHW "<BR><CENTER><TABLE class=\"tabconfig tablesorter\">\n";
  print FHW "<thead><TR> <TH class=\"sortable\">LPAR&nbsp;&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\">&nbsp;&nbsp;&nbsp;Min&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\">&nbsp;&nbsp;&nbsp;Assigned&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\">&nbsp;&nbsp;&nbsp;Max&nbsp;&nbsp;&nbsp;</TH> <TH align=\"center\" class=\"sortable\">&nbsp;&nbsp;&nbsp;Running&nbsp;&nbsp;&nbsp;</TH></TR>\n</thead><tbody>\n";
  print FHW "$report\n";
  print FHW "</tbody></TABLE></CENTER><br>(all in MB)<BR>\n";
  close(FHW);

  # if any change then  run install_html.sh
  if ( -f "$mem_cfg-old" ) {
    if ( compare( "$mem_cfg", "$mem_cfg-old" ) != 0 ) {
      LoadDataModule::touch("$mem_cfg-old");
    }
  }
  else {
    LoadDataModule::touch("$mem_cfg-old 1");
  }

  if ( -f "$cpu_cfg-old" ) {
    if ( compare( "$cpu_cfg", "$cpu_cfg-old" ) != 0 ) {
      LoadDataModule::touch("$cpu_cfg-old");
    }
  }
  else {
    LoadDataModule::touch("$cpu_cfg-old 1");
  }

}

sub FormatResults {
  my @results_unsort = @_;
  my $line           = "";
  my $formated       = "";
  my @items1         = "";
  my $item           = "";

  my @results = sort { lc $a cmp lc $b } @results_unsort;
  foreach $line (@results) {
    chomp $line;
    @items1   = split /,/, $line;
    $formated = $formated . "<TR>";
    my $col = 0;
    foreach $item (@items1) {
      if ( $col == 0 ) {
        $formated = sprintf( "%s <TD><B>%s</B></TD>", $formated, $item );
      }
      else {
        $formated = sprintf( "%s <TD align=\"center\">%s</TD>", $formated, $item );
      }
      $col++;
    }
    $formated = $formated . "</TR>\n";
  }
  return $formated;
}

# function saves CPU config of each lpar, this is then shown in the main panel of each lpar
# it save also lpar cfg for all lpars into lpar.cfg
sub save_cpu_cfg {
  my $managedname    = shift;
  my $time           = shift;
  my $upgrade        = shift;
  my $cfg            = "$wrkdir/$managedname/$host/cpu.cfg";
  my $cfg_lpar       = "$wrkdir/$managedname/$host/lpar.cfg";
  my $cfg_shell      = $cfg;
  my $cfg_lpar_shell = $cfg_lpar;
  $cfg_shell      =~ s/ /\\ /g;
  $cfg_lpar_shell =~ s/ /\\ /g;
  my $act_time = time();
  my $serial   = "";

  if ($restapi) {
    print "Skip save_cpu_cfg (use rest api instead)\n";
    return 0;
  }

  if ( !-d "$wrkdir/$managedname/$host" ) {
    error("$wrkdir/$managedname/$host does not exist");
    return 0;
  }

  # --> IT must not be here!!! lpar2rrd needs to have actuall data every run!!!
  # do not update chart every run
  #if ( -f "$cfg" ) {
  #  my $png_time = (stat("$cfg"))[9];
  #  if ( ($act_time - $png_time) < $CFG_REFRESH ) {
  #    #print "creating graph : $host:$managedname:$type:$adapter_id:$port no upd\n" if $DEBUG ;
  #    return 0;
  #  }
  #}

  my @lparlist = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lssyscfg -m \\"$managedname\\" -r lpar -F name,state,logical_serial_num" 2>&1`;
  if ( $lparlist[0] =~ /Standby or Operating state/ ) {
    error("$host:$managedname : $lparlist[0] : server looks like switched off");
    return 2;
  }

  if ( $lparlist[0] =~ /HSCL/ || $lparlist[0] =~ /VIOSE0/ ) {
    error("$host:$managedname : $lparlist[0] : lssyscfg -m $managedname  -r lpar -F name,state");
    return 1;
  }

  print "fetching HMC   : $host:$managedname CPU lpar config\n" if $DEBUG;
  `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r proc --level lpar" > $cfg_shell`;
  `$SSH $hmc_user\@$host " LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lssyscfg -m \\"$managedname\\" -r lpar " > $cfg_lpar_shell`;

  open( FHR, "< $cfg" ) || error( " Cannot open  $cfg: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  while ( my $line = <FHR> ) {
    chomp($line);
    if ( $line =~ /Standby or Operating state/ ) {
      error("$host:$managedname : $line : server looks like switched off");
      return 2;
    }
    if ( $line =~ /HSCL/ || $line =~ /VIOSE0/ ) {
      error("$host:$managedname : $line : lshwres -m $managedname -r proc --level lpar");
      return 1;
    }

    if ( $line =~ "lpar_name=" ) {
      my @list  = split( /,/, $line );
      my $first = 0;
      my $l     = "";
      my $state = "";
      my $lpar  = "";
      foreach my $item (@list) {
        chomp($item);
        $first++;
        if ( $first == 1 ) {
          ( my $name, $lpar ) = split( /=/, $item );
          foreach $l (@lparlist) {
            ( my $name, my $state_a, my $serial_new ) = split( /,/, $l );
            if ( $name eq "$lpar" ) {
              $state  = $state_a;
              $serial = $serial_new;
              last;
            }
          }

          #print "$lpar $state\n";
          $lpar =~ s/\//\&\&1/g;
          open( FHW, "> $cfg-$lpar" ) || error( " Cannot open $cfg-$lpar: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          print FHW "<B>Current CPU configuration:</B><TABLE class=\"tabconfig\">\n";
          my $result = sprintf( "<TR><TD><font size=\"-1\">state</font></TD><TD><font size=\"-1\">&nbsp;&nbsp;%s</font></TD></TR>\n", $state );
          print FHW "$result";
          chomp($serial);
          $result = sprintf( "<TR><TD><font size=\"-1\">logical_serial_num</font></TD><TD><font size=\"-1\">%s</font></TD></TR>\n", $serial );
          print FHW "$result";
          next;
        }
        if ( $item =~ m/^curr_/ && ( $item !~ "_max" ) && ( $item !~ "_min" ) ) {
          ( my $left_c, my $right_c ) = split( /=/, $item );

          my $result = sprintf( "<TR><TD><font size=\"-1\">%s</font></TD><TD><font size=\"-1\">&nbsp;&nbsp;%s</font></TD></TR>\n", $left_c, $right_c );
          if ( $left_c =~ m/curr_shared_proc_pool_name/ ) {

            # place a direct link into CPU pool
            $right_c = pool_translate( $wrkdir, $host, $managedname, $right_c );
            $result  = sprintf( "<TR><TD><font size=\"-1\">%s</font></TD><TD><font size=\"-1\">%s</font></TD></TR>\n", $left_c, $right_c );
          }
          print FHW "$result";
        }
      }

      #print FHW "<TR><TD><font size=\"-1\">$time</font></TD></TR></TABLE>\n<BR>\n";
      # print SMT details if exist
      my $smt = get_smt_details( $wrkdir, $managedname, $lpar );
      if ( $smt != -1 ) {
        print FHW "<TR><TD><font size=\"-1\">SMT</font></TD><TD><font size=\"-1\">&nbsp;&nbsp;$smt</font></TD></TR>\n";
      }
      print FHW "</TABLE>\n<font size=\"-1\">HMC time : $time</font><BR><BR>\n";
      close(FHW);
    }
  }
  close(FHR);
  return 0;
}

sub sys_change {
  my $managedname = shift;
  my $date        = shift;

  #my $cmd = "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r all -s h  -m \"$managedname\" --filter \"event_types=config_change,state_change,utility_cod_proc_usage\" -n $SYS_CHANGE";

  if ( !-d "$wrkdir/$managedname/$host" ) {
    error("$wrkdir/$managedname/$host does not exist");
    return 0;
  }
  my $gui_out    = "$wrkdir/$managedname/$host/gui-change-state.txt";
  my $head_state = "<CENTER><B>Changes in LPAR state for last $SYS_CHANGE days</B> <font size=-1>(Updated on: $date)</font><br>\
	<TABLE class=\"tabconfig tablesorter\"> \
	<thead><tr><th align=\"center\" class=\"sortable\">&nbsp;&nbsp;&nbsp;Time&nbsp;&nbsp;&nbsp;</th><th align=\"center\" class=\"sortable\">&nbsp;&nbsp;&nbsp;State&nbsp;&nbsp;&nbsp;</th><th align=\"center\" class=\"sortable\">&nbsp;&nbsp;&nbsp;LPAR&nbsp;&nbsp;&nbsp;</th><th align=\"center\" class=\"sortable\">&nbsp;&nbsp;&nbsp;ID&nbsp;&nbsp;&nbsp;</th></tr></thead><tbody>\n";

  print "sys change     : $host:$managedname:$SYS_CHANGE\n" if $DEBUG;
  my @state = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r all -s h  -m \\"$managedname\\" --filter \"event_types=state_change\" -d $SYS_CHANGE"`;

  open( FHLG, "> $gui_out" ) || error( " Can't open $gui_out : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FHLG "$head_state\n";

  my $line_out = "";
  foreach my $line (@state) {

    #time=04/03/2014 13:26:01,event_type=state_change,resource_type=lpar,primary_state=Started,detailed_state=None,lpar_name=VIOS,lpar_id=1
    #time=05/20/2014 12:57:32,event_type=state_change,resource_type=lpar,state=Running,lpar_name=BSRV21LPAR3,lpar_id=3

    chomp($line);
    if ( $line eq '' || $line !~ m/,/ || $line !~ m/event_type=state_change/ ) {
      next;
    }
    $line =~ s/event_type=state_change,//;
    $line =~ s/,detailed_state=.*,lpar_name=/,lpar_name=/;    # to filter SDMC detailed_state=None
                                                              #$line =~ s/,,/,/g;
                                                              #print "007 $line\n";
                                                              #time=06/29/2014 22:45:24,resource_type=lpar,primary_state=Started,lpar_id=16
    if ( $line =~ m/resource_type=lpar/ ) {
      ( my $time, my $res, my $stat, my $lpar, my $id ) = split( /,/, $line );

      my $time_data = "";
      if ( defined $time && !$time eq '' ) {
        ( my $tr, $time_data ) = split( /=/, $time );
      }

      my $stat_data = "";
      if ( defined $stat && !$stat eq '' ) {
        ( my $tr, $stat_data ) = split( /=/, $stat );
      }

      my $lpar_data = "";
      if ( defined $lpar && !$lpar eq '' ) {
        ( my $tr, $lpar_data ) = split( /=/, $lpar );
      }

      my $id_data = "";
      if ( defined $id && !$id eq '' ) {
        ( my $tr, $id_data ) = split( /=/, $id );
      }

      #print "008 <tr><td>$time_data</td><td>$res_data</td><td>$stat_data</td><td>$lpar_data</td><td>$id_data</td></tr>\n";
      $line_out .= "<tr><td align=\"center\" nowrap>$time_data</td><td align=\"center\" nowrap>$stat_data</td><td align=\"center\" nowrap>$lpar_data</td><td align=\"center\" nowrap>$id_data</td></tr>\n";
    }

    #if ( $line =~ m/resource_type=sys/ ) {
    # time=03/12/2014 13:54:50,resource_type=sys,primary_state=Started,detailed_state=None
    #}
  }

  print FHLG "$line_out</tbody></centre></table>\n";
  close(FHLG);

  my $gui_out1        = "$wrkdir/$managedname/$host/gui-change-config.txt";
  my $head_config_gui = "<CENTER><B>Changes in LPAR configuration for last $SYS_CHANGE days</B> <font size=-1>(Updated on: $date)</font><br>\
	<TABLE class=\"tabconfig tablesorter\">";
  my @config = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lslparutil -r all -s h  -m \\"$managedname\\" --filter \"event_types=config_change\" -d $SYS_CHANGE"`;

  open( FHLG, "> $gui_out1" ) || error( " Can't open $gui_out1 : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FHLG "$head_config_gui\n";

  $line_out = "";
  my $line_out_head = "<tr>";
  my $head          = 0;
  foreach my $line (@config) {
    chomp($line);
    $line =~ s/event_type=config_change//;
    if ( $line eq '' || $line !~ m/,/ || $line !~ m/resource_type=lpar/ ) {
      next;
    }
    my @line_items = split( /,/, $line );
    $line_out .= "<tr>";
    my $head_ok = 0;
    foreach my $item (@line_items) {
      if ( $item eq '' || $item =~ m/resource_type=/ ) {
        next;
      }
      if ( $head == 0 ) {
        ( my $item_head, my $tr1 ) = split( /=/, $item );
        $line_out_head .= "<th align=\"center\" class=\"sortable\">$item_head&nbsp;&nbsp;&nbsp;</th>";
        $head_ok = 1;
      }
      ( my $tr, my $item_data ) = split( /=/, $item );
      if ( $item_data eq '' ) {
        next;
      }
      if ( $tr =~ m/lpar_name/ ) {
        $line_out .= "<td nowrap>&nbsp;&nbsp;$item_data</td>";
      }
      else {
        $line_out .= "<td align=\"center\" nowrap>$item_data</td>";
      }
    }
    if ( $head_ok == 1 ) {
      $head = 1;
    }
    $line_out .= "</tr>\n";
  }
  $line_out_head .= "</tr>";
  print FHLG "<thead>$line_out_head\n</thead><tbody>\n$line_out\n</tbody>\n";

  print FHLG "</table></centre>\n";
  close(FHLG);
}

sub cfg_config_change {

  # If any change in lpar2rrd.cfg  then must be run install-html.sh
  my $cfg_update = "$tmpdir/cfg_update";

  if ( -f "$cfg_update" ) {
    my $last_line = "";
    open( FHLT, "< $cfg_update" ) || error( " Can't open $cfg_update: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line (<FHLT>) {
      $last_line = $line;
    }
    close(FHLT);
    my $png_time = ( stat("$basedir/etc/lpar2rrd.cfg") )[9];
    if ( $last_line < $png_time ) {
      LoadDataModule::touch("cfg_config_change: $last_line < $png_time");
      open( FHLT, "> $cfg_update" ) || error( " Can't open $cfg_update: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      my $act_time = time();
      print FHLT "$act_time";
      close(FHLT);
    }
  }
  else {
    LoadDataModule::touch("cfg_config_change: $cfg_update");
    my $png_time = ( stat("$basedir/etc/lpar2rrd.cfg") )[9];
    open( FHLT, "> $cfg_update" ) || error( " Can't open $cfg_update: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my $act_time = time();
    print FHLT "$act_time";
    close(FHLT);

    #print "$cfg_update $basedir/etc/lpar2rrd.cfg $png_time\n";
  }

  return 1;

}

# create server/lpar cfg high level page

sub get_cfg_server {
  my $new_gui              = shift;
  my $managedname          = "";
  my $model                = "";
  my $serial               = "";
  my $managedname_exl      = "";
  my $managed_ok           = "";
  my @m_excl               = "";
  my @mm                   = "";                                      #array of all servers and lpars
  my @mm_one               = "";                                      #array of all servers and lpars for sum page of processed server (there are other paths then in mm_sum)
  my @mm_sum               = "";                                      #array of all servers and lpars for sum page
  my $count_s              = "";
  my $lpar_c               = 0;
  my $server_c             = 0;
  my $tds                  = "<TD";
  my $td                   = "<TD></TD>";
  my $tde                  = "</TD>";
  my $tr_start             = "<TR>";
  my $tr_stop              = "</TR>";
  my $td_col_run           = " bgcolor=\"#80FF80\">";
  my $td_col_donot_run     = " bgcolor=\"#FF8080\">";
  my $td_col_pool          = " bgcolor=\"#FFFF80\">";
  my $cfg_high_html_rel    = $new_gui . "config-high.html";
  my $cfg_high_html        = "$webdir/$host/$cfg_high_html_rel";
  my $cfg_sum_html_rel     = $new_gui . "config-high-sum.html";
  my $cfg_sum_html_rel_tmp = "$cfg_sum_html_rel-tmp";
  my $cfg_sum_html         = "$webdir/$host/$cfg_sum_html_rel_tmp";
  my $cfg_sum_html_full    = "$webdir/$host/$cfg_sum_html_rel";
  my $act_time             = time();
  my @proc_pools           = "";
  my $cvs_lpar             = "$host-lpar-config.csv";
  my $cvs_srv              = "$host-server-config.csv";
  my $cvs                  = "$webdir/$host/$cvs_lpar";
  my $cvs_tmp              = "$webdir/$host/$cvs_lpar-tmp";
  my $cvs_server           = "$webdir/$host/$cvs_srv";
  my $managedname_url      = "";

  if ($restapi) {
    print "Skip get_cfg_server sub. use rest api\n";
    return 0;
  }

  # do not update cfg file if less than 1 day
  if ( -f "$cfg_high_html" ) {
    my $file_time = ( stat("$cfg_high_html") )[9];
    if ( ( $act_time - $file_time ) < $UPDATE_DAILY ) {
      return 0;
    }
  }

  print "CFG highlevel  : $host \n" if $DEBUG;

  if ( !-d "$webdir/$host" ) {
    print "mkdir          : $host $webdir/$host\n" if $DEBUG;
    LoadDataModule::touch("$webdir/$host");
    mkdir( "$webdir/$host", 0755 ) || error( " Cannot mkdir $webdir/$host: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  open( FHR, "> $cvs_server" ) || error( " Can't open $cvs_srv" . __FILE__ . ":" . __LINE__ ) && return 0;                                                                                                                         # detailed cfg in CSV format
  print FHR "HMC;server;type_model;serial;configurable_sys_proc_units;configurable_sys_mem[MB];curr_avail_sys_mem[MB];CPU pool name;reserved CPU units;maximum CPU units;installed_sys_proc_units;curr_avail_sys_proc_units\n";    # CVS header

  open( FHO, "> $cfg_high_html" )     || error( " Can't open $cfg_high_html" . __FILE__ . ":" . __LINE__ )     && return 0;                                                                                                        # detailed cfg
  open( FHH, "> $cfg_sum_html_full" ) || error( " Can't open $cfg_sum_html_full" . __FILE__ . ":" . __LINE__ ) && return 0;                                                                                                        # Sum cfg, it has different link path then sum bellow
  open( FHS, "> $cfg_sum_html" )      || error( " Can't open $cfg_sum_html" . __FILE__ . ":" . __LINE__ )      && return 0;                                                                                                        # sum cfg, just a table, htm is created in install-html.sh

  #  print FHO "<A HREF=\"gui-config-global.htm\" target=\"sample\">Global</A> / <A HREF=\"".$cfg_sum_html_rel."\">Summary</A> <br><font size=\"-1\"><A HREF=\"$host/$cvs_lpar\" target=\"_blank\">CSV LPAR</A> / <A HREF=\"$host/$cvs_lpar\" target=\"_blank\">CSV Server</A></font>\n";
  #  print FHH "<A HREF=\"gui-config-global.htm\" target=\"sample\">Global</A> / <A HREF=\"".$host."/".$cfg_high_html_rel."\">Detailed</A> <br><font size=\"-1\"><A HREF=\"$host/$cvs_lpar\" target=\"_blank\">CSV LPAR</A>  / <A HREF=\"$host/$cvs_srv\" target=\"_blank\">CSV Server</A></font>\n";

  #  if ($IVM == 0 ) {
  #    print FHO "<center><h3>$host</h3></center>\n";
  #    print FHH "<center><h3>$host</h3></center>\n";
  #  }
  print FHO "<center><TABLE class=\"tabsyscfg\">\n";
  print FHH "<center><TABLE class=\"tabsyscfg\">\n";
  print FHS "<center><TABLE class=\"tabsyscfg\">\n";

  open( FHC, "> $cvs_tmp" ) || error( " Can't open $cvs" . __FILE__ . ":" . __LINE__ ) && return 0;    # detailed cfg in CSV format
  print FHC "HMC;server;lpar_name;curr_shared_proc_pool_name;curr_proc_mode;curr_procs;curr_proc_units;curr_sharing_mode;curr_uncap_weight;lpar_id;default_profile;min_proc_units;desired_proc_units;max_proc_units;curr_min_proc_units;curr_max_proc_units;min_procs;desired_procs;max_procs;curr_min_procs;curr_max_procs;min_mem;desired_mem;max_mem;curr_min_mem;curr_mem;curr_max_mem;state;lpar_env;os_version\n";
  close(FHC);

  # run that 1st time after the midnight!!
  #     --> due to putting avrg lpar load per last day in stats

  # get data for all managed system which are conected to HMC

  foreach my $line (@managednamelist) {
    chomp($line);

    if ( $line !~ ".*,.*,.*" ) {

      # it must look like : PWR6A-9117-MMA-SN103A4B0,9117-MMA,103A4B0, --> exclude banners
      next;
    }
    if ( $line =~ /No results were found/ ) {
      print "$host does not contain any managed system\n" if $DEBUG;
      return 0;
    }
    ( $managedname, $model, $serial ) = split( /,/, $line );

    if ( is_IP($managedname) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    print "managed system : $host:$managedname (type_model*serial : $model*$serial)\n" if $DEBUG;
    $managedname_url = $managedname;
    $managedname_url =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

    #$managedname_url =~ s/([^ A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg; # PH: keep it is it is exactly!!!
    #$managedname_url =~ s/ /+/g;
    #$managedname_url =~ s/\#/%23/g;

    $managed_ok = 1;
    @pool_list  = "";    # clean pool_list for each managed name

    # do not exclude here anything

    my $cfg = "$wrkdir/$managedname/$host/cpu.cfg";
    if ( !-f $cfg ) {
      error("$host:$managedname : does not exist : $cfg");
      next;
    }

    my $cfg_shell = $cfg;
    $cfg_shell =~ s/ /\\ /g;

    # what about IVM/SDMC???
    my @lparlist = "";
    if ( $IVM == 1 ) {
      @lparlist = `$SSH $hmc_user\@$host "lssyscfg -m \\"$managedname\\" -r lpar -F name,state" 2>&1`;
    }
    else {
      @lparlist   = `$SSH $hmc_user\@$host "lssyscfg -r lpar -m \\"$managedname\\" -F name,state" 2>&1`;
      @proc_pools = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -m \\"$managedname\\" -r procpool -F \"name,max_pool_proc_units,curr_reserved_pool_proc_units\"" 2>&1`;
      if ( $proc_pools[0] =~ /HSCL/ || $proc_pools[0] =~ /VIOSE0/ ) {
        $proc_pools[0] = '';
      }
    }

    #if ($lparlist[0] =~ /HSCL/ || $lparlist[0] =~ /VIOSE0/ ) || $lparlist[0] eq '' ) {
    if ( $lparlist[0] =~ /HSCL/ || $lparlist[0] =~ /VIOSE0/ ) {
      $lparlist[0] = '';

      #my $act_time = localtime();
      #error ("$host:$managedname : $lparlist[0]");
      #next;
    }

    # get global CPU and MEM
    my $out_file = "$CONFIG_HISTORY/$managedname/$host/config.cfg";

    my $timestamp_cpucfg    = ( stat("$cfg") )[9];
    my $timestamp_cfg       = ( stat("$out_file") )[9];
    my $actual_unix_time    = time;
    my $last_30_days        = 30 * 86400;                           ### 30 days back
    my $actual_last_30_days = $actual_unix_time - $last_30_days;    ### 30 days back with actual unix time-
    if ( $timestamp_cpucfg && $timestamp_cfg < $actual_last_30_days ) {next}

    my $mcpu           = "n/a";
    my $c_mem          = "n/a";
    my $a_mem          = "n/a";
    my $serial_num     = "n/a";
    my $type_model     = "n/a";
    my $installed_cpu  = "n/a";
    my $curr_avail_cpu = "n/a";

    if ( -f $out_file ) {
      open( FHG, "< $out_file" );
      my @lines_glo = <FHG>;
      foreach my $linel (@lines_glo) {
        chomp($linel);
        if ( $linel =~ "HSCL" || $linel =~ "VIOSE0" ) {
          last;
        }
        if ( $linel =~ m/type_model/ ) {
          $type_model = $linel;
          $type_model =~ s/type_model//;
          $type_model =~ s/ //g;
          $type_model =~ s/<\/td>//g;
          $type_model =~ s/<td>//g;
          next;
        }
        if ( $linel =~ m/serial_num/ ) {
          $serial_num = $linel;
          $serial_num =~ s/serial_num//;
          $serial_num =~ s/ //g;
          $serial_num =~ s/<\/td>//g;
          $serial_num =~ s/<td>//g;
          next;
        }
        if ( $linel =~ m/configurable_sys_proc_units/ ) {
          $mcpu = $linel;
          $mcpu =~ s/configurable_sys_proc_units//;
          $mcpu =~ s/ //g;
          $mcpu =~ s/<\/td>//g;
          $mcpu =~ s/<td>//g;
          next;
        }
        if ( $linel =~ m/configurable_sys_mem/ ) {
          $c_mem = $linel;
          $c_mem =~ s/configurable_sys_mem//;
          $c_mem =~ s/ //g;
          $c_mem =~ s/<\/td>//g;
          $c_mem =~ s/<td>//g;

          # tohle se najak "nechytlo" v CSOB :)
          #if ( $c_mem > 1024  ) { # conversion to GB if >1GB
          #   my $l = int($c_mem/1024 + 0.5);
          #   $c_mem = $l." GB";
          # }
          # else {
          #  $c_mem .= " MB";
          #}
          next;
        }
        if ( $linel =~ m/installed_sys_proc_units/ ) {
          $installed_cpu = $linel;
          $installed_cpu =~ s/installed_sys_proc_units//;
          $installed_cpu =~ s/ //g;
          $installed_cpu =~ s/<\/td>//g;
          $installed_cpu =~ s/<td>//g;
          next;
        }
        if ( $linel =~ m/curr_avail_sys_proc_units/ ) {
          $curr_avail_cpu = $linel;
          $curr_avail_cpu =~ s/curr_avail_sys_proc_units//;
          $curr_avail_cpu =~ s/ //g;
          $curr_avail_cpu =~ s/<\/td>//g;
          $curr_avail_cpu =~ s/<td>//g;
          next;
        }
        if ( $linel =~ m/curr_avail_sys_mem/ ) {
          $a_mem = $linel;
          $a_mem =~ s/curr_avail_sys_mem//;
          $a_mem =~ s/ //g;
          $a_mem =~ s/<\/td>//g;
          $a_mem =~ s/<td>//g;

          # tohle se najak "nechytlo" v CSOB :)
          #if ( $a_mem > 1024  ) { # conversion to GB if >1GB
          #   my $l = int($a_mem/1024 + 0.5);
          #   $a_mem = $l." GB";
          # }
          # else {
          #  $a_mem .= " MB";
          #}
          last;
        }
      }
      print FHR "$host;$managedname;$type_model;$serial_num;$mcpu;$c_mem;$a_mem;;;;$installed_cpu;$curr_avail_cpu\n";
      close(FHG);
    }
    else {
      # server might be switched off --> no global cfg is available
      # or global cfg do not exist from any reason, it will be created nex run (day)
      error("$host:$managedname : does not exist : $out_file");
    }

    $count_s = 0;
    if ( $IVM == 1 ) {
      $mm[$count_s]     .= $tds . "><b><center><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html\">" . $host . "</A></center></b></font><table class=\"tabsyscfg\"><tr><td><font size=\"-1\">Total&nbsp;cores:&nbsp;<b>" . $mcpu . "</b></font></td></tr><tr><td><font size=\"-1\">Total&nbsp;mem:&nbsp;<b>" . $c_mem . "</b></font></td><td><font size=\"-1\">Avail&nbsp;mem:&nbsp;<b>" . $a_mem . "</b></font></td></tr></table>" . $tde;
      $mm_sum[$count_s] .= $tds . " nowrap title=\"Total&nbsp;cores:&nbsp;" . $mcpu . "&nbsp;&nbsp;Total&nbsp;mem:&nbsp;" . $c_mem . "&nbsp;&nbsp;Avail&nbsp;mem:&nbsp;" . $a_mem . "\"><br><b><center><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html\">" . $host . "</A></center></b></font>" . $tde;
      $mm_one[$count_s] .= $tds . " nowrap title=\"Total&nbsp;cores:&nbsp;" . $mcpu . "&nbsp;&nbsp;Total&nbsp;mem:&nbsp;" . $c_mem . "&nbsp;&nbsp;Avail&nbsp;mem:&nbsp;" . $a_mem . "\"><br><b><center><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html\">" . $host . "</A></center></b></font>" . $tde;
    }
    else {
      $mm[$count_s]     .= $tds . "><b><center><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html\" >" . $managedname . "</A></center></b></font><table class=\"tabsyscfg\"><tr><td><font size=\"-1\">Total&nbsp;cores:&nbsp;<b>" . $mcpu . "</b></font></td></tr><tr><td><font size=\"-1\">Total&nbsp;mem:&nbsp;<b>" . $c_mem . "</b></font></td><td><font size=\"-1\">Avail&nbsp;mem:&nbsp;<b>" . $a_mem . "</b></font></td></tr></table>" . $tde;
      $mm_sum[$count_s] .= $tds . " nowrap title=\"Total&nbsp;cores:&nbsp;" . $mcpu . "&nbsp;&nbsp;Total&nbsp;mem:&nbsp;" . $c_mem . "&nbsp;&nbsp;Avail&nbsp;mem:&nbsp;" . $a_mem . "\"><b><center><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html\">" . $managedname . "</A></center></b></font>" . $tde;
      $mm_one[$count_s] .= $tds . " nowrap title=\"Total&nbsp;cores:&nbsp;" . $mcpu . "&nbsp;&nbsp;Total&nbsp;mem:&nbsp;" . $c_mem . "&nbsp;&nbsp;Avail&nbsp;mem:&nbsp;" . $a_mem . "\"><b><center><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html\">" . $managedname . "</A></center></b></font>" . $tde;
    }
    my $result     = "";
    my $result_sum = "";
    my $result_one = "";
    $server_c++;
    my $lpar = "";

    my $mem_cfg = "$wrkdir/$managedname/$host/mem.html";
    if ( !-f $mem_cfg ) {
      error("$host:$managedname : does not exist : $mem_cfg");
      next;
    }

    open( FHM, "< $mem_cfg" ) || next;
    my @lines_mem = <FHM>;
    close(FHM);

    open( FHX, "< $cfg" ) || next;
    my @lines_unsorted = sort(<FHX>);

    # case non sensitive sort
    my @lines = sort { lc($a) cmp lc($b) } @lines_unsorted;
    close(FHX);

    # proc pools
    #print "--- CFG \n";
    foreach my $linep (@proc_pools) {
      chomp($linep);

      #print "--- $linep\n";
      if ( $linep eq '' ) {
        last;
      }
      if ( $linep =~ m/^DefaultPool/ ) {
        next;
      }
      if ( $linep =~ "HSCL" || $linep =~ "VIOSE0" ) {
        error("$host:$managedname : Problem with reading proc pool cfg : $linep");
        last;
      }
      if ( $linep =~ m/does not support multiple shared/ || $linep =~ m/The command entered is either missing/ ) {
        last;
      }

      ( my $name_pool, my $max, my $reserved ) = split( /,/, $linep );
      if ( !defined $reserved || $reserved eq '' ) {
        last;    # potential error
      }
      print FHR "$host;$managedname;;;;;;$name_pool;$reserved;$max\n";

      $count_s++;

      #print "++ $lpar_c $count_s $server_c \n";
      #print "+++ $lpar_c $count_s $server_c $name_pool $max $reserved \n";
      if ( $lpar_c < $count_s && $server_c > 1 ) {
        $lpar_c = $count_s;
        for ( my $i = 1; $i < $server_c; $i++ ) {

          #print "-- $count_s $i\n";
          $mm[$count_s]     .= $td;
          $mm_sum[$count_s] .= $td;
          $mm_one[$count_s] .= $td;
        }
      }
      $result = "<TD nowrap " . $td_col_pool . "<center><B><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html#CPU_pools\">" . $name_pool . "</A></B></font></center><TABLE class=\"tabsyscfg\">";
      $result .= "<tr><td size=\"50%\"><font size=\"-1\">Max&nbsp;CPU:&nbsp;<B>" . $max . "</font></b></td><td><font size=\"-1\">Reserved&nbsp;CPU:&nbsp;<b>" . $reserved . "</font></b></td></tr></table></TD>";
      $result_sum = "<TD nowrap title=\"Max&nbsp;CPU:&nbsp;" . $max . "&nbsp;&nbsp;Reserved&nbsp;CPU:&nbsp;" . $reserved . "\" " . $td_col_pool . "<center><B><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html#CPU_pools\">" . $name_pool . "</A></font></B></center></TD>";
      $result_one = "<TD nowrap title=\"Max&nbsp;CPU:&nbsp;" . $max . "&nbsp;&nbsp;Reserved&nbsp;CPU:&nbsp;" . $reserved . "\" " . $td_col_pool . "<center><B><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html#CPU_pools\">" . $name_pool . "</A></font></B></center></TD>";
      $mm[$count_s]     .= $result;
      $mm_sum[$count_s] .= $result_sum;
      $mm_one[$count_s] .= $result_one;
    }

    lpar_details( $managedname, $host, $cvs_tmp );

    my $out_pools_cli;
    foreach my $linel (@lines) {
      chomp($linel);
      if ( $linel =~ "lpar_name=" ) {
        my @list  = split( /,/, $linel );
        my $first = 0;
        my $l     = "";
        my $state = "";
        $result     = "";
        $result_sum = "";
        $result_one = "";
        my $cpu_ded    = 0;
        my $phys_cores = "na";
        my $logical    = "na";
        my $pool_name  = "na";
        my $cpu_weight = "na";
        my $cpu_mode1  = "na";
        my $cpu_mode2  = "na";

        foreach my $item (@list) {
          chomp($item);
          $first++;
          if ( $first == 1 ) {
            ( my $name_trash, $lpar ) = split( /=/, $item );
            $state = "na";
            foreach $l (@lparlist) {
              if ( $l eq '' ) {
                next;
              }
              chomp($l);
              if ( $l eq '' ) {
                next;
              }
              ( my $name, my $state_a ) = split( /,/, $l );
              if ( $state_a eq '' ) {
                next;
              }
              if ( ( $name =~ quotemeta($lpar) ) && ( length($name) == length($lpar) ) ) {
                $state = $state_a;
              }
            }

            #print "\n$lpar $state ";
            my $lpar_path = $lpar;
            $lpar_path =~ s/\//\&\&1/g;
            my $lpar_url = $lpar;

            #$lpar_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg; # PH: keep it is it is exactly!!!
            #$lpar_url =~ s/ /+/g;
            #$lpar_url =~ s/\#/%23/g;
            $lpar_url =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
            $result     = "<center><B><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html#" . $lpar_url . "\">" . $lpar . "</A></font></B></center><TABLE class=\"tabsyscfg\">";
            $result_sum = "<center><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html#" . $lpar_url . "\">" . $lpar . "</A></font></center>";
            $result_one = "<center><font size=\"-1\"><A HREF=\"" . $host . "/" . $managedname_url . "/config.html#" . $lpar_url . "\">" . $lpar . "</A></font></center>";
            next;
          }

          #if ($item =~ m/^curr_/ && ($item !~ "_max") && ($item !~ "_min") && ($item !~ "curr_shared_proc_pool_id") )
          my $name_col = "";
          ( my $left_c, my $right_c ) = split( /=/, $item );
          if ( $item =~ m/^curr_shared_proc_pool_name/ ) {
            $pool_name = $right_c;
            push( @{$out_pools_cli}, $pool_name );
            next;
          }
          if ( $item =~ m/^curr_proc_mode/ ) {
            $cpu_mode1 = $right_c;
            if ( $right_c =~ m/ded/ ) {
              $cpu_ded = 1;
            }
            next;
          }
          if ( $item =~ m/^curr_proc_units/ ) {
            $phys_cores = $right_c;
            next;
          }
          if ( $item =~ m/^curr_procs/ ) {
            $logical = $right_c;
          }
          if ( $item =~ m/^curr_sharing_mode/ ) {
            if ( $cpu_ded == 1 ) {
              $cpu_mode2 = " ";
            }
            else {
              $cpu_mode2 = "," . $right_c;
            }
            next;
          }
          if ( $item =~ m/^curr_uncap_weight/ ) {
            $cpu_weight = $right_c;
            next;
          }
        }
        my $mode2 = $cpu_mode2;
        $mode2 =~ s/,//;

        $count_s++;

        #print "++ $lpar_c $count_s $server_c \n";
        if ( $lpar_c < $count_s && $server_c > 1 ) {
          $lpar_c = $count_s;
          for ( my $i = 1; $i < $server_c; $i++ ) {

            #print "-- $count_s $i\n";
            $mm[$count_s]     .= $td;
            $mm_sum[$count_s] .= $td;
            $mm_one[$count_s] .= $td;
          }
        }

        my $ram = "na";
        foreach my $line_mem (@lines_mem) {
          chomp($line_mem);
          $line_mem .= " ";
          $line_mem =~ s/<TR> <TD><B>//;
          $line_mem =~ s/<\/B><\/TD> <TD align=\"center\">/|/g;
          $line_mem =~ s/<\/TD> <TD align=\"center\">/|/g;
          $line_mem =~ s/<\/TD><\/TR>//g;

          #$line_mem =~ s/<.*//;
          if ( $line_mem !~ m/\|/ ) {
            next;
          }

          #print "XX3 $line_mem\n";
          ( my $lpar_mem, my $trash1, my $trash2, my $strash3, $ram ) = split( /\|/, $line_mem );
          if ( !defined $ram ) {
            $ram = "";
          }
          if ( "$lpar_mem" eq "$lpar" && length($lpar) == length($lpar_mem) ) {
            if ( isdigit($ram) ) {

              #if ( $ram > 1024  )  # conversion to GB if >1GB
              #  my $l = sprintf ("%.1f",$ram/1024);
              #  $ram = $l."&nbsp;GB";
              #
              #else
              #  $ram .= "&nbsp;MB";
              #
            }
            last;
          }
        }

        # get al lpar info into HTML format
        $result .= "<tr><td><font size=\"-1\">Cores:&nbsp;<b>" . $phys_cores . "</b></font></td>";
        $result .= "    <td><font size=\"-1\">Logical&nbsp;CPU:&nbsp;<b>" . $logical . "</b></font></td><tr>";
        $result .= "<tr><td><font size=\"-1\">Pool:&nbsp;<b>" . $pool_name . "</b></font></td>";
        $result .= "    <td><font size=\"-1\">CPU&nbsp;weight:&nbsp;<b>" . $cpu_weight . "</b></font></td></tr>";
        $result .= "<tr><td><font size=\"-1\">Mode:&nbsp;<b>" . $cpu_mode1 . $cpu_mode2 . "</b></font></td>";
        $result .= "    <td><font size=\"-1\">RAM:&nbsp;<b>" . $ram . "</b></font></td></tr></table>";

        #print "------ $lpar  $state\n";
        if ( $state =~ m/Running/ ) {
          $mm[$count_s]     .= $tds . $td_col_run . $result . $tde;
          $mm_sum[$count_s] .= $tds . " nowrap title=\"Cores:&nbsp;" . $phys_cores . "&nbsp;&nbsp;Logical&nbsp;CPU:&nbsp;" . $logical . "&nbsp;&nbsp;Pool:&nbsp;" . $pool_name . "&nbsp;&nbsp;CPU&nbsp;weight:" . $cpu_weight . "&nbsp;&nbsp;Mode:&nbsp;" . $cpu_mode1 . $cpu_mode2 . "&nbsp;&nbsp;RAM:&nbsp;" . $ram . "\" " . $td_col_run . $result_sum . $tde;
          $mm_one[$count_s] .= $tds . " nowrap title=\"Cores:&nbsp;" . $phys_cores . "&nbsp;&nbsp;Logical&nbsp;CPU:&nbsp;" . $logical . "&nbsp;&nbsp;Pool:&nbsp;" . $pool_name . "&nbsp;&nbsp;CPU&nbsp;weight:" . $cpu_weight . "&nbsp;&nbsp;Mode:&nbsp;" . $cpu_mode1 . $cpu_mode2 . "&nbsp;&nbsp;RAM:&nbsp;" . $ram . "\" " . $td_col_run . $result_one . $tde;
        }
        else {
          $mm[$count_s]     .= $tds . $td_col_donot_run . $result . $tde;
          $mm_sum[$count_s] .= $tds . " nowrap title=\"&nbsp;&nbsp;Cores:&nbsp;" . $phys_cores . "&nbsp;&nbsp;Logical&nbsp;CPU:&nbsp;" . $logical . "&nbsp;&nbsp;Pool:&nbsp;" . $pool_name . "&nbsp;&nbsp;CPU&nbsp;weight:" . $cpu_weight . "&nbsp;&nbsp;Mode:&nbsp;" . $cpu_mode1 . $cpu_mode2 . "&nbsp;&nbsp;RAM:&nbsp;" . $ram . "\" " . $td_col_donot_run . $result_sum . $tde;
          $mm_one[$count_s] .= $tds . " nowrap title=\"&nbsp;&nbsp;Cores:&nbsp;" . $phys_cores . "&nbsp;&nbsp;Logical&nbsp;CPU:&nbsp;" . $logical . "&nbsp;&nbsp;Pool:&nbsp;" . $pool_name . "&nbsp;&nbsp;CPU&nbsp;weight:" . $cpu_weight . "&nbsp;&nbsp;Mode:&nbsp;" . $cpu_mode1 . $cpu_mode2 . "&nbsp;&nbsp;RAM:&nbsp;" . $ram . "\" " . $td_col_donot_run . $result_one . $tde;
        }

        #print "$mm[$count_s]\n";
      }
    }
    if ( $lpar_c == 0 ) {
      $lpar_c = $count_s;
    }
    else {
      #print "-- $count_s $lpar_c \n";
      #$count_s++;
      for ( ; $count_s + 1 < $lpar_c + 1; $count_s++ ) {

        #print "++ $count_s $lpar_c \n";
        $mm[ $count_s + 1 ]     .= $td;
        $mm_sum[ $count_s + 1 ] .= $td;
        $mm_one[ $count_s + 1 ] .= $td;
      }
      if ( $count_s > $lpar_c ) {
        $lpar_c = $count_s;
      }
    }

  }

  foreach my $line (@mm) {
    print FHO "$tr_start $line $tr_stop\n";
  }

  foreach my $line (@mm_sum) {
    print FHS "$tr_start $line $tr_stop\n";
  }

  foreach my $line (@mm_one) {
    print FHH "$tr_start $line $tr_stop\n";
  }

  print FHO "</TABLE>\n";
  print FHH "</TABLE>\n";
  print FHS "</TABLE>\n";
  my $ltime = localtime($act_time);
  print FHO "</center><br><br><table><tr><td $td_col_run <font size=\"-1\"> running</font></td><td $td_col_donot_run <font size=\"-1\"> not running</font></td><td $td_col_pool <font size=\"-1\"> CPU pool</font></td></tr></table><br>\n";
  print FHH "</center><br><br><table><tr><td $td_col_run <font size=\"-1\"> running</font></td><td $td_col_donot_run <font size=\"-1\"> not running</font></td><td $td_col_pool <font size=\"-1\"> CPU pool</font></td></tr></table><br>\n";
  print FHO "<font size=\"-1\">It is updated once a day, last run: $ltime\n</font><br>";
  print FHH "<font size=\"-1\">It is updated once a day, last run: $ltime\n</font><br>";

  close(FHO);
  close(FHH);
  close(FHS);
  close(FHR);

  # delete old CVS file and move new one
  if ( -f "$cvs" ) {
    unlink("$cvs") || error( "Cannot rm $cvs: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  rename( "$cvs_tmp", "$cvs" ) || error( " Cannot mv $cvs_tmp $cvs: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  return 1;
}

# had a problem with filling that in var in LoadDataModule.pm tehrefore it is here
sub procpoolagg {
  my $host                   = shift;
  my $managedname            = shift;
  my $UUID_SERVER            = shift;
  my $cpu_pools_mapping_file = "$basedir/data/$managedname/$host/cpu-pools-mapping.txt";
  open( my $pools_mapping, "<", $cpu_pools_mapping_file ) || error( " Cannot open $cpu_pools_mapping_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  my @mappings = <$pools_mapping>;
  my $out_mapping;
  foreach my $map (@mappings) {
    chomp($map);
    ( my $id, my $name ) = split( ",", $map );
    $out_mapping->{$id}{name} = $name;
  }
  close($pools_mapping);

  @poollistagg = `$SSH $hmc_user\@$host "LC_ALL=en_US LANG=en_US LC_NUMERIC=en_US lshwres -r procpool -m \\"$managedname\\" -F shared_proc_pool_id,lpar_names"`;
  my $out = \@poollistagg;
  my $out_shp;
  foreach my $o ( @{$out} ) {
    chomp($o);
    my ( $pool_id, @lpars ) = split( ',', $o );
    $out_shp->{$pool_id}{PoolID}   = $pool_id;
    $out_shp->{$pool_id}{PoolName} = $out_mapping->{$pool_id}{name};
    $out_shp->{$pool_id}{UUID}     = PowerDataWrapper::md5_string("$UUID_SERVER $pool_id");
    foreach my $l (@lpars) {
      $l =~ s/"//g;
      if ( $l =~ m/=/ ) {
        my ( $metric, $value ) = split( "=", $l );
        $out_shp->{$pool_id}{$metric} = $value;
      }

      #      push(@{$out_shp->{$pool_id}{vm}}, $l);
    }

  }
  if ( !$restapi ) {
    my $file_path = "$basedir/tmp/restapi/HMC_SHP_$managedname\_conf.json";
    Xorux_lib::write_json( $file_path, $out_shp ) if ( defined $out_shp && Xorux_lib::file_time_diff($file_path) > 3600 || Xorux_lib::file_time_diff($file_path) == 0 );
  }

  return 1;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

sub save_cfg_data {
  my $managedname = shift;
  my $date        = shift;
  my $upgrade     = shift;
  my $serial      = shift;
  my $model       = shift;
  my $ret         = 0;
  if ( $restapi == 1 ) {
    print "Skip save_cfg_data (use rest api instead)\n";
    return 0;
  }
  my $UUID_SERVER = PowerDataWrapper::md5_string("$serial $model");

  $ret = save_cpu_cfg( $managedname, $date, $upgrade );
  if ( $ret > 0 ) {
    return $ret;
  }
  $ret = save_cpu_cfg_global( $managedname, $date, $upgrade, $UUID_SERVER );
  if ( $ret == 1 ) {
    return 1;
  }

  # Include HW info
  if ( $HWINFO && !$restapi ) {
    save_config( $managedname, $date, $upgrade );
  }

  if ( $HMC == 1 || $SDMC == 1 ) {    # IVM does not support it
                                      # Include system changes
    if ($SYS_CHANGE) {
      sys_change( $managedname, $date );
    }
  }

  return 0;
}

sub rename_server {
  my $host        = shift;
  my $managedname = shift;
  my $model       = shift;
  my $serial      = shift;

  if ( !-d "$wrkdir/$managedname" ) {

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

      print "system renamed : $host:$managedname from $base to $managedname, behave as upgrade : $link\n" if $DEBUG;
      if ( -d "$link" ) {
        print "system renamed : mv $link $wrkdir/$managedname\n" if $DEBUG;
        rename( "$link", "$wrkdir/$managedname" ) || error( " Cannot mv $link $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      unlink("$wrkdir/$model*$serial") || error( " Cannot rm $wrkdir/$model*4serial: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      $upgrade = 1;    # must be like upgrade behave due to views
    }
    else {
      print "mkdir          : $host:$managedname $wrkdir/$managedname\n" if $DEBUG;
      mkdir( "$wrkdir/$managedname", 0755 ) || error( " Cannot mkdir $wrkdir/$managedname: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    LoadDataModule::touch("$wrkdir/$managedname");    #must be at the end dou to renaming servers
  }

  # check wherher the symlink is linked to the right targed
  # there could be an issue with symlink prior 3.37 ($managedname dirs could be created from HEA stuff without care about renaming)
  my $managedname_linked = "";
  my $link               = "";
  my $link_expected      = "$wrkdir/$model*$serial";
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
      return 1;
    }
    else {
      print "symlink correct: $host:$managedname : $link : $link_expected\n" if $DEBUG;
      unlink($link_expected);
    }
  }

  return 1;
}

# fill in @lpm_excl_vio for server
sub lpm_exclude_vio {
  my $host        = shift;
  my $managedname = shift;
  my $wrkdir      = shift;
  my $lpm_excl    = "$wrkdir/$managedname/$host/lpm-exclude.txt";

  if ( $lpm == 0 ) {
    return 0;    # LPM is switched off
  }
  open( FH, "< $lpm_excl" ) || return 1;
  @lpm_excl_vio = <FH>;
  close(FH);
  return 0;
}

sub lpar_details {
  my $managedname = shift;
  my $host        = shift;
  my $cvs         = shift;

  if ( !-f "$wrkdir/$managedname/$host/config.cfg" ) {
    error("does not exist $wrkdir/$managedname/$host/config.cfg");
    return 1;
  }

  open( FHC, ">> $cvs" ) || error( " Can't open $cvs" . __FILE__ . ":" . __LINE__ ) && return 0;    # detailed cfg in CSV format

  open( FCFG, "< $wrkdir/$managedname/$host/config.cfg" ) || error( " Can't open $wrkdir/$managedname/$host/config.cfg" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $csv_lpar_name           = "na";
  my $csv_lpar_id             = "na";
  my $csv_default_profile     = "na";
  my $csv_min_proc_units      = "na";
  my $csv_desired_proc_units  = "na";
  my $csv_max_proc_units      = "na";
  my $csv_curr_min_proc_units = "na";
  my $csv_curr_proc_units     = "na";
  my $csv_curr_max_proc_units = "na";
  my $csv_min_procs           = "na";
  my $csv_desired_procs       = "na";
  my $csv_max_procs           = "na";
  my $csv_curr_min_procs      = "na";
  my $csv_curr_procs          = "na";
  my $csv_curr_max_procs      = "na";
  my $csv_min_mem             = "na";
  my $csv_desired_mem         = "na";
  my $csv_max_mem             = "na";
  my $csv_curr_min_mem        = "na";
  my $csv_curr_mem            = "na";
  my $csv_curr_max_mem        = "na";
  my $csv_state               = "na";
  my $csv_lpar_env            = "na";
  my $csv_os_version          = "na";
  my $pool_name               = "na";
  my $cpu_mode1               = "na";
  my $phys_cores              = "na";
  my $logical                 = "na";
  my $cpu_mode2               = "na";
  my $cpu_weight              = "na";
  my $cpu_ded                 = "na";

  my $item    = "";
  my $right_c = "";
  my $first   = 0;

  # select data only from actual active profile
  my $curr_profile  = "";
  my $right_profile = 0;
  my $profile       = 0;

  #print "000 $wrkdir/$managedname/$host/config.cfg\n";
  foreach my $linel (<FCFG>) {
    chomp($linel);
    if ( $linel eq '' ) {
      next;
    }

    if ( $linel =~ "LPAR config:" ) {
      $first = 1;
      if ( $csv_lpar_name !~ m/^na$/ ) {
        print FHC "$host;$managedname;$csv_lpar_name;$pool_name;$cpu_mode1;$phys_cores;$logical;$cpu_mode2;$cpu_weight;$csv_lpar_id;$csv_default_profile;$csv_min_proc_units;$csv_desired_proc_units;$csv_max_proc_units;$csv_curr_min_proc_units;$csv_curr_max_proc_units;$csv_min_procs;$csv_desired_procs;$csv_max_procs;$csv_curr_min_procs;$csv_curr_max_procs;$csv_min_mem;$csv_desired_mem;$csv_max_mem;$csv_curr_min_mem;$csv_curr_mem;$csv_curr_max_mem;$csv_state;$csv_lpar_env;$csv_os_version\n";
      }

      #print "001 $csv_lpar_name\n";

      $csv_lpar_name           = "na";
      $csv_lpar_id             = "na";
      $csv_default_profile     = "na";
      $csv_min_proc_units      = "na";
      $csv_desired_proc_units  = "na";
      $csv_max_proc_units      = "na";
      $csv_curr_min_proc_units = "na";
      $csv_curr_proc_units     = "na";
      $csv_curr_max_proc_units = "na";
      $csv_min_procs           = "na";
      $csv_desired_procs       = "na";
      $csv_max_procs           = "na";
      $csv_curr_min_procs      = "na";
      $csv_curr_procs          = "na";
      $csv_curr_max_procs      = "na";
      $csv_min_mem             = "na";
      $csv_desired_mem         = "na";
      $csv_max_mem             = "na";
      $csv_curr_min_mem        = "na";
      $csv_curr_mem            = "na";
      $csv_curr_max_mem        = "na";
      $csv_state               = "na";
      $csv_lpar_env            = "na";
      $csv_os_version          = "na";
      $pool_name               = "na";
      $cpu_mode1               = "na";
      $phys_cores              = "na";
      $logical                 = "na";
      $cpu_mode2               = "na";
      $cpu_weight              = "na";
      $cpu_ded                 = "na";
      $curr_profile            = "";
      $right_profile           = 0;
      $profile                 = 0;
      next;
    }

    if ( $first == 0 ) {
      next;
    }

    $item    = "";
    $right_c = "na";

    #print "003 $linel \n";

    if ( $linel !~ m/ / ) {
      next;
    }

    ( $item, $right_c ) = split( /\s{1,}/, $linel );    # if is there one and more spaces or tabelators

    if ( $item eq '' ) {
      next;
    }
    if ( $right_c eq '' ) {
      next;
    }

    # --> this is due to parameter with a space inside like pool name, status ...
    my $line2 = $linel;
    $line2 =~ s/^.*$right_c / /;
    if ( length($linel) != length($line2) ) {
      $right_c .= $line2;
    }

    #print "004 $linel : $item - $right_c : profile=$profile curr_profile=$curr_profile \n";

    if ( $linel =~ m/LPAR profiles:/ ) {
      $profile = 1;
      next;
    }

    if ( $item =~ m/^curr_profile/ ) {
      $curr_profile = $right_c;
      next;
    }
    if ( $profile == 1 && $item =~ m/^name/ ) {
      $right_profile = 0;
      if ( $curr_profile =~ m/^$right_c$/ ) {
        $right_profile = 1;
      }
      next;
    }
    if ( $item =~ m/^Memory resources / ) {
      $profile = 0;
    }

    #print "004 $linel : $item - $right_c : profile=$profile curr_profile=$curr_profile right_profile=$right_profile\n";

    if ( $item =~ m/^curr_shared_proc_pool_name/ ) {
      if ( $pool_name !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $pool_name = $right_c;
      next;
    }
    if ( $item =~ m/^curr_proc_mode/ ) {
      if ( $cpu_mode1 !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $cpu_mode1 = $right_c;
      next;
    }
    if ( $item =~ m/^curr_proc_units/ ) {
      if ( $phys_cores !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $phys_cores = $right_c;
      next;
    }
    if ( $item =~ m/^curr_procs/ ) {
      if ( $logical !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $logical = $right_c;
      next;
    }
    if ( $item =~ m/^curr_sharing_mode/ ) {
      if ( $cpu_mode2 !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $cpu_mode2 = $right_c;
      next;
    }
    if ( $item =~ m/^curr_uncap_weight/ ) {
      if ( $cpu_weight !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $cpu_weight = $right_c;
      next;
    }
    if ( $item =~ m/^name/ ) {
      if ( $csv_lpar_name !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_lpar_name = $right_c;
      next;
    }
    if ( $item =~ m/^lpar_id/ ) {
      if ( $csv_lpar_id !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_lpar_id = $right_c;
      next;
    }
    if ( $item =~ m/^default_profile/ ) {
      if ( $csv_default_profile !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_default_profile = $right_c;
      next;
    }
    if ( $item =~ m/^min_proc_units/ ) {
      if ( $csv_min_proc_units !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_min_proc_units = $right_c;
      next;
    }
    if ( $item =~ m/^desired_proc_units/ ) {
      if ( $csv_desired_proc_units !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_desired_proc_units = $right_c;
      next;
    }
    if ( $item =~ m/^max_proc_units/ ) {
      if ( $csv_max_proc_units !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_max_proc_units = $right_c;
      next;
    }
    if ( $item =~ m/^curr_min_proc_units/ ) {
      if ( $csv_curr_min_proc_units !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_curr_min_proc_units = $right_c;
      next;
    }
    if ( $item =~ m/^curr_proc_units/ ) {
      if ( $csv_curr_proc_units !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_curr_proc_units = $right_c;
      next;
    }
    if ( $item =~ m/^curr_max_proc_units/ ) {
      if ( $csv_curr_max_proc_units !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_curr_max_proc_units = $right_c;
      next;
    }
    if ( $item =~ m/^min_procs/ ) {
      if ( $csv_min_procs !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_min_procs = $right_c;
      next;
    }
    if ( $item =~ m/^desired_procs/ ) {
      if ( $csv_desired_procs !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_desired_procs = $right_c;
      next;
    }
    if ( $item =~ m/^max_procs/ ) {
      if ( $csv_max_procs !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_max_procs = $right_c;
      next;
    }
    if ( $item =~ m/^curr_min_procs/ ) {
      if ( $csv_curr_min_procs !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_curr_min_procs = $right_c;
      next;
    }
    if ( $item =~ m/^curr_procs/ ) {
      if ( $csv_curr_procs !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_curr_procs = $right_c;
      next;
    }
    if ( $item =~ m/^curr_max_procs/ ) {
      if ( $csv_curr_max_procs !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_curr_max_procs = $right_c;
      next;
    }
    if ( $item =~ m/^min_mem/ ) {
      if ( $csv_min_mem !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_min_mem = $right_c;
      next;
    }
    if ( $item =~ m/^desired_mem/ ) {
      if ( $csv_desired_mem !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_desired_mem = $right_c;
      next;
    }
    if ( $item =~ m/^max_mem/ ) {
      if ( $csv_max_mem !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_max_mem = $right_c;
      next;
    }
    if ( $item =~ m/^curr_min_mem/ ) {
      if ( $csv_curr_min_mem !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_curr_min_mem = $right_c;
      next;
    }
    if ( $item =~ m/^curr_mem$/ ) {
      if ( $csv_curr_mem !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_curr_mem = $right_c;
      next;
    }
    if ( $item =~ m/^curr_max_mem/ ) {
      if ( $csv_curr_max_mem !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_curr_max_mem = $right_c;
      next;
    }
    if ( $item =~ m/^state/ ) {
      if ( $csv_state !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_state = $right_c;
      next;
    }
    if ( $item =~ m/^lpar_env/ ) {
      if ( $csv_lpar_env !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_lpar_env = $right_c;
      next;
    }
    if ( $item =~ m/^os_version/ ) {
      if ( $csv_os_version !~ m/^na$/ ) {
        if ( $right_profile == 0 ) {
          next;
        }
      }
      $csv_os_version = $right_c;
      next;
    }
  }

  # print the last lpar
  if ( $csv_lpar_name !~ m/^na$/ ) {
    print FHC "$host;$managedname;$csv_lpar_name;$pool_name;$cpu_mode1;$phys_cores;$logical;$cpu_mode2;$cpu_weight;$csv_lpar_id;$csv_default_profile;$csv_min_proc_units;$csv_desired_proc_units;$csv_max_proc_units;$csv_curr_min_proc_units;$csv_curr_max_proc_units;$csv_min_procs;$csv_desired_procs;$csv_max_procs;$csv_curr_min_procs;$csv_curr_max_procs;$csv_min_mem;$csv_desired_mem;$csv_max_mem;$csv_curr_min_mem;$csv_curr_mem;$csv_curr_max_mem;$csv_state;$csv_lpar_env;$csv_os_version\n";
  }

  close(FHC);
  close(FCFG);

  return 0;
}

sub last_timestamp {
  my $wrkdir        = shift;
  my $managedname   = shift;
  my $host          = shift;
  my $last_file     = shift;
  my $source        = shift;
  my $t             = shift;
  my $last_rec_file = "";
  my $where         = "file";

  if ( -f "$wrkdir/$managedname/$host/$last_file" ) {
    $where = "$last_file";

    # read timestamp of last record
    # this is main loop how to get corectly timestamp of last record!!!
    open( FHLT, "< $wrkdir/$managedname/$host/$last_file" ) || error( " Can't open $wrkdir/$managedname/$host/$last_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    foreach my $line (<FHLT>) {
      chomp($line);
      $last_rec_file = $line;
    }

    #print "last rec       : $host:$managedname $last_rec_file : $last_file\n";
    close(FHLT);
    $ret = substr( $last_rec_file, 0, 1 );
    if ( $last_rec_file eq '' || $ret =~ /\D/ ) {

      # in case of an issue with last file, remove it and use default 140 min? for further run ...
      error("Wrong input data, deleting file : $wrkdir/$managedname/$host/$last_file : $last_rec_file");
      unlink("$wrkdir/$managedname/$host/$last_file");

      # place ther last 2h when an issue with last.txt
      $loadhours = 2;
      $loadmins  = 120;
      $last_rec  = $t - 7200;
    }
    else {
      $last_rec  = str2time($last_rec_file);
      $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
      $loadhours++;
      $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
    }
  }
  else {
    # old not accurate way how to get last time stamp, keeping it here as backup if above temp fails for any reason
    if ( -f "$wrkdir/$managedname/$host/$source.rr$type_sam" ) {
      $where = "$source.rr$type_sam - $last_file";

      # find out last record in the db (hourly)
      RRDp::cmd qq(last "$wrkdir/$managedname/$host/$source.rr$type_sam" );
      my $last_rec_raw = RRDp::read;
      chomp($$last_rec_raw);
      $last_rec  = $$last_rec_raw;
      $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
      $loadhours++;
      $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
      ( my $sec, $ivmmin, $ivmh, $ivmd, $ivmm, $ivmy, my $wday, my $yday, my $isdst ) = localtime($last_rec);
      $ivmy += 1900;
      $ivmm += 1;

      if ( $loadmins < 0 ) {                                         # Do not know why, but it sometimes happens!!!
        if ( -f "$wrkdir/$managedname/$host/$source.rrd" ) {

          # find out last record in the db (hourly)
          RRDp::cmd qq(last "$wrkdir/$managedname/$host/$source.rrd" );
          my $last_rec_raw = RRDp::read;
          chomp($$last_rec_raw);
          $last_rec  = $$last_rec_raw;
          $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
          $loadhours++;
          $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
          error("$last_file: ++2 $loadhours $last_rec -- $t");
        }
      }
    }
    else {
      if ( -f "$wrkdir/$managedname/$host/$source.rrd" ) {
        $where = "$source.rrd - $last_file";

        # find out last record in the db (hourly)
        RRDp::cmd qq(last "$wrkdir/$managedname/$host/$source.rrd" );
        my $last_rec_raw = RRDp::read;
        chomp($$last_rec_raw);
        $last_rec  = $$last_rec_raw;
        $loadhours = sprintf( "%.0f", ( $t - $last_rec ) / 3600 );
        $loadhours++;
        $loadmins = sprintf( "%.0f", ( $t - $last_rec ) / 60 + 5 );    # +5mins to be sure
      }
      else {
        $where = "init - $last_file";

        # nothing does not exist --> initial load
        $loadhours = $INIT_LOAD_IN_HOURS_BACK;
        $loadmins  = $loadhours * 60;
      }
    }
  }

  if ( ( $loadhours <= 0 || $loadmins <= 0 ) && !$restapi ) {    # something wrong is here
    my $time_string = localtime($last_rec);
    error("Last rec issue: $host:$managedname $last_file:  $loadhours - $loadmins -  $time_string ($last_rec) : where ($where) : $last_rec_file : 02");

    # place some reasonable defaults : -2 hours
    $loadhours = 2;
    $loadmins  = 120;
    $last_rec  = time();
    $last_rec  = $last_rec - 7200;
  }

  ( $sec, $ivmmin, $ivmh, $ivmd, $ivmm, $ivmy, $wday, $yday, $isdst ) = localtime($last_rec);
  $ivmy += 1900;
  $ivmm += 1;

  $timerange = " --minutes " . $loadmins . " ";    # global variable, it must be changed here
  print "last rec 3     : $host:$managedname min:$loadmins , hour:$loadhours, $ivmm/$ivmd/$ivmy $ivmh:$ivmmin : $where - source:$source\n" if $DEBUG;

  return 0;
}

# return 1 if the argument is valid IP, otherwise 0
sub is_IP {
  my $ip = shift;

  if ( $ip =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/ && ( ( $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 ) ) ) {
    return 1;
  }
  else {
    return 0;
  }
}

sub isdigit {
  my $digit = shift;
  my $text  = shift;

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

# it check if rrdtool supports graphv --> then zoom is supported
sub rrdtool_graphv {
  my $graph_cmd   = "graph";
  my $graphv_file = "$tmpdir/graphv";

  my $ansx = `$rrdtool`;

  if ( index( $ansx, 'graphv' ) != -1 ) {

    # graphv exists, create a file to pass it to cgi-bin commands
    if ( !-f $graphv_file ) {
      `touch $graphv_file`;
    }
  }
  else {
    if ( -f $graphv_file ) {
      unlink($graphv_file);
    }
  }

  return 0;
}

sub frame_multi {
  my ( $text, $type_sam, $type, $xgrid ) = @_;

  # e.g. frame_multi( "day",   "m", "d", "MINUTE:60:HOUR:2:HOUR:4:0:%H" );

  my $file = "";
  my $i    = 0;
  my $cmd  = "";
  my $cmdq = "";
  my $j    = 0;
  my $managed_ok;
  my $managedname_exl = "";
  my $managedname     = "";
  my @m_excl          = "";
  my $req_time        = 0;
  my $act_time        = time();
  my $name            = "$webdir/$host/pool-multi-$type";
  $step = $STEP;

  my $tmp_file  = "$tmpdir/multi-hmc-$host-$type.cmd";
  my $skip_time = 0;
  if ( "$type" =~ "d" ) {
    $req_time = $act_time - 86400;
  }
  if ( "$type" =~ "w" ) {
    $req_time  = $act_time - 604800;
    $skip_time = $WEEK_REFRESH;
  }
  if ( "$type" =~ "m" ) {
    $req_time  = $act_time - 2764800;
    $skip_time = $MONTH_REFRESH;
  }
  if ( "$type" =~ "y" ) {
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  print "creating m_hmc : $host:$type\n" if $DEBUG;
  my $header = "$host aggregated : last $text";

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"CPU cores\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"Utilization in CPU cores\\:               average   maximum\\l\\\"";

  my $gtype      = "AREA";
  my $color_indx = 0;
  my $i_max      = 0;
  my $y_max      = -1;
  my $cmd_max    = "";

  foreach my $line (@managednamelist) {
    chomp($line);
    if ( $line !~ ".*,.*,.*" ) {

      # it must look like : PWR6A-9117-MMA-SN103A4B0,9117-MMA,103A4B0, --> exclude banners
      next;
    }
    if ( $line =~ /No results were found/ ) {
      print "HMC : $host does not contain any managed system\n" if $DEBUG;
      return 0;
    }
    ( $managedname, my $model, my $serial ) = split( /,/, $line );

    if ( is_IP($managedname) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    $managed_ok = 1;
    if ( $managed_systems_exclude ne '' ) {
      @m_excl = split( /:/, $managed_systems_exclude );
      foreach $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managedname =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      next;
    }

    if ( $type_sam =~ "d" ) {
      $req_time = $act_time - 31536000;
    }
    $file = "pool.rrm";
    if ( "$type" =~ "d" ) {
      if ( -e "$wrkdir/$managedname/$host/pool.rrh" ) {
        $file = "pool.rrh";
      }
      $req_time = $act_time - 86400;
    }
    if ( "$type" =~ "w" ) {
      if ( -e "$wrkdir/$managedname/$host/pool.rrh" ) {
        $file = "pool.rrh";
      }
      if ( -e "$wrkdir/$managedname/$host/pool.rrm" ) {
        $file = "pool.rrm";
      }
      $req_time = $act_time - 604800;
    }
    if ( "$type" =~ "m" ) {
      if ( -e "$wrkdir/$managedname/$host/pool.rrh" ) {
        $file = "pool.rrh";
      }
      if ( -e "$wrkdir/$managedname/$host/pool.rrm" ) {
        $file = "pool.rrm";
      }
      $req_time = $act_time - 2764800;
    }
    if ( "$type" =~ "y" ) {
      if ( -e "$wrkdir/$managedname/$host/pool.rrh" ) {
        $file = "pool.rrh";
      }
      if ( -e "$wrkdir/$managedname/$host/pool.rrd" ) {
        $file = "pool.rrd";
      }
      if ( -e "$wrkdir/$managedname/$host/pool.rrm" ) {
        $file = "pool.rrm";
      }
    }

    if ( -e "$wrkdir/$managedname/$host/$file" ) {

      # avoid old servers which do not exist in the period
      my $rrd_upd_time = ( stat("$wrkdir/$managedname/$host/$file") )[9];
      if ( $rrd_upd_time < $req_time ) {
        next;
      }
    }
    else {
      # avoid non-existing managed systems (with no utillization data on)
      next;
    }

    my $managedname_space      = $managedname;
    my $managedname_space_proc = $managedname;
    $managedname_space_proc =~ s/:/\\:/g;
    $managedname_space_proc =~ s/%/%%/g;    # anti '%

    for ( my $k = length($managedname); $k < 35; $k++ ) {
      $managedname_space .= " ";
    }

    $managedname_space =~ s/:/\\:/g;        # anti ':'
    my $wrkdir_managedname_host_file = "$wrkdir/$managedname/$host/$file";
    $wrkdir_managedname_host_file =~ s/:/\\:/g;
    my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
    $wrkdir_managedname_host_file_legend =~ s/%/%%/g;

    # bulid RRDTool cmd
    my $csp = PowerDataWrapper::get_server_metric( $managedname, "ConfigurableSystemProcessorUnits", 0 );
    $cmd .= " DEF:totcyc${i}=\\\"$wrkdir_managedname_host_file\\\":total_pool_cycles:AVERAGE";
    $cmd .= " DEF:uticyc${i}=\\\"$wrkdir_managedname_host_file\\\":utilized_pool_cyc:AVERAGE";
    $cmd .= " DEF:ncpu${i}=\\\"$wrkdir_managedname_host_file\\\":conf_proc_units:AVERAGE";
    $cmd .= " DEF:ncpubor${i}=\\\"$wrkdir_managedname_host_file\\\":bor_proc_units:AVERAGE";

    # if it does not exist for some time period then put 0 there
    $cmd .= " CDEF:cpu${i}=ncpu${i},UN,0,ncpu${i},IF";
    $cmd .= " CDEF:cpubor${i}=ncpubor${i},UN,0,ncpubor${i},IF";
    $cmd .= " CDEF:totcpu${i}=cpu${i},cpubor${i},+";
    $cmd .= " CDEF:cpuutil${i}=uticyc${i},totcyc${i},GT,UNKN,uticyc${i},totcyc${i},/,IF";
    $cmd .= " CDEF:cpuutiltot${i}=cpuutil${i},totcpu${i},*";
    $cmd .= " CDEF:utilisa${i}=cpuutil${i},100,*";
    $cmd .= " PRINT:cpuutiltot${i}:AVERAGE:\"%6.2lf $delimiter multihmcframe $delimiter $managedname_space_proc $delimiter $color[$color_indx] $delimiter $wrkdir_managedname_host_file_legend-ahoj\"";
    $cmd .= " PRINT:cpuutiltot${i}:MAX:\" %6.2lf $delimiter\"";

    $cmdq .= " $gtype:cpuutiltot${i}$color[$color_indx++]:\\\"$managedname_space\\\"";
    $cmdq .= " GPRINT:cpuutiltot${i}:AVERAGE:\\\"%6.2lf \\\"";
    $cmdq .= " GPRINT:cpuutiltot${i}:MAX:\\\"%6.2lf \\l\\\"";
    $gtype = "STACK";
    $i++;

    # rrd max for pools
    my $rrd_max = "pool.xrm";
    if ( -e "$wrkdir/$managedname/$host/$rrd_max" ) {

      my $wrkdir_managedname_host_file_max = "$wrkdir/$managedname/$host/$rrd_max";
      $wrkdir_managedname_host_file_max =~ s/:/\\:/g;

      # bulid RRDTool cmd
      $cmd_max .= " DEF:totcyc_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":total_pool_cycles:MAX";
      $cmd_max .= " DEF:uticyc_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":utilized_pool_cyc:MAX";
      $cmd_max .= " DEF:ncpu_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":conf_proc_units:MAX";
      $cmd_max .= " DEF:ncpubor_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":bor_proc_units:MAX";

      # if it does not exist for some time period then put 0 there
      $cmd_max .= " CDEF:cpu_max${i_max}=ncpu_max${i_max},UN,0,ncpu_max${i_max},IF";
      $cmd_max .= " CDEF:cpubor_max${i_max}=ncpubor_max${i_max},UN,0,ncpubor_max${i_max},IF";
      $cmd_max .= " CDEF:totcpu_max${i_max}=cpu_max${i_max},cpubor_max${i_max},+";
      $cmd_max .= " CDEF:cpuutil_max${i_max}=uticyc_max${i_max},totcyc_max${i_max},GT,UNKN,uticyc_max${i_max},totcyc_max${i_max},/,IF";
      $cmd_max .= " CDEF:cpuutiltot_max${i_max}=cpuutil_max${i_max},totcpu_max${i_max},*";

      if ( $i_max == 0 ) {
        $cmd_max .= " CDEF:main_res${i_max}=cpuutiltot_max${i_max}";
      }
      else {
        $cmd_max .= " CDEF:pom${i_max}=main_res${y_max},UN,0,main_res${y_max},IF,cpuutiltot_max${i_max},UN,0,cpuutiltot_max${i_max},IF,+";
        $cmd_max .= " CDEF:main_res${i_max}=main_res${y_max},UN,cpuutiltot_max${i_max},UN,UNKN,pom${i_max},IF,pom${i_max},IF";
      }

      $i_max++;
      $y_max++;
    }

    if ( $color_indx > $color_max ) {
      $color_indx = 0;
    }
  }

  if ( $i == 0 ) {

    # no available managed system
    return 1;
  }

  # add count of all CPU in pools
  for ( $j = 0; $j < $i; $j++ ) {
    if ( $j == 0 ) {
      $cmd .= " CDEF:tcpu${j}=cpu${j},cpubor${j},+";
    }
    else {
      my $k = $j - 1;
      $cmd .= " CDEF:tcpu_tmp${j}=cpu${j},cpubor${j},+";
      $cmd .= " CDEF:tcpu${j}=tcpu_tmp${j},tcpu${k},+";
    }
  }
  if ( $j > 0 ) {
    $j--;
  }
  my $cpu_pool_total = "Total available in pools";
  for ( my $k = length($cpu_pool_total); $k < 35; $k++ ) {
    $cpu_pool_total .= " ";
  }

  $cmd .= " CDEF:tcpun${j}=tcpu${j},0,EQ,UNKN,tcpu${j},IF";
  $cmd .= " LINE2:tcpun${j}#888888:\\\"$cpu_pool_total\\\"";

  #$cmd .= " GPRINT:tcpu${j}:AVERAGE:\\\"%6.2lf \\\"";
  # excluded as it is a bit misleading there there is any even small data gap
  $cmd .= " GPRINT:tcpun${j}:MAX:\\\"          %6.2lf \\l\\\"";
  $cmd .= $cmdq;
  $cmd .= " PRINT:tcpun${j}:MAX:\\\"         %6.2lf MAXTCPU $delimiter\\\"";

  if ( defined $cmd_max && $cmd_max ne '' ) {
    $cmd .= $cmd_max;
    my $cpu_max_space = sprintf( "%-35s", "Total maximum" );

    if ( $graph_cmd =~ m/graphv$/ ) {
      $cmd .= " LINE1:main_res${y_max}#0088FF:\\\"$cpu_max_space\\\":dashes=1,2";
    }
    else {
      # RRDTool 1.2.x does not support dashed lines
      $cmd .= " LINE1:main_res${y_max}#0088FF:\\\"$cpu_max_space\\\"";
    }
    $cmd .= " GPRINT:main_res${y_max}:MAX:\\\"          %6.2lf \\l\\\"";
    $cmd .= " PRINT:main_res${y_max}:MAX:\\\"          %6.2lf MAXCPUMAX $delimiter\\\"";
  }

  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my $FH;

  # my $tmp_file = "$tmpdir/multi-hmc-$host-$type.cmd";
  open( FH, "> $tmp_file" ) || error( " Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  return 1;    # do not execute the cmd itself

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret = `$rrdtool - < "$tmp_file" 2>&1`;

  #my $ret  = `echo  "$cmd" | $rrdtool - 2>&1`;
  if ( $ret =~ "ERROR" ) {
    error("$host: Multi graph rrdtool error : $ret");
    if ( $ret =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $ret );
      error("Removing as it seems to be corrupted: $file");
      unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    else {
      error("$host: $cmd: Pool multi graph rrdtool error : $ret");
    }
  }

  #unlink ("$tmp_file"); --> do not remove, it is used for details

  return 0;
}

sub frame_multi_total {
  my ( $text, $type_sam, $type, $xgrid ) = @_;

  # e.g. frame_multi( "day",   "m", "d", "MINUTE:60:HOUR:2:HOUR:4:0:%H" );

  my $file = "";
  my $i    = 0;
  my $cmd  = "";
  my $cmdq = "";
  my $j    = 0;
  my $managed_ok;
  my $managedname_exl = "";
  my $managedname     = "";
  my @m_excl          = "";
  my $req_time        = 0;
  my $act_time        = time();
  my $name            = "$webdir/$host/pool-multi-$type-total";
  $step = $STEP;

  my $tmp_file  = "$tmpdir/multi-hmc-$host-$type-total.cmd";
  my $skip_time = 0;
  if ( "$type" =~ "d" ) {
    $req_time = $act_time - 86400;
  }
  if ( "$type" =~ "w" ) {
    $req_time  = $act_time - 604800;
    $skip_time = $WEEK_REFRESH;
  }
  if ( "$type" =~ "m" ) {
    $req_time  = $act_time - 2764800;
    $skip_time = $MONTH_REFRESH;
  }
  if ( "$type" =~ "y" ) {
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  print "creating m_hmc : $host:$type-total\n" if $DEBUG;
  my $header = "$host aggregated cpu total: last $text";

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"CPU cores\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"Utilization in CPU cores\\:               average   maximum\\l\\\"";

  my $gtype      = "AREA";
  my $color_indx = 0;
  my $i_max      = 0;
  my $y_max      = -1;
  my $cmd_max    = "";

  foreach my $line (@managednamelist) {
    chomp($line);
    if ( $line !~ ".*,.*,.*" ) {

      # it must look like : PWR6A-9117-MMA-SN103A4B0,9117-MMA,103A4B0, --> exclude banners
      next;
    }
    if ( $line =~ /No results were found/ ) {
      print "HMC : $host does not contain any managed system\n" if $DEBUG;
      return 0;
    }
    ( $managedname, my $model, my $serial ) = split( /,/, $line );

    if ( is_IP($managedname) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    $managed_ok = 1;
    if ( $managed_systems_exclude ne '' ) {
      @m_excl = split( /:/, $managed_systems_exclude );
      foreach $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managedname =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      next;
    }

    if ( $type_sam =~ "d" ) {
      $req_time = $act_time - 31536000;
    }
    $file = "pool_total.rrt";
    if ( "$type" =~ "d" ) {
      if ( -e "$wrkdir/$managedname/$host/pool_total.rrt" ) {
        $file = "pool_total.rrt";
      }
      $req_time = $act_time - 86400;
    }
    if ( "$type" =~ "w" ) {
      if ( -e "$wrkdir/$managedname/$host/pool_total.rrt" ) {
        $file = "pool_total.rrt";
      }
      if ( -e "$wrkdir/$managedname/$host/pool_total.rrt" ) {
        $file = "pool_total.rrt";
      }
      $req_time = $act_time - 604800;
    }
    if ( "$type" =~ "m" ) {
      if ( -e "$wrkdir/$managedname/$host/pool_total.rrt" ) {
        $file = "pool_total.rrt";
      }
      if ( -e "$wrkdir/$managedname/$host/pool_total.rrt" ) {
        $file = "pool_total.rrt";
      }
      $req_time = $act_time - 2764800;
    }
    if ( "$type" =~ "y" ) {
      if ( -e "$wrkdir/$managedname/$host/pool_total.rrt" ) {
        $file = "pool_total.rrt";
      }
      if ( -e "$wrkdir/$managedname/$host/pool_total.rrt" ) {
        $file = "pool_total.rrt";
      }
      if ( -e "$wrkdir/$managedname/$host/pool_total.rrt" ) {
        $file = "pool_total.rrt";
      }
    }

    if ( -e "$wrkdir/$managedname/$host/$file" ) {

      # avoid old servers which do not exist in the period
      my $rrd_upd_time = ( stat("$wrkdir/$managedname/$host/$file") )[9];
      if ( $rrd_upd_time < $req_time ) {
        next;
      }
    }
    else {
      # avoid non-existing managed systems (with no utillization data on)
      next;
    }

    my $managedname_space      = $managedname;
    my $managedname_space_proc = $managedname;
    $managedname_space_proc =~ s/:/\\:/g;
    $managedname_space_proc =~ s/%/%%/g;    # anti '%

    for ( my $k = length($managedname); $k < 35; $k++ ) {
      $managedname_space .= " ";
    }

    $managedname_space =~ s/:/\\:/g;        # anti ':'
    my $wrkdir_managedname_host_file = "$wrkdir/$managedname/$host/$file";
    $wrkdir_managedname_host_file =~ s/:/\\:/g;
    my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
    $wrkdir_managedname_host_file_legend =~ s/%/%%/g;

    # bulid RRDTool cmd
    my $csp = PowerDataWrapper::get_server_metric( $managedname, "ConfigurableSystemProcessorUnits", 0 );
    $cmd .= " DEF:configured${i}=\\\"$wrkdir_managedname_host_file\\\":configured:AVERAGE";
    $cmd .= " DEF:curr_proc_units${i}=\\\"$wrkdir_managedname_host_file\\\":curr_proc_units:AVERAGE";
    $cmd .= " DEF:entitled_cycles${i}=\\\"$wrkdir_managedname_host_file\\\":entitled_cycles:AVERAGE";
    $cmd .= " DEF:capped_cycles${i}=\\\"$wrkdir_managedname_host_file\\\":capped_cycles:AVERAGE";
    $cmd .= " DEF:uncapped_cycles${i}=\\\"$wrkdir_managedname_host_file\\\":uncapped_cycles:AVERAGE";

    # if it does not exist for some time period then put 0 there
    $cmd .= " CDEF:tot${i}=capped_cycles${i},uncapped_cycles${i},+";
    $cmd .= " CDEF:util${i}=tot${i},entitled_cycles${i},/,$cpu_max_filter,GT,UNKN,tot${i},entitled_cycles${i},/,IF";
    $cmd .= " CDEF:utilperct${i}=util${i},100,*";
    $cmd .= " CDEF:utiltot${i}=util${i},curr_proc_units${i},*";
    $cmd .= " CDEF:utiltest${i}=utiltot${i},configured${i},GT,UNKN,utiltot${i},IF";

    $cmd  .= " PRINT:utiltest${i}:AVERAGE:\"%6.2lf $delimiter multihmcframe $delimiter $managedname_space_proc $delimiter $color[$color_indx] $delimiter $wrkdir_managedname_host_file_legend\"";
    $cmd  .= " PRINT:utiltest${i}:MAX:\" %6.2lf $delimiter\"";
    $cmdq .= " $gtype:utiltest${i}$color[$color_indx++]:\\\"$managedname_space\\\"";
    $cmdq .= " GPRINT:utiltest${i}:AVERAGE:\\\"%6.2lf \\\"";
    $cmdq .= " GPRINT:utiltest${i}:MAX:\\\"%6.2lf \\\"";
    $gtype = "STACK";
    $i++;

    # rrd max for pools
    my $rrd_max = "pool_total.rxm";
    if ( -e "$wrkdir/$managedname/$host/$rrd_max" ) {

      my $wrkdir_managedname_host_file_max = "$wrkdir/$managedname/$host/$rrd_max";
      $wrkdir_managedname_host_file_max =~ s/:/\\:/g;

      # bulid RRDTool cmd
      #      $cmd_max .= " DEF:totcyc_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":total_pool_cycles:MAX";
      #      $cmd_max .= " DEF:uticyc_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":utilized_pool_cyc:MAX";
      #      $cmd_max .= " DEF:ncpu_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":conf_proc_units:MAX";
      #      $cmd_max .= " DEF:ncpubor_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":bor_proc_units:MAX";

      $cmd_max .= " DEF:configured_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":configured:MAX";
      $cmd_max .= " DEF:curr_proc_units_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":curr_proc_units:MAX";
      $cmd_max .= " DEF:entitled_cycles_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":entitled_cycles:MAX";
      $cmd_max .= " DEF:capped_cycles_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":capped_cycles:MAX";
      $cmd_max .= " DEF:uncapped_cycles_max${i_max}=\\\"$wrkdir_managedname_host_file_max\\\":uncapped_cycles:MAX";

      $cmd_max .= " CDEF:tot_max${i_max}=capped_cycles_max${i_max},uncapped_cycles_max${i_max},+";
      $cmd_max .= " CDEF:util_max${i_max}=tot${i_max},entitled_cycles_max${i_max},/,$cpu_max_filter,GT,UNKN,tot_max${i_max},entitled_cycles_max${i_max},/,IF";
      $cmd_max .= " CDEF:utilperct_max${i_max}=util_max${i_max},100,*";
      $cmd_max .= " CDEF:utiltot_max${i_max}=util_max${i_max},curr_proc_units_max${i_max},*";
      $cmd_max .= " CDEF:utiltest_max${i_max}=utiltot_max${i_max},configured${i_max},GT,UNKN,utiltot_max${i_max},IF";

      # if it does not exist for some time period then put 0 there
      #$cmd_max .= " CDEF:cpu_max${i_max}=ncpu_max${i_max},UN,0,ncpu_max${i_max},IF";
      #$cmd_max .= " CDEF:cpubor_max${i_max}=ncpubor_max${i_max},UN,0,ncpubor_max${i_max},IF";
      #$cmd_max .= " CDEF:totcpu_max${i_max}=cpu_max${i_max},cpubor_max${i_max},+";
      #$cmd_max .= " CDEF:cpuutil_max${i_max}=uticyc_max${i_max},totcyc_max${i_max},GT,UNKN,uticyc_max${i_max},totcyc_max${i_max},/,IF";
      #$cmd_max .= " CDEF:cpuutiltot_max${i_max}=cpuutil_max${i_max},totcpu_max${i_max},*";

      if ( $i_max == 0 ) {
        $cmd_max .= " CDEF:main_res${i_max}=utiltest_max${i_max}";
      }
      else {
        $cmd_max .= " CDEF:pom${i_max}=main_res${y_max},UN,0,main_res${y_max},IF,utiltest_max${i_max},UN,0,utiltest_max${i_max},IF,+";
        $cmd_max .= " CDEF:main_res${i_max}=main_res${y_max},UN,utiltest_max${i_max},UN,UNKN,pom${i_max},IF,pom${i_max},IF";
      }

      $i_max++;
      $y_max++;
    }

    if ( $color_indx > $color_max ) {
      $color_indx = 0;
    }
  }

  if ( $i == 0 ) {

    # no available managed system
    return 1;
  }

  # add count of all CPU cores
  for ( $j = 0; $j < $i; $j++ ) {
    if ( $j == 0 ) {
      $cmd .= " CDEF:tcpu${j}=configured${j},0,+";
    }
    else {
      my $k = $j - 1;
      $cmd .= " CDEF:tcpu_tmp${j}=configured${j},0,+";
      $cmd .= " CDEF:tcpu${j}=tcpu_tmp${j},tcpu${k},+";
    }
  }
  if ( $j > 0 ) {
    $j--;
  }
  my $cpu_pool_total = "Total available cores";
  for ( my $k = length($cpu_pool_total); $k < 35; $k++ ) {
    $cpu_pool_total .= " ";
  }

  $cmd .= " CDEF:tcpun${j}=tcpu${j},0,EQ,UNKN,tcpu${j},IF";
  $cmd .= " LINE2:tcpu${j}#888888:\\\"$cpu_pool_total\\\"";    #here

  #$cmd .= " GPRINT:tcpu${j}:AVERAGE:\\\"%6.2lf \\\"";
  # excluded as it is a bit misleading there there is any even small data gap
  $cmd .= " GPRINT:tcpun${j}:MAX:\\\"          %6.2lf \\l\\\"";
  $cmd .= $cmdq;
  $cmd .= " PRINT:tcpun${j}:MAX:\\\"         %6.2lf MAXTCPU $delimiter\\\"";

  if ( defined $cmd_max && $cmd_max ne '' ) {
    $cmd .= $cmd_max;
    my $cpu_max_space = sprintf( "%-35s", "Total maximum" );

    if ( $graph_cmd =~ m/graphv$/ ) {
      $cmd .= " LINE1:main_res${y_max}#0088FF:\\\"$cpu_max_space\\\":dashes=1,2";
    }
    else {
      # RRDTool 1.2.x does not support dashed lines
      $cmd .= " LINE1:main_res${y_max}#0088FF:\\\"$cpu_max_space\\\"";
    }
    $cmd .= " GPRINT:main_res${y_max}:MAX:\\\"          %6.2lf \\l\\\"";
    $cmd .= " PRINT:main_res${y_max}:MAX:\\\"          %6.2lf MAXCPUMAX $delimiter\\\"";
  }

  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my $FH;

  # my $tmp_file = "$tmpdir/multi-hmc-$host-$type.cmd";
  open( FH, "> $tmp_file" ) || error( " Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  return 1;    # do not execute the cmd itself

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret = `$rrdtool - < "$tmp_file" 2>&1`;

}

# LPARs aggregated per a HMC
sub multiview_hmc {
  my ( $host, $name_part, $type, $type_sam, $act_time, $text, $xgrid ) = @_;

  #e.g. multiview_hmc( $host, "lpar-multi", "d", "m", $time, "day",   "MINUTE:60:HOUR:2:HOUR:4:0:%H" );

  my $req_time = 0;
  my $file     = "";
  my $i        = 0;
  my $lpar     = "";
  my $cmd      = "";
  my $j        = 0;
  my $name     = "$webdir/$host/$name_part-$type";    # out graph file name

  $act_time = time();                                 # cus it can be wrong fromat from call
  my $tmp_file  = "$tmpdir/multi-hmc-lpar-$host-$type.cmd";
  my $skip_time = 0;
  if ( "$type" =~ "d" ) {
    $req_time = $act_time - 86400;
  }
  if ( "$type" =~ "w" ) {
    $req_time  = $act_time - 604800;
    $skip_time = $WEEK_REFRESH;
  }
  if ( "$type" =~ "m" ) {
    $req_time  = $act_time - 2764800;
    $skip_time = $MONTH_REFRESH;
  }
  if ( "$type" =~ "y" ) {
    $req_time  = $act_time - 31536000;
    $skip_time = $YEAR_REFRESH;
  }

  # do not update weekly/monthly/yearly command files each run
  if ( -f "$tmp_file" ) {
    my $tmp_time = ( stat("$tmp_file") )[9];
    if ( ( $act_time - $tmp_time ) < $skip_time ) {
      print "                        skipped this time : ( $act_time - $tmp_time ) < $skip_time \n";
      return 0;
    }
  }

  print "creating l_hmc : $host:$type - LPARs aggregated per a HMC\n" if $DEBUG;
  my $header = "LPARs aggregated per $host: last $text";

  if ( "$type" =~ "d" ) {
    $req_time = $act_time - 86400;
  }
  if ( "$type" =~ "w" ) {
    $req_time = $act_time - 604800;
  }
  if ( "$type" =~ "m" ) {
    $req_time = $act_time - 2764800;
  }

  # for daily, must be even type as for IVM/SDMC it is not in $type_sam =~ "d"
  if ( $type_sam =~ "d" || "$type" =~ "y" ) {
    $req_time = $act_time - 31536000;
  }

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type";
  $cmd .= " --end now-1$type+1$type";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$STEP";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " --vertical-label=\\\"CPU cores\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " COMMENT:\\\"Utilization in CPU cores                       \\l\\\"";
  $cmd .= " COMMENT:\\\"  Server                       LPAR                    avrg     max\\l\\\"";

  my $gtype = "AREA";

  # it will be used for creating files with colors for detail_graph_cgi.pl use server lpars aggregated
  my $file_top = "$tmpdir/topten.tmp";
  open( my $FHCPU, "< $file_top" );    #|| error( "Can't open $cpu_file : $!" . __FILE__ . ":" . __LINE__ );
  my @topten = <$FHCPU>;
  close($FHCPU);

  foreach my $line (@managednamelist) {

    # goes through all servers of each HMC

    chomp($line);
    if ( $line !~ ".*,.*,.*" ) {

      # it must look like : PWR6A-9117-MMA-SN103A4B0,9117-MMA,103A4B0, --> exclude banners
      next;
    }
    if ( $line =~ /No results were found/ ) {
      print "HMC : $host does not contain any managed system\n" if $DEBUG;
      return 0;
    }
    ( $managedname, my $model, my $serial ) = split( /,/, $line );

    if ( is_IP($managedname) == 1 ) {
      next;    # wrong entry from the HMC, a problem of the HMC or unconfigured server yet
    }

    my $managed_ok = 1;
    if ( $managed_systems_exclude ne '' ) {
      my @m_excl = split( /:/, $managed_systems_exclude );
      foreach my $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $managedname =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      next;
    }

    opendir( DIR, "$wrkdir/$managedname/$host" ) || error( " directory does not exists : $wrkdir/$managedname/$host  " . __FILE__ . ":" . __LINE__ ) && return 0;
    my @files = "";
    if ( $type_sam =~ "m" ) {
      my @files_unsorted = grep( /\.rrm$/, readdir(DIR) );
      @files = sort { lc $a cmp lc $b } @files_unsorted;
    }
    if ( $type_sam =~ "h" ) {
      my @files_unsorted = grep( /\.rrh$/, readdir(DIR) );
      @files = sort { lc $a cmp lc $b } @files_unsorted;
    }
    if ( $type_sam =~ "d" ) {
      my @files_unsorted = grep( /\.rrd$/, readdir(DIR) );
      @files    = sort { lc $a cmp lc $b } @files_unsorted;
      $req_time = $act_time - 31536000;
    }
    closedir(DIR);

    # get server cpu lines
    my $grep_expr     = "load_cpu,$managedname,";
    my @topten_server = grep ( /$grep_expr/, @topten );

    # print "@topten_server\n";

    #no warnings;
    # sort on year value
    # load_cpu,Power770,p770-demo.rrm,hmc,0.26,0.26,0.25,0.26

    my @topten_sorted_load_cpu = sort {
      my @b = split( /,/, $b );
      my @a = split( /,/, $a );
      $b[7] <=> $a[7] if ( defined $b[7] && defined( $a[7] ) );
    } @topten_server;

    # print "@topten_sorted_load_cpu\n";

    # prepare hash with lpar_name -> order
    my %CPU_topten_sorted_lpars;
    my $color_index = 0;
    foreach my $line (@topten_sorted_load_cpu) {
      ( undef, undef, my $lpar_name, undef ) = split ",", $line;
      $lpar_name =~ s/\..*//g;
      $CPU_topten_sorted_lpars{$lpar_name} = $color_index++;
    }

    # print Dumper (\%CPU_topten_sorted_lpars);

    my @color_save = "";

    foreach $file (@files) {

      # goes through all lpars of each server
      chomp($file);

      if ( $file =~ m/^\.rr/ ) {
        next;    # avoid .rrm
      }

      # avoid old lpars which do not exist in the period
      my $rrd_upd_time = ( stat("$wrkdir/$managedname/$host/$file") )[9];
      if ( $rrd_upd_time < $req_time ) {
        next;
      }

      $lpar = $file;
      $lpar =~ s/.rrh//;
      $lpar =~ s/.rrm//;
      $lpar =~ s/.rrd//;
      my $lpar_space      = $lpar;
      my $lpar_space_proc = $lpar;

      if ( $lpar eq '' ) {
        next;    # avoid .rrm --> just to be sure :)
      }

      # add spaces to lpar name to have 25 chars total (for formating graph legend)
      $lpar_space =~ s/\&\&1/\//g;
      for ( my $k = length($lpar_space); $k < 25; $k++ ) {
        $lpar_space .= " ";
      }

      # Exclude pools and memory
      if ( $lpar =~ m/^cod$/ || $lpar =~ m/^pool$/ || $lpar =~ m/^mem$/ || $lpar =~ /^SharedPool[0-9]$/ || $lpar =~ m/^SharedPool[1-9][0-9]$/ || $lpar =~ m/^mem-pool$/ ) {
        next;
      }

      # Assure that lpar colors is same for each lpar through daily - yearly charts
      my $l;
      my $l_count = 0;
      my $found   = -1;
      foreach $l (@keep_color_lpar) {
        if ( $l eq '' || $l =~ m/^ $/ ) {
          next;
        }
        if ( $l =~ m/^$lpar$/ ) {
          $found = $l_count;
          last;
        }
        $l_count++;
      }
      if ( $found == -1 ) {
        $keep_color_lpar[$l_count] = $lpar;
        $found = $l_count;
      }

      # take color from 0 to 53 -- division modulo
      $found = $found % $color_max;

      #print "$found $lpar $color[$found]\n";
      print "$wrkdir/$managedname/$host/$file $rrd_upd_time $req_time $act_time\n" if ( $DEBUG == 3 );

      my $server_name = $managedname;
      $server_name =~ s/\&\&1/\//g;
      my $server_name_space = $server_name;
      for ( my $k = length($server_name_space); $k < 25; $k++ ) {
        $server_name_space .= " ";
      }
      $server_name =~ s/:/\\:/g;
      $server_name =~ s/%/%%/g;

      $lpar_space = $server_name_space . "    " . $lpar_space;

      $lpar_space      =~ s/:/\\:/g;    # anti ':'
      $lpar_space_proc =~ s/:/\\:/g;
      $lpar_space_proc =~ s/%/%%/g;     # anti '%

      my $wrkdir_managedname_host_file = "$wrkdir/$managedname/$host/$file";
      $wrkdir_managedname_host_file =~ s/:/\\:/g;
      my $wrkdir_managedname_host_file_legend = $wrkdir_managedname_host_file;
      $wrkdir_managedname_host_file_legend =~ s/%/%%/g;

      # bulid RRDTool cmd
      $cmd .= " DEF:cap${i}=\\\"$wrkdir_managedname_host_file\\\":capped_cycles:AVERAGE";
      $cmd .= " DEF:uncap${i}=\\\"$wrkdir_managedname_host_file\\\":uncapped_cycles:AVERAGE";
      $cmd .= " DEF:ent${i}=\\\"$wrkdir_managedname_host_file\\\":entitled_cycles:AVERAGE";
      $cmd .= " DEF:cur${i}=\\\"$wrkdir_managedname_host_file\\\":curr_proc_units:AVERAGE";

      $cmd .= " CDEF:tot${i}=cap${i},uncap${i},+";

      #  $cmd .= " CDEF:util${i}=tot${i},ent${i},/";
      $cmd .= " CDEF:util${i}=tot${i},ent${i},/,$cpu_max_filter,GT,UNKN,tot${i},ent${i},/,IF";
      $cmd .= " CDEF:utiltot${i}=util${i},cur${i},*";                                            # since 4.74-  (u)
                                                                                                 # next line not necessary when you start with AREA
                                                                                                 # $cmd .= " CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF";
      $cmd .= " $gtype:utiltot${i}$color[$found]:\\\"$lpar_space\\\"";

      push @color_save, $lpar;

      $cmd .= " PRINT:utiltot${i}:AVERAGE:\"%3.2lf $delimiter multihmclpar $delimiter $server_name $delimiter $lpar_space_proc\"";
      $cmd .= " PRINT:utiltot${i}:AVERAGE:\\\"%3.2lf $delimiter $color[$found] $delimiter $wrkdir_managedname_host_file_legend\\\"";
      $cmd .= " PRINT:utiltot${i}:MAX:\" %3.2lf $delimiter\"";

      $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%3.2lf \\\"";
      $cmd .= " GPRINT:utiltot${i}:MAX:\\\" %3.2lf \\l\\\"";

      # put carriage return after each second lpar in the legend
      if ( $j == 1 ) {
        $j = 0;
      }
      else {
        #$cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%3.2lf \\t\\\"";
        # --> it does not work ideally with newer RRDTOOL (1.2.30 --> it needs to be separated by cariage return here)
        $j++;
      }
      $gtype = "STACK";
      $i++;
    }

    # write colors into a file for detail-graph-cgi.pl
    if ( "$type" =~ "y" ) {
      open( FHC, "> $wrkdir/$managedname/$host/lpars.col" ) || error( "file does not exists : $wrkdir/$managedname/$host/lpars.col " . __FILE__ . ":" . __LINE__ ) && return 0;

      # $color_index now contains color number for next item, which is not in %CPU_topten_sorted_lpars
      foreach my $lpar_name (@color_save) {
        chomp($lpar_name);    # it must be there, somehow appear there \n ...
        if ( $lpar_name eq '' ) {
          next;
        }
        my $num_col_lpar_write = $CPU_topten_sorted_lpars{$lpar_name};
        if ( !defined $num_col_lpar_write || $num_col_lpar_write eq "" ) {
          $num_col_lpar_write = $color_index++;
        }
        $num_col_lpar_write = $num_col_lpar_write % $color_max;
        print FHC "$num_col_lpar_write : $lpar_name\n";

        # print "$num_col_lpar_write : $lpar_name\n";
      }

      close(FHC);
    }

  }
  if ( "$type" =~ "d" ) {
    if ( $j == 1 ) {
      $cmd .= " COMMENT:\\\" \\l\\\"";
    }
    $cmd .= " COMMENT:\\\"\(Note that for CPU dedicated LPARs is always shown their whole entitlement\)\\\"";
  }
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my $FH;

  # my $tmp_file = "$tmpdir/multi-hmc-lpar-$host-$type.cmd";
  open( FH, "> $tmp_file" ) || error( " Can't open $tmp_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$cmd\n";
  close(FH);

  return 1;    # do not execute the cmd itself

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret = `$rrdtool - < "$tmp_file" 2>&1`;

  #my $ret  = `echo  "$cmd" | $rrdtool - 2>&1`;
  if ( $ret =~ "ERROR" ) {
    error("$host : Multi graph rrdtool error : $ret");
    if ( $ret =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $ret );
      error("Removing as it seems to be corrupted: $file");
      unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    else {
      error("$host: $cmd : Multi graph rrdtool error : $ret");
    }
  }

  #unlink ("$tmp_file"); --> do not remove!!! used for details

  return 0;
}

sub once_a_day {
  my $version_file = shift;

  # at first check whether it is a first run after the midnight
  if ( !-f $version_file ) {

    #error("version file er: $version_file does not exist, it should not happen, creating it");
    `touch $version_file`;
    `touch $version_file-LPM`;
    LoadDataModule::touch("$version_file does not exist");
  }
  else {
    my $run_time = ( stat("$version_file") )[9];
    ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
    ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
    if ( $aday != $png_day ) {
      LoadDataModule::touch("first run after the midnight: $aday != $png_day");
      `touch $version_file`;
      `touch $version_file-LPM`;    # run LPM search at least once a day
    }
  }
  return 1;
}

# it returns SMT detail if the OS agent provides it (4.70.7+)
sub get_smt_details {
  my ( $wrkdir, $server, $lpar ) = @_;

  my $server_space = $server;
  my $lpar_space   = $lpar;

  # check if exists data/server/hmc/lpar/cpu.txt where the OS agent saves SMT
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }
  if ( $lpar =~ m/ / ) {
    $lpar_space = "\"" . $lpar . "\"";        # it must be here to support space with server names
  }

  my @cpu_files = <$wrkdir/$server_space/*/$lpar_space/cpu.txt>;
  foreach my $cpu_file (@cpu_files) {
    chomp($cpu_file);
    open( FHCPU, "< $cpu_file" ) || error( "Can't open $cpu_file : $!" . __FILE__ . ":" . __LINE__ );
    my @smt = <FHCPU>;
    close(FHCPU);
    foreach my $line (@smt) {
      chomp($line);
      if ( isdigit($line) ) {
        return $line;
      }
    }
  }

  return -1;
}

sub pool_translate {
  my $wrkdir           = shift;
  my $host             = shift;
  my $managedname      = shift;
  my $pool_name_search = shift;

  open( FR, "<$wrkdir/$managedname/$host/cpu-pools-mapping.txt" ) || error( "Can't open $wrkdir/$managedname/$host/cpu-pools-mapping.txt : $!" . __FILE__ . ":" . __LINE__ ) && return $pool_name_search;
  foreach my $linep (<FR>) {
    chomp($linep);
    ( my $id, my $pool_name ) = split( /,/, $linep );
    if ( isdigit($id) && $pool_name =~ m/^$pool_name_search$/ ) {
      my $host_url        = urlencode($host);
      my $managedname_url = urlencode($managedname);
      my $pool_link       = "<A HREF=\"/lpar2rrd-cgi/detail.sh?host=$host_url&server=$managedname_url&lpar=SharedPool$id&item=shpool&entitle=0&gui=1&none=none\">&nbsp;&nbsp;$pool_name</A>";
      close(FR);
      return $pool_link;
    }
  }
  close(FR);
  return $pool_name_search;
}

sub urlencode {
  my $s = shift;
  $s =~ s/([^a-zA-Z0-9!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  return $s;
}

sub read_json {
  my $src = shift;
  if ( !defined $src || $src eq "" ) {
    error( "Not defined \$src " . __FILE__ . ":" . __LINE__ ) && return -1;
  }
  my $read;
  my $rawcfg;    # helper for file reading
                 # read from JSON file
  if ( open( CFG, "$src" ) ) {
    local $/ = undef;    # required for re-read of encode_json pretty output
    $rawcfg = <CFG>;
    if ($rawcfg) {
      eval { $read = decode_json($rawcfg); };
      if ($@) {
        error( "Error while decoding json : $src $! " . __FILE__ . ":" . __LINE__ );
        return -1;
      }
    }
    close CFG;
    return $read;
  }
  else {
    # error handling
    error( "Cannot open $src" . " File: " . __FILE__ . ":" . __LINE__ );
    return -1;
  }
}

sub is_host_rest {
  my $host  = shift;
  my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };
  foreach my $alias ( keys %hosts ) {
    if ( $host eq $hosts{$alias}{host} || ( defined $hosts{$alias}{hmc2} && $host eq $hosts{$alias}{hmc2} ) ) {
      if ( defined $hosts{$alias}{auth_api} && $hosts{$alias}{auth_api} ) {
        return 1;
      }
      else {
        return 0;
      }
      return $hosts{$alias}{auth_api};
    }
  }
}

sub is_server_excluded_from_rest {
  my $managedname      = shift;
  my $excluded_servers = shift;
  foreach my $e ( @{$excluded_servers} ) {
    if ( $managedname eq $e->{name} ) {
      if ( $e->{exclude_data_load} ) {
        return 1;
      }
    }
  }
  return 0;
}

sub write_hmc_version {
  my $version = shift;
  my $hmc     = shift;

  chomp($version);
  open FH, ">$basedir/tmp/HMC-version-$hmc.txt" or error( "can't open '$basedir/tmp/HMC-version-$hmc.txt': $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH "$version\n";
  close FH;
}
