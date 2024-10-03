use warnings;
use strict;
use Date::Parse;
use POSIX qw(strftime);
use PowerDataWrapper;
use PowerMenu;
use Data::Dumper;
use Menu;

# it runs only if not exist tmp/ent-run or it has previous day timestamp

# set unbuffered stdout
$| = 1;

# get cmd line params
my $version = "$ENV{version}";
my $webdir  = $ENV{WEBDIR};
my $bindir  = $ENV{BINDIR};
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $cpu_max_filter = 100;    # max 10k peak in % is allowed (in fact it cann by higher than 1k now when 1 logical CPU == 0.1 entitlement
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}

my $entitle_less = 0;
if ( defined $ENV{ENTITLEMENT_LESS} ) {
  $entitle_less = $ENV{ENTITLEMENT_LESS};
}
my $rrdtool   = $ENV{RRDTOOL};
my $DEBUG     = $ENV{DEBUG};
my $MAX_ENT   = $ENV{MAX_ENT};
my $upgrade   = $ENV{UPGRADE};
my $csv_separ = ";";             # CSV separator
if ( defined $ENV{CSV_SEPARATOR} ) {
  $csv_separ = $ENV{CSV_SEPARATOR};    # CSV separator
}

my $step_interval = 600;               # seconds
if ( defined $ENV{STEP_INTERVAL} ) { $step_interval = $ENV{STEP_INTERVAL} }
my $step_interval_min = $step_interval / 60;    # minutes

my ( $SERV, $CONF ) = PowerDataWrapper::init();

#$DEBUG = 2;
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $wrkdir                  = "$basedir/data";
my $ent_log                 = "$basedir/logs/entitle-check.log";     # log output
my $ent_html                = "$webdir/cpu_max_check.html";          # html ouput of the last run
my $ent_html_gui            = "$webdir/gui-cpu_max_check.html";      # html ouput of the last run
my $ent_csv_daily           = "cpu_config_advisor_daily.csv";        # CSV daily
my $ent_csv_weekly          = "cpu_config_advisor_weekly.csv";       # CSV weekly
my $ent_csv_monthly         = "cpu_config_advisor_monthly.csv";      # CSV monthly
my $ent_mem_csv_daily       = "mem_config_advisor_daily.csv";        # CSV daily
my $ent_mem_csv_weekly      = "mem_config_advisor_weekly.csv";       # CSV weekly
my $ent_mem_csv_monthly     = "mem_config_advisor_monthly.csv";      # CSV monthly
my $ent_csv_daily_all       = "$webdir/$ent_csv_daily";
my $ent_csv_weekly_all      = "$webdir/$ent_csv_weekly";
my $ent_csv_monthly_all     = "$webdir/$ent_csv_monthly";
my $ent_mem_csv_daily_all   = "$webdir/$ent_mem_csv_daily";
my $ent_mem_csv_weekly_all  = "$webdir/$ent_mem_csv_weekly";
my $ent_mem_csv_monthly_all = "$webdir/$ent_mem_csv_monthly";
my $ent_io_csv_monthly      = "io_config_advisor_monthly.csv";       # not used yet
my $ent_io_csv_all          = "$webdir/$ent_io_csv_monthly";         # not used yet
my $ent_week_html           = "$webdir/cpu_max_check_week.html";     # html ouput of the last run
my $ent_month_html          = "$webdir/cpu_max_check_month.html";    # html ouput of the last run
my $ent_run                 = "$tmpdir/ent-run";
my $act_time                = localtime();
my $filter_max_paging       = 100000000;                             # 100MB/sec, filter values above as this is most probably caused by a counter reset (lpar restart)
if ( defined $ENV{FILTER_MAX_PAGING} ) { $filter_max_paging = $ENV{FILTER_MAX_PAGING} }

my $MEM_ADD_CRIT = 15;                                               # add % of RAM
my $MEM_ADD_LIM  = 12;                                               # add % of RAM
my $MEM_ADD      = 10;                                               # add % of RAM
my $MEM_SAFE_LIM = 80;                                               # limit in % for mem peak where is safe for decrease of memory

my $MEM_PEAK_CRIT = 97;
my $MEM_PEAK_WARN = 93;
my $MEM_PEAK_LIM  = 93;
my $MEM_AVRG_CRIT = 95;
my $MEM_AVRG_WARN = 90;
my $MEM_AVRG_LIM  = 85;
my $MEM_PEAK_LOW  = 70;

my $PGS_UTIL_CRIT = 90;
my $PGS_UTIL_LIM  = 80;
my $PGS_PEAK_CRIT = 4096;
my $PGS_PEAK_LIM  = 512;
my $PGS_AVRG_CRIT = 100;
my $PGS_AVRG_LIM  = 10;

# IO wait peaks and average in %
my $IO_PEAK_MAX  = 10;
my $IO_AVRG_MAX  = 1;
my $IO_PEAK_WARN = 20;
my $IO_AVRG_WARN = 5;
my $IO_AVRG_CRIT = 10;

if ( defined $ENV{MEM_ADD_CRIT} )  { $MEM_ADD_CRIT  = $ENV{MEM_ADD_CRIT} }
if ( defined $ENV{MEM_ADD_LIM} )   { $MEM_ADD_LIM   = $ENV{MEM_ADD_LIM} }
if ( defined $ENV{MEM_ADD} )       { $MEM_ADD       = $ENV{MEM_ADD} }
if ( defined $ENV{MEM_SAFE_LIM} )  { $MEM_SAFE_LIM  = $ENV{MEM_SAFE_LIM} }
if ( defined $ENV{MEM_PEAK_CRIT} ) { $MEM_PEAK_CRIT = $ENV{MEM_PEAK_CRIT} }
if ( defined $ENV{MEM_PEAK_WARN} ) { $MEM_PEAK_WARN = $ENV{MEM_PEAK_WARN} }
if ( defined $ENV{MEM_PEAK_LIM} )  { $MEM_PEAK_LIM  = $ENV{MEM_PEAK_LIM} }
if ( defined $ENV{MEM_AVRG_CRIT} ) { $MEM_AVRG_CRIT = $ENV{MEM_AVRG_CRIT} }
if ( defined $ENV{MEM_AVRG_WARN} ) { $MEM_AVRG_WARN = $ENV{MEM_AVRG_WARN} }
if ( defined $ENV{MEM_AVRG_LIM} )  { $MEM_AVRG_LIM  = $ENV{MEM_AVRG_LIM} }
if ( defined $ENV{MEM_PEAK_LOW} )  { $MEM_PEAK_LOW  = $ENV{MEM_PEAK_LOW} }
if ( defined $ENV{PGS_UTIL_CRIT} ) { $PGS_UTIL_CRIT = $ENV{PGS_UTIL_CRIT} }
if ( defined $ENV{PGS_UTIL_LIM} )  { $PGS_UTIL_LIM  = $ENV{PGS_UTIL_LIM} }
if ( defined $ENV{PGS_PEAK_CRIT} ) { $PGS_PEAK_CRIT = $ENV{PGS_PEAK_CRIT} }
if ( defined $ENV{PGS_PEAK_LIM} )  { $PGS_PEAK_LIM  = $ENV{PGS_PEAK_LIM} }
if ( defined $ENV{PGS_AVRG_CRIT} ) { $PGS_AVRG_CRIT = $ENV{PGS_AVRG_CRIT} }
if ( defined $ENV{PGS_AVRG_LIM} )  { $PGS_AVRG_LIM  = $ENV{PGS_AVRG_LIM} }
if ( defined $ENV{IO_PEAK_MAX} )   { $IO_PEAK_MAX   = $ENV{IO_PEAK_MAX} }
if ( defined $ENV{IO_AVRG_MAX} )   { $IO_AVRG_MAX   = $ENV{IO_AVRG_MAX} }
if ( defined $ENV{IO_PEAK_WARN} )  { $IO_PEAK_WARN  = $ENV{IO_PEAK_WARN} }
if ( defined $ENV{IO_AVRG_WARN} )  { $IO_AVRG_WARN  = $ENV{IO_AVRG_WARN} }
if ( defined $ENV{IO_AVRG_CRIT} )  { $IO_AVRG_CRIT  = $ENV{IO_AVRG_CRIT} }

my $DAY            = 86400;
my $WEEK           = 604800;
my $MONTH          = 2592000;
my $color          = "bgcolor=\"#FF4040\"";
my $color_warning  = "bgcolor=\"#FFFF80\"";
my $color_recomend = "bgcolor=\"#FFAAAA\"";
my $color_panic    = "bgcolor=\"#FF4040\"";
my $color_noted    = "bgcolor=\"#40FF40\"";

my $cfg = $ENV{ALERCFG};

#my $from_mail="lpar2rrd";
my $from_mail = "support\@gmail.com";
my $subject   = "High CPU utilization";
my $ltime_str = localtime();
my $ltime     = str2time($ltime_str);

my @day_dual_hmc_prevent = "";
my $day_dual_indx        = 0;
my @wee_dual_hmc_prevent = "";
my $wee_dual_indx        = 0;
my @mon_dual_hmc_prevent = "";
my $mon_dual_indx        = 0;

my @day_err_type        = "";
my @day_err_lpar_url    = "";
my @day_err_lpar        = "";
my @day_err_name        = "";
my @day_err_srv         = "";
my @day_err_hmc         = "";
my @day_err_max         = "";
my @day_err_max_reached = "";
my @day_err_avrg        = "";
my @day_err_entitle     = "";
my @day_err_mode        = "";
my @day_err_size        = "";
my @day_err_pg          = "";
my $day_err             = 0;

my @day_war_type        = "";
my @day_war_lpar_url    = "";
my @day_war_lpar        = "";
my @day_war_name        = "";
my @day_war_srv         = "";
my @day_war_hmc         = "";
my @day_war_max         = "";
my @day_war_max_reached = "";
my @day_war_avrg        = "";
my @day_war_entitle     = "";
my @day_war_mode        = "";
my @day_war_size        = "";
my @day_war_pg          = "";
my $day_war             = 0;

my @wee_err_type        = "";
my @wee_err_lpar_url    = "";
my @wee_err_lpar        = "";
my @wee_err_name        = "";
my @wee_err_srv         = "";
my @wee_err_hmc         = "";
my @wee_err_max         = "";
my @wee_err_max_reached = "";
my @wee_err_avrg        = "";
my @wee_err_entitle     = "";
my @wee_err_mode        = "";
my @wee_err_size        = "";
my @wee_err_pg          = "";
my $wee_err             = 0;

my @wee_war_type        = "";
my @wee_war_lpar_url    = "";
my @wee_war_lpar        = "";
my @wee_war_name        = "";
my @wee_war_srv         = "";
my @wee_war_hmc         = "";
my @wee_war_max         = "";
my @wee_war_max_reached = "";
my @wee_war_avrg        = "";
my @wee_war_entitle     = "";
my @wee_war_mode        = "";
my @wee_war_size        = "";
my @wee_war_pg          = "";
my $wee_war             = 0;

my @mon_err_type        = "";
my @mon_err_lpar_url    = "";
my @mon_err_lpar        = "";
my @mon_err_name        = "";
my @mon_err_srv         = "";
my @mon_err_hmc         = "";
my @mon_err_max         = "";
my @mon_err_max_reached = "";
my @mon_err_avrg        = "";
my @mon_err_entitle     = "";
my @mon_err_mode        = "";
my @mon_err_size        = "";
my @mon_err_pg          = "";
my $mon_err             = 0;

my @mon_war_type        = "";
my @mon_war_lpar_url    = "";
my @mon_war_lpar        = "";
my @mon_war_name        = "";
my @mon_war_srv         = "";
my @mon_war_hmc         = "";
my @mon_war_max         = "";
my @mon_war_max_reached = "";
my @mon_war_avrg        = "";
my @mon_war_entitle     = "";
my @mon_war_mode        = "";
my @mon_war_size        = "";
my @mon_war_pg          = "";
my $mon_war             = 0;

if ( $MAX_ENT eq '' ) {
  $MAX_ENT = 2;
}

# at first check whether it is a first run after the midnight
if ( once_a_day("$ent_run") == 0 ) {
  if ( isdigit($upgrade) == 1 && $upgrade == 1 ) {
    print "CPU cfg advisor: run it as first run after the upgrade : $upgrade\n";
  }
  else {
    exit(0);    # run just once a day per timestamp on $ent_run
  }
}

use RRDp;
RRDp::start "$rrdtool";

read_lpars();

create_html();

my $unixt = str2time($act_time);
$act_time = localtime();
my $unixt_end = str2time($act_time);
my $run_time  = $unixt_end - $unixt;
print "Finished       : $act_time, run time: $run_time secs\n";

sub read_lpars {
  my $act_time_u = time();

  foreach my $server_all (<$wrkdir/*>) {
    my $server = basename($server_all);
    next if $server =~ /^vmware_/;

    #print "00 $server\n";
    if ( !-d $server_all ) { next; }
    if ( -l $server_all )  { next; }
    my $server_space_all = $server_all;
    $server_space_all = "\"" . $server_all . "\"" if $server_all =~ / /;    # it must be here to support space with server names
    foreach my $hmc_all (<$server_space_all/*>) {
      my $hmc = basename($hmc_all);

      #print "02 $hmc\n";
      if ( !-d $hmc_all ) { next; }
      my $hmc_space_all = $hmc_all;
      $hmc_space_all = "\"" . $hmc_all . "\"" if $hmc_all =~ / /;           # it must be here to support space with server names
      foreach my $lpar_all (<$hmc_space_all/*rr[m|h]>) {
        my $lpar      = basename($lpar_all);
        my $lpar_name = $lpar;
        $lpar_name =~ s/\.rrm//;
        $lpar_name =~ s/\.rrh//;
        if ( $lpar_name =~ m/^pool$/ ) {
          pool_check( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u );
          next;
        }
        if ( $lpar_name =~ m/^SharedPool[1-9].*$/ ) {
          sh_pool_check( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u );
          next;
        }
        if ( $lpar_name =~ m/^SharedPool0/ || $lpar_name =~ m/^mem-pool$/ || $lpar_name =~ m/^mem$/ || $lpar_name =~ m/^cod$/ ) {
          next;    #exclude non lpars
        }

        lpar_check( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u );

      }
    }
  }
}

sub sh_pool_check {
  my $lpar_name  = shift;
  my $lpar_all   = shift;
  my $lpar       = shift;
  my $server     = shift;
  my $hmc        = shift;
  my $hmc_all    = shift;
  my $act_time_u = shift;

  my $uniq_name = $lpar_name . $server . "POOL";
  my $found     = 0;

  if ( !-f "$hmc_all/config.cfg" ) {

    #print "info           : config.cfg does not exists for $lpar, ignoring : $hmc_all/config.cfg\n";
    return 1;
  }

  my $lpar_name_id = $lpar_name;
  $lpar_name_id =~ s/SharedPool//;

  open( FC, "< $hmc_all/config.cfg" ) || error( "Can't open $hmc_all/config.cfg : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  my @lines = <FC>;
  close(FC);
  my $sh_res  = 0;
  my $sh_max  = 0;
  my $sh_name = "";
  $found = 0;
  foreach my $line (@lines) {
    chomp($line);
    if ( $line =~ m/name/ ) {
      $line =~ s/name//;
      $lpar_name = $line;
      next;
    }
    if ( $line =~ m/shared_proc_pool_id.*$lpar_name_id$/ ) {
      $found = 1;
      next;
    }
    if ( $found == 1 && $line =~ m/max_pool_proc_units.*/ ) {
      $line =~ s/max_pool_proc_units *//;
      $sh_max = $line;
      next;
    }
    if ( $found == 1 && $line =~ m/curr_reserved_pool_proc_units/ ) {
      $line =~ s/curr_reserved_pool_proc_units *//;
      $sh_res = $line;
      last;
    }
  }

  if ( $sh_max == 0 ) {

    #error ("max_pool_proc_units has not been found: $lpar : $hmc_all/config.cfg ".__FILE__.":".__LINE__);
    # do not report it ...
    return 1;
  }

  my $ret = 0;
  $ret = sh_pool_check_detail( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $sh_max, $sh_res, $DAY );

  #if ( $ret == 2 ) { return 2; }
  $ret = sh_pool_check_detail( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $sh_max, $sh_res, $WEEK );

  #if ( $ret == 2 ) { return 2; }
  sh_pool_check_detail( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $sh_max, $sh_res, $MONTH );

  return 0;
}

sub sh_pool_check_detail {
  my $lpar_name     = shift;
  my $lpar_all      = shift;
  my $lpar          = shift;
  my $server        = shift;
  my $hmc           = shift;
  my $hmc_all       = shift;
  my $act_time_u    = shift;
  my $uniq_name     = shift;
  my $sh_max        = shift;
  my $sh_res        = shift;
  my $time_range    = shift;
  my $lpar_name_org = $lpar_name;
  my $found         = 0;
  my @dual          = "";
  my $sh_name       = $lpar;
  $sh_name =~ s/\..*//;

  if ( $time_range == $DAY ) {    # day
    @dual = @day_dual_hmc_prevent;
  }
  if ( $time_range == $WEEK ) {    #week
    @dual = @wee_dual_hmc_prevent;
  }
  if ( $time_range == $MONTH ) {    # month
    @dual = @mon_dual_hmc_prevent;
  }
  foreach my $name (@dual) {
    if ( $uniq_name =~ m/^$name$/ ) {
      $found = 1;
      last;
    }
  }

  if ( $found == 1 ) {
    return 0;                       # there has been already alert for that server & lpar --> probably dual HMC setup
  }

  my $rrd_time = ( stat("$lpar_all") )[9];
  if ( ( $act_time_u - $rrd_time ) > $time_range ) {
    return 0;
  }

  #print "001 sh_name:$sh_name lpar_all: $lpar_all lpar_name_org:$lpar_name_org lpar:$lpar lpar_name:$lpar_name\n";

  my $ret = get_sh_pool_peak( $lpar_all, "max", $time_range, 0 );    # max CPU
  if ( $ret > 0 ) {
    if ( $time_range == $DAY ) {                                     # day
                                                                     #print "SH POOL ERROR  : $lpar_name:$server:$hmc : shared pool has reached its max CPU $ret (limit:$sh_max)\n";
    }

    my $avrg = get_sh_pool_peak( $lpar_all, "res", $time_range, 1 );    # average
    update_struct( "Shared POOL", "ERROR", $time_range, $sh_name, $lpar_name, $server, $hmc, $sh_max, $uniq_name, $ret, $avrg, $sh_res, "na", -1, -1 );
    return 2;
  }

  if ( $sh_res == 0 ) {                                                 # there could be set reserved = 0; then ignore this check!!! Only max has a sense
    return 0;
  }

  $ret = get_sh_pool_peak( $lpar_all, "res", $time_range, 0 );          # entitle check: curr_proc_units
  if ( $ret > 0 ) {
    if ( $time_range == $DAY ) {                                        # day
                                                                        #print "SH POOL WARNING: $lpar_name:$server:$hmc : shared pool has reached its entitlement last day $ret (limit:$sh_res)\n";
    }

    my $avrg = get_sh_pool_peak( $lpar_all, "res", $time_range, 1 );    # average
    update_struct( "Shared POOL", "WARNING", $time_range, $sh_name, $lpar_name, $server, $hmc, $sh_max, $uniq_name, $ret, $avrg, $sh_res, "na", -1, -1 );
    return 1;
  }

  return 0;
}

sub get_sh_pool_peak {
  my $rrd        = shift;
  my $type       = shift;
  my $time_range = shift;
  my $time_end   = "now";
  my $avrg       = shift;

  if ( $time_range == $WEEK ) {    # week (time range last 7 days without last day
    $time_end = "now-$DAY";
    $time_end .= "s";
  }
  if ( $time_range == $MONTH ) {    # month (time range last 31 days without last week
    $time_end = "now-$WEEK";
    $time_end .= "s";
  }

  my $width = 1440 * ( $time_range / $DAY );    # to get 1 minute per a pixel
  $time_range =~ s/$/s/;

  if ( $avrg == 0 ) {
    if ( $type =~ m/max/ ) {
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$tmpdir/name.png"
        "--start" "now-$time_range"
        "--end" "$time_end"
        "--width=$width"
        "--step" "$step_interval"
        "DEF:max=$rrd:max_pool_units:AVERAGE"
        "DEF:res=$rrd:res_pool_units:AVERAGE"
        "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
        "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
        "CDEF:max1=max,res,-"
        "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
        "CDEF:cpuutiltot=cpuutil,max,*"
        "CDEF:result=cpuutiltot,max,LT,UNKN,cpuutiltot,IF"
        "PRINT:result:MAX: %3.3lf"
      );
    }
    else {
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$tmpdir/name.png"
        "--start" "now-$time_range"
        "--end" "$time_end"
        "--width=$width"
        "DEF:max=$rrd:max_pool_units:AVERAGE"
        "DEF:res=$rrd:res_pool_units:AVERAGE"
        "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
        "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
        "CDEF:max1=max,res,-"
        "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
        "CDEF:cpuutiltot=cpuutil,max,*"
        "CDEF:result=cpuutiltot,res,LT,UNKN,cpuutiltot,IF"
        "PRINT:result:MAX: %3.3lf"
      );
    }
  }
  else {
    # prints just avrg for given period
    $rrd =~ s/:/\\:/g;
    RRDp::cmd qq(graph "$tmpdir/name.png"
      "--start" "now-$time_range"
      "--end" "$time_end"
      "--width=$width"
      "DEF:max=$rrd:max_pool_units:AVERAGE"
      "DEF:res=$rrd:res_pool_units:AVERAGE"
      "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
      "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
      "CDEF:max1=max,res,-"
      "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
      "CDEF:cpuutiltot=cpuutil,max,*"
      "PRINT:cpuutiltot:AVERAGE: %3.3lf"
    );
  }
  my $answer = RRDp::read;

  #print "$type: $$answer\n";
  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {
    return 0;
  }
  else {
    my $once = 0;
    foreach my $answ ( split( / /, $$answer ) ) {
      if ( $once == 1 ) {
        $answ =~ s/ //g;
        my $ret = substr( $answ, 0, 1 );
        if ( $ret =~ /\D/ ) {
          next;
        }
        else {
          #print "99 $answ \n";
          chomp($answ);
          my $ret = sprintf( "%.2f", $answ );
          return $ret;    # return max value
        }
      }
      $once++;
    }
    error( "Could not parse output from $rrd : $$answer " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

}

sub lpar_check {
  my $lpar_name  = shift;
  my $lpar_all   = shift;
  my $lpar       = shift;
  my $server     = shift;
  my $hmc        = shift;
  my $hmc_all    = shift;
  my $act_time_u = shift;

  my $uniq_name = $lpar_name . $server . "LPAR";
  my $found     = 0;

  my $lpar_cfg_file = "$hmc_all/cpu.cfg-$lpar_name";

  if ( !-f "$lpar_cfg_file" ) {

    #print "info           : cpu.cfg does not exists for $lpar, ignoring : $hmc_all/cpu.cfg-$lpar_name\n";
    # do not place error, just info ...
    #error("cpu.cfg does not exists for $lpar, ignoring : $hmc_all/cpu.cfg-$lpar_name");
    return 1;
  }
  open( FL, "<", "$lpar_cfg_file" ) || error( "Can't open $lpar_cfg_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  my @lines = <FL>;
  close(FL);
  my $curr_proc       = 0;
  my $curr_proc_units = 0;
  my $curr_proc_mode  = "";
  my $sharing_mode    = "uncap";

=begin sample
<B>Current CPU configuration:</B><TABLE class="tabconfig"><tbody>
<tr><td><font size="-1">PartitionState</font></td><td><font size="-1">running</font></td></tr>
<tr><td><font size="-1">CurrentSharedProcessorPoolID</font></td><td><font size="-1">1</font></td></tr>
<tr><td><font size="-1">CurrentProcessingUnits</font></td><td><font size="-1">0.4</font></td></tr>
<tr><td><font size="-1">AllocatedVirtualProcessors</font></td><td><font size="-1">4</font></td></tr>
<tr><td><font size="-1">SharingMode</font></td><td><font size="-1">uncapped</font></td></tr>
<tr><td><font size="-1">CurrentUncappedWeight</font></td><td><font size="-1">128</font></td></tr>
<tr><td><font size="-1">CurrentProcessorMode</font></td><td><font size="-1">shared</font></td></tr>
</tbody></TABLE><font size="-1">HMC time : 2019-01-14 08:31:40</font>
=cut

  foreach my $line (@lines) {
    chomp($line);
    if ( $line =~ m/curr_proc_mode/ || $line =~ m/CurrentProcessorMode/ ) {
      $line =~ s/<TD><font size=\"-1\">//g;
      $line =~ s/<\/font><\/TD>//g;
      $line =~ s/\&nbsp;//g;
      $line =~ s/<\/TR>//g;
      $line =~ s/<TR>//g;
      $line =~ s/curr_proc_mode//g;

      #Rest API adjustment
      $line =~ s/<tr>.*<font size=.-1.>//g;
      $line =~ s/<.*//g;

      $curr_proc_mode = $line;
      next;
    }
    if ( $line =~ m/curr_procs</ ) {
      $line =~ s/<TD><font size=\"-1\">//g;
      $line =~ s/<\/font><\/TD>//g;
      $line =~ s/\&nbsp;//g;
      $line =~ s/<\/TR>//g;
      $line =~ s/<TR>//g;
      $line =~ s/curr_procs//g;

      #Rest API adjustment
      $line =~ s/<tr>.*<font size=.-1.>//g;
      $line =~ s/<.*//g;
      $curr_proc = $line;
      next;
    }
    if ( $line =~ m/curr_proc_units</ || $line =~ m/CurrentProcessingUnits/ ) {
      $line =~ s/<TD><font size=\"-1\">//g;
      $line =~ s/<\/font><\/TD>//g;
      $line =~ s/\&nbsp;//g;
      $line =~ s/<\/TR>//g;
      $line =~ s/<TR>//g;
      $line =~ s/curr_proc_units//g;

      #Rest API adjustment
      $line =~ s/<tr>.*<font size=.-1.>//g;
      $line =~ s/<.*//g;
      $curr_proc_units = $line;
      if ( isdigit($curr_proc_units) == 0 || $curr_proc_units == 0 ) {
        return 0;    # it cannot be zero, then it fails on zerpo division
      }
      next;
    }
    if ( $line =~ m/curr_sharing_mode</ || $line =~ m/SharingMode/ ) {
      $line =~ s/<TD><font size=\"-1\">//g;
      $line =~ s/<\/font><\/TD>//g;
      $line =~ s/\&nbsp;//g;
      $line =~ s/<\/TR>//g;
      $line =~ s/<TR>//g;
      $line =~ s/curr_sharing_mode//g;

      #Rest API adjustment
      $line =~ s/<tr>.*<font size=.-1.>//g;
      $line =~ s/<.*//g;
      $sharing_mode = $line;
      next;
    }
  }

  if ( $curr_proc_mode eq '' ) {
    error( "curr_proc_mode has not been found: $lpar : $hmc_all/cpu.cfg-$lpar_name " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  if ( $curr_proc eq 'null' || $curr_proc == 0 ) {

    #print "info           : curr_proc has not been found: $lpar : $hmc_all/cpu.cfg-$lpar_name\n";
    # LPAR is probably switched off
    return 1;
  }

  if ( $curr_proc_mode !~ m/^ded/ ) {

    # exclude dedicated here
    lpar_check_detail_cpu( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $curr_proc, $curr_proc_units, $DAY,   $sharing_mode );
    lpar_check_detail_cpu( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $curr_proc, $curr_proc_units, $WEEK,  $sharing_mode );
    lpar_check_detail_cpu( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $curr_proc, $curr_proc_units, $MONTH, $sharing_mode );
  }

  # Memory stuff --> no matter if CPU dedicated or not
  #print "000 $hmc_all/$lpar_name/mem.mmm\n";
  if ( -f "$hmc_all/$lpar_name/mem.mmm" && -f "$hmc_all/$lpar_name/pgs.mmm" ) {
    $uniq_name = $lpar_name . $server . "MEM";
    my $lpar_all_mem = "$hmc_all/$lpar_name/mem.mmm";
    lpar_check_detail_mem( $lpar_name, $lpar_all_mem, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $DAY );
    lpar_check_detail_mem( $lpar_name, $lpar_all_mem, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $WEEK );
    lpar_check_detail_mem( $lpar_name, $lpar_all_mem, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $MONTH );
  }

  # IO wait stuff
  if ( -f "$hmc_all/$lpar_name/cpu.mmm" ) {
    $uniq_name = $lpar_name . $server . "IO";
    my $lpar_all_mem = "$hmc_all/$lpar_name/cpu.mmm";
    lpar_check_detail_io( $lpar_name, $lpar_all_mem, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $DAY );
    lpar_check_detail_io( $lpar_name, $lpar_all_mem, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $WEEK );
    lpar_check_detail_io( $lpar_name, $lpar_all_mem, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $MONTH );
  }

  return 0;
}

# only identify of potential IO candidates
sub lpar_check_detail_io {
  my $lpar_name  = shift;
  my $lpar_all   = shift;
  my $lpar       = shift;
  my $server     = shift;
  my $hmc        = shift;
  my $hmc_all    = shift;
  my $act_time_u = shift;
  my $uniq_name  = shift;
  my $time_range = shift;
  my $found      = 0;
  my @dual       = "";

  #print "001 $lpar_all\n";

  if ( $time_range == $DAY ) {    # day
    @dual = @day_dual_hmc_prevent;
  }
  if ( $time_range == $WEEK ) {    #week
    @dual = @wee_dual_hmc_prevent;
  }
  if ( $time_range == $MONTH ) {    # month
    @dual = @mon_dual_hmc_prevent;
  }

  foreach my $name (@dual) {
    if ( $uniq_name =~ m/^$name$/ ) {
      $found = 1;
      last;
    }
  }

  if ( $found == 1 ) {
    return 0;                       # there has been already alert for that server & lpar --> probably dual HMC setup
  }

  my $rrd_time = ( stat("$lpar_all") )[9];
  if ( ( $act_time_u - $rrd_time ) > $time_range ) {
    return 1;
  }

  my $lpar_url = $lpar_name;
  $lpar_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  $lpar_url =~ s/\+/ /g;

  my $line = get_lpar_io( $lpar_all, $time_range );    # IO usage avrg/peak
  ( my $io_peak, my $io_avrg ) = split( /:/, $line );

  $io_peak = sprintf( "%.0f", $io_peak );
  $io_avrg = sprintf( "%.0f", $io_avrg );

  if ( $io_avrg > $IO_AVRG_CRIT ) {

    #print "003 MAX $lpar_name: $io_peak : $time_range : $io_avrg\n";
    update_struct( "IO", "ERROR", $time_range, $lpar_url, $lpar_name, $server, $hmc, 0, $uniq_name, $io_peak, $io_avrg, 0, 0, 0, 0 );
    return 0;
  }

  if ( $io_peak > $IO_PEAK_MAX || $io_avrg > $IO_AVRG_MAX ) {

    #print "004 CRIT $lpar_name: $io_peak : $time_range : $io_avrg\n";
    update_struct( "IO", "WARNING", $time_range, $lpar_url, $lpar_name, $server, $hmc, 0, $uniq_name, $io_peak, $io_avrg, 0, 0, 0, 0 );
    return 0;
  }

  return 0;
}

sub get_lpar_io {
  my $rrd        = shift;
  my $time_range = shift;
  my $peak       = shift;
  my $time_end   = "now";

  if ( $time_range == $WEEK ) {    # week (time range last 7 days without last day
    $time_end = "now-$DAY";
    $time_end .= "s";
  }
  if ( $time_range == $MONTH ) {    # month (time range last 31 days without last week
    $time_end = "now-$WEEK";
    $time_end .= "s";
  }

  my $width = 1440 * ( $time_range / $DAY );    # to get 1 minute per a pixel
  $time_range =~ s/$/s/;

  $rrd =~ s/:/\\:/g;
  RRDp::cmd qq(graph "$tmpdir/name.png"
        "--start" "now-$time_range"
        "--end" "$time_end"
        "--width=$width"
        "DEF:cpuwa=$rrd:cpu_wa:AVERAGE"
        "PRINT:cpuwa:MAX: %.1lf"
        "PRINT:cpuwa:AVERAGE: %.1lf"
      );

  my $answer = RRDp::read;

  #print "$$answer";

  my $return = "";
  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {
    return "-1:-1";
  }
  else {
    foreach my $answ ( split( / /, $$answer ) ) {
      chomp($answ);
      $answ =~ s/ //g;
      if ( $answ =~ m/x/ || $answ eq '' ) {
        next;
      }
      my $ret_digit = isdigit($answ);
      if ( $ret_digit == 0 ) {
        next;
      }
      $return .= sprintf( "%.1f", $answ ) . ":";
    }
  }

  #print "002 MEM  : $return\n";
  if ( $return eq '' || $return !~ m/:/ ) {
    error( "Could not parse output from $rrd : $$answer " . __FILE__ . ":" . __LINE__ );
    return "-1:-1";
  }
  return $return;

}

# only identify of potential candidates
sub lpar_check_detail_mem {
  my $lpar_name  = shift;
  my $lpar_all   = shift;
  my $lpar       = shift;
  my $server     = shift;
  my $hmc        = shift;
  my $hmc_all    = shift;
  my $act_time_u = shift;
  my $uniq_name  = shift;
  my $time_range = shift;
  my $found      = 0;
  my @dual       = "";

  #print "001 $lpar_all\n";

  if ( $time_range == $DAY ) {    # day
    @dual = @day_dual_hmc_prevent;
  }
  if ( $time_range == $WEEK ) {    #week
    @dual = @wee_dual_hmc_prevent;
  }
  if ( $time_range == $MONTH ) {    # month
    @dual = @mon_dual_hmc_prevent;
  }

  foreach my $name (@dual) {
    if ( $uniq_name =~ m/^$name$/ ) {
      $found = 1;
      last;
    }
  }

  if ( $found == 1 ) {
    return 0;                       # there has been already alert for that server & lpar --> probably dual HMC setup
  }

  my $rrd_time = ( stat("$lpar_all") )[9];
  if ( ( $act_time_u - $rrd_time ) > $time_range ) {
    return 1;
  }

  my $lpar_url = $lpar_name;
  $lpar_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  $lpar_url =~ s/\+/ /g;

  my $line = get_lpar_mem( $lpar_all, $time_range );    # memory usage avrg/peak
  ( my $mem_peak, my $mem_avrg, my $mem_size_last ) = split( /:/, $line );

  $lpar_all =~ s/mem\.mmm/pgs.mmm/;
  $line = get_lpar_pgs( $lpar_all, $time_range );       # paging usage avrg/peak
  ( my $pgs_peak, my $pgs_avrg, my $pgs_util_peak, my $paging_space ) = split( /:/, $line );
  $pgs_peak = sprintf( "%.0f", $pgs_peak );
  $pgs_avrg = sprintf( "%.0f", $pgs_avrg );

  if ( $mem_peak < $MEM_PEAK_LOW && $mem_peak > 0 ) {

    # if mem peak < 70% then ignore the rest
    # memory saving!!
    #print "003 $lpar_name: $mem_peak : $time_range : $mem_avrg\n";
    #update_struct("MEM","WARNING",$time_range,$lpar_url,$lpar_name,$server,$hmc,-1,$uniq_name,$mem_peak,$mem_avrg,-1,-1,$mem_size_last,-1);
    update_struct( "MEM", "WARNING", $time_range, $lpar_url, $lpar_name, $server, $hmc, $pgs_util_peak, $uniq_name, $mem_peak, $mem_avrg, $pgs_peak, $pgs_avrg, $mem_size_last, $paging_space );
    return 0;
  }

  if ( $mem_peak > $MEM_PEAK_CRIT || $mem_avrg > $MEM_AVRG_CRIT || $pgs_util_peak > $PGS_UTIL_CRIT || $pgs_peak > $PGS_PEAK_CRIT || $pgs_avrg > $PGS_AVRG_CRIT ) {

    #print "004 $lpar_name: $time_range : $pgs_peak : $pgs_avrg : $pgs_util_peak : $mem_peak : $mem_avrg :: $mem_size_last : $paging_space\n";
    update_struct( "MEM", "ERROR", $time_range, $lpar_url, $lpar_name, $server, $hmc, $pgs_util_peak, $uniq_name, $mem_peak, $mem_avrg, $pgs_peak, $pgs_avrg, $mem_size_last, $paging_space );
    return 0;
  }

  if ( $mem_peak > $MEM_PEAK_LIM || $mem_avrg > $MEM_AVRG_LIM || $pgs_util_peak > $PGS_UTIL_LIM || $pgs_peak > $PGS_PEAK_LIM || $pgs_avrg > $PGS_AVRG_LIM ) {

    #print "005 $lpar_name: $time_range : $pgs_peak : $pgs_avrg : $pgs_util_peak : $mem_peak : $mem_avrg :: $mem_size_last : $paging_space\n";
    update_struct( "MEM", "WARNING", $time_range, $lpar_url, $lpar_name, $server, $hmc, $pgs_util_peak, $uniq_name, $mem_peak, $mem_avrg, $pgs_peak, $pgs_avrg, $mem_size_last, $paging_space );
    return 0;
  }

  return 0;
}

sub get_lpar_pgs {
  my $rrd        = shift;
  my $time_range = shift;
  my $peak       = shift;
  my $time_end   = "now";

  my $filter_max = $filter_max_paging;    # filter values above as this is mkost probably caused by a coiunter reset (lpar restart)

  if ( $time_range == $WEEK ) {           # week (time range last 7 days without last day
    $time_end = "now-$DAY";
    $time_end .= "s";
    $filter_max = $filter_max / 2;
  }
  if ( $time_range == $MONTH ) {          # month (time range last 31 days without last week
    $time_end = "now-$WEEK";
    $time_end .= "s";

    # lower limits for monthly graphs as they are averaged ....
    $filter_max = $filter_max / 10;
  }

  my $width = 1440 * ( $time_range / $DAY );    # to get 1 minute per a pixel
  $time_range =~ s/$/s/;

  $rrd =~ s/:/\\:/g;
  RRDp::cmd qq(graph "$tmpdir/name.png"
        "--start" "now-$time_range"
        "--end" "$time_end"
        "--width=$width"
        "DEF:pagein=$rrd:page_in:AVERAGE"
        "DEF:pageout=$rrd:page_out:AVERAGE"
        "DEF:percent=$rrd:percent:AVERAGE"
        "DEF:paging_space=$rrd:paging_space:AVERAGE"
        "CDEF:pagein_b_nf=pagein,4096,*"
        "CDEF:pageout_b_nf=pageout,4096,*"
        "CDEF:pagein_b=pagein_b_nf,$filter_max,GT,UNKN,pagein_b_nf,IF"
        "CDEF:pageout_b=pageout_b_nf,$filter_max,GT,UNKN,pageout_b_nf,IF"
        "CDEF:pagein_kb=pagein_b,1024,/"
        "CDEF:pageout_kb=pageout_b,1024,/"
        "CDEF:page_tot=pagein_kb,pageout_kb,+"
        "PRINT:page_tot:MAX: %.0lf"
        "PRINT:page_tot:AVERAGE: %.0lf"
        "PRINT:percent:MAX: %3.1lf"
        "PRINT:paging_space:LAST: %.0lf"
      );

  my $answer = RRDp::read;

  #print "$$answer";

  my $return = "";
  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {
    return "-1:-1:-1:-1";
  }
  else {
    foreach my $answ ( split( / /, $$answer ) ) {
      chomp($answ);
      $answ =~ s/ //g;
      if ( $answ =~ m/x/ || $answ eq '' ) {
        next;
      }
      my $ret_digit = isdigit($answ);
      if ( $ret_digit == 0 ) {
        next;
      }
      $return .= sprintf( "%.1f", $answ ) . ":";
    }
  }

  #print "002 MEM  : $return\n";
  if ( $return eq '' || $return !~ m/:/ ) {
    error( "Could not parse output from $rrd : $$answer " . __FILE__ . ":" . __LINE__ );
    return "-1:-1:-1:-1";
  }
  return $return;

}

sub get_lpar_mem {
  my $rrd        = shift;
  my $time_range = shift;
  my $peak       = shift;
  my $time_end   = "now";

  if ( $time_range == $WEEK ) {    # week (time range last 7 days without last day
    $time_end = "now-$DAY";
    $time_end .= "s";
  }
  if ( $time_range == $MONTH ) {    # month (time range last 31 days without last week
    $time_end = "now-$WEEK";
    $time_end .= "s";
  }

  my $width = 1440 * ( $time_range / $DAY );    # to get 1 minute per a pixel
  $time_range =~ s/$/s/;

  $rrd =~ s/:/\\:/g;
  RRDp::cmd qq(graph "$tmpdir/name.png"
        "--start" "now-$time_range"
        "--end" "$time_end"
        "--width=$width"
        "DEF:size=$rrd:size:AVERAGE"
        "DEF:free=$rrd:free:AVERAGE"
        "DEF:in_use_clnt=$rrd:in_use_clnt:AVERAGE"
        "CDEF:sizemb=size,1024,/"
        "CDEF:size_perc=size,100,/"
        "CDEF:nfree=free,in_use_clnt,+"
        "CDEF:nuse=size,nfree,-"
        "CDEF:nuse_perc=nuse,size_perc,/"
        "PRINT:nuse_perc:MAX: %3.1lf"
        "PRINT:nuse_perc:AVERAGE: %3.1lf"
        "PRINT:sizemb:LAST: %8.0lf"
      );

  my $answer = RRDp::read;

  #print "$$answer";

  my $return = "";
  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {
    return "-1:-1:-1";
  }
  else {
    foreach my $answ ( split( / /, $$answer ) ) {
      chomp($answ);
      $answ =~ s/ //g;
      if ( $answ =~ m/x/ || $answ eq '' ) {
        next;
      }
      my $ret_digit = isdigit($answ);
      if ( $ret_digit == 0 ) {
        next;
      }
      $return .= sprintf( "%.1f", $answ ) . ":";
    }
  }

  #print "002 MEM  : $return\n";
  if ( $return eq '' || $return !~ m/:/ ) {
    error( "Could not parse output from $rrd : $$answer " . __FILE__ . ":" . __LINE__ );
    return "-1:-1:-1";
  }
  return $return;

}

sub pool_check {
  my $lpar_name     = shift;
  my $lpar_all      = shift;
  my $lpar          = shift;
  my $server        = shift;
  my $hmc           = shift;
  my $hmc_all       = shift;
  my $act_time_u    = shift;
  my $lpar_name_org = $lpar_name;

  my $uniq_name = $lpar_name . $server . "POOL";
  my $found     = 0;

  if ( !-f "$hmc_all/config.cfg" ) {

    #print "info           : config.cfg does not exists for $lpar, ignoring : $hmc_all/config.cfg\n";
    return 1;
  }

  my $lpar_name_id = $lpar_name;
  $lpar_name_id =~ s/SharedPool//;

  open( FP, "< $hmc_all/config.cfg" ) || error( "Can't open $hmc_all/config.cfg : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  my @lines = <FP>;
  close(FP);
  my $pool_res = 0;
  my $pool_max = 0;
  $found = 0;
  foreach my $line (@lines) {
    chomp($line);
    if ( $line =~ m/configurable_sys_proc_units/ ) {
      $line =~ s/configurable_sys_proc_units//;
      $line =~ s/ //g;
      $line =~ s/<\/td>//g;
      $line =~ s/<td>//g;
      $pool_max = $line;
      next;
    }
    if ( $line =~ m/curr_avail_sys_proc_units/ ) {
      $line =~ s/curr_avail_sys_proc_units//;
      $line =~ s/ //g;
      $line =~ s/<\/td>//g;
      $line =~ s/<td>//g;
      $pool_res = $pool_max - $line;
      last;
    }
  }

  if ( $pool_max == 0 ) {

    #error ("max_pool_proc_units has not been found: $lpar : $hmc_all/config.cfg ".__FILE__.":".__LINE__);
    # do not report it ...
    return 1;
  }

  my $ret = 0;
  $ret = pool_check_detail( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $pool_max, $pool_res, $DAY );

  #if ( $ret == 2 ) { return 2; }
  $ret = pool_check_detail( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $pool_max, $pool_res, $WEEK );

  #if ( $ret == 2 ) { return 2; }
  pool_check_detail( $lpar_name, $lpar_all, $lpar, $server, $hmc, $hmc_all, $act_time_u, $uniq_name, $pool_max, $pool_res, $MONTH );

  return 0;
}

sub pool_check_detail {
  my $lpar_name  = shift;
  my $lpar_all   = shift;
  my $lpar       = shift;
  my $server     = shift;
  my $hmc        = shift;
  my $hmc_all    = shift;
  my $act_time_u = shift;
  my $uniq_name  = shift;
  my $pool_max   = shift;
  my $pool_res   = shift;
  my $time_range = shift;
  my $found      = 0;
  my @dual       = "";

  if ( $time_range == $DAY ) {    # day
    @dual = @day_dual_hmc_prevent;
  }
  if ( $time_range == $WEEK ) {    #week
    @dual = @wee_dual_hmc_prevent;
  }
  if ( $time_range == $MONTH ) {    # month
    @dual = @mon_dual_hmc_prevent;
  }

  foreach my $name (@dual) {
    if ( $uniq_name =~ m/^$name$/ ) {
      $found = 1;
      last;
    }
  }

  if ( $found == 1 ) {
    return 0;                       # there has been already alert for that server & lpar --> probably dual HMC setup
  }

  my $lpar_name_org = $lpar_name;
  my $rrd_time      = ( stat("$lpar_all") )[9];
  if ( ( $act_time_u - $rrd_time ) > $time_range ) {
    return 1;
  }

  $lpar_name = "CPU&nbsp;pool";
  my $lpar_name_plain = "CPU pool";

  my $ret = get_pool_peak( $lpar_all, "max", $time_range, $pool_max, 0 );    # max CPU
  if ( $ret > 0 ) {
    if ( $time_range == $DAY ) {                                             # day
                                                                             #print "POOL ERROR     : $lpar_name_plain:$server:$hmc : pool has reached its max CPU $ret (limit:$pool_max)\n";
    }

    my $lpar_url = $lpar_name_org;
    $lpar_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $lpar_url =~ s/\+/ /g;
    my $avrg = get_pool_peak( $lpar_all, "res", $time_range, $pool_res, 1 );    # avrg
    update_struct( "POOL", "ERROR", $time_range, $lpar_url, $lpar_name, $server, $hmc, $pool_max, $uniq_name, $ret, $avrg, $pool_res, "na", -1, -1 );
    return 1;
  }

  $ret = get_pool_peak( $lpar_all, "res", $time_range, $pool_res, 0 );          # entitle check: curr_proc_units
  if ( $ret > 0 ) {
    if ( $time_range == $DAY ) {                                                # day
                                                                                #print "POOL WARNING   : $lpar_name_plain:$server:$hmc : pool has reached its entitlement last day $ret (limit:$pool_res)\n";
    }

    my $lpar_url = $lpar_name_org;
    $lpar_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $lpar_url =~ s/\+/ /g;
    my $avrg = get_pool_peak( $lpar_all, "res", $time_range, $pool_res, 1 );    # avrg
    update_struct( "POOL", "WARNING", $time_range, $lpar_url, $lpar_name, $server, $hmc, $pool_max, $uniq_name, $ret, $avrg, $pool_res, "na", -1, -1 );
    return 1;
  }

  return 0;
}

sub get_pool_peak {
  my $rrd        = shift;
  my $type       = shift;
  my $time_range = shift;
  my $limit      = shift;
  my $time_end   = "now";
  my $avrg       = shift;

  if ( $time_range == $WEEK ) {    # week (time range last 7 days without last day
    $time_end = "now-$DAY";
    $time_end .= "s";
  }
  if ( $time_range == $MONTH ) {    # month (time range last 31 days without last week
    $time_end = "now-$WEEK";
    $time_end .= "s";
  }

  my $width = 1440 * ( $time_range / $DAY );    # to get 1 minute per a pixel
  $time_range =~ s/$/s/;

  if ( $avrg == 0 ) {
    if ( $type =~ m/max/ ) {
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$tmpdir/name.png"
        "--start" "now-$time_range"
        "--end" "$time_end"
        "--width=$width"
        "--step" "$step_interval"
        "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
        "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
        "DEF:cpu=$rrd:conf_proc_units:AVERAGE"
        "DEF:cpubor=$rrd:bor_proc_units:AVERAGE"
        "CDEF:totcpu=cpu,cpubor,+"
        "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
        "CDEF:cpuutiltot_ok=cpuutil,totcpu,*"
        "CDEF:cpuutiltot=cpuutiltot_ok,0.01,+"
        "CDEF:result=cpuutiltot,$limit,LT,UNKN,cpuutiltot,IF"
        "PRINT:result:MAX: %3.3lf"
      );
    }
    else {
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$tmpdir/name.png"
        "--start" "now-$time_range"
        "--end" "$time_end"
        "--width=$width"
        "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
        "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
        "DEF:cpu=$rrd:conf_proc_units:AVERAGE"
        "DEF:cpubor=$rrd:bor_proc_units:AVERAGE"
        "CDEF:totcpu=cpu,cpubor,+"
        "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
        "CDEF:cpuutiltot_ok=cpuutil,totcpu,*"
        "CDEF:cpuutiltot=cpuutiltot_ok,0.01,+"
        "CDEF:result=cpuutiltot,$limit,LT,UNKN,cpuutiltot,IF"
        "PRINT:result:MAX: %3.3lf"
      );
    }
  }
  else {
    # average
    $rrd =~ s/:/\\:/g;
    RRDp::cmd qq(graph "$tmpdir/name.png"
      "--start" "now-$time_range"
      "--end" "$time_end"
      "--width=$width"
      "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
      "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
      "DEF:cpu=$rrd:conf_proc_units:AVERAGE"
      "DEF:cpubor=$rrd:bor_proc_units:AVERAGE"
      "CDEF:totcpu=cpu,cpubor,+"
      "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
      "CDEF:cpuutiltot_ok=cpuutil,totcpu,*"
      "PRINT:cpuutiltot_ok:AVERAGE: %3.3lf"
    );
  }

  my $answer = RRDp::read;

  #print "003 POOL $rrd : $avrg : $$answer";
  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {
    return 0;
  }
  else {
    my $once = 0;
    foreach my $answ ( split( / /, $$answer ) ) {
      if ( $once == 1 ) {
        $answ =~ s/ //g;
        my $ret = substr( $answ, 0, 1 );
        if ( $ret =~ /\D/ ) {
          next;
        }
        else {
          #print "99 $answ \n";
          chomp($answ);

          #print "004 POOL $rrd : $avrg : $answ\n";
          my $ret = sprintf( "%.2f", $answ );
          return $ret;    # return max value
        }
      }
      $once++;
    }
    error( "Could not parse output from $rrd : $$answer " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

}

sub basename {
  my $full = shift;
  my $out  = "";

  # basename without direct function
  my @base = split( /\//, $full );
  foreach my $m (@base) {
    $out = $m;
  }

  return $out;
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

#("Shared POOL","WARNING",$time_range,$lpar_url,$lpar_name,$server,$hmc,$sh_max);
sub update_struct {
  my $type          = shift;
  my $type_alert    = shift;
  my $time_range    = shift;
  my $lpar_url      = shift;
  my $lpar_name     = shift;
  my $server        = shift;
  my $hmc           = shift;
  my $max           = shift;
  my $uniq_name     = shift;
  my $max_reached   = shift;
  my $avrg          = shift;
  my $entitled      = shift;
  my $sharing_mode  = shift;
  my $mem_size_last = shift;
  my $paging_space  = shift;

  if ( $time_range == $DAY ) {    # day
    $day_dual_hmc_prevent[$day_dual_indx] = $uniq_name;
    $day_dual_indx++;
    if ( $type_alert =~ m/ERROR/ ) {
      $day_err_type[$day_err]     = $type;
      $day_err_lpar_url[$day_err] = $lpar_url;
      $day_err_lpar[$day_err]     = $lpar_name;

      #$day_err_name[$day_err] = ;
      $day_err_srv[$day_err]         = $server;
      $day_err_hmc[$day_err]         = $hmc;
      $day_err_max[$day_err]         = $max;
      $day_err_max_reached[$day_err] = $max_reached;
      $day_err_avrg[$day_err]        = $avrg;
      $day_err_entitle[$day_err]     = $entitled;
      $day_err_mode[$day_err]        = $sharing_mode;
      $day_err_size[$day_err]        = $mem_size_last;
      $day_err_pg[$day_err]          = $paging_space;
      $day_err++;
    }
    else {
      $day_war_type[$day_war]     = $type;
      $day_war_lpar_url[$day_war] = $lpar_url;
      $day_war_lpar[$day_war]     = $lpar_name;

      #$day_war_name[$day_war] = ;
      $day_war_srv[$day_war]         = $server;
      $day_war_hmc[$day_war]         = $hmc;
      $day_war_max[$day_war]         = $max;
      $day_war_max_reached[$day_war] = $max_reached;
      $day_war_avrg[$day_war]        = $avrg;
      $day_war_entitle[$day_war]     = $entitled;
      $day_war_mode[$day_war]        = $sharing_mode;
      $day_war_size[$day_war]        = $mem_size_last;
      $day_war_pg[$day_war]          = $paging_space;
      $day_war++;
    }
  }

  if ( $time_range == $WEEK ) {    #week
    $wee_dual_hmc_prevent[$wee_dual_indx] = $uniq_name;
    $wee_dual_indx++;
    if ( $type_alert =~ m/ERROR/ ) {
      $wee_err_type[$wee_err]     = $type;
      $wee_err_lpar_url[$wee_err] = $lpar_url;
      $wee_err_lpar[$wee_err]     = $lpar_name;

      #$wee_err_name[$wee_err] = ;
      $wee_err_srv[$wee_err]         = $server;
      $wee_err_hmc[$wee_err]         = $hmc;
      $wee_err_max[$wee_err]         = $max;
      $wee_err_max_reached[$wee_err] = $max_reached;
      $wee_err_avrg[$wee_err]        = $avrg;
      $wee_err_entitle[$wee_err]     = $entitled;
      $wee_err_mode[$wee_err]        = $sharing_mode;
      $wee_err_size[$wee_err]        = $mem_size_last;
      $wee_err_pg[$wee_err]          = $paging_space;
      $wee_err++;
    }
    else {
      $wee_war_type[$wee_war]     = $type;
      $wee_war_lpar_url[$wee_war] = $lpar_url;
      $wee_war_lpar[$wee_war]     = $lpar_name;

      #$wee_war_name[$wee_war] = ;
      $wee_war_srv[$wee_war]         = $server;
      $wee_war_hmc[$wee_war]         = $hmc;
      $wee_war_max[$wee_war]         = $max;
      $wee_war_max_reached[$wee_war] = $max_reached;
      $wee_war_avrg[$wee_war]        = $avrg;
      $wee_war_entitle[$wee_war]     = $entitled;
      $wee_war_mode[$wee_war]        = $sharing_mode;
      $wee_war_size[$wee_war]        = $mem_size_last;
      $wee_war_pg[$wee_war]          = $paging_space;
      $wee_war++;
    }
  }

  if ( $time_range == $MONTH ) {    # month
    $mon_dual_hmc_prevent[$mon_dual_indx] = $uniq_name;
    $mon_dual_indx++;
    if ( $type_alert =~ m/ERROR/ ) {
      $mon_err_type[$mon_err]     = $type;
      $mon_err_lpar_url[$mon_err] = $lpar_url;
      $mon_err_lpar[$mon_err]     = $lpar_name;

      #$mon_err_name[$mon_err] = ;
      $mon_err_srv[$mon_err]         = $server;
      $mon_err_hmc[$mon_err]         = $hmc;
      $mon_err_max[$mon_err]         = $max;
      $mon_err_max_reached[$mon_err] = $max_reached;
      $mon_err_avrg[$mon_err]        = $avrg;
      $mon_err_entitle[$mon_err]     = $entitled;
      $mon_err_mode[$mon_err]        = $sharing_mode;
      $mon_err_size[$mon_err]        = $mem_size_last;
      $mon_err_pg[$mon_err]          = $paging_space;
      $mon_err++;
    }
    else {
      $mon_war_type[$mon_war]     = $type;
      $mon_war_lpar_url[$mon_war] = $lpar_url;
      $mon_war_lpar[$mon_war]     = $lpar_name;

      #$mon_war_name[$mon_war] = ;
      $mon_war_srv[$mon_war]         = $server;
      $mon_war_hmc[$mon_war]         = $hmc;
      $mon_war_max[$mon_war]         = $max;
      $mon_war_max_reached[$mon_war] = $max_reached;
      $mon_war_avrg[$mon_war]        = $avrg;
      $mon_war_entitle[$mon_war]     = $entitled;
      $mon_war_mode[$mon_war]        = $sharing_mode;
      $mon_war_size[$mon_war]        = $mem_size_last;
      $mon_war_pg[$mon_war]          = $paging_space;
      $mon_war++;
    }
  }

  return 1;
}

sub create_html {

  my $indx     = 0;
  my $indx_all = 0;
  my @selected = "";
  my $text     = "";
  my $header   = "<thead><tr><th title=\"LPAR / POOL / Shared POOL \"
                        rowspan=\"2\" valign=\"center\" class=\"sortable\">Type&nbsp;&nbsp;&nbsp;&nbsp;</th>
	     <th rowspan=\"2\" valign=\"center\" class=\"sortable\">Name&nbsp;&nbsp;&nbsp;&nbsp;</th>
	     <th rowspan=\"2\" valign=\"center\" class=\"sortable\">Server&nbsp;&nbsp;&nbsp;&nbsp;</th>
             <th colspan=\"4\" align=\"center\">CPU cores</th>
	     <th title=\"Virtual processor / Entitlement ratio\"
                 align=\"center\" rowspan=\"2\" valign=\"center\">&nbsp;VP:Ent&nbsp;<br>ratio</th>
             <th title=\"Maximal CPU peak in given period / Entitlement ratio \"
                 align=\"center\" rowspan=\"2\" valign=\"center\">&nbsp;Max:Ent&nbsp;<br>ratio</th>
             <th title=\"Average CPU load in given period / Entitlement ratio \"
                 align=\"center\" rowspan=\"2\" valign=\"center\">&nbsp;Avg:Ent&nbsp;<br>ratio</th>
             <th title=\"LPAR2RRD recommendation for changes \"
                 align=\"center\" colspan=\"2\">&nbsp;&nbsp;Recommended&nbsp;&nbsp;</th></tr><tr>

 	     <th title=\"Maximal CPU peak in given time period \" align=\"center\">&nbsp;&nbsp;&nbsp;Max&nbsp;&nbsp;&nbsp;</th>
             <th title=\"LPAR: configured Virtual Processors / POOL: configured CPU cores in the pool\"
                 align=\"center\">&nbsp;&nbsp;&nbsp;VP&nbsp;&nbsp;&nbsp;</th>
             <th title=\"Average CPU load in given time period \" align=\"center\">&nbsp;&nbsp;&nbsp;Avg&nbsp;&nbsp;&nbsp;</th>
	     <th title=\"LPAR: configured CPU entitlement / POOL: configured reserved CPU pool units\"
                 align=\"center\">&nbsp;&nbsp;&nbsp;Ent&nbsp;&nbsp;&nbsp;</th>
             <th title=\"Recommended CPU entitlement \" align=\"center\">&nbsp;&nbsp;&nbsp;Ent&nbsp;&nbsp;&nbsp;</th>
             <th title=\"LPAR: recommended number of Virtual Processors / POOL: recommended number of CPU cores in the pool\"
                 align=\"center\">&nbsp;&nbsp;&nbsp;VP&nbsp;&nbsp;&nbsp;</th></tr>
             </thead><tbody>";
  my $header_mem = "<thead><tr>
	     <th rowspan=\"2\" valign=\"center\" class=\"sortable\">LPAR&nbsp;&nbsp;&nbsp;&nbsp;</th>
	     <th rowspan=\"2\" valign=\"center\" class=\"sortable\">Server&nbsp;&nbsp;&nbsp;&nbsp;</th>
	     <th align=\"center\" rowspan=\"2\" valign=\"center\">&nbsp;&nbsp;Memory&nbsp;&nbsp;<br><font size=\"-1\">[GB]</th>
	     <th align=\"center\" rowspan=\"2\" valign=\"center\">&nbsp;&nbsp;Paging&nbsp;&nbsp;<br><font size=\"-1\">[GB]</th>
             <th align=\"center\" rowspan=\"2\" >&nbsp;&nbsp;Paging&nbsp;&nbsp;<br>&nbsp;&nbsp;space&nbsp;&nbsp;<br> <font size=\"-1\">[%]</font></th>
             <th align=\"center\" colspan=\"2\" >&nbsp;&nbsp;Paging&nbsp;rate&nbsp;&nbsp;<br><font size=\"-1\"> [kBps]</font></th>
             <th align=\"center\" colspan=\"2\" >&nbsp;&nbsp;Memory&nbsp;usage&nbsp;&nbsp;<br> <font size=\"-1\">[%]</font></th>
             <th align=\"center\" rowspan=\"2\" >&nbsp;&nbsp;Advise&nbsp;&nbsp;<br><font size=\"-1\">[GB]</font></th>
             <th align=\"center\" rowspan=\"2\" class=\"sortable\" >&nbsp;&nbsp;&nbsp;&nbsp;Diff&nbsp;&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;&nbsp;<font size=\"-1\">[GB]&nbsp;&nbsp;&nbsp;&nbsp;</th></font></tr><tr>
             <th align=\"center\" >AVG</th>
             <th align=\"center\" >MAX</th>
             <th align=\"center\" >AVG</th>
             <th align=\"center\" >MAX</th></tr>
             </thead><tbody>";

  my $header_io = "<thead><tr>
	     <th valign=\"center\" class=\"sortable\">LPAR&nbsp;&nbsp;&nbsp;&nbsp;</th>
	     <th valign=\"center\" class=\"sortable\">Server&nbsp;&nbsp;&nbsp;&nbsp;</th>
             <th align=\"center\"  class=\"sortable\">&nbsp;&nbsp;&nbsp;&nbsp;CPU IO wait peak [%]&nbsp;&nbsp;&nbsp;&nbsp;</th>
             <th align=\"center\"  class=\"sortable\">&nbsp;&nbsp;&nbsp;&nbsp;CPU IO wait avrg [%]&nbsp;&nbsp;&nbsp;&nbsp;</th></tr>
             </thead><tbody>";

  my $legend_mem = "<table><tr>
	         <td>Change is</td>
                 <td title=\"this change saves memory\" $color_noted> <b>noted</b></td>
                 <td title=\"this reports warning\" $color_warning> <b>recommended</b></td>
	         <td title=\"this recomends memory increase\" $color_recomend> <b>strongly recommended</b></td>
	         <td title=\"memory must be increased\" $color_panic><b> a must</b></td></tr></table>";

  my $legend = "<table><tr>
	         <td>Change is</td>
                 <td title=\"this change saves CPU entitlement\" $color_noted> <b>noted</b></td>
                 <td title=\"this change could bring some speed up\" $color_warning> <b>recommended</b></td>
	         <td title=\"this change probably brings speed up\" $color_recomend> <b>strongly recommended</b></td>
	         <td title=\"this change definitely brings speed up\" $color_panic><b> a must</b></td></tr></table>";

  my $legend_io = "<table><tr>
                 <td title=\"Warning\" $color_warning> <b>warning</b></td>
	         <td title=\"Strong warning, there could be a IO problem\" $color_recomend> <b>strong warning</b></td>
	         <td title=\"There is a IO problem and is necessary to fix it\" $color_panic><b>critical</b></td></tr></table>";

  my $how_it_works = "<td  valign=\"top\" nowrap align=\"right\"><font size=\"-1\">
                      <a href=\"http://www.lpar2rrd.com/cpu_configuration_advisor.html\" target=\"_blank\" valign=\"center\">How it works</a></font></td>";

  my $title = "<br><TABLE BORDER=0 width=\"100%\"><tr><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
	        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td align=\"center\">
	        <h3>Configuration Advisor</h3>
	        </td><td align=\"right\" valign=\"top\"><font size=\"-1\">
	        <a href=\"http://www.lpar2rrd.com/cpu_configuration_advisor.html\" target=\"_blank\" valign=\"center\">How it works</a></font></td>
	        </tr></table>\n";

  my $title_gui = " ";

  open( FHL, "> $ent_log" ) || error( "could not open $ent_log : $! " . __FILE__ . ":" . __LINE__ ) && return 0;

  open( FHD, "> $ent_html" ) || error( "could not open $ent_html : $! " . __FILE__ . ":" . __LINE__ ) && return 0;

  # new GUI without HTML header
  open( FHG, "> $ent_html_gui" ) || error( "could not open $ent_html_gui : $! " . __FILE__ . ":" . __LINE__ ) && return 0;

  # CSV into daily
  open( FHCSV, "> $ent_csv_daily_all" ) || error( "could not open $ent_csv_daily_all: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  my $csv_header = "Type$csv_separ" . "Name$csv_separ" . "Server$csv_separ" . "MAX$csv_separ" . "VP$csv_separ" . "Avg$csv_separ" . "Ent$csv_separ" . "VP/Ent$csv_separ" . "Max/Ent$csv_separ" . "Avg/Ent$csv_separ" . "Ent-colour$csv_separ" . "Recom-Ent$csv_separ" . "VP-colour$csv_separ" . "Recom-VP\n";
  print FHCSV $csv_header;

  print_head();
  my $tabs = print_tabs_header();
  print FHD "$tabs\n<div id=\"fragment-0\">\n";
  print FHG "$tabs\n<div id=\"fragment-0\">\n";
  print FHD "$title $legend \n";
  print FHG "$title_gui $legend \n";
  my $date_start = my $date = strftime "%d-%m-%Y", localtime( time() - $DAY );
  print FHD "<font size=\"-1\">Based on data from $date_start (last day) <a href=\"$ent_csv_daily\"><div class=\"csvexport\">CSV</div></a></font><br>\n";
  print FHG "<table width=\"100%\"><tr><td><font size=\"-1\">Based on data from $date_start (last day) <a href=\"$ent_csv_daily\"><div class=\"csvexport\">CSV</div></a></font></td>$how_it_works</tr></table>\n";

  #
  # last day
  #
  print FHD "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last day\">\n";
  print FHG "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last day\">\n";
  print FHD "$header\n";
  print FHG "$header\n";

  # ERR && POOL

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_err_type) {
    if ( $type =~ m/^POOL$/ ) {
      $day_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_err_srv[$indx] . ":" . $day_err_hmc[$indx] . ":" . $day_err_max[$indx] . ":" . $day_err_max_reached[$indx] . ":" . $day_err_lpar[$indx] . ":" . $day_err_lpar_url[$indx] . ":" . $day_err_entitle[$indx] . ":" . $day_err_avrg[$indx] . ":" . $day_err_mode[$indx] . ":" . $day_err_size[$indx] . ":" . $day_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "POOL", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "POOL", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # ERR && SH POOL
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_err_type) {
    if ( $type =~ m/^Shared POOL$/ ) {
      $day_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_err_srv[$indx] . ":" . $day_err_hmc[$indx] . ":" . $day_err_max[$indx] . ":" . $day_err_max_reached[$indx] . ":" . $day_err_lpar[$indx] . ":" . $day_err_lpar_url[$indx] . ":" . $day_err_entitle[$indx] . ":" . $day_err_avrg[$indx] . ":" . $day_err_mode[$indx] . ":" . $day_err_size[$indx] . ":" . $day_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "Shared POOL", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "Shared POOL", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # ERR && LPAR
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_err_type) {
    if ( $type =~ m/LPAR/ ) {
      $day_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_err_srv[$indx] . ":" . $day_err_hmc[$indx] . ":" . $day_err_max[$indx] . ":" . $day_err_max_reached[$indx] . ":" . $day_err_lpar[$indx] . ":" . $day_err_lpar_url[$indx] . ":" . $day_err_entitle[$indx] . ":" . $day_err_avrg[$indx] . ":" . $day_err_mode[$indx] . ":" . $day_err_size[$indx] . ":" . $day_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "LPAR", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "LPAR", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && POOL

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_war_type) {
    if ( $type =~ m/^POOL$/ ) {
      $day_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_war_srv[$indx] . ":" . $day_war_hmc[$indx] . ":" . $day_war_max[$indx] . ":" . $day_war_max_reached[$indx] . ":" . $day_war_lpar[$indx] . ":" . $day_war_lpar_url[$indx] . ":" . $day_war_entitle[$indx] . ":" . $day_war_avrg[$indx] . ":" . $day_war_mode[$indx] . ":" . $day_war_size[$indx] . ":" . $day_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "POOL", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "POOL", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && SH POOL
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_war_type) {
    if ( $type =~ m/^Shared POOL$/ ) {
      $day_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_war_srv[$indx] . ":" . $day_war_hmc[$indx] . ":" . $day_war_max[$indx] . ":" . $day_war_max_reached[$indx] . ":" . $day_war_lpar[$indx] . ":" . $day_war_lpar_url[$indx] . ":" . $day_war_entitle[$indx] . ":" . $day_war_avrg[$indx] . ":" . $day_war_mode[$indx] . ":" . $day_war_size[$indx] . ":" . $day_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "Shared POOL", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "Shared POOL", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && LPAR
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_war_type) {
    if ( $type =~ m/LPAR/ ) {
      $day_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_war_srv[$indx] . ":" . $day_war_hmc[$indx] . ":" . $day_war_max[$indx] . ":" . $day_war_max_reached[$indx] . ":" . $day_war_lpar[$indx] . ":" . $day_war_lpar_url[$indx] . ":" . $day_war_entitle[$indx] . ":" . $day_war_avrg[$indx] . ":" . $day_war_mode[$indx] . ":" . $day_war_size[$indx] . ":" . $day_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "LPAR", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "LPAR", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  print FHD "</tbody></table>\n";
  print FHG "</tbody></table>\n";
  print FHD "</div>\n";
  print FHG "</div>\n";

  print FHD "\n<div id=\"fragment-1\">\n";
  print FHG "\n<div id=\"fragment-1\">\n";
  print FHD "$title $legend \n";
  print FHG "$title_gui $legend \n";
  $date_start = strftime "%d-%m-%Y", localtime( time() - $DAY - $DAY );
  my $date_end = strftime "%d-%m-%Y", localtime( time() - $WEEK );
  print FHD "<font size=\"-1\">Based on data from $date_end : $date_start (last week without last day) <a href=\"$ent_csv_weekly\"><div class=\"csvexport\">CSV</div></a></font><br>\n";
  print FHG "<table width=\"100%\"><tr><td><font size=\"-1\">Based on data from $date_end : $date_start (last week without last day) <a href=\"$ent_csv_weekly\"><div class=\"csvexport\">CSV</div></a></font></td>$how_it_works</tr></table>\n";

  #
  # last week
  #

  print FHD "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last week\">\n";
  print FHG "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last week\">\n";
  print FHD "$header\n";
  print FHG "$header\n";

  # CSV into weekly
  close(FHCSV);
  open( FHCSV, "> $ent_csv_weekly_all" ) || error( "could not open $ent_csv_weekly_all: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  print FHCSV $csv_header;

  # ERR && POOL

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_err_type) {
    if ( $type =~ m/^POOL$/ ) {
      $wee_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_err_srv[$indx] . ":" . $wee_err_hmc[$indx] . ":" . $wee_err_max[$indx] . ":" . $wee_err_max_reached[$indx] . ":" . $wee_err_lpar[$indx] . ":" . $wee_err_lpar_url[$indx] . ":" . $wee_err_entitle[$indx] . ":" . $wee_err_avrg[$indx] . ":" . $wee_err_mode[$indx] . ":" . $wee_err_size[$indx] . ":" . $wee_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "POOL", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "POOL", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # ERR && SH POOL
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_err_type) {
    if ( $type =~ m/^Shared POOL$/ ) {
      $wee_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_err_srv[$indx] . ":" . $wee_err_hmc[$indx] . ":" . $wee_err_max[$indx] . ":" . $wee_err_max_reached[$indx] . ":" . $wee_err_lpar[$indx] . ":" . $wee_err_lpar_url[$indx] . ":" . $wee_err_entitle[$indx] . ":" . $wee_err_avrg[$indx] . ":" . $wee_err_mode[$indx] . ":" . $wee_err_size[$indx] . ":" . $wee_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "Shared POOL", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "Shared POOL", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # ERR && LPAR
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_err_type) {
    if ( $type =~ m/LPAR/ ) {
      $wee_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_err_srv[$indx] . ":" . $wee_err_hmc[$indx] . ":" . $wee_err_max[$indx] . ":" . $wee_err_max_reached[$indx] . ":" . $wee_err_lpar[$indx] . ":" . $wee_err_lpar_url[$indx] . ":" . $wee_err_entitle[$indx] . ":" . $wee_err_avrg[$indx] . ":" . $wee_err_mode[$indx] . ":" . $wee_err_size[$indx] . ":" . $wee_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "LPAR", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "LPAR", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && POOL

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_war_type) {
    if ( $type =~ m/^POOL$/ ) {
      $wee_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_war_srv[$indx] . ":" . $wee_war_hmc[$indx] . ":" . $wee_war_max[$indx] . ":" . $wee_war_max_reached[$indx] . ":" . $wee_war_lpar[$indx] . ":" . $wee_war_lpar_url[$indx] . ":" . $wee_war_entitle[$indx] . ":" . $wee_war_avrg[$indx] . ":" . $wee_war_mode[$indx] . ":" . $wee_war_size[$indx] . ":" . $wee_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "POOL", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "POOL", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && SH POOL
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_war_type) {
    if ( $type =~ m/^Shared POOL$/ ) {
      $wee_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_war_srv[$indx] . ":" . $wee_war_hmc[$indx] . ":" . $wee_war_max[$indx] . ":" . $wee_war_max_reached[$indx] . ":" . $wee_war_lpar[$indx] . ":" . $wee_war_lpar_url[$indx] . ":" . $wee_war_entitle[$indx] . ":" . $wee_war_avrg[$indx] . ":" . $wee_war_mode[$indx] . ":" . $wee_war_size[$indx] . ":" . $wee_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "Shared POOL", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "Shared POOL", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && LPAR
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_war_type) {
    if ( $type =~ m/LPAR/ ) {
      $wee_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_war_srv[$indx] . ":" . $wee_war_hmc[$indx] . ":" . $wee_war_max[$indx] . ":" . $wee_war_max_reached[$indx] . ":" . $wee_war_lpar[$indx] . ":" . $wee_war_lpar_url[$indx] . ":" . $wee_war_entitle[$indx] . ":" . $wee_war_avrg[$indx] . ":" . $wee_war_mode[$indx] . ":" . $wee_war_size[$indx] . ":" . $wee_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "LPAR", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "LPAR", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  print FHD "</tbody></table>\n";
  print FHG "</tbody></table>\n";
  print FHD "\n</div>\n";
  print FHG "\n</div>\n";

  print FHD "\n<div id=\"fragment-2\">\n";
  print FHG "\n<div id=\"fragment-2\">\n";
  print FHD "$title $legend \n";
  print FHG "$title_gui $legend \n";
  $date_start = strftime "%d-%m-%Y", localtime( time() - $WEEK - $DAY );
  $date_end   = strftime "%d-%m-%Y", localtime( time() - $MONTH );
  print FHD "<font size=\"-1\">Based on data from $date_end : $date_start (last month without last week) <a href=\"$ent_csv_monthly\"><div class=\"csvexport\">CSV</div></a></font><br>\n";
  print FHG "<table width=\"100%\"><tr><td><font size=\"-1\">Based on data from $date_end : $date_start (last month without last week) <a href=\"$ent_csv_monthly\"><div class=\"csvexport\">CSV</div></a></font></td>$how_it_works</tr></table>\n";

  #
  # last month
  #

  print FHD "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last month\">\n";
  print FHG "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last month\">\n";
  print FHD "$header\n";
  print FHG "$header\n";

  # CSV into monthly
  close(FHCSV);
  open( FHCSV, "> $ent_csv_monthly_all" ) || error( "could not open $ent_csv_monthly_all: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  print FHCSV $csv_header;

  # ERR && POOL

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_err_type) {
    if ( $type =~ m/^POOL$/ ) {
      $mon_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_err_srv[$indx] . ":" . $mon_err_hmc[$indx] . ":" . $mon_err_max[$indx] . ":" . $mon_err_max_reached[$indx] . ":" . $mon_err_lpar[$indx] . ":" . $mon_err_lpar_url[$indx] . ":" . $mon_err_entitle[$indx] . ":" . $mon_err_avrg[$indx] . ":" . $mon_err_mode[$indx] . ":" . $mon_err_size[$indx] . ":" . $mon_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "POOL", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "POOL", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # ERR && SH POOL
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_err_type) {
    if ( $type =~ m/^Shared POOL$/ ) {
      $mon_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_err_srv[$indx] . ":" . $mon_err_hmc[$indx] . ":" . $mon_err_max[$indx] . ":" . $mon_err_max_reached[$indx] . ":" . $mon_err_lpar[$indx] . ":" . $mon_err_lpar_url[$indx] . ":" . $mon_err_entitle[$indx] . ":" . $mon_err_avrg[$indx] . ":" . $mon_err_mode[$indx] . ":" . $mon_err_size[$indx] . ":" . $mon_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "Shared POOL", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "Shared POOL", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # ERR && LPAR
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_err_type) {
    if ( $type =~ m/LPAR/ ) {
      $mon_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_err_srv[$indx] . ":" . $mon_err_hmc[$indx] . ":" . $mon_err_max[$indx] . ":" . $mon_err_max_reached[$indx] . ":" . $mon_err_lpar[$indx] . ":" . $mon_err_lpar_url[$indx] . ":" . $mon_err_entitle[$indx] . ":" . $mon_err_avrg[$indx] . ":" . $mon_err_mode[$indx] . ":" . $mon_err_size[$indx] . ":" . $mon_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "LPAR", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "LPAR", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && POOL

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_war_type) {
    if ( $type =~ m/^POOL$/ ) {
      $mon_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_war_srv[$indx] . ":" . $mon_war_hmc[$indx] . ":" . $mon_war_max[$indx] . ":" . $mon_war_max_reached[$indx] . ":" . $mon_war_lpar[$indx] . ":" . $mon_war_lpar_url[$indx] . ":" . $mon_war_entitle[$indx] . ":" . $mon_war_avrg[$indx] . ":" . $mon_war_mode[$indx] . ":" . $mon_war_size[$indx] . ":" . $mon_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "POOL", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "POOL", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && SH POOL
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_war_type) {
    if ( $type =~ m/^Shared POOL$/ ) {
      $mon_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_war_srv[$indx] . ":" . $mon_war_hmc[$indx] . ":" . $mon_war_max[$indx] . ":" . $mon_war_max_reached[$indx] . ":" . $mon_war_lpar[$indx] . ":" . $mon_war_lpar_url[$indx] . ":" . $mon_war_entitle[$indx] . ":" . $mon_war_avrg[$indx] . ":" . $mon_war_mode[$indx] . ":" . $mon_war_size[$indx] . ":" . $mon_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "Shared POOL", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "Shared POOL", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && LPAR
  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_war_type) {
    if ( $type =~ m/LPAR/ ) {
      $mon_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_war_srv[$indx] . ":" . $mon_war_hmc[$indx] . ":" . $mon_war_max[$indx] . ":" . $mon_war_max_reached[$indx] . ":" . $mon_war_lpar[$indx] . ":" . $mon_war_lpar_url[$indx] . ":" . $mon_war_entitle[$indx] . ":" . $mon_war_avrg[$indx] . ":" . $mon_war_mode[$indx] . ":" . $mon_war_size[$indx] . ":" . $mon_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it( "LPAR", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it( "LPAR", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  print FHD "</tbody></table>\n";
  print FHG "</tbody></table>\n";
  print FHD "</div>\n";
  print FHG "</div>\n";

  #
  # Memory
  #

  print FHD "\n<div id=\"fragment-3\">\n";
  print FHG "\n<div id=\"fragment-3\">\n";
  print FHD "$title $legend_mem \n";
  print FHG "$title_gui $legend_mem \n";
  $date_start = strftime "%d-%m-%Y", localtime( time() - $DAY );
  print FHD "<font size=\"-1\">Based on data from $date_start (last day) <a href=\"$ent_mem_csv_daily\"><div class=\"csvexport\">CSV</div></a>It requires <a href =\"http://lpar2rrd.com/agent.htm\" target=\"_blank\">OS agent</a> v4.XXX running on all LPARs</font><br>\n";
  print FHG "<table width=\"100%\"><tr><td><font size=\"-1\">Based on data from $date_start (last day) <a href=\"$ent_mem_csv_daily\"><div class=\"csvexport\">CSV</div></a></font></td>$how_it_works</tr></table>\n";

  close(FHCSV);

  # CSV into daily
  open( FHCSV, "> $ent_mem_csv_daily_all" ) || error( "could not open $ent_mem_csv_daily_all: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  my $csv_mem_header = "Lpar$csv_separ" . "Server$csv_separ" . "Memory$csv_separ" . "Paging$csv_separ" . "Paging space$csv_separ" . "Paging rate/Avg$csv_separ" . "Paging rate/Max$csv_separ" . "Memory usage/Avg$csv_separ" . "Memory usage/Max$csv_separ" . "Advise-colour$csv_separ" . "Advise$csv_separ" . "Diff-colour$csv_separ" . "Diff\n";
  print FHCSV $csv_mem_header;

  #
  # last day
  #
  print FHD "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"Memory last day\">\n";
  print FHG "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"Memory last day\">\n";
  print FHD "$header_mem\n";
  print FHG "$header_mem\n";

  # ERR && MEM

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_err_type) {
    if ( $type =~ m/^MEM$/ ) {
      $day_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_err_srv[$indx] . ":" . $day_err_hmc[$indx] . ":" . $day_err_max[$indx] . ":" . $day_err_max_reached[$indx] . ":" . $day_err_lpar[$indx] . ":" . $day_err_lpar_url[$indx] . ":" . $day_err_entitle[$indx] . ":" . $day_err_avrg[$indx] . ":" . $day_err_mode[$indx] . ":" . $day_err_size[$indx] . ":" . $day_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_mem( "MEM", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_mem( "MEM", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && MEM

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_war_type) {
    if ( $type =~ m/^MEM$/ ) {
      $day_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_war_srv[$indx] . ":" . $day_war_hmc[$indx] . ":" . $day_war_max[$indx] . ":" . $day_war_max_reached[$indx] . ":" . $day_war_lpar[$indx] . ":" . $day_war_lpar_url[$indx] . ":" . $day_war_entitle[$indx] . ":" . $day_war_avrg[$indx] . ":" . $day_war_mode[$indx] . ":" . $day_war_size[$indx] . ":" . $day_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_mem( "MEM", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_mem( "MEM", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  print FHD "</tbody></table>\n";
  print FHG "</tbody></table>\n";
  print FHD "</div>\n";
  print FHG "</div>\n";

  print FHD "\n<div id=\"fragment-4\">\n";
  print FHG "\n<div id=\"fragment-4\">\n";
  print FHD "$title $legend_mem \n";
  print FHG "$title_gui $legend_mem \n";
  $date_start = strftime "%d-%m-%Y", localtime( time() - $DAY - $DAY );
  $date_end   = strftime "%d-%m-%Y", localtime( time() - $WEEK );
  print FHD "<font size=\"-1\">Based on data from $date_end : $date_start (last week without last day) <a href=\"$ent_mem_csv_weekly\"><div class=\"csvexport\">CSV</div></a>It requires <a href =\"http://lpar2rrd.com/agent.htm\" target=\"_blank\">OS agent</a> v4.XXX running on all LPARs</font><br>\n";
  print FHG "<table width=\"100%\"><tr><td><font size=\"-1\">Based on data from $date_end : $date_start (last week without last day) <a href=\"$ent_mem_csv_weekly\"><div class=\"csvexport\">CSV</div></a></font></td>$how_it_works</tr></table>\n";

  close(FHCSV);

  # CSV into weekly
  open( FHCSV, "> $ent_mem_csv_weekly_all" ) || error( "could not open $ent_mem_csv_weekly_all: $! " . __FILE__ . ":" . __LINE__ ) && return 0;

  #
  # last week
  #

  print FHD "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last week\">\n";
  print FHG "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last week\">\n";
  print FHD "$header_mem\n";
  print FHG "$header_mem\n";

  print FHCSV $csv_mem_header;

  # ERR && MEM

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_err_type) {
    if ( $type =~ m/^MEM$/ ) {
      $wee_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_err_srv[$indx] . ":" . $wee_err_hmc[$indx] . ":" . $wee_err_max[$indx] . ":" . $wee_err_max_reached[$indx] . ":" . $wee_err_lpar[$indx] . ":" . $wee_err_lpar_url[$indx] . ":" . $wee_err_entitle[$indx] . ":" . $wee_err_avrg[$indx] . ":" . $wee_err_mode[$indx] . ":" . $wee_err_size[$indx] . ":" . $wee_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_mem( "MEM", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_mem( "MEM", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && MEM

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_war_type) {
    if ( $type =~ m/^MEM$/ ) {
      $wee_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_war_srv[$indx] . ":" . $wee_war_hmc[$indx] . ":" . $wee_war_max[$indx] . ":" . $wee_war_max_reached[$indx] . ":" . $wee_war_lpar[$indx] . ":" . $wee_war_lpar_url[$indx] . ":" . $wee_war_entitle[$indx] . ":" . $wee_war_avrg[$indx] . ":" . $wee_war_mode[$indx] . ":" . $wee_war_size[$indx] . ":" . $wee_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_mem( "MEM", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_mem( "MEM", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  print FHD "</tbody></table>\n";
  print FHG "</tbody></table>\n";
  print FHD "\n</div>\n";
  print FHG "\n</div>\n";

  print FHD "\n<div id=\"fragment-5\">\n";
  print FHG "\n<div id=\"fragment-5\">\n";
  print FHD "$title $legend_mem \n";
  print FHG "$title_gui $legend_mem \n";
  $date_start = strftime "%d-%m-%Y", localtime( time() - $WEEK - $DAY );
  $date_end   = strftime "%d-%m-%Y", localtime( time() - $MONTH );
  print FHD "<font size=\"-1\">Based on data from $date_end : $date_start (last month without last week) <a href=\"$ent_mem_csv_monthly\"><div class=\"csvexport\">CSV</div></a>It requires <a href =\"http://lpar2rrd.com/agent.htm\" target=\"_blank\">OS agent</a> v4.XXX running on all LPARs</font><br>\n";
  print FHG "<table width=\"100%\"><tr><td><font size=\"-1\">Based on data from $date_end : $date_start (last month without last week) <a href=\"$ent_mem_csv_monthly\"><div class=\"csvexport\">CSV</div></a></font></td>$how_it_works</tr></table>\n";

  #
  # last month
  #

  print FHD "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last month\">\n";
  print FHG "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"MAX CPU error last month\">\n";
  print FHD "$header_mem\n";
  print FHG "$header_mem\n";

  # CSV into monthly
  close(FHCSV);
  open( FHCSV, "> $ent_mem_csv_monthly_all" ) || error( "could not open $ent_mem_csv_monthly_all: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  print FHCSV $csv_mem_header;

  # ERR && MEM

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_err_type) {
    if ( $type =~ m/^MEM$/ ) {
      $mon_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_err_srv[$indx] . ":" . $mon_err_hmc[$indx] . ":" . $mon_err_max[$indx] . ":" . $mon_err_max_reached[$indx] . ":" . $mon_err_lpar[$indx] . ":" . $mon_err_lpar_url[$indx] . ":" . $mon_err_entitle[$indx] . ":" . $mon_err_avrg[$indx] . ":" . $mon_err_mode[$indx] . ":" . $mon_err_size[$indx] . ":" . $mon_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_mem( "MEM", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_mem( "MEM", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && MEM

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_war_type) {
    if ( $type =~ m/^MEM$/ ) {
      $mon_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_war_srv[$indx] . ":" . $mon_war_hmc[$indx] . ":" . $mon_war_max[$indx] . ":" . $mon_war_max_reached[$indx] . ":" . $mon_war_lpar[$indx] . ":" . $mon_war_lpar_url[$indx] . ":" . $mon_war_entitle[$indx] . ":" . $mon_war_avrg[$indx] . ":" . $mon_war_mode[$indx] . ":" . $mon_war_size[$indx] . ":" . $mon_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_mem( "MEM", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_mem( "MEM", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  print FHD "</tbody></table>\n";
  print FHG "</tbody></table>\n";
  print FHD "</div>\n";
  print FHG "</div>\n";
  close(FHCSV);

  open( FHCSV, "> $ent_io_csv_all" ) || error( "could not open $ent_io_csv_all: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  #
  #  IO
  #

  print FHD "\n<div id=\"fragment-6\">\n";
  print FHG "\n<div id=\"fragment-6\">\n";
  print FHD "$title $legend_io \n";
  print FHG "$title_gui $legend_io \n";
  $date_start = strftime "%d-%m-%Y", localtime( time() - $DAY );
  print FHD "<font size=\"-1\">Based on data from $date_start (last day) <!-- <a href=\"$ent_csv_daily\">CSV</a> --> </font><br>\n";
  print FHG "<table width=\"100%\"><tr><td><font size=\"-1\">Based on data from $date_start (last day) <!-- <a href=\"$ent_csv_daily\">CSV</a> --> </font></td>$how_it_works</tr></table>\n";

  #
  # last day
  #
  print FHD "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"IO last day\">\n";
  print FHG "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"IO last day\">\n";
  print FHD "$header_io\n";
  print FHG "$header_io\n";

  # ERR && IO

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_err_type) {
    if ( $type =~ m/^IO$/ ) {
      $day_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_err_srv[$indx] . ":" . $day_err_hmc[$indx] . ":" . $day_err_max[$indx] . ":" . $day_err_max_reached[$indx] . ":" . $day_err_lpar[$indx] . ":" . $day_err_lpar_url[$indx] . ":" . $day_err_entitle[$indx] . ":" . $day_err_avrg[$indx] . ":" . $day_err_mode[$indx] . ":" . $day_err_size[$indx] . ":" . $day_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_io( "IO", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_io( "IO", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && IO

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@day_war_type) {
    if ( $type =~ m/^IO$/ ) {
      $day_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $day_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $day_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $day_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $day_war_srv[$indx] . ":" . $day_war_hmc[$indx] . ":" . $day_war_max[$indx] . ":" . $day_war_max_reached[$indx] . ":" . $day_war_lpar[$indx] . ":" . $day_war_lpar_url[$indx] . ":" . $day_war_entitle[$indx] . ":" . $day_war_avrg[$indx] . ":" . $day_war_mode[$indx] . ":" . $day_war_size[$indx] . ":" . $day_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_io( "IO", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_io( "IO", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  print FHD "</tbody></table>\n";
  print FHG "</tbody></table>\n";
  print FHD "</div>\n";
  print FHG "</div>\n";

  print FHD "\n<div id=\"fragment-7\">\n";
  print FHG "\n<div id=\"fragment-7\">\n";
  print FHD "$title $legend_io \n";
  print FHG "$title_gui $legend_io \n";
  $date_start = strftime "%d-%m-%Y", localtime( time() - $DAY - $DAY );
  $date_end   = strftime "%d-%m-%Y", localtime( time() - $WEEK );
  print FHD "<font size=\"-1\">Based on data from $date_end : $date_start (last week without last day) <!-- <a href=\"$ent_csv_weekly\">CSV</a> --> </font><br>\n";
  print FHG "<table width=\"100%\"><tr><td><font size=\"-1\">Based on data from $date_end : $date_start (last week without last day) <!-- <a href=\"$ent_csv_weekly\">CSV</a> --> </font></td>$how_it_works</tr></table>\n";

  #
  # last week
  #

  print FHD "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"IO last week\">\n";
  print FHG "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"IO last week\">\n";
  print FHD "$header_io\n";
  print FHG "$header_io\n";

  # CSV into weekly
  #close (FHCSV);
  #open(FHCSV, "> $ent_csv_weekly_all") || error("could not open $ent_csv_weekly_all: $! ".__FILE__.":".__LINE__) && return 0;
  #print FHCSV $csv_header;

  # ERR && IO

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_err_type) {
    if ( $type =~ m/^IO$/ ) {
      $wee_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_err_srv[$indx] . ":" . $wee_err_hmc[$indx] . ":" . $wee_err_max[$indx] . ":" . $wee_err_max_reached[$indx] . ":" . $wee_err_lpar[$indx] . ":" . $wee_err_lpar_url[$indx] . ":" . $wee_err_entitle[$indx] . ":" . $wee_err_avrg[$indx] . ":" . $wee_err_mode[$indx] . ":" . $wee_err_size[$indx] . ":" . $wee_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_io( "IO", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_io( "IO", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && IO

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@wee_war_type) {
    if ( $type =~ m/^IO$/ ) {
      $wee_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $wee_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $wee_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $wee_war_srv[$indx] . ":" . $wee_war_hmc[$indx] . ":" . $wee_war_max[$indx] . ":" . $wee_war_max_reached[$indx] . ":" . $wee_war_lpar[$indx] . ":" . $wee_war_lpar_url[$indx] . ":" . $wee_war_entitle[$indx] . ":" . $wee_war_avrg[$indx] . ":" . $wee_war_mode[$indx] . ":" . $wee_war_size[$indx] . ":" . $wee_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_io( "IO", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_io( "IO", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  print FHD "</tbody></table>\n";
  print FHG "</tbody></table>\n";
  print FHD "\n</div>\n";
  print FHG "\n</div>\n";

  print FHD "\n<div id=\"fragment-8\">\n";
  print FHG "\n<div id=\"fragment-8\">\n";
  print FHD "$title $legend_io \n";
  print FHG "$title_gui $legend_io \n";
  $date_start = strftime "%d-%m-%Y", localtime( time() - $WEEK - $DAY );
  $date_end   = strftime "%d-%m-%Y", localtime( time() - $MONTH );
  print FHD "<font size=\"-1\">Based on data from $date_end : $date_start (last month without last week) <!-- <a href=\"$ent_csv_monthly\">CSV</a> --> </font><br>\n";
  print FHG "<table width=\"100%\"><tr><td><font size=\"-1\">Based on data from $date_end : $date_start (last month without last week) <!-- <a href=\"$ent_csv_monthly\">CSV</a> --> </font></td>$how_it_works</tr></table>\n";

  #
  # last month
  #

  print FHD "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"IO last month\">\n";
  print FHG "<TABLE class=\"tabadvisor tablesorter\" SUMMARY=\"IO last month\">\n";
  print FHD "$header_io \n";
  print FHG "$header_io \n";

  # CSV into monthly
  #close (FHCSV);
  #open(FHCSV, "> $ent_csv_monthly_all") || error("could not open $ent_csv_monthly_all: $! ".__FILE__.":".__LINE__) && return 0;
  #print FHCSV $csv_header;

  # ERR && IO

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_err_type) {
    if ( $type =~ m/^IO$/ ) {
      $mon_err_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_err_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_err_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_err_srv[$indx] . ":" . $mon_err_hmc[$indx] . ":" . $mon_err_max[$indx] . ":" . $mon_err_max_reached[$indx] . ":" . $mon_err_lpar[$indx] . ":" . $mon_err_lpar_url[$indx] . ":" . $mon_err_entitle[$indx] . ":" . $mon_err_avrg[$indx] . ":" . $mon_err_mode[$indx] . ":" . $mon_err_size[$indx] . ":" . $mon_err_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_io( "IO", $type, 0, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_io( "IO", $type, 0, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }

  # WAR && IO

  $indx     = 0;
  $indx_all = 0;
  @selected = "";

  # first insert all valid for that into a structure @selected    for future sorting
  foreach my $type (@mon_war_type) {
    if ( $type =~ m/^IO$/ ) {
      $mon_war_srv[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_hmc[$indx]      =~ s/:/====double_colon====/g;
      $mon_war_lpar[$indx]     =~ s/:/====double_colon====/g;
      $mon_war_lpar_url[$indx] =~ s/:/====double_colon====/g;
      $selected[$indx_all] = $mon_war_srv[$indx] . ":" . $mon_war_hmc[$indx] . ":" . $mon_war_max[$indx] . ":" . $mon_war_max_reached[$indx] . ":" . $mon_war_lpar[$indx] . ":" . $mon_war_lpar_url[$indx] . ":" . $mon_war_entitle[$indx] . ":" . $mon_war_avrg[$indx] . ":" . $mon_war_mode[$indx] . ":" . $mon_war_size[$indx] . ":" . $mon_war_pg[$indx];
      $indx_all++;
    }
    $indx++;
  }

  if ( $indx_all > 0 ) {
    @selected = reverse sort { ( split ':', $a )[3] <=> ( split ':', $b )[3] } @selected;    #reverse numeric sorting per max_reached

    foreach my $type (@selected) {
      $text = print_it_io( "IO", $type, 1, *FHL, *FHCSV, 0 );
      print FHD $text;
      $text = print_it_io( "IO", $type, 1, *FHL, *FHCSV, 1 );
      print FHG $text;
    }
  }
  print FHD "</tbody></table>\n";
  print FHG "</tbody></table>\n";
  print FHD "</div>\n";
  print FHG "</div>\n";

  print FHD "\n<div id=\"fragment-9\">\n";
  print FHG "\n<div id=\"fragment-9\">\n";

  #print FHD "HONZA-START";
  #print FHG "HONZA-START";
  my $how_it_works_smart_trends = "<td  valign=\"top\" nowrap align=\"right\"><font size=\"-1\">
                      <a href=\"https://lpar2rrd.com/smart_trends.php\" target=\"_blank\" valign=\"center\">How it works</a></font></td>";
  print FHG "<table width=\"100%\"><tr>$how_it_works_smart_trends</tr></table>\n";

  print FHD print_html_file("$basedir/www/smart_trends.html") if ( -e "$basedir/www/smart_trends.html" );
  print FHG print_html_file("$basedir/www/smart_trends.html") if ( -e "$basedir/www/smart_trends.html" );

  #print FHD "HONZA-END";
  #print FHG "HONZA-END";
  print FHD "</div>\n";
  print FHG "</div>\n";

  print FHD "</div>\n";
  print FHG "</div>\n";

  print FHD "<br><font size=\"-1\">Report has been created at: $act_time<br></font>\n";
  print FHG "<br><font size=\"-1\">Report has been created at: $act_time<br></font>\n";
  print FHD "<br><ul><li><font size=\"-1\"><b>CPU:</b> There are listed only those LPARs or CPU pools where at least one $step_interval_min MIN peak in given time period has been higher or equal of their entitlement.<br>\n";
  print FHG "<br><ul><li><font size=\"-1\"><b>CPU:</b> There are listed only those LPARs or CPU pools where at least one $step_interval_min MIN peak in given time period has been higher or equal of their entitlement.<br>\n";
  print FHD "There are also listed LPARs or CPU pools which have unnecessary high CPU entitlement.</font><br></li>\n";
  print FHG "There are also listed LPARs or CPU pools which have unnecessary high CPU entitlement.</font><br></li>\n";
  print FHD "<br><li><font size=\"-1\"><b>MEM:</b> There are listed only those LPARs where seems to be lack of memory or where memory can be reduced</font></li></ul><br>\n";
  print FHG "<br><li><font size=\"-1\"><b>MEM:</b> There are listed only those LPARs where seems to be lack of memory or where memory can be reduced</font></li></ul><br>\n";

  print FHD "</body></html>\n";

  close(FHD);
  close(FHG);
  close(FHL);
  close(FHCSV);

  return 1;
}

#
# main engine
#

# IO engine

sub print_it_io {
  my $name_item = shift;
  my $line      = shift;

  #my $FH = shift;
  my $alert_type    = shift;    # panic 0, warning 1
  my $FHL           = shift;
  my $FHCSV         = shift;
  my $new_gui       = shift;
  my $ram           = "ok";
  my $ram_diff      = 0;
  my $ram_web       = "";
  my $ram_diff_web  = "";
  my $color_io_peak = " ";
  my $color_io_avrg = " ";
  my $color         = " ";

  ( my $server, my $host, my $tr5, my $io_peak, my $name, my $name_url, my $tr3, my $io_avrg, my $tr1, my $tr4, my $tr2 ) = split( /:/, $line );

  # update_struct("IO","ERROR",$time_range,$lpar_url,$lpar_name,$server,$hmc,0,$uniq_name,$io_peak,$io_avrg,0,0,0,0);

  #print "008 $name_item : $line : $alert_type : io_avrg:$io_avrg - io_peak:$io_peak | $tr5 - $tr4 - $tr3 - $tr1 - $tr2\n";

  # just to be sure ...
  if ( $server eq '' || $host eq '' || $io_avrg eq '' || $io_peak eq '' ) {
    return "";
  }

  $server   =~ s/====double_colon====/:/g;
  $host     =~ s/====double_colon====/:/g;
  $name     =~ s/====double_colon====/:/g;
  $name     =~ s/\&\&1/\//g;
  $name_url =~ s/====double_colon====/:/g;
  $name_url =~ s/\&\&1/\//g;
  $name_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;    # PH: keep is as it is exactly!!
  $name_url =~ s/\+/ /g;
  $name_url =~ s/\#/%23/g;
  my $server_url = $server;
  $server_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  $server_url =~ s/\+/ /g;
  $server_url =~ s/\#/%23/g;

  #
  # warning == recommended
  #
  if ( $io_peak > $IO_PEAK_MAX ) {
    $color         = $color_warning;
    $color_io_peak = $color_warning;
  }
  if ( $io_avrg > $IO_AVRG_MAX ) {
    $color         = $color_warning;
    $color_io_avrg = $color_warning;
  }

  #
  # recomen == strongly recommended
  #
  if ( $io_peak > $IO_PEAK_WARN ) {
    $color         = $color_recomend;
    $color_io_peak = $color_recomend;
  }
  if ( $io_avrg > $IO_AVRG_WARN ) {
    $color         = $color_recomend;
    $color_io_avrg = $color_recomend;
  }

  #
  # critical == must
  #
  if ( $io_avrg > $IO_AVRG_CRIT ) {
    $color = $color_panic;

    #$color_io_peak = $color_panic;
    $color_io_avrg = $color_panic;
  }

  # conversion to web format
  my $io_peak_web = sprintf( "%+5s", $io_peak );
  $io_peak_web =~ s/ /\&nbsp;/g;
  my $io_avrg_web = sprintf( "%+5s", $io_avrg );
  $io_avrg_web =~ s/ /\&nbsp;/g;

  my $server_index = "index.html";
  if ( $new_gui == 1 ) {
    $server_index = "gui-cpu.html";
    print FHCSV "$name$csv_separ$server$csv_separ$io_peak$csv_separ$io_avrg$csv_separ\n";    # print it once
  }

  return "<tr><td nowrap >&nbsp;<a class=\"backlink\" href=\"/lpar2rrd-cgi/detail.sh?host=$host&server=$server_url&lpar=$name_url&item=lpar&entitle=$entitle_less&none=none\" target=\"sample\">$name</A>&nbsp;&nbsp;&nbsp;</td><td nowrap >&nbsp;<A HREF=\"$host/$server_url/pool/$server_index\" target=\"main\">$server</A>&nbsp;&nbsp;&nbsp;</td><td $color_io_peak title=\"CPU IO wait peak %\" align=\"center\">$io_peak_web</td><td $color_io_avrg title=\"CPU IO wait average in %\" align=\"center\" >$io_avrg_web</td></tr>\n";

}
#
# How it works, rules ... exact limits are parametrized on the top
#
# Mem
# avg %util > 90% --> light red
#           > 80% --> yellow
# max peak  > 95% --> light red
#           > 90 --> yellow
#
# Paging rate
# avg > 10kB/sec --> red
# peak > 1MB/sec --> red
#
#
# Paging space utilization
# > 50% --> yellow
# > 80% --> ligyt red
# > 90% --> red
#
#
# Identify of overusage of memory
# Mem
#  --> if no any alert then
# 10% in higest peak must be there reserve, rest is wasting
# 100 - %peak - 10% --> if above 0 then report as green
#
#

sub print_it_mem {
  my $name_item = shift;
  my $line      = shift;

  #my $FH = shift;
  my $alert_type          = shift;    # panic 0, warning 1
  my $FHL                 = shift;
  my $FHCSV               = shift;
  my $new_gui             = shift;
  my $ram                 = "ok";
  my $ram_diff            = 0;
  my $ram_web             = "";
  my $ram_diff_web        = "";
  my $color_pgs_util_peak = " ";
  my $color_mem_peak      = " ";
  my $color_mem_avrg      = " ";
  my $color_pgs_peak      = " ";
  my $color_pgs_avrg      = " ";
  my $color               = " ";
  my $color_csv           = " ";
  my $color_diff_csv      = " ";

  ( my $server, my $host, my $pgs_util_peak, my $mem_peak, my $name, my $name_url, my $pgs_peak, my $mem_avrg, my $pgs_avrg, my $mem_size, my $pg_size ) = split( /:/, $line );

  # update_struct("MEM","WARNING",$time_range,$lpar_url,$lpar_name,$server,$hmc,$pgs_util_peak,$uniq_name,$mem_peak,$mem_avrg,$pgs_peak,$pgs_avrg);

  #print "008 $name_item : $line : $alert_type\n";

  # just to be sure ...
  if ( $server eq '' || $host eq '' || $mem_avrg eq '' || $mem_peak eq '' ) {
    return "";
  }

  $server   =~ s/====double_colon====/:/g;
  $host     =~ s/====double_colon====/:/g;
  $name     =~ s/====double_colon====/:/g;
  $name     =~ s/\&\&1/\//g;
  $name_url =~ s/====double_colon====/:/g;
  $name_url =~ s/\&\&1/\//g;
  $name_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;    # PH: keep is as it is exactly!!
  $name_url =~ s/\+/ /g;
  $name_url =~ s/\#/%23/g;
  my $server_url = $server;
  $server_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  $server_url =~ s/\+/ /g;
  $server_url =~ s/\#/%23/g;

  #
  # noted
  #
  if ( $mem_peak < $MEM_PEAK_LOW ) {
    $color     = $color_noted;
    $color_csv = "green";
    $ram       = $mem_size - ( $mem_size / 100 * ( $MEM_SAFE_LIM - $mem_peak ) );
    $ram_diff  = $ram - $mem_size;
  }

  #
  # warning == recommended
  #
  if ( $mem_peak > $MEM_PEAK_LIM ) {
    $color          = $color_warning;
    $color_csv      = "yellow";
    $color_mem_peak = $color_warning;
  }
  if ( $mem_avrg > $MEM_AVRG_LIM ) {
    $color          = $color_warning;
    $color_csv      = "yellow";
    $color_mem_avrg = $color_warning;
  }

  #
  # recomen == strongly recommended
  #
  if ( $pgs_util_peak > $PGS_UTIL_LIM ) {
    $color               = $color_recomend;
    $color_csv           = "light red";
    $color_pgs_util_peak = $color_recomend;
  }
  if ( $pgs_peak > $PGS_PEAK_LIM ) {
    $color          = $color_recomend;
    $color_csv      = "light red";
    $color_pgs_peak = $color_recomend;
  }
  if ( $pgs_avrg > $PGS_AVRG_LIM ) {
    $color          = $color_recomend;
    $color_csv      = "light red";
    $color_pgs_avrg = $color_recomend;
  }
  if ( $mem_peak > $MEM_PEAK_WARN ) {
    $color          = $color_recomend;
    $color_csv      = "light red";
    $color_mem_peak = $color_recomend;
  }
  if ( $mem_avrg > $MEM_AVRG_WARN ) {
    $color          = $color_recomend;
    $color_csv      = "light red";
    $color_mem_avrg = $color_recomend;
  }

  #
  # critical == must
  #
  if ( $pgs_util_peak > $PGS_UTIL_CRIT ) {
    $color               = $color_panic;
    $color_csv           = "red";
    $color_pgs_util_peak = $color_panic;
  }
  if ( $pgs_peak > $PGS_PEAK_CRIT ) {
    $color          = $color_panic;
    $color_csv      = "red";
    $color_pgs_peak = $color_panic;
    $ram            = $mem_size + ( $mem_size / 100 * $MEM_ADD );    # add 5% typically
    $ram_diff       = $ram - $mem_size;
  }
  if ( $pgs_avrg > $PGS_AVRG_CRIT ) {
    $color          = $color_panic;
    $color_csv      = "red";
    $color_pgs_avrg = $color_panic;
    $ram            = $mem_size + ( $mem_size / 100 * $MEM_ADD );    # add 5% typically
    $ram_diff       = $ram - $mem_size;
  }
  if ( $mem_peak > $MEM_PEAK_CRIT ) {
    $color          = $color_panic;
    $color_csv      = "red";
    $color_mem_peak = $color_panic;
    $ram            = $mem_size + ( $mem_size / 100 * $MEM_ADD );    # add 5% typically
    $ram_diff       = $ram - $mem_size;
  }
  if ( $mem_avrg > $MEM_AVRG_CRIT ) {
    $color          = $color_panic;
    $color_csv      = "red";
    $color_mem_avrg = $color_panic;
    $ram            = $mem_size + ( $mem_size / 100 * $MEM_ADD );    # add 5% typically
    $ram_diff       = $ram - $mem_size;
  }

  #
  # suggest memory change
  #
  if ( $pgs_avrg > $PGS_AVRG_LIM && $mem_peak > $MEM_PEAK_LIM ) {
    $ram      = $mem_size + ( $mem_size / 100 * $MEM_ADD_LIM );    # add 5% typically
    $ram_diff = $ram - $mem_size;
  }
  if ( $pgs_peak > $PGS_PEAK_CRIT && $pgs_avrg > $PGS_AVRG_CRIT && $mem_peak > $MEM_PEAK_CRIT ) {
    $ram      = $mem_size + ( $mem_size / 100 * $MEM_ADD_CRIT );    # add 15% typically
    $ram_diff = $ram - $mem_size;
  }

  # conversion to web format
  if ( $pgs_util_peak == -1 ) {
    $pgs_util_peak = " ";
  }
  my $pgs_util_peak_web = sprintf( "%+5s", $pgs_util_peak );
  $pgs_util_peak_web =~ s/ /\&nbsp;/g;

  if ( $pgs_avrg == -1 ) {
    $pgs_avrg = " ";
  }
  my $pgs_avrg_web = sprintf( "%+5s", $pgs_avrg );
  $pgs_avrg_web =~ s/ /\&nbsp;/g;

  if ( $pgs_peak == -1 ) {
    $pgs_peak = " ";
  }
  my $pgs_peak_web = sprintf( "%+5s", $pgs_peak );
  $pgs_peak_web =~ s/ /\&nbsp;/g;

  my $mem_avrg_web = sprintf( "%+5s", $mem_avrg );
  $mem_avrg_web =~ s/ /\&nbsp;/g;

  my $mem_peak_web = sprintf( "%+5s", $mem_peak );
  $mem_peak_web =~ s/ /\&nbsp;/g;

  my $color_diff = $color;
  $color_diff_csv = $color_csv;
  if ( $ram =~ m/ok/ || $ram == 0 ) {
    $ram_web        = sprintf( "%+5s", $ram );
    $color_diff     = "";
    $color_diff_csv = " ";
  }
  else {
    $ram_web = sprintf( "%+5s", sprintf( "%.1f", $ram / 1024 ) );
  }
  my $ram_csv = $ram_web;
  $ram_web =~ s/ /\&nbsp;/g;
  $ram_diff_web = sprintf( "%+5s", sprintf( "%.1f", $ram_diff / 1024 ) );
  my $ram_diff_csv = $ram_diff_web;
  $ram_diff_web =~ s/ /\&nbsp;/g;
  my $mem_size_web = sprintf( "%+5s", sprintf( "%.1f", $mem_size / 1024 ) );
  my $mem_size_csv = $mem_size_web;
  $mem_size_web =~ s/ /\&nbsp;/g;
  my $pg_size_web = sprintf( "%+5s", sprintf( "%.1f", $pg_size / 1024 ) );
  $pg_size_web =~ s/-0.0//;    # agent 1.x does not send paging size
  my $pg_size_csv = $pg_size_web;
  $pg_size_web =~ s/ /\&nbsp;/g;

  my $server_index = "index.html";
  if ( $new_gui == 1 ) {
    $server_index = "gui-cpu.html";
    print FHCSV "$name$csv_separ$server$csv_separ$mem_size_csv$csv_separ$pg_size_csv$csv_separ$pgs_util_peak$csv_separ$pgs_avrg$csv_separ$pgs_peak$csv_separ$mem_avrg$csv_separ$mem_peak$csv_separ$color_csv$csv_separ$ram_csv$csv_separ$color_diff_csv$csv_separ$ram_diff_csv\n";    # print it once
  }

  return "<tr><td nowrap >&nbsp;<A class=\"backlink\" HREF=\"/lpar2rrd-cgi/detail.sh?host=$host&server=$server_url&lpar=$name_url&item=lpar&entitle=$entitle_less&none=none\" target=\"sample\">$name</A>&nbsp;&nbsp;&nbsp;</td><td nowrap >&nbsp;<A HREF=\"$host/$server_url/pool/$server_index\" target=\"main\">$server</A>&nbsp;&nbsp;&nbsp;</td><td title=\"Memory size\" align=\"center\" >$mem_size_web</td><td title=\"Paging size\" align=\"center\" >$pg_size_web</td><td $color_pgs_util_peak title=\"Paging space max\" align=\"center\">$pgs_util_peak_web</td><td $color_pgs_avrg title=\"Paging rate average in kBytes\" align=\"center\" >$pgs_avrg_web</td><td $color_pgs_peak title=\"Paging rate peak in kBytes\" align=\"center\" >$pgs_peak_web</td><td $color_mem_avrg title=\"Memory usage average in %\" align=\"center\" >$mem_avrg_web</td><td $color_mem_peak title=\"Memory usage peak in %\" align=\"center\">$mem_peak_web</td><td  title=\"Sugested memory size in GB\" $color align=\"center\"><b>$ram_web</b></td><td title=\"Difference to actual memory in GB\" $color_diff align=\"center\">$ram_diff_web</td></tr>\n";

}

sub print_it {
  my $lpar_pool = shift;
  my $line      = shift;

  #my $FH = shift;
  my $alert_type       = shift;                                                                                                                                                                                                                                                       # panic 0, warning 1
  my $FHL              = shift;
  my $FHCSV            = shift;
  my $new_gui          = shift;
  my $color_it_ent     = " ";
  my $color_it_vp      = " ";
  my $color_it_ent_csv = " ";
  my $color_it_vp_csv  = " ";

  my $name_item_tmp = $lpar_pool;
  $name_item_tmp =~ s/Shared/SH/;
  my $name_item = sprintf( "%-7s", "$name_item_tmp" );
  if ( $alert_type == 1 ) {

    # just warning
    $color = "$color_warning";
  }

  ( my $server, my $host, my $max, my $max_reach, my $name, my $name_url, my $entitled, my $avrg, my $sh_mode ) = split( /:/, $line );

  #print "008 $lpar_pool : $line : $alert_type\n";

  # just to be sure ...
  if ( $server eq '' || $host eq '' || $max eq '' || $max_reach eq '' || $name eq '' ) {
    return "";
  }
  if ( $name_url eq '' || $entitled eq '' || $avrg eq '' || $sh_mode eq '' ) {
    return "";
  }
  if ( $max == 0 || $max_reach == 0 || $entitled == 0 || $avrg == 0 ) {
    return "";
  }

  $server   =~ s/====double_colon====/:/g;
  $host     =~ s/====double_colon====/:/g;
  $name     =~ s/====double_colon====/:/g;
  $name     =~ s/\&\&1/\//g;
  $name_url =~ s/====double_colon====/:/g;
  $name_url =~ s/\&\&1/\//g;

  #$name_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg; # PH: keep it is it is exactly!!!
  #$name_url =~ s/ /+/g;
  #$name_url =~ s/\#/%23/g;
  $name_url =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  my $server_url = $server;
  $server_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  $server_url =~ s/\+/ /g;
  $server_url =~ s/\#/%23/g;

  #my $max_web = sprintf ("%3.0f",$max); # pools

  my $en_vp     = sprintf( "%3.1f", $max / $entitled );
  my $en_vp_web = sprintf( "%+5s",  $en_vp );
  $en_vp_web =~ s/ /\&nbsp;/g;

  my $max_ent     = sprintf( "%3.1f", $max_reach / $entitled );
  my $max_ent_web = sprintf( "%+5s",  $max_ent );
  $max_ent_web =~ s/ /\&nbsp;/g;

  my $avrg_ent     = sprintf( "%3.1f", $avrg / $entitled );
  my $avrg_ent_web = sprintf( "%+5s",  $avrg_ent );
  $avrg_ent_web =~ s/ /\&nbsp;/g;

  my $vp = "ok";
  if ( $alert_type == 0 || ( $max - $max_reach ) < ( ( $max / 100 ) * 5 ) ) {    # when util reaches 95% then this consider also for panic
                                                                                 #print "009 ($max - $max_reach) < (($max / 100) * 5 )\n";
                                                                                 # panic, it has reached max logical CPU
    $vp              = $max + 1;
    $color_it_vp     = " title=\"It is a must to increase number of Virtual (Logical) processors from $max to $vp\" $color_panic";
    $color_it_vp_csv = "red";
    print "$name_item ERROR  : $name:$server:$host : it is recommended to increase virtual processors to $vp (max_reach: $max_reach)\n";
    print FHL "$ltime_str: $name_item ERROR  : $name:$server:$host : it is recommended to increase virtual processors to $vp (max_reach: $max_reach)\n";
  }

  my $ent     = "ok";
  my $ent_tmp = "$ent";
  if ( $max_ent > $MAX_ENT && $avrg > ( ( $entitled / 100 ) * 50 ) && $name !~ m/^all.*pools$/ ) {

    # if $max_ent > $MAX_ENT and average utils is above 50% of entitled
    # if Max/Ent > $MAX_ENT (lpar2rrd.cfg: default 2) then yellow
    $ent = $max_reach / $MAX_ENT;
    my $avrg_est = $avrg * 3;    # 3 time average
    if ( $avrg_est < $ent && $avrg_est > $entitled ) {
      $ent = $avrg_est;          # if avrg x 3 < Max/Ent then use it
    }
    if ( ( $avrg * 3 ) < $ent ) {
      $ent = $avrg * 3;
    }
    $ent_tmp = sprintf( "%3.1f", $ent );
    if ( $ent_tmp > $entitled ) {
      $color_it_ent     = " title=\"It is recommended to increase CPU entitlement from $entitled to $ent\" $color_warning";
      $color_it_ent_csv = "yellow";
      print "$name_item WARN   : $name:$server:$host : it is recommended to increase CPU entitlement $ent\n";
      print FHL "$ltime_str: $name_item WARN   : $name:$server:$host : it is recommended to increase CPU entitlement $ent\n";
    }
    else {
      $ent = "ok";
    }
  }

  if ( $avrg_ent > 0.6 && $name !~ m/^all.*pools$/ ) {

    # if average > ent then recomend, set recomendation to 2 x average
    $ent = sprintf( "%3.2f", $avrg * 2 );
    my $max_reach_half = $max_reach / 2;
    if ( $ent > $max_reach_half ) {

      # if recomendation ent > half of maximal peak then use half of max peak
      $ent = $max_reach_half;
    }
    if ( $ent < $entitled ) {
      $ent = $entitled + ( $entitled / 2 );
    }
    if ( $ent == $entitled ) {
      $ent = $entitled + ( $entitled / 5 );    # + 20%
    }
    if ( ( $max - $avrg ) < ( $max / 5 ) ) {    # if average load is at 80% of max
      $ent = $max + 1;                          # this + 1 will be restricted bellow if necessary
    }

    # restriction to do not go over VP or new sugested VP
    if ( $vp =~ m/ok/ ) {
      if ( $ent > $max ) {
        $ent = $max;
      }
    }
    else {
      if ( $ent > $vp ) {
        $ent = $vp;
      }
    }
    if ( $ent < $avrg ) {
      $ent = $avrg + $avrg / 10;    # if suggested entitlement after all above is still bellow average then average +10%
    }

    $ent_tmp = sprintf( "%3.1f", $ent );    # rounding to one decimal
    if ( $ent_tmp > $entitled ) {
      if ( $avrg_ent > 2 ) {

        # strong everage oveload of entitlement --> panic
        $color_it_ent     = " title=\"It is a must to increase CPU entitlement from $entitled to $ent\" $color_panic";
        $color_it_ent_csv = "red";
      }
      else {
        $color_it_ent     = " title=\"It is strongly recommended to increase CPU entitlement from $entitled to $ent\" $color_recomend";
        $color_it_ent_csv = "light red";
      }
      print "$name_item RECOME : $name:$server:$host : it is recommended to increase CPU entitlement $ent\n";
      print FHL "$ltime_str: $name_item RECOME : $name:$server:$host : it is recommended to increase CPU entitlement $ent\n";
    }
    else {
      $ent = "ok";
    }
  }

  # capped lpars
  if ( $sh_mode =~ m/^cap$/ ) {

    # if it is listed here then it is definitely panic
    # suggest increase ent about 20%
    $ent              = $entitled + $entitled / 5;
    $ent_tmp          = sprintf( "%3.2f", $ent );
    $color_it_ent     = " title=\"It is a must to increase CPU entitlement from $entitled to $ent, It is capped LPAR!\" $color_panic";
    $color_it_ent_csv = "red";
  }

  # suggest save entitlemen
  if ( $max_ent < 0.5 && $avrg_ent < 0.5 ) {    # the rule :)
    $ent     = $max_reach + ( $max_reach / 10 );    # $max_reach + 10% as a reserve
    $ent     = int( $ent * 10 + 0.99 ) / 10;        # rounding on first higher decimal number
    $ent_tmp = sprintf( "%3.1f", $ent );

    $color_it_ent     = " title=\"CPU entitlement if unnecessary high, you might reduce it without performance penalty from $entitled to $ent\" $color_noted";
    $color_it_ent_csv = "green";
    print "$name_item RECOME : $name:$server:$host : CPU entitlement if unnecessary high, you might reduce it to: $ent\n";
    print FHL "$ltime_str: $name_item RECOME : $name:$server:$host : CPU entitlement if unnecessary high, you might reduce it to: $ent\n";

    # check if recomended change of ent forces VP change (1 VP requires 0.1 ent)
    if ( $max > ( $ent * 10 ) ) {

      # VP must be decreased as well
      $vp              = $ent * 10;
      $color_it_vp     = " title=\"Number of Virtual (Logical) processors must be reduce $vp when CPU entitlement is reduced\" $color_noted";
      $color_it_vp_csv = "green";
      print "$name_item RECOME : $name:$server:$host : Number of Virtual (Logical) processors must be reduced $vp to $max when CPU entitlement is reduced\n";
      print FHL "$ltime_str: $name_item RECOME : Number of Virtual (Logical) processors must be reduced $vp to $max when CPU entitlement is reduced\n";
    }
  }

  my $ent_web = sprintf( "%+5s", $ent_tmp );
  $ent_web =~ s/ /\&nbsp;/g;
  my $vp_web = sprintf( "%+5s", $vp );
  $vp_web =~ s/ /\&nbsp;/g;

  if ( $name =~ m/^all.*pools$/ ) {

    # default CPU pool == all pools has no sence to advise entitlement as it is done on lpar level
    $ent_web = "-";
  }
  $entitled = sprintf( "%.2f", $entitled );

  my $server_index = "index.html";
  if ( $new_gui == 1 ) {
    $server_index = "gui-cpu.html";
  }

  my $menu = Menu->new( lc 'Power' );
  if ( $lpar_pool =~ m/^LPAR$/ ) {
    my $server_uid = PowerDataWrapper::get_item_uid( { type => 'server', label => $server } );
    my $url_server = $menu->page_url( 'pool', $server_uid );
    my $params     = $url_server;
    ( undef, $params ) = split( '\\?', $params );
    $params = Xorux_lib::parse_url_params($params);
    my $url_server_old = PowerMenu::url_new_to_old($params);
    $url_server_old = PowerMenu::gen_url($url_server_old);

    #warn Dumper $url_server_old;
    if ( $new_gui == 1 ) {
      print FHCSV "LPAR$csv_separ\"$name\"$csv_separ$server$csv_separ$max_reach$csv_separ$max$csv_separ$avrg$csv_separ$entitled$csv_separ$en_vp$csv_separ$max_ent$csv_separ$avrg_ent$csv_separ$color_it_ent_csv$csv_separ$ent$csv_separ$color_it_vp_csv$csv_separ$vp\n";    # print it once
    }
    return "<tr><td nowrap >&nbsp;LPAR&nbsp;</td><td nowrap >&nbsp;<A class=\"backlink\" HREF=\"/lpar2rrd-cgi/detail.sh?host=$host&server=$server_url&lpar=$name_url&item=lpar&entitle=$entitle_less&none=none\" target=\"sample\">$name</A>&nbsp;&nbsp;&nbsp;</td><td nowrap >&nbsp;<A class=\"backlink\" HREF=\"$url_server_old\" target=\"main\">$server</A>&nbsp;&nbsp;&nbsp;</td><td title=\"Maximum CPU peak\" align=\"center\">$max_reach</td><td title=\"Virtual (logical) processors\" align=\"center\" >$max</td><td title=\"Average CPU load\" align=\"center\" >$avrg</td><td title=\"Entitled\" align=\"center\" >$entitled</td><td align=\"center\">$en_vp_web</td><td align=\"center\">$max_ent_web</td><td align=\"center\">$avrg_ent_web</td><td $color_it_ent align=\"center\"><b>$ent_web</b></td><td $color_it_vp align=\"center\"><b>$vp_web</b></td></tr>\n";
  }

  if ( $lpar_pool =~ m/^Shared POOL$/ ) {
    if ( $new_gui == 1 ) {
      print FHCSV "Shared POOL$csv_separ$name$csv_separ$server$csv_separ$max_reach$csv_separ$max$csv_separ$avrg$csv_separ$entitled$csv_separ$en_vp$csv_separ$max_ent$csv_separ$avrg_ent$csv_separ$color_it_ent_csv$csv_separ$ent$csv_separ$color_it_vp_csv$csv_separ$vp\n";    # print it once
    }
    my $name_f = $name_url;
    $name_f =~ s/^ *//g;
    my $server_uid = PowerDataWrapper::get_item_uid( { type => 'server', label => $server } );
    my $pool_uuid  = PowerDataWrapper::get_item_uid( { type => 'shpool', label => $name_f, parent => $server_uid } );

    my $url_pool   = $menu->page_url( 'shpool', $pool_uuid );
    my $url_server = $menu->page_url( 'pool',   $server_uid );

    my $params_pool = $url_pool;
    my $params      = $url_server;

    ( undef, $params_pool ) = split( '\\?', $params_pool );
    ( undef, $params )      = split( '\\?', $params );

    $params_pool = Xorux_lib::parse_url_params($params_pool);
    $params      = Xorux_lib::parse_url_params($params);

    my $url_pool_old   = PowerMenu::url_new_to_old($params_pool);
    my $url_server_old = PowerMenu::url_new_to_old($params);

    $url_pool_old   = PowerMenu::gen_url($url_pool_old);
    $url_server_old = PowerMenu::gen_url($url_server_old);

    #return "<tr><td nowrap >&nbsp;Shared POOL&nbsp;</td><td nowrap >&nbsp;<A HREF=\"$host/$server_url/$name_url/$server_index\" target=\"main\">$name</A>&nbsp;&nbsp;&nbsp;</td><td nowrap >&nbsp;<A HREF=\"$host/$server_url/pool/$server_index\" target=\"main\">$server</A>&nbsp;&nbsp;&nbsp;</td><td title=\"Maximum CPU peak\" align=\"center\">$max_reach</td><td title=\"Virtual (logical) processors\" align=\"center\" >$max</td><td title=\"Average CPU load\" align=\"center\" >$avrg</td><td title=\"Entitled\" align=\"center\" >$entitled</td><td align=\"center\">$en_vp_web</td><td align=\"center\">$max_ent_web</td><td align=\"center\">$avrg_ent_web</td><td $color_it_ent align=\"center\"><b>$ent_web</b></td><td $color_it_vp align=\"center\"><b>$vp_web</b></td></tr>\n";
    return "<tr><td nowrap >&nbsp;Shared POOL&nbsp;</td><td nowrap >&nbsp;<A class=\"backlink\" HREF=\"$url_pool_old\" target=\"main\">$name</A>&nbsp;&nbsp;&nbsp;</td><td nowrap >&nbsp;<A class=\"backlink\" HREF=\"$url_server_old\" target=\"main\">$server</A>&nbsp;&nbsp;&nbsp;</td><td title=\"Maximum CPU peak\" align=\"center\">$max_reach</td><td title=\"Virtual (logical) processors\" align=\"center\" >$max</td><td title=\"Average CPU load\" align=\"center\" >$avrg</td><td title=\"Entitled\" align=\"center\" >$entitled</td><td align=\"center\">$en_vp_web</td><td align=\"center\">$max_ent_web</td><td align=\"center\">$avrg_ent_web</td><td $color_it_ent align=\"center\"><b>$ent_web</b></td><td $color_it_vp align=\"center\"><b>$vp_web</b></td></tr>\n";
  }

  if ( $lpar_pool =~ m/^POOL$/ ) {
    if ( $new_gui == 1 ) {
      print FHCSV "POOL$csv_separ CPU pool$csv_separ$server$csv_separ$max_reach$csv_separ$max$csv_separ$avrg$csv_separ$entitled$csv_separ$en_vp$csv_separ$max_ent$csv_separ$avrg_ent$csv_separ$color_it_ent_csv$csv_separ$ent$csv_separ$color_it_vp_csv$csv_separ$vp\n";    # print it once
    }
    my $menu       = Menu->new( lc 'Power' );
    my $type       = 'server';
    my $uuid       = PowerDataWrapper::get_item_uid( { type => $type, label => $server } );
    my $url_server = $menu->page_url( 'pool', $uuid );
    my $params     = $url_server;
    ( undef, $params ) = split( '\\?', $params );
    $params = Xorux_lib::parse_url_params($params);
    my $url_server_old = PowerMenu::url_new_to_old($params);
    $url_server_old = PowerMenu::gen_url($url_server_old);

    #return "<tr><td nowrap >&nbsp;POOL&nbsp;</td><td nowrap >&nbsp;<A HREF=\"$host/$server_url/$name_url/$server_index\" target=\"main\">$name</A>&nbsp;&nbsp;&nbsp;</td><td nowrap >&nbsp;<A HREF=\"$host/$server_url/pool/$server_index\" target=\"main\">$server</A>&nbsp;&nbsp;&nbsp;</td><td title=\"Maximum CPU peak\" align=\"center\">$max_reach</td><td title=\"Virtual (logical) processors\" align=\"center\" >$max</td><td title=\"Average CPU load\" align=\"center\" >$avrg</td><td title=\"Entitled\" align=\"center\" >$entitled</td><td align=\"center\">$en_vp_web</td><td align=\"center\">$max_ent_web</td><td align=\"center\">$avrg_ent_web</td><td $color_it_ent align=\"center\"><b>$ent_web</b></td><td $color_it_vp align=\"center\"><b>$vp_web</b></td></tr>\n";
    return "<tr><td nowrap >&nbsp;POOL&nbsp;</td><td nowrap >&nbsp;<A class=\"backlink\" HREF=\"$url_server_old\" target=\"main\">$name</A>&nbsp;&nbsp;&nbsp;</td><td nowrap >&nbsp;<A class=\"backlink\" HREF=\"$url_server_old\" target=\"main\">$server</A>&nbsp;&nbsp;&nbsp;</td><td title=\"Maximum CPU peak\" align=\"center\">$max_reach</td><td title=\"Virtual (logical) processors\" align=\"center\" >$max</td><td title=\"Average CPU load\" align=\"center\" >$avrg</td><td title=\"Entitled\" align=\"center\" >$entitled</td><td align=\"center\">$en_vp_web</td><td align=\"center\">$max_ent_web</td><td align=\"center\">$avrg_ent_web</td><td $color_it_ent align=\"center\"><b>$ent_web</b></td><td $color_it_vp align=\"center\"><b>$vp_web</b></td></tr>\n";
  }

  return "";

}

sub print_head {

  print FHD "<HTML><HEAD>
<META HTTP-EQUIV=\"pragma\" CONTENT=\"no-cache\">
<META HTTP-EQUIV=\"Expires\" CONTENT=\"NOW\">
<META HTTP-EQUIV=\"last modified\" CONTENT=\"NOW\">
<STYLE TYPE=\"text/css\">
<!--
.header, .header TD, .header TH
{
background-color:#D3D2F3;
}
-->
</STYLE>
<style>
<!--
a {text-decoration: none}
-->
</style>
<SCRIPT TYPE=\"text/javascript\">
<!--
function popup(mylink, windowname)
{
if (! window.focus)return true;
var href;
if (typeof(mylink) == 'string')
   href=mylink;
else
   href=mylink.href;
window.open(href, windowname, 'width=1329,height=670,scrollbars=yes');
return false;
}
//-->
</SCRIPT>
<link rel=\"stylesheet\" href=\"jquery/jquery-ui-1.10.3.custom.min.css\">
<script src=\"jquery/jquery-1.11.1.min.js\"></script>
<script src=\"jquery/jquery-ui-1.10.4.custom.min.js\"></script>
<script>
\$(function() {
\$( \"#tabs\" ).tabs();
});
</script>

</HEAD>
<BODY BGCOLOR=\"#FFFFFF\" TEXT=\"#000000\" LINK=\"#0000FF\" VLINK=\"#0000FF\" ALINK=\"#FF0000\">\n";

  return 0;

}

sub print_tabs_header {

  return "
   <div id=\"tabs\">
    <ul>
    <li class=\"tabagent\"><a href=\"#fragment-9\"><span>CPU Trends</span></a></li>
    <li class=\"tabhmc\"><a href=\"#fragment-0\"><span>CPU day</span></a></li>
    <li class=\"tabhmc\"><a href=\"#fragment-1\"><span>CPU week</span></a></li>
    <li class=\"tabhmc\"><a href=\"#fragment-2\"><span>CPU month</span></a></li>
    <li class=\"tabagent\"><a href=\"#fragment-3\"><span>Mem day</span></a></li>
    <li class=\"tabagent\"><a href=\"#fragment-4\"><span>Mem week</span></a></li>
    <li class=\"tabagent\"><a href=\"#fragment-5\"><span>Mem month</span></a></li>
    <li class=\"tabagent\"><a href=\"#fragment-6\"><span>IO day</span></a></li>
    <li class=\"tabagent\"><a href=\"#fragment-7\"><span>IO week</span></a></li>
    <li class=\"tabagent\"><a href=\"#fragment-8\"><span>IO month</span></a></li>
    </ul>
    <br>\n";
}

sub lpar_check_detail_cpu {
  my $lpar_name       = shift;
  my $lpar_all        = shift;
  my $lpar            = shift;
  my $server          = shift;
  my $hmc             = shift;
  my $hmc_all         = shift;
  my $act_time_u      = shift;
  my $uniq_name       = shift;
  my $curr_proc       = shift;
  my $curr_proc_units = shift;
  my $time_range      = shift;
  my $sharing_mode    = shift;
  my $found           = 0;
  my @dual            = "";

  if ( $time_range == $DAY ) {    # day
    @dual = @day_dual_hmc_prevent;
  }
  if ( $time_range == $WEEK ) {    #week
    @dual = @wee_dual_hmc_prevent;
  }
  if ( $time_range == $MONTH ) {    # month
    @dual = @mon_dual_hmc_prevent;
  }

  foreach my $name (@dual) {
    if ( $uniq_name =~ m/^$name$/ ) {
      $found = 1;
      last;
    }
  }

  if ( $found == 1 ) {
    return 0;                       # there has been already alert for that server & lpar --> probably dual HMC setup
  }

  my $rrd_time = ( stat("$lpar_all") )[9];
  if ( ( $act_time_u - $rrd_time ) > $time_range ) {
    return 1;
  }

  my $ret = get_lpar_peak( $lpar_all, $curr_proc, $time_range, 0 );    # max CPU
  if ( $ret > 0 ) {
    my $lpar_url = $lpar_name;
    $lpar_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $lpar_url =~ s/\+/ /g;
    my $avrg = get_lpar_peak( $lpar_all, 0, $time_range, 1 );          # avrg
    update_struct( "LPAR", "ERROR", $time_range, $lpar_url, $lpar_name, $server, $hmc, $curr_proc, $uniq_name, $ret, $avrg, $curr_proc_units, $sharing_mode, -1, -1 );
    return 2;
  }

  $ret = get_lpar_peak( $lpar_all, 0, $time_range, 0 );                # entitle check: curr_proc_units
  if ( $ret > 0 ) {
    my $lpar_url = $lpar_name;
    $lpar_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $lpar_url =~ s/\+/ /g;
    my $avrg = get_lpar_peak( $lpar_all, 0, $time_range, 1 );          # avrg
    update_struct( "LPAR", "WARNING", $time_range, $lpar_url, $lpar_name, $server, $hmc, $curr_proc, $uniq_name, $ret, $avrg, $curr_proc_units, $sharing_mode, -1, -1 );
    return 1;
  }

  #
  # LPAR has never reached its entitled (recomendation to decrease unused entitlement
  # check where was the higest peak and average
  #
  # rules: if max_ent < 0.5 && avg_ent < 0.5

  if ( $curr_proc_units == 0.1 ) {
    return 0;    # entitlement cannot be decreased
  }

  my $avrg = get_lpar_peak( $lpar_all, 0, $time_range, 1 );    # returns average load
  $ret = get_lpar_peak( $lpar_all, 0.01, $time_range, 0 );     # returns average load # MAX

  if ( $curr_proc_units == 0 ) {
    return 0;    # entitlement is zero, weird, not running lpar??
  }

  my $max_ent = $ret / $curr_proc_units;
  my $avg_ent = $avrg / $curr_proc_units;

  #print "001 $lpar_all : $ret : $avrg :: $max_ent : $avg_ent\n";
  if ( $max_ent < 0.5 && $avg_ent < 0.5 ) {
    my $lpar_url = $lpar_name;
    $lpar_url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $lpar_url =~ s/\+/ /g;
    my $avrg = get_lpar_peak( $lpar_all, 0, $time_range, 1 );    # avrg
    update_struct( "LPAR", "WARNING", $time_range, $lpar_url, $lpar_name, $server, $hmc, $curr_proc, $uniq_name, $ret, $avrg, $curr_proc_units, $sharing_mode, -1, -1 );
    return 3;
  }

  return 0;
}

sub get_lpar_peak {
  my $rrd        = shift;
  my $logical    = shift;
  my $time_range = shift;
  my $avrg       = shift;
  my $time_end   = "now";

  if ( $time_range == $WEEK ) {    # week (time range last 7 days without last day
    $time_end = "now-$DAY";
    $time_end .= "s";
  }
  if ( $time_range == $MONTH ) {    # month (time range last 31 days without last week
    $time_end = "now-$WEEK";
    $time_end .= "s";
  }

  my $width = 1440 * ( $time_range / $DAY );    # to get 1 minute per a pixel
  $time_range =~ s/$/s/;

  if ( $avrg == 0 ) {
    if ( $logical == 0 ) {
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$tmpdir/name.png"
        "--start" "now-$time_range"
        "--end" "$time_end"
        "--width=$width"
        "--step" "$step_interval"
        "DEF:cur=$rrd:curr_proc_units:AVERAGE"
        "DEF:ent=$rrd:entitled_cycles:AVERAGE"
        "DEF:cap=$rrd:capped_cycles:AVERAGE"
        "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
        "CDEF:tot=cap,uncap,+"
        "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
        "CDEF:utiltot=util,cur,*"
        "CDEF:result=utiltot,cur,LT,UNKN,utiltot,IF"
        "PRINT:result:MAX: %3.3lf"
      );
    }
    else {
      $logical -= 0.01;    # it must be 0.01, it does not work with 0.001 no idea why!!!!
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$tmpdir/name.png"
        "--start" "now-$time_range"
        "--end" "$time_end"
        "--width=$width"
        "--step" "$step_interval"
        "DEF:cur=$rrd:curr_proc_units:AVERAGE"
        "DEF:ent=$rrd:entitled_cycles:AVERAGE"
        "DEF:cap=$rrd:capped_cycles:AVERAGE"
        "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
        "CDEF:tot=cap,uncap,+"
        "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
        "CDEF:utiltot=util,cur,*"
        "CDEF:result=utiltot,$logical,LT,UNKN,utiltot,IF"
        "PRINT:result:MAX: %3.3lf"
      );
    }
  }
  else {
    # prints just avrg for given period
    $rrd =~ s/:/\\:/g;
    RRDp::cmd qq(graph "$tmpdir/name.png"
      "--start" "now-$time_range"
      "--end" "$time_end"
      "--width=$width"
      "DEF:cur=$rrd:curr_proc_units:AVERAGE"
      "DEF:ent=$rrd:entitled_cycles:AVERAGE"
      "DEF:cap=$rrd:capped_cycles:AVERAGE"
      "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
      "CDEF:tot=cap,uncap,+"
      "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
      "CDEF:utiltot=util,cur,*"
      "PRINT:utiltot:AVERAGE: %3.3lf"
    );
  }

  my $answer = RRDp::read;

  #if ( $logical > 0 ) {
  #  print "$$answer\n";
  #  print "$logical \n";
  #}

  #print "001 LPAR $rrd : $logical : $avrg : $$answer";
  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {
    return 0;
  }
  else {
    my $once = 0;
    foreach my $answ ( split( / /, $$answer ) ) {
      if ( $once == 1 ) {
        $answ =~ s/ //g;
        my $ret = substr( $answ, 0, 1 );
        if ( $ret =~ /\D/ ) {
          next;
        }
        else {
          chomp($answ);

          #print "002 LPAR $rrd : $answ\n";
          my $ret = sprintf( "%.2f", $answ );
          return $ret;    # return max value
        }
      }
      $once++;
    }
    error( "Could not parse output from $rrd : $$answer " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

}

sub isdigit {
  my $digit = shift;

  my $digit_work = $digit;

  if ( !defined($digit_work) ) {
    return 0;
  }

  if ( $digit_work eq '' ) {
    return 0;
  }

  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  #if (($digit * 1) eq $digit){
  #  # is a number
  #  return 1;
  #}

  # NOT a number
  #error ("there was expected a digit but a string is there, field: $text , value: $digit");
  return 0;
}

sub once_a_day {
  my $file = shift;

  # at first check whether it is a first run after the midnight
  if ( !-f $file ) {
    `touch $file`;    # first run after the upgrade
    print "CPU cfg advisor: first run after the midnight or after the upgrade, it takes some time ...\n";
  }
  else {
    my $run_time = ( stat("$file") )[9];
    ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
    ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
    if ( $aday == $png_day ) {

      # If it is the same day then do not update static graphs
      # static graps need to be updated due to views and top10
      print "CPU cfg advisor: not this time $aday == $png_day\n";
      return (0);
    }
    else {
      print "CPU cfg advisor: first run after the midnight: $aday != $png_day\n";
      `touch $file`;    # first run after the upgrade
    }
  }
  return 1;
}

sub print_html_file {
  my $file   = shift;
  my $output = "";
  open( my $in, "<", $file ) || error( "Cannot read $file " . __FILE__ . ":" . __LINE__ . "\n" ) && return -1;
  my @lines = <$in>;
  close($in);
  $output .= "<div>\n";
  my $file_html = $file;
  my $print_html;

  if ( -f "$file_html" ) {
    open( FH, "< $file_html" );
    $print_html = do { local $/; <FH> };
    close(FH);
    $output .= "$print_html";
  }
  $output .= "</div>\n";
}

