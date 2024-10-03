use strict;
use warnings;
use Date::Parse;
use Math::BigInt;
use Time::Local;
use POSIX;
use File::Copy;
use File::Compare;
use Data::Dumper;

#use File::Glob ':glob';
use File::Path 'rmtree';
use RRDp;
use File::Glob qw(bsd_glob GLOB_TILDE);
use HostCfg;
use PowerDataWrapper;

# it runs only if not exist tmp/dent-run or it has previous day timestamp
# you can run it from cmdline:
# rm tmp/*ent-run*; . etc/lpar2rrd.cfg; $PERL bin/daily_lpar_check.pl
#
# if demo run this: rm tmp/*ent-run*; . etc/lpar2rrd.cfg; . etc/.magic; $PERL bin/daily_lpar_check.pl
#
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
my $cpu_max_filter = 100;    # max 10k peak in % is allowed (in fact it can be higher than 1k now when 1 logical CPU == 0.1 entitlement)
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}
my $rrdtool = $ENV{RRDTOOL};
my $DEBUG   = $ENV{DEBUG};
my $demo    = 0;
if ( defined $ENV{DEMO} && $ENV{DEMO} ne '' ) {
  $demo = $ENV{DEMO};
}

# $DEBUG = 3;
my $managed_systems_exclude = $ENV{MANAGED_SYSTEMS_EXCLUDE};
my $upgrade                 = 0;
if ( defined $ENV{UPGRADE} ) {
  $upgrade = $ENV{UPGRADE};
}
my $wrkdir        = "$basedir/data";
my $dent_log      = "$basedir/logs/daily_lpar_check.log";    # log output
my $dent_html     = "$webdir/daily_lpar_check.html";         # html ouput of the last run
my $dent_html_gui = "$webdir/gui-daily_lpar_check.html";     # html ouput of the last run
my $dent_run      = "$tmpdir/dent-run";
my $filelpst      = "$tmpdir/daily_lpar_check.txt";
my $filelpstlog   = "$basedir/logs/daily_lpar_check.log";
my $actprogsize   = -s "$basedir/bin/daily_lpar_check.pl";
my $NMON          = "--NMON--";
my $AS400         = "--AS400--";
my $x_days_sec    = ( 90 * 86400 );

# menu.txt for grep
my $menu_txt = "$tmpdir/menu.txt";
my @menu     = ();
if ( -f $menu_txt ) {
  open( MENU, "<$menu_txt" ) || error( "Couldn't open file $menu_txt $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  @menu = <MENU>;
  chomp @menu;
  close(MENU);
}

my @list_of_solaris = grep {/^L:no_hmc:.*:.*:.*:.*:.*:.*:L/} @menu;

my $filter_max_lansan = 1000000000000;    # 100GB/sec, filter values above as this is most probably caused by a counter reset (lpar restart)
if ( defined $ENV{FILTER_MAX_LANSAN} ) { $filter_max_lansan = $ENV{FILTER_MAX_LANSAN} }
my $filter_max_iops = 10000000;           # 1M IOPS filter values above as this is most probably caused by a counter reset (lpar restart)
if ( defined $ENV{FILTER_MAX_IOPS} ) { $filter_max_iops = $ENV{FILTER_MAX_IOPS} }

my $act_time = localtime();

# at first check whether it is a first run after the midnight
if ( !-f $dent_run ) {
  `touch $dent_run`;    # first run after the install
  print "lpar_check     : first run after install 01\n";
}
else {
  my $run_time = ( stat("$dent_run") )[9];
  ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
  ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
  if ( $aday == $png_day ) {

    # If it is the same day then do not update except upgrade
    if ( $upgrade == 0 ) {
      print "lpar_check     : not this time $aday == $png_day\n";
      exit(0);    # run just once a day per timestamp on $webdir/daily_lpar_check.html
                  # and  $tmpdir/daily_lpar_check.txt
    }
    else {
      print "lpar_check     : run it as first run after the upgrade : $upgrade\n";
    }
  }
  else {
    print "lpar_check     : first run after the midnight 02: $aday != $png_day\n";
    `touch $dent_run`;
  }
}

###  erasing old VMs
my $vm_days_to_erase = 30;
if ( defined $ENV{VMWARE_VM_ERASE_DAYS} && $ENV{VMWARE_VM_ERASE_DAYS} > 1 ) {
  $vm_days_to_erase = $ENV{VMWARE_VM_ERASE_DAYS};
}
vmware_vm_erase();

# exit; # when debugging
###

###  erasing old datastores
#my $vm_days_to_erase = 90;
#if ( defined $ENV{VMWARE_VM_ERASE_DAYS} && $ENV{VMWARE_VM_ERASE_DAYS} > 1 ) {
#      $vm_days_to_erase = $ENV{VMWARE_VM_ERASE_DAYS};
#}
vmware_datastore_erase();

# exit; # when debugging
###

hlink_check();

open( VYFILE, ">$filelpst" ) || error( "Cannot open: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
print VYFILE "InFo_Lpar Activity Table " . localtime() . "\n";

read_lpars();

print VYFILE "InFo_Lpar Activity Table Prog Size $actprogsize " . localtime() . "\n";
close(VYFILE);

copy( "$filelpst", "$filelpstlog" ) || error( "Cannot copy $filelpstlog: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;

# for testing purposes
# `cp /home/lpar2rrd/tested-daily_lpar_check.txt /home/lpar2rrd/lpar2rrd/tmp/daily_lpar_check.txt`;

# create web page

open( FHG, "> $dent_html_gui" ) || error( "Cannot open $dent_html_gui: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
open( FHW, "> $dent_html" )     || error( "Cannot open $dent_html: $!" . __FILE__ . ":" . __LINE__ )     && exit 0;
print_head_lpar_check();

open( FH, "< $filelpst" ) || error( "Cannot read $filelpst: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
my @lines     = <FH>;
my @lines_top = @lines;    # for later use for top10
close(FH);

my $count = 0;
while ( my $line = shift @lines ) {

  # looking for lpar data
  if ( $line =~ m/InFo_cfg/ ) {
    my @lpar_info = split( ',', $line );
    print FHW "<tr><td>$lpar_info[1]</td><td>$lpar_info[2]</td><td>server</td><td>$lpar_info[4]</td><td>HMC - all</td></tr>\n";
    print FHG "<tr><td>$lpar_info[1]</td><td>$lpar_info[2]</td><td>server</td><td>$lpar_info[4]</td><td>HMC - all</td></tr>\n";
    $count = $count + 1;
  }

  if ( !( $line =~ m/InFo/ ) ) {
    my @lpar_info = split( ',', $line );
    if ( $lpar_info[3] !~ "OK" ) {
      my $type = "CPU - HMC";
      if ( $line =~ m/poool/ )       { $type = "Pool - HMC"; }
      if ( $line =~ m/AllCPUPools/ ) { $type = "CPU Pool - HMC"; }
      if ( $line =~ m/\.mmm/ )       { $type = "OS MEM"; }
      if ( $line =~ m/agent/ )       { $type = "OS agent"; }
      if ( $line =~ m/$NMON/ )       { $type = "NMON"; }
      $lpar_info[2] =~ s/\.rrm$//;
      $lpar_info[2] =~ s/\.rrh$//;
      $lpar_info[2] =~ s/\.mmm$//;
      $lpar_info[2] =~ s/$NMON$//;
      $lpar_info[2] =~ s/AllCPUPools/All CPU Pools/;

      # if there is a "/" in lpar name, make subst only for print
      $lpar_info[2] =~ s/&&1/\//g;
      $lpar_info[1] =~ s/no_hmc/NA/g;
      $lpar_info[0] =~ s/--unknown//g;
      if ( $lpar_info[0] =~ /Solaris/ && $type !~ /OS agent/ ) {
        next;
      }
      print FHW "<tr><td>$lpar_info[0]</td><td>$lpar_info[1]</td><td>$lpar_info[2]</td><td>$lpar_info[4]</td><td>$type</td></tr>\n";
      print FHG "<tr><td>$lpar_info[0]</td><td>$lpar_info[1]</td><td>$lpar_info[2]</td><td>$lpar_info[4]</td><td>$type</td></tr>\n";
      $count = $count + 1;
    }
  }
}
print FHW "</table></center></td></tr>";
print FHG "</table></center><br><br><br><br><br>";

if ( $count == 0 ) {
  print FHW "<tr><td>Congrats,all LPARs and CPU pools are regularly updated.</td></tr><br>\n";
  print FHG "Congrats,all LPARs and CPU pools are regularly updated.<br>\n";
}

# looking for other comments
#  open FH,"< $filelpst" or die "Cannot read the file $filelpst: $!\n";
#  @lines = <FH>;
#  close (FH);
#
#  while (my $line = shift @lines) {
#    if ($line =~ m/InFo/)  {
#       print FHW "$line<br>\n";
#    }
#  }
print FHW "<tr><td>Report has been created at: $act_time<br>\n";
print FHW "Table above shows lpars and servers not updated within last 24 hours.<br>\n";
print FHW "Lpars and servers not updated more than 30 days are ignored.<br>\n";
print FHW "</tr></td></tbody></table></body></html>\n";
close(FHW);

print FHG "Report has been created at: $act_time<br>\n";
print FHG "Table above shows lpars and servers not updated within last 24 hours.<br>\n";
print FHG "Lpars and servers not updated more than 30 days are ignored.<br>\n";
close(FHG);

#
### prepare top10 utilisation
#

#   start RRD via a pipe

if ( !-f "$rrdtool" ) {
  error( "Set correct path to rrdtool binary, it does not exist here: $rrdtool " . __FILE__ . ":" . __LINE__ );
  exit;
}
RRDp::start "$rrdtool";

print "topten file    : starting for POWER at " . localtime( time() ) . "\n";

my @lines_top_out1;
my @lines_top_out2;
my @lines_top_out4;

# print "179 daily_lpar_check.pl prepare top10 utilisation \@lines_top @lines_top\n";
my $name_out = "shade";
foreach my $line (@lines_top) {
  next if $line =~ /^InFo_/;
  next if $line =~ /poool/;
  ( my $server_t, my $hmc_t, my $lpar_t, my $status ) = split( ",", $line );
  next if $status ne "OK";
  if ( $lpar_t !~ /\.rrm$/ ) {next}
  my $rrd = "$wrkdir/$server_t/$hmc_t/$lpar_t";

  # print "test if exists file $rrd";
  if ( -f "$rrd" ) {

    # print "  OK\n"
  }
  else {
    error( "file $rrd  does not exist " . __FILE__ . ":" . __LINE__ );

    #print "file $rrd  does not exist\n";
    next;
  }
  my $save_line1 = "load_cpu,$server_t,$lpar_t,$hmc_t";

  #my $save_line2 = "load_peak,$server_t,$lpar_t,$hmc_t";
  $rrd =~ s/:/\\:/g;
  foreach my $type ( "d", "w", "m", "y" ) {
    my $start_time = "now-1$type";
    my $end_time   = "now-1$type+1$type";
    RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:cur=$rrd:curr_proc_units:AVERAGE"
        "DEF:ent=$rrd:entitled_cycles:AVERAGE"
        "DEF:cap=$rrd:capped_cycles:AVERAGE"
        "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
        "CDEF:tot=cap,uncap,+"
        "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
        "CDEF:utilperct=util,100,*"
        "CDEF:utiltot=util,cur,*"
        "PRINT:utiltot:AVERAGE: %3.2lf"
        "PRINT:utiltot:MAX: %3.2lf"
      );
    my $answer = RRDp::read;
    if ( $$answer =~ "ERROR" ) {
      error("Rrdtool error : $$answer");
      next;
    }
    my $aaa = $$answer;

    #print "$answer\n";
    #print "$i, $$answer\n";
    ( undef, my $utiltot, my $utiltot_max ) = split( "\n", $aaa );
    $utiltot =~ s/NaNQ/0/g;
    $utiltot =~ s/NaN/0/g;
    $utiltot =~ s/nan/0/g;        # rrdtool v 1.2.27
    $utiltot =~ s/,/\./;
    $utiltot *= 1;
    $utiltot_max =~ s/NaNQ/0/g;
    $utiltot_max =~ s/NaN/0/g;
    $utiltot_max =~ s/nan/0/g;    # rrdtool v 1.2.27
    $utiltot_max =~ s/,/\./;
    $utiltot_max *= 1;
    my $util2places     = sprintf '%.1f', $utiltot;
    my $util2places_max = sprintf '%.1f', $utiltot_max;

    # print "$type, $utiltot,"
    $save_line1 .= ",$util2places,$util2places_max";

    #$save_line2 .= ",$util2places_max";

    #print STDERR "???$save_line???\n";
  }

  #print "$save_line\n";
  push @lines_top_out1, "$save_line1\n";

  #push @lines_top_out1, "$save_line2\n";
}

foreach my $line_cpu_per (@lines_top) {
  next if $line_cpu_per =~ /^InFo_/;
  next if $line_cpu_per =~ /poool/;
  ( my $server_t, my $hmc_t, my $lpar_t, my $status ) = split( ",", $line_cpu_per );
  next if $status ne "OK";
  if ( $lpar_t !~ /\.rrm$/ ) {next}
  my $lpar_rvm = "$lpar_t";
  $lpar_rvm =~ s/\.rrm$//g;
  my $rrd     = "$wrkdir/$server_t/$hmc_t/$lpar_t";
  my $rrd_rvm = "$wrkdir/$server_t/$hmc_t/$lpar_rvm.rvm";

  # print "test if exists file $rrd";
  if ( -f "$rrd" ) {

    # print "  OK\n"
  }
  else {
    error( "file $rrd  does not exist " . __FILE__ . ":" . __LINE__ );

    #print "file $rrd  does not exist\n";
    next;
  }
  if ( -f "$rrd_rvm" ) {

    # print "  OK\n"
  }
  else {
    error( "file $rrd_rvm  does not exist " . __FILE__ . ":" . __LINE__ );
    next;
  }
  my $save_line2 = "util_cpu_perc,$server_t,$lpar_t,$hmc_t";
  $rrd     =~ s/:/\\:/g;
  $rrd_rvm =~ s/:/\\:/g;
  foreach my $type ( "d", "w", "m", "y" ) {
    my $start_time = "now-1$type";
    my $end_time   = "now-1$type+1$type";

    #"CDEF:vcpu_final=vcpu,UN,cur,vcpu,IF" when vcpu does not exist, replace it with entitled(cur)
    RRDp::cmd qq(graph "$name_out"
        "--start" "$start_time"
        "--end" "$end_time"
        "DEF:cur=$rrd:curr_proc_units:AVERAGE"
        "DEF:ent=$rrd:entitled_cycles:AVERAGE"
        "DEF:cap=$rrd:capped_cycles:AVERAGE"
        "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
        "DEF:vcpu=$rrd_rvm:allocated_cores:AVERAGE"
        "CDEF:vcpu_final=vcpu,UN,cur,vcpu,IF"
        "CDEF:tot=cap,uncap,+"
        "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
        "CDEF:utilperct=util,100,*"
        "CDEF:utiltot=util,cur,*"
        "CDEF:utilp1=utiltot,vcpu_final,/"
        "CDEF:utilp2=utilp1,100,*"
        "PRINT:utilp2:AVERAGE: %3.0lf"
        "PRINT:utilp2:MAX: %3.0lf"
        "PRINT:vcpu:AVERAGE: %3.0lf"
        "PRINT:vcpu_final:AVERAGE: %3.0lf"
        "PRINT:cur:AVERAGE: %5.2lf"
      );
    my $answer = RRDp::read;
    if ( $$answer =~ "ERROR" ) {
      error("Rrdtool error : $$answer");
      next;
    }
    my $aaa = $$answer;

    #print "$answer\n";
    #print "$i, $$answer\n";
    ( undef, my $utiltot, my $utiltot_max, my $vcpu, my $vcpu_final, my $ent ) = split( "\n", $aaa );
    $utiltot =~ s/NaNQ/0/g;
    $utiltot =~ s/NaN/0/g;
    $utiltot =~ s/nan/0/g;        # rrdtool v 1.2.27
    $utiltot =~ s/,/\./;
    $utiltot *= 1;
    $utiltot_max =~ s/NaNQ/0/g;
    $utiltot_max =~ s/NaN/0/g;
    $utiltot_max =~ s/nan/0/g;    # rrdtool v 1.2.27
    $utiltot_max =~ s/,/\./;
    $utiltot_max *= 1;
    my $util2places         = sprintf '%.0f', $utiltot;
    my $utiltot_max_2places = sprintf '%.0f', $utiltot_max;

    # print "$type, $utiltot,"
    $save_line2 .= ",$util2places,$utiltot_max";

    #print STDERR "???$save_line???\n";
  }

  #print "$save_line2\n";
  push @lines_top_out1, "$save_line2\n";
}

#my @lines_one_hmc;
#foreach my $line_dual_hmc (@lines_top) {
#  if ( $line_dual_hmc =~ /agent_OK/ ) {
#    ( my $server_t, my $hmc_t, my $lpar_t, my $status ) = split( ",", $line_dual_hmc );
#    if ( $lpar_t =~ /--NMON--$/ ) { next; }
#    my $rrd_file = "$wrkdir/$server_t/$hmc_t/$lpar_t";
#
#    #print "$rrd_file\n";
#    #my $timestamp = ( stat("$rrd_file") )[9];
#    #$hash_timestamp1{$server_t}{$lpar_t}{$hmc_t}=$timestamp;
#  } ## end if ( $line_dual_hmc =~...)
#} ## end foreach my $line_dual_hmc (...)

my @lines_dual_hmc   = sort @lines_top;
my $mtimestamp_file  = 0;
my $mtimestamp_file1 = 0;
foreach my $line1 (@lines_dual_hmc) {
  if ( $line1 =~ /agent_OK/ ) {
    ( my $server_t, my $hmc_t, my $lpar_t, my $status ) = split( ",", $line1 );

    #print "$server_t,,$hmc_t,,$lpar_t,, $status\n";
    opendir( DIR, "$wrkdir/$server_t/$hmc_t/$lpar_t" ) || error( "can't opendir $wrkdir/$server_t/$hmc_t/$lpar_t: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @server_agent = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    foreach my $line2 (@server_agent) {
      $line2 = "$wrkdir/$server_t/$hmc_t/$lpar_t/$line2";
      my $type_file = basename($line2);

      # print "294 \$line2 $line2 \$type_file $type_file\n";
      if ( $type_file =~ /san\-.*\.mmm$/ ) {    ################# SAN IOPS alias SAN2
        my $san = "";
        if ( $lpar_t =~ /--NMON--$/ ) {
          my $lpar_test_nmon = $lpar_t;
          $lpar_test_nmon =~ s/--NMON--$//g;
          my $file_test = "$wrkdir/$server_t/$hmc_t/$lpar_test_nmon";
          if ( -d $file_test ) {
            next;
          }
        }

        #if ( !-f "$wrkdir/$server_t/$hmc_t/$lpar_t/cpu.txt" ) { next; }
        my $line_tmp = "os_san,$server_t,$lpar_t,$hmc_t";
        my $filter   = $filter_max_iops;
        foreach my $type ( "d", "w", "m", "y" ) {
          my $start_time  = "now-1$type";
          my $end_time    = "now-1$type+1$type";
          my $ds_name_os1 = "iops_in";
          my $ds_name_os2 = "iops_out";
          my $divider     = 1;
          my $rrd         = $line2;
          $rrd =~ s/:/\\:/g;
          $mtimestamp_file = ( stat("$rrd") )[9];

          if ( $type =~ m/y/ ) {

            # lower limits for yearly graphs as they are averaged ....
            $filter = $filter / 10;
          }
          if ( $type =~ m/m/ ) {

            # lower limits for monthly graphs as they are averaged ....
            $filter = $filter / 2;
          }

          #print "$start_time --- $end_time\n";
          $san = basename($rrd);

          #$line_tmp .= ",$san";
          RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "DEF:value_os1=$rrd:$ds_name_os1:AVERAGE"
            "DEF:value_os2=$rrd:$ds_name_os2:AVERAGE"
            "CDEF:value_os1_a=value_os1,$filter,GT,0,value_os1,IF"
            "CDEF:value_os1_b=value_os1_a,UN,0,value_os1_a,IF"
            "CDEF:value_os2_a=value_os2,$filter,GT,0,value_os2,IF"
            "CDEF:value_os2_b=value_os2_a,UN,0,value_os2_a,IF"
            "CDEF:value_os1_res=value_os1_b,1,*,0.5,+,FLOOR,1,/"
            "CDEF:value_os2_res=value_os2_b,1,*,0.5,+,FLOOR,1,/"
            "CDEF:value_os3_res=value_os1_res,value_os2_res,+"
            "PRINT:value_os3_res:AVERAGE: %3.0lf"
            "PRINT:value_os3_res:MAX: %3.0lf"
            );
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
            next;
          }
          my $aaa = $$answer;
          my ( undef, $iops_avrg, $iops_max ) = split( "\n", $aaa );
          $iops_avrg =~ s/NaNQ/0/g;
          $iops_avrg =~ s/NaN/0/g;
          $iops_avrg =~ s/nan/0/g;    # rrdtool v 1.2.27
          $iops_max  =~ s/NaNQ/0/g;
          $iops_max  =~ s/NaN/0/g;
          $iops_max  =~ s/nan/0/g;    # rrdtool v 1.2.27
          chomp( $iops_avrg, $iops_max );
          $line_tmp .= ",$iops_avrg,$iops_max";
        }

        #print "??$line_tmp,$san,$mtimestamp_file??\n";
        $mtimestamp_file = "" if not defined $mtimestamp_file;
        push @lines_top_out2, "$line_tmp,$san,$mtimestamp_file";
      }
      if ( $type_file =~ /lan\-.*\.mmm$/ ) {    #################### LAN
        my $lan = "";
        if ( $lpar_t =~ /--NMON--$/ ) {
          my $lpar_test_nmon = $lpar_t;
          $lpar_test_nmon =~ s/--NMON--$//g;
          my $file_test = "$wrkdir/$server_t/$hmc_t/$lpar_test_nmon";
          if ( -d $file_test ) {
            next;
          }
        }
        if ( $server_t =~ /Linux--/ ) { next; }
        my $line_tmp = "os_lan,$server_t,$lpar_t,$hmc_t";
        my $filter   = $filter_max_iops;
        foreach my $type ( "d", "w", "m", "y" ) {
          my $start_time = "now-1$type";
          my $end_time   = "now-1$type+1$type";

          #my $divider = 1;
          my $divider = 1000000;
          my $rrd     = $line2;
          $rrd =~ s/:/\\:/g;
          $mtimestamp_file = ( stat("$rrd") )[9];

          #print "$start_time --- $end_time\n";
          if ( $type =~ m/y/ ) {
            $filter = $filter / 10;
          }
          if ( $type =~ m/m/ ) {
            $filter = $filter / 2;
          }
          my $count_avg_day = 1;
          my $minus_one     = -1;
          $lan = basename($rrd);

          #$line_tmp .= ",$san";
          #print "$rrd\n";
          RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "DEF:transfers_bytes=$rrd:trans_bytes:AVERAGE"
            "DEF:received_bytes=$rrd:recv_bytes:AVERAGE"
            "CDEF:recv=received_bytes"
            "CDEF:trans=transfers_bytes"
            "CDEF:recv_smb=recv,$divider,/"
            "CDEF:trans_smb=trans,$divider,/"
            "CDEF:result_san=recv_smb,trans_smb,+"
            "PRINT:result_san:AVERAGE: %6.2lf"
            "PRINT:result_san:MAX: %6.2lf"
            );
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
            next;
          }
          my $aaa = $$answer;
          my ( undef, $san_avrg, $san_max ) = split( "\n", $aaa );
          $san_avrg =~ s/NaNQ/0/g;
          $san_avrg =~ s/NaN/0/g;
          $san_avrg =~ s/nan/0/g;    # rrdtool v 1.2.27
          $san_max  =~ s/NaNQ/0/g;
          $san_max  =~ s/NaN/0/g;
          $san_max  =~ s/nan/0/g;    # rrdtool v 1.2.27
          chomp( $san_avrg, $san_max );
          $line_tmp .= ",$san_avrg,$san_max";
        }
        $mtimestamp_file = "" if not defined $mtimestamp_file;
        push @lines_top_out4, "$line_tmp,$lan,$mtimestamp_file";
      }
    }
  }
}

#print Dumper \@lines_top_out4;
my @lines_top_out6;
foreach my $line3 (@lines_dual_hmc) {    #################### SAN1
  if ( $line3 =~ /agent_OK/ ) {
    ( my $server_t, my $hmc_t, my $lpar_t, my $status ) = split( ",", $line3 );
    opendir( DIR, "$wrkdir/$server_t/$hmc_t/$lpar_t" ) || error( "can't opendir $wrkdir/$server_t/$hmc_t/$lpar_t: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @server_agent = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);

    #print "$server_t,,$hmc_t,,$lpar_t,, $status\n";
    foreach my $line4 (@server_agent) {
      next if $line4 =~ /^wlm\-/;
      $line4 = "$wrkdir/$server_t/$hmc_t/$lpar_t/$line4";
      my $type_file = basename($line4);
      if ( $type_file =~ /san/ ) {

        #print "$line2\n";
        my $san = "";
        if ( $lpar_t =~ /--NMON--$/ ) {
          my $lpar_test_nmon = $lpar_t;
          $lpar_test_nmon =~ s/--NMON--$//g;
          my $file_test = "$wrkdir/$server_t/$hmc_t/$lpar_test_nmon";
          if ( -d $file_test ) {
            next;
          }
        }
        my $line_tmp = "os_san,$server_t,$lpar_t,$hmc_t";
        my $filter   = $filter_max_iops;
        foreach my $type ( "d", "w", "m", "y" ) {
          my $start_time  = "now-1$type";
          my $end_time    = "now-1$type+1$type";
          my $ds_name_os1 = "recv_bytes";
          my $ds_name_os2 = "trans_bytes";
          my $divider     = 1000000;
          my $max_rows    = 65000;
          my $step        = 60;
          if ( $line4 =~ /\.cfg|san_resp|ame|cpu|san_error/ ) { next; }
          my $rrd = $line4;
          $rrd =~ s/:/\\:/g;
          $mtimestamp_file = ( stat("$rrd") )[9];

          if ( $type =~ m/y/ ) {

            # lower limits for yearly graphs as they are averaged ....
            $filter = $filter / 10;
          }
          if ( $type =~ m/m/ ) {

            # lower limits for monthly graphs as they are averaged ....
            $filter = $filter / 2;
          }

          #print "$start_time --- $end_time\n";
          $san = basename($rrd);

          #$line_tmp .= ",$san";
          RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "--step=$step"
            "DEF:value_os1=$rrd:$ds_name_os1:AVERAGE"
            "DEF:value_os2=$rrd:$ds_name_os2:AVERAGE"
            "CDEF:value_os1_res=value_os1,$divider,/"
            "CDEF:value_os2_res=value_os2,$divider,/"
            "CDEF:value_os3_res=value_os1_res,value_os2_res,+"
            "PRINT:value_os3_res:AVERAGE: %6.1lf"
            "PRINT:value_os3_res:MAX: %6.1lf"
            );
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
            next;
          }
          my $aaa = $$answer;
          my ( undef, $iops_avrg, $iops_max ) = split( "\n", $aaa );
          $iops_avrg =~ s/NaNQ/0/g;
          $iops_avrg =~ s/NaN/0/g;
          $iops_avrg =~ s/nan/0/g;    # rrdtool v 1.2.27
          $iops_max  =~ s/NaNQ/0/g;
          $iops_max  =~ s/NaN/0/g;
          $iops_max  =~ s/nan/0/g;    # rrdtool v 1.2.27
          chomp( $iops_avrg, $iops_max );
          $line_tmp .= ",$iops_avrg,$iops_max";
        }

        #print "??$line_tmp,$san,$mtimestamp_file??\n";
        $mtimestamp_file = "" if not defined $mtimestamp_file;
        push @lines_top_out6, "$line_tmp,$san,$mtimestamp_file";
      }
    }
  }
}

my %server_hash2;
foreach my $line_sort (@lines_top_out6) {    ########## HASH for SAN1
  my ( undef, $server, $lpar, $hmc, $day_v, $day_v_max, $week_v, $week_v_max, $month_v, $month_v_max, $year_v, $year_v_max, $san, $mtime ) = split( ",", $line_sort );

  #print "$server, $lpar, $hmc, $day_v, $day_v_max, $week_v, $week_v_max, $month_v, $month_v_max, $year_v, $year_v_max, $san, $mtime\n";
  #chomp ($day_v,$week_v,$month_v,$year_v);
  if ( defined $day_v && $week_v && $month_v && $year_v ) {
    if ( $san =~ m/\.bphl$/ ) {
      $san =~ s/\.bphl//g;
    }

    #print "$line_sort\n";
    if ( defined $server_hash2{$server}{$lpar}{day}{$san} && $server_hash2{$server}{$lpar}{day}{$san} ne '' ) {
      if ( defined $server_hash2{$server}{$lpar}{day}{$san}{update} && $server_hash2{$server}{$lpar}{day}{$san}{update} ne "" ) {
        if ( $mtime > $server_hash2{$server}{$lpar}{day}{$san}{update} ) {
          $server_hash2{$server}{$lpar}{day}{$san}{value_avrg} = $day_v;
          $server_hash2{$server}{$lpar}{day}{$san}{value_max}  = $day_v_max;
          $server_hash2{$server}{$lpar}{day}{$san}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash2{$server}{$lpar}{day}{$san}{value_avrg} = $day_v;
      $server_hash2{$server}{$lpar}{day}{$san}{value_max}  = $day_v_max;
      $server_hash2{$server}{$lpar}{day}{$san}{update}     = $mtime;
    }
    if ( defined $server_hash2{$server}{$lpar}{week}{$san} && $server_hash2{$server}{$lpar}{week}{$san} ne '' ) {
      if ( defined $server_hash2{$server}{$lpar}{week}{$san}{update} && $server_hash2{$server}{$lpar}{week}{$san}{update} ne "" ) {
        if ( $mtime > $server_hash2{$server}{$lpar}{week}{$san}{update} ) {
          $server_hash2{$server}{$lpar}{week}{$san}{value_avrg} = $day_v;
          $server_hash2{$server}{$lpar}{week}{$san}{value_avrg} = $day_v_max;
          $server_hash2{$server}{$lpar}{week}{$san}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash2{$server}{$lpar}{week}{$san}{value_avrg} = $week_v;
      $server_hash2{$server}{$lpar}{week}{$san}{value_max}  = $week_v_max;
      $server_hash2{$server}{$lpar}{week}{$san}{update}     = $mtime;
    }
    if ( defined $server_hash2{$server}{$lpar}{month}{$san} && $server_hash2{$server}{$lpar}{month}{$san} ne '' ) {
      if ( defined $server_hash2{$server}{$lpar}{month}{$san}{update} && $server_hash2{$server}{$lpar}{month}{$san}{update} ne "" ) {
        if ( $mtime > $server_hash2{$server}{$lpar}{month}{$san}{update} ) {
          $server_hash2{$server}{$lpar}{month}{$san}{value_avrg} = $day_v;
          $server_hash2{$server}{$lpar}{month}{$san}{value_max}  = $day_v_max;
          $server_hash2{$server}{$lpar}{month}{$san}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash2{$server}{$lpar}{month}{$san}{value_avrg} = $month_v;
      $server_hash2{$server}{$lpar}{month}{$san}{value_max}  = $month_v_max;
      $server_hash2{$server}{$lpar}{month}{$san}{update}     = $mtime;
    }
    if ( defined $server_hash2{$server}{$lpar}{year}{$san} && $server_hash2{$server}{$lpar}{year}{$san} ne '' ) {
      if ( defined $server_hash2{$server}{$lpar}{year}{$san}{update} && $server_hash2{$server}{$lpar}{year}{$san}{update} ne "" ) {
        if ( $mtime > $server_hash2{$server}{$lpar}{year}{$san}{update} ) {
          $server_hash2{$server}{$lpar}{year}{$san}{value_avrg} = $day_v;
          $server_hash2{$server}{$lpar}{year}{$san}{value_max}  = $day_v_max;
          $server_hash2{$server}{$lpar}{year}{$san}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash2{$server}{$lpar}{year}{$san}{value_avrg} = $year_v;
      $server_hash2{$server}{$lpar}{year}{$san}{value_max}  = $year_v_max;
      $server_hash2{$server}{$lpar}{year}{$san}{update}     = $mtime;
    }
  }
}

#print Dumper \%server_hash2;

my @lines_top_out;
my %server_hash;
my $last_found1 = "";
my $day_value;
foreach my $line_sort (@lines_top_out2) {    ########## SAN IOPS last update
  my ( undef, $server, $lpar, $hmc, $day_v, $day_v_max, $week_v, $week_v_max, $month_v, $month_v_max, $year_v, $year_v_max, $san, $mtime ) = split( ",", $line_sort );

  #chomp ($day_v,$week_v,$month_v,$year_v);
  if ( defined $day_v && $week_v && $month_v && $year_v ) {
    if ( $san =~ m/\.bphl$/ ) {
      $san =~ s/\.bphl//g;
    }

    #print "$line_sort\n";
    if ( defined $server_hash{$server}{$lpar}{day}{$san} && $server_hash{$server}{$lpar}{day}{$san} ne '' ) {
      if ( defined $server_hash{$server}{$lpar}{day}{$san}{update} && $server_hash{$server}{$lpar}{day}{$san}{update} ne "" ) {
        if ( $mtime > $server_hash{$server}{$lpar}{day}{$san}{update} ) {
          $server_hash{$server}{$lpar}{day}{$san}{value_avrg} = $day_v;
          $server_hash{$server}{$lpar}{day}{$san}{value_max}  = $day_v_max;
          $server_hash{$server}{$lpar}{day}{$san}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash{$server}{$lpar}{day}{$san}{value_avrg} = $day_v;
      $server_hash{$server}{$lpar}{day}{$san}{value_max}  = $day_v_max;
      $server_hash{$server}{$lpar}{day}{$san}{update}     = $mtime;
    }
    if ( defined $server_hash{$server}{$lpar}{week}{$san} && $server_hash{$server}{$lpar}{week}{$san} ne '' ) {
      if ( defined $server_hash{$server}{$lpar}{week}{$san}{update} && $server_hash{$server}{$lpar}{week}{$san}{update} ne "" ) {
        if ( $mtime > $server_hash{$server}{$lpar}{week}{$san}{update} ) {
          $server_hash{$server}{$lpar}{week}{$san}{value_avrg} = $day_v;
          $server_hash{$server}{$lpar}{week}{$san}{value_max}  = $day_v_max;
          $server_hash{$server}{$lpar}{week}{$san}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash{$server}{$lpar}{week}{$san}{value_avrg} = $week_v;
      $server_hash{$server}{$lpar}{week}{$san}{value_max}  = $week_v_max;
      $server_hash{$server}{$lpar}{week}{$san}{update}     = $mtime;
    }
    if ( defined $server_hash{$server}{$lpar}{month}{$san} && $server_hash{$server}{$lpar}{month}{$san} ne '' ) {
      if ( defined $server_hash{$server}{$lpar}{month}{$san}{update} && $server_hash{$server}{$lpar}{month}{$san}{update} ne "" ) {
        if ( $mtime > $server_hash{$server}{$lpar}{month}{$san}{update} ) {
          $server_hash{$server}{$lpar}{month}{$san}{value_avrg} = $day_v;
          $server_hash{$server}{$lpar}{month}{$san}{value_max}  = $day_v_max;
          $server_hash{$server}{$lpar}{month}{$san}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash{$server}{$lpar}{month}{$san}{value_avrg} = $month_v;
      $server_hash{$server}{$lpar}{month}{$san}{value_max}  = $month_v_max;
      $server_hash{$server}{$lpar}{month}{$san}{update}     = $mtime;
    }
    if ( defined $server_hash{$server}{$lpar}{year}{$san} && $server_hash{$server}{$lpar}{year}{$san} ne '' ) {
      if ( defined $server_hash{$server}{$lpar}{year}{$san}{update} && $server_hash{$server}{$lpar}{year}{$san}{update} ne "" ) {
        if ( $mtime > $server_hash{$server}{$lpar}{year}{$san}{update} ) {
          $server_hash{$server}{$lpar}{year}{$san}{value_avrg} = $day_v;
          $server_hash{$server}{$lpar}{year}{$san}{value_max}  = $day_v_max;
          $server_hash{$server}{$lpar}{year}{$san}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash{$server}{$lpar}{year}{$san}{value_avrg} = $year_v;
      $server_hash{$server}{$lpar}{year}{$san}{value_max}  = $year_v_max;
      $server_hash{$server}{$lpar}{year}{$san}{update}     = $mtime;
    }
  }
}

my %server_hash1;
my $last_found2 = "";
my $day_value1;
foreach my $line_sort (@lines_top_out4) {    ################### LAN last update
  my ( undef, $server, $lpar, $hmc, $day_v, $day_v_max, $week_v, $week_v_max, $month_v, $month_v_max, $year_v, $year_v_max, $lan, $mtime ) = split( ",", $line_sort );

  #chomp ($day_v,$week_v,$month_v,$year_v);
  if ( defined $day_v && $week_v && $month_v && $year_v ) {
    if ( $lan =~ m/\.bphl$/ ) {
      $lan =~ s/\.bphl//g;
    }

    #print "$line_sort\n";
    if ( defined $server_hash1{$server}{$lpar}{day}{$lan} && $server_hash1{$server}{$lpar}{day}{$lan} ne '' ) {
      if ( defined $server_hash1{$server}{$lpar}{day}{$lan}{update} && $server_hash1{$server}{$lpar}{day}{$lan}{update} ne "" ) {
        if ( $mtime > $server_hash1{$server}{$lpar}{day}{$lan}{update} ) {
          $server_hash1{$server}{$lpar}{day}{$lan}{value_avrg} = $day_v;
          $server_hash1{$server}{$lpar}{day}{$lan}{value_max}  = $day_v_max;
          $server_hash1{$server}{$lpar}{day}{$lan}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash1{$server}{$lpar}{day}{$lan}{value_avrg} = $day_v;
      $server_hash1{$server}{$lpar}{day}{$lan}{value_max}  = $day_v_max;
      $server_hash1{$server}{$lpar}{day}{$lan}{update}     = $mtime;
    }
    if ( defined $server_hash1{$server}{$lpar}{week}{$lan} && $server_hash1{$server}{$lpar}{week}{$lan} ne '' ) {
      if ( defined $server_hash1{$server}{$lpar}{week}{$lan}{update} && $server_hash1{$server}{$lpar}{week}{$lan}{update} ne "" ) {
        if ( $mtime > $server_hash1{$server}{$lpar}{week}{$lan}{update} ) {
          $server_hash1{$server}{$lpar}{week}{$lan}{value_avrg} = $day_v;
          $server_hash1{$server}{$lpar}{week}{$lan}{value_max}  = $day_v_max;
          $server_hash1{$server}{$lpar}{week}{$lan}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash1{$server}{$lpar}{week}{$lan}{value_avrg} = $week_v;
      $server_hash1{$server}{$lpar}{week}{$lan}{value_max}  = $week_v_max;
      $server_hash1{$server}{$lpar}{week}{$lan}{update}     = $mtime;
    }
    if ( defined $server_hash1{$server}{$lpar}{month}{$lan} && $server_hash1{$server}{$lpar}{month}{$lan} ne '' ) {
      if ( defined $server_hash1{$server}{$lpar}{month}{$lan}{update} && $server_hash1{$server}{$lpar}{month}{$lan}{update} ne "" ) {
        if ( $mtime > $server_hash1{$server}{$lpar}{month}{$lan}{update} ) {
          $server_hash1{$server}{$lpar}{month}{$lan}{value_avrg} = $day_v;
          $server_hash1{$server}{$lpar}{month}{$lan}{value_max}  = $day_v_max;
          $server_hash1{$server}{$lpar}{month}{$lan}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash1{$server}{$lpar}{month}{$lan}{value_avrg} = $month_v;
      $server_hash1{$server}{$lpar}{month}{$lan}{value_max}  = $month_v_max;
      $server_hash1{$server}{$lpar}{month}{$lan}{update}     = $mtime;
    }
    if ( defined $server_hash1{$server}{$lpar}{year}{$lan} && $server_hash1{$server}{$lpar}{year}{$lan} ne '' ) {
      if ( defined $server_hash1{$server}{$lpar}{year}{$lan}{update} && $server_hash1{$server}{$lpar}{year}{$lan}{update} ne "" ) {
        if ( $mtime > $server_hash1{$server}{$lpar}{year}{$lan}{update} ) {
          $server_hash1{$server}{$lpar}{year}{$lan}{value_avrg} = $day_v;
          $server_hash1{$server}{$lpar}{year}{$lan}{value_max}  = $day_v_max;
          $server_hash1{$server}{$lpar}{year}{$lan}{update}     = $mtime;
        }
      }
    }
    else {
      $server_hash1{$server}{$lpar}{year}{$lan}{value_avrg} = $year_v;
      $server_hash1{$server}{$lpar}{year}{$lan}{value_max}  = $year_v_max;
      $server_hash1{$server}{$lpar}{year}{$lan}{update}     = $mtime;
    }
  }
}

#print Dumper \%server_hash1;

my @lines_top_out3;
foreach my $server ( keys %server_hash ) {    #################### SAN IOPS
  foreach my $lpar ( keys %{ $server_hash{$server} } ) {
    my ( $day_values, $week_values, $month_values, $year_values, $day_values_max, $week_values_max, $month_values_max, $year_values_max );
    foreach my $time ( sort keys %{ $server_hash{$server}{$lpar} } ) {
      foreach my $san ( sort keys %{ $server_hash{$server}{$lpar}{$time} } ) {
        chomp( $server_hash{$server}{$lpar}{$time}{$san}{value_avrg} );
        chomp( $server_hash{$server}{$lpar}{$time}{$san}{value_max} );
        if ( $time eq 'day' ) {
          $day_values     += $server_hash{$server}{$lpar}{$time}{$san}{value_avrg};
          $day_values_max += $server_hash{$server}{$lpar}{$time}{$san}{value_max};
        }
        if ( $time eq 'week' ) {
          $week_values     += $server_hash{$server}{$lpar}{$time}{$san}{value_avrg};
          $week_values_max += $server_hash{$server}{$lpar}{$time}{$san}{value_max};
        }
        if ( $time eq 'month' ) {
          $month_values     += $server_hash{$server}{$lpar}{$time}{$san}{value_avrg};
          $month_values_max += $server_hash{$server}{$lpar}{$time}{$san}{value_max};
        }
        if ( $time eq 'year' ) {
          $year_values     += $server_hash{$server}{$lpar}{$time}{$san}{value_avrg};
          $year_values_max += $server_hash{$server}{$lpar}{$time}{$san}{value_max};
        }
      }
    }

    #print "os_san,$server,$lpar.rrm,hmc,$day_values,$week_values,$month_values,$year_values\n";
    push @lines_top_out3, "os_san_iops,$server,$lpar.rrm,hmc,$day_values,$day_values_max,$week_values,$week_values_max,$month_values,$month_values_max,$year_values,$year_values_max\n";
  }
}

#print "@lines_top_out3\n";

my @lines_top_out5;
foreach my $server ( keys %server_hash1 ) {    ####################### LAN
  foreach my $lpar ( keys %{ $server_hash1{$server} } ) {
    my ( $day_values, $week_values, $month_values, $year_values, $day_values_max, $week_values_max, $month_values_max, $year_values_max );
    foreach my $time ( sort keys %{ $server_hash1{$server}{$lpar} } ) {
      foreach my $lan ( sort keys %{ $server_hash1{$server}{$lpar}{$time} } ) {
        chomp( $server_hash1{$server}{$lpar}{$time}{$lan}{value_avrg} );
        chomp( $server_hash1{$server}{$lpar}{$time}{$lan}{value_max} );
        if ( $time eq 'day' ) {
          $day_values     += $server_hash1{$server}{$lpar}{$time}{$lan}{value_avrg};
          $day_values_max += $server_hash1{$server}{$lpar}{$time}{$lan}{value_max};
        }
        if ( $time eq 'week' ) {
          $week_values     += $server_hash1{$server}{$lpar}{$time}{$lan}{value_avrg};
          $week_values_max += $server_hash1{$server}{$lpar}{$time}{$lan}{value_max};
        }
        if ( $time eq 'month' ) {
          $month_values     += $server_hash1{$server}{$lpar}{$time}{$lan}{value_avrg};
          $month_values_max += $server_hash1{$server}{$lpar}{$time}{$lan}{value_max};
        }
        if ( $time eq 'year' ) {
          $year_values     += $server_hash1{$server}{$lpar}{$time}{$lan}{value_avrg};
          $year_values_max += $server_hash1{$server}{$lpar}{$time}{$lan}{value_max};
        }
      }
    }

    #print "os_san,$server,$lpar.rrm,hmc,$day_values,$week_values,$month_values,$year_values\n";
    push @lines_top_out5, "os_lan,$server,$lpar.rrm,hmc,$day_values,$day_values_max,$week_values,$week_values_max,$month_values,$month_values_max,$year_values,$year_values_max\n";
  }
}

#print "@lines_top_out5\n";

my @lines_top_out7;
foreach my $server ( keys %server_hash2 ) {    #################### SAN1
  foreach my $lpar ( keys %{ $server_hash2{$server} } ) {
    my ( $day_values, $week_values, $month_values, $year_values, $day_values_max, $week_values_max, $month_values_max, $year_values_max );
    foreach my $time ( sort keys %{ $server_hash2{$server}{$lpar} } ) {
      foreach my $san ( sort keys %{ $server_hash2{$server}{$lpar}{$time} } ) {
        chomp( $server_hash2{$server}{$lpar}{$time}{$san}{value_avrg} );
        chomp( $server_hash2{$server}{$lpar}{$time}{$san}{value_max} );
        if ( $time eq 'day' ) {
          $day_values     += $server_hash2{$server}{$lpar}{$time}{$san}{value_avrg};
          $day_values_max += $server_hash2{$server}{$lpar}{$time}{$san}{value_max};
        }
        if ( $time eq 'week' ) {
          $week_values     += $server_hash2{$server}{$lpar}{$time}{$san}{value_avrg};
          $week_values_max += $server_hash2{$server}{$lpar}{$time}{$san}{value_max};
        }
        if ( $time eq 'month' ) {
          $month_values     += $server_hash2{$server}{$lpar}{$time}{$san}{value_avrg};
          $month_values_max += $server_hash2{$server}{$lpar}{$time}{$san}{value_max};
        }
        if ( $time eq 'year' ) {
          $year_values     += $server_hash2{$server}{$lpar}{$time}{$san}{value_avrg};
          $year_values_max += $server_hash2{$server}{$lpar}{$time}{$san}{value_max};
        }
      }
    }

    #print "os_san,$server,$lpar.rrm,hmc,$day_values,$week_values,$month_values,$year_values\n";
    push @lines_top_out7, "os_san1,$server,$lpar.rrm,hmc,$day_values,$day_values_max,$week_values,$week_values_max,$month_values,$month_values_max,$year_values,$year_values_max\n";
  }
}

#print "@lines_top_out7";
push @lines_top_out, @lines_top_out1, @lines_top_out3, @lines_top_out5, @lines_top_out7;

#reduce lines from dual hmc
my @lines_top_out_sorted = sort @lines_top_out;
my @lines_top_out_reduced;

#print "@lines_top_out_sorted";
my $last_server = "";
my $last_lpar   = "";
foreach my $line (@lines_top_out_sorted) {
  chomp($line);
  ( undef, my $server, my $lpar, my $hmc ) = split( ',', $line );

  #print"$server,$lpar,$hmc\n";
  next if ( $server eq $last_server && $lpar eq $last_lpar );
  push( @lines_top_out_reduced, "$line" );

  # print "last $last_server $last_lpar, now $server $lpar\n";
  $last_server = $server;
  $last_lpar   = $lpar;
}

# print "after reduction\n";

#  print join("", @lines_top_out_reduced);
my $outfile = "$tmpdir/topten.tmp";
open( OFH, "> $outfile" ) || error( "Cannot open $outfile: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
foreach my $line (@lines_top_out_reduced) {
  print OFH "$line\n";
}
close OFH;

print "topten file    : prepared for POWER at " . localtime( time() ) . "\n";

sub print_head_lpar_check {

  my $body = "<center><h4>Data health check: IBM Power Systems LPARs and servers not being updated</h4></center>
    <table><tbody><tr><td><center><table class =\"tabconfig tablesorter\">
    <thead><tr><th class = \"sortable\">SERVER&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">HMC&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">VM/LPAR/CPU Pool/MEM&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">last update&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">Type&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</tr></thead><tbody>";

  print FHW "$body\n";

  return (0);
}

# +++++ Charlie's part +++++

# agent activity table
# creating web pages agent

print "agent activity : test starting at " . localtime( time() ) . "\n";

my $agent_html = "$webdir/daily_agent_check.html";

open( FHW, "> $agent_html" ) || error( "Cannot open $agent_html: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;

print_head_agent_check();

open( FH, "< $filelpst" ) || error( "Cannot read $filelpst: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
@lines = <FH>;
close(FH);

# looking for lpar data

my @lines2 = grep { !/^InFo/ & !/poool$/ } @lines;

my @lines3 = sort @lines2;

# This foreach sets up lpar status, agent OS status and agent NMON status
my $lpar_last_found       = "";
my $agent_os_last_found   = "";
my $agent_nmon_last_found = "";

foreach (@lines3) {

  #  print "970 $_\n";
  ( my $server, my $hmc, my $lpar, my $status, my $last_update ) = split( ",", $_ );
  if ( $server =~ /Solaris/ && $hmc ne "no_hmc" ) {

    print "962 \$server ,$server, \$hmc ,$hmc,\n";

    #next;
  }
  my $lpar_a = $lpar;
  $lpar =~ s/$NMON$//;
  $lpar =~ s/\.rrm$//;
  $lpar =~ s/$AS400$//;
  ( my $server_hmc, my $others, undef ) = split( "$lpar", $_ );
  my $lpar_found = "$server_hmc$lpar\.[r|m]..";
  if ( $lpar_found eq $lpar_last_found ) {next}
  $lpar_last_found = $lpar_found;
  my $lpar_found_slash = $lpar_found;
  $lpar_found_slash = "\Q" . $lpar_found_slash;    #    ."\E";
  my @lpar_array  = grep {/$lpar_found_slash/} @lines3;
  my $lpar_status = "running";

  if ( @lpar_array > 0 ) {
    if ( $lpar_array[0] !~ /,OK,/ ) {
      $lpar_status = "not updated";
    }
  }
  else {
    $lpar_status = "not installed";
  }

  my $agent_os_found = "$server_hmc$lpar,agent";
  if ( $agent_os_found eq $agent_os_last_found ) {next}
  $agent_os_last_found = $agent_os_found;
  my @agent_os_array  = grep {/$agent_os_found|$server_hmc$lpar$AS400,agent/} @lines3;
  my $agent_os_status = "running";
  if ( @agent_os_array > 1 ) { error( "double agent OS $agent_html: $!" . __FILE__ . ":" . __LINE__ ); }
  if ( @agent_os_array > 0 ) {
    if ( $agent_os_array[0] !~ /agent_OK/ ) {
      $agent_os_status = "not updated";
    }
  }
  else {
    $agent_os_status = "not installed";
  }

  my $agent_nmon_found = "$server_hmc$lpar$NMON,agent";
  if ( $agent_nmon_found eq $agent_nmon_last_found ) {next}
  $agent_nmon_last_found = $agent_nmon_found;
  my @agent_nmon_array  = grep {/$agent_nmon_found/} @lines3;
  my $agent_nmon_status = "running";
  if ( @agent_nmon_array > 1 ) { error( "double agent NMON $agent_html: $!" . __FILE__ . ":" . __LINE__ ); }
  if ( @agent_nmon_array > 0 ) {
    if ( $agent_nmon_array[0] !~ /agent_OK/ ) {
      $agent_nmon_status = "not updated";
    }
  }
  else {
    $agent_nmon_status = "not installed";
  }

  my $version_agent_path = "$wrkdir/$server/$hmc/$lpar/agent.cfg";
  if ( !-f "$version_agent_path" ) {
    $version_agent_path = "$wrkdir/$server/$hmc/$lpar$AS400/agent.cfg";
  }

  # print "1001 daily_lpar_check.pl \$agent_os_status $agent_os_status \$version_agent_path $version_agent_path\n";

  ### IP address check

  my $ip_agent   = "$wrkdir/$server/$hmc/$lpar/IP.txt";
  my $ip_address = "";
  if ( -f "$ip_agent" ) {
    open( IP, "< $ip_agent" ) || error( "Cannot read $ip_agent: $!" . __FILE__ . ":" . __LINE__ ) && next;
    $ip_address = <IP>;
    close(IP);
    if ($ip_address) {
      chomp $ip_address;
      $ip_address = "&nbsp;&nbsp;&nbsp;$ip_address";
    }
    else {
      $ip_address = "-";
    }
  }
  else {
    $ip_address = "-";
  }

  ###

  my $agent_version;
  if ( $agent_os_status eq "not installed" && $agent_nmon_status eq "not installed" ) {
    $agent_version = "";
  }
  else {
    if ( -f "$version_agent_path" ) {
      open( DATA, "< $version_agent_path" ) || error( "Cannot read $version_agent_path: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
      $agent_version = <DATA>;
      chomp $agent_version;
      $agent_version = "&nbsp;&nbsp;&nbsp;$agent_version";
      close(DATA);

    }
    else {
      $agent_version = "< 4.70";
    }
  }
  my $lpar_slash = $lpar;
  $lpar_slash =~ s/&&1/\//g;
  if ( $lpar_a = /--AS400--/ ) {
    next;
  }
  if ( $hmc =~ /no_hmc/ ) { $hmc = "NA"; }
  $server =~ s/--unknown//g;

  # print FHW "<tr><td>$server</td><td>$hmc</td><td>$lpar_slash</td><td>$lpar_status</td><td>$agent_os_status</td><td>$agent_nmon_status</td><td>$agent_version</td><td>$ip_address</td></tr>\n";
  print FHW "<tr><td>$server</td><td>$hmc</td><td>$lpar_slash</td><td>$agent_os_status</td><td>$agent_nmon_status</td><td>$agent_version</td><td>$ip_address</td></tr>\n";
  $count = $count + 1;
}

# Solaris agent to OS AGENT CHECK
foreach my $line (@list_of_solaris) {
  my ( undef, undef, $server, $ldom_name, undef, undef, undef, undef, undef ) = split( /:/, $line );
  $ldom_name =~ s/===double-col===/:/g;
  my $ip_agent        = "$wrkdir/Solaris--unknown/no_hmc/$ldom_name/IP.txt";
  my $agent_cfg       = "$wrkdir/Solaris--unknown/no_hmc/$ldom_name/agent.cfg";
  my $cpu_mmm         = "$wrkdir/Solaris--unknown/no_hmc/$ldom_name/cpu.mmm";
  my $agent_os_status = "not installed";
  my $agent_version   = "";
  my $ip_address      = "";

  if ( -f $cpu_mmm ) {
    $agent_os_status = "running";
    if ( -f "$ip_agent" ) {
      open( IP, "< $ip_agent" ) || error( "Cannot read $ip_agent: $!" . __FILE__ . ":" . __LINE__ ) && next;
      $ip_address = <IP>;
      close(IP);
      if ($ip_address) {
        chomp $ip_address;
        $ip_address = "&nbsp;&nbsp;&nbsp;$ip_address";
      }
      else {
        $ip_address = "-";
      }
    }
    else {
      $ip_address = "-";
    }
    if ( -f "$agent_cfg" ) {
      open( CFG, "< $agent_cfg" ) || error( "Cannot read $agent_cfg: $!" . __FILE__ . ":" . __LINE__ ) && next;
      $agent_version = <CFG>;
      close(IP);
      if ($ip_address) {
        chomp $ip_address;
        $agent_version = "&nbsp;&nbsp;&nbsp;$agent_version";
      }
      else {
        $agent_version = "-";
      }
    }
    else {
      $agent_version = "-";
    }
  }

  # print FHW "<tr><td>Solaris</td><td>NA</td><td>$ldom_name</td><td>-</td><td>$agent_os_status</td><td>-</td><td>$agent_version</td><td>$ip_address</td></tr>\n";
  print FHW "<tr><td>Solaris</td><td>NA</td><td>$ldom_name</td><td>$agent_os_status</td><td>-</td><td>$agent_version</td><td>$ip_address</td></tr>\n";
}

print FHW "</tbody></table></center></td></tr>";

if ( $count == 0 ) {
  print FHW "Something wrong. Server hasn´t lpars.<br>\n";
}
print FHW "<tr><td>Report has been created at: $act_time<br>\n";
print FHW "Table above shows agent activity within last 24 hours.<br>\n";
print FHW "Lpars and servers not updated more than 30 days are ignored.<br>\n";
print FHW "</td></tr></tbody></table></body></html>\n";
close(FHW);

print "agent activity : test finished at " . localtime( time() ) . "\n";

sub print_head_agent_check {

  my $body = "<br>
<table><tbody><tr><td><center><table class =\"tabconfig tablesorter\">
<thead><tr><th class = \"sortable\">SERVER&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">HMC&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">VM/LPAR/CPU Pool/MEM&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">Agent OS&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">Agent NMON&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">Agent version&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">IP&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th></tr></thead><tbody>";

  # <thead><tr><th class = \"sortable\">SERVER&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">HMC&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">VM/LPAR/CPU Pool/MEM&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">Lpar status&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">Agent OS&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">Agent NMON&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">Agent version&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable\">IP&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th></tr></thead><tbody>";
  print FHW "$body\n";

  return (0);
}

# configuration summary

print "config summary : preparing at " . localtime( time() ) . "\n";

# looking for data

my @path_lines              = grep { !/^InFo/ & !/poool$/ } @lines2;
my $last_summary_found      = "";
my $path_last_summary_found = "";

# looking for servers from daily_lpar_check.txt, opening servers config.cfg, cpu.cfg and mem.html

my @all_data_arr;

my $last_found      = "";
my $path_last_found = "";

foreach (@lines3) {
  ( my $server, my $hmc, my $lpar, my $status, my $last_update ) = split( ",", $_ );
  $lpar =~ s/$NMON$//;
  $lpar =~ s/\....$//;

  ( my $server_hmc, my $others, undef ) = split( "$lpar", $_ );

  my $found = "$server,$hmc,$lpar";

  #print STDERR " -- 03 $found \n";
  if ( $found eq $last_found ) {next}
  $last_found = $found;

  my $cpu_cfg    = "$wrkdir/$server/$hmc/cpu\.cfg";
  my $mem_html   = "$wrkdir/$server/$hmc/mem\.html";
  my $config_cfg = "$wrkdir/$server/$hmc/config\.cfg";
  my $state_file = "$wrkdir/$server/$hmc/cpu\.cfg-$lpar";

  if ( !-f $cpu_cfg || !-f $mem_html || !-f $config_cfg ) {

    # it is not IBM Power!
    #print "Does not exist ($server/$hmc): $cpu_cfg || $mem_html || $config_cfg\n";
    next;
  }

  #print STDERR " -- 04 $found \n";
  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }

  # go through all HMCs, some might be unused with old data already, then taking the most fresh one
  my @files     = <$wrkdir/$server_space/*/cpu\.cfg>;
  my $file_time = 0;
  foreach my $file_act (@files) {
    my $file_time_act = ( stat("$file_act") )[9];
    if ( $file_time_act > $file_time ) {
      $cpu_cfg   = $file_act;
      $file_time = $file_time_act;
    }
  }

  @files     = <$wrkdir/$server_space/*/config\.cfg>;
  $file_time = 0;
  foreach my $file_act (@files) {
    my $file_time_act = ( stat("$file_act") )[9];
    if ( $file_time_act > $file_time ) {
      $config_cfg = $file_act;
      $file_time  = $file_time_act;
    }
  }

  @files     = <$wrkdir/$server_space/*/mem\.html>;
  $file_time = 0;
  foreach my $file_act (@files) {
    my $file_time_act = ( stat("$file_act") )[9];
    if ( $file_time_act > $file_time ) {
      $mem_html  = $file_act;
      $file_time = $file_time_act;
    }
  }

  # @files  = <$wrkdir/$server_space/*/cpu.cfg-$lpar>;
  @files     = bsd_glob "$wrkdir/$server_space/*/cpu.cfg-$lpar";
  $file_time = 0;
  foreach my $file_act (@files) {

    # print "1154 daily_lpar_check.pl \$file_act $file_act\n";
    my $file_time_act = ( stat("$file_act") )[9];
    if ( $file_time_act > $file_time ) {
      $state_file = $file_act;
      $file_time  = $file_time_act;
    }
  }

  my $path_found = "$server";
  if ( $path_found eq $path_last_found ) {next}
  $path_last_found = $path_found;
  my @path_array = grep {/$path_found/} $server_hmc;
  my $path       = $path_array[0];

  #print STDERR " -- 05 $found \n";

  my @lines_cpu;
  open( FH, "< $cpu_cfg" ) || error( "Cannot read $cpu_cfg: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
  @lines_cpu = <FH>;
  close(FH);

  my @lines_mem;
  open( FH, "< $mem_html" ) || error( "Cannot read $mem_html: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
  @lines_mem = <FH>;
  close(FH);

  my @lines_config;
  open( FH, "< $config_cfg" ) || error( "Cannot read $config_cfg: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
  @lines_config = <FH>;
  close(FH);

  my @cores;

  #take data from configs

  my $configurable_sys_proc_units = "";
  if ( grep {/configurable_sys_proc_units/} @lines_config ) {
    ($configurable_sys_proc_units) = grep {/configurable_sys_proc_units/} @lines_config;
    $configurable_sys_proc_units =~ s/configurable_sys_proc_units//;
    $configurable_sys_proc_units =~ s/<td>//g;
    $configurable_sys_proc_units =~ s/<\/td>//g;
    $configurable_sys_proc_units =~ s/\s+//;
    chomp $configurable_sys_proc_units;
  }

  my $curr_avail_sys_proc_units = "";
  if ( grep {/curr_avail_sys_proc_units/} @lines_config ) {
    ($curr_avail_sys_proc_units) = grep {/curr_avail_sys_proc_units/} @lines_config;
    $curr_avail_sys_proc_units =~ s/curr_avail_sys_proc_units//;
    $curr_avail_sys_proc_units =~ s/<td>//g;
    $curr_avail_sys_proc_units =~ s/<\/td>//g;
    $curr_avail_sys_proc_units =~ s/\s+//;
    chomp $curr_avail_sys_proc_units;
  }

  my $configurable_sys_mem = "";
  if ( grep {/configurable_sys_mem/} @lines_config ) {
    ($configurable_sys_mem) = grep {/configurable_sys_mem/} @lines_config;
    $configurable_sys_mem =~ s/configurable_sys_mem//;
    $configurable_sys_mem =~ s/<td>//g;
    $configurable_sys_mem =~ s/<\/td>//g;
    $configurable_sys_mem =~ s/\s+//;
    chomp $configurable_sys_mem;
  }

  my $curr_avail_sys_mem = "";
  if ( grep {/curr_avail_sys_mem/} @lines_config ) {
    ($curr_avail_sys_mem) = grep {/curr_avail_sys_mem/} @lines_config;
    $curr_avail_sys_mem =~ s/curr_avail_sys_mem//;
    $curr_avail_sys_mem =~ s/<td>//g;
    $curr_avail_sys_mem =~ s/<\/td>//g;
    $curr_avail_sys_mem =~ s/\s+//;
    chomp $curr_avail_sys_mem;
  }

  foreach (@lines_cpu) {
    my ( $lpar_name, undef ) = split( ",", $_ );
    $lpar_name =~ s/^lpar_name=//;

    my $lines_conf = "@lines_config";
    $lines_conf =~ s/\n/===new_line===/g;
    $lines_conf =~ s/^.+<CENTER><B>.LPAR.:.$lpar_name//g;
    $lines_conf =~ s/<\/PRE><B>LPAR profiles:<\/B><PRE>.+name.+$lpar_name.+$//g;
    $lines_conf =~ s/===new_line===/\n/g;

    #print $lines_conf;
    my @conf       = split( "\n", $lines_conf );
    my $lpar_state = "";

    #foreach my $line (@conf) {
    #  chomp $line;
    #  $line =~ s/^\s+//g;
    #  $line =~ s/\s+$//g;
    #  if ( $line =~ /^name/ ) {
    #    $line =~ s/^name\s+//g;
    #
    #        #print "$line\n";
    #      }
    #      if ( $line =~ /^state/ ) {
    #        $line =~ s/^state\s+//g;
    #
    #        #print "$line\n";
    #        $lpar_state = $line;
    #      } ## end if ( $line =~ /^state/)
    #      if ( $line =~ /^primary_state/ ) {
    #        $line =~ s/^primary_state\s+//g;
    #
    #        #print "$line\n";
    #        $lpar_state = $line;
    #      } ## end if ( $line =~ /^primary_state/)
    #    } ## end foreach my $line (@conf)
    ( $state_file, undef ) = split( '/cpu\.cfg-', $state_file );
    my $lpar_trans = $lpar_name;
    $lpar_trans =~ s/\//&&1/g;
    $state_file = "$state_file/cpu.cfg-$lpar_trans";
    $lpar_state = lpar_state_in_configcfg($state_file);
    if ( $_ =~ "run_proc_units=" && $_ =~ "^lpar_name=" ) {
      $_ =~ s/^.+run_proc_units=//;
      $_ =~ s/,.+//;
      chomp $_;
      push( @cores, "$server,$lpar_name,$_,$lpar_state" );
    }
    else {
      $_ =~ s/^.+run_procs=//;
      $_ =~ s/,.+//;
      chomp $_;
      push( @cores, "$server,$lpar_name,$_,$lpar_state" );
    }
  }
  my @pools;

  my $lines_conf = "@lines_config";
  $lines_conf =~ s/\n/===new_line===/g;
  $lines_conf =~ s/^.+<B>CPU pools:<\/B>//g;

  $lines_conf =~ s/<B>Memory:<\/B>.+$//g;

  #print $lines_conf;
  my @pool_conf                     = split( "===new_line===", $lines_conf );
  my $name_pool                     = "";
  my $max_pool_proc_units           = "";
  my $shared_proc_pool_id           = "";
  my $curr_reserved_pool_proc_units = "";

  foreach my $line (@pool_conf) {
    chomp $line;
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;

    #print "$line\n";
    if ( $line =~ /^name/ ) {
      $line =~ s/^name\s+//g;
      $name_pool = $line;

      #print "$line\n";
    }
    if ( $line =~ /^max_pool_proc_units/ ) {
      $line =~ s/^max_pool_proc_units\s+//g;
      $max_pool_proc_units = $line;

      #print "$line\n";
    }
    if ( $line =~ /^shared_proc_pool_id/ ) {
      $line =~ s/^shared_proc_pool_id\s+/SharedPool/g;
      $shared_proc_pool_id = $line;

      #print "$line\n";
    }
    if ( $line =~ /^curr_reserved_pool_proc_units/ ) {
      $line =~ s/^curr_reserved_pool_proc_units\s+//g;
      $curr_reserved_pool_proc_units = $line;

      #print "$line\n";
      push( @pools, "$name_pool,$curr_reserved_pool_proc_units,$max_pool_proc_units,$shared_proc_pool_id\n" );

      #print "$name_pool,$max_pool_proc_units,$curr_reserved_pool_proc_units,$shared_proc_pool_id\n";
    }
  }

  my @pools_table;

  foreach (@pools) {
    ( my $pool, my $res, my $max, my $SharedPool ) = split( ",", $_ );
    chomp $pool;
    chomp $res;
    chomp $max;
    chomp $SharedPool;
    if ( $pool =~ /^DefaultPool/ ) { next; }
    push( @pools_table, "$server,$hmc,pool_name,$pool,$res,$max,$SharedPool\n" );
  }

  my @lpars_table;

  foreach (@lines_mem) {
    my @lpar_mem = grep {/<\/TD><\/TR>$/} $_;

    foreach (@lpar_mem) {
      my @mem = split( "<TD", $_ );
      $mem[1] =~ s/<\/B><\/TD>\s$//;
      $mem[1] =~ s/^><B>//;
      $mem[5] =~ s/<\/TD><\/TR>$//;
      $mem[5] =~ s/^\salign="center">//;
      chomp $mem[5];
      my @grep_cores = grep {/$server,$mem[1],/} @cores;
      my $items      = "@grep_cores,$server,$mem[1],$mem[5]";

      #my @table_items = split( ",", $items );
      my ( undef, $tb_item1, $tb_item2, $tb_item3, undef, undef, $tb_item6 ) = split( /,/, $items );
      if ( !defined $tb_item1 ) { $tb_item1 = ""; }
      if ( !defined $tb_item2 ) { $tb_item2 = ""; }
      if ( !defined $tb_item3 ) { $tb_item3 = ""; }
      if ( !defined $tb_item6 ) { $tb_item6 = ""; }

      push( @lpars_table, "$server,$hmc,lpar_name,$tb_item1,$tb_item2,$tb_item6,$tb_item3\n" );
    }
  }

  #print STDERR " -- 08 $server:$hmc \n";
  if ( -f "$wrkdir/$server/$hmc/cpu.cfg" ) {

    #print STDERR " -- 09 $server:$hmc \n";
    push( @all_data_arr, "server_name,$server,$hmc\n" );
    push( @all_data_arr, "summary,EC,MEM\n" );
    push( @all_data_arr, "TOTAL,$server,$configurable_sys_proc_units,$configurable_sys_mem\n" );
    push( @all_data_arr, "FREE,$server,$curr_avail_sys_proc_units,$curr_avail_sys_mem\n" );
    push( @all_data_arr, "CPU pools:,Res,Max\n" );
    push( @all_data_arr, @pools_table );
    push( @all_data_arr, "\n" );
    push( @all_data_arr, "LPAR,EC,MEM\n" );
    push( @all_data_arr, @lpars_table );
    push( @all_data_arr, "\n\n" );
  }
}

#print @all_data_arr;
my @servers = grep {/^server_name,/} @all_data_arr;

#creating table to web page
my $cfg_summary_html = "$webdir/cfg_summary.html";

open( FHW, "> $cfg_summary_html" ) || error( "Cannot open $cfg_summary_html: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;

print FHW "<br><center><table class =\"tabcfgsumext\"><thead><tr>\n";

my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };
my %api_list;
foreach my $host_alias ( keys %hosts ) {
  my $host     = $hosts{$host_alias}{host};
  my $auth_api = $hosts{$host_alias}{auth_api};
  if ($auth_api) {
    $api_list{$host} = 1;
  }
  else {
    $api_list{$host} = 0;
  }
}

my %skip_server;
foreach (@servers) {
  my @server_name = split( ",", $_ );
  chomp $server_name[1];
  my $item_uid = PowerDataWrapper::get_item_uid( { type => "SERVER", label => $server_name[1] } );
  if ( !defined $item_uid ) { next; }
  my $server_parent = PowerDataWrapper::get_server_parent($item_uid);
  if ( !defined $server_parent ) { next; }
  my $hmc = PowerDataWrapper::get_label( "HMC", $server_parent );
  if ( !defined $hmc ) { next; }

  if ( defined $api_list{$hmc} && $api_list{$hmc} ) {

    #$skip_server{$server_name[1]} = 1; #solve problem with dual HMC (ssh+api) wip
  }
  else {
    #$skip_server{$server_name[1]} = 1;
  }
}

foreach (@servers) {
  my @server_name = split( ",", $_ );
  chomp $server_name[1];
  if ( $skip_server{ $server_name[1] } ) { next; }

  #print STDERR " -- 10 $server_name[1] \n";
  print FHW "<th colspan=\"3\" style=\"text-align:center;\"><A class=\"backlink\" HREF=\"/lpar2rrd-cgi/detail.sh?host=$server_name[2]&server=$server_name[1]&lpar=pool&item=pool&entitle=0&none=none\">$server_name[1]</th>\n";    #server name
}
print FHW "</tr><tr>\n";

foreach (@servers) {
  my @server_name = split( ",", $_ );
  chomp $server_name[1];
  if ( $skip_server{ $server_name[1] } ) { next; }
  my @totals = grep {/^TOTAL,$server_name[1]/} @all_data_arr;
  my @free   = grep {/^FREE,$server_name[1]/} @all_data_arr;
  print FHW "<td colspan=\"3\"><table class =\"tabcfgsum\">\n";
  print FHW "<thead><th class =\"columnalignleft\"></th><th class =\"columnalignmiddle\">EC</th><th class =\"columnalignright\">MEM</th></thead>\n";                                                                               #1st tabhead
                                                                                                                                                                                                                                   # print "727 daily_lpar_check.pl \@servers @servers \@all_data_arr @all_data_arr\n";

  foreach (@totals) {
    chomp $_;
    my @total_items = split( ",", $_ );
    print FHW "<tr><td class =\"columnalignleft\">TOTAL</td><td class =\"columnalignmiddle\">$total_items[2]</td><td class =\"columnalignright\">$total_items[3]</td></tr>\n";                                                     #total values
  }

  foreach (@free) {
    chomp $_;
    my @free_items = split( ",", $_ );
    print FHW "<tr><td class =\"columnalignleft\">FREE</td><td class =\"columnalignmiddle\">$free_items[2]</td><td class =\"columnalignright\">$free_items[3]</td></tr>\n";                                                        #free values
  }
  print FHW "</table></td>\n";
}
print FHW "</tr><tr>\n";

foreach (@servers) {
  my @server_name = split( ",", $_ );
  chomp $server_name[1];
  chomp $server_name[2];
  if ( $skip_server{ $server_name[1] } ) { next; }
  my @pools = grep {/^$server_name[1],$server_name[2],pool_name,/} @all_data_arr;
  print FHW "<td colspan=\"3\"><table class =\"tabcfgsum\">\n";
  print FHW "<thead>
    <th class =\"columnalignleft\">CPU pools:</th>
    <th class =\"columnalignmiddle\" colspan=\"2\">Reserved</th>
    <th class =\"columnalignmiddle\" colspan=\"2\">Max</th>
  </thead>\n";    #2nd tabhead

  foreach (@pools) {
    my @pool_items = split( ",", $_ );
    chomp $_;
    chomp $pool_items[5];
    chomp $pool_items[6];
    print FHW "
    <tr>
      <td class =\"columnalignleft\" bgcolor=\"#FFFF80\">
        <A class=\"backlink\" HREF=\"/lpar2rrd-cgi/detail.sh?host=$pool_items[1]&server=$pool_items[0]&lpar=$pool_items[6]&item=pool&entitle=0&none=none\">$pool_items[3]</A>
      </td>
      <td class =\"columnalignright\" bgcolor=\"#FFFF80\" colspan=\"2\">$pool_items[4]</td>
      <td class =\"columnalignright\" bgcolor=\"#FFFF80\" colspan=\"2\">$pool_items[5]</td>
    </tr>\n";    #pools values

  }
  print FHW "</table></td>\n";
}
print FHW "</tr>";

foreach (@servers) {
  my @server_name = split( ",", $_ );
  chomp $server_name[1];
  chomp $server_name[2];
  if ( $skip_server{ $server_name[1] } ) { next; }
  my @lpars = grep {/^$server_name[1],$server_name[2],lpar_name,/} @all_data_arr;
  print FHW "<td colspan=\"3\"><table class =\"tabcfgsum tablesorter tablesortercfgsum\">\n";
  print FHW "<thead><tr><th class = \"sortable columnalignleft\">LPAR</th><th class = \"sortable columnalignmiddle\">EC&nbsp;&nbsp;&nbsp;&nbsp;</th><th class = \"sortable columnalignright\">MEM&nbsp;&nbsp;&nbsp;&nbsp;</th></tr></thead><tbody>\n";    #3rd tabhead
  foreach (@lpars) {
    my @lpar_items = split( ",", $_ );
    chomp $lpar_items[5];
    if ( $lpar_items[6] =~ m/[Ss]tarted/ || $lpar_items[6] =~ m/[Rr]unning/ ) {
      print FHW "<tr><td class =\"columnalignleft\" bgcolor=\"#80FF80\"><A class=\"backlink\" HREF=\"/lpar2rrd-cgi/detail.sh?host=$lpar_items[1]&server=$lpar_items[0]&lpar=$lpar_items[3]&item=lpar&entitle=0&none=none\">$lpar_items[3]</A></td><td class =\"columnalignmiddle\" bgcolor=\"#80FF80\">$lpar_items[4]</td><td class =\"columnalignright\" bgcolor=\"#80FF80\">$lpar_items[5]</td></tr>\n";    #lpars values
    }
    else {
      print FHW "<tr><td class =\"columnalignleft\" bgcolor=\"#FF8080\"><A class=\"backlink\" HREF=\"/lpar2rrd-cgi/detail.sh?host=$lpar_items[1]&server=$lpar_items[0]&lpar=$lpar_items[3]&item=lpar&entitle=0&none=none\">$lpar_items[3]</A></td><td class =\"columnalignmiddle\" bgcolor=\"#FF8080\">$lpar_items[4]</td><td class =\"columnalignright\" bgcolor=\"#FF8080\">$lpar_items[5]</td></tr>\n";    #lpars values
    }
  }
  print FHW "</tbody></table></td>\n";
}
print FHW "</table>";
print FHW "<br><br><table><tr><td bgcolor=\"#80FF80\"> <font size=\"-1\"> running</font></td>";
print FHW "<td bgcolor=\"#FF8080\"> <font size=\"-1\"> not running</font></td>";
print FHW "<td  bgcolor=\"#FFFF80\"> <font size=\"-1\"> CPU pool</font></td></tr></table><br>";

print FHW "<br>Report has been created at: $act_time<br></center></body></html>\n";
close(FHW);

print "config summary : finished at " . localtime( time() ) . "\n";

#end configuration summary
#
### end of Charlie's part

exit(0);

sub print_head {

  print FHW "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2 Final//EN\">
<HTML>
<HEAD>
  <TITLE>LPAR2RRD old GUI </TITLE>
  <META HTTP-EQUIV=\"pragma\" CONTENT=\"no-cache\">
  <META HTTP-EQUIV=\"Expires\" CONTENT=\"NOW\">
  <META HTTP-EQUIV=\"last modified\" CONTENT=\"NOW\">
<style>
<!--
a {text-decoration: none}
-->
</style>
</HEAD>
<BODY BGCOLOR=\"#D3D2D2\" TEXT=\"#000000\" LINK=\"#0000FF\" VLINK=\"#0000FF\" ALINK=\"#FF0000\" >\n";

  my $body = "<center><h4>Data health check: IBM Power Systems LPARs and servers not being updated</h4></center><br><br>
<center><table>
<tr><th>SERVER&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>HMC&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>VM/LPAR/CPU Pool/MEM&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>last update&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>Type&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th></tr>";

  print FHW "$body\n";

  $body = "<center><h4>Data health check: IBM Power Systems LPARs and servers not being updated</h4></center><br><br>
<center><table class=\"tabconfig\">
<tr><th>SERVER&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>HMC&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>LPAR/CPU Pool/MEM&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>last update&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th><th>Type&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th></tr>";
  print FHG "$body\n";

  return (0);
}

sub read_lpars {

  my %vm_found   = ();
  my $list_of_vm = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
  my @vm_list    = ();
  if ( -f $list_of_vm ) {    ####### ALL VM in @vm_list
    open( FC, "< $list_of_vm" ) || error( "Cannot read $list_of_vm: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
    @vm_list = <FC>;
    close(FC);
  }
  else {
    print "D_L_CH         : VMWARE not detected\n";
  }

  my $act_time_u = time();
  `rm -f $tmpdir/topten_vm.tmp`;
  my $rrd_started = 0;
  my $i_foreach   = 0;
  foreach my $server_all (<$wrkdir/*>) {
    my $server = basename($server_all);

    #    print "00 $server_all in \$wrkdir $wrkdir\n";
    if ( -l $server_all )           { next; }
    if ( $server_all =~ m/\.rrx$/ ) { print VYFILE "InFo_serv,$server,found database,server\n"; next; }
    if ( !-d $server_all )          { print VYFILE "InFo_serv,$server,non-existent,server\n"; next; }
    if ( $server eq "vmware_VMs" )  { print VYFILE "InFo_serv,$server,VMWARE VMs,server\n"; next; }

    # exclude excluded servers
    my $managed_ok = 1;
    if ( $managed_systems_exclude ne '' ) {
      my @m_excl = split( /:/, $managed_systems_exclude );
      foreach my $managedname_exl (@m_excl) {
        chomp($managedname_exl);
        if ( $server =~ m/^$managedname_exl$/ ) {
          $managed_ok = 0;
        }
      }
    }
    if ( $managed_ok == 0 ) {
      next;
    }

    # if vCenter has been detected
    if ( $server =~ "^vmware_" ) {
      print VYFILE "InFo_serv,$server,VMWARE vCenter,server\n";

      # my $vcenter_name = ( glob "$server_all/cluster_*/vcenter_name_*" )[0];

      my $vcenter_name = ( bsd_glob "$server_all/*/vcenter_name_*" )[0];    # there can be servers not under cluster
      next if !defined $vcenter_name or $vcenter_name eq "";                # no such file

      $vcenter_name =~ s/.*vcenter_name_//;
      my $vcenter_alias_name = "$server_all/vmware_alias_name";
      my $vcenter_alias      = "";
      if ( !-f $vcenter_alias_name ) {
        error( "vCenter $vcenter_name has not  $vcenter_alias_name: " . __FILE__ . ":" . __LINE__ ) && next;
      }
      if ( ( $act_time_u - ( stat("$vcenter_alias_name") )[9] ) > ($x_days_sec) ) {
        print VYFILE "InFo_vcenter,$vcenter_name,older 90 days,$vcenter_alias_name in $server_all \n";
        next;
      }
      open( FH, "<$vcenter_alias_name" ) || error( "Cannot read $vcenter_alias_name: $!" . __FILE__ . ":" . __LINE__ ) && next;
      $vcenter_alias = <FH>;
      close(FH);
      chomp $vcenter_alias;
      $vcenter_alias = ( split( /\|/, $vcenter_alias ) )[1];
      print "topten file VM : starting " . localtime() . " for vcenter: $vcenter_alias\n";

      #   create list vms_in_vcenter from all servers file lpar_trans.txt, hmc is vcenter_name !
      my %vms_in_vcenter = ();

      # trick to concatenate files for reading per lines
      # @ARGV = bsd_glob "$wrkdir/*/$vcenter_name/lpar_trans.txt"; # this is obsolete
      @ARGV = bsd_glob "$wrkdir/*/$vcenter_name/cpu.csv";
      next if !defined $ARGV[0] || $ARGV[0] eq "";

      # print "874 daily_lpar_check.pl found file \@ARGV ,@ARGV, for vcenter \n";

      #   start RRD via a pipe

      if ( !-f "$rrdtool" ) {
        error( localtime() . "Set correct path to rrdtool binary, it does not exist here: $rrdtool: " . __FILE__ . ":" . __LINE__ ) && exit;
      }
      if ( $rrd_started == 0 ) {
        RRDp::start "$rrdtool";
        $rrd_started = 1;
      }

      my @lines_top_out;
      my %vm_names_once = ();

      my $name_out = "shade";

      # read lines from all files from @ARGV
      while (<>) {

        # ( my $vm_uuid, my $vm_name ) = split( ",", $_ );
        my ( $vm_name, $vm_uuid ) = "";
        if ( $demo eq "1" ) {
          ( $vm_name, undef, undef, undef, undef, undef, undef, undef, undef, $vm_uuid, undef ) = split( ",", $_ );
        }
        else {
          ( $vm_name, undef, undef, undef, undef, undef, undef, undef, undef, undef, $vm_uuid, undef ) = split( ",", $_ );
        }
        if ( ( !defined $vm_uuid ) or ( !defined $vm_name ) ) {

          # print "err line: $_\n"; # not interesting, skip it
          next;
        }
        chomp( $vm_name, $vm_uuid );    # sometimes necessary
                                        # print "889 daily_lpar_check.pl \$vm_uuid $vm_uuid \$vm_name $vm_name\n";
        my $rrd = "$wrkdir/vmware_VMs/$vm_uuid.rrm";

        # print "891 daily_lpar_check.pl testing VM $rrd\n";
        next if !-f $rrd;
        next if exists $vm_found{$vm_uuid};    # probably renamed VM
        $vm_found{$vm_uuid} = 1;

        #if ( exists $vm_names_once{$vm_name} ) {
        #  print VYFILE "InFo_serv,$vm_name,possible,duplicate VM\n";
        #  next;
        #}

        # cus VM names can be changed, get last (present) name
        my @present_vm_line = grep {/$vm_uuid/} @vm_list;
        next if !defined $present_vm_line[0] or $present_vm_line[0] eq "";

        # 520e000d-7da2-8001-4d94-02bf9f84657c,EMC ECS,EMC%20ECS,564d1b0d-6c6a-b6ad-5e4f-6dc631e0bae8
        ( undef, my $present_name, undef ) = split( ",", $present_vm_line[0] );
        if ( $present_name ne $vm_name ) {
          print "for uuid $vm_uuid is old name $vm_name but present name $present_name\n";
          $vm_name = $present_name;
        }
        $vm_names_once{$vm_name} = 1;
        my $save_line    = "$vcenter_alias,$vm_name,$vcenter_name";
        my $line_cpu     = "";
        my $line_disk    = "";
        my $line_net     = "";
        my $line_cpu_per = "";
        my $kbmb         = 100;

        foreach my $type ( "d", "w", "m", "y" ) {
          my $start_time = "now-1$type";
          my $end_time   = "now-1$type+1$type";
          my $answer     = "";
          eval {
            RRDp::cmd qq(graph "$name_out"
            "--start" "$start_time"
            "--end" "$end_time"
            "DEF:currc=$rrd:CPU_usage:AVERAGE"
            "PRINT:currc:AVERAGE: %3.2lf"
            "PRINT:currc:MAX: %3.2lf"
            "DEF:currd=$rrd:Disk_usage:AVERAGE"
            "PRINT:currd:AVERAGE: %3.2lf"
            "PRINT:currd:MAX: %3.2lf"
            "DEF:currn=$rrd:Network_usage:AVERAGE"
            "PRINT:currn:AVERAGE: %3.2lf"
            "PRINT:currn:MAX: %3.2lf"
            "DEF:cpu_u_proc=$rrd:CPU_usage_Proc:AVERAGE"
            "DEF:virt_cpu=$rrd:vCPU:AVERAGE"
            "DEF:host_in_hz=$rrd:host_hz:AVERAGE"
            "DEF:cpu_u=$rrd:CPU_usage:AVERAGE"
            "CDEF:CPU_u_proc1=cpu_u_proc,$kbmb,/"
            "CDEF:pageout_b_nf=virt_cpu,$kbmb,/"
            "CDEF:vCPU=virt_cpu,1,/"
            "CDEF:host_MHz=host_in_hz,1000,/,1000,/"
            "CDEF:CPU_usage=cpu_u,1,/"
            "CDEF:CPU_usage_res=CPU_usage,host_MHz,/,vCPU,/,100,*"
            "PRINT:CPU_usage_res:AVERAGE: %3.0lf"
            "PRINT:CPU_usage_res:MAX: %3.0lf"
            );
            $answer = RRDp::read;
          };
          if ($@) {
            error("ERROR reading file $rrd : $@");
            next;
          }
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
            next;
          }
          my $aaa = $$answer;
          $aaa =~ s/NaNQ|NaN|nan/0/g;

          # print "1601 \$vm_uuid \$vm_name $vm_uuid $vm_name \$type $type \$aaa $aaa\n";
          ( undef, my $util_cpu, my $util_cpu_max, my $util_disk, my $util_disk_max, my $util_net, my $util_net_max, my $util_cpu_perc, my $util_cpu_perc_max ) = split( "\n", $aaa );
          chomp $util_cpu;
          chomp $util_disk;
          chomp $util_disk_max;
          chomp $util_net;
          chomp $util_net_max;
          chomp $util_cpu_max;
          chomp $util_cpu_perc;
          chomp $util_cpu_perc_max;
          $util_cpu          =~ s/,/\./;
          $util_disk         =~ s/,/\./;
          $util_disk_max     =~ s/,/\./;
          $util_net          =~ s/,/\./;
          $util_net_max      =~ s/,/\./;
          $util_cpu_max      =~ s/,/\./;
          $util_cpu_perc     =~ s/,/\./;
          $util_cpu_perc_max =~ s/,/\./;
          $util_cpu      /= 1000;
          $util_disk     /= 1000;
          $util_disk_max /= 1000;
          $util_net      /= 1000;
          $util_net_max  /= 1000;
          $util_cpu_max  /= 1000;

          #$util_cpu_perc_max /=1000;
          $line_cpu     .= sprintf( '%.1f', $util_cpu ) . ",";
          $line_cpu     .= sprintf( '%.1f', $util_cpu_max ) . ",";
          $line_disk    .= sprintf( '%.2f', $util_disk ) . ",";
          $line_disk    .= sprintf( '%.2f', $util_disk_max ) . ",";
          $line_net     .= sprintf( '%.2f', $util_net ) . ",";
          $line_net     .= sprintf( '%.2f', $util_net_max ) . ",";
          $line_cpu_per .= sprintf( '%.0f', $util_cpu_perc ) . ",";
          $line_cpu_per .= sprintf( '%.0f', $util_cpu_perc_max ) . ",";
        }
        push @lines_top_out, "vm_cpu,$save_line,$line_cpu$vm_uuid,$server";
        push @lines_top_out, "vm_disk,$save_line,$line_disk$vm_uuid,$server";
        push @lines_top_out, "vm_net,$save_line,$line_net$vm_uuid,$server";
        push @lines_top_out, "vm_perc_cpu,$save_line,$line_cpu_per$vm_uuid,$server";

      }
      $i_foreach++;

      # all VM IOPS in one pass
      if ( $i_foreach <= 1 ) {
        print "topten file VM : IOPS starting " . localtime() . "\n";
        my %hash_vm = ();    #contains vm_name->vm_uuid
        my $uuid;
        my $name_vm;

        #my $list_of_vm = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
        my $vm_dir    = "$wrkdir/vmware_VMs";
        my %hash_test = ();
        opendir( DIR, "$vm_dir" ) || error( " directory does not exists : $vm_dir " . __FILE__ . ":" . __LINE__ ) && return 1;
        my @all_rrm_files = grep {/\.rrm$/} readdir(DIR);
        closedir(DIR);
        s/$_/$vm_dir\/$_/ for @all_rrm_files;

        # prepare list of vcenters
        my %vcenter_name_path = ();
        my %vcenter_uuid_name = ();
        my %vcenter_name_hmc  = ();

        foreach my $center (<$wrkdir/vmware_*>) {
          next if $center =~ "vmware_VMs";
          next if !open( FH, "< $center/vmware_alias_name" );
          my $vmware_alias_name = <FH>;
          close(FH);
          chomp $vmware_alias_name;
          ( undef, $vmware_alias_name ) = split( /\|/, $vmware_alias_name );
          if ( $vmware_alias_name ne "" ) {
            $vcenter_name_path{$vmware_alias_name} = $center;

            # print "1681 \$vmware_alias_name $vmware_alias_name \$center $center\n";
            $vcenter_uuid_name{ basename($center) } = $vmware_alias_name;
          }
          else {
            error( " problem vmware_alias_name in vcenter: $center  " . __FILE__ . ":" . __LINE__ ) && next;
          }

          # print Dumper %vcenter_uuid_name;
        }

        my @all_rrv_files = <$wrkdir/vmware_*/*/*/*.rrv>;

        # print join("\n",@file)."\n";
        my %vm_rrv_path = ();
        foreach (@all_rrv_files) {
          $vm_rrv_path{ ( split "\/", $_ )[-1] }{$_} = 63;
        }

        my @files = ();
        opendir( DIR, "$wrkdir" ) || error( " directory does not exists : $wrkdir " . __FILE__ . ":" . __LINE__ ) && return 1;
        my @wrkdir_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $server_all (@wrkdir_all) {
          $server_all = "$wrkdir/$server_all";

          #print "line 1952 - VMWARE - $server_all\n";
          if ( !-d $server_all )                                                { next; }
          if ( -l $server_all )                                                 { next; }
          if ( $server_all =~ /\/vmware_|\/windows|\/Solaris|\/Linux|\/--HMC/ ) { next; }
          my $server  = basename($server_all);
          my $hmc_dir = "$wrkdir/$server";
          opendir( DIR, "$hmc_dir" ) || error( " directory does not exists : $hmc_dir " . __FILE__ . ":" . __LINE__ ) && next;
          my @hmc_dir_all = grep !/^\.\.?$/, readdir(DIR);
          closedir(DIR);
          s/$_/$hmc_dir\/$_/ for @hmc_dir_all;

          foreach my $hmc_all (@hmc_dir_all) {    # here should be only one dir but ...
            next if ( !-f "$hmc_all/vmware.txt" );
            next if ( !-f "$hmc_all/pool.rrm" );                                   # take only servers
            next if ( stat("$hmc_all/pool.rrm") )[9] < ( time() - 30 * 86400 );    # ignore servers older 30 days
            my $hmc = basename($hmc_all);

            #print "line 1968 - ESXI - $server_all\n";

            my $vcenter_name = "";
            my $hmc_vcenter  = "";
            if ( open( FH, "< $wrkdir/$server/$hmc/my_vcenter_name" ) ) {
              $vcenter_name = <FH>;
              close(FH);
              chomp $vcenter_name;    # e.g. '10.22.11.10|Regina-new'
              ( $hmc_vcenter, $vcenter_name ) = split( /\|/, $vcenter_name );
              $vcenter_name_hmc{$vcenter_name} = $hmc_vcenter;
            }
            else {
              error( " problem reading file: $wrkdir/$server/$hmc/my_vcenter_name (can be standalone ESXi (not?) under vCenter) " . __FILE__ . ":" . __LINE__ ) && next;
            }
            my $vCenter = "";
            if ( exists $vcenter_name_path{$vcenter_name} ) {
              $vCenter = $vcenter_name_path{$vcenter_name};
            }
            else {
              error( " not existing vcenter $vcenter_name  " . __FILE__ . ":" . __LINE__ ) && next;
            }
            my @line = ();

            # if ( open( FH, "< $wrkdir/$server/$hmc/lpar_trans.txt" ) ) left_curly
            if ( open( FH, "< $wrkdir/$server/$hmc/cpu.csv" ) ) {
              @line = <FH>;
              close(FH);
            }
            else {
              error( " problem reading file: $wrkdir/$server/$hmc/cpu.csv  " . __FILE__ . ":" . __LINE__ ) && next;
            }
            foreach my $rrd_vm (@line) {
              next if index( $rrd_vm, "poweredOff" ) != -1;
              chomp $rrd_vm;

              # print "1710 \$rrd_vm $rrd_vm from $server\n";
              # NetApp_DOT9.1-c1n2,2,0,-1,normal,2000,FreeBSD (64-bit),poweredOn,guestToolsRunning,500f3075-357d-8e31-61e1-7b21447815b1,5120
              my ( $lpar, $uuid ) = "";
              if ( $demo eq "1" ) {
                ( $lpar, undef, undef, undef, undef, undef, undef, undef, undef, $uuid, undef ) = split( /,/, $rrd_vm );

              }
              else {
                ( $lpar, undef, undef, undef, undef, undef, undef, undef, undef, undef, $uuid, undef ) = split( /,/, $rrd_vm );
              }
              chomp( $lpar, $uuid );
              $hash_vm{$lpar} = $uuid;

              my $rrd_file = "";

              # print "3886 \@files @files\n";
              my $i = 0;
              foreach my $rrv_path ( keys %{ $vm_rrv_path{"$uuid.rrv"} } ) {
                $i++;

                #print "%%%$file%%%\n";
                $rrd_file = $rrv_path;
                chomp $rrd_file;
                $hash_test{$lpar}{$vcenter_name}{$i} = "$rrd_file";
              }

              # print "1714 $wrkdir/$server/$hmc/$lpar,$vCenter,$vcenter_name\n";
            }
          }
        }

        #print Dumper \%hash_test;
        my %hash_test1 = ();
        foreach my $lpar ( keys %hash_test ) {
          foreach my $vcenter_name ( %{ $hash_test{$lpar} } ) {
            my $i = 0;
            foreach my $file ( %{ $hash_test{$lpar}{$vcenter_name} } ) {
              if ( defined $hash_test{$lpar}{$vcenter_name}{$file} && $hash_test{$lpar}{$vcenter_name}{$file} ne '' ) {

                # print "1725 $hash_test{$lpar}{$vcenter_name}{$file},,$lpar\n";
                my $rrd = $hash_test{$lpar}{$vcenter_name}{$file};
                if ( !-f $rrd ) {
                  print "D_L_CH         : file does not exist $rrd for $lpar\n";
                  next;
                }
                chomp $rrd;

                # my $rrd_split = $rrd;
                # my (undef,undef,undef,undef,undef,$vmware_path,undef,undef,$uuid_path) = split (/\//,$rrd_split);
                $i++;
                foreach my $type ( "d", "w", "m", "y" ) {
                  my $start_time = "now-1$type";
                  my $end_time   = "now-1$type+1$type";
                  my $ds_name1   = "vm_iops_read";
                  my $ds_name2   = "vm_iops_write";
                  my $answer     = "";
                  eval {
                    RRDp::cmd qq(graph "$name_out"
                      "--start" "$start_time"
                      "--end" "$end_time"
                      "DEF:iops_read_d=$rrd:$ds_name1:AVERAGE"
                      "DEF:iops_write_d=$rrd:$ds_name2:AVERAGE"
                      "CDEF:res_d=iops_read_d,iops_write_d,+"
                      "PRINT:res_d:AVERAGE: %3.0lf"
                      "PRINT:res_d:MAX: %3.0lf"
                    );
                    $answer = RRDp::read;
                  };
                  if ($@) {
                    error("ERROR reading file $rrd : $@");
                    next;
                  }
                  if ( $$answer =~ "ERROR" ) {
                    error("Rrdtool error : $$answer");
                    next;
                  }
                  my $aaa = $$answer;
                  $aaa =~ s/NaNQ|NaN|nan/0/g;
                  ( undef, my $utild, my $util_max ) = split( "\n", $aaa );
                  chomp $utild;
                  chomp $util_max;

                  if ( $type eq "d" ) {
                    $hash_test1{$lpar}{$vcenter_name}{day_l}{$i} = "$utild";
                    $hash_test1{$lpar}{$vcenter_name}{day_m}{$i} = "$util_max";
                  }
                  if ( $type eq "w" ) {
                    $hash_test1{$lpar}{$vcenter_name}{week_l}{$i} = "$utild";
                    $hash_test1{$lpar}{$vcenter_name}{week_m}{$i} = "$util_max";
                  }
                  if ( $type eq "m" ) {
                    $hash_test1{$lpar}{$vcenter_name}{month_l}{$i} = "$utild";
                    $hash_test1{$lpar}{$vcenter_name}{month_m}{$i} = "$util_max";
                  }
                  if ( $type eq "y" ) {
                    $hash_test1{$lpar}{$vcenter_name}{year_l}{$i} = "$utild";
                    $hash_test1{$lpar}{$vcenter_name}{year_m}{$i} = "$util_max";
                  }
                }
              }
            }
          }
        }

        #print Dumper \%hash_test1;

        my $save_line1 = "";
        foreach my $lpar ( keys %hash_test1 ) {
          foreach my $vcenter_name ( %{ $hash_test1{$lpar} } ) {
            if ( $vcenter_name =~ /HASH/ ) { next; }
            $save_line1 = "vm_iops,$vcenter_name,$lpar,$vcenter_name_hmc{$vcenter_name}";
            ( undef, my $vcenter_uuid, undef ) = split( "\/vmware_", $vcenter_name_path{$vcenter_name} );
            chomp $vcenter_uuid;

            # my $save_line = "$vcenter_alias,$vm_name,$vcenter_name";
            foreach my $period ( "day_l", "day_m", "week_l", "week_m", "month_l", "month_m", "year_l", "year_m" ) {
              my $sum_l = 0;
              my $sum_m = 0;
              foreach my $number ( %{ $hash_test1{$lpar}{$vcenter_name}{$period} } ) {
                if ( defined $hash_test1{$lpar}{$vcenter_name}{$period}{$number} && $hash_test1{$lpar}{$vcenter_name}{$period}{$number} ne '' ) {
                  $sum_l += $hash_test1{$lpar}{$vcenter_name}{$period}{$number};
                  $sum_m += $hash_test1{$lpar}{$vcenter_name}{$period}{$number};

                  #print "$lpar-$period-$hash_test1{$lpar}{$vcenter_name}{$period}{$number}\n";
                }
              }
              if ( $period =~ /day_l|week_l|month_l|year_l/ ) {

                #print "$period!!";
                $save_line1 = "$save_line1" . ",$sum_l";
              }
              if ( $period =~ /day_m|week_m|month_m|year_m/ ) {
                $save_line1 = "$save_line1" . ",$sum_m";
              }
            }
            push @lines_top_out, "$save_line1,$hash_vm{$lpar},vmware_$vcenter_uuid";
          }
        }
        print "topten file VM : IOPS finished " . localtime() . "\n";
      }

      # close RRD pipe
      RRDp::end;
      $rrd_started = 0;
      my @sorted_lines_top_out = sort @lines_top_out;
      my $outfile              = "$tmpdir/topten_vm.tmp";
      open( OFH, ">> $outfile" ) || error( "Cannot open $outfile: $!" . __FILE__ . ":" . __LINE__ ) && next;
      foreach my $line (@sorted_lines_top_out) {
        print OFH "$line\n";
      }
      close OFH;
      print "topten file VM : prepared " . localtime() . "\n";
      next;
    }

    #test for empty server directory - see 2nd line and end of next foreach
    my $emptydir = "empty";

    my $server_all_space = $server_all;

    #    $server_all_space = "\"".$server_all."\"" if $server_all =~ m/ /;
    opendir( DIR, "$server_all_space" ) || error( "can't opendir $server_all_space: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @hmc_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    foreach my $hmc_all (@hmc_dir_all) {
      $hmc_all  = "$wrkdir/$server/$hmc_all";
      $emptydir = $hmc_all;
      my $hmc = basename($hmc_all);

      # print "02 $hmc,$hmc_all\n";
      if ( !-d $hmc_all ) { print VYFILE "InFo_hmc,$server,non-existent,in $server_all \n"; next; }
      if ( !-f "$hmc_all/config.cfg" ) {
        print VYFILE "InFo_hmc,$server,non-existent,config.cfg in $server_all \n";
      }
      my $mon_sec       = 30 * 86400;
      my $hmc_all_space = "";
      if ( -f "$hmc_all/vmware.txt" ) { next; }
      if ( -f "$hmc_all/config.cfg" ) {

        #if ( ( $act_time_u - ( stat("$hmc_all/config.cfg") )[9] ) > $mon_sec ) { print VYFILE "InFo_hmc,$server,older 30 days,config.cfg in $server_all \n"; next; }
        if ( !-f "$hmc_all/pool.rrm" )                                       { print VYFILE "InFo_hmc,$server,older 30 days not exists,pool.rrm in $server_all \n"; next; }
        if ( ( $act_time_u - ( stat("$hmc_all/pool.rrm") )[9] ) > $mon_sec ) { print VYFILE "InFo_hmc,$server,older 30 days,pool.rrm in $server_all \n";            next; }
        my $hmc_all_time = ( stat("$hmc_all/config.cfg") )[9];
        my ( $mmin, $hhour, $dd, $mm, $yy ) = ( localtime($hmc_all_time) )[ 1, 2, 3, 4, 5 ];
        $yy = $yy + 1900;
        $mm = $mm + 1;
        if ( $mmin < 10 )  { $mmin  = "0" . $mmin }
        if ( $hhour < 10 ) { $hhour = "0" . $hhour }
        if ( $dd < 10 )    { $dd    = "0" . $dd }
        if ( $mm < 10 )    { $mm    = "0" . $mm }
        my $update_d = "$yy-$mm-$dd $hhour:$mmin";

        if ( ( $act_time_u - $hmc_all_time ) > 86400 ) {
          print VYFILE "InFo_cfg,$server,$hmc,non-actual,$update_d \n";
        }
        ;    #  next; ???

        $hmc_all_space = $hmc_all;

        #      $hmc_all_space = "\"".$hmc_all."\"" if $hmc_all =~ m/ /;
      }
      else {
        $hmc_all_space = $hmc_all;
      }
      my $lpar_mem_name = "";    #do not test lpar.mmm if lpar/mem.mmm is OK
      opendir( DIR, "$hmc_all_space" ) || error( "can't opendir $hmc_all_space: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpar_dir_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      foreach my $lpar_all (@lpar_dir_all) {
        $lpar_all = "$wrkdir/$server/$hmc/$lpar_all";

        #print VYFILE "InFo_lpar,$lpar_all,,print every file,,\n";
        # if ( -d "$lpar_all" && $lpar_all !~ /NMON/) left_curly        #  lpar directory
        if ( -d "$lpar_all" ) {    #  lpar directory
          my $lpar_all_space = $lpar_all;

          #          $lpar_all_space = "\"".$lpar_all."\"" if $lpar_all =~ m/ /;
          opendir( DIR, "$lpar_all" ) || error( "can't opendir $lpar_all: $! :" . __FILE__ . ":" . __LINE__ ) && next;
          my @lpar_agent_dir_all = grep /\.mmm/, readdir(DIR);
          closedir(DIR);
          foreach my $file_tst (@lpar_agent_dir_all) {
            my $lpar = basename($lpar_all);
            $file_tst = "$wrkdir/$server/$hmc/$lpar/$file_tst";
            my $file_name = basename($file_tst);
            if ( $file_name ne "mem.mmm" && $file_name ne "S0200ADDR.mmm" ) { next; }

            # do not know if next line should be here
            #if ($file_tst =~ /--unknown|no_hmc/) { next; }
            if ( $file_tst =~ /--AS400--|Solaris/ ) { next; }

            #print "line - 2231 - POWER - $lpar_all | file_tst-$file_tst\n";

            #print "testing        : $file_tst\n" ;
            my $file_tst_ttime = ( stat("$file_tst") )[9];
            my ( $mmin, $hhour, $dd, $mm, $yy ) = ( localtime($file_tst_ttime) )[ 1, 2, 3, 4, 5 ];
            $yy = $yy + 1900;
            $mm = $mm + 1;
            if ( $mmin < 10 )  { $mmin  = "0" . $mmin }
            if ( $hhour < 10 ) { $hhour = "0" . $hhour }
            if ( $dd < 10 )    { $dd    = "0" . $dd }
            if ( $mm < 10 )    { $mm    = "0" . $mm }
            my $update_d = "$yy-$mm-$dd $hhour:$mmin";

            # if ($hmc =~ /no_hmc/){$hmc="NA";}
            if ( ( $act_time_u - ($file_tst_ttime) ) > ( 86400 * 30 ) ) {
              my $file_name = basename($file_tst);
              print VYFILE "InFo_lpar,$server,$hmc,$lpar,agent older 30 days,$update_d\n";
              next;
            }

            if ( ( $act_time_u - ($file_tst_ttime) ) > (86400) ) {
              my $file_name = basename($file_tst);
              print VYFILE "$server,$hmc,$lpar,agent older 1 day,$update_d\n";
              next;
            }

            #print "2256 - to daily_lpar_check.txt - $server,$hmc,$lpar,agent_OK ,$update_d\n";
            print VYFILE "$server,$hmc,$lpar,agent_OK ,$update_d\n";
            $lpar_mem_name = $lpar if ( $lpar_all !~ /NMON/ );
            next;
          }
          next;
        }
        if ( !( ( $lpar_all =~ m/mmm$/ ) or ( $lpar_all =~ m/rrh$/ ) or ( $lpar_all =~ m/rrm$/ ) ) ) {

          # print "this is to omit, $lpar_all\n";
          next;
        }

        #print VYFILE "InFo_lpar,$lpar_all,,$lpar_mem_name,,\n";
        #do not test lpar.mmm if lpar/mem.mmm is OK
        if ( $lpar_all =~ m/mmm$/ && $lpar_mem_name ne "" ) {
          if ( -1 != index( $lpar_all, $lpar_mem_name ) ) {
            $lpar_mem_name = "";
            next;
          }
        }
        my $lpar            = basename($lpar_all);
        my $lpar_name_ttime = ( stat("$lpar_all") )[9];
        my ( $mmin, $hhour, $dd, $mm, $yy ) = ( localtime($lpar_name_ttime) )[ 1, 2, 3, 4, 5 ];
        $yy = $yy + 1900;
        $mm = $mm + 1;
        if ( $mmin < 10 )  { $mmin  = "0" . $mmin }
        if ( $hhour < 10 ) { $hhour = "0" . $hhour }
        if ( $dd < 10 )    { $dd    = "0" . $dd }
        if ( $mm < 10 )    { $mm    = "0" . $mm }
        my $update_d = "$yy-$mm-$dd $hhour:$mmin";

        if ( ( $act_time_u - ($lpar_name_ttime) ) > ( 30 * 86400 ) ) {
          print VYFILE "InFo_lpar,$server,$hmc,$lpar,older 30 days,$update_d\n";
          next;
        }
        my $lpar_all_name = $lpar_all;
        $lpar_all_name =~ s/\.rrm$//;
        $lpar_all_name =~ s/\.rrh$//;
        $lpar_all_name =~ s/\.mmm$//;

        #print "testing        : $server, $hmc, $lpar\n";
        my $lpar_name = $lpar;

        #print "X01,$lpar_name,\n";
        $lpar_name =~ s/\.rrm$//;
        $lpar_name =~ s/\.rrh$//;
        $lpar_name =~ s/\.mmm$//;

        #print "X02,$lpar_name,\n";

        # if both .rrh and .rrm, take the newer from them
        my $last_letter = substr( $lpar_all, length($lpar_all) - 1, 1 );
        if ( $last_letter eq "h" ) {
          if ( -f "$lpar_all_name.rrm" ) {    #print "found -h and -m\n";
            my $lpar_name_ttimem = ( stat("$lpar_all_name.rrm") )[9];
            if ( $lpar_name_ttimem > $lpar_name_ttime ) { next; }
          }
        }
        if ( $last_letter eq "m" ) {
          if ( -f "$lpar_all_name.rrh" ) {    #print "found -m and -h\n";
            my $lpar_name_ttimem = ( stat("$lpar_all_name.rrh") )[9];
            if ( $lpar_name_ttimem > $lpar_name_ttime ) { next; }
          }
        }
        my $lpar_pool_alias = $lpar;
        if ( $lpar_name =~ m/^pool$/ ) {      # test for actual time
          $lpar_pool_alias =~ s/pool/AllCPUPools/g;
          if ( ( $act_time_u - ($lpar_name_ttime) ) > 86400 ) {
            print VYFILE "$server,$hmc,$lpar_pool_alias,non_actual,$update_d,poool\n";
            next;
          }
          print VYFILE "$server,$hmc,$lpar_pool_alias,OK,$update_d,poool\n";

          # print "001 pool : $lpar_name,$lpar_all,$lpar,$lpar_pool_alias,$server,$hmc,$hmc_all,$update_d\n";
          next;
        }
        if ( $lpar      =~ m/^SharedPool0\.rrm/ ) { next; }    #print "    always leave out\n";
        if ( $lpar_name =~ m/^SharedPool/ ) {                  # test for actual time

          # change  Shared CPU pool alias  (if exists and it is not a default CPUpool)
          my $pool_id = $lpar;
          $pool_id =~ s/SharedPool//g;
          $pool_id =~ s/\.[^\.]*$//;
          if ( -f "$hmc_all/cpu-pools-mapping.txt" ) {
            my $c_p_mapping_time = ( stat("$hmc_all/cpu-pools-mapping.txt") )[9];
            if ( ( $act_time_u - ($c_p_mapping_time) ) > ( 30 * 86400 ) ) {
              print VYFILE "InFo_map,$server,$hmc,cpu-pools-mapping.txt,older 30 days\n";
              next;
            }
            if ( ( $act_time_u - ($c_p_mapping_time) ) > 86400 ) {
              print VYFILE "InFo_map,$server,$hmc,cpu-pools-mapping.txt,older 24 hours\n";
            }
            open( FR, "<$hmc_all/cpu-pools-mapping.txt" );
            foreach my $linep (<FR>) {
              chomp($linep);
              ( my $id, my $pool_name ) = split( /,/, $linep );
              if ( $id == $pool_id ) {
                $lpar_pool_alias = "$pool_name";
                last;
              }
            }
            close(FR);
            if ( $lpar_pool_alias eq $lpar ) {    #SharedPool not in mapping? then leave out
              next;
            }
          }
          if ( ( $act_time_u - ($lpar_name_ttime) ) > 86400 ) {
            print VYFILE "$server,$hmc,$lpar_pool_alias,non_actual,$update_d,poool\n";
            next;
          }
          print VYFILE "$server,$hmc,$lpar_pool_alias,OK,$update_d,poool\n";

          #print "001 SharedPool : $lpar_name,$lpar_all,$lpar_pool_alias,$server,$hmc,$hmc_all,$update_d\n";
          next;
        }
        if ( $lpar_all =~ /\.mmm$/ ) {    # test for actual time
          if ( $server =~ /Solaris/ ) { next; }
          if ( ( $act_time_u - ($lpar_name_ttime) ) > 86400 ) {
            print VYFILE "$server,$hmc,$lpar,non_actual,$update_d\n";
            next;
          }
          print VYFILE "$server,$hmc,$lpar,OK,$update_d\n";

          #print "001 mmm : $lpar_name,$lpar_all,$lpar,$server,$hmc,$hmc_all,$update_d\n";
          next;
        }
        if ( $lpar_name =~ m/^mem-pool$/ || $lpar_name =~ m/^mem$/ || $lpar_name =~ m/^cod$/ ) {

          # print "excluded $lpar_name\n";
          next;    #exclude non lpars
        }

        # test activity in config.cfg and actual time
        my $lpar_state = lpar_state_in_configcfg("$hmc_all/cpu.cfg-$lpar_name");

        #print "009 LPAR_state $lpar_name is,$lpar_state,\n";
        if ( $lpar_state eq "not_found" ) {
          print VYFILE "InFo_lpar,$server,not found,in cpu.cfg-$lpar_name $lpar_all \n";
          next;
        }
        if ( $lpar_state =~ m/[Nn]ot [Aa]ctivated/ ) { next; }                             # always leave out
        if ( !( ( $lpar_state =~ /[Rr]unning/ ) or ( $lpar_state =~ /[Ss]tarted/ ) ) ) {
          print VYFILE "$server,$hmc,$lpar,UNKNOWN_state,$update_d,$lpar_state\n";
          next;
        }
        if ( ( $act_time_u - ($lpar_name_ttime) ) > 86400 ) {
          print VYFILE "$server,$hmc,$lpar,non_actual,$update_d\n";
          next;
        }
        print VYFILE "$server,$hmc,$lpar,OK,$update_d\n";

        # print "001 lpar : $lpar_name,$lpar_all,$lpar,$server,$hmc,$hmc_all,$update_d\n";
        next;
      }
    }
    if ( $emptydir eq "empty" ) { print VYFILE "InFo_hmc,$server,non-existent,in $server_all \n"; }
  }
}

#</PRE><B>LPAR config:</B><PRE>
#name                                   aix4 test /%#;        pay att to "/"
#lpar_id                                5
#lpar_env                               aixlinux
#primary_state                          Started

sub lpar_state_in_configcfg {
  my $filename = shift;
  my ( $line, $lpar_env, $lpar_state );

  # if there is a "/" in lpar name, make subst
  #$filename =~ s/&&1/\//g; # not here
  chomp($filename);

  # print "2070 ;$filename;\n";
  my @lines;
  if ( -f $filename ) {
    open( FH, "<$filename" ) || error( "Cannot read $filename: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @lines = <FH>;
    close(FH);
  }
  my $lpar_name  = "";
  my $lpar_found = 0;
  my $rmc_state  = "";
  my $number_bad = 0;
  while ( my $line = shift @lines ) {

    # looking for lpar
    if ( $line =~ m/">state</ ) {
      $line =~ s/.*>state<//;
      $line =~ s/^.*&nbsp;&nbsp;//;
      $line =~ s/.*font size//;
      $line =~ s/<\/font>.*//;
      $line =~ s/.*>//;
      $lpar_state = $line;
      chomp($lpar_state);
      $lpar_found = 1;
      last;
    }
  }
  if ( $lpar_found == 0 ) { $lpar_state = "not_found" }

  #  print "ret lpar_state_in_configcfg,$lpar_state\n";
  return ($lpar_state);
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

#
### hard link check
#
#  algorithm:
#  cycle on workdir/servers - take only directories
#   |   cycle on workdir/servers/hmcs - take only directories which contain cpu-pools-mapping.txt ie. POWER server
#   |  - no dir for this server? error -> log -> next
#   |  - one dir  - nothing to test  -> log -> next
#   |  - cycle on two or more dirs -> first is hmc1, others hmcX
#   |    2014-06-17 necessary to test every hmc against all others
#   |   |   cycle on workdir/servers/hmc1/*.mmm - means 'lpar'.mmm = file ????
#   |   |   |  - test-hlink( hmcX/, file)
#   |   |   cycle on workdir/servers/hmc1/*/
#   |   |   |  -  if exists workdir/servers/hmc1/lpar/   -> check if  ..hmcX/lpar/  or create
#   |   |   |  -  cycle on workdir/servers/hmc1/*/*.mmm or *.cfg = file and other extensions
#   |   |   |  | -  test-hlink( hmcX/lpar/, file)
#   |   |   |  - if any dir exists (ASP,JOB for AS400 or wlm- or wpar
#   |   |   |  |  -  cycle on workdir/servers/hmc1/*/any dir/*.mmc or *.cfg = file and other extensions
#   |   |   |  |  |  - test-hlink( hmcX/lpar/JOB, file)
#   |   |   |  |  |  - if any dir exists (any dir eg JOB for wpar
#   #   |   |  |  |  | - cycle on workdir/servers/hmc1/*/any dir/*.mmc or *.cfg = file and other extensions
#   |   |   |  |  |  | | - test-hlink( hmcX/lpar/JOB, file)
#   --------------

# sub test-hlink (dirX, file)
#-	dirX/file exists?
#     o	no -  [A] make HL dir1/file -> dirX/file -> log ->  (if links>2 ? -> log ) -> return
#     o	yes -  same inode?
#             	yes  -> ( if links>2 ? -> log ) -> return
#                     no  -> move force = back-up existing dirX/file to dirX/file.bphl  -> log -> [A]
#---------------------------

#  ***     main    ***
sub hlink_check {
  my $logfile = "$basedir/logs/thl.out";
  open( THL, ">> $logfile" ) || errorh( "Cannot open for writing $logfile: $! " . __FILE__ . ":" . __LINE__ ) && return 0;

  #write_log("testing hlink : started");
  print "testing hlink  : starting at " . localtime( time() ) . "\n";

  foreach my $server_ful (<$wrkdir/*>) {
    print "01 take item from server dir: $server_ful\n" if $DEBUG > 2;
    next                                                if !defined $server_ful;    # sometimes happens ?
    if ( -l $server_ful )  { next; }
    if ( !-d $server_ful ) { next; }

    opendir( my $dh, $server_ful )
      || errorh( "Cannot open dir for reading $server_ful: $! " . __FILE__ . ":" . __LINE__ ) && next;

    my @dirs = grep { -d "$server_ful/$_" && !/^\.{1,2}$/ } readdir($dh);
    closedir($dh);
    print "02 hmcs : @dirs\n" if $DEBUG > 2;

    my $hmcount = @dirs;
    if ( $hmcount < 2 ) {
      print "one hmc:@dirs for server: $server_ful 'Bye'\n" if $DEBUG > 2;
      next;
    }

    # find out if at least one hmc from @dirs contains file cpu-pools-mapping.txt, then it is POWER and should be hlinked
    my $is_power_hmc = 0;
    foreach my $hmcdir (@dirs) {
      print "2253 \$server_ful $server_ful \$hmcdir $hmcdir\n" if $DEBUG > 2;
      if ( -f "$server_ful/$hmcdir/cpu-pools-mapping.txt" || -f "$server_ful/$hmcdir/last-pool.txt" ) {
        $is_power_hmc++;
      }
    }
    next if !$is_power_hmc;

    #if ($hmcount > 2) {
    #   print "only 2 hmcs not!$hmcount! possible\n" if $DEBUG>2 ;
    #   errorh("only 2 hmcs not!$hmcount! possible: @dirs ".__FILE__.":".__LINE__) ;
    #       next;
    #}
    foreach my $hmc1 (@dirs) {
      foreach my $hmc2 (@dirs) {
        if ( $hmc1 eq $hmc2 ) {next}

        print " check server  : hlink $server_ful and hmc: $hmc2\n";

        opendir( my $dhl, "$server_ful/$hmc1/" )
          || errorh( "Cannot open dir for reading $server_ful/$hmc1/: $! " . __FILE__ . ":" . __LINE__ ) && next;
        my @dirsl = grep { -d "$server_ful/$hmc1/$_" && !/^\.{1,2}$/ } readdir($dhl);
        closedir($dhl);

        print "04 lpars : @dirsl\n" if $DEBUG > 2;
        foreach my $dirl (@dirsl) {
          my @dirl_part = split( /\//, $dirl );
          my $lpar_dir  = $dirl_part[-1];

          if ( !-d "$server_ful/$hmc2/$lpar_dir" ) {
            mkdir("$server_ful/$hmc2/$lpar_dir")
              || errorh( "Cannot mkdir $server_ful/$hmc2/$lpar_dir: $! " . __FILE__ . ":" . __LINE__ ) && next;
            write_log("dir lpar made: $server_ful/$hmc2/$lpar_dir");
          }

          hlink_files_in_dir( "$server_ful/$hmc1/$lpar_dir", "$server_ful/$hmc2/$lpar_dir" );

          # as400 has dirs ASP, DSK, IFC, JOB, even usual agent has JOB or can be wlm- or can be wpar dirs
          opendir( my $dhl, "$server_ful/$hmc1/$lpar_dir" )
            || errorh( "Cannot open dir for reading $server_ful/$hmc1/$lpar_dir: $! " . __FILE__ . ":" . __LINE__ ) && next;
          my @dirs2 = grep { -d "$server_ful/$hmc1/$lpar_dir/$_" && !/^\.{1,2}$/ } readdir($dhl);
          closedir($dhl);

          print "05 lpars : @dirs2\n" if $DEBUG > 2;

          foreach my $dir2 (@dirs2) {
            my @dir2_part = split( /\//, $dir2 );
            my $lpar_dir2 = $dir2_part[-1];

            if ( !-d "$server_ful/$hmc2/$lpar_dir/$lpar_dir2" ) {
              mkdir("$server_ful/$hmc2/$lpar_dir/$lpar_dir2")
                || errorh( "Cannot mkdir $server_ful/$hmc2/$lpar_dir/$lpar_dir2: $! " . __FILE__ . ":" . __LINE__ ) && next;
              write_log("dir as400 made: $server_ful/$hmc2/$lpar_dir/$lpar_dir2");
            }

            hlink_files_in_dir( "$server_ful/$hmc1/$lpar_dir/$lpar_dir2", "$server_ful/$hmc2/$lpar_dir/$lpar_dir2" );

            # can be dir JOB in wpar /home/lpar2rrd/lpar2rrd/data/Power770/hmc/aix71-770/testwpar/JOB
            opendir( my $dhl3, "$server_ful/$hmc1/$lpar_dir/$lpar_dir2" )
              || errorh( "Cannot open dir for reading $server_ful/$hmc1/$lpar_dir/$lpar_dir2: $! " . __FILE__ . ":" . __LINE__ ) && next;
            my @dirs3 = grep { -d "$server_ful/$hmc1/$lpar_dir/$lpar_dir2/$_" && !/^\.{1,2}$/ } readdir($dhl3);
            closedir($dhl3);

            print "06 lpars : @dirs3\n" if $DEBUG > 2;

            foreach my $dir3 (@dirs3) {
              my @dir3_part = split( /\//, $dir3 );
              my $lpar_dir3 = $dir3_part[-1];

              if ( !-d "$server_ful/$hmc2/$lpar_dir/$lpar_dir2/$lpar_dir3" ) {
                mkdir("$server_ful/$hmc2/$lpar_dir/$lpar_dir2/$lpar_dir3")
                  || errorh( "Cannot mkdir $server_ful/$hmc2/$lpar_dir/$lpar_dir2/$lpar_dir3: $! " . __FILE__ . ":" . __LINE__ ) && next;
                write_log("dir as400 made: $server_ful/$hmc2/$lpar_dir/$lpar_dir2/$lpar_dir3");
              }

              hlink_files_in_dir( "$server_ful/$hmc1/$lpar_dir/$lpar_dir2/$lpar_dir3", "$server_ful/$hmc2/$lpar_dir/$lpar_dir2/$lpar_dir3" );

            }
          }
        }
      }
    }
  }

  #write_log("testing hlink : finished");
  close(THL);
  print "testing hlink  : finished at " . localtime( time() ) . "\n";

  return (0);
}

sub hlink_files_in_dir {
  my $dir_from = shift;
  my $dir_to   = shift;

  opendir( my $dhl, "$dir_from" )
    || errorh( "Cannot open dir for reading $dir_from/: $! " . __FILE__ . ":" . __LINE__ ) && return;
  my @hl_files = grep { /\.mmm$/ || /\.cfg$/ || /\.txt$/ || /\.col$/ || /\.csv$/ || /\.mmc$/ } readdir($dhl);

  # print "2379 \@hl_files @hl_files\n";
  closedir($dhl);

  # return; # just create folders
  foreach my $file_tst (@hl_files) {
    print "07 take item : $file_tst\n" if $DEBUG > 2;
    test_hlink( "$dir_to", "$dir_from/$file_tst" );
  }
}

sub test_hlink {
  my $hmc2     = shift;
  my $file_ful = shift;

  # print "2362 test hlink \$hmc2 $hmc2 \$file_ful $file_ful\n";

  my @file_ful_part = split( /\//, $file_ful );
  my $file_name     = $file_ful_part[-1];

  my $hlink;
  my ( $inode_1, $inode_2 );

  if ( !-f "$hmc2/$file_name" ) {
    if ( link( $file_ful, "$hmc2/$file_name" ) ) {
      write_log("hlink created for:$file_ful to:$hmc2/$file_name");

      # test number of links
      #     $hlink = (stat("$hmc2/$file_name"))[3];
      #    if ( $hlink != 2 ) {
      #       write_log("hlink num: $hlink for: $hmc2/$file_name");
      #    }
      return 1;
    }
    else {
      errorh( "Cannot hlink create for:$file_ful to:$hmc2/$file_name : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
    }
  }
  $inode_1 = ( stat("$file_ful") )[1];
  ( $inode_2, $hlink ) = ( stat("$hmc2/$file_name") )[ 1, 3 ];
  if ( $inode_1 == $inode_2 ) {

    #    if ( $hlink != 2 ) {
    #       write_log("hlink num: $hlink for: $hmc2/$file_name");
    #    }
    return 1;
  }
  if ( !move( "$hmc2/$file_name", "$hmc2/$file_name.bphl" ) ) {
    errorh( "Cannot back up: $hmc2/$file_name : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  write_log("backed up $hmc2/$file_name");
  if ( link( $file_ful, "$hmc2/$file_name" ) ) {
    write_log("hlink created for:$file_ful to:$hmc2/$file_name");

    # test number of links
    #     $hlink = (stat("$hmc2/$file_name"))[3];
    #     if ( $hlink != 2 ) {
    #        write_log("hlink num: $hlink for: $hmc2/$file_name");
    #     }
    return 1;
  }
  else {
    errorh( "Cannot hlink create for:$file_ful to:$hmc2/$file_name : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  }
}

sub human_vmware_name {
  my $lpar  = shift;
  my $arrow = shift;
  $arrow = "" if !defined $arrow;

  # my $trans_file = "$wrkdir/$server/$host/lpar_trans.txt"; # old solution on servers
  my $trans_file = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
  if ( -f "$trans_file" ) {
    my $name      = "";
    my $file_time = 0;

    # there can be more UUID for same Vm name when param is 'neg', choose latest one
    open( FR, "< $trans_file" );
    foreach my $linep (<FR>) {
      chomp($linep);
      ( my $id, my $name_tmp, undef ) = split( /,/, $linep );
      if ( "$arrow" eq "neg" ) {
        ( $name_tmp, $id, undef ) = split( /,/, $linep );
        if ( "$id" eq "$lpar" ) {
          next if !-f "$wrkdir/vmware_VMs/$name_tmp.rrm";
          my $act_file_time = ( stat("$wrkdir/vmware_VMs/$name_tmp.rrm") )[9];
          if ( $act_file_time > $file_time ) {
            $file_time = $act_file_time;
            $name      = $name_tmp;

            # print STDERR "11630 \$name $name \$file_time $file_time\n";
          }
        }
      }
      else {
        if ( "$id" eq "$lpar" ) {
          $name = $name_tmp;
          last;
        }
      }
    }
    close(FR);
    $lpar = "$name" if $name ne "";
  }
  return "$lpar";    #human name - if found, or original
}

sub write_log {
  my $text     = shift;
  my $act_time = localtime();
  print THL "$act_time: $text\n";
}

# error handling
sub errorh {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print STDERR "$act_time: $text : $!\n";
  print THL "$act_time: $text : $!\n";
  return 1;
}

sub vmware_vm_erase {

  # read from tmp/menu_vmware.txt just VM lines
  # L:cluster_New Cluster:10.22.11.14:500f3775-9b2d-f0e3-8f36-6799f3e70d79:Mint Linux GUI:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.14&lpar=500f3775-9b2d-f0e3-8f36-6799f3e70d79&item=lpar&entitle=0&gui=1&none=none::Hosting:V
  # L:cluster_Garage_Cluster:192.168.1.8:5028f34d-b2a5-1300-b874-51e3b23e855b:lnim:/lpar2rrd-cgi/detail.sh?host=pavel.lpar2rrd.com===double-col===443&server=192.168.1.8&lpar=5028f34d-b2a5-1300-b874-51e3b23e855b&item=lpar&entitle=0&gui=1&none=none::garage:V:M

  if ( $ENV{DEMO} ) {

    # do not test
    return;
  }

  my %vm_from_menu = ();
  open( my $info, "<$tmpdir/menu_vmware.txt" ) || print "vmware_vm_erase : not detected $tmpdir/menu_vmware.txt\n" && return 0;
  while ( my $line = <$info> ) {
    next if $line !~ /^L:/;

    # print "$line";
    ( undef, undef, undef, my $uuid, my $name, undef ) = split( ":", $line );

    # print "$uuid $name\n";
    $vm_from_menu{$uuid} = $name;
  }
  close $info;
  if ( !%vm_from_menu ) { print "vmware erase   : no VM's files found - exit\n" && return 0; }

  print "vmware erase   : VM starting " . localtime(time) . " : going to erase VM files older than $vm_days_to_erase days\n";

  my $vm_uuid_name = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
  my %vm_list      = ();
  if ( !-f $vm_uuid_name ) { print "vmware erase   : file $vm_uuid_name not found - exit\n" && return 0; }

  open( $info, "< $vm_uuid_name" ) || print "vmware erase   : cannot open $vm_uuid_name - exit\n" && return 0;
  while ( my $line = <$info> ) {
    chomp $line;
    ( my $uuid, my $rest ) = split( ",", $line, 2 );

    # print "$uuid $rest\n";
    $vm_list{$uuid} = $rest;
  }
  close($info);
  unlink "$tmpdir/vm_uuid_name.txt";
  copy $vm_uuid_name, "$tmpdir/vm_uuid_name.txt";

  my $vm_dir = "$wrkdir/vmware_VMs";
  opendir( DIR, "$vm_dir" ) || error( " directory does not exists : $vm_dir " . __FILE__ . ":" . __LINE__ ) && return 1;
  my @all_rrm_files = grep {/\.rrm$/} readdir(DIR);
  closedir(DIR);

  my $actual_unix_time = time;
  my $tested_time      = $actual_unix_time - ( $vm_days_to_erase * 86400 );

  my %erased_vm_list = ();
  my @report         = ();

  my $datum = localtime(time);
  push @report, "vmware erase   : start $datum\n";

  my $erased_file_count = 0;

  foreach (@all_rrm_files) {
    my $filename = $_;

    # print "testing $filename\n";
    my $f_name = $filename;
    $f_name =~ s/\.rrm$//;
    next if exists $vm_from_menu{$f_name};                 # living VM
    my $full_filename = "$vm_dir/$filename";
    next if ( stat($full_filename) )[9] > $tested_time;    # not old VM
    next if $f_name !~ m{.{8}-.{4}-.{4}-.{4}-.{12}};       # not uuid > do not erase

    # print "erase $filename ".localtime((stat($full_filename))[9])."\n";
    my $erased_vm = "- not detected in vm_uuid_name.txt";
    if ( exists $vm_list{$f_name} ) {
      $erased_vm_list{$f_name} = $vm_list{$f_name};
      $erased_vm = $vm_list{$f_name};
      delete $vm_list{$f_name};
    }
    print "vmware erase   : $full_filename $erased_vm\n";
    push @report, "vmware erase   : $full_filename $erased_vm\n";
    unlink $full_filename || push @report, "vmware_vm_erase : cannot erase $full_filename\n";
    $full_filename =~ s/\.rrm$/\.last/;
    unlink $full_filename || push @report, "vmware_vm_erase : cannot erase $full_filename\n";
    $erased_file_count++;
  }

  # write new vm_uuid_name.txt file
  my $vm_uuid_name_temp = "$wrkdir/vmware_VMs/vm_uuid_name.tmp";
  if ( open( my $info, ">$vm_uuid_name_temp" ) ) {
    keys %vm_list;    # reset the internal iterator so a prior each() doesn't affect the loop
    while ( my ( $k, $v ) = each %vm_list ) {
      print $info "$k,$v\n";
    }
  }
  else {
    print "vmware erase   : cannot write to $vm_uuid_name_temp\n" && return;
  }
  if ( unlink $vm_uuid_name ) {
    move $vm_uuid_name_temp, $vm_uuid_name || print "vmware_vm_erase : cannot create $vm_uuid_name\n" && return;
  }
  else {
    print "vmware erase   : cannot delete $vm_uuid_name\n" && return;
  }

  # append erase report file
  $datum = localtime(time);
  push @report, "vmware erase   : finish $datum erased file count $erased_file_count\n";
  print "vmware erase   : VM finished $datum erased file count $erased_file_count\n";

  # do not fill the file just with the two everyday lines
  if ( scalar @report > 2 ) {
    my $vm_erased_log = "$basedir/logs/vm_erased.log-vmware";
    if ( open( my $info, ">>$vm_erased_log" ) ) {
      foreach (@report) {
        print $info $_;
      }
      close $info;
    }
    else {
      print "vmware erase   : cannot append $vm_erased_log\n";
    }
  }

}

sub vmware_datastore_erase {

  # my $wrkdir              = "$basedir/data"; # is global
  # my $vm_days_to_erase = 90; # is global
  my $act_time = time();

  if ( $ENV{DEMO} ) {

    # do not test
    return;
  }

  my @report = ();
  my $datum  = localtime(time);
  push @report, "vmware erase   : datastore start $datum\n";
  print "vmware erase   : datastore start $datum: erasing vmware datastores older $vm_days_to_erase days\n";

  my $erased_file_count = 0;

  opendir( DIR, "$wrkdir" ) || error( " directory does not exists : $wrkdir " . __FILE__ . ":" . __LINE__ ) && return;
  my @wrkdir_all = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);
  @wrkdir_all = sort @wrkdir_all;

  my $days370_in_sec        = 370 * 86400;
  my $year_in_sec           = 365 * 86400;
  my $time_for_erase_in_sec = $vm_days_to_erase * 86400;

  while ( my $server_all = shift(@wrkdir_all) ) {
    $server_all = "$wrkdir/$server_all";
    if ( !-d $server_all )               { next; }
    if ( -l $server_all )                { next; }
    if ( $server_all =~ /\/vmware_VMs/ ) { next; }
    my $server = basename($server_all);

    if ( $server =~ /^vmware_/ ) {

      #print "testing vcenter: $server\n";
      my $name_file = "$wrkdir/$server/vmware_alias_name";
      next if !-f $name_file;    # how it is possible?

      next if ( $act_time - ( stat("$name_file") )[9] ) > $days370_in_sec;    # do not test older vCenter

      # print "2558 go on with this vcenter $name_file\n";

      my $alias_name = "fake _alias_name";
      if ( open( FC, "< $name_file" ) ) {
        $alias_name = <FC>;
        close(FC);
        $alias_name =~ s/^[^\|]*\|//;
        chomp $alias_name;
      }
      else {
        error( "Cannot read $name_file: $!" . __FILE__ . ":" . __LINE__ );
      }

      my $hmc_dir = "$wrkdir/$server";
      opendir( DIR, "$hmc_dir" ) || error( " directory does not exists : $hmc_dir " . __FILE__ . ":" . __LINE__ ) && next;
      my @all_datacenters = grep /datastore_*/, readdir(DIR);
      closedir(DIR);

      # print "2571 \@all_datacenters @all_datacenters\n";

      foreach (@all_datacenters) {
        my $datacenter_dir = "$hmc_dir/$_";
        my $hmc            = $_;

        # find datacenter name in 'datastore_<name>.dcname'
        opendir( DIR, "$datacenter_dir" ) || error( " cannot open directory : $datacenter_dir " . __FILE__ . ":" . __LINE__ ) && next;
        my @all_datacenter_dir = readdir(DIR);
        closedir(DIR);

        # print "2758 \@all_datacenter_dir @all_datacenter_dir\n";
        my @all_datacenter_names = grep /datastore_.*\.dcname/, @all_datacenter_dir;    # should be only one, take the 1st
                                                                                        # print "2760 \@all_datacenter_names @all_datacenter_names\n";
        my @all_datastores       = grep /.*\.rrs$/,             @all_datacenter_dir;

        # print "2764 \@all_datastores @all_datastores\n";
        # next; # when debug

        if ( !defined $all_datacenter_names[0] || $all_datacenter_names[0] eq "" ) {
          print "testing update : datacenter name file does not exist !!! for datacenter dir: $datacenter_dir: skipping it\n";

          # print "unlink vcenter: datacenter: $datacenter_dir\n";
          push @report, "exception: vcenter:$alias_name datacenter: $datacenter_dir - no name file \n";
          next;
        }

        print "testing update : datacenter file $datacenter_dir/$all_datacenter_names[0]\n";

        # next if ( $act_time - ( stat("$datacenter_dir/$all_datacenter_names[0]"))[9]) < $time_for_erase_in_sec; # newer datacenter is OK
        # no, even new datacenter can have old (not used) datastores

        my $datacenter_name = $all_datacenter_names[0];
        $datacenter_name =~ s/\.dcname$//;

        # datacenter has datastores
        # print "2592 \@all_datastores @all_datastores\n";
        # these are UUID names like 52b85c8c359cb741-02f40223f72d51a7.rrs 57e66ae1-aeb8f118-207e-18a90577a87c.rrs

        foreach (@all_datastores) {

          # print "2785 testing datastore $_\n";
          my $ds_uuid_name = $_;
          my $ds_uuid      = $ds_uuid_name;
          $ds_uuid =~ s/\.rrs$//;

          # find the name in filename 'name.uuid'
          my @all_ds_names = grep /.*\.$ds_uuid/, @all_datacenter_dir;    # should be only one, take the 1st
          if ( !defined $all_ds_names[0] || $all_ds_names[0] eq "" ) {
            print "testing update : datastore name file does not exist !!! for uuid: $ds_uuid going to remove it\n";

            # print "unlink vcenter:$alias_name datastore: $datacenter_dir/$ds_uuid\n";
            push @report, "exception: vcenter:$alias_name datastore: $datacenter_dir/$ds_uuid \n";
            next;
          }

          # active datastore can have old .rrv files from VMs which are not active, remove these files if one year old
          if ( -d "$datacenter_dir/$ds_uuid" ) {

            # print "2801 found datastore dir $datacenter_dir/$ds_uuid\n";
            opendir( DIR, "$datacenter_dir/$ds_uuid" ) || error( " cannot open directory : $datacenter_dir/$ds_uuid " . __FILE__ . ":" . __LINE__ ) && next;
            my @all_rrv_files = grep /.*\.rrv$/, readdir(DIR);
            closedir(DIR);
            my $removed_rrv_files_count = 0;
            foreach (@all_rrv_files) {

              # next if $removed_rrv_files_count > 0; # when debug - only one at a time
              # print  "testing update : datastore rrv file $datacenter_dir/$ds_uuid/$_\n";
              # next if ( $act_time - ( stat("$datacenter_dir/$ds_uuid/$_"))[9]) < $year_in_sec; # time_for_erase_in_sec
              next if ( $act_time - ( stat("$datacenter_dir/$ds_uuid/$_") )[9] ) < $time_for_erase_in_sec;    # only 3 months because VM names
                                                                                                              # print "testing update : datastore rrv file $datacenter_dir/$ds_uuid/$_ is older 3 months\n";
              my $file_to_delete = "$datacenter_dir/$ds_uuid/$_";
              if ( -f $file_to_delete ) {
                if ( unlink $file_to_delete ) {
                  push @report, "deleted : $file_to_delete\n";
                  $removed_rrv_files_count++;
                  $erased_file_count++;
                }
                else {
                  push @report, "error   : can not delete $file_to_delete\n";
                }
              }
            }
          }

          # next; # when debug
          # print  "testing update : datastore file $datacenter_dir/$all_ds_names[0]\n";
          next if ( $act_time - ( stat("$datacenter_dir/$ds_uuid.rrs") )[9] ) < $time_for_erase_in_sec;    # newer datastore is OK

          my $ds_name = $all_ds_names[0];
          $ds_name =~ s/\.$ds_uuid$//;

          # deleting datastore older than $vm_days_to_erase means to delete in datacenter_dir:
          # uuid.rrt,  uuid.rru,  uuid.last,  uuid.html,  and dir uuid/
          # for the purpose of YEAR graph in Datastore TOP -> Used Space do not delete  uuid.rrs and name.uuid
          # those two files are deleted when older one year

          if ( ( $act_time - ( stat("$datacenter_dir/$ds_uuid.rrs") )[9] ) < $year_in_sec ) {

            # remove all files except name.uuid and uuid.rrs

            # print "unlink vcenter:$alias_name datastore: $datacenter_dir/ $ds_name\n";
            # push @report,"        :vcenter:$alias_name datastore: $datacenter_dir/ $ds_name\n";
            my $deleted        = 0;
            my $file_to_delete = "$datacenter_dir/$ds_uuid" . ".rrt";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
                $deleted++;
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            $file_to_delete = "$datacenter_dir/$ds_uuid" . ".rru";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
                $deleted++;
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            $file_to_delete = "$datacenter_dir/$ds_uuid" . ".last";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
                $deleted++;
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            $file_to_delete = "$datacenter_dir/$ds_uuid" . ".html";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
                $deleted++;
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            if ($deleted) {
              $erased_file_count++;
              push @report, "        :vcenter:$alias_name datastore: $datacenter_dir/ $ds_name\n";
            }
          }
          else {
            # remove all files
            #print "unlink older 1 year vcenter:$alias_name datastore: $datacenter_dir/ $ds_name\n";
            push @report, ">1 year :vcenter:$alias_name datastore: $datacenter_dir/ $ds_name\n";
            my $file_to_delete = "$datacenter_dir/$ds_uuid" . ".rrt";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            $file_to_delete = "$datacenter_dir/$ds_uuid" . ".rru";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            $file_to_delete = "$datacenter_dir/$ds_uuid" . ".last";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            $file_to_delete = "$datacenter_dir/$ds_uuid" . ".html";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            my $dir_to_delete = "$datacenter_dir/$ds_uuid";
            if ( -d $dir_to_delete ) {
              if ( rmtree($dir_to_delete) ) {
                push @report, "deleted : dir $dir_to_delete\n";
              }
              else {
                push @report, "error   : can not delete dir $dir_to_delete\n";
              }
            }
            $file_to_delete = "$datacenter_dir/$ds_uuid" . ".rrs";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            $file_to_delete = "$datacenter_dir/$ds_name.$ds_uuid";
            if ( -f $file_to_delete ) {
              if ( unlink $file_to_delete ) {
                push @report, "deleted : $file_to_delete\n";
              }
              else {
                push @report, "error   : can not delete $file_to_delete\n";
              }
            }
            $erased_file_count++;
          }
        }
      }
    }
  }

  # append erase report
  $datum = localtime(time);
  push @report, "vmware erase   : datastore finish $datum erased file count $erased_file_count\n";
  print "vmware erase   : datastore finish $datum erased file count $erased_file_count\n";

  # do not fill the file just with the two everyday lines
  if ( scalar @report > 2 ) {
    my $erased_log = "$basedir/logs/vm_erased.log-vmware-datastore";
    if ( open( my $info, ">>$erased_log" ) ) {
      foreach (@report) {
        print $info $_;
      }
      close $info;
    }
    else {
      print "vmware erase   : cannot append $erased_log\n";
    }
  }
}
