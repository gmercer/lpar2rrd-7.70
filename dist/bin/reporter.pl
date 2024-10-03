
use strict;
use warnings;
use Time::Local;
use Data::Dumper;
use POSIX qw(mktime strftime);
use JSON qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64 decode_base64);
use Storable;
use XoruxEdition;

my $basedir      = $ENV{INPUTDIR};
my $wrkdir       = "$basedir/data";
my $tmpdir       = "$basedir/tmp";
my $bindir       = "$basedir/bin";
my $reportsdir   = "$basedir/reports";
my $reporter_cfg = "$basedir/etc/web_config/reporter.json";

my $message_body = ("Hello,\n\nyour report has been succesfully created!\n");
if ( -f "$basedir/etc/reporter_email_body.cfg" ) {
  local $/;
  open( my $MSG, "<$basedir/etc/reporter_email_body.cfg" ) || error( "Couldn't open file $basedir/etc/reporter_email_body.cfg $!" . __FILE__ . ":" . __LINE__ );
  $message_body = <$MSG>;
  close($MSG);
}

$ENV{'REQUEST_METHOD'} = "GET";
my $perl  = $ENV{'PERL'}           ||= "perl";
my $debug = $ENV{'DEBUG_REPORTER'} ||= 9;
umask 0000;

my $act_time2debug = localtime();
print "reporter START : $act_time2debug\n" if $debug == 9;

if ( !-f $reporter_cfg ) {
  print "reporter       : $reporter_cfg does not exists! Exiting...\n" if $debug == 9;
  exit 1;
}
if ( !-d $reportsdir ) {
  mkdir( "$reportsdir", 0777 ) || error( "Cannot mkdir $reportsdir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
}

my ( $user_name, $report_name, $startup_from ) = @ARGV;

#
# Configuration
#
print "load cfg       : $reporter_cfg\n" if $debug == 9;
open( CFG, "<$reporter_cfg" ) || error( "Couldn't open file $reporter_cfg $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
my %cfg = %{ decode_json( join( "", <CFG> ) ) };
close(CFG);

#
# Global variables
#
my $product    = "LPAR2RRD";
my $product_lc = "";
if ( defined $ENV{WLABEL} && $ENV{WLABEL} ne 'Dark' ) { $product = $ENV{WLABEL}; }
$product_lc = lc $product;

print "product        : $product\n" if $debug == 9;
my $uname_n = `uname -n`;
chomp $uname_n;
my $mail_from_default = "$product_lc-reporter\@$uname_n.com";

#
# find all lpars
#
my %power_inventory;
get_power_inventory();

#
# find all VMs
#
my %vmware_inventory;
get_vmware_inventory();

#
# load oVirt structure
#
my %ovirt_inventory;
get_ovirt_inventory();

#
# load Solaris structure
#
my %solaris_inventory;
get_solaris_inventory();

#
# load Hyper-V structure
#
my %hyperv_inventory;
get_hyperv_inventory();

#
# load Topten
#
my $topten_timerange = "";
my $topten_bookmarks = 0;
my $topten_loaded    = 0;
my %topten_inventory;

#get_topten_inventory();

#
# Progress bar variables
#
my %status;
my $pid     = $$;    # this process ID
my $done    = 0;
my $count   = 0;
my $API_RUN = 0;

#
# ACL: find all users, also from xormon
#
my %users;
my %users_xormon;
if ( -f "$basedir/etc/web_config/users.json" ) {
  %users = %{ Xorux_lib::read_json("$basedir/etc/web_config/users.json") };
}
if ( -f "$basedir/etc/web_config/users-xormon.json" ) {
  %users_xormon = %{ Xorux_lib::read_json("$basedir/etc/web_config/users-xormon.json") };
}

#
# alias.cfg
#
my %aliases;

#my $alias_cfg_file = "$basedir/etc/alias.cfg";
#my @alias_cfg;
#if ( -f $alias_cfg_file ) {
#  open( CFG, "<$alias_cfg_file" ) || error( "Couldn't open file $alias_cfg_file $!" . __FILE__ . ":" . __LINE__ ) && exit;
#  my @alias_cfg = <CFG>;
#  close(CFG);
#
#  foreach my $alias_line (@alias_cfg) {
#    chomp $alias_line;
#    if ( $alias_line =~ m/^#/ ) { next; }
#    if ( $alias_line =~ m/^$/ ) { next; }
#
#    my ($al_type, $al_host, $al_id, $alias) = split(/:/, $alias_line);
#    if ( defined $al_type && $al_type ne '' && defined $al_host && $al_host ne '' && defined $al_id && $al_id ne '' && defined $alias && $alias ne '' ) {
#      if ( $al_type eq "SANPORT" ) {
#        $al_id =~ s/^port//; # just to be sure, bcs there can be configured port id like "port1"
#      }
#      $aliases{$al_type}{$al_host}{$alias}{'ID'} = $al_id;
#    }
#  }
#}

#
# Reports
#
if ( defined $report_name && $report_name ne '' && defined $user_name && $user_name ne '' ) {
  print "user           : $user_name\n"   if $debug == 9;
  print "report name    : $report_name\n" if $debug == 9;

  # if the reporter is running from the GUI, there have to be the following var, because vars reporter_name and user_name are required also for manual startup by wrapper
  # status file (required for progress bar) is not created, when reporter is not running from the GUI
  if ( defined $startup_from && $startup_from eq "RUNFROMGUI" ) {
    $API_RUN = 1;    # reporter is executed from the GUI
  }

  #
  # Report main variables
  #
  my $format = "";
  my $sunix  = "";
  my $eunix  = "";
  my $sdate  = "";
  my $edate  = "";
  my $time   = "";

  # format IMG/PDF/CSV
  if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'format'} && ( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'format'} eq "IMG" || $cfg{'users'}{$user_name}{'reports'}{$report_name}{'format'} eq "PDF" || $cfg{'users'}{$user_name}{'reports'}{$report_name}{'format'} eq "CSV" ) ) {
    $format = $cfg{'users'}{$user_name}{'reports'}{$report_name}{'format'};
  }
  else {
    error("Report : $report_name : Unknown format of output file! Exiting... ") && exit 1;
  }

  # report time range
  if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'mode'} && $cfg{'users'}{$user_name}{'reports'}{$report_name}{'mode'} eq "timerange" ) {
    if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'sunix'} && isdigit( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'sunix'} ) && exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'eunix'} && isdigit( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'eunix'} ) ) {
      $sunix = $cfg{'users'}{$user_name}{'reports'}{$report_name}{'sunix'};
      $eunix = $cfg{'users'}{$user_name}{'reports'}{$report_name}{'eunix'};

      if ( defined $sunix && isdigit($sunix) && $sunix > 0 && defined $eunix && isdigit($eunix) && $eunix > 0 ) {
        my ( $sec_s, $min_s, $hour_s, $day_s, $month_s, $year_s, $wday_s, $yday_s, $isdst_s ) = localtime($sunix);
        $sdate = sprintf( "%02d:%02d:%02d %02d.%02d.%4d", $hour_s, $min_s, $sec_s, $day_s, $month_s + 1, $year_s + 1900 );

        my ( $sec_e, $min_e, $hour_e, $day_e, $month_e, $year_e, $wday_e, $yday_e, $isdst_e ) = localtime($eunix);
        $edate = sprintf( "%02d:%02d:%02d %02d.%02d.%4d", $hour_e, $min_e, $sec_e, $day_e, $month_e + 1, $year_e + 1900 );
      }
      else {
        error("Report : $report_name : Something is wrong with setting time range! sunix=\"$sunix\", eunix=\"$eunix\"! Exiting... ") && exit 1;
      }
      $time = "a";
    }
    else {
      error("Report : $report_name : Unknown time range! sunix=\"$cfg{'users'}{$user_name}{'reports'}{$report_name}{'sunix'}\", eunix=\"$cfg{'users'}{$user_name}{'reports'}{$report_name}{'eunix'}\"! Exiting... ") && exit 1;
    }
  }
  else {    # recurrence
    if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'} && $cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'} ne '' && exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'range'} && $cfg{'users'}{$user_name}{'reports'}{$report_name}{'range'} ne '' ) {
      ( $sunix, $eunix ) = set_report_time_range( "$cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'}", "$cfg{'users'}{$user_name}{'reports'}{$report_name}{'range'}" );

      if ( defined $sunix && isdigit($sunix) && $sunix > 0 && defined $eunix && isdigit($eunix) && $eunix > 0 ) {
        my ( $sec_s, $min_s, $hour_s, $day_s, $month_s, $year_s, $wday_s, $yday_s, $isdst_s ) = localtime($sunix);
        $sdate = sprintf( "%02d:%02d:%02d %02d.%02d.%4d", $hour_s, $min_s, $sec_s, $day_s, $month_s + 1, $year_s + 1900 );

        my ( $sec_e, $min_e, $hour_e, $day_e, $month_e, $year_e, $wday_e, $yday_e, $isdst_e ) = localtime($eunix);
        $edate = sprintf( "%02d:%02d:%02d %02d.%02d.%4d", $hour_e, $min_e, $sec_e, $day_e, $month_e + 1, $year_e + 1900 );
      }
      else {
        error("Report : $report_name : Something is wrong with setting time range! freq=\"$cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'}\",range=\"$cfg{'users'}{$user_name}{'reports'}{$report_name}{'range'}\"! Exiting... ") && exit 1;
      }

      if ( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'} eq "daily" ) {
        $time = "d";
      }
      elsif ( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'} eq "weekly" ) {
        $time = "w";
      }
      elsif ( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'} eq "monthly" ) {
        $time = "m";
      }
      elsif ( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'} eq "yearly" ) {
        $time = "y";
      }
      else {
        error("Report : $report_name : Unknown freq value! There should be daily/weekly/monthly/yearly! freq=\"$cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'}\"! Exiting... ") && exit 1;
      }
      print "time range     : $cfg{'users'}{$user_name}{'reports'}{$report_name}{'freq'} $cfg{'users'}{$user_name}{'reports'}{$report_name}{'range'}\n" if $debug == 9;
    }
  }

  print "format         : $format\n"        if $debug == 9;
  print "start time     : $sunix, $sdate\n" if $debug == 9;
  print "end time       : $eunix, $edate\n" if $debug == 9;

  #
  # Make report
  #
  if ( $format eq "IMG" && $product eq "LPAR2RRD" ) {
    make_img_report_lpar( "$report_name", "$user_name", "$sunix", "$eunix", "$time" );
  }
  if ( $format eq "PDF" && $product eq "LPAR2RRD" ) {
    make_pdf_report_lpar( "$report_name", "$user_name", "$sunix", "$eunix", "$sdate", "$edate", "$time" );
  }
  if ( $format eq "CSV" && $product eq "LPAR2RRD" ) {
    make_csv_report_lpar( "$report_name", "$user_name", "$sunix", "$eunix", "$sdate", "$edate", "$time" );
  }
}
else {
  # only first run after the midnight
  my $reporter_run = "$reportsdir/reporter-run";
  if ( !-f $reporter_run ) {
    `touch $reporter_run`;
  }
  else {
    my $run_time = ( stat("$reporter_run") )[9];
    ( my $sec, my $min, my $h, my $aday, my $m, my $y, my $wday, my $yday, my $isdst ) = localtime( time() );
    ( $sec, $min, $h, my $png_day, $m, $y, $wday, $yday, $isdst ) = localtime($run_time);
    if ( $aday == $png_day ) {
      print "reporter       : not this time $aday == $png_day\n";
      print "reporter END   : $act_time2debug\n" if $debug == 9;
      exit(0);
    }
    else {
      `touch $reporter_run`;
    }
  }

  if ( -f "$bindir/reporter-premium.pl" ) {
    require "$bindir/reporter-premium.pl";
    set_reports( $product, $debug, \%cfg );
  }
}

$act_time2debug = localtime();
print "reporter END   : $act_time2debug\n" if $debug == 9;

# progress bar end
%status = ( status => "done", count => $count, done => $done );
write_file( "/tmp/lrep-$pid.status", encode_json( \%status ) );

exit 0;

sub get_power_inventory {
  my $menu_txt = "$tmpdir/menu.txt";
  if ( -f $menu_txt ) {
    open( MENU, "<$menu_txt" ) || error( "Couldn't open file $menu_txt $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
    my @menu = <MENU>;
    chomp @menu;
    close(MENU);

    # find all deleted servers
    my %del_servers;
    foreach my $line ( grep {/^D:.*:.*:.*:.*:.*:.*:P/} @menu ) {
      my ( undef, $hmc, $server ) = split( /:/, $line );

      if ( defined $hmc && $hmc ne '' && defined $server && $server ne '' ) {
        $del_servers{$server}{$hmc} = $hmc;
      }
    }

    my @list_of_lpars = grep {/^L:.*:.*:.*:.*:.*:.*:P:.*$/} @menu;    # "P" -> only POWER section
                                                                      # L:hmc:P02DR__9117-MMC-SN44K8102:p770-demo:p770-demo:/lpar2rrd-cgi/detail.sh?host=hmc&server=P02DR__9117-MMC-SN44K8102&lpar=p770-demo&item=lpar&entitle=0&gui=1&none=none:::P:A
    foreach my $line (@list_of_lpars) {
      my ( undef, $hmc, $server, $lpar, undef, $url, undef, undef, undef, $lpar_type ) = split( /:/, $line );

      #if ( $hmc eq "no_hmc" ) { next; } # skip lpars from unmanaged linux systems
      # test if server is not deleted
      # D:hmc:p710 space test:CPUpool-pool:CPU pool:/lpar2rrd-cgi/detail.sh?host=hmc&server=p710%20space%20test&lpar=pool&item=pool&entitle=0&gui=1&none=none::1522309746:P
      #my $deleted_num = grep {/^D:$hmc:$server:.*:.*:.*:.*:P$/} @menu;
      #if ( $deleted_num && isdigit($deleted_num) && $deleted_num > 0 ) { next; }
      if ( exists $del_servers{$server} && exists $del_servers{$server}{$hmc} ) { next; }    # skip deleted server

      $hmc    = urldecodel("$hmc");
      $server = urldecodel("$server");
      $lpar   = urldecodel("$lpar");

      $hmc    =~ s/===double-col===/:/g;
      $server =~ s/===double-col===/:/g;
      $lpar   =~ s/===double-col===/:/g;
      $url    =~ s/===double-col===/:/g;
      $url    =~ s/^.+detail\.sh\?//;

      $power_inventory{LPARS}{$lpar}{MENU_TYPE} = $lpar_type;
      $power_inventory{LPARS}{$lpar}{SERVER}    = $server;
      $power_inventory{LPARS}{$lpar}{HMC}       = $hmc;
      $power_inventory{LPARS}{$lpar}{URL}       = $url;

      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{MENU_TYPE} = $lpar_type;
      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{HMC}       = $hmc;
      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{URL}       = $url;
    }

    # add also removed lpars
    my @list_of_lpars_removed = grep {/^RR:.*:.*:.*:.*:.*:.*:P:.*$/} @menu;    # "P" -> only POWER section
                                                                               # RR:hmc:Power710===double-col===testovani dlouheeeeeho:aix3%20-%20dlouhy%20nazev:aix3 - dlouhy nazev:/lpar2rrd-cgi/detail.sh?host=hmc&server=Power710===double-col===testovani%20dlouheeeeeho&lpar=aix3%20-%20dlouhy%20nazev&item=lpar&entitle=0&gui=1&none=none:::P:C
    foreach my $line (@list_of_lpars_removed) {
      my ( undef, $hmc, $server, $lpar, undef, $url, undef, undef, undef, $lpar_type ) = split( /:/, $line );

      #if ( $hmc eq "no_hmc" ) { next; } # skip lpars from unmanaged linux systems
      # test if server is not deleted
      # D:hmc:p710 space test:CPUpool-pool:CPU pool:/lpar2rrd-cgi/detail.sh?host=hmc&server=p710%20space%20test&lpar=pool&item=pool&entitle=0&gui=1&none=none::1522309746:P
      #my $deleted_num = grep {/^D:$hmc:$server:.*:.*:.*:.*:P$/} @menu;
      #if ( $deleted_num && isdigit($deleted_num) && $deleted_num > 0 ) { next; }
      if ( exists $del_servers{$server} && exists $del_servers{$server}{$hmc} ) { next; }    # skip deleted server

      $hmc    = urldecodel("$hmc");
      $server = urldecodel("$server");
      $lpar   = urldecodel("$lpar");

      $hmc    =~ s/===double-col===/:/g;
      $server =~ s/===double-col===/:/g;
      $lpar   =~ s/===double-col===/:/g;
      $url    =~ s/===double-col===/:/g;
      $url    =~ s/^.+detail\.sh\?//;

      $power_inventory{LPARS}{$lpar}{MENU_TYPE} = $lpar_type;
      $power_inventory{LPARS}{$lpar}{SERVER}    = $server;
      $power_inventory{LPARS}{$lpar}{HMC}       = $hmc;
      $power_inventory{LPARS}{$lpar}{URL}       = $url;
      $power_inventory{LPARS}{$lpar}{REMOVED}   = 1;

      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{MENU_TYPE} = $lpar_type;
      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{HMC}       = $hmc;
      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{URL}       = $url;
      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{REMOVED}   = 1;
    }
    @list_of_lpars_removed = grep {/^R:.*:.*:.*:.*:.*:.*:P:.*$/} @menu;    # "P" -> only POWER section
                                                                           # R:hmc:Power710===double-col===testovani dlouheeeeeho:aix3%20-%20dlouhy%20nazev:aix3 - dlouhy nazev:/lpar2rrd-cgi/detail.sh?host=hmc&server=Power710===double-col===testovani%20dlouheeeeeho&lpar=aix3%20-%20dlouhy%20nazev&item=lpar&entitle=0&gui=1&none=none:::P:C
    foreach my $line (@list_of_lpars_removed) {
      my ( undef, $hmc, $server, $lpar, undef, $url, undef, undef, undef, $lpar_type ) = split( /:/, $line );

      #if ( $hmc eq "no_hmc" ) { next; } # skip lpars from unmanaged linux systems
      # test if server is not deleted
      # D:hmc:p710 space test:CPUpool-pool:CPU pool:/lpar2rrd-cgi/detail.sh?host=hmc&server=p710%20space%20test&lpar=pool&item=pool&entitle=0&gui=1&none=none::1522309746:P
      #my $deleted_num = grep {/^D:$hmc:$server:.*:.*:.*:.*:P$/} @menu;
      #if ( $deleted_num && isdigit($deleted_num) && $deleted_num > 0 ) { next; }
      if ( exists $del_servers{$server} && exists $del_servers{$server}{$hmc} ) { next; }    # skip deleted server

      $hmc    = urldecodel("$hmc");
      $server = urldecodel("$server");
      $lpar   = urldecodel("$lpar");

      $hmc    =~ s/===double-col===/:/g;
      $server =~ s/===double-col===/:/g;
      $lpar   =~ s/===double-col===/:/g;
      $url    =~ s/===double-col===/:/g;
      $url    =~ s/^.+detail\.sh\?//;

      $power_inventory{LPARS}{$lpar}{MENU_TYPE} = $lpar_type;
      $power_inventory{LPARS}{$lpar}{SERVER}    = $server;
      $power_inventory{LPARS}{$lpar}{HMC}       = $hmc;
      $power_inventory{LPARS}{$lpar}{URL}       = $url;
      $power_inventory{LPARS}{$lpar}{REMOVED}   = 1;

      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{MENU_TYPE} = $lpar_type;
      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{HMC}       = $hmc;
      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{URL}       = $url;
      $power_inventory{SERVERS}{$server}{LPARS}{$lpar}{REMOVED}   = 1;
    }

    my @list_of_pools = grep {/^S:.*:.*:.*:.*:.*:.*:.*:P$/} @menu;    # "P" -> only POWER section
                                                                      # S:hmc:p710 space test:CPUpool-pool:CPU pool:/lpar2rrd-cgi/detail.sh?host=hmc&server=p710%20space%20test&lpar=pool&item=pool&entitle=0&gui=1&none=none::1543187114:P
                                                                      # S:hmc:p710 space test:CPUpool-SharedPool0:CPU pool 0 ===double-col=== DefaultPool:/lpar2rrd-cgi/detail.sh?host=hmc&server=p710%20space%20test&lpar=SharedPool0&item=shpool&entitle=0&gui=1&none=none:::P
    foreach my $line (@list_of_pools) {
      my ( undef, $hmc, $server, $pool_id, $pool_name, undef, undef, undef, undef ) = split( /:/, $line );

      if ( $pool_id !~ m/^CPUpool-/ ) { next; }

      $hmc       = urldecodel("$hmc");
      $server    = urldecodel("$server");
      $pool_id   = urldecodel("$pool_id");
      $pool_name = urldecodel("$pool_name");

      $hmc       =~ s/===double-col===/:/g;
      $server    =~ s/===double-col===/:/g;
      $pool_id   =~ s/===double-col===/:/g;
      $pool_id   =~ s/^CPUpool-//;
      $pool_name =~ s/===double-col===/:/g;

      if ( $pool_name =~ m/\s+:\s+/ ) { ( undef, $pool_name ) = split( /\s+:\s+/, $pool_name ); }

      # some change in menu.txt, CPU pool has been replaced by CPU
      # S:hmc:Power770:CPUpool-pool:CPU:/lpar2rrd-cgi/detail.sh?host=hmc&server=Power770&lpar=pool&item=pool&entitle=0&gui=1&none=none::1592381780:P
      if ( $pool_name eq "CPU" ) { $pool_name = "CPU pool"; }

      $power_inventory{SERVERS}{$server}{POOLS}{$pool_name}{POOL_ID} = $pool_id;
      $power_inventory{SERVERS}{$server}{POOLS}{$pool_name}{HMC}     = $hmc;
    }
  }

  return 1;
}

sub get_topten_inventory {
  if ( $topten_loaded == 1 ) { return 1; }    # inventory is already created, do not update it again

  my @lines_p;
  if ( -f "$tmpdir/topten.tmp" ) {
    open( TOP, "< $tmpdir/topten.tmp" ) || error( "Couldn't open file $tmpdir/topten.tmp $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @lines_p = <TOP>;
    close(TOP);
  }

  foreach (@lines_p) {
    chomp $_;
    my $metric = "";
    my $server = "";
    my $name   = "";
    my $stat_d = "";
    my $stat_w = "";
    my $stat_m = "";
    my $stat_y = "";

    ( $metric, $server, $name, undef, $stat_d, $stat_w, $stat_m, $stat_y ) = split( ",", $_ );

    if ( !defined $metric || !defined $server || !defined $name ) { next; }
    $name =~ s/\.r[a-z][a-z]$//;

    if ( isdigit($stat_d) ) { $topten_inventory{POWER}{$metric}{day}{$stat_d}{$server}{$name}   = $name; }
    if ( isdigit($stat_w) ) { $topten_inventory{POWER}{$metric}{week}{$stat_w}{$server}{$name}  = $name; }
    if ( isdigit($stat_m) ) { $topten_inventory{POWER}{$metric}{month}{$stat_m}{$server}{$name} = $name; }
    if ( isdigit($stat_y) ) { $topten_inventory{POWER}{$metric}{year}{$stat_y}{$server}{$name}  = $name; }
  }

  my @lines_v;
  if ( -f "$tmpdir/topten_vm.tmp" ) {
    open( TOP, "< $tmpdir/topten_vm.tmp" ) || error( "Couldn't open file $tmpdir/topten_vm.tmp $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    @lines_v = <TOP>;
    close(TOP);
  }

  foreach (@lines_v) {
    chomp $_;
    my $metric = "";
    my $server = "";
    my $name   = "";
    my $stat_d = "";
    my $stat_w = "";
    my $stat_m = "";
    my $stat_y = "";

    if ( $_ =~ m/^rep_iops/ ) {
      ( $metric, $server, $name, $stat_d, $stat_w, $stat_m, $stat_y ) = split( ",", $_ );
    }
    else {
      ( $metric, $server, $name, undef, $stat_d, $stat_w, $stat_m, $stat_y ) = split( ",", $_ );
    }

    if ( !defined $metric || !defined $server || !defined $name ) { next; }
    $name =~ s/\.r[a-z][a-z]$//;

    if ( isdigit($stat_d) ) { $topten_inventory{VMWARE}{$metric}{day}{$stat_d}{$server}{$name}   = $name; }
    if ( isdigit($stat_w) ) { $topten_inventory{VMWARE}{$metric}{week}{$stat_w}{$server}{$name}  = $name; }
    if ( isdigit($stat_m) ) { $topten_inventory{VMWARE}{$metric}{month}{$stat_m}{$server}{$name} = $name; }
    if ( isdigit($stat_y) ) { $topten_inventory{VMWARE}{$metric}{year}{$stat_y}{$server}{$name}  = $name; }
  }

  # do not load this inventory again in the same run of reporter
  $topten_loaded = 1;

  return 1;
}

sub get_solaris_inventory {
  my $menu_txt = "$tmpdir/menu.txt";
  if ( -f $menu_txt ) {
    open( MENU, "<$menu_txt" ) || error( "Couldn't open file $menu_txt $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
    my @menu = <MENU>;
    chomp @menu;
    close(MENU);

    # LDOMs
    my @list_of_ldoms = grep {/^L:no_hmc:.*:.*:.*:.*:.*:.*:S:L$/} @menu;

    # L:no_hmc:t8-1mvbc-l5:t8-1mvbc-l5:t8-1mvbc-l5:/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=t8-1mvbc-l5&item=sol-ldom&entitle=0&gui=1&none=none:::S:L
    foreach my $line (@list_of_ldoms) {
      my ( undef, undef, $ldom, undef, undef, $url, undef, $sol, undef, undef ) = split( /:/, $line );

      $ldom = urldecodel("$ldom");
      $sol  = urldecodel("$sol");
      $ldom =~ s/===double-col===/:/g;
      $sol  =~ s/===double-col===/:/g;
      $url  =~ s/===double-col===/:/g;
      $url  =~ s/^.+detail\.sh\?//;

      $solaris_inventory{LDOM}{$ldom}{NAME} = $ldom;
      $solaris_inventory{LDOM}{$ldom}{SOL}  = $sol;
      $solaris_inventory{LDOM}{$ldom}{URL}  = $url;
    }

    # Global zones
    my @list_of_gz = grep {/^L:no_hmc:.*:.*:.*:.*:.*:.*:S:G$/} @menu;

    # L:no_hmc:kvm-solaris:kvm-solaris:kvm-solaris:/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=kvm-solaris&item=sol-ldom&entitle=0&gui=1&none=none:::S:G
    foreach my $line (@list_of_gz) {
      my ( undef, undef, $gz, undef, undef, $url, undef, undef, undef, undef ) = split( /:/, $line );

      $gz = urldecodel("$gz");
      $gz  =~ s/===double-col===/:/g;
      $url =~ s/===double-col===/:/g;
      $url =~ s/^.+detail\.sh\?//;

      $solaris_inventory{GLOBAL_ZONE}{$gz}{NAME} = $gz;
      $solaris_inventory{GLOBAL_ZONE}{$gz}{URL}  = $url;
    }

    # Zones
    my @list_of_z = grep {/^L:no_hmc:.*:.*:.*:.*:.*:.*:S:Z$/} @menu;

    # L:no_hmc:kvm-solaris:test_z2:test_z2:/lpar2rrd-cgi/detail.sh?host=Solaris&server=kvm-solaris&lpar=test_z2&item=sol11-test_z2&entitle=0&gui=1&none=none:::S:Z
    foreach my $line (@list_of_z) {
      my ( undef, undef, $host, $zone, undef, $url, undef, $sol, undef, undef ) = split( /:/, $line );

      $host = urldecodel("$host");
      $zone = urldecodel("$zone");
      $sol  = urldecodel("$sol");
      $host =~ s/===double-col===/:/g;
      $zone =~ s/===double-col===/:/g;
      $sol  =~ s/===double-col===/:/g;
      $url  =~ s/===double-col===/:/g;
      $url  =~ s/^.+detail\.sh\?//;

      #$solaris_inventory{ZONE}{$zone}{NAME} = $zone;
      #$solaris_inventory{ZONE}{$zone}{HOST} = $host;
      #$solaris_inventory{ZONE}{$zone}{URL}  = $url;

      $solaris_inventory{HOST}{$host}{ZONE}{$zone}{NAME} = $zone;
      $solaris_inventory{HOST}{$host}{ZONE}{$zone}{SOL}  = $sol;
      $solaris_inventory{HOST}{$host}{ZONE}{$zone}{URL}  = $url;
    }
  }

  return 1;
}

sub get_hyperv_inventory {
  my $menu_txt = "$tmpdir/menu.txt";
  if ( -f $menu_txt ) {
    open( MENU, "<$menu_txt" ) || error( "Couldn't open file $menu_txt $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
    my @menu = <MENU>;
    chomp @menu;
    close(MENU);

    # VMs
    my @list_of_ldoms = grep {/^L:.*:.*:.*:.*:.*:.*:.*:H$/} @menu;

    # L:ad.int.xorux.com:HYPERV:8E3AB390-A112-4DCB-AAB4-CE51042A7A4A:WinXP:/lpar2rrd-cgi/detail.sh?host=HYPERV&server=windows/domain_ad.int.xorux.com&lpar=8E3AB390-A112-4DCB-AAB4-CE51042A7A4A&item=lpar&entitle=0&gui=1&none=none:::H
    foreach my $line (@list_of_ldoms) {
      my ( undef, $domain, $server, $vm_uid, $vm_name, $url, $cluster, undef, undef ) = split( /:/, $line );

      $domain  =~ s/===double-col===/:/g;
      $server  =~ s/===double-col===/:/g;
      $vm_uid  =~ s/===double-col===/:/g;
      $vm_name =~ s/===double-col===/:/g;
      $url     =~ s/===double-col===/:/g;
      $url     =~ s/^.+detail\.sh\?//;

      $hyperv_inventory{VM}{$vm_name}{NAME}   = $vm_name;
      $hyperv_inventory{VM}{$vm_name}{UID}    = $vm_uid;
      $hyperv_inventory{VM}{$vm_name}{DOMAIN} = $domain;
      $hyperv_inventory{VM}{$vm_name}{SERVER} = $server;
      $hyperv_inventory{VM}{$vm_name}{URL}    = $url;

      if ( defined $cluster && $cluster ne '' ) {
        $cluster =~ s/===double-col===/:/g;
        $hyperv_inventory{VM}{$vm_name}{CLUSTER} = $cluster;
      }
    }
  }

  return 1;
}

sub get_vmware_inventory {
  my $menu_txt = "$tmpdir/menu.txt";
  if ( -f $menu_txt ) {
    open( MENU, "<$menu_txt" ) || error( "Couldn't open file $menu_txt $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
    my @menu = <MENU>;
    chomp @menu;
    close(MENU);

    #
    # Vcenter
    #
    my @list_of_vcenters = grep {/^V:.*:Totals:.*:.*:.*:.*:.*:V/} @menu;

    # V:10.22.11.10:Totals:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=hmctotals&entitle=0&gui=1&none=none:::Hosting::V
    foreach my $line (@list_of_vcenters) {
      my ( undef, $vc_ip, undef, $url, undef, undef, $vcenter, undef ) = split( /:/, $line );

      $vc_ip   =~ s/===double-col===/:/g;
      $url     =~ s/===double-col===/:/g;
      $vcenter =~ s/===double-col===/:/g;

      $vmware_inventory{VCENTER}{$vcenter}{VCENTER_IP} = $vc_ip;
    }

    #
    # CLUSTER
    #
    my @list_of_cl = grep {/^A:.*:cluster_.*:Totals:.*:.*:.*:.*:V/} @menu;    # "V" -> only VMware section
                                                                              # A:10.22.11.10:cluster_New Cluster:Cluster totals:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=cluster&entitle=0&gui=1&none=none::Hosting::V
    foreach my $line (@list_of_cl) {
      my ( undef, undef, $cluster, undef, $detail_url, undef, $vcenter, undef ) = split( /:/, $line );

      $cluster    =~ s/^cluster_//;
      $cluster    =~ s/===double-col===/:/g;
      $vcenter    =~ s/===double-col===/:/g;
      $detail_url =~ s/===double-col===/:/g;

      # get url params
      $detail_url =~ s/^.+detail\.sh\?//;
      my @params = split( /&/, $detail_url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && defined $value ) {
            $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{URL_PARAM}{$param} = $value;
          }
        }
      }
    }

    #
    # VM
    #
    #my @list_of_vms = grep {/^L:.*:.*:.*:.*:.*:.*:.*:V$/} @menu; # "V" -> only VMware section
    my @list_of_vms = grep {/^L:.*:.*:.*:.*:.*:.*:.*:V/} @menu;    # "V" -> only VMware section
                                                                   # L:cluster_New Cluster:10.22.11.9:501c1a53-cf7d-07cb-88e4-cf94ca6c5b0e:vm-karel:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=501c1a53-cf7d-07cb-88e4-cf94ca6c5b0e&item=lpar&entitle=0&gui=1&none=none::Hosting:V
    foreach my $line (@list_of_vms) {
      my ( undef, $cluster, $server, $vm_uuid, $vm_name, $detail_url, undef, $vcenter, undef ) = split( /:/, $line );

      $cluster    =~ s/^cluster_//;
      $cluster    =~ s/===double-col===/:/g;
      $server     =~ s/===double-col===/:/g;
      $vm_uuid    =~ s/===double-col===/:/g;
      $vm_name    =~ s/===double-col===/:/g;
      $vcenter    =~ s/===double-col===/:/g;
      $detail_url =~ s/===double-col===/:/g;

      $vmware_inventory{VM}{$vm_uuid}{VCENTER} = $vcenter;
      $vmware_inventory{VM}{$vm_uuid}{CLUSTER} = $cluster;
      $vmware_inventory{VM}{$vm_uuid}{SERVER}  = $server;
      $vmware_inventory{VM}{$vm_uuid}{VM_NAME} = $vm_name;

      $vmware_inventory{VM_NAME}{$vm_name}{VCENTER}{$vcenter}{CLUSTER}{$cluster}{VM_UUID} = $vm_uuid;
      $vmware_inventory{VM_NAME}{$vm_name}{VCENTER}{$vcenter}{CLUSTER}{$cluster}{SERVER}  = $server;

      $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{VM}{$vm_uuid}{VM_NAME} = $vm_name;
      $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{VM}{$vm_uuid}{SERVER}  = $server;

      # get url params
      $detail_url =~ s/^.+detail\.sh\?//;
      my @params = split( /&/, $detail_url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && defined $value ) {
            $vmware_inventory{VM}{$vm_uuid}{URL_PARAM}{$param}                                            = $value;
            $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{VM}{$vm_uuid}{URL_PARAM}{$param}      = $value;
            $vmware_inventory{VM_NAME}{$vm_name}{VCENTER}{$vcenter}{CLUSTER}{$cluster}{URL_PARAM}{$param} = $value;
          }
        }
      }
    }

    #
    # ESXi
    #
    my @list_of_esxi = grep {/^S:cluster_.*:.*:CPUpool-pool:CPU:.*:.*:.*:V/} @menu;

    # S:cluster_New Cluster:10.22.11.9:CPUpool-pool:CPU pool:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.9&lpar=pool&item=pool&entitle=0&gui=1&none=none::1548025200:V
    foreach my $line (@list_of_esxi) {
      my ( undef, $cluster, $esxi, undef, undef, $url, undef ) = split( /:/, $line );

      $cluster =~ s/^cluster_//;
      $cluster =~ s/===double-col===/:/g;
      $url     =~ s/===double-col===/:/g;
      $esxi    =~ s/===double-col===/:/g;
      my $vcenter = "";

      # get url params
      $url =~ s/^.+detail\.sh\?//;
      my @params = split( /&/, $url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && $param eq "host" && defined $value ) {    # Vcenter IP
            foreach my $vc ( sort keys %{ $vmware_inventory{VCENTER} } ) {
              if ( exists $vmware_inventory{VCENTER}{$vc}{VCENTER_IP} && $vmware_inventory{VCENTER}{$vc}{VCENTER_IP} eq $value ) {
                $vcenter = $vc;
              }
            }
            last;
          }
        }
      }
      if ( defined $vcenter && $vcenter ne '' ) {
        $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{ESXI}{$esxi}{NAME} = $esxi;
      }
    }

    #
    # RESPOOL
    #
    my @list_of_rp = grep {/^B:.*:cluster_.*:.*:.*:.*:.*:.*:V/} @menu;

    # B:10.22.11.10:cluster_New Cluster:Development:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=resgroup-139&item=resourcepool&entitle=0&gui=1&none=none::Hosting::V
    foreach my $line (@list_of_rp) {
      my ( undef, undef, $cluster, $rp, $url, undef, $vcenter, undef, undef ) = split( /:/, $line );

      $cluster =~ s/^cluster_//;
      $cluster =~ s/===double-col===/:/g;
      $url     =~ s/===double-col===/:/g;
      $rp      =~ s/===double-col===/:/g;
      $vcenter =~ s/===double-col===/:/g;

      # get url params
      $url =~ s/^.+detail\.sh\?//;
      my @params = split( /&/, $url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && defined $value ) {
            $vmware_inventory{VCENTER}{$vcenter}{CLUSTER}{$cluster}{RESPOOL}{$rp}{URL_PARAM}{$param} = $value;
          }
        }
      }
    }

    #
    # DATASTORE
    #
    my @list_of_ds = grep {/^Z:.*:datastore_.*:.*:.*:.*:.*:.*:V/} @menu;

    # Z:10.22.11.10:datastore_DC:3PAR-phys-xorux-test:/lpar2rrd-cgi/detail.sh?host=datastore_datacenter-2&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=590e2b41-3f75d5e4-3f85-18a90577a87c&item=datastore&entitle=0&gui=1&none=none::Hosting::V
    foreach my $line (@list_of_ds) {
      my ( undef, undef, $dc, $ds, $url, undef, $vcenter, undef, undef ) = split( /:/, $line );

      $dc      =~ s/^datastore_//;
      $dc      =~ s/===double-col===/:/g;
      $ds      =~ s/===double-col===/:/g;
      $url     =~ s/===double-col===/:/g;
      $vcenter =~ s/===double-col===/:/g;
      $url     =~ s/^.+detail\.sh\?//;

      $vmware_inventory{VCENTER}{$vcenter}{DATASTORE}{$ds}{DATACENTER} = $dc;
      $vmware_inventory{VCENTER}{$vcenter}{DATASTORE}{$ds}{URL}        = $url;

      # get url params
      my @params = split( /&/, $url );
      foreach my $line (@params) {
        if ( $line =~ m/=/ ) {
          my ( $param, $value ) = split( /=/, $line );
          if ( defined $param && defined $value ) {
            $vmware_inventory{VCENTER}{$vcenter}{DATASTORE}{$ds}{URL_PARAM}{$param} = $value;
          }
        }
      }
    }

  }

  return 1;
}

sub get_ovirt_inventory {
  if ( -f "$wrkdir/oVirt/metadata.json" ) {
    use OVirtDataWrapper;

    # Datacenters
    foreach my $datacenter_uuid ( @{ OVirtDataWrapper::get_uuids('datacenter') } ) {
      my $datacenter_label = OVirtDataWrapper::get_label( 'datacenter', $datacenter_uuid );
      $ovirt_inventory{DATACENTER}{$datacenter_uuid}{label} = $datacenter_label;
      $ovirt_inventory{TRANSLATE_UUID}{$datacenter_uuid} = $datacenter_label;

      # Clusters
      foreach my $cluster_uuid ( @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'cluster' ) } ) {
        my $cluster_label = OVirtDataWrapper::get_label( 'cluster', $cluster_uuid );
        $ovirt_inventory{DATACENTER}{$datacenter_uuid}{CLUSTER}{$cluster_uuid}{label} = $cluster_label;
        $ovirt_inventory{TRANSLATE_UUID}{$cluster_uuid} = $cluster_label;

        # Hosts
        foreach my $host_uuid ( @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'host' ) } ) {
          my $host_label = OVirtDataWrapper::get_label( 'host', $host_uuid );
          $ovirt_inventory{DATACENTER}{$datacenter_uuid}{CLUSTER}{$cluster_uuid}{HOST}{$host_uuid}{label} = $host_label;
          $ovirt_inventory{TRANSLATE_UUID}{$host_uuid} = $host_label;

          # LANs
          foreach my $nic_uuid ( @{ OVirtDataWrapper::get_arch( $host_uuid, 'host', 'nic' ) } ) {
            my $nic_label = OVirtDataWrapper::get_label( 'host_nic', $nic_uuid );
            $ovirt_inventory{DATACENTER}{$datacenter_uuid}{CLUSTER}{$cluster_uuid}{HOST}{$host_uuid}{LAN}{$nic_uuid}{label} = $nic_label;
            $ovirt_inventory{TRANSLATE_UUID}{$nic_uuid} = $nic_label;
          }
        }

        # VMs
        foreach my $vm_uuid ( @{ OVirtDataWrapper::get_arch( $cluster_uuid, 'cluster', 'vm' ) } ) {
          my $vm_label = OVirtDataWrapper::get_label( 'vm', $vm_uuid );
          $ovirt_inventory{DATACENTER}{$datacenter_uuid}{CLUSTER}{$cluster_uuid}{VM}{$vm_uuid}{label} = $vm_label;
          $ovirt_inventory{TRANSLATE_UUID}{$vm_uuid} = $vm_label;
        }
      }

      # Storage domain
      foreach my $domain_uuid ( @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'storage_domain' ) } ) {
        my $domain_label = OVirtDataWrapper::get_label( 'storage_domain', $domain_uuid );
        $ovirt_inventory{DATACENTER}{$datacenter_uuid}{STORAGEDOMAIN}{$domain_uuid}{label} = $domain_label;
        $ovirt_inventory{TRANSLATE_UUID}{$domain_uuid} = $domain_label;

        # Disks
        foreach my $disk_uuid ( @{ OVirtDataWrapper::get_arch( $domain_uuid, 'storage_domain', 'disk' ) } ) {
          my $disk_label = OVirtDataWrapper::get_label( 'disk', $disk_uuid );
          $ovirt_inventory{DATACENTER}{$datacenter_uuid}{STORAGEDOMAIN}{$domain_uuid}{DISK}{$disk_uuid}{label} = $disk_label;
          $ovirt_inventory{TRANSLATE_UUID}{$disk_uuid} = $disk_label;
        }
      }
    }
  }

  return 1;
}

sub get_uuids_ovirt {
  my $params = shift;
  my @uuids;

  if ( exists $params->{subsys} && exists $params->{datacenter} ) {

    # CLUSTER
    if ( $params->{subsys} eq "CLUSTER" && exists $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{CLUSTER} ) {

      # datacenter -> cluster
      foreach my $uuid ( sort keys %{ $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{CLUSTER} } ) {
        push( @uuids, $uuid );
      }
    }

    # VM
    elsif ( $params->{subsys} eq "VM" && exists $params->{host} && ref( $params->{host} ) eq "ARRAY" ) {

      # datacenter -> cluster -> vm
      foreach my $cluster ( @{ $params->{host} } ) {
        if ( exists $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{CLUSTER}{$cluster}{VM} ) {
          foreach my $uuid ( sort keys %{ $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{CLUSTER}{$cluster}{VM} } ) {
            push( @uuids, $uuid );
          }
        }
      }
    }

    # HOST/LAN-TOTAL
    elsif ( ( $params->{subsys} eq "HOST" || $params->{subsys} eq "LAN-TOTAL" ) && exists $params->{host} && ref( $params->{host} ) eq "ARRAY" ) {

      # datacenter -> cluster -> host
      foreach my $cluster ( @{ $params->{host} } ) {
        if ( exists $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{CLUSTER}{$cluster}{HOST} ) {
          foreach my $uuid ( sort keys %{ $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{CLUSTER}{$cluster}{HOST} } ) {
            push( @uuids, $uuid );
          }
        }
      }
    }

    # LAN
    elsif ( $params->{subsys} eq "LAN" && exists $params->{host} && ref( $params->{host} ) eq "ARRAY" && exists $params->{name} && ref( $params->{name} ) eq "ARRAY" ) {

      # datacenter -> cluster -> host -> name (lan/nic)
      foreach my $cluster ( @{ $params->{host} } ) {
        foreach my $host ( @{ $params->{name} } ) {
          if ( exists $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{CLUSTER}{$cluster}{HOST}{$host}{LAN} ) {
            foreach my $uuid ( sort keys %{ $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{CLUSTER}{$cluster}{HOST}{$host} } ) {
              push( @uuids, $uuid );
            }
          }
        }
      }
    }

    # STORAGEDOMAIN
    if ( $params->{subsys} eq "STORAGEDOMAIN" && exists $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{STORAGEDOMAIN} ) {

      # datacenter -> storage domain
      foreach my $uuid ( sort keys %{ $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{STORAGEDOMAIN} } ) {
        push( @uuids, $uuid );
      }
    }

    # DISK
    elsif ( $params->{subsys} eq "DISK" && exists $params->{host} && ref( $params->{host} ) eq "ARRAY" ) {

      # datacenter -> storage domain -> disk
      foreach my $storagedomain ( @{ $params->{host} } ) {
        if ( exists $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{STORAGEDOMAIN}{$storagedomain}{DISK} ) {
          foreach my $uuid ( sort keys %{ $ovirt_inventory{DATACENTER}{ $params->{datacenter} }{STORAGEDOMAIN}{$storagedomain}{DISK} } ) {
            push( @uuids, $uuid );
          }
        }
      }
    }
  }

  return @uuids;
}

sub test_acl {
  my $user     = shift;
  my $platform = shift;
  my $subsys   = shift;
  my $host     = shift;
  my $item     = shift;

  # $user,POWER,LPAR,$server,$name
  # $user,POWER,POOL,$server,$pool_id
  # $user,POWER,SERVER,$server,MEMORY
  # $user,CUSTOM,CUSTOM,$host
  # $user,VMWARE,VM,cluster_$cluster,$vm_name
  # $user,VMWARE,ESXI,$cluster,$esxi
  # $user,VMWARE,RESPOOL,$cluster,$rp
  # $user,VMWARE,DATASTORE,$vcenter,$ds
  # $user,VMWARE,CLUSTER,$vcenter,$cluster
  # $user,OVIRT,VM,$uuid,$uuid
  # $user,OVIRT,DISK,$uuid,$uuid
  # $user,OVIRT,HOST,$uuid,$uuid
  # $user,OVIRT,CLUSTER,$uuid,$uuid
  # $user,OVIRT,STORAGEDOMAIN,$uuid,$uuid
  # $user,OVIRT,VM,$uuid,$uuid
  # $user,NUTANIX,NUTANIXVM,$clusteruuid,$uuid
  # $user,SOLARIS,TOTAL,cod,cod
  # $user,SOLARIS,LDOM,$name,$name
  # $user,SOLARIS,ZONE,$name,$name
  # $user,HYPERV,CLUSTER,$host,$host
  # $user,HYPERV,SERVER,$host,$host
  # $user,HYPERV,VM,$host,$host
  # $user,HYPERV,STORAGE,$host,$host

  if ( exists $users{users}{$user} ) {
    #
    # lpar2rrd
    #
    require ACL;

    $ENV{XORUX_ACCESS_CONTROL} = 1;
    $ENV{REMOTE_USER}          = $user;

    my $acl = ACL->new($user);

    #if ( !$acl->isAdmin( $user ) ) {
    #  if ( !$acl->canShow( $platform, $subsys, $host, $item, $user ) ) {
    if ( !$acl->isAdmin() ) {
      if ( !$acl->canShow( $platform, $subsys, $host, $item ) ) {
        print "ACL            : not allowed for user $user $platform: $subsys, $host, $item\n" if $debug == 9;
        return 0;
      }
    }
  }
  elsif ( exists $users_xormon{users}{$user} && $ENV{XORMON} ) {
    #
    # xormon
    #
    require ACLx;

    $ENV{REMOTE_USER}    = $user;
    $ENV{HTTP_XORUX_APP} = "Xormon";

    my ( $SERV, $CONF ) = ( Storable::retrieve("$basedir/tmp/servers_conf.storable"), Storable::retrieve("$basedir/tmp/power_conf.storable") );

    my $acl = ACLx->new($user);

    #print Dumper $acl;

    my ( $acl_hw_type, $acl_item_id ) = ( '', '' );

    # $user,OVIRT,VM,$uuid,$uuid
    # $user,OVIRT,DISK,$uuid,$uuid
    # $user,OVIRT,HOST,$uuid,$uuid
    # $user,OVIRT,CLUSTER,$uuid,$uuid
    # $user,OVIRT,STORAGEDOMAIN,$uuid,$uuid
    # $user,OVIRT,VM,$uuid,$uuid
    # $user,NUTANIX,NUTANIXVM,$clusteruuid,$uuid
    $acl_hw_type = $platform;
    $acl_item_id = ( $host eq 'nope' ) ? $item : $host;

    if ( $platform eq "POWER" ) {
      require PowerDataWrapper;

      # $user,POWER,LPAR,$server,$name
      # $user,POWER,POOL,$server,$pool_id
      # $user,POWER,SERVER,$server,MEMORY
      if ( $subsys eq "LPAR" ) { $acl_item_id = PowerDataWrapper::get_item_uid( { type => 'vm', label => $item } ); }
      if ( $subsys eq "POOL" ) {
        if ( $item eq "pool" ) {    # CPU pool
          $acl_item_id = PowerDataWrapper::get_item_uid( { type => 'pool', label => $host } );
        }
        else {                      # shpool
          my $server_id = PowerDataWrapper::get_item_uid( { type => 'SERVER', label => $host } );
          if ( defined $server_id ) {
            $acl_item_id = PowerDataWrapper::get_item_uid( { type => 'shpool', label => $item, parent => $server_id } );
          }
        }
      }
      if ( $subsys eq "SERVER" ) { $acl_item_id = PowerDataWrapper::get_item_uid( { type => 'server', label => $host } ); }
    }
    if ( $platform eq "VMWARE" ) {

      # $user,VMWARE,VM,cluster_$cluster,$vm_name
      # $user,VMWARE,ESXI,$cluster,$esxi
      # $user,VMWARE,RESPOOL,$cluster,$rp
      # $user,VMWARE,DATASTORE,$vcenter,$ds
      # $user,VMWARE,CLUSTER,$vcenter,$cluster
      # NOTE: it's necessary to create new functions to get item_id directly from DB

      return 1;    # ACLx not supported yet, allow it for everyone
    }
    if ( $platform eq "SOLARIS" ) {
      require SolarisDataWrapper;

      # $user,SOLARIS,TOTAL,cod,cod
      # $user,SOLARIS,LDOM,$name,$name
      # $user,SOLARIS,ZONE,$name,$name
      if ( $subsys eq "TOTAL" ) { $acl_item_id = "total_solaris"; }

      #LDOM,host                    -> solaris_ldom_cpu|solaris_ldom_mem|solaris_ldom_net
      #ZONE_L,host                  -> solaris_zone_cpu|solaris_zone_os_cpu|solaris_zone_mem|solaris_zone_net
      #STANDALONE_LDOM,get_item_uid -> oscpu|mem|pg1|pg2|san1|san2|san_resp|jobs|queue_cpu
      #SOLARIS_TOTAL,total_solaris  -> solaris_ldom_agg_c|solaris_ldom_agg_m
      #LDOM,get_item_uid            -> solaris_pool

      return 1;    # ACLx not supported yet, allow it for everyone
    }
    if ( $platform eq "HYPERV" ) {

      # $user,HYPERV,CLUSTER,$host,$host
      # $user,HYPERV,SERVER,$host,$host
      # $user,HYPERV,VM,$host,$host
      # $user,HYPERV,STORAGE,$host,$host
      $acl_hw_type = "WINDOWS";

      return 1;    # ACLx not supported yet, allow it for everyone
    }

    my $aclitem;
    if ( $platform eq "CUSTOM" ) {
      $aclitem = { hw_type => "CUSTOM GROUPS", item_id => $host };
    }
    else {
      $aclitem = { hw_type => $acl_hw_type, item_id => $acl_item_id, match => 'granted' };
    }

    if ( !$acl->isGranted($aclitem) ) {
      $aclitem->{label} = $host;
      my $str = join( ', ', map {"$_=>$aclitem->{$_}"} keys %{$aclitem} );
      error( "ACL: object not allowed for user: $acl->{uid}: $str " . __FILE__ . ':' . __LINE__ );
      return 0;
    }

  }
  else {
    error("ACL: User $user not found! $platform, $host, $subsys, $item ") && return 0;
  }

  #print "allowed for user $user $platform: $subsys, $host, $item\n";
  #warn "$user, $platform, $subsys, $host, $item";

  return 1;
}

sub get_list_of_graphs {
  my $user_name   = shift;
  my $report_name = shift;
  my $format      = shift;

  $topten_bookmarks = 0;

  #
  # progress bar, inventory for all graphs
  #
  my %graphs;
  $count = 0;
  if ( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'items'} && ref( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'items'} ) eq "ARRAY" ) {
    foreach my $params ( @{ $cfg{'users'}{$user_name}{'reports'}{$report_name}{'items'} } ) {
      #
      # POWER
      #
      if ( $params->{'metrics'} && ref( $params->{'metrics'} ) eq "ARRAY" && $params->{group} && $params->{group} eq "POWER" && $params->{'subsys'} ) {

        # 1.
        # host = always all, items = always all
        # ALL lpars/pools/memory for ALL servers
        if ( $params->{'allhosts'} && $params->{'entiresubsys'} ) {
          if ( $power_inventory{SERVERS} ) {
            foreach my $server ( sort keys %{ $power_inventory{SERVERS} } ) {
              #
              # LPARs
              #
              if ( $params->{'subsys'} eq "LPAR" ) {
                if ( $power_inventory{SERVERS}{$server}{LPARS} ) {
                  foreach my $name ( sort keys %{ $power_inventory{SERVERS}{$server}{LPARS} } ) {

                    # ACL
                    if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $server, $name ) ) { next; }

                    # test if lpar is active
                    if ( !$params->{'outdated'} && exists $power_inventory{SERVERS}{$server}{LPARS}{$name}{REMOVED} ) { next; }    # skip removed lpar

                    if ( $power_inventory{SERVERS}{$server}{LPARS}{$name}{MENU_TYPE} && $power_inventory{SERVERS}{$server}{LPARS}{$name}{HMC} && $power_inventory{SERVERS}{$server}{LPARS}{$name}{URL} ) {
                      my @available_metrics = find_lpar_metrics( "$power_inventory{SERVERS}{$server}{LPARS}{$name}{MENU_TYPE}", "$power_inventory{SERVERS}{$server}{LPARS}{$name}{URL}" );    # available metrics for lpar
                      foreach my $metric ( @{ $params->{'metrics'} } ) {

                        # test if metric is available for this lpar
                        my $metric_found = grep {/^$metric$/} @available_metrics;
                        if ( $metric_found == 0 ) { next; }                                                                                                                                   # this metric is not available
                        $count++;

                        $graphs{$count}->{group}  = $params->{group};
                        $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$server}{LPARS}{$name}{HMC};
                        $graphs{$count}->{host}   = $server;
                        $graphs{$count}->{subsys} = $params->{subsys};
                        $graphs{$count}->{metric} = $metric;
                        $graphs{$count}->{name}   = $name;
                        if ( $params->{sample_rate} ) {
                          $graphs{$count}->{sample_rate} = $params->{sample_rate};
                        }
                      }
                    }
                  }
                }
              }
              #
              # POOLs
              #
              if ( $params->{'subsys'} eq "POOL" ) {
                if ( $power_inventory{SERVERS}{$server}{POOLS} ) {
                  foreach my $name ( sort keys %{ $power_inventory{SERVERS}{$server}{POOLS} } ) {
                    if ( exists $power_inventory{SERVERS}{$server}{POOLS}{$name}{POOL_ID} && exists $power_inventory{SERVERS}{$server}{POOLS}{$name}{HMC} ) {

                      # ACL
                      if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $server, $power_inventory{SERVERS}{$server}{POOLS}{$name}{POOL_ID} ) ) { next; }

                      # available metrics for pool or shpool
                      my @available_metrics = find_pool_metrics( "$power_inventory{SERVERS}{$server}{POOLS}{$name}{POOL_ID}", "$cfg{'users'}{$user_name}{'reports'}{$report_name}{'format'}" );
                      foreach my $metric ( @{ $params->{'metrics'} } ) {

                        # test if metric is available for this pool/shpool
                        my $metric_found = grep {/^$metric$/} @available_metrics;
                        if ( $metric_found == 0 ) { next; }    # this metric is not available
                        $count++;

                        $graphs{$count}->{group}  = $params->{group};
                        $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$server}{POOLS}{$name}{HMC};
                        $graphs{$count}->{host}   = $server;
                        $graphs{$count}->{subsys} = $params->{subsys};
                        $graphs{$count}->{metric} = $metric;
                        $graphs{$count}->{name}   = $power_inventory{SERVERS}{$server}{POOLS}{$name}{POOL_ID};
                        if ( $params->{sample_rate} ) {
                          $graphs{$count}->{sample_rate} = $params->{sample_rate};
                        }
                      }
                    }
                  }
                }
              }
              #
              # Server memory
              #
              if ( $params->{'subsys'} eq "SERVER" ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $server, "MEMORY" ) ) { next; }

                if ( exists $power_inventory{SERVERS}{$server}{POOLS}{'CPU pool'}{HMC} ) {
                  foreach my $metric ( @{ $params->{'metrics'} } ) {
                    $count++;

                    $graphs{$count}->{group}  = $params->{group};
                    $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$server}{POOLS}{'CPU pool'}{HMC};
                    $graphs{$count}->{host}   = $server;
                    $graphs{$count}->{subsys} = $params->{subsys};
                    $graphs{$count}->{metric} = $metric;
                    $graphs{$count}->{name}   = "pool";
                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
          }
        }

        # 2.
        # host = always all
        # SINGLE LPARs/POOLs/SERVER mem for all servers
        elsif ( $params->{'allhosts'} && !$params->{'entiresubsys'} && $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {
          if ( $power_inventory{SERVERS} ) {
            foreach my $server ( sort keys %{ $power_inventory{SERVERS} } ) {
              #
              # LPARs
              #
              if ( $params->{'subsys'} eq "LPAR" ) {
                foreach my $name ( @{ $params->{'name'} } ) {

                  # ACL
                  if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $server, $name ) ) { next; }

                  # test if lpar is active
                  if ( !$params->{'outdated'} && exists $power_inventory{SERVERS}{$server}{LPARS}{$name}{REMOVED} ) { next; }    # skip removed lpar

                  if ( $power_inventory{SERVERS}{$server}{LPARS}{$name}{MENU_TYPE} && $power_inventory{SERVERS}{$server}{LPARS}{$name}{HMC} && $power_inventory{SERVERS}{$server}{LPARS}{$name}{URL} ) {    # load available metrics for this lpar
                    my @available_metrics = find_lpar_metrics( "$power_inventory{SERVERS}{$server}{LPARS}{$name}{MENU_TYPE}", "$power_inventory{SERVERS}{$server}{LPARS}{$name}{URL}" );                    # available metrics for lpar

                    foreach my $metric ( @{ $params->{'metrics'} } ) {

                      # test if metric is available for this lpar
                      my $metric_found = grep {/^$metric$/} @available_metrics;
                      if ( $metric_found == 0 ) { next; }                                                                                                                                                   # this metric is not available
                      $count++;

                      $graphs{$count}->{group}  = $params->{group};
                      $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$server}{LPARS}{$name}{HMC};
                      $graphs{$count}->{host}   = $server;
                      $graphs{$count}->{subsys} = $params->{subsys};
                      $graphs{$count}->{metric} = $metric;
                      $graphs{$count}->{name}   = $name;
                      if ( $params->{sample_rate} ) {
                        $graphs{$count}->{sample_rate} = $params->{sample_rate};
                      }
                    }
                  }
                }
              }
              #
              # POOLs
              #
              if ( $params->{'subsys'} eq "POOL" ) {
                foreach my $name ( @{ $params->{'name'} } ) {
                  if ( exists $power_inventory{SERVERS}{$server}{POOLS}{$name}{POOL_ID} && exists $power_inventory{SERVERS}{$server}{POOLS}{$name}{HMC} ) {

                    # ACL
                    if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $server, $power_inventory{SERVERS}{$server}{POOLS}{$name}{POOL_ID} ) ) { next; }

                    # available metrics for pool or shpool
                    my @available_metrics = find_pool_metrics( "$power_inventory{SERVERS}{$server}{POOLS}{$name}{POOL_ID}", "$cfg{'users'}{$user_name}{'reports'}{$report_name}{'format'}" );
                    foreach my $metric ( @{ $params->{'metrics'} } ) {

                      # test if metric is available for this pool/shpool
                      my $metric_found = grep {/^$metric$/} @available_metrics;
                      if ( $metric_found == 0 ) { next; }    # this metric is not available
                      $count++;

                      $graphs{$count}->{group}  = $params->{group};
                      $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$server}{POOLS}{$name}{HMC};
                      $graphs{$count}->{host}   = $server;
                      $graphs{$count}->{subsys} = $params->{subsys};
                      $graphs{$count}->{metric} = $metric;
                      $graphs{$count}->{name}   = $power_inventory{SERVERS}{$server}{POOLS}{$name}{POOL_ID};
                      if ( $params->{sample_rate} ) {
                        $graphs{$count}->{sample_rate} = $params->{sample_rate};
                      }
                    }
                  }
                }
              }
              #
              # SERVER mem
              #
              if ( $params->{'subsys'} eq "SERVER" && exists $power_inventory{SERVERS}{$server}{POOLS}{'CPU pool'}{HMC} ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $server, "MEMORY" ) ) { next; }

                foreach my $metric ( @{ $params->{'metrics'} } ) {
                  $count++;

                  $graphs{$count}->{group}  = $params->{group};
                  $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$server}{POOLS}{'CPU pool'}{HMC};
                  $graphs{$count}->{host}   = $server;
                  $graphs{$count}->{subsys} = $params->{subsys};
                  $graphs{$count}->{metric} = $metric;
                  $graphs{$count}->{name}   = $params->{name};
                  if ( $params->{sample_rate} ) {
                    $graphs{$count}->{sample_rate} = $params->{sample_rate};
                  }
                }
              }
            }
          }
        }

        # 3.
        # items = always all
        # ALL LPARs/POOLs/SERVER mem for single servers
        elsif ( !$params->{'allhosts'} && $params->{'entiresubsys'} && $params->{'host'} && ref( $params->{'host'} ) eq "ARRAY" ) {
          foreach my $host ( @{ $params->{'host'} } ) {
            #
            # LPARs
            #
            if ( $params->{'subsys'} eq "LPAR" && $power_inventory{SERVERS}{$host}{LPARS} ) {
              foreach my $lpar_name ( sort keys %{ $power_inventory{SERVERS}{$host}{LPARS} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, $lpar_name ) ) { next; }

                # test if lpar is active
                if ( !$params->{'outdated'} && exists $power_inventory{SERVERS}{$host}{LPARS}{$lpar_name}{REMOVED} ) { next; }    # skip removed lpar

                if ( $power_inventory{SERVERS}{$host}{LPARS}{$lpar_name}{MENU_TYPE} && $power_inventory{SERVERS}{$host}{LPARS}{$lpar_name}{HMC} && $power_inventory{SERVERS}{$host}{LPARS}{$lpar_name}{URL} ) {    # load available metrics for this lpar
                  my @available_metrics = find_lpar_metrics( "$power_inventory{SERVERS}{$host}{LPARS}{$lpar_name}{MENU_TYPE}", "$power_inventory{SERVERS}{$host}{LPARS}{$lpar_name}{URL}" );                       # available metrics for lpar

                  foreach my $metric ( @{ $params->{'metrics'} } ) {

                    # test if metric is available for this lpar
                    my $metric_found = grep {/^$metric$/} @available_metrics;
                    if ( $metric_found == 0 ) { next; }                                                                                                                                                            # this metric is not available
                    $count++;

                    $graphs{$count}->{group}  = $params->{group};
                    $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$host}{LPARS}{$lpar_name}{HMC};
                    $graphs{$count}->{host}   = $host;
                    $graphs{$count}->{subsys} = $params->{subsys};
                    $graphs{$count}->{metric} = $metric;
                    $graphs{$count}->{name}   = $lpar_name;
                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
            #
            # POOLs
            #
            if ( $params->{'subsys'} eq "POOL" && $power_inventory{SERVERS}{$host}{POOLS} ) {
              foreach my $name ( sort keys %{ $power_inventory{SERVERS}{$host}{POOLS} } ) {
                if ( exists $power_inventory{SERVERS}{$host}{POOLS}{$name}{POOL_ID} && exists $power_inventory{SERVERS}{$host}{POOLS}{$name}{HMC} ) {

                  # ACL
                  if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, $power_inventory{SERVERS}{$host}{POOLS}{$name}{POOL_ID} ) ) { next; }

                  # available metrics for pool or shpool
                  my @available_metrics = find_pool_metrics( "$power_inventory{SERVERS}{$host}{POOLS}{$name}{POOL_ID}", "$cfg{'users'}{$user_name}{'reports'}{$report_name}{'format'}" );
                  foreach my $metric ( @{ $params->{'metrics'} } ) {

                    # test if metric is available for this pool/shpool
                    my $metric_found = grep {/^$metric$/} @available_metrics;
                    if ( $metric_found == 0 ) { next; }    # this metric is not available
                    $count++;

                    $graphs{$count}->{group}  = $params->{group};
                    $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$host}{POOLS}{$name}{HMC};
                    $graphs{$count}->{host}   = $host;
                    $graphs{$count}->{subsys} = $params->{subsys};
                    $graphs{$count}->{metric} = $metric;
                    $graphs{$count}->{name}   = $power_inventory{SERVERS}{$host}{POOLS}{$name}{POOL_ID};
                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
            #
            # Server memory
            #
            if ( $params->{'subsys'} eq "SERVER" && exists $power_inventory{SERVERS}{$host}{POOLS}{'CPU pool'}{HMC} ) {

              # ACL
              if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, "MEMORY" ) ) { next; }

              foreach my $metric ( @{ $params->{'metrics'} } ) {
                $count++;

                $graphs{$count}->{group}  = $params->{group};
                $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$host}{POOLS}{'CPU pool'}{HMC};
                $graphs{$count}->{host}   = $host;
                $graphs{$count}->{subsys} = $params->{subsys};
                $graphs{$count}->{metric} = $metric;
                $graphs{$count}->{name}   = "pool";
                if ( $params->{sample_rate} ) {
                  $graphs{$count}->{sample_rate} = $params->{sample_rate};
                }
              }
            }
          }
        }

        # 4.
        # SINGLE LPARs/POOLs/etc. for single servers
        #
        elsif ( !$params->{'allhosts'} && !$params->{'entiresubsys'} && $params->{'host'} && ref( $params->{'host'} ) eq "ARRAY" && $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {
          foreach my $host ( @{ $params->{'host'} } ) {
            #
            # LPARs
            #
            if ( $params->{'subsys'} eq "LPAR" ) {
              foreach my $name ( @{ $params->{'name'} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, $name ) ) { next; }

                # test if lpar is active
                if ( !$params->{'outdated'} && exists $power_inventory{SERVERS}{$host}{LPARS}{$name}{REMOVED} ) { next; }    # skip removed lpar

                if ( $power_inventory{SERVERS}{$host}{LPARS}{$name}{MENU_TYPE} && $power_inventory{SERVERS}{$host}{LPARS}{$name}{HMC} && $power_inventory{SERVERS}{$host}{LPARS}{$name}{URL} ) {    # load available metrics for this lpar
                  my @available_metrics = find_lpar_metrics( "$power_inventory{SERVERS}{$host}{LPARS}{$name}{MENU_TYPE}", "$power_inventory{SERVERS}{$host}{LPARS}{$name}{URL}" );                  # available metrics for lpar

                  foreach my $metric ( @{ $params->{'metrics'} } ) {

                    # test if metric is available for this lpar
                    my $metric_found = grep {/^$metric$/} @available_metrics;
                    if ( $metric_found == 0 ) { next; }                                                                                                                                             # this metric is not available
                    $count++;

                    $graphs{$count}->{group}  = $params->{group};
                    $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$host}{LPARS}{$name}{HMC};
                    $graphs{$count}->{host}   = $host;
                    $graphs{$count}->{subsys} = $params->{subsys};
                    $graphs{$count}->{metric} = $metric;
                    $graphs{$count}->{name}   = $name;
                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
            #
            # POOLs
            #
            if ( $params->{'subsys'} eq "POOL" ) {
              foreach my $name ( @{ $params->{'name'} } ) {
                if ( exists $power_inventory{SERVERS}{$host}{POOLS}{$name}{POOL_ID} && exists $power_inventory{SERVERS}{$host}{POOLS}{$name}{HMC} ) {

                  # ACL
                  if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, $power_inventory{SERVERS}{$host}{POOLS}{$name}{POOL_ID} ) ) { next; }

                  # available metrics for pool or shpool
                  my @available_metrics = find_pool_metrics( "$power_inventory{SERVERS}{$host}{POOLS}{$name}{POOL_ID}", "$cfg{'users'}{$user_name}{'reports'}{$report_name}{'format'}" );
                  foreach my $metric ( @{ $params->{'metrics'} } ) {

                    # test if metric is available for this pool/shpool
                    my $metric_found = grep {/^$metric$/} @available_metrics;
                    if ( $metric_found == 0 ) { next; }    # this metric is not available
                    $count++;

                    $graphs{$count}->{group}  = $params->{group};
                    $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$host}{POOLS}{$name}{HMC};
                    $graphs{$count}->{host}   = $host;
                    $graphs{$count}->{subsys} = $params->{subsys};
                    $graphs{$count}->{metric} = $metric;
                    $graphs{$count}->{name}   = $power_inventory{SERVERS}{$host}{POOLS}{$name}{POOL_ID};
                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
            #
            # SERVER mem
            #
            if ( $params->{'subsys'} eq "SERVER" && exists $power_inventory{SERVERS}{$host}{POOLS}{'CPU pool'}{HMC} ) {

              # ACL
              if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, "MEMORY" ) ) { next; }

              foreach my $metric ( @{ $params->{'metrics'} } ) {
                $count++;

                $graphs{$count}->{group}  = $params->{group};
                $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$host}{POOLS}{'CPU pool'}{HMC};
                $graphs{$count}->{host}   = $host;
                $graphs{$count}->{subsys} = $params->{subsys};
                $graphs{$count}->{metric} = $metric;
                $graphs{$count}->{name}   = $params->{name};
                if ( $params->{sample_rate} ) {
                  $graphs{$count}->{sample_rate} = $params->{sample_rate};
                }
              }
            }
          }
        }
      }
      #
      # CUSTOM GROUPS
      #
      if ( $params->{'metrics'} && ref( $params->{'metrics'} ) eq "ARRAY" && $params->{group} && $params->{group} eq "CUSTOM" && $params->{'subsys'} && $params->{'host'} && ref( $params->{'host'} ) eq "ARRAY" ) {
        foreach my $host ( @{ $params->{'host'} } ) {

          # ACL
          if ( !test_acl( $user_name, $params->{group}, $params->{group}, $host, "" ) ) { next; }

          foreach my $metric ( @{ $params->{'metrics'} } ) {
            if ( $params->{subsys} eq "LPAR" || $params->{subsys} eq "POOL" || $params->{subsys} eq "LINUX" ) {
              my $graph_exists = find_custom_group_metric( "$host", "$metric" );

              #print STDERR "$graph_exists : $params->{host} : $metric\n";
              if ( $graph_exists == 0 ) { next; }    # unsupported metric for this custom group, probably lpars without os agent
            }
            $count++;

            $graphs{$count}->{group}  = $params->{group};
            $graphs{$count}->{host}   = $host;
            $graphs{$count}->{subsys} = $params->{subsys};
            $graphs{$count}->{metric} = $metric;
            if ( $params->{sample_rate} ) {
              $graphs{$count}->{sample_rate} = $params->{sample_rate};
            }
          }
        }
      }
      #
      # VMWARE
      #
      if ( $params->{'metrics'} && ref( $params->{'metrics'} ) eq "ARRAY" && $params->{group} && $params->{group} eq "VMWARE" && $params->{'subsys'} ) {
        #
        # VM
        #
        if ( $params->{'subsys'} eq "VM" ) {
          if ( $params->{'entiresubsys'} && exists $params->{vcenter} && exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
            foreach my $cluster ( @{ $params->{host} } ) {
              if ( exists $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{VM} ) {
                foreach my $vm_uuid ( sort keys %{ $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{VM} } ) {

                  # ACL
                  if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, "cluster_$cluster", $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{VM}{$vm_uuid}{VM_NAME} ) ) { next; }

                  foreach my $metric ( @{ $params->{'metrics'} } ) {
                    $count++;

                    $graphs{$count}->{group}   = $params->{group};
                    $graphs{$count}->{host}    = $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{VM}{$vm_uuid}{URL_PARAM}{host};
                    $graphs{$count}->{server}  = $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{VM}{$vm_uuid}{URL_PARAM}{server};
                    $graphs{$count}->{vcenter} = $params->{vcenter};
                    $graphs{$count}->{cluster} = $cluster;
                    $graphs{$count}->{vm_uuid} = $vm_uuid;
                    $graphs{$count}->{vm_name} = $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{VM}{$vm_uuid}{VM_NAME};
                    $graphs{$count}->{subsys}  = $params->{subsys};
                    $graphs{$count}->{metric}  = $metric;

                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
          }
          elsif ( !$params->{'entiresubsys'} && $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {
            foreach my $vm_uuid ( @{ $params->{'name'} } ) {
              if ( exists $vmware_inventory{VM}{$vm_uuid} && exists $vmware_inventory{VM}{$vm_uuid}{URL_PARAM}{host} && exists $vmware_inventory{VM}{$vm_uuid}{URL_PARAM}{server} && exists $vmware_inventory{VM}{$vm_uuid}{VCENTER} && exists $vmware_inventory{VM}{$vm_uuid}{CLUSTER} && exists $vmware_inventory{VM}{$vm_uuid}{VM_NAME} ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, "cluster_$vmware_inventory{VM}{$vm_uuid}{CLUSTER}", $vmware_inventory{VM}{$vm_uuid}{VM_NAME} ) ) { next; }

                foreach my $metric ( @{ $params->{'metrics'} } ) {
                  $count++;

                  $graphs{$count}->{group}   = $params->{group};
                  $graphs{$count}->{host}    = $vmware_inventory{VM}{$vm_uuid}{URL_PARAM}{host};
                  $graphs{$count}->{server}  = $vmware_inventory{VM}{$vm_uuid}{URL_PARAM}{server};
                  $graphs{$count}->{vcenter} = $vmware_inventory{VM}{$vm_uuid}{VCENTER};
                  $graphs{$count}->{cluster} = $vmware_inventory{VM}{$vm_uuid}{CLUSTER};
                  $graphs{$count}->{vm_uuid} = $vm_uuid;
                  $graphs{$count}->{vm_name} = $vmware_inventory{VM}{$vm_uuid}{VM_NAME};
                  $graphs{$count}->{subsys}  = $params->{subsys};
                  $graphs{$count}->{metric}  = $metric;

                  if ( $params->{sample_rate} ) {
                    $graphs{$count}->{sample_rate} = $params->{sample_rate};
                  }
                }
              }
            }
          }
        }
        #
        # ESXi
        #
        if ( $params->{'subsys'} eq "ESXI" && exists $params->{vcenter} && exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
          if ( $params->{'entiresubsys'} ) {
            foreach my $cluster ( @{ $params->{host} } ) {
              if ( exists $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{ESXI} && exists $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{VCENTER_IP} ) {
                foreach my $esxi ( sort keys %{ $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{ESXI} } ) {

                  # ACL
                  if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $cluster, $esxi ) ) { next; }

                  foreach my $metric ( @{ $params->{'metrics'} } ) {
                    $count++;

                    if ( $metric eq "pool" ) {
                      $graphs{$count}->{lpar} = "pool";
                    }
                    elsif ( $metric eq "lparagg" ) {
                      $graphs{$count}->{lpar} = "pool-multi";
                    }
                    else {
                      $graphs{$count}->{lpar} = "cod";
                    }

                    $graphs{$count}->{group}   = $params->{group};
                    $graphs{$count}->{host}    = $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{VCENTER_IP};
                    $graphs{$count}->{server}  = $esxi;
                    $graphs{$count}->{vcenter} = $params->{'vcenter'};
                    $graphs{$count}->{cluster} = $cluster;
                    $graphs{$count}->{subsys}  = $params->{subsys};
                    $graphs{$count}->{metric}  = $metric;
                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
          }
          elsif ( !$params->{'entiresubsys'} && $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {
            foreach my $cluster ( @{ $params->{host} } ) {
              foreach my $esxi ( @{ $params->{'name'} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $cluster, $esxi ) ) { next; }

                if ( exists $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{VCENTER_IP} ) {
                  foreach my $metric ( @{ $params->{'metrics'} } ) {
                    $count++;

                    if ( $metric eq "pool" ) {
                      $graphs{$count}->{lpar} = "pool";
                    }
                    elsif ( $metric eq "lparagg" ) {
                      $graphs{$count}->{lpar} = "pool-multi";
                    }
                    else {
                      $graphs{$count}->{lpar} = "cod";
                    }

                    $graphs{$count}->{group}   = $params->{group};
                    $graphs{$count}->{host}    = $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{VCENTER_IP};
                    $graphs{$count}->{server}  = $esxi;
                    $graphs{$count}->{vcenter} = $params->{'vcenter'};
                    $graphs{$count}->{cluster} = $cluster;
                    $graphs{$count}->{subsys}  = $params->{subsys};
                    $graphs{$count}->{metric}  = $metric;
                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
          }
        }
        #
        # RESPOOL
        #
        # B:10.22.11.10:cluster_New Cluster:Development:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=resgroup-139&item=resourcepool&entitle=0&gui=1&none=none::Hosting::V
        if ( $params->{'subsys'} eq "RESPOOL" && exists $params->{vcenter} && exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
          if ( $params->{'entiresubsys'} ) {
            foreach my $cluster ( @{ $params->{host} } ) {
              if ( exists $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{RESPOOL} ) {
                foreach my $rp ( sort keys %{ $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{RESPOOL} } ) {

                  # ACL
                  if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $cluster, $rp ) ) { next; }

                  if ( exists $vmware_inventory{VCENTER}{ $params->{vcenter} }{CLUSTER}{$cluster}{RESPOOL}{$rp}{URL_PARAM} ) {
                    my $url_params = $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{CLUSTER}{$cluster}{RESPOOL}{$rp}{URL_PARAM};
                    if ( exists $url_params->{host} && exists $url_params->{server} && exists $url_params->{lpar} ) {
                      foreach my $metric ( @{ $params->{'metrics'} } ) {
                        $count++;

                        $graphs{$count}->{group}   = $params->{group};
                        $graphs{$count}->{subsys}  = $params->{subsys};
                        $graphs{$count}->{host}    = $url_params->{host};
                        $graphs{$count}->{server}  = $url_params->{server};
                        $graphs{$count}->{lpar}    = $url_params->{lpar};
                        $graphs{$count}->{vcenter} = $params->{'vcenter'};
                        $graphs{$count}->{cluster} = $cluster;
                        $graphs{$count}->{respool} = $rp;
                        $graphs{$count}->{metric}  = $metric;

                        if ( $params->{sample_rate} ) {
                          $graphs{$count}->{sample_rate} = $params->{sample_rate};
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          elsif ( !$params->{'entiresubsys'} && $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {
            foreach my $cluster ( @{ $params->{host} } ) {
              foreach my $rp ( @{ $params->{'name'} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $cluster, $rp ) ) { next; }

                if ( exists $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{CLUSTER}{$cluster}{RESPOOL}{$rp}{URL_PARAM} ) {
                  my $url_params = $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{CLUSTER}{$cluster}{RESPOOL}{$rp}{URL_PARAM};
                  if ( exists $url_params->{host} && exists $url_params->{server} && exists $url_params->{lpar} ) {
                    foreach my $metric ( @{ $params->{'metrics'} } ) {
                      $count++;

                      $graphs{$count}->{group}   = $params->{group};
                      $graphs{$count}->{subsys}  = $params->{subsys};
                      $graphs{$count}->{host}    = $url_params->{host};
                      $graphs{$count}->{server}  = $url_params->{server};
                      $graphs{$count}->{lpar}    = $url_params->{lpar};
                      $graphs{$count}->{vcenter} = $params->{'vcenter'};
                      $graphs{$count}->{cluster} = $cluster;
                      $graphs{$count}->{respool} = $rp;
                      $graphs{$count}->{metric}  = $metric;

                      if ( $params->{sample_rate} ) {
                        $graphs{$count}->{sample_rate} = $params->{sample_rate};
                      }
                    }
                  }
                }
              }
            }
          }
        }
        #
        # DATASTORE
        #
        if ( $params->{'subsys'} eq "DATASTORE" && exists $params->{vcenter} && exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
          if ( $params->{'entiresubsys'} ) {
            if ( exists $vmware_inventory{VCENTER}{ $params->{vcenter} }{DATASTORE} ) {
              foreach my $ds ( sort keys %{ $vmware_inventory{VCENTER}{ $params->{vcenter} }{DATASTORE} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $params->{'vcenter'}, $ds ) ) { next; }

                if ( exists $vmware_inventory{VCENTER}{ $params->{vcenter} }{DATASTORE}{$ds}{URL_PARAM} && exists $vmware_inventory{VCENTER}{ $params->{vcenter} }{DATASTORE}{$ds}{DATACENTER} ) {
                  my $url_params = $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{DATASTORE}{$ds}{URL_PARAM};
                  if ( exists $url_params->{host} && exists $url_params->{server} && exists $url_params->{lpar} && exists $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{DATASTORE}{$ds}{URL} ) {
                    my @available_metrics = find_datastore_metrics("$vmware_inventory{VCENTER}{$params->{'vcenter'}}{DATASTORE}{$ds}{URL}");
                    foreach my $metric ( @{ $params->{'metrics'} } ) {

                      # test if metric is available for this datastore
                      my $metric_found = grep {/^$metric$/} @available_metrics;
                      if ( $metric_found == 0 ) { next; }    # this metric is not available
                      $count++;

                      $graphs{$count}->{group}      = $params->{group};
                      $graphs{$count}->{subsys}     = $params->{subsys};
                      $graphs{$count}->{host}       = $url_params->{host};
                      $graphs{$count}->{server}     = $url_params->{server};
                      $graphs{$count}->{lpar}       = $url_params->{lpar};
                      $graphs{$count}->{vcenter}    = $params->{'vcenter'};
                      $graphs{$count}->{datacenter} = $vmware_inventory{VCENTER}{ $params->{vcenter} }{DATASTORE}{$ds}{DATACENTER};
                      $graphs{$count}->{datastore}  = $ds;
                      $graphs{$count}->{metric}     = $metric;

                      if ( $params->{sample_rate} ) {
                        $graphs{$count}->{sample_rate} = $params->{sample_rate};
                      }
                    }
                  }
                }
              }
            }
          }
          elsif ( !$params->{'entiresubsys'} && $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {
            foreach my $cluster ( @{ $params->{host} } ) {
              foreach my $ds ( @{ $params->{'name'} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $vmware_inventory{VCENTER}{ $params->{vcenter} }{DATASTORE}{$ds}{DATACENTER}, $ds ) ) { next; }

                if ( exists $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{DATASTORE}{$ds}{URL_PARAM} ) {
                  my $url_params = $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{DATASTORE}{$ds}{URL_PARAM};
                  if ( exists $url_params->{host} && exists $url_params->{server} && exists $url_params->{lpar} ) {
                    my @available_metrics = find_datastore_metrics("$vmware_inventory{VCENTER}{$params->{'vcenter'}}{DATASTORE}{$ds}{URL}");
                    foreach my $metric ( @{ $params->{'metrics'} } ) {

                      # test if metric is available for this datastore
                      my $metric_found = grep {/^$metric$/} @available_metrics;
                      if ( $metric_found == 0 ) { next; }    # this metric is not available
                      $count++;

                      $graphs{$count}->{group}      = $params->{group};
                      $graphs{$count}->{subsys}     = $params->{subsys};
                      $graphs{$count}->{host}       = $url_params->{host};
                      $graphs{$count}->{server}     = $url_params->{server};
                      $graphs{$count}->{lpar}       = $url_params->{lpar};
                      $graphs{$count}->{vcenter}    = $params->{'vcenter'};
                      $graphs{$count}->{datacenter} = $vmware_inventory{VCENTER}{ $params->{vcenter} }{DATASTORE}{$ds}{DATACENTER};
                      $graphs{$count}->{datastore}  = $ds;
                      $graphs{$count}->{metric}     = $metric;

                      if ( $params->{sample_rate} ) {
                        $graphs{$count}->{sample_rate} = $params->{sample_rate};
                      }
                    }
                  }
                }
              }
            }
          }
        }
        #
        # CLUSTER
        #
        if ( $params->{'subsys'} eq "CLUSTER" ) {
          if ( !$params->{'entiresubsys'} && exists $params->{vcenter} && exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
            foreach my $cluster ( @{ $params->{host} } ) {

              # ACL
              if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $params->{'vcenter'}, $cluster ) ) { next; }

              if ( exists $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{CLUSTER}{$cluster}{URL_PARAM} ) {
                my $url_params = $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{CLUSTER}{$cluster}{URL_PARAM};
                if ( exists $url_params->{host} && exists $url_params->{server} && exists $url_params->{lpar} ) {
                  foreach my $metric ( @{ $params->{'metrics'} } ) {
                    $count++;

                    $graphs{$count}->{group}   = $params->{group};
                    $graphs{$count}->{subsys}  = $params->{subsys};
                    $graphs{$count}->{host}    = $url_params->{host};
                    $graphs{$count}->{server}  = $url_params->{server};
                    $graphs{$count}->{lpar}    = $url_params->{lpar};
                    $graphs{$count}->{vcenter} = $params->{'vcenter'};
                    $graphs{$count}->{cluster} = $cluster;
                    $graphs{$count}->{metric}  = $metric;

                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
          }
        }
      }
      #
      # oVirt
      #
      if ( $params->{'metrics'} && ref( $params->{'metrics'} ) eq "ARRAY" && $params->{group} && $params->{group} eq "OVIRT" && $params->{'subsys'} && $params->{'datacenter'} && exists $params->{'host'} && ref( $params->{'host'} ) eq "ARRAY" ) {
        my @uuids;
        if ( $params->{'entiresubsys'} ) {    # all items from subsystem
          @uuids = get_uuids_ovirt( \%$params );
        }
        elsif ( $params->{'subsys'} eq "VM" || $params->{'subsys'} eq "DISK" || $params->{'subsys'} eq "HOST" ) {    # single items
          if ( exists $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {
            @uuids = @{ $params->{'name'} };
          }
        }
        elsif ( $params->{'subsys'} eq "CLUSTER" || $params->{'subsys'} eq "STORAGEDOMAIN" ) {                       # single items
          @uuids = @{ $params->{'host'} };
        }
        foreach my $uuid (@uuids) {

          # ACL
          if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $uuid, $uuid ) ) { next; }

          foreach my $metric ( @{ $params->{'metrics'} } ) {

            # test if storage domain has got aggreg data and latency
            if ( $params->{'subsys'} eq "STORAGEDOMAIN" && test_storagedomain_metric( $uuid, $metric ) != 1 ) { next; }

            $count++;

            foreach my $host ( @{ $params->{'host'} } ) {
              $graphs{$count}->{host} = $host;
            }

            $graphs{$count}->{datacenter} = $params->{datacenter};
            $graphs{$count}->{group}      = $params->{group};
            $graphs{$count}->{subsys}     = $params->{subsys};
            $graphs{$count}->{uuid}       = $uuid;
            $graphs{$count}->{metric}     = $metric;
            if ( $params->{sample_rate} ) {
              $graphs{$count}->{sample_rate} = $params->{sample_rate};
            }
          }
        }
      }
      #
      # Nutanix
      #
      if ( $params->{'metrics'} && ref( $params->{'metrics'} ) eq "ARRAY" && $params->{group} && $params->{group} eq "NUTANIX" && $params->{'subsys'} && $params->{'clusteruuid'} && exists $params->{'host'} && ref( $params->{'host'} ) eq "ARRAY" ) {
        my @uuids;
        if ( $params->{'entiresubsys'} ) {    # all items from subsystem
                                              #@uuids = get_uuids_ovirt(\%$params); # not supported yet
        }
        elsif ( $params->{'subsys'} eq "SERVERTOTALS" || $params->{'subsys'} eq "STORAGETOTALS" || $params->{'subsys'} eq "VMTOTALS" ) {    # single items
          @uuids = ("$params->{'clusteruuid'}");
        }
        elsif ( $params->{'subsys'} eq "SERVER" || $params->{'subsys'} eq "VM" || $params->{'subsys'} eq "STORAGEPOOL" || $params->{'subsys'} eq "STORAGECONTAINER" || $params->{'subsys'} eq "VIRTUALDISK" || $params->{'subsys'} eq "PHYSICALDISK" ) {    # single items, not supported yet
                                                                                                                                                                                                                                                            #@uuids = @{ $params->{'host'} };
        }
        foreach my $uuid (@uuids) {

          # ACL
          if ( !test_acl( $user_name, $params->{group}, "NUTANIXVM", $params->{'clusteruuid'}, $uuid ) ) { next; }

          foreach my $metric ( @{ $params->{'metrics'} } ) {
            $count++;

            $graphs{$count}->{host}        = @{ $params->{'host'} }[0];
            $graphs{$count}->{clusteruuid} = $params->{clusteruuid};
            $graphs{$count}->{group}       = $params->{group};
            $graphs{$count}->{subsys}      = $params->{subsys};
            $graphs{$count}->{uuid}        = $uuid;
            $graphs{$count}->{metric}      = $metric;
            if ( $params->{sample_rate} ) {
              $graphs{$count}->{sample_rate} = $params->{sample_rate};
            }
          }
        }
      }
      #
      # Solaris
      #
      if ( $params->{'metrics'} && ref( $params->{'metrics'} ) eq "ARRAY" && $params->{group} && $params->{group} eq "SOLARIS" ) {
        my @names;
        if ( $params->{'entiresubsys'} && ( $params->{'subsys'} eq "LDOM" || $params->{'subsys'} eq "ZONE" ) ) {    # all items from subsystem
          foreach my $name ( sort keys %{ $solaris_inventory{LDOM} } ) {
            push( @names, $name );
          }
          foreach my $name ( sort keys %{ $solaris_inventory{GLOBAL_ZONE} } ) {
            push( @names, $name );
          }
        }
        elsif ( exists $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" && $params->{'subsys'} ne "TOTAL" ) {    # single items
          @names = @{ $params->{'name'} };
        }
        elsif ( $params->{'subsys'} eq "TOTAL" ) {
          @names = ("cod");
        }
        foreach my $name (@names) {

          # ACL
          if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $name, $name ) ) { next; }

          if ( $params->{'subsys'} eq "ZONE" ) {
            my @zones;
            if ( exists $params->{'zones'} && ref( $params->{'zones'} ) eq "ARRAY" ) {
              @zones = @{ $params->{'zones'} };
            }
            elsif ( $params->{'allzones'} ) {
              foreach ( sort keys %{ $solaris_inventory{HOST}{$name}{ZONE} } ) {
                push( @zones, $_ );
              }
            }
            foreach my $zone (@zones) {
              if ( !exists $solaris_inventory{HOST}{$name}{ZONE}{$zone} ) { next; }

              my @available_metrics = find_solaris_metrics( "$params->{'subsys'}", "$zone", "$name" );

              foreach my $metric ( @{ $params->{'metrics'} } ) {

                # test if metric is available for this datastore
                my $metric_found = grep {/^$metric$/} @available_metrics;
                if ( $metric_found == 0 ) { next; }    # this metric is not available
                $count++;

                $graphs{$count}->{group}  = $params->{group};
                $graphs{$count}->{subsys} = $params->{subsys};
                $graphs{$count}->{name}   = $name;
                $graphs{$count}->{zone}   = $zone;
                $graphs{$count}->{metric} = $metric;
                if ( $params->{sample_rate} ) {
                  $graphs{$count}->{sample_rate} = $params->{sample_rate};
                }
              }
            }
          }
          else {
            my @available_metrics = find_solaris_metrics( "$params->{'subsys'}", "$name" );

            foreach my $metric ( @{ $params->{'metrics'} } ) {
              if ( $params->{'subsys'} ne "TOTAL" ) {

                # test if metric is available for this datastore
                my $metric_found = grep {/^$metric$/} @available_metrics;
                if ( $metric_found == 0 ) { next; }    # this metric is not available
              }
              $count++;

              $graphs{$count}->{group}  = $params->{group};
              $graphs{$count}->{subsys} = $params->{subsys};
              $graphs{$count}->{name}   = $name;
              $graphs{$count}->{metric} = $metric;
              if ( $params->{sample_rate} ) {
                $graphs{$count}->{sample_rate} = $params->{sample_rate};
              }
            }
          }
        }
      }
      #
      # Hyper-V
      #
      if ( $params->{'metrics'} && ref( $params->{'metrics'} ) eq "ARRAY" && $params->{group} && $params->{group} eq "HYPERV" && exists $params->{subsys} ) {
        if ( $params->{subsys} eq "CLUSTER" ) {
          if ( exists $params->{level} && $params->{level} eq "CLUSTER" ) {    # cluster totals
            if ( exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
              foreach my $host ( @{ $params->{'host'} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, $host ) ) { next; }

                foreach my $metric ( @{ $params->{'metrics'} } ) {
                  $count++;

                  $graphs{$count}->{group}  = $params->{group};
                  $graphs{$count}->{subsys} = $params->{subsys};
                  $graphs{$count}->{host}   = $host;
                  $graphs{$count}->{name}   = "nope";
                  $graphs{$count}->{server} = "windows";
                  $graphs{$count}->{metric} = $metric;
                  if ( $params->{sample_rate} ) {
                    $graphs{$count}->{sample_rate} = $params->{sample_rate};
                  }
                }
              }
            }
          }
        }
        if ( $params->{subsys} eq "SERVER" ) {
          if ( exists $params->{level} && $params->{level} eq "DOMAIN" ) {    # server totals
            if ( exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
              foreach my $host ( @{ $params->{'host'} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, $host ) ) { next; }

                if ( exists $params->{domain} && ref( $params->{'domain'} ) eq "ARRAY" ) {
                  foreach my $domain ( @{ $params->{'domain'} } ) {
                    foreach my $metric ( @{ $params->{'metrics'} } ) {
                      $count++;

                      my $lpar = "pool";
                      if ( $metric eq "lparagg" )                                                 { $lpar = "pool-multi"; }
                      if ( $metric eq "vmnetrw" || $metric eq "hdt_data" || $metric eq "hdt_io" ) { $lpar = "cod"; }
                      if ( $metric eq "memalloc" || $metric eq "hyppg1" )                         { $lpar = "mem"; }

                      $graphs{$count}->{group}  = $params->{group};
                      $graphs{$count}->{subsys} = $params->{subsys};
                      $graphs{$count}->{host}   = $host;
                      $graphs{$count}->{name}   = $lpar;
                      $graphs{$count}->{server} = $domain;
                      $graphs{$count}->{metric} = $metric;
                      if ( $params->{sample_rate} ) {
                        $graphs{$count}->{sample_rate} = $params->{sample_rate};
                      }
                    }
                  }
                }
              }
            }
          }
        }
        if ( $params->{subsys} eq "VM" ) {
          if ( exists $params->{level} && $params->{level} eq "DOMAIN" ) {    # server VMs
            if ( exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
              foreach my $host ( @{ $params->{'host'} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, $host ) ) { next; }

                if ( exists $params->{domain} && ref( $params->{'domain'} ) eq "ARRAY" ) {
                  foreach my $domain ( @{ $params->{'domain'} } ) {
                    my @names;
                    if ( $params->{'entiresubsys'} ) {    # all items from subsystem
                      foreach my $name ( sort keys %{ $hyperv_inventory{VM} } ) {
                        push( @names, $name );
                      }
                    }
                    elsif ( exists $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {    # single items
                      @names = @{ $params->{'name'} };
                    }
                    foreach my $name (@names) {
                      foreach my $metric ( @{ $params->{'metrics'} } ) {
                        $count++;

                        if ( !exists $hyperv_inventory{VM}{$name}{UID} ) { next; }

                        $graphs{$count}->{group}  = $params->{group};
                        $graphs{$count}->{subsys} = $params->{subsys};
                        $graphs{$count}->{host}   = $host;
                        $graphs{$count}->{name}   = $name;
                        $graphs{$count}->{uid}    = $hyperv_inventory{VM}{$name}{UID};
                        $graphs{$count}->{server} = $domain;
                        $graphs{$count}->{metric} = $metric;
                        if ( $params->{sample_rate} ) {
                          $graphs{$count}->{sample_rate} = $params->{sample_rate};
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          if ( exists $params->{level} && $params->{level} eq "CLUSTER" ) {    # cluster VMs
            if ( exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
              foreach my $host ( @{ $params->{'host'} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, $host ) ) { next; }

                my @names;
                if ( $params->{'entiresubsys'} ) {    # all items from subsystem
                  foreach my $name ( sort keys %{ $hyperv_inventory{VM} } ) {
                    if ( exists $hyperv_inventory{VM}{$name}{CLUSTER}{$host} ) {
                      push( @names, $name );
                    }
                  }
                }
                elsif ( exists $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {    # single items
                  @names = @{ $params->{'name'} };
                }
                foreach my $name (@names) {
                  foreach my $metric ( @{ $params->{'metrics'} } ) {
                    $count++;

                    if ( !exists $hyperv_inventory{VM}{$name}{UID} )    { next; }
                    if ( !exists $hyperv_inventory{VM}{$name}{DOMAIN} ) { next; }
                    if ( !exists $hyperv_inventory{VM}{$name}{SERVER} ) { next; }

                    $graphs{$count}->{group}   = $params->{group};
                    $graphs{$count}->{subsys}  = $params->{subsys};
                    $graphs{$count}->{cluster} = $host;
                    $graphs{$count}->{host}    = $hyperv_inventory{VM}{$name}{SERVER};
                    $graphs{$count}->{name}    = $name;
                    $graphs{$count}->{uid}     = $hyperv_inventory{VM}{$name}{UID};
                    $graphs{$count}->{server}  = $hyperv_inventory{VM}{$name}{DOMAIN};
                    $graphs{$count}->{metric}  = $metric;

                    if ( $params->{sample_rate} ) {
                      $graphs{$count}->{sample_rate} = $params->{sample_rate};
                    }
                  }
                }
              }
            }
          }
        }
        if ( $params->{subsys} eq "STORAGE" ) {
          if ( exists $params->{level} && $params->{level} eq "DOMAIN" ) {    # server VMs
            if ( exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
              foreach my $host ( @{ $params->{'host'} } ) {

                # ACL
                if ( !test_acl( $user_name, $params->{group}, $params->{'subsys'}, $host, $host ) ) { next; }

                if ( exists $params->{domain} && ref( $params->{'domain'} ) eq "ARRAY" ) {
                  foreach my $domain ( @{ $params->{'domain'} } ) {
                    if ( exists $params->{'name'} && ref( $params->{'name'} ) eq "ARRAY" ) {    # single items
                      foreach my $name ( @{ $params->{'name'} } ) {
                        foreach my $metric ( @{ $params->{'metrics'} } ) {
                          $count++;

                          $graphs{$count}->{group}  = $params->{group};
                          $graphs{$count}->{subsys} = $params->{subsys};
                          $graphs{$count}->{host}   = $host;
                          $graphs{$count}->{name}   = $name;
                          $graphs{$count}->{server} = $domain;
                          $graphs{$count}->{metric} = $metric;
                          if ( $params->{sample_rate} ) {
                            $graphs{$count}->{sample_rate} = $params->{sample_rate};
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      #
      # TOP
      #
      if ( $params->{'metrics'} && ref( $params->{'metrics'} ) eq "ARRAY" && $params->{group} && $params->{group} eq "TOP" ) {
        if ( exists $params->{subsys} && exists $params->{topcount} && exists $params->{toptimerange} && exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
          if ( defined $format && $format eq "CSV" ) {
            foreach my $metric ( @{ $params->{'metrics'} } ) {
              $count++;

              $graphs{$count}->{group}        = $params->{group};
              $graphs{$count}->{subsys}       = $params->{subsys};
              $graphs{$count}->{topcount}     = $params->{topcount};
              $graphs{$count}->{toptimerange} = $params->{toptimerange};
              $graphs{$count}->{platform}     = @{ $params->{host} }[0];
              $graphs{$count}->{metric}       = $metric;
              if ( exists $params->{name} ) {
                $graphs{$count}->{name} = $params->{name};
              }
            }
          }
          else {
            $topten_bookmarks = 1;
            $topten_timerange = $params->{toptimerange};
            if ( $topten_loaded == 0 ) { get_topten_inventory(); }
            my $platform = @{ $params->{host} }[0];

            foreach my $metric ( @{ $params->{'metrics'} } ) {
              my $item       = $metric;
              my $item_graph = $metric;

              if ( $platform eq "POWER" ) {
                if ( $metric eq "rep_cpu" )     { $item = "load_cpu";    $item_graph = "lpar"; }
                if ( $metric eq "rep_saniops" ) { $item = "os_san_iops"; $item_graph = "san2"; }
                if ( $metric eq "rep_san" )     { $item = "os_san1";     $item_graph = "san1"; }
                if ( $metric eq "rep_lan" )     { $item = "os_lan";      $item_graph = "lan"; }

                my $idx = 0;
              OUTER: foreach my $stat_val ( sort { $b <=> $a } keys %{ $topten_inventory{$platform}{$item}{ $params->{toptimerange} } } ) {
                  foreach my $host ( sort keys %{ $topten_inventory{$platform}{$item}{ $params->{toptimerange} }{$stat_val} } ) {
                    if ( $params->{'subsys'} eq "server" ) {    # only selected servers
                      my $found = grep {/^$host$/} @{ $params->{'name'} };
                      if ( $found == 0 ) { next; }              # this is not selected host
                    }

                    my $host_label = $host;
                    $host_label =~ s/--unknown$//;
                    foreach my $name ( sort keys %{ $topten_inventory{$platform}{$item}{ $params->{toptimerange} }{$stat_val}{$host} } ) {
                      my $name_space = $name;
                      $name_space =~ s/&&1/\//g;
                      if ( $host eq "Solaris--unknown" && exists $solaris_inventory{GLOBAL_ZONE}{$name_space} ) {
                        $idx++;
                        $count++;

                        #print "$metric : $item : $stat_val : $host : $host_label : $name\n";
                        $graphs{$count}->{group}  = $platform;
                        $graphs{$count}->{hmc}    = "no_hmc";
                        $graphs{$count}->{host}   = $host;
                        $graphs{$count}->{subsys} = "LPAR";
                        $graphs{$count}->{metric} = $item_graph;
                        $graphs{$count}->{name}   = $name;

                        if ( $idx >= $params->{topcount} ) { last OUTER; }
                      }
                      elsif ( exists $power_inventory{SERVERS}{$host_label}{LPARS}{$name_space}{HMC} ) {
                        $idx++;
                        $count++;

                        #print "$metric : $item : $stat_val : $host : $host_label : $name : $power_inventory{SERVERS}{$host_label}{LPARS}{$name}{HMC}\n";
                        $graphs{$count}->{group}  = $platform;
                        $graphs{$count}->{hmc}    = $power_inventory{SERVERS}{$host_label}{LPARS}{$name_space}{HMC};
                        $graphs{$count}->{host}   = $host;
                        $graphs{$count}->{subsys} = "LPAR";
                        $graphs{$count}->{metric} = $item_graph;
                        $graphs{$count}->{name}   = $name;

                        if ( $idx >= $params->{topcount} ) { last OUTER; }
                      }
                    }
                  }
                }
              }
              if ( $platform eq "VMWARE" ) {
                if ( $metric eq "rep_cpu" )  { $item = "vm_cpu";  $item_graph = "lpar"; }
                if ( $metric eq "rep_iops" ) { $item = "vm_iops"; $item_graph = "vmw-iops"; }
                if ( $metric eq "rep_disk" ) { $item = "vm_disk"; $item_graph = "vmw-diskrw"; }
                if ( $metric eq "rep_lan" )  { $item = "vm_net";  $item_graph = "vmw-netrw"; }

                my $idx = 0;
              OUTER: foreach my $stat_val ( sort { $b <=> $a } keys %{ $topten_inventory{$platform}{$item}{ $params->{toptimerange} } } ) {
                  foreach my $host ( sort keys %{ $topten_inventory{$platform}{$item}{ $params->{toptimerange} }{$stat_val} } ) {
                    if ( $params->{'subsys'} eq "server" ) {    # only selected servers
                      my $found = grep {/^$host$/} @{ $params->{'name'} };
                      if ( $found == 0 ) { next; }              # this is not selected host
                    }

                    my $host_label = $host;
                    $host_label =~ s/--unknown$//;
                    foreach my $name ( sort keys %{ $topten_inventory{$platform}{$item}{ $params->{toptimerange} }{$stat_val}{$host} } ) {
                      my $name_space = $name;
                      $name_space =~ s/&&1/\//g;
                      if ( exists $vmware_inventory{VM_NAME}{$name_space}{VCENTER}{$host}{CLUSTER} ) {
                        foreach my $cluster ( sort keys %{ $vmware_inventory{VM_NAME}{$name_space}{VCENTER}{$host}{CLUSTER} } ) {
                          if ( exists $vmware_inventory{VM_NAME}{$name_space}{VCENTER}{$host}{CLUSTER}{$cluster}{URL_PARAM}{host} && exists $vmware_inventory{VM_NAME}{$name_space}{VCENTER}{$host}{CLUSTER}{$cluster}{URL_PARAM}{server} && exists $vmware_inventory{VM_NAME}{$name_space}{VCENTER}{$host}{CLUSTER}{$cluster}{VM_UUID} ) {

                            $idx++;
                            $count++;

                            #print "$metric : $item : $stat_val : $host : $host_label : $name : $power_inventory{SERVERS}{$host_label}{LPARS}{$name}{HMC}\n";
                            $graphs{$count}->{group}   = $platform;
                            $graphs{$count}->{host}    = $vmware_inventory{VM_NAME}{$name_space}{VCENTER}{$host}{CLUSTER}{$cluster}{URL_PARAM}{host};
                            $graphs{$count}->{server}  = $vmware_inventory{VM_NAME}{$name_space}{VCENTER}{$host}{CLUSTER}{$cluster}{URL_PARAM}{server};
                            $graphs{$count}->{vcenter} = $host;
                            $graphs{$count}->{cluster} = $cluster;
                            $graphs{$count}->{vm_uuid} = $vmware_inventory{VM_NAME}{$name_space}{VCENTER}{$host}{CLUSTER}{$cluster}{VM_UUID};
                            $graphs{$count}->{vm_name} = $name;
                            $graphs{$count}->{subsys}  = "VM";
                            $graphs{$count}->{metric}  = $item_graph;

                            if ( $idx >= $params->{topcount} ) { last OUTER; }
                            last;    # use only first cluster
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      #
      # Resource Configuration Advisor
      #
      if ( $params->{'metrics'} && ref( $params->{'metrics'} ) eq "ARRAY" && $params->{group} && $params->{group} eq "RCA" ) {
        if ( exists $params->{toptimerange} && exists $params->{host} && ref( $params->{'host'} ) eq "ARRAY" ) {
          foreach my $metric ( @{ $params->{'metrics'} } ) {
            $count++;

            $graphs{$count}->{group}        = $params->{group};
            $graphs{$count}->{toptimerange} = $params->{toptimerange};
            $graphs{$count}->{platform}     = @{ $params->{host} }[0];
            $graphs{$count}->{metric}       = $metric;
          }
        }
      }
    }
  }

  return %graphs;
}

sub test_storagedomain_metric {
  my $uuid   = shift;
  my $metric = shift;

  if ( $metric eq "ovirt_storage_domain_aggr_data" || $metric eq "ovirt_storage_domain_aggr_latency" ) {

    # test if this storagedomain has got assignet DISKs
    if ( exists $ovirt_inventory{DATACENTER} ) {
      foreach my $dc_uuid ( keys %{ $ovirt_inventory{DATACENTER} } ) {
        if ( exists $ovirt_inventory{DATACENTER}{$dc_uuid}{STORAGEDOMAIN}{$uuid}{DISK} ) { return 1; }
      }
    }

    return 0;
  }
  else {
    return 1;
  }
}

sub find_custom_group_metric {
  my $name = shift;
  my $item = shift;

  if ( $item eq "custom"            && -f "$tmpdir/custom-group-$name-d.cmd" )           { return 1; }
  if ( $item eq "custom_cpu_trend"  && -f "$tmpdir/custom-group-$name-cpu_trend-y.cmd" ) { return 1; }
  if ( $item eq "custommem"         && -f "$tmpdir/custom-group-mem-$name-d.cmd" )       { return 1; }
  if ( $item eq "customosmem"       && -f "$tmpdir/custom-group-mem-os-$name-d.cmd" )    { return 1; }
  if ( $item eq "customoslan"       && -f "$tmpdir/custom-group-lan-os-$name-d.cmd" )    { return 1; }
  if ( $item eq "customossan1"      && -f "$tmpdir/custom-group-san1-os-$name-d.cmd" )   { return 1; }
  if ( $item eq "customossan2"      && -f "$tmpdir/custom-group-san2-os-$name-d.cmd" )   { return 1; }
  if ( $item eq "custom_linux_cpu"  && -f "$tmpdir/custom-group-cpu-$name-d.cmd" )       { return 1; }
  if ( $item eq "custom_linux_mem"  && -f "$tmpdir/custom-group-mem-$name-d.cmd" )       { return 1; }
  if ( $item eq "custom_linux_lan"  && -f "$tmpdir/custom-group-lan-os-$name-d.cmd" )    { return 1; }
  if ( $item eq "custom_linux_san1" && -f "$tmpdir/custom-group-san1-os-$name-d.cmd" )   { return 1; }

  return 0;
}

sub set_report_time_range {
  my $freq  = shift;
  my $range = shift;

  my $sunix = 0;
  my $eunix = 0;

  my $day_sec  = 60 * 60 * 24;
  my $act_time = time();
  my $act_date = localtime();
  my ( $act_sec, $act_min, $act_hour, $act_day, $act_month, $act_year, $act_wday, $act_yday, $act_isdst ) = localtime();

  # previous day/week/month/year
  if ( $range eq "prev" ) {
    if ( $freq eq "daily" ) {
      $eunix = mktime( 0, 0, 0, $act_day, $act_month, $act_year );
      $sunix = $eunix - $day_sec;
    }
    if ( $freq eq "weekly" ) {
      $eunix = mktime( 0, 0, 0, $act_day, $act_month, $act_year );
      $eunix = $eunix - ( ( $act_wday - 1 ) * $day_sec );
      $sunix = $eunix - ( 7 * $day_sec );
    }
    if ( $freq eq "monthly" ) {
      $sunix = mktime( 0, 0, 0, 1, $act_month - 1, $act_year );
      $eunix = mktime( 0, 0, 0, 1, $act_month,     $act_year );
    }
    if ( $freq eq "yearly" ) {
      $sunix = mktime( 0, 0, 0, 1, 0, $act_year - 1 );
      $eunix = mktime( 0, 0, 0, 1, 0, $act_year );
    }

    # perl <5.12 has got some problems on aix with DST (daylight saving time)
    # sometimes there is one hour difference
    # therefore align the time to midnight again
    my ( $s_sec, $s_min, $s_hour, $s_day, $s_month, $s_year, $s_wday, $s_yday, $s_isdst ) = localtime($sunix);
    $sunix = mktime( 0, 0, 0, $s_day, $s_month, $s_year, $s_wday, $s_yday, $s_isdst );
    my ( $e_sec, $e_min, $e_hour, $e_day, $e_month, $e_year, $e_wday, $e_yday, $e_isdst ) = localtime($eunix);
    $eunix = mktime( 0, 0, 0, $e_day, $e_month, $e_year, $e_wday, $e_yday, $e_isdst );
  }

  # last day/week/month/year
  if ( $range eq "last" ) {
    if ( $freq eq "daily" ) {
      $eunix = $act_time;
      $sunix = $eunix - $day_sec;
    }
    if ( $freq eq "weekly" ) {
      $eunix = $act_time;
      $sunix = $eunix - ( $day_sec * 7 );
    }
    if ( $freq eq "monthly" ) {
      $sunix = mktime( $act_sec, $act_min, $act_hour, $act_day, $act_month - 1, $act_year );
      $eunix = $act_time;
    }
    if ( $freq eq "yearly" ) {
      $sunix = mktime( $act_sec, $act_min, $act_hour, $act_day, $act_month, $act_year - 1 );
      $eunix = $act_time;
    }
  }

  #print STDERR localtime($sunix) . " - " . localtime($eunix) . "\n";

  return ( $sunix, $eunix );
}

sub make_csv_report_lpar {
  my $report_name = shift;
  my $user_name   = shift;
  my $sunix       = shift;
  my $eunix       = shift;
  my $sdate       = shift;
  my $edate       = shift;
  my $time        = shift;

  my $report_name_space = $report_name;
  $report_name_space =~ s/\s/_/g;

  # test if user is configured
  if ( !exists $users{users}{$user_name} && !exists $users_xormon{users}{$user_name} ) {
    error( "User \"$user_name\" is no longer configured! Report \"$report_name\" skipped... $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  #
  # Report variables
  #
  my $zip_report = 0;
  if ( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'zipattach'} ) { $zip_report = 1; }
  print "zipattach      : $zip_report\n" if $debug == 9;

  if ( exists $cfg{'users'}{$user_name}{'csvDelimiter'} ) {
    $ENV{'CSV_SEPARATOR'} = $cfg{'users'}{$user_name}{'csvDelimiter'};
  }

  #
  # Report dir
  #
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime();
  my $act_time2name  = sprintf( "%4d%02d%02d_%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
  my $report_dir     = "$reportsdir/$user_name/$report_name_space";
  my $act_report_dir = "$report_dir/$act_time2name";

  if ( !-d "$reportsdir/$user_name" ) {
    mkdir( "$reportsdir/$user_name", 0777 ) || error( "Cannot mkdir $reportsdir/$user_name: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }
  if ( !-d $report_dir ) {
    mkdir( "$report_dir", 0777 ) || error( "Cannot mkdir $report_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }
  if ( !-d $act_report_dir ) {
    mkdir( "$act_report_dir", 0777 ) || error( "Cannot mkdir $act_report_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }

  #
  # progress bar, inventory for all graphs
  #
  my %graphs = get_list_of_graphs( "$user_name", "$report_name", "CSV" );

  #
  # Make report / Create PNG
  #
  #print Dumper \%graphs;
  $done = 0;
  foreach my $graph_idx ( sort { $a <=> $b } keys %graphs ) {
    my $params = $graphs{$graph_idx};
    my ( $csv_name, $query_string_act ) = set_query_string_csv( "$sunix", "$eunix", \%$params );
    if ( $csv_name && $query_string_act ) {
      get_csv_stor( "$act_report_dir/$csv_name", "$query_string_act" );
    }
    else {
      error( "Can't create QUERY_STRING for: user=$user_name,report=$report_name,metric=$params->{metric} : " . __FILE__ . ":" . __LINE__ );
      error( "Item parameters: " . encode_json( \%$params ) );
    }
    $done++;
    %status = ( status => "pending", count => $count, done => $done );
    write_file( "/tmp/lrep-$pid.status", encode_json( \%status ) );
  }

  #
  # Zip files
  #
  my $zip_file_name = "$report_name_space-$act_time2name.zip";
  my $zip_file      = "$report_dir/$zip_file_name";
  my $ret           = zip_file( "$zip_file", "$user_name/$report_name_space/$act_time2name", "$reportsdir" );
  if ( !-f $zip_file ) {
    error( "Something wrong, zip file does not exists!" . __FILE__ . ":" . __LINE__ ) && return;
  }
  else {
    set_permissions( "$zip_file", 0664 );
  }

  #
  # Send report via email
  #
  my $emails_count = 0;
  my %attachments;
  if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} && ref( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} ) eq "ARRAY" ) {
    foreach ( @{ $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} } ) {
      if ( exists $cfg{'users'}{$user_name}{'groups'}{$_}{'emails'} && ref( $cfg{'users'}{$user_name}{'groups'}{$_}{'emails'} ) eq "ARRAY" ) {
        foreach ( @{ $cfg{'users'}{$user_name}{'groups'}{$_}{'emails'} } ) {
          $emails_count++;
        }
      }
    }
  }
  print "emails found   : $emails_count\n" if $debug == 9;
  if ( $emails_count > 0 ) {
    #
    # Set attachments
    #
    my @att_files;
    my @att_names;

    #if ( defined $zip_report && isdigit($zip_report) && $zip_report == 1 ) {
    if ( -f $zip_file ) {    # always send a zip in case of csv

      print "attachment     : Content-Type=\"application/zip\",filename=\"$zip_file_name\"\n" if $debug == 9;
      push @att_files, $zip_file;
      push @att_names, $zip_file_name;

      #}
    }
    else {
      opendir( DIR, "$act_report_dir" ) || error( " directory does not exists : $act_report_dir" . __FILE__ . ":" . __LINE__ ) && exit 1;
      my @files = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);

      foreach my $file (@files) {
        chomp $file;

        print "attachment     : Content-Type=\"text/csv\",filename=\"$file\"\n" if $debug == 9;
        push @att_files, $file;

      }
    }
    my $subject   = "$product: $report_name";
    my $mail_from = "";

    if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} && ref( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} ) eq "ARRAY" ) {
      foreach my $group ( @{ $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} } ) {
        if ( exists $cfg{'users'}{$user_name}{'groups'}{$group}{'mailfrom'} && $cfg{'users'}{$user_name}{'groups'}{$group}{'mailfrom'} ne '' ) {
          $mail_from = $cfg{'users'}{$user_name}{'groups'}{$group}{'mailfrom'};
        }
        else {
          $mail_from = $mail_from_default;
        }
        if ( exists $cfg{'users'}{$user_name}{'groups'}{$group}{'emails'} && ref( $cfg{'users'}{$user_name}{'groups'}{$group}{'emails'} ) eq "ARRAY" ) {
          foreach my $mail_to ( @{ $cfg{'users'}{$user_name}{'groups'}{$group}{'emails'} } ) {
            print "send email to  : group=\"$group\" email=\"$mail_to\" from=\"$mail_from\"\n" if $debug == 9;
            Xorux_lib::send_email( $mail_to, $mail_from, $subject, $message_body, \@att_files, \@att_names );
          }
        }
      }
    }
  }

  #
  # Print location of output files
  #
  if ( -f $zip_file ) {
    print "download       : $zip_file\n" if $debug == 9;
    print "stored zip     : $zip_file\n" if $debug == 9;
  }
  else {
    error( "Something wrong, zip file does not exists!" . __FILE__ . ":" . __LINE__ );
  }
  if ( -d $act_report_dir ) {
    print "stored report  : $act_report_dir\n" if $debug == 9;
  }
  else {
    error( "Something wrong, report directory does not exists!" . __FILE__ . ":" . __LINE__ );
  }

  return 1;
}

sub get_csv_stor {
  my $csv          = shift;
  my $query_string = shift;

  $ENV{'QUERY_STRING'} = $query_string;

  chdir("$bindir") || error( "Couldn't change directory to $bindir $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  print "create csv     : QUERY_STRING=$ENV{'QUERY_STRING'}\n" if $debug == 9;

  #my $ret = `$perl $bindir/lpar2rrd-rep.pl 2>$reportsdir/error.log-tmp`;
  my $ret = `$perl $bindir/lpar2csv.pl 2>$reportsdir/error.log-tmp`;

  if ( -f "$reportsdir/error.log-tmp" ) {
    my $file_size = ( stat("$reportsdir/error.log-tmp") )[9];
    if ( isdigit($file_size) && $file_size > 0 ) {
      open( ERR, "<$reportsdir/error.log-tmp" ) || error( "Couldn't open file $reportsdir/error.log-tmp $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
      my @lines = <ERR>;
      close(ERR);

      foreach my $line (@lines) {
        chomp $line;
        error("ERROR lpar2csv.pl: $line");
      }
    }
    unlink("$reportsdir/error.log-tmp");
  }

  # remove html header
  my ( $header, $justcsv ) = ( split "\n\n", $ret, 2 );

  # write png without header
  if ( defined $justcsv && $justcsv ne '' ) {
    open( CSV, ">$csv" ) || error( "Couldn't open file $csv $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
    print CSV "$justcsv";
    close(CSV);
  }

  # check if image was created
  if ( !-f $csv ) {
    error("CSV was not created! \"$csv\"") && return 0;
  }
  else {
    set_permissions( "$csv", 0664 );
  }

  # check file size
  my $file_size = ( stat("$csv") )[9];
  if ( isdigit($file_size) && $file_size == 0 ) {
    error("CSV file size is 0! Something wrong with csv creation. File \"$csv\" removed!");
    unlink("$csv");
    return 0;
  }

  #print "PNG HEADER: $header\n";

  return 1;
}

sub find_pool_metrics {
  my $pool_id    = shift;
  my $rep_format = shift;

  my @metrics;

  #>->-"POOL" : {
  #>->->-"IMG" : {
  #>->->->-"ITEMS" : {
  #>->->->->-"pool" : ["pool", "trendpool", "pool-max", "trendpool-max", "lparagg"],
  #>->->->->-"shpool" : ["shpool", "trendshpool", "shpool-max", "trendshpool-max", "poolagg"],
  #>->->->->-"all" : ["pool", "trendpool", "pool-max", "trendpool-max", "lparagg", "shpool", "trendshpool", "shpool-max", "trendshpool-max", "poolagg"]
  #>->->->-},
  #>->->->-"AGGREGATES" : {
  #>->->->-}
  #>->->-},
  #>->->-"CSV" : {
  #>->->->-"ITEMS" : {
  #>->->->->-"pool" : ["pool", "pool-max", "lparagg"],
  #>->->->->-"shpool" : ["shpool", "shpool-max"],
  #>->->->->-"all" : ["pool", "pool-max", "lparagg", "shpool", "shpool-max"]
  #>->->->-},
  #>->->->-"AGGREGATES" : {
  #>->->->-}

  if ( defined $pool_id && defined $rep_format ) {
    if ( $pool_id eq "pool" ) {    # CPU pool
      if ( $rep_format eq "PDF" || $rep_format eq "IMG" ) {
        @metrics = ( "pool-total", "pool-total-max", "pool", "trendpool", "pool-max", "trendpool-max", "lparagg" );
      }
      elsif ( $rep_format eq "CSV" ) {
        @metrics = ( "pool", "pool-max", "lparagg" );
      }
    }
    elsif ( $pool_id =~ m/^SharedPool/ ) {    # shpool
      if ( $rep_format eq "PDF" || $rep_format eq "IMG" ) {
        @metrics = ( "shpool", "trendshpool", "shpool-max", "trendshpool-max", "poolagg" );
      }
      elsif ( $rep_format eq "CSV" ) {
        @metrics = ( "shpool", "shpool-max" );
      }
    }
  }

  return @metrics;
}

sub find_lpar_metrics {
  my $menu_char = shift;
  my $url       = shift;

  my @metrics;

  # A: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS', 'SAN_RESP'],    // AIX or Linux on Power or VIOS without SEA
  # B: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN'],                                   // AIX or Linux on Power or VIOS without SEA without SAN
  # C: ['CPU'], // AIX or Linux on Power without OS agent
  # L: ['OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS', 'SAN_RESP'],           // Linux OS agent or AIX without HMC CPU
  # M: ['OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN'],                                          // Linux OS agent or AIX or without HMC CPU & SAN
  # // I: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS'], // AS400 (not implemented yet)
  # S: ['OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN'],                                          // Solaris (no HMC CPU, no SAN)
  # V: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS', 'SAN_RESP', 'SEA'],    // VIOS with SEA
  # U: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SEA'],                                   // VIOS with SEA without SAN
  # W: ['OSCPU', 'MEM', 'PAGING1', 'PAGING2'],                                                 // WPAR (cpu,mem,pg only)
  # X: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS', 'SAN_RESP'],    // VMware VM

  if ( $menu_char eq "A" ) { @metrics = ( 'lpar',  'lparmemalloc', 'trend', 'oscpu', 'mem', 'pg1', 'pg2', 'lan', 'san1', 'san2', 'san_resp' ); }
  if ( $menu_char eq "B" ) { @metrics = ( 'lpar',  'lparmemalloc', 'trend', 'oscpu', 'mem', 'pg1', 'pg2', 'lan' ); }
  if ( $menu_char eq "C" ) { @metrics = ( 'lpar',  'lparmemalloc', 'trend' ); }
  if ( $menu_char eq "L" ) { @metrics = ( 'oscpu', 'mem',          'pg1', 'pg2', 'lan', 'san1', 'san2', 'san_resp' ); }
  if ( $menu_char eq "M" ) { @metrics = ( 'oscpu', 'mem',          'pg1', 'pg2', 'lan' ); }

  #if ( $menu_char eq "I" ) { @metrics = ('lpar', 'oscpu', 'mem', 'pg1', 'pg2', 'lan', 'san1', 'san2'); }
  if ( $menu_char eq "S" ) { @metrics = ( 'oscpu', 'mem',          'pg1',   'pg2',   'lan' ); }
  if ( $menu_char eq "V" ) { @metrics = ( 'lpar',  'lparmemalloc', 'trend', 'oscpu', 'mem', 'pg1', 'pg2', 'lan', 'san1', 'san2', 'san_resp', 'sea' ); }
  if ( $menu_char eq "U" ) { @metrics = ( 'lpar',  'lparmemalloc', 'trend', 'oscpu', 'mem', 'pg1', 'pg2', 'lan', 'sea' ); }
  if ( $menu_char eq "W" ) { @metrics = ( 'oscpu', 'mem',          'pg1',   'pg2' ); }
  if ( $menu_char eq "X" ) { @metrics = ( 'lpar',  'lparmemalloc', 'trend', 'oscpu', 'mem', 'pg1', 'pg2', 'lan', 'san1', 'san2', 'san_resp' ); }
  if ( $menu_char eq "Y" ) { @metrics = ( 'lpar',  'lparmemalloc', 'trend', 'oscpu', 'mem', 'pg1', 'pg2', 'lan', 'san1', 'san2' ); }

  # test if this lpar has got CPU QUEUE tab
  if ( defined $url && $url ne '' ) {
    $ENV{'QUERY_STRING'} = $url;

    chdir("$bindir") || error( "Couldn't change directory to $bindir $!" . __FILE__ . ":" . __LINE__ ) && exit 1;

    #print "detail-cgi.pl  : QUERY_STRING=$ENV{'QUERY_STRING'}\n" if $debug == 9;

    my $ret = `$perl $bindir/detail-cgi.pl 2>$reportsdir/error.log-tmp`;

    if ( -f "$reportsdir/error.log-tmp" ) {
      my $file_size = ( stat("$reportsdir/error.log-tmp") )[9];
      if ( isdigit($file_size) && $file_size > 0 ) {
        open( ERR, "<$reportsdir/error.log-tmp" ) || error( "Couldn't open file $reportsdir/error.log-tmp $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
        my @lines = <ERR>;
        close(ERR);

        foreach my $line (@lines) {
          chomp $line;
          error("ERROR detail-cgi.pl: $line");
        }
      }
      unlink("$reportsdir/error.log-tmp");
    }

    my @out = ( split "\n", $ret );
    foreach my $line (@out) {
      if ( $line =~ m/<li/ && $line =~ m/<\/li>/ && $line =~ m/#tabs-[0-9]+/ ) {
        if ( $line =~ m/>CPU QUEUE</ ) {
          push( @metrics, "queue_cpu" );
          last;
        }
      }
      if ( $line =~ m/<\/ul>/ ) { last; }
    }
  }

  return @metrics;
}

sub find_solaris_metrics {
  my $type = shift;
  my $name = shift;
  my $host = shift;

  my @metrics;

  if ( $type eq "LDOM" && exists $solaris_inventory{LDOM}{$name}{URL} ) {
    $ENV{'QUERY_STRING'} = $solaris_inventory{LDOM}{$name}{URL};
  }
  elsif ( $type eq "LDOM" && exists $solaris_inventory{GLOBAL_ZONE}{$name}{URL} ) {    # LDOM and GLOB_ZONE are in the same level LDOM/GLOB_ZONE, so then try also if it is not GLOB_ZONE
    $ENV{'QUERY_STRING'} = $solaris_inventory{GLOBAL_ZONE}{$name}{URL};
  }
  elsif ( $type eq "ZONE" && defined $host && exists $solaris_inventory{HOST}{$host}{ZONE}{$name}{URL} ) {
    $ENV{'QUERY_STRING'} = $solaris_inventory{HOST}{$host}{ZONE}{$name}{URL};
  }
  else {
    return @metrics;
  }

  chdir("$bindir") || error( "Couldn't change directory to $bindir $!" . __FILE__ . ":" . __LINE__ ) && exit 1;

  #print "detail-cgi.pl  : QUERY_STRING=$ENV{'QUERY_STRING'}\n" if $debug == 9;

  my $ret = `$perl $bindir/detail-cgi.pl 2>$reportsdir/error.log-tmp`;

  if ( -f "$reportsdir/error.log-tmp" ) {
    my $file_size = ( stat("$reportsdir/error.log-tmp") )[9];
    if ( isdigit($file_size) && $file_size > 0 ) {
      open( ERR, "<$reportsdir/error.log-tmp" ) || error( "Couldn't open file $reportsdir/error.log-tmp $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
      my @lines = <ERR>;
      close(ERR);

      foreach my $line (@lines) {
        chomp $line;
        error("ERROR detail-cgi.pl: $line");
      }
    }
    unlink("$reportsdir/error.log-tmp");
  }

  my @out = ( split "\n", $ret );
  foreach my $line (@out) {
    if ( $line =~ m/<li/ && $line =~ m/<\/li>/ && $line =~ m/#tabs-[0-9]+/ ) {

      # ldom/global zone
      if ( $type eq "LDOM" ) {
        if ( $line =~ m/>CPU</ )       { push( @metrics, "solaris_ldom_cpu" ); }
        if ( $line =~ m/>MEM</ )       { push( @metrics, "solaris_ldom_mem" ); }
        if ( $line =~ m/>CPU OS</ )    { push( @metrics, "oscpu" ); }
        if ( $line =~ m/>Memory OS</ ) { push( @metrics, "mem" ); }
        if ( $line =~ m/>Paging 1</ )  { push( @metrics, "pg1" ); }
        if ( $line =~ m/>Paging 2</ )  { push( @metrics, "pg2" ); }
        if ( $line =~ m/>SAN</ )       { push( @metrics, "solaris_ldom_san1" ); }
        if ( $line =~ m/>SAN IOPS</ )  { push( @metrics, "solaris_ldom_san2" ); }
        if ( $line =~ m/>SAN RESP</ )  { push( @metrics, "solaris_ldom_san_resp" ); }
        if ( $line =~ m/>NET</ )       { push( @metrics, "solaris_ldom_net" ); }
        if ( $line =~ m/>VNET</ )      { push( @metrics, "solaris_ldom_vnet" ); }
        if ( $line =~ m/>JOB</ )       { push( @metrics, "jobs" ); push( @metrics, "jobs_mem" ); }
        if ( $line =~ m/>LAN</ )       { push( @metrics, "lan" ); }
      }

      # zone
      if ( $type eq "ZONE" ) {
        if ( $line =~ m/>CPU</ )         { push( @metrics, "solaris_zone_cpu" ); }
        if ( $line =~ m/>CPU percent</ ) { push( @metrics, "solaris_zone_os_cpu" ); }
        if ( $line =~ m/>Memory</ )      { push( @metrics, "solaris_zone_mem" ); }
        if ( $line =~ m/>Net</ )         { push( @metrics, "solaris_zone_net" ); }
        if ( $line =~ m/>CPU OS</ )      { push( @metrics, "oscpu" ); }
        if ( $line =~ m/>Paging 1</ )    { push( @metrics, "pg1" ); }
        if ( $line =~ m/>Paging 2</ )    { push( @metrics, "pg2" ); }
        if ( $line =~ m/>LAN</ )         { push( @metrics, "lan" ); }
      }
    }
    if ( $line =~ m/<\/ul>/ ) { last; }
  }

  return @metrics;
}

sub find_datastore_metrics {
  my $query_string = shift;

  $ENV{'QUERY_STRING'} = $query_string;

  chdir("$bindir") || error( "Couldn't change directory to $bindir $!" . __FILE__ . ":" . __LINE__ ) && exit 1;

  #print "detail-cgi.pl  : QUERY_STRING=$ENV{'QUERY_STRING'}\n" if $debug == 9;

  my $ret = `$perl $bindir/detail-cgi.pl 2>$reportsdir/error.log-tmp`;

  if ( -f "$reportsdir/error.log-tmp" ) {
    my $file_size = ( stat("$reportsdir/error.log-tmp") )[9];
    if ( isdigit($file_size) && $file_size > 0 ) {
      open( ERR, "<$reportsdir/error.log-tmp" ) || error( "Couldn't open file $reportsdir/error.log-tmp $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
      my @lines = <ERR>;
      close(ERR);

      foreach my $line (@lines) {
        chomp $line;
        error("ERROR detail-cgi.pl: $line");
      }
    }
    unlink("$reportsdir/error.log-tmp");
  }

  my @metrics;

  my @out = ( split "\n", $ret );
  foreach my $line (@out) {
    if ( $line =~ m/<li/ && $line =~ m/<\/li>/ && $line =~ m/#tabs-[0-9]+/ ) {

      #if ( $line =~ m/>SPACE</ )    { push(@metrics, "dsmem"); }
      #if ( $line =~ m/>DATA</ )     { push(@metrics, "dsrw"); }
      if ( $line =~ m/>Space</ )    { push( @metrics, "dsmem" ); }
      if ( $line =~ m/>Data</ )     { push( @metrics, "dsrw" ); }
      if ( $line =~ m/>IOPS</ )     { push( @metrics, "dsarw" ); }
      if ( $line =~ m/>IOPS\/VM</ ) { push( @metrics, "ds-vmiops" ); }
      if ( $line =~ m/>Latency</ )  { push( @metrics, "dslat" ); }
    }
    if ( $line =~ m/<\/ul>/ ) { last; }
  }

  return @metrics;
}

sub text_item {
  my $item = shift;
  my $type = shift;
  my $text = $item;

  # lpar metrics
  if ( $item eq "lpar" )         { $text = "CPU"; }
  if ( $item eq "trend" )        { $text = "CPU trend"; }
  if ( $item eq "oscpu" )        { $text = "CPU OS"; }
  if ( $item eq "mem" )          { $text = "Memory"; }
  if ( $item eq "pg1" )          { $text = "Paging 1"; }
  if ( $item eq "pg2" )          { $text = "Paging 2"; }
  if ( $item eq "lan" )          { $text = "LAN"; }
  if ( $item eq "san1" )         { $text = "SAN"; }
  if ( $item eq "san2" )         { $text = "SAN IOPS"; }
  if ( $item eq "san_resp" )     { $text = "SAN RESP"; }
  if ( $item eq "sea" )          { $text = "SEA"; }
  if ( $item eq "lparmemalloc" ) { $text = "Memory allocation"; }
  if ( $item eq "queue_cpu" )    { $text = "CPU QUEUE"; }

  # pool metrics
  if ( $item eq "pool-total" )      { $text = "CPU total"; }
  if ( $item eq "pool-total-max" )  { $text = "CPU total max"; }
  if ( $item eq "pool" )            { $text = "CPU"; }
  if ( $item eq "trendpool" )       { $text = "CPU trend"; }
  if ( $item eq "pool-max" )        { $text = "CPU max"; }
  if ( $item eq "trendpool-max" )   { $text = "CPU max trend"; }
  if ( $item eq "lparagg" )         { $text = "LPARs aggregated"; }
  if ( $item eq "shpool" )          { $text = "CPU"; }
  if ( $item eq "trendshpool" )     { $text = "CPU trend"; }
  if ( $item eq "shpool-max" )      { $text = "CPU max"; }
  if ( $item eq "trendshpool-max" ) { $text = "CPU max trend"; }
  if ( $item eq "poolagg" )         { $text = "LPARs aggregated"; }

  # memory metrics
  if ( $item eq "memalloc" )      { $text = "Allocation"; }
  if ( $item eq "trendmemalloc" ) { $text = "Allocation trend"; }
  if ( $item eq "memaggreg" )     { $text = "Aggregated"; }

  # custom groups
  if ( $item eq "custom" )              { $text = "CPU"; }
  if ( $item eq "custom_cpu_trend" )    { $text = "CPU trend"; }
  if ( $item eq "custommem" )           { $text = "MEM allocated"; }
  if ( $item eq "customosmem" )         { $text = "Memory"; }
  if ( $item eq "customoslan" )         { $text = "LAN"; }
  if ( $item eq "customossan1" )        { $text = "SAN"; }
  if ( $item eq "customossan2" )        { $text = "SAN IOPS"; }
  if ( $item eq "customvmmemactive" )   { $text = "MEM Active"; }
  if ( $item eq "customvmmemconsumed" ) { $text = "MEM Granted"; }
  if ( $item eq "customdisk" )          { $text = "DISK"; }
  if ( $item eq "customnet" )           { $text = "NET"; }

  # vm
  if ( $item eq "lpar" && defined $type && $type eq "VM" ) { $text = "CPU GHz"; }
  if ( $item eq "vmw-proc" )                               { $text = "CPU"; }
  if ( $item eq "vmw-mem" )                                { $text = "MEM"; }
  if ( $item eq "vmw-disk" )                               { $text = "DISK"; }
  if ( $item eq "vmw-diskrw" )                             { $text = "DISK"; }
  if ( $item eq "vmw-iops" )                               { $text = "IOPS"; }
  if ( $item eq "vmw-net" )                                { $text = "NET"; }
  if ( $item eq "vmw-netrw" )                              { $text = "NET"; }
  if ( $item eq "vmw-swap" )                               { $text = "SWAP"; }
  if ( $item eq "vmw-comp" )                               { $text = "COMP"; }
  if ( $item eq "vmw-ready" )                              { $text = "CPU READY"; }

  # esxi
  if ( $item eq "lparagg"   && defined $type && $type eq "ESXI" ) { $text = "VMs aggregated"; }
  if ( $item eq "memalloc"  && defined $type && $type eq "ESXI" ) { $text = "Memory allocation"; }
  if ( $item eq "memaggreg" && defined $type && $type eq "ESXI" ) { $text = "Memory aggregated"; }

  # respool
  if ( $item eq "rpcpu" )  { $text = "CPU"; }
  if ( $item eq "rplpar" ) { $text = "CPU VMs"; }
  if ( $item eq "rpmem" )  { $text = "MEMORY"; }

  # datastore
  if ( $item eq "dsmem" )     { $text = "SPACE"; }
  if ( $item eq "dsrw" )      { $text = "DATA"; }
  if ( $item eq "dsarw" )     { $text = "IOPS"; }
  if ( $item eq "ds-vmiops" ) { $text = "IOPS VMs"; }
  if ( $item eq "dslat" )     { $text = "Latency"; }

  # cluster
  if ( $item eq "clustcpu" )    { $text = "CPU"; }
  if ( $item eq "clustlpar" )   { $text = "CPU VMs"; }
  if ( $item eq "clustmem" )    { $text = "MEMORY"; }
  if ( $item eq "clustser" )    { $text = "SERVER"; }
  if ( $item eq "clustlpardy" ) { $text = "CPU READY"; }
  if ( $item eq "clustlan" )    { $text = "LAN"; }

  # oVirt
  if ( $item eq "ovirt_storage_domains_total_aggr_data" )    { $text = "Data"; }
  if ( $item eq "ovirt_storage_domains_total_aggr_latency" ) { $text = "Latency"; }
  if ( $item eq "ovirt_cluster_aggr_host_cpu_core" )         { $text = "CPU"; }
  if ( $item eq "ovirt_cluster_aggr_host_cpu_percent" )      { $text = "CPU %"; }
  if ( $item eq "ovirt_cluster_aggr_host_mem_used" )         { $text = "MEM used"; }
  if ( $item eq "ovirt_cluster_aggr_host_mem_free" )         { $text = "MEM free"; }
  if ( $item eq "ovirt_cluster_aggr_host_mem_used_percent" ) { $text = "MEM used %"; }
  if ( $item eq "ovirt_cluster_aggr_vm_cpu_core" )           { $text = "VM CPU"; }
  if ( $item eq "ovirt_cluster_aggr_vm_cpu_percent" )        { $text = "VM CPU %"; }
  if ( $item eq "ovirt_cluster_aggr_vm_mem_used" )           { $text = "VM MEM used"; }
  if ( $item eq "ovirt_cluster_aggr_vm_mem_free" )           { $text = "VM MEM free"; }
  if ( $item eq "ovirt_cluster_aggr_vm_mem_used_percent" )   { $text = "VM MEM used %"; }
  if ( $item eq "ovirt_host_cpu_core" )                      { $text = "CPU"; }
  if ( $item eq "ovirt_host_cpu_percent" )                   { $text = "CPU %"; }
  if ( $item eq "ovirt_host_mem" )                           { $text = "MEM"; }
  if ( $item eq "ovirt_host_nic_aggr_net" )                  { $text = "Net"; }
  if ( $item eq "ovirt_host_nic_net" )                       { $text = "Net"; }
  if ( $item eq "ovirt_vm_cpu_core" )                        { $text = "CPU"; }
  if ( $item eq "ovirt_vm_cpu_percent" )                     { $text = "CPU %"; }
  if ( $item eq "ovirt_vm_mem" )                             { $text = "MEM"; }
  if ( $item eq "ovirt_vm_aggr_net" )                        { $text = "Net"; }
  if ( $item eq "ovirt_vm_aggr_data" )                       { $text = "Data"; }
  if ( $item eq "ovirt_vm_aggr_latency" )                    { $text = "Latency"; }
  if ( $item eq "ovirt_storage_domain_space" )               { $text = "Space"; }
  if ( $item eq "ovirt_storage_domain_aggr_data" )           { $text = "Data"; }
  if ( $item eq "ovirt_storage_domain_aggr_latency" )        { $text = "Latency"; }
  if ( $item eq "ovirt_disk_data" )                          { $text = "Data"; }
  if ( $item eq "ovirt_disk_latency" )                       { $text = "Latency"; }
  if ( $item eq "custom_ovirt_vm_cpu_percent" )              { $text = "CPU %"; }
  if ( $item eq "custom_ovirt_vm_cpu_core" )                 { $text = "CPU cores"; }
  if ( $item eq "custom_ovirt_vm_memory_used" )              { $text = "MEM used"; }
  if ( $item eq "custom_ovirt_vm_memory_free" )              { $text = "MEM free"; }
  if ( $item eq "custom-xenvm-cpu-percent" )                 { $text = "CPU %"; }
  if ( $item eq "custom-xenvm-cpu-cores" )                   { $text = "CPU"; }
  if ( $item eq "custom-xenvm-memory-used" )                 { $text = "MEM used"; }
  if ( $item eq "custom-xenvm-memory-free" )                 { $text = "MEM free"; }
  if ( $item eq "custom-xenvm-vbd" )                         { $text = "Data"; }
  if ( $item eq "custom-xenvm-vbd-iops" )                    { $text = "IOPS"; }
  if ( $item eq "custom-xenvm-vbd-latency" )                 { $text = "Latency"; }
  if ( $item eq "custom-xenvm-lan" )                         { $text = "Net"; }

  # solaris
  if ( $item eq "jobs" )                  { $text = "JOB CPU"; }
  if ( $item eq "jobs_mem" )              { $text = "JOB MEM"; }
  if ( $item eq "solaris_ldom_cpu" )      { $text = "CPU"; }
  if ( $item eq "solaris_ldom_mem" )      { $text = "MEM"; }
  if ( $item eq "solaris_ldom_agg_c" )    { $text = "CPU"; }
  if ( $item eq "solaris_ldom_agg_m" )    { $text = "MEM"; }
  if ( $item eq "solaris_ldom_san1" )     { $text = "SAN"; }
  if ( $item eq "solaris_ldom_san2" )     { $text = "SAN IOPS"; }
  if ( $item eq "solaris_ldom_san_resp" ) { $text = "SAN RESP"; }
  if ( $item eq "solaris_ldom_cpu" )      { $text = "CPU"; }
  if ( $item eq "solaris_ldom_mem" )      { $text = "MEM"; }
  if ( $item eq "solaris_ldom_net" )      { $text = "NET"; }
  if ( $item eq "solaris_ldom_vnet" )     { $text = "VNET"; }
  if ( $item eq "solaris_zone_cpu" )      { $text = "CPU"; }
  if ( $item eq "solaris_zone_os_cpu" )   { $text = "CPU percent"; }
  if ( $item eq "solaris_zone_mem" )      { $text = "Memory"; }
  if ( $item eq "solaris_zone_net" )      { $text = "Net"; }

  # TOP csv, Resource Configuration Advisor
  if ( $item eq "rep_cpu"     && defined $type && ( $type eq "TOP" || $type eq "RCA" ) ) { $text = "CPU"; }
  if ( $item eq "rep_saniops" && defined $type && ( $type eq "TOP" || $type eq "RCA" ) ) { $text = "SAN-IOPS"; }
  if ( $item eq "rep_san"     && defined $type && ( $type eq "TOP" || $type eq "RCA" ) ) { $text = "SAN"; }
  if ( $item eq "rep_lan"     && defined $type && ( $type eq "TOP" || $type eq "RCA" ) ) { $text = "LAN"; }
  if ( $item eq "rep_mem"     && defined $type && ( $type eq "TOP" || $type eq "RCA" ) ) { $text = "MEM"; }

  # Hyper-V
  if ( $item eq "hyp-cpu" )                                       { $text = "CPU"; }
  if ( $item eq "hyp-mem" )                                       { $text = "MEM"; }
  if ( $item eq "hyp-disk" )                                      { $text = "DISK"; }
  if ( $item eq "hyp-net" )                                       { $text = "LAN"; }
  if ( $item eq "hyp_clustsercpu" )                               { $text = "CPU"; }
  if ( $item eq "hyp_clustservms" )                               { $text = "CPU VMs"; }
  if ( $item eq "hyp_clustsermem" )                               { $text = "MEM"; }
  if ( $item eq "hyp_clustser" )                                  { $text = "NODES"; }
  if ( $item eq "hdt_data" )                                      { $text = "DATA"; }
  if ( $item eq "hdt_io" )                                        { $text = "IO"; }
  if ( $item eq "lfd_cat_" )                                      { $text = "Capacity"; }
  if ( $item eq "lfd_dat_" )                                      { $text = "Data"; }
  if ( $item eq "lfd_io_" )                                       { $text = "IO"; }
  if ( $item eq "lfd_lat_" )                                      { $text = "Latency"; }
  if ( $item eq "lparagg" && defined $type && $type eq "HYPERV" ) { $text = "VMs aggregated"; }
  if ( $item eq "hyppg1" && defined $type && $type eq "HYPERV" )  { $text = "Paging"; }
  if ( $item eq "vmnetrw" && defined $type && $type eq "HYPERV" ) { $text = "LAN"; }

  # Nutanix
  if ( $item eq "nutanix-host-cpu-percent" )         { $text = "Host CPU percent"; }
  if ( $item eq "nutanix-host-cpu-cores" )           { $text = "Host CPU cores"; }
  if ( $item eq "nutanix-host-memory" )              { $text = "Host MEM"; }
  if ( $item eq "nutanix-disk-vbd" )                 { $text = "Storage data"; }
  if ( $item eq "nutanix-disk-vbd-iops" )            { $text = "Storage IOPS"; }
  if ( $item eq "nutanix-disk-vbd-latency" )         { $text = "Storage latency"; }
  if ( $item eq "nutanix-lan" )                      { $text = "Host LAN"; }
  if ( $item eq "nutanix-vm-cpu-percent" )           { $text = "VM CPU percent"; }
  if ( $item eq "nutanix-vm-cpu-cores" )             { $text = "VM CPU cores"; }
  if ( $item eq "nutanix-vm-memory" )                { $text = "VM MEM"; }
  if ( $item eq "nutanix-vm-vbd" )                   { $text = "VM Disk data"; }
  if ( $item eq "nutanix-vm-vbd-iops" )              { $text = "VM Disk IOPS"; }
  if ( $item eq "nutanix-vm-vbd-latency" )           { $text = "VM Disk latency"; }
  if ( $item eq "nutanix-vm-lan" )                   { $text = "VM LAN"; }
  if ( $item eq "nutanix-host-cpu-percent-aggr" )    { $text = "Host CPU percent aggregated"; }
  if ( $item eq "nutanix-host-cpu-cores-aggr" )      { $text = "Host CPU cores aggregated"; }
  if ( $item eq "nutanix-host-memory-free-aggr" )    { $text = "Host MEM free aggregated"; }
  if ( $item eq "nutanix-host-memory-used-aggr" )    { $text = "Host MEM used aggregated"; }
  if ( $item eq "nutanix-host-vm-cpu-percent-aggr" ) { $text = "VM CPU percent aggregated"; }
  if ( $item eq "nutanix-host-vm-cpu-cores-aggr" )   { $text = "VM CPU cores aggregated"; }
  if ( $item eq "nutanix-host-vm-memory-free-aggr" ) { $text = "VM MEM free aggregated"; }
  if ( $item eq "nutanix-host-vm-memory-used-aggr" ) { $text = "VM MEM used aggregated"; }
  if ( $item eq "nutanix-vm-cpu-percent-aggr" )      { $text = "VM CPU percent aggregated"; }
  if ( $item eq "nutanix-vm-cpu-cores-aggr" )        { $text = "VM CPU cores aggregated"; }
  if ( $item eq "nutanix-vm-memory-free-aggr" )      { $text = "VM MEM free aggregated"; }
  if ( $item eq "nutanix-vm-memory-used-aggr" )      { $text = "VM MEM used aggregated"; }
  if ( $item eq "nutanix-disk-vbd-aggr" )            { $text = "Storage data aggregated"; }
  if ( $item eq "nutanix-disk-vbd-iops-aggr" )       { $text = "Storage IOPS aggregated"; }
  if ( $item eq "nutanix-disk-vbd-latency-aggr" )    { $text = "Storage latency aggregated"; }
  if ( $item eq "nutanix-pool-vbd-aggr" )            { $text = "Storage data aggregated"; }
  if ( $item eq "nutanix-pool-vbd-iops-aggr" )       { $text = "Storage IOPS aggregated"; }
  if ( $item eq "nutanix-pool-vbd-latency-aggr" )    { $text = "Storage latency aggregated"; }
  if ( $item eq "nutanix-lan-traffic-aggr" )         { $text = "Host LAN aggregated"; }
  if ( $item eq "nutanix-disk-vbd-sp-aggr" )         { $text = "Storage Pool data aggregated"; }
  if ( $item eq "nutanix-disk-vbd-iops-sp-aggr" )    { $text = "Storage Pool IOPS aggregated"; }
  if ( $item eq "nutanix-disk-vbd-latency-sp-aggr" ) { $text = "Storage Pool latency aggregated"; }
  if ( $item eq "nutanix-disk-vbd-sc-aggr" )         { $text = "Storage Containers data aggregated"; }
  if ( $item eq "nutanix-disk-vbd-iops-sc-aggr" )    { $text = "Storage Containers IOPS aggregated"; }
  if ( $item eq "nutanix-disk-vbd-latency-sc-aggr" ) { $text = "Storage Containers latency aggregated"; }
  if ( $item eq "nutanix-disk-vbd-vd-aggr" )         { $text = "Volume Groups data aggregated"; }
  if ( $item eq "nutanix-disk-vbd-iops-vd-aggr" )    { $text = "Volume Groups IOPS aggregated"; }
  if ( $item eq "nutanix-disk-vbd-latency-vd-aggr" ) { $text = "Volume Groups latency aggregated"; }
  if ( $item eq "nutanix-disk-vbd-sr-aggr" )         { $text = "Disk data aggregated"; }
  if ( $item eq "nutanix-disk-vbd-iops-sr-aggr" )    { $text = "Disk IOPS aggregated"; }
  if ( $item eq "nutanix-disk-vbd-latency-sr-aggr" ) { $text = "Disk latency aggregated"; }
  if ( $item eq "nutanix-vm-vbd-aggr" )              { $text = "VM data aggregated"; }
  if ( $item eq "nutanix-vm-vbd-iops-aggr" )         { $text = "VM IOPS aggregated"; }
  if ( $item eq "nutanix-vm-vbd-latency-aggr" )      { $text = "VM latency aggregated"; }
  if ( $item eq "nutanix-vm-lan-aggr" )              { $text = "VM LAN aggregated"; }
  if ( $item eq "custom-nutanixvm-cpu-percent" )     { $text = "VM CPU percent aggregated"; }
  if ( $item eq "custom-nutanixvm-cpu-cores" )       { $text = "VM CPU cores aggregated"; }
  if ( $item eq "custom-nutanixvm-memory-used" )     { $text = "VM MEM used aggregated"; }
  if ( $item eq "custom-nutanixvm-memory-free" )     { $text = "VM MEM free aggregated"; }
  if ( $item eq "custom-nutanixvm-vbd" )             { $text = "VM Disk data aggregated"; }
  if ( $item eq "custom-nutanixvm-vbd-iops" )        { $text = "VM Disk IOPS aggregated"; }
  if ( $item eq "custom-nutanixvm-vbd-latency" )     { $text = "VM Disk latency aggregated"; }
  if ( $item eq "custom-nutanixvm-lan" )             { $text = "VM LAN aggregated"; }

  return $text;
}

sub translate_shpool_id {
  my $server = shift;
  my $id     = shift;
  my $name   = $id;

  $id =~ s/^SharedPool//;

  opendir( DIR, "$wrkdir/$server" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
  my @hmc_list = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);
  chomp @hmc_list;

  foreach my $hmc (@hmc_list) {
    if ( -f "$wrkdir/$server/$hmc/cpu-pools-mapping.txt" ) {
      open( POOL, "< $wrkdir/$server/$hmc/cpu-pools-mapping.txt" ) || error( "Couldn't open file $wrkdir/$server/$hmc/cpu-pools-mapping.txt $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
      my @cfg = <POOL>;
      close(POOL);
      chomp @cfg;

      foreach my $line (@cfg) {
        my ( $id_n, $name_n ) = split( ",", $line );
        if ( $id eq $id_n ) {
          return $name_n;
        }
      }
    }
  }

  return $name;
}

sub set_topten_time_range {
  my $sunix = "";
  my $eunix = "";
  my $sdate = "";
  my $edate = "";
  my $time  = "";

  if ( $topten_timerange eq "day" ) {
    ( $sunix, $eunix ) = set_report_time_range( "daily", "last" );
    $time = "d";
  }
  elsif ( $topten_timerange eq "week" ) {
    ( $sunix, $eunix ) = set_report_time_range( "weekly", "last" );
    $time = "w";
  }
  elsif ( $topten_timerange eq "month" ) {
    ( $sunix, $eunix ) = set_report_time_range( "monthly", "last" );
    $time = "m";
  }
  elsif ( $topten_timerange eq "year" ) {
    ( $sunix, $eunix ) = set_report_time_range( "yearly", "last" );
    $time = "y";
  }
  else {
    error("Unknown toptimerange : $topten_timerange!");
  }
  my ( $sec_s, $min_s, $hour_s, $day_s, $month_s, $year_s, $wday_s, $yday_s, $isdst_s ) = localtime($sunix);
  $sdate = sprintf( "%02d:%02d:%02d %02d.%02d.%4d", $hour_s, $min_s, $sec_s, $day_s, $month_s + 1, $year_s + 1900 );

  my ( $sec_e, $min_e, $hour_e, $day_e, $month_e, $year_e, $wday_e, $yday_e, $isdst_e ) = localtime($eunix);
  $edate = sprintf( "%02d:%02d:%02d %02d.%02d.%4d", $hour_e, $min_e, $sec_e, $day_e, $month_e + 1, $year_e + 1900 );

  return ( $sunix, $eunix, $sdate, $edate, $time );
}

sub make_pdf_report_lpar {
  my $report_name = shift;
  my $user_name   = shift;
  my $sunix       = shift;
  my $eunix       = shift;
  my $sdate       = shift;
  my $edate       = shift;
  my $time        = shift;

  my $report_name_space = $report_name;
  $report_name_space =~ s/\s/_/g;

  # test if user is configured
  if ( !exists $users{users}{$user_name} && !exists $users_xormon{users}{$user_name} ) {
    error( "User \"$user_name\" is no longer configured! Report \"$report_name\" skipped... $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  #
  # Report variables
  #
  my $png_height_orig = 150;
  my $png_width_orig  = 620;
  my $png_height      = $png_height_orig;
  my $png_width       = $png_width_orig;
  my $detail          = 10;

  #
  # Report dir
  #
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime();
  my $act_time2name = sprintf( "%4d%02d%02d_%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
  my $report_dir    = "$reportsdir/$user_name/$report_name_space";

  if ( !-d "$reportsdir/$user_name" ) {
    mkdir( "$reportsdir/$user_name", 0777 ) || error( "Cannot mkdir $reportsdir/$user_name: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }
  if ( !-d $report_dir ) {
    mkdir( "$report_dir", 0777 ) || error( "Cannot mkdir $report_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }

  #
  # progress bar, inventory for all graphs
  #
  my %graphs = get_list_of_graphs( "$user_name", "$report_name" );

  #
  # Make report / Create PNG
  #
  my $pdf_name = "$report_name_space-$act_time2name.pdf";
  my %pdf_sections;

  if ( -d "$report_dir/PDF-tmp" ) {
    remove_files("$report_dir/PDF-tmp");
  }
  if ( !-d "$report_dir/PDF-tmp" ) {
    mkdir( "$report_dir/PDF-tmp", 0777 ) || error( "Cannot mkdir $report_dir/PDF-tmp: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }

  # set new timerange for graphs
  if ( $topten_bookmarks == 1 ) {
    ( $sunix, $eunix, $sdate, $edate, $time ) = set_topten_time_range();
  }

  #print Dumper \%graphs;
  $done = 0;
  foreach my $graph_idx ( sort { $a <=> $b } keys %graphs ) {
    my $params = $graphs{$graph_idx};
    my ( $img_name, $query_string_act, $host, $subsys, $name, $metric ) = set_query_string_img( "$png_height", "$png_width", "$detail", "$sunix", "$eunix", "$time", \%$params );
    if ( $img_name && $query_string_act ) {
      get_img_stor( "$report_dir/PDF-tmp/$img_name", "$query_string_act" );
      if ( $topten_bookmarks == 1 ) {
        $pdf_sections{$metric}{$host}{$subsys}{$done}{$name}{"$report_dir/PDF-tmp/$img_name"} = "$report_dir/PDF-tmp/$img_name";
      }
      else {
        $pdf_sections{$host}{$subsys}{$name}{$done}{$metric}{"$report_dir/PDF-tmp/$img_name"} = "$report_dir/PDF-tmp/$img_name";
      }
    }
    else {
      error( "Can't create QUERY_STRING for: user=$user_name,report=$report_name,metric=$params->{metric} : " . __FILE__ . ":" . __LINE__ );
      error( "Item parameters: " . encode_json( \%$params ) );
    }
    $done++;
    %status = ( status => "pending", count => $count, done => $done );
    write_file( "/tmp/lrep-$pid.status", encode_json( \%status ) );
  }

  print "create PDF     : $report_dir/$pdf_name\n" if $debug == 9;
  create_pdf( "$pdf_name", "$report_dir/$pdf_name", "$report_dir/PDF-tmp", "$png_height_orig", "$png_width_orig", "$sdate", "$edate", "$report_name", \%pdf_sections );

  # remove PDF dir
  if ( -d "$report_dir/PDF-tmp" ) {
    remove_files("$report_dir/PDF-tmp");
  }
  if ( !-f "$report_dir/$pdf_name" ) {
    error( "Something wrong! PDF does not exists! \"$report_dir/$pdf_name\" $!" . __FILE__ . ":" . __LINE__ ) && return;
  }
  else {
    set_permissions( "$report_dir/$pdf_name", 0664 );
  }

  #
  # Send report via email
  #
  my $emails_count = 0;
  if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} && ref( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} ) eq "ARRAY" ) {
    foreach ( @{ $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} } ) {
      if ( exists $cfg{'users'}{$user_name}{'groups'}{$_}{'emails'} && ref( $cfg{'users'}{$user_name}{'groups'}{$_}{'emails'} ) eq "ARRAY" ) {
        foreach ( @{ $cfg{'users'}{$user_name}{'groups'}{$_}{'emails'} } ) {
          $emails_count++;
        }
      }
    }
  }
  print "emails found   : $emails_count\n" if $debug == 9;
  if ( $emails_count > 0 && -f "$report_dir/$pdf_name" ) {

    # send email with attached pdf file
    my $subject   = "$product: $report_name";
    my $mailprog  = "/usr/sbin/sendmail";
    my $boundary  = "===" . time . "===";
    my $mail_from = "";
    my @att_files;

    open( PDF, "<$report_dir/$pdf_name" ) || error( "Couldn't open file $report_dir/$pdf_name $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
    my $attachment_file = join( "", <PDF> );
    my $attachment_data = encode_base64($attachment_file);
    close(PDF);

    my %attachments;
    $attachments{$pdf_name}{'data'}         = $attachment_data;
    $attachments{$pdf_name}{'Content-Type'} = "application/pdf";

    print "attachment     : Content-Type=\"application/pdf\",filename=\"$pdf_name\"\n" if $debug == 9;
    push @att_files, "$report_dir/$pdf_name";

    if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} && ref( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} ) eq "ARRAY" ) {
      foreach my $group ( @{ $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} } ) {
        if ( exists $cfg{'users'}{$user_name}{'groups'}{$group}{'mailfrom'} && $cfg{'users'}{$user_name}{'groups'}{$group}{'mailfrom'} ne '' ) {
          $mail_from = $cfg{'users'}{$user_name}{'groups'}{$group}{'mailfrom'};
        }
        else {
          $mail_from = $mail_from_default;
        }
        if ( exists $cfg{'users'}{$user_name}{'groups'}{$group}{'emails'} && ref( $cfg{'users'}{$user_name}{'groups'}{$group}{'emails'} ) eq "ARRAY" ) {
          foreach my $mail_to ( @{ $cfg{'users'}{$user_name}{'groups'}{$group}{'emails'} } ) {
            print "send email to  : group=\"$group\" email=\"$mail_to\" from=\"$mail_from\"\n" if $debug == 9;
            Xorux_lib::send_email( $mail_to, $mail_from, $subject, $message_body, \@att_files );
          }
        }
      }
    }
  }

  #
  # Print location of output files
  #
  if ( -f "$report_dir/$pdf_name" ) {
    print "download       : $report_dir/$pdf_name\n" if $debug == 9;
    print "stored report  : $report_dir/$pdf_name\n" if $debug == 9;
  }
  else {
    error( "Something wrong! PDF does not exists! \"$report_dir/$pdf_name\" $!" . __FILE__ . ":" . __LINE__ );
  }

  return 1;
}

sub create_pdf {
  my $pdf_name    = shift;
  my $pdf_file    = shift;
  my $png_dir     = shift;
  my $png_height  = shift;
  my $png_width   = shift;
  my $sdate       = shift;
  my $edate       = shift;
  my $report_name = shift;
  my $sect_hash   = shift;
  my %sections    = %{$sect_hash};

  #use PDF::API2;
  eval 'use PDF::API2; 1';

  use constant mm   => 25.4 / 72;    # 25.4 mm in an inch, 72 points in an inch
  use constant in   => 1 / 72;       # 72 points in an inch
  use constant pt   => 1;            # 1 point
  use constant A4_x => 210 / mm;     # x points in an A4 page ( 595.2755 )
  use constant A4_y => 297 / mm;     # y points in an A4 page ( 841.8897 )

  use constant US_x => 216 / mm;     # x points in an US letter page ( 612.2834 )
  use constant US_y => 279 / mm;     # y points in an US letter page ( 790.8661 )

  my $format  = "A4";
  my $pagetop = 796;
  my $pagey   = A4_y;
  my $pagex   = A4_x;

  my $act_time    = localtime();
  my $header_text = "$sdate - $edate";

  #my $header_text = $report_name;

  # Create a blank PDF file
  my $pdf = PDF::API2->new();
  $pdf->info(
    'CreationDate' => $act_time,
    'ModDate'      => $act_time,
    'Creator'      => "reporter.pl",
    'Title'        => "$product report",
    'Subject'      => ""
  );

  my $logo_file = "";
  if ( defined $basedir && $basedir ne '' ) {
    if ( $product eq "LPAR2RRD" ) {
      if ( -f "$basedir/html/css/images/logo-$product_lc.png" ) {
        $logo_file = "$basedir/html/css/images/logo-$product_lc.png";
      }
      else {
        error( "Logo file is not exist! \"$basedir/html/css/images/logo-$product_lc.png\" " . __FILE__ . ":" . __LINE__ ) && exit 1;
      }
    }
  }
  else {
    error( "basedir is not defined!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }
  my $logo  = $pdf->image_png("$logo_file");
  my $font  = $pdf->corefont( 'Helvetica',      -encode => "utf8" );
  my $fontb = $pdf->corefont( 'Helvetica-Bold', -encode => "utf8" );

  my $outline_root = $pdf->outlines;

  # add graphs to pdf page
  my $png_idx = 0;
  if (%sections) {
    foreach my $host ( sort keys(%sections) ) {
      my $host_space = $host;

      if ( $topten_bookmarks == 1 ) { $host_space = text_item($host); }

      my $sect = $outline_root->outline();
      $sect->title("$host_space");

      foreach my $subsys ( keys( %{ $sections{$host} } ) ) {

        my $page = "";
        if ( $png_idx == 0 ) {
          $page    = add_new_page( $pdf, $format, $pagey, $pagex, $logo, $fontb, $font, $header_text, $host_space, $report_name );    # add report name to header only to 1st page
          $pagetop = 768;
        }
        else {
          $page    = add_new_page( $pdf, $format, $pagey, $pagex, $logo, $fontb, $font, $header_text, $host_space );
          $pagetop = 796;
        }
        my $content = $page->gfx();
        my $cntr    = $pagetop;

        # bookmarks
        my $outline = $sect->outline();
        $outline->title("$subsys");
        $outline->dest($page);

        foreach my $name ( sort keys( %{ $sections{$host}{$subsys} } ) ) {

          # bookmarks
          my $outline_last  = $outline->outline();
          my $name2bookmark = $name;
          if ( $name =~ m/^SharedPool[0-9]+$/ ) {    # translate shared pool id to human name
            $name2bookmark = translate_shpool_id( "$host", "$name" );
          }

          my $graph_idx = 0;
          foreach my $item_idx ( sort { $a <=> $b } keys( %{ $sections{$host}{$subsys}{$name} } ) ) {
            foreach my $item ( keys( %{ $sections{$host}{$subsys}{$name}{$item_idx} } ) ) {
              foreach my $png ( keys( %{ $sections{$host}{$subsys}{$name}{$item_idx}{$item} } ) ) {
                $png_idx++;
                $graph_idx++;

                if ( !-f $png ) {
                  error( "Graph for PDF not found! \"$png\" :" . __FILE__ . ":" . __LINE__ ) && next;
                }

                my $dpng    = $pdf->image_png($png);
                my $rwidth  = $dpng->width();
                my $rheight = $dpng->height();

                my $zoomfactor = ( 595 - 60 ) / $rwidth;

                # $zoomfactor = 0.500;
                my $height_png = $rheight * $zoomfactor;
                my $width_png  = $rwidth * $zoomfactor;

                if ( $png_height > $pagetop ) {
                  $zoomfactor = ( $pagetop - 30 ) / $rheight;
                  $height_png = $rheight * $zoomfactor;
                  $width_png  = $rwidth * $zoomfactor;

                  # print STDERR "PDF generator: image was too big to fit in the page, shrinking...\n";
                  # next;
                }

                if ( ( $cntr - $height_png ) < 24 ) {
                  $page    = add_new_page( $pdf, $format, $pagey, $pagex, $logo, $fontb, $font, $header_text, $host_space );
                  $pagetop = 796;
                  $content = $page->gfx();
                  $cntr    = $pagetop;
                }

                if ( $graph_idx == 1 ) {    # add bookmark for LPAR only at first page
                                            # bookmarks
                                            #$outline_last = $outline->outline();
                  $outline_last->title("$name2bookmark");
                  $outline_last->dest($page);
                }

                # bookmarks
                my $outline_item    = $outline_last->outline();
                my $item_text_human = text_item( $item, $subsys );
                $outline_item->title("$item_text_human");
                $outline_item->dest($page);

                $content->image( $dpng, 30, $cntr - $height_png, $zoomfactor );

                # close $fh;
                $cntr -= $height_png;
              }
              if ( $png_idx == 0 ) {
                error( "Files for PDF not found! :" . __FILE__ . ":" . __LINE__ );
              }
            }
          }
        }
      }
    }
  }

  # Save the PDF
  $pdf->saveas("$pdf_file");

  return 1;
}

sub add_new_page {
  my $pdf         = shift;
  my $format      = shift;
  my $pagey       = shift;
  my $pagex       = shift;
  my $logo        = shift;
  my $fontb       = shift;
  my $font        = shift;
  my $header_text = shift;
  my $section     = shift;
  my $report_name = shift;

  my $page = $pdf->page();
  $page->mediabox($format);

  my $count    = $pdf->pages();
  my $grey_box = $page->gfx(1);
  if ( defined $report_name && $report_name ne '' ) {
    $grey_box->fillcolor('#0B2F3A');
  }
  else {
    $grey_box->fillcolor('#555');
  }
  $grey_box->strokecolor('#222');
  $grey_box->rect(
    80 * mm,                  # left
    $pagey - ( 130 * mm ),    # bottom
    $pagex - ( 140 * mm ),    # width
    70 * mm                   # height
  );

  if ( defined $report_name && $report_name ne '' ) {
    my $grey_box2 = $page->gfx(1);
    $grey_box2->fillcolor('#555');
    $grey_box2->strokecolor('#222');
    $grey_box2->rect(
      80 * mm,                  # left
      $pagey - ( 205 * mm ),    # bottom
      $pagex - ( 140 * mm ),    # width
      70 * mm                   # height
    );

    $grey_box2->fill;
  }

  $grey_box->fill;

  my $logo_box = $page->gfx();
  $logo_box->image( $logo, 12, 12, 0.35 );

  my $prod_link = $page->annotation();
  my $prod_url  = "http://www.$product_lc.com";
  my %options   = (
    -border => [ 0,  0,  0 ],
    -rect   => [ 12, 12, 80, 30 ]
  );
  $prod_link->url( $prod_url, %options );

  # Add some text to the page
  my $text = $page->text();

  #$text->font( $fontb, 15 );
  $text->font( $fontb, 10 );
  $text->fillcolor("white");
  if ( defined $report_name && $report_name ne '' ) {
    $text->translate( 365, $pagey - 64 );
  }
  else {
    $text->translate( 365, $pagey - 38 );
  }
  $text->text($header_text);

  # Add some text to the page
  my $text_section = $page->text();

  #$text_section->font( $fontb, 15 );
  $text_section->font( $fontb, 12 );
  $text_section->fillcolor("white");
  if ( defined $report_name && $report_name ne '' ) {
    $text_section->translate( 40, $pagey - 64 );
  }
  else {
    $text_section->translate( 40, $pagey - 38 );
  }
  $text_section->text($section);

  # report name in the first page header
  if ( defined $report_name && $report_name ne '' ) {
    my $text_rep = $page->text();
    $text_rep->font( $fontb, 15 );
    $text_rep->fillcolor("white");
    $text_rep->translate( 40, $pagey - 39 );
    $text_rep->text($report_name);
  }

  my $act_date  = localtime();
  my $paragraph = "Generated from $product version $ENV{version} $act_date                                                              Page $count";
  my $footer    = $page->text;
  $footer->textstart;
  $footer->lead(7);
  $footer->font( $font, 7 );
  $footer->fillcolor('navy');

  #$footer->translate( 560, 14 );
  $footer->translate( 550, 24 );
  $footer->section( "$paragraph", 400, 16, -align => "right" );

  return $page;
}

sub make_img_report_lpar {
  my $report_name = shift;
  my $user_name   = shift;
  my $sunix       = shift;
  my $eunix       = shift;
  my $time        = shift;

  my $report_name_space = $report_name;
  $report_name_space =~ s/\s/_/g;

  # test if user is configured
  if ( !exists $users{users}{$user_name} && !exists $users_xormon{users}{$user_name} ) {
    error( "User \"$user_name\" is no longer configured! Report \"$report_name\" skipped... $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  #
  # Report variables
  #
  my $zip_report = 0;
  my $png_height = 150;
  my $png_width  = 620;
  my $detail     = 10;

  if ( defined $ENV{RRDHEIGHT} && isdigit( $ENV{RRDHEIGHT} ) && defined $ENV{RRDWIDTH} && isdigit( $ENV{RRDWIDTH} ) ) {
    $png_height = $ENV{RRDHEIGHT};
    $png_width  = $ENV{RRDWIDTH};
  }
  if ( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'zipattach'} ) { $zip_report = 1; }
  print "zipattach      : $zip_report\n" if $debug == 9;

  #
  # Report dir
  #
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime();
  my $act_time2name  = sprintf( "%4d%02d%02d_%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
  my $report_dir     = "$reportsdir/$user_name/$report_name_space";
  my $act_report_dir = "$report_dir/$act_time2name";

  if ( !-d "$reportsdir/$user_name" ) {
    mkdir( "$reportsdir/$user_name", 0777 ) || error( "Cannot mkdir $reportsdir/$user_name: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }
  if ( !-d $report_dir ) {
    mkdir( "$report_dir", 0777 ) || error( "Cannot mkdir $report_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }
  if ( !-d $act_report_dir ) {
    mkdir( "$act_report_dir", 0777 ) || error( "Cannot mkdir $act_report_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  }

  #
  # progress bar, inventory for all graphs
  #
  my %graphs = get_list_of_graphs( "$user_name", "$report_name" );

  # set new timerange for graphs
  if ( $topten_bookmarks == 1 ) {
    ( $sunix, $eunix, undef, undef, $time ) = set_topten_time_range();
  }

  #
  # Make report / Create PNG
  #
  #print Dumper \%graphs;
  $done = 0;
  foreach my $graph_idx ( sort { $a <=> $b } keys %graphs ) {
    my $params = $graphs{$graph_idx};
    my ( $img_name, $query_string_act ) = set_query_string_img( "$png_height", "$png_width", "$detail", "$sunix", "$eunix", "$time", \%$params );
    if ( $img_name && $query_string_act ) {
      get_img_stor( "$act_report_dir/$img_name", "$query_string_act" );
    }
    else {
      error( "Can't create QUERY_STRING for: user=$user_name,report=$report_name,metric=$params->{metric} : " . __FILE__ . ":" . __LINE__ );
      error( "Item parameters: " . encode_json( \%$params ) );
    }
    $done++;
    %status = ( status => "pending", count => $count, done => $done );
    write_file( "/tmp/lrep-$pid.status", encode_json( \%status ) );
  }

  #
  # Zip file
  #
  my $zip_file_name = "$report_name_space-$act_time2name.zip";
  my $zip_file      = "$report_dir/$zip_file_name";
  my $ret           = zip_file( "$zip_file", "$user_name/$report_name_space/$act_time2name", "$reportsdir" );
  if ( !-f $zip_file ) {
    error( "Something wrong, zip file does not exists!" . __FILE__ . ":" . __LINE__ ) && return;
  }
  else {
    set_permissions( "$zip_file", 0664 );
  }

  #
  # Send report via email
  #
  my $emails_count = 0;
  my %attachments;
  if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} && ref( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} ) eq "ARRAY" ) {
    foreach ( @{ $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} } ) {
      if ( exists $cfg{'users'}{$user_name}{'groups'}{$_}{'emails'} && ref( $cfg{'users'}{$user_name}{'groups'}{$_}{'emails'} ) eq "ARRAY" ) {
        foreach ( @{ $cfg{'users'}{$user_name}{'groups'}{$_}{'emails'} } ) {
          $emails_count++;
        }
      }
    }
  }
  print "emails found   : $emails_count\n" if $debug == 9;
  if ( $emails_count > 0 ) {
    #
    # Set attachments
    #
    my @att_files;
    my @att_names;
    if ( defined $zip_report && isdigit($zip_report) && $zip_report == 1 ) {
      if ( -f $zip_file ) {

        print "attachment     : Content-Type=\"application/zip\",filename=\"$zip_file_name\"\n" if $debug == 9;
        push @att_files, $zip_file;
        push @att_names, $zip_file_name;
      }
    }
    else {    # send email with attached single graphs
      opendir( DIR, "$act_report_dir" ) || error( " directory does not exists : $act_report_dir" . __FILE__ . ":" . __LINE__ ) && exit 1;
      my @files = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);

      foreach my $file (@files) {
        chomp $file;

        chdir("$act_report_dir") || error( "Couldn't change directory to $act_report_dir $!" . __FILE__ . ":" . __LINE__ ) && exit;
        push @att_files, $file;
        push @att_names, $file;

        print "attachment     : Content-Type=\"image/png\",filename=\"$file\"\n" if $debug == 9;
      }
    }
    my $subject   = "$product: $report_name";
    my $mail_from = "";

    if ( exists $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} && ref( $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} ) eq "ARRAY" ) {
      foreach my $group ( @{ $cfg{'users'}{$user_name}{'reports'}{$report_name}{'recipients'} } ) {
        if ( exists $cfg{'users'}{$user_name}{'groups'}{$group}{'mailfrom'} && $cfg{'users'}{$user_name}{'groups'}{$group}{'mailfrom'} ne '' ) {
          $mail_from = $cfg{'users'}{$user_name}{'groups'}{$group}{'mailfrom'};
        }
        else {
          $mail_from = $mail_from_default;
        }
        if ( exists $cfg{'users'}{$user_name}{'groups'}{$group}{'emails'} && ref( $cfg{'users'}{$user_name}{'groups'}{$group}{'emails'} ) eq "ARRAY" ) {
          foreach my $mail_to ( @{ $cfg{'users'}{$user_name}{'groups'}{$group}{'emails'} } ) {
            print "send email to  : group=\"$group\" email=\"$mail_to\" from=\"$mail_from\"\n" if $debug == 9;
            Xorux_lib::send_email( $mail_to, $mail_from, $subject, $message_body, \@att_files, \@att_names );
          }
        }
      }
    }
  }

  #
  # Print location of output files
  #
  if ( -f $zip_file ) {
    print "download       : $zip_file\n" if $debug == 9;
    print "stored zip     : $zip_file\n" if $debug == 9;
  }
  else {
    error( "Something wrong, zip file does not exists!" . __FILE__ . ":" . __LINE__ );
  }
  if ( -d $act_report_dir ) {
    print "stored report  : $act_report_dir\n" if $debug == 9;
  }
  else {
    error( "Something wrong, report directory does not exists!" . __FILE__ . ":" . __LINE__ );
  }

  return 1;
}

sub set_query_string_img {
  my $png_height = shift;
  my $png_width  = shift;
  my $detail     = shift;
  my $sunix      = shift;
  my $eunix      = shift;
  my $time       = shift;
  my $params     = shift;

  my $query_string_act = "";
  my $img_name         = "";
  my $hmc              = "";
  my $host             = "";
  my $subsys           = "";
  my $name             = "";
  my $name2bookmark    = "";

  my $metric = $params->{'metric'};

  #
  # IBM POWER
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "POWER" && exists $params->{'subsys'} && exists $params->{'hmc'} && exists $params->{'host'} && exists $params->{'name'} ) {
    $hmc           = $params->{'hmc'};
    $host          = $params->{'host'};
    $subsys        = $params->{'subsys'};
    $name          = $params->{'name'};
    $name2bookmark = $params->{'name'};
    $img_name      = "$host\_$subsys\_$name\_$metric.png";

    # LPAR graphs : lpar (hmc cpu), oscpu, mem, pg1, pg2, lan, san1, san2
    if ( $params->{'subsys'} eq "LPAR" ) {
      if ( $metric eq "trend" ) {    # lpar cpu (hmc) trend
                                     #host=hmc&server=P02DR%5F%5F9117-MMC-SN44K8102&lpar=Accept&item=trend&time=y&type_sam=m&detail=0&upper=0.635&entitle=0&none=-1540542675
        $query_string_act = "host=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&time=y&type_sam=m&detail=$detail&height=$png_height&width=$png_width";
      }
      else {
        if ( $metric eq "lpar" ) {
          $img_name = "$host\_$subsys\_$name\_cpu.png";
        }
        $query_string_act = "host=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&time=$time&type_sam=m&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
      }
    }

    # CPU pool, shared pool : pool, lparagg
    if ( $params->{'subsys'} eq "POOL" ) {
      if ( $name eq "pool" ) {
        $img_name      = "$host\_$subsys\_CPUPOOL_$metric.png";
        $name2bookmark = "CPU POOL";
      }
      if ( $name =~ m/^SharedPool[0-9]+$/ ) {    # translate shared pool id to human name
        my $shpool_n = translate_shpool_id( "$host", "$name" );
        $img_name = "$host\_$subsys\_$shpool_n\_$metric.png";
      }
      if ( $metric =~ m/^trend/ ) {
        $query_string_act = "host=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&time=y&type_sam=m&detail=$detail&height=$png_height&width=$png_width";
      }
      else {
        if ( $metric eq "lparagg" ) { $name = "pool-multi"; }

        $query_string_act = "host=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&time=$time&type_sam=m&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
      }
    }

    # SERVER memory
    if ( $params->{'subsys'} eq "SERVER" ) {
      if ( $metric eq "memalloc" || $metric eq "memaggreg" || $metric eq "trendmemalloc" ) {
        $name          = "cod";
        $name2bookmark = "MEMORY";
        $img_name      = "$host\_$subsys\_MEMORY_$metric.png";
      }
      if ( $metric eq "pagingagg" ) {
        $name          = "cod";
        $name2bookmark = "PAGING";
        $img_name      = "$host\_$subsys\_PAGING_$metric.png";
      }
      if ( $metric eq "trendmemalloc" ) {
        $query_string_act = "host=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&time=y&type_sam=m&detail=$detail&height=$png_height&width=$png_width";
      }
      else {
        $query_string_act = "host=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&time=$time&type_sam=m&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
      }
    }
  }

  #
  # CUSTOM GROUPS
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "CUSTOM" && exists $params->{'subsys'} && exists $params->{'host'} ) {
    $host          = "na";
    $hmc           = "na";
    $subsys        = $params->{'subsys'};
    $name          = $params->{'host'};
    $name2bookmark = $params->{'host'};
    $img_name      = "CUSTOM-GROUP_$name\_$metric.png";

    if ( $params->{'subsys'} eq "VM" )      { $hmc = "VMware"; }
    if ( $params->{'subsys'} eq "OVIRTVM" ) { $hmc = "oVirt"; }

    #if ( $params->{'subsys'} eq "NUTANIXVM" )   { $hmc = "Nutanix"; }
    if ( $params->{'subsys'} eq "XENVM" )       { $hmc = "XenServer"; }
    if ( $params->{'subsys'} eq "SOLARISLDOM" ) { $hmc = "Solaris"; }
    if ( $params->{'subsys'} eq "SOLARISZONE" ) { $hmc = "Solaris"; }
    if ( $params->{'subsys'} eq "HYPERVM" )     { $hmc = "Hyperv"; }
    if ( $params->{'subsys'} eq "LINUX" )       { $hmc = "Linux"; }

    if ( $metric eq "custom_cpu_trend" ) {
      $query_string_act = "host=$hmc&server=$host&lpar=" . urlencode("$name") . "&item=$metric&time=y&type_sam=m&detail=$detail&height=$png_height&width=$png_width";
    }
    else {
      $query_string_act = "host=$hmc&server=$host&lpar=" . urlencode("$name") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
    }

    # add following info to bookmarks
    $host = "CUSTOM GROUPS";
  }

  #
  # VMWARE
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "VMWARE" && exists $params->{'subsys'} ) {
    if ( $params->{'subsys'} eq "VM" ) {
      $host          = "$params->{'vcenter'} - $params->{cluster}";
      $subsys        = $params->{'subsys'};
      $name2bookmark = $params->{'vm_name'};
      $img_name      = "$params->{vcenter}\_$params->{cluster}\_$subsys\_$params->{'vm_name'}\_$metric.png";

      $query_string_act = "host=" . urlencode("$params->{'host'}") . "&server=" . urlencode("$params->{'server'}") . "&lpar=" . urlencode("$params->{'vm_uuid'}") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width&d_platform=VMware";
    }
    if ( $params->{'subsys'} eq "ESXI" ) {
      $host          = "$params->{'vcenter'} - $params->{cluster}";
      $subsys        = $params->{'subsys'};
      $name2bookmark = $params->{'server'};
      $img_name      = "$params->{vcenter}\_$params->{cluster}\_$subsys\_$params->{'server'}\_$metric.png";
      my $type_sam = "na";
      if ( $metric eq "pool" ) { $type_sam = "m"; }

      $query_string_act = "host=" . urlencode("$params->{'host'}") . "&server=" . urlencode("$params->{'server'}") . "&lpar=" . urlencode("$params->{'lpar'}") . "&item=$metric&time=$time&type_sam=$type_sam&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width&d_platform=VMware";
    }
    if ( $params->{'subsys'} eq "RESPOOL" ) {
      $host          = "$params->{'vcenter'} - $params->{cluster}";
      $subsys        = $params->{'subsys'};
      $name2bookmark = $params->{'respool'};
      $img_name      = "$params->{vcenter}\_$params->{cluster}\_$subsys\_$params->{'respool'}\_$metric.png";

      $query_string_act = "host=" . urlencode("$params->{'host'}") . "&server=" . urlencode("$params->{'server'}") . "&lpar=" . urlencode("$params->{'lpar'}") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width&d_platform=VMware";
    }
    if ( $params->{'subsys'} eq "DATASTORE" ) {
      $host          = "$params->{'vcenter'} - $params->{datacenter}";
      $subsys        = $params->{'subsys'};
      $name2bookmark = $params->{'datastore'};
      $img_name      = "$params->{vcenter}\_$subsys\_$params->{'datastore'}\_$metric.png";

      $query_string_act = "host=" . urlencode("$params->{'host'}") . "&server=" . urlencode("$params->{'server'}") . "&lpar=" . urlencode("$params->{'lpar'}") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width&d_platform=VMware";
    }
    if ( $params->{'subsys'} eq "CLUSTER" ) {
      $host          = "$params->{'vcenter'} - $params->{cluster}";
      $subsys        = $params->{'subsys'};
      $name2bookmark = $params->{'cluster'};
      $img_name      = "$params->{vcenter}\_$subsys\_$params->{'cluster'}\_$metric.png";

      $query_string_act = "host=" . urlencode("$params->{'host'}") . "&server=" . urlencode("$params->{'server'}") . "&lpar=" . urlencode("$params->{'lpar'}") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width&d_platform=VMware";
    }
  }

  #
  # OVIRT
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "OVIRT" && exists $params->{'subsys'} && exists $params->{'datacenter'} && exists $params->{'host'} ) {
    $host = ( exists $ovirt_inventory{TRANSLATE_UUID}{ $params->{'datacenter'} } ) ? $ovirt_inventory{TRANSLATE_UUID}{ $params->{'datacenter'} } : $params->{'datacenter'};

    #$subsys        = (exists $ovirt_inventory{TRANSLATE_UUID}{ $params->{'host'} }) ? "$params->{'subsys'} - $ovirt_inventory{TRANSLATE_UUID}{ $params->{'host'} }" : "$params->{'subsys'} - $params->{'host'}";
    $subsys        = $params->{'subsys'};
    $name2bookmark = ( exists $ovirt_inventory{TRANSLATE_UUID}{ $params->{'uuid'} } ) ? $ovirt_inventory{TRANSLATE_UUID}{ $params->{'uuid'} } : $params->{'uuid'};
    $img_name      = "$host\_$subsys\_$name2bookmark\_$metric.png";

    $query_string_act = "host=oVirt&server=nope&lpar=" . urlencode("$params->{'uuid'}") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
  }

  #
  # NUTANIX
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "NUTANIX" && exists $params->{'subsys'} && exists $params->{'clusteruuid'} && exists $params->{'host'} ) {
    $host          = $params->{'host'};
    $subsys        = $params->{'subsys'};
    $name2bookmark = $params->{'host'};

    if ( $subsys =~ m/TOTALS$/ ) {
      my $metric2filename = text_item($metric);
      $metric2filename =~ s/\s+/_/g;
      $img_name = "$host\_$subsys\_$metric2filename.png";
    }
    else {
      $img_name = "$host\_$subsys\_$name2bookmark\_$metric.png";
    }

    #host=Nutnanix&server=0005a23f-1568-642a-289b-0050568cf524&lpar=nope&item=nutanix-disk-vbd-sp-aggr&time=d&type_sam=&detail=1&entitle=0&none=none&d_platform=not%20defined

    $query_string_act = "host=Nutanix&server=$params->{'clusteruuid'}&lpar=nope&item=$metric&time=$time&type_sam=&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
  }

  #
  # SOLARIS
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "SOLARIS" && exists $params->{'subsys'} && exists $params->{'name'} ) {
    $host          = "Solaris";
    $subsys        = $params->{'subsys'};
    $name2bookmark = $params->{'name'};
    my $metric_label = text_item($metric);
    $img_name = "$host\_$subsys\_$name2bookmark\_$metric_label.png";

    # LDOM/Global zone
    if ( $params->{'subsys'} eq "LDOM" ) {
      $subsys = "LDOM/Global ZONE";    # PDF bookmark

      #host=0&server=Solaris--unknown&lpar=sol101%3A0004fb00000600006d9a8f1baae815f7&item=s_ldom_c&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined
      #host=0&server=Solaris--unknown&lpar=sol101%3A0004fb00000600006d9a8f1baae815f7&item=s_ldom_m&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined)
      #host=no_hmc&server=Solaris--unknown&lpar=sol101:0004fb00000600006d9a8f1baae815f7&item=oscpu&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined
      #host=no_hmc&server=Solaris--unknown&lpar=sol101:0004fb00000600006d9a8f1baae815f7&item=queue_cpu&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined
      #host=no_hmc&server=Solaris--unknown&lpar=sol101:0004fb00000600006d9a8f1baae815f7&item=jobs&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined
      #host=no_hmc&server=Solaris--unknown&lpar=sol101:0004fb00000600006d9a8f1baae815f7&item=mem&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined
      #host=no_hmc&server=Solaris--unknown&lpar=sol101:0004fb00000600006d9a8f1baae815f7&item=pg1&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined
      #host=no_hmc&server=Solaris--unknown&lpar=sol101:0004fb00000600006d9a8f1baae815f7&item=pg2&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined
      #host=no_hmc&server=Solaris--unknown&lpar=sol101:0004fb00000600006d9a8f1baae815f7&item=s_ldom_n&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined
      #host=sol101:0004fb00000600006d9a8f1baae815f7&server=Solaris&lpar=pool_default&item=solaris_pool&time=d&type_sam=m&detail=1&entitle=0&none=none&d_platform=not%20defined

      my $name_new = $params->{'name'};
      if ( exists $solaris_inventory{LDOM}{ $params->{'name'} }{SOL} && $solaris_inventory{LDOM}{ $params->{'name'} }{SOL} ne '' ) {
        $name_new = "$solaris_inventory{LDOM}{ $params->{'name'} }{SOL}:$params->{'name'}";
        $subsys   = "$solaris_inventory{LDOM}{ $params->{'name'} }{SOL} : $subsys";      # to PDF bookmark
      }

      $query_string_act = "host=no_hmc&server=Solaris--unknown&lpar=" . urlencode($name_new) . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
    }

    # Totals
    if ( $params->{'subsys'} eq "TOTAL" ) {
      $name2bookmark = "Aggregated";
      $img_name      = "$host\_$subsys\_$name2bookmark\_$metric_label.png";

      $query_string_act = "host=no_hmc&server=Solaris&lpar=" . urlencode("$params->{'name'}") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
    }

    # Zone
    if ( $params->{'subsys'} eq "ZONE" && exists $params->{'zone'} ) {
      $name2bookmark = "$params->{'name'} : $params->{'zone'}";
      $img_name      = "$host\_LDOM\_$params->{'name'}\_$subsys\_$params->{'zone'}\_$metric_label.png";

      my $sol = ( exists $solaris_inventory{HOST}{ $params->{'name'} }{ZONE}{ $params->{'zone'} }{SOL} ) ? $solaris_inventory{HOST}{ $params->{'name'} }{ZONE}{ $params->{'zone'} }{SOL} : "";
      $subsys = "$sol : $params->{'subsys'}";    # to PDF bookmark

      # ZONE OS agent data
      $query_string_act = "host=no_hmc&server=Solaris--unknown&lpar=" . urlencode("$sol:zone:$params->{'zone'}") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";

      # ZONE standard
      if ( $metric =~ m/^solaris_zone_/ ) {
        $query_string_act = "host=Solaris&server=" . urlencode("$sol:$params->{'name'}") . "&lpar=" . urlencode("$sol:zone:$params->{'zone'}") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
      }
    }
  }

  #
  # Hyper-V
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "HYPERV" && exists $params->{'subsys'} ) {
    if ( $params->{'subsys'} eq "CLUSTER" && exists $params->{'server'} && exists $params->{'name'} && exists $params->{'host'} ) {
      $host          = "Cluster: $params->{'host'}";
      $subsys        = $params->{'subsys'};
      $name2bookmark = "Totals";

      my $metric_label = text_item( $metric, "HYPERV" );
      $img_name = "$subsys\_$params->{'host'}\_$metric_label.png";

      $query_string_act = "host=cluster_" . urlencode("$params->{'host'}") . "&server=" . urlencode("$params->{'server'}") . "&lpar=" . urlencode("$params->{'name'}") . "&item=$metric&time=$time&type_sam=na&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
      $metric           = $metric_label;
    }
    if ( $params->{'subsys'} eq "SERVER" && exists $params->{'server'} && exists $params->{'name'} && exists $params->{'host'} ) {
      $host          = "$params->{'server'} - $params->{'host'}";
      $subsys        = $params->{'subsys'};
      $name2bookmark = "Totals";

      my $metric_label = text_item( $metric, "HYPERV" );
      $img_name = "$host\_$subsys\_$name2bookmark\_$metric_label.png";

      $query_string_act = "host=" . urlencode("$params->{'host'}") . "&server=" . urlencode("windows/domain_$params->{'server'}") . "&lpar=" . urlencode("$params->{'name'}") . "&item=$metric&time=$time&type_sam=m&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
      $metric           = $metric_label;
    }
    if ( $params->{'subsys'} eq "VM" && exists $params->{'server'} && exists $params->{'name'} && exists $params->{'uid'} && exists $params->{'host'} ) {
      $host          = "$params->{'server'} - $params->{'host'}";
      $subsys        = $params->{'subsys'};
      $name2bookmark = $params->{'name'};
      my $metric_label = text_item( $metric, "HYPERV" );
      $img_name = "$host\_$subsys\_$name2bookmark\_$metric_label.png";

      if ( exists $params->{'cluster'} ) {    # VMs from cluster
        $host     = "Cluster: $params->{'cluster'}";
        $img_name = "CLUSTER_$params->{'cluster'}\_$subsys\_$name2bookmark\_$metric_label.png";
      }

      $query_string_act = "host=" . urlencode("$params->{'host'}") . "&server=" . urlencode("windows/domain_$params->{'server'}") . "&lpar=" . urlencode("$params->{'uid'}") . "&item=$metric&time=$time&type_sam=m&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
      $metric           = $metric_label;
    }
    if ( $params->{'subsys'} eq "STORAGE" && exists $params->{'server'} && exists $params->{'name'} && exists $params->{'host'} ) {
      $host          = "$params->{'server'} - $params->{'host'}";
      $subsys        = $params->{'subsys'};
      $name2bookmark = $params->{'name'};
      my $metric_label = text_item( $metric, "HYPERV" );
      $img_name = "$host\_$subsys\_$name2bookmark\_$metric_label.png";

      # grrr some disks have got different metric
      # change string lfd to csv
      # Local_Fixed_Disk -> lfd
      # Cluster_Storage -> csv
      if ( -f "$wrkdir/windows/domain_$params->{'server'}/$params->{'host'}/Cluster_Storage_$params->{'name'}.rrm" ) { $metric =~ s/lfd/csv/; }

      $query_string_act = "host=" . urlencode("$params->{'host'}") . "&server=" . urlencode("windows/domain_$params->{'server'}") . "&lpar=" . urlencode("$params->{'name'}") . "&item=$metric&time=$time&type_sam=m&detail=$detail&sunix=$sunix&eunix=$eunix&entitle=0&height=$png_height&width=$png_width";
      $metric           = $metric_label;
    }
  }

  $img_name =~ s/\//&&1/g;
  $img_name =~ s/\s/_/g;

  return ( "$img_name", "$query_string_act", "$host", "$subsys", "$name2bookmark", "$metric" );
}

sub set_query_string_csv {
  my $sunix  = shift;
  my $eunix  = shift;
  my $params = shift;

  my $query_string_act = "";
  my $csv_name         = "";
  my $hmc              = "";
  my $host             = "";
  my $subsys           = "";
  my $name             = "";

  my $metric = $params->{'metric'};

  # convert timestamp
  my ( undef, undef, $shour, $sday, $smon, $syear, undef, undef, undef ) = localtime($sunix);
  $syear = $syear + 1900;
  $smon  = $smon + 1;
  my ( undef, undef, $ehour, $eday, $emon, $eyear, undef, undef, undef ) = localtime($eunix);
  $eyear = $eyear + 1900;
  $emon  = $emon + 1;

  # IBM POWER
  if ( exists $params->{'group'} && $params->{'group'} eq "POWER" && exists $params->{'subsys'} && exists $params->{'hmc'} && exists $params->{'host'} && exists $params->{'name'} ) {
    $hmc      = $params->{'hmc'};
    $host     = $params->{'host'};
    $subsys   = $params->{'subsys'};
    $name     = $params->{'name'};
    $csv_name = "$host\_$subsys\_$name\_$metric.csv";

    # LPAR graphs
    if ( $params->{'subsys'} eq "LPAR" ) {
      if ( $metric eq "lpar" ) { $csv_name = "$host\_$subsys\_$name\_cpu.csv"; }
      $query_string_act = "subsys=$params->{'subsys'}&platform=POWER&hmc=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&sunix=$sunix&eunix=$eunix";
    }

    # CPU pool, shared pool, server memory, server paging
    if ( $params->{'subsys'} eq "POOL" ) {
      my $name2csv_file_name = $name;
      if ( $name eq "pool" ) { $name2csv_file_name = "CPUPOOL"; }
      if ( $name =~ m/^SharedPool[0-9]+$/ ) {                       # translate shared pool id to human name
        $name2csv_file_name = translate_shpool_id( "$host", "$name" );
      }
      $csv_name = "$host\_$subsys\_$name2csv_file_name\_$metric.csv";
      if ( $metric eq "pool"     || $metric eq "shpool" )     { $csv_name = "$host\_$subsys\_$name2csv_file_name\_cpu.csv"; }
      if ( $metric eq "pool-max" || $metric eq "shpool-max" ) { $csv_name = "$host\_$subsys\_$name2csv_file_name\_cpu-max.csv"; }
      $query_string_act = "subsys=$params->{'subsys'}&platform=POWER&hmc=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&sunix=$sunix&eunix=$eunix";
    }

    # SERVER memory
    if ( $params->{'subsys'} eq "SERVER" ) {
      if ( $metric eq "memalloc" || $metric eq "memaggreg" ) {
        $csv_name         = "$host\_$subsys\_MEMORY_$metric.csv";
        $query_string_act = "subsys=$params->{'subsys'}&platform=POWER&hmc=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&sunix=$sunix&eunix=$eunix";
      }
    }
  }
  #
  # CUSTOM GROUPS
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "CUSTOM" && exists $params->{'host'} && exists $params->{'subsys'} ) {
    $host = "na";
    $hmc  = "na";
    $name = $params->{'host'};
    my $metric2filename = text_item( $metric, $params->{'subsys'} );
    $metric2filename =~ s/\s/_/g;
    $csv_name = "CUSTOM-GROUP_$name\_$metric2filename.csv";

    my $platform = "POWER";
    if ( $params->{'subsys'} eq "ESXI" || $params->{'subsys'} eq "VM" ) {
      $platform = "VMWARE";
    }

    $query_string_act = "subsys=$params->{'group'}-$params->{'subsys'}&platform=$platform&hmc=" . urlencode("$hmc") . "&server=" . urlencode("$host") . "&lpar=" . urlencode("$name") . "&item=$metric&sunix=$sunix&eunix=$eunix";
  }
  #
  # TOP
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "TOP" ) {
    my $metric2filename = text_item( $metric, $params->{'group'} );

    if ( $params->{subsys} eq "global" ) {
      $csv_name         = "TOP$params->{topcount}_$params->{'platform'}_$params->{subsys}_$metric2filename\_last_$params->{toptimerange}.csv";
      $query_string_act = "subsys=$params->{'group'}&platform=" . $params->{'platform'} . "&server=XOR-GLOBAL-XOR&item=$metric&time=$params->{toptimerange}&limit=$params->{topcount}";
    }
    else {
      $csv_name         = "TOP$params->{topcount}_$params->{'platform'}_" . join( "-", @{ $params->{name} } ) . "_$metric2filename\_last_$params->{toptimerange}.csv";
      $query_string_act = "subsys=$params->{'group'}&platform=" . $params->{'platform'} . "&server=" . join( "&server=", @{ $params->{name} } ) . "&item=$metric&time=$params->{toptimerange}&limit=$params->{topcount}";
    }
  }
  #
  # Resource Configuration Advisor
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "RCA" ) {
    my $metric2filename = text_item( $metric, $params->{'group'} );

    $csv_name         = "Resource_Configuration_Advisor_$params->{'platform'}_$metric2filename\_last_$params->{toptimerange}.csv";
    $query_string_act = "subsys=$params->{'group'}&platform=" . $params->{'platform'} . "&item=$metric&time=$params->{toptimerange}";
  }
  #
  # VMware
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "VMWARE" ) {
    if ( $params->{'subsys'} eq "CLUSTER" ) {
      my $metric2filename = text_item( $metric, $params->{'group'} );
      $csv_name         = "Vcenter_$params->{'vcenter'}_" . $params->{'subsys'} . "_$params->{'cluster'}_$metric2filename.csv";
      $query_string_act = "subsys=$params->{'subsys'}&platform=VMWARE&host=$params->{'host'}" . "&server=$params->{'server'}" . "&vcenter=" . urlencode("$params->{'vcenter'}") . "&cluster=" . urlencode("$params->{'cluster'}") . "&item=$metric&sunix=$sunix&eunix=$eunix";
    }
    if ( $params->{'subsys'} eq "ESXI" ) {
      my $metric2filename = text_item( $metric, "ESXI" );
      $csv_name         = "Vcenter_$params->{'vcenter'}_cluster_$params->{'cluster'}_" . "$params->{'subsys'}_$params->{'server'}" . "_$metric2filename.csv";
      $query_string_act = "subsys=$params->{'subsys'}&platform=VMWARE&host=$params->{'host'}" . "&server=$params->{'server'}" . "&vcenter=" . urlencode("$params->{'vcenter'}") . "&cluster=" . urlencode("$params->{'cluster'}") . "&item=$metric&sunix=$sunix&eunix=$eunix";
    }
    if ( $params->{'subsys'} eq "VM" ) {

      #print Dumper \%{ $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{CLUSTER}{ $params->{'cluster'} }{URL_PARAM}{server} };
      my $metric2filename = text_item( $metric, "VM" );
      $csv_name = "Vcenter_$params->{'vcenter'}_cluster_$params->{'cluster'}_" . "$params->{'subsys'}_$params->{'server'}_VM_$params->{'vm_name'}" . "_$metric2filename.csv";
      if ( $metric eq "vmw-iops" ) {
        if ( exists $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{CLUSTER}{ $params->{'cluster'} }{URL_PARAM}{server} ) {
          my $vcenter_id = $vmware_inventory{VCENTER}{ $params->{'vcenter'} }{CLUSTER}{ $params->{'cluster'} }{URL_PARAM}{server};
          $query_string_act = "subsys=$params->{'subsys'}&platform=VMWARE&host=$params->{'host'}" . "&server=$params->{'server'}" . "&vcenter=" . urlencode("$params->{'vcenter'}") . "&cluster=" . urlencode("$params->{'cluster'}") . "&vm_name=" . urlencode("$params->{'vm_name'}") . "&vm_uuid=" . urlencode("$params->{'vm_uuid'}") . "&vcenter_id=$vcenter_id&item=$metric&sunix=$sunix&eunix=$eunix";
        }
      }
      else {
        $query_string_act = "subsys=$params->{'subsys'}&platform=VMWARE&host=$params->{'host'}" . "&server=$params->{'server'}" . "&vcenter=" . urlencode("$params->{'vcenter'}") . "&cluster=" . urlencode("$params->{'cluster'}") . "&vm_name=" . urlencode("$params->{'vm_name'}") . "&vm_uuid=" . urlencode("$params->{'vm_uuid'}") . "&item=$metric&sunix=$sunix&eunix=$eunix";
      }
    }
    if ( $params->{'subsys'} eq "DATASTORE" ) {
      my $metric2filename = text_item( $metric, "DATASTORE" );
      $csv_name         = "Vcenter_$params->{'vcenter'}_datacenter_$params->{'datacenter'}_" . "$params->{'subsys'}_$params->{'datastore'}" . "_$metric2filename.csv";
      $query_string_act = "subsys=$params->{'subsys'}&platform=VMWARE&host=$params->{'host'}" . "&server=$params->{'server'}" . "&vcenter=" . urlencode("$params->{'vcenter'}") . "&datacenter=" . urlencode("$params->{'datacenter'}") . "&datastore=" . urlencode("$params->{'datastore'}") . "&uuid=" . urlencode("$params->{'lpar'}") . "&item=$metric&sunix=$sunix&eunix=$eunix";
    }
    if ( $params->{'subsys'} eq "RESPOOL" ) {
      my $metric2filename = text_item( $metric, "RESPOOL" );
      $csv_name         = "Vcenter_$params->{'vcenter'}_cluster_$params->{'cluster'}_" . "$params->{'subsys'}_$params->{'respool'}" . "_$metric2filename.csv";
      $query_string_act = "subsys=$params->{'subsys'}&platform=VMWARE&host=$params->{'host'}" . "&server=$params->{'server'}" . "&vcenter=" . urlencode("$params->{'vcenter'}") . "&cluster=" . urlencode("$params->{'cluster'}") . "&respool=" . urlencode("$params->{'respool'}") . "&id=" . urlencode("$params->{'lpar'}") . "&item=$metric&sunix=$sunix&eunix=$eunix";
    }
    $csv_name =~ s/ /_/g;
  }
  #
  # oVirt
  #
  if ( exists $params->{'group'} && $params->{'group'} eq "OVIRT" && exists $params->{'subsys'} && exists $params->{'datacenter'} && exists $params->{'host'} && exists $params->{'uuid'} ) {
    $host   = ( exists $ovirt_inventory{TRANSLATE_UUID}{ $params->{'datacenter'} } ) ? $ovirt_inventory{TRANSLATE_UUID}{ $params->{'datacenter'} } : $params->{'datacenter'};
    $subsys = $params->{'subsys'};
    my $name = ( exists $ovirt_inventory{TRANSLATE_UUID}{ $params->{'uuid'} } ) ? $ovirt_inventory{TRANSLATE_UUID}{ $params->{'uuid'} } : $params->{'uuid'};
    $csv_name = "$host\_$subsys\_$name\_$metric.csv";

    $query_string_act = "subsys=$params->{'subsys'}&platform=OVIRT&host=$host" . "&name=$name" . "&uuid=$params->{'uuid'}" . "&datacenter=" . urlencode("$params->{'datacenter'}") . "&item=$metric&sunix=$sunix&eunix=$eunix";
  }

  # set SAMPLE_RATE if exists
  if ( defined $params->{'sample_rate'} && isdigit( $params->{'sample_rate'} ) ) {
    $query_string_act .= "&sample_rate=$params->{'sample_rate'}";
  }

  $csv_name =~ s/\//&&1/g;

  return ( "$csv_name", "$query_string_act" );
}

sub get_img_stor {
  my $img          = shift;
  my $query_string = shift;

  $ENV{'PICTURE_COLOR'} = "FFF";
  $ENV{'QUERY_STRING'}  = $query_string;

  chdir("$bindir") || error( "Couldn't change directory to $bindir $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  print "create graph   : QUERY_STRING=$ENV{'QUERY_STRING'}\n" if $debug == 9;

  my $ret = `$perl $bindir/detail-graph-cgi.pl 2>$reportsdir/error.log-tmp`;

  if ( -f "$reportsdir/error.log-tmp" ) {
    my $file_size = ( stat("$reportsdir/error.log-tmp") )[9];
    if ( isdigit($file_size) && $file_size > 0 ) {
      open( ERR, "<$reportsdir/error.log-tmp" ) || error( "Couldn't open file $reportsdir/error.log-tmp $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
      my @lines = <ERR>;
      close(ERR);

      foreach my $line (@lines) {
        chomp $line;
        error("ERROR detail-graph-cgi.pl: $line");
      }
    }
    unlink("$reportsdir/error.log-tmp");
  }

  # remove html header
  my ( $header, $justpng ) = ( split "\n\n", $ret, 2 );

  # write png without header
  if ( defined $justpng && $justpng ne '' ) {
    open( PNG, ">$img" ) || error( "Couldn't open file $img $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
    print PNG "$justpng";
    close(PNG);
  }

  # check if image was created
  if ( !-f $img ) {
    error("Graph was not created! \"$img\"") && return 0;
  }
  else {
    set_permissions( "$img", 0664 );
  }

  # check file size
  my $file_size = ( stat("$img") )[9];
  if ( isdigit($file_size) && $file_size == 0 ) {
    error("Graph file size is 0! Something wrong with graph creation. File \"$img\" removed!");
    unlink("$img");
    return 0;
  }

  #print "PNG HEADER: $header\n";

  return 1;
}

sub remove_files {
  my $dir = shift;

  if ( -d $dir ) {
    opendir( DIR, "$dir" ) || error( " directory does not exists : $dir " . __FILE__ . ":" . __LINE__ ) && exit 1;
    my @files = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);

    foreach my $file (@files) {
      chomp $file;

      if ( -f "$dir/$file" ) {
        print "remove file    : $dir/$file\n" if $debug == 9;
        unlink("$dir/$file");
      }
      if ( -d "$dir/$file" ) {
        opendir( DIR, "$dir/$file" ) || error( " directory does not exists : $dir/$file " . __FILE__ . ":" . __LINE__ ) && exit 1;
        my @files_2 = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);

        foreach my $file_2 (@files_2) {
          chomp $file_2;
          if ( -f "$dir/$file/$file_2" ) {
            print "remove file    : $dir/$file/$file_2\n" if $debug == 9;
            unlink("$dir/$file/$file_2");
          }
        }
        print "remove dir     : $dir/$file\n" if $debug == 9;
        rmdir("$dir/$file");
      }
    }
    print "remove dir     : $dir\n" if $debug == 9;
    rmdir("$dir");
  }

  return 1;
}

sub urlencode {
  my $s = shift;
  $s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  return $s;
}

sub urldecodel {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  return $s;
}

sub send_email {
  my ( $mailprog, $email_to, $email, $subject, $boundary, $attachment_data ) = @_;

  if ( $ENV{DEMO} ) { return 1; }    # do not send emails on our demo

  my @message = ( "Hello,\n\n", "your report has been successfully created!\n" );
  if ( -f "$basedir/etc/reporter_email_body.cfg" ) {
    open( MSG, "<$basedir/etc/reporter_email_body.cfg" ) || error( "Couldn't open file $basedir/etc/reporter_email_body.cfg $!" . __FILE__ . ":" . __LINE__ );
    @message = <MSG>;
    close(MSG);
  }

  my %attachments = %$attachment_data;

  if ( !-f $mailprog ) {
    error( "Alerting: emailing program missing \"$mailprog\", install it " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  my $sendmail_from = " -f $email";
  if ( $email eq '' ) {
    $sendmail_from = "";
  }

  if ( open MAIL, "|$mailprog -t $sendmail_from" ) {
    print MAIL "To: $email_to\n";
    print MAIL "From: $email\n";
    print MAIL "Subject: $subject\n";

    print MAIL "MIME-Version: 1.0\n";
    print MAIL "Content-Type: multipart/mixed; boundary=\"$boundary\"\n\n";
    print MAIL "--$boundary\n";
    print MAIL "Content-Type: text/plain; charset=utf-8;\n\n";
    foreach my $msg_line (@message) {
      print MAIL "$msg_line";
    }

    foreach my $filename ( keys(%attachments) ) {
      if ( defined $attachments{$filename}{'data'} && $attachments{$filename}{'data'} ne '' && defined $attachments{$filename}{'Content-Type'} && $attachments{$filename}{'Content-Type'} ne '' ) {
        print MAIL "--$boundary\n";
        print MAIL "Content-Type: $attachments{$filename}{'Content-Type'};";
        print MAIL "name=\"$filename\"\n";
        print MAIL "Content-Transfer-Encoding: base64\n";
        print MAIL "Content-Disposition: attachment;";
        print MAIL "filename=\"$filename\"\n\n";
        print MAIL "$attachments{$filename}{'data'}\n";
      }
    }
    print MAIL "--$boundary--\n";
    close MAIL;
  }

  return 1;
}

sub translate_name_to_id {
  my $host     = shift;
  my $type     = shift;
  my $name     = shift;
  my $st_type  = shift;
  my $cfg_file = shift;
  my $id       = $name;

  if ( -f $cfg_file ) {
    open( CFG, "< $cfg_file" ) || error( "Can't open $cfg_file : $! " . __FILE__ . ":" . __LINE__ ) && exit 1;
    my @cfg = <CFG>;
    close(CFG);

    if ( $type eq "NODE" || $type eq "VOLUME-FOLDER" || $type eq "PORT" || $type eq "NAS" || $type eq "FS" || $type eq "RANK" || $type eq "IO-GROUP" || $type eq "NAS" || $type eq "TIER" || $type eq "HOST-GROUP" || $type eq "CATALYST" || ( $type eq "POOL" && $st_type eq "VMAX" ) ) {
      if ( $name =~ m/\(/ || $name =~ m/\)/ ) {    # INFINIBOX has got PORT names like: N3ETH1 (ETH)
        $name =~ s/\(/\\(/g;
        $name =~ s/\)/\\)/g;
      }
      my ($cfg_line) = grep {/:$name$/} @cfg;
      if ( defined $cfg_line && $cfg_line ne '' ) {
        my ( $id_new, undef ) = split( /:/, $cfg_line );
        if ( -f "$wrkdir/$host/$type/$id_new.rrd" ) {
          $id = $id_new;
        }
        else {
          if ( $type eq "RANK" && $st_type eq "SWIZ" ) {
            my ($rrd_file) = <$wrkdir/$host/$type/$id_new-P*.rrd>;
            if ( defined $rrd_file && $rrd_file ne '' ) {
              $id = $id_new;
            }
          }
        }
      }
    }
    if ( $type eq "DRIVE" || ( $type eq "CPU-NODE" && $st_type eq "STOREONCE" ) ) {
      my ($cfg_line) = grep {/,$name,/} @cfg;
      if ( defined $cfg_line && $cfg_line ne '' ) {
        my ( $id_new, undef ) = split( /,/, $cfg_line );
        if ( -f "$wrkdir/$host/$type/$id_new.rrd" ) {
          $id = $id_new;
        }
      }
      else {
        ($cfg_line) = grep {/,$name$/} @cfg;
        if ( defined $cfg_line && $cfg_line ne '' ) {
          my ( $id_new, undef ) = split( /,/, $cfg_line );
          if ( -f "$wrkdir/$host/$type/$id_new.rrd" ) {
            $id = $id_new;
          }
        }
      }
    }

  }

  return $id;
}

sub translate_port_id {
  my $port_name = shift;
  my $phys_cfg  = shift;

  my $port_name_new = $port_name;

  if ( -f $phys_cfg ) {
    open( FHR, "< $phys_cfg" ) || error( "Can't open $phys_cfg : $! " . __FILE__ . ":" . __LINE__ ) && exit 1;
    my @phys_ports = <FHR>;
    close(FHR);

    my $port_line = "";
    ($port_line) = grep {/ : $port_name$/} @phys_ports;
    if ( defined $port_line && $port_line ne '' ) {
      ( $port_name_new, undef ) = split( " : ", $port_line );
    }
  }

  return $port_name_new;
}

sub alias_to_name {
  my $host     = shift;
  my $subsys   = shift;
  my $name     = shift;
  my $name_new = $name;

  if ( exists $aliases{$subsys}{$host}{$name}{'ID'} && $aliases{$subsys}{$host}{$name}{'ID'} ne '' ) {
    $name_new = $aliases{$subsys}{$host}{$name}{'ID'};
    if ( $subsys eq "SANPORT" ) {
      $name_new =~ s/^port//;
    }
    print "alias found    : $subsys:$host:$name_new:$name\n" if $debug == 9;
  }

  return $name_new;
}

sub zip_file {
  my $file_out = shift;
  my $files_in = shift;
  my $dir      = shift;

  chdir("$dir") || error( "Couldn't change directory to $dir $!" . __FILE__ . ":" . __LINE__ ) && exit 1;

  my $ZipError     = "";
  my $module_found = 1;

  eval 'use IO::Compress::Zip qw(zip $ZipError)';

  if ($@) {
    $module_found = 0;
  }

  if ( $module_found == 1 ) {
    print "zip report     : $files_in/* to $file_out\n" if $debug == 9;

    if ( -d $files_in ) {
      my @files = <$files_in/*>;
      zip( \@files => "$file_out" ) or error("zip failed: $ZipError") && return 0;
    }
    else {
      error("Directory \"$files_in\" not exists!") && return 0;
    }
  }
  else {
    error("Cannot use module IO::Compress::Zip, probably it is not installed!") && return 0;
  }

  return 1;
}

sub is_dir_empty {
  my $dir = shift;

  if ( -f $dir ) {
    opendir( DIR, "$dir" ) || error( "can't opendir $dir: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @files = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);

    my $count = @files;
    if ( $count > 0 ) {
      return 0;
    }
    else {
      return 1;
    }
  }

  # not exists
  return 3;
}

sub isdigit {
  my $digit = shift;

  if ( !defined($digit) || $digit eq '' ) {
    return 0;
  }

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/^-//;
  $digit_work =~ s/^\+//;
  $digit_work =~ s/e\+//;
  $digit_work =~ s/e\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  # NOT a number
  return 0;
}

sub file_time_diff {
  my $file = shift;

  my $act_time  = time();
  my $file_time = $act_time;
  my $time_diff = 0;

  if ( -f $file ) {
    $file_time = ( stat($file) )[9];
    $time_diff = $act_time - $file_time;
  }

  return ($time_diff);
}

sub message {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "$act_time: $text\n";

  return 1;
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  #print "$act_time: $text : $!\n" if $DEBUG > 2;;

  return 1;
}

sub set_permissions {
  my $file = shift;
  my $perm = shift;

  if ( !defined $perm || $perm eq '' ) { $perm = 0664; }    # default

  chmod $perm, $file || error("Cannot change permissions of the file: \"chmod $perm, $file\"") && return 0;

  return 1;
}

sub write_file {
  my $file = shift;

  if ( $API_RUN == 0 && $file eq "\/tmp\/lrep-$pid.status" ) { return 1; }    # do not create status file if reports are generated from load.sh

  open IO, ">$file" or die "Cannot open $file for output: $!\n";
  print IO @_;
  close IO;

  return 1;
}
