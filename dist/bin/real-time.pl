#use strict;
use Math::BigInt;
use RRDp;
use POSIX qw(strftime);
use Env qw(QUERY_STRING);
use File::Copy;
use Date::Parse;
use LoadDataModule;
use XoruxEdition;

my $DEBUG = $ENV{DEBUG};
$DEBUG = 0;
my $SSH      = $ENV{SSH} . " ";
my $ident    = $ENV{SSH_WEB_IDENT};
my $hmc_user = $ENV{HMC_USER};
my $inputdir = $ENV{INPUTDIR};
my $tmpdir   = "$inputdir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $cpu_max_filter = 100;    # max 10k peak in % is allowed (in fact it cann by higher than 1k now when 1 logical CPU == 0.1 entitlement
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}

my $rrdtool             = $ENV{RRDTOOL};
my $refer               = $ENV{HTTP_REFERER};
my $errlog              = $ENV{ERRLOG};
my $idir                = "$tmpdir/$$";                   # temp dir, must be 777
my $webdir              = $ENV{WEBDIR};
my $bindir              = $ENV{BINDIR};
my $pic_col             = $ENV{PICTURE_COLOR};
my $name                = "/var/tmp/lpar2rrd-realt-$$";
my $width               = $ENV{RRDWIDTH};
my $height              = $ENV{RRDHEIGHT};
my @pool_list           = "";
my $time                = localtime();
my $act_time            = $time;
my $sec                 = "";
my $ivmmin              = "";
my $ivmh                = "";
my $ivmd                = "";
my $ivmm                = "";
my $ivmy                = "";
my $wday                = "";
my $yday                = "";
my $isdst               = "";
my $rrd                 = "";
my $sharepool_id        = -1;
my $MAX_ROWS_WORKAROUND = 100000;                         # some HMCs have a problem with lslparutil -s d -r lpar/sys -h XY, solution is to put there
                                                          # one more argument -n whatever_high_enough
                                                          # HMC returns either HSCL8016 or "No resupts found"
my $mem_params          = "";

my $keep_virtual = 0;
if ( $ENV{KEEP_VIRTUAL} ) {
  $keep_virtual = $ENV{KEEP_VIRTUAL};                     # keep number of virt processors in RRD --> etc/.magic
}
else {
  $keep_virtual = 0;
}

# disable Tobi's promo
# my $disable_rrdtool_tag = "COMMENT: ";
my $rrd_ver                 = $RRDp::VERSION;
my $disable_rrdtool_tag     = "--interlaced";    # just nope string, it is deprecated anyway
my $disable_rrdtool_tag_agg = "--interlaced";    # just nope string, it is deprecated anyway

if ( isdigit($rrd_ver) && $rrd_ver > 1.35 ) {
  $disable_rrdtool_tag = "--disable-rrdtool-tag";
}

open( OUT, ">> $errlog" ) if $DEBUG;

# print HTML header
print "Content-type: image/png\n";
print "Cache-Control: max-age=60, public\n\n";    # workaround for caching on Chrome

# get QUERY_STRING
#print OUT "-- $QUERY_STRING\n" if $DEBUG ;

( my $lpar, my $hmc, my $managedname, my $gui, my $none ) = split( /&/, $QUERY_STRING );

$lpar =~ s/source=//;
$lpar =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/seg;
$lpar =~ s/\+/ /g;
$lpar_slash = $lpar;
$lpar_slash =~ s/\//&&1/;
$hmc        =~ s/hmc=//;
$hmc        =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/seg;
$hmc        =~ s/\+/ /g;
my $host = $hmc;    # for compatability reasons with the other code
$managedname =~ s/mname=//;
$managedname =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/seg;
$managedname =~ s/\+/ /g;

print OUT "$idir - $lpar - $hmc - $managedname \n" if $DEBUG;

# prepare global $sharepool_id
if ( $lpar =~ m/CPU pool/ && -f "$inputdir/data/$managedname/$hmc/cpu-pools-mapping.txt" ) {
  open( FR, "<$inputdir/data/$managedname/$hmc/cpu-pools-mapping.txt" ) || error( "Can't open $inputdir/data/$managedname/$hmc/cpu-pools-mapping.txt : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  my $id_shared = $lpar;
  $id_shared =~ s/CPU pool //;
  foreach my $linep (<FR>) {
    chomp($linep);
    ( my $id, my $pool_name ) = split( /,/, $linep );
    if ( $id_shared =~ m/^$id$/ ) {
      $lpar         = $pool_name;
      $sharepool_id = $id;
      last;
    }
  }
  close(FR);
  $lpar =~ s/://;
}
my $type_sam = "m";
my $step     = 60;

#mkdir("$idir", 0777) || error("Can't create temp dir : $idir : $!".__FILE__.":".__LINE__) && return 0;

my $input         = "$idir-in";
my $input_pool    = "$idir-pool.in";
my $input_pool_sh = "$idir-pool_sh.in";

# _shell variables for usage in shell cmd lines, must be to avoid a problem with spaces in managed names
my $input_shell         = $input;
my $input_pool_shell    = $input_pool;
my $input_pool_sh_shell = $input_pool_sh;
$input_shell         =~ s/ /\\ /g;
$input_pool_shell    =~ s/ /\\ /g;
$input_pool_sh_shell =~ s/ /\\ /g;

my @lpar_trans = "";    # lpar translation names/ids for IVM systems

my $IVM  = 0;
my $SDMC = 0;
my $HMC  = 0;

if ( -f "$inputdir/data/$managedname/$host/SDMC" ) {
  $SDMC = 1;
}
if ( -f "$inputdir/data/$managedname/$host/IVM" ) {
  $IVM = 1;
}

if ( $SDMC == 0 && $IVM == 0 ) {
  $HMC = 1;
  my $hmcv = `$SSH -i $ident $hmc_user\@$host "lshmc -v" 2>/dev/null|grep RM| tr -d \'[:alpha:]\'|tr -d \'[:punct:]\'`;
  if ( length($hmcv) < 3 ) {
    $HMC      = 0;                                                                                                                                       # looks like IVM system
    $hmcv_num = 700;
    $SDMC     = `$SSH -i $ident $hmc_user\@$host "if test -r /usr/smrshbin ; then echo \"PLATFORM=1\" ; else echo \"PLATFORM=0\" ; fi"|grep PLATFORM`;
    chomp($SDMC);
    $SDMC =~ s/PLATFORM=//g;
    if ( $SDMC eq '' ) {
      my $SDMC_tmp = `$SSH -i $ident $hmc_user\@$host "if test -r /usr/smrshbin ; then echo \"PLATFORM=1\" ; else echo \"PLATFORM=0\" ; fi"`;
      error("$0: $host:$managedname : was not able to confirm SDMC source : $SDMC_tmp");
      error("Connection to $host failed, probably wrong ownership or missing identity file $ident… ,it must be owned by Apache user (httpd, apache, nobody …), refer to http://www.lpar2rrd.com/install.htm --> LPAR2RRD tab");
      $SDMC = 1;                                                                                                                                         # setting it
    }
    @lpar_trans = `$SSH -i $ident $hmc_user\@$host "lssyscfg -r lpar -m \\"$managedname\\" -F lpar_id,name" 2>\&1| egrep "^[0-9]"`;
  }
  else {
    $hmcv =~ s/ //g;
    $hmcv_num = substr( $hmcv, 0, 3 );

    #print "DEBUG : $hmcv_num $hmcv\n";
    #print OUT "HMC version    : $hmcv" if $DEBUG ;
    if ( $hmcv_num > 734 || $hmcv_num < 600 ) {

      #$hmcv_num < 6 for PureFlex, not exact but should be ok  (actually it is in 1.2.0 version: Mar 2013)
      # set params for lslparutil and AMS available from HMC V7R3.4.0 Service Pack 2 (05-21-2009)
      $mem_params = ",mem_mode,curr_mem,phys_run_mem,curr_io_entitled_mem,mapped_io_entitled_mem,mem_overage_cooperation";
    }
  }
}
else {
  $mem_params = ",mem_mode,curr_mem,phys_run_mem,curr_io_entitled_mem,mapped_io_entitled_mem,mem_overage_cooperation";
}

my $check = $HMC + $IVM + $SDMC;
if ( $check != 1 ) {
  error("$0: $host:$managedname: Wrongly identified the source, exiting, contact the support : $HMC - $IVM - $SDMC");
  exit(0);
}

if ( $HMC == 0 ) {
  my $t = time();    # ignore date +%s on purpose!!!
                     # set defaults for IVM
  ( $sec, $ivmmin, $ivmh, $ivmd, $ivmm, $ivmy, $wday, $yday, $isdst ) = localtime( $t - 86400 );    # just last 1 day
  $ivmy += 1900;
  $ivmm += 1;
}

# Load CPU pool data
print OUT "fetching HMC   : $host:$managedname pool data, $lpar,\n" if $DEBUG;
if ( $lpar =~ "CPU pool" || $sharepool_id != -1 ) {
  if ( $step == 3600 ) {
    if ( $HMC == 1 ) {
      if ( $sharepool_id != -1 ) {
        print OUT "fetching HMC   : $host:$managedname:CPU pool $sharepool_id\n" if $DEBUG;
        `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r procpool  -h 24 -n 24 -m \\"$managedname\\" -F time,shared_proc_pool_id,total_pool_cycles,utilized_pool_cycles  --filter \"event_types=sample\",\"pools=$sharepool_id\"" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_pool_sh_shell-$type_sam`;
      }
      else {
        # == "CPU pool" (no space == default pool)
        `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r pool  -h 24 -n 24 -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units  --filter \"event_types=sample\"" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_pool_shell-$type_sam`;
      }
    }
    if ( $IVM == 1 ) {
      `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -r pool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_pool_shell-$type_sam`;
    }
    if ( $SDMC == 1 ) {
      if ( $lpar =~ "CPU pool " ) {
        LoadDataModule::sdmc_procpool_load( "$SSH -i $ident ", $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_sh_shell-$type_sam" );
      }
      else {
        LoadDataModule::sdmc_pool_load( "$SSH -i $ident ", $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_shell-$type_sam" );
      }
    }
  }
  else {
    if ( $HMC == 1 ) {
      if ( $sharepool_id != -1 ) {
        print OUT "fetching HMC   : $host:$managedname:CPU pool $sharepool_id\n" if $DEBUG;
        `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -s s -r procpool  --minutes 1440 -n $MAX_ROWS_WORKAROUND   -m \\"$managedname\\" -F time,shared_proc_pool_id,total_pool_cycles,utilized_pool_cycles  --filter \"event_types=sample\",\"pools=$sharepool_id\"" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_pool_sh_shell-$type_sam`;
      }
      else {
        `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -s s -r pool  --minutes 1440 -n $MAX_ROWS_WORKAROUND -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units  --filter \"event_types=sample\"" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_pool_shell-$type_sam`;
      }
    }
    if ( $IVM == 1 ) {
      `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -r pool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_pool_shell-$type_sam`;
    }
    if ( $SDMC == 1 ) {
      if ( $sharepool_id != -1 ) {
        LoadDataModule::sdmc_procpool_load( "$SSH -i $ident ", $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_sh_shell-$type_sam" );
      }
      else {
        LoadDataModule::sdmc_pool_load( "$SSH -i $ident ", $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_pool_shell-$type_sam" );
      }
    }
  }
}
else {
  # Load lpar data
  print OUT "fetching HMC   : $host:$managedname lpar data\n" if $DEBUG;
  my $lpar_semicol = $lpar;    # ssh does not like ";" in lpar name --> "\;"
  $lpar_semicol =~ s/;/\\\;/g;
  $lpar_semicol =~ s/ /\\ /g;
  if ( $step == 3600 ) {
    if ( $HMC == 1 ) {
      if ( $hmcv_num < 700 ) {
        `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r lpar -h 24 -n $MAX_ROWS_WORKAROUND -m \\"$managedname\\" -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles  --filter \"event_types=sample\",\"lpar_names=$lpar_semicol\"" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_shell-$type_sam`;
      }
      else {
        `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r lpar -h 24 -n $MAX_ROWS_WORKAROUND -m \\"$managedname\\" -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,shared_cycles_while_active$mem_params --filter \"event_types=sample\",\"lpar_names=$lpar_semicol\"" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_shell-$type_sam`;
      }
    }
    if ( $IVM == 1 ) {
      `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -r lpar --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,lpar_id,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,donated_cycles$mem_params --filter \\\\\\"lpar_names=$lpar_semicol\\\\\\"" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_shell-$type_sam`;
    }
    if ( $SDMC == 1 ) {
      LoadDataModule::sdmc_lpar_load( "$SSH -i $ident ", $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_shell-$type_sam", $type_sam, 0, $lpar_semicol, $mem_params );
    }
  }
  else {
    if ( $HMC == 1 ) {
      `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -s s -r lpar --minutes 1440 -n $MAX_ROWS_WORKAROUND -m \\"$managedname\\" -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,shared_cycles_while_active$mem_params  --filter \"event_types=sample\",\"lpar_names=$lpar_semicol\"" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_shell-$type_sam`;
    }
    if ( $IVM == 1 ) {
      `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lslparutil -r lpar --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,lpar_id,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,donated_cycles$mem_params --filter \\\\\\"lpar_names=$lpar_semicol\\\\\\"" 2>&1 |egrep -iv "Could not create directory|known hosts" > $input_shell-$type_sam`;
    }
    if ( $SDMC == 1 ) {
      LoadDataModule::sdmc_lpar_load( "$SSH -i $ident ", $hmc_user, $host, $ivmy, $ivmm, $ivmd, $ivmh, $ivmmin, $managedname, "$input_shell-$type_sam", $type_sam, 0, "$lpar_semicol", $mem_params );
    }
  }
}

print OUT "fetched : $host:$managedname:$type_sam:$type, $lpar,\n" if $DEBUG;

# start RRD via a pipe
use RRDp;
print OUT "rrdtool : $host:$managedname:$type_sam:$type, $lpar,\n" if $DEBUG;
RRDp::start "$rrdtool";

print OUT "rrd load: $host:$managedname:$type_sam:$type, $lpar,\n" if $DEBUG;
load_rrd($managedname);

print OUT "draw grph $host:$managedname:$type_sam:$type, $lpar,\n" if $DEBUG;
draw_graph( "day", "d", "MINUTE:30:HOUR:1:HOUR:1:0:%H", $lpar, $managedname, $type_sam );

# close RRD pipe
RRDp::end;

print OUT "printing: $host:$managedname:$type_sam:$type\n" if $DEBUG;
print_png();
print OUT "exiting : $host:$managedname:$type_sam:$type\n" if $DEBUG;

exit(0);

sub load_rrd {
  my $managedname = shift;
  my $source      = "";

  # print STDERR "008load_rrd $lpar\n";
  if ( $sharepool_id != -1 ) {
    $lpar   = "SharedPool" . $sharepool_id;
    $source = "$inputdir/data/$managedname/$hmc/$lpar.rrm";
    $rrd    = "$idir-$lpar.rrm";
    copy( "$source", "$rrd" ) || error( "Can't create temp file : $rrd or read $source under WEB user identification : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

    # `echo "++ $lpar -- $source -- $rrd"  >> /tmp/e1`;
    load_data_pool_sh($managedname);
    unlink("$input_pool_sh-$type_sam");
  }
  else {
    if ( $lpar =~ "CPU pool" ) {
      $lpar   = "pool";
      $source = "$inputdir/data/$managedname/$hmc/$lpar.rrm";
      $rrd    = "$idir-$lpar.rrm";
      copy( "$source", "$rrd" ) || error( "Can't create temp file : $rrd or read $source under WEB user identification : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      load_data_pool($managedname);
      unlink("$input_pool-$type_sam");
    }
    else {
      my $lpar_no_slash = $lpar;
      $lpar_no_slash =~ s/\//\&\&1/g;
      $source = "$inputdir/data/$managedname/$hmc/$lpar_no_slash.rrm";
      $rrd    = "$idir-$lpar_no_slash.rrm";
      copy( "$source", "$rrd" ) || error( "Can't create temp file : $rrd or read $source under WEB user identification : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      load_data($managedname);
      unlink("$input-$type_sam");
    }
  }
  return 0;
}

# Print the png out
sub print_png {

  if ( !-f "$name.png" ) {
    error("$act_time:$name.png does not exist");
    return 0;
  }
  open( PNG, "< $name.png" ) || error( "Cannot open  $name: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  binmode(PNG);
  while ( read( PNG, $b, 4096 ) ) {
    print "$b";
  }
  unlink("$name.png");
}

# it is load only for 1 LPAR!!!
# 2 and more lpars in the input file causes that always the first timestapm will be inserten no mather about the lpar name
# it could be adjusted ... anyway here should not be loaded more than 1 LPAR ...

sub load_data {
  my $managedname = shift;
  my $counter     = 0;
  my $counter_tot = 0;
  my $counter_ins = 0;
  my @lpar_name   = "";
  my @lpar_time   = "";
  my $last_rec    = "";

  print OUT "updating RRD   : $host:data:$input-$type_sam, $lpar\n" if $DEBUG;
  open( FH, "< $input-$type_sam" ) || error( "Can't open $input-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my @lines = reverse <FH>;
  my $line  = "";
  foreach $line (@lines) {

    #print "$line";
    chomp($line);
    my $time                       = "";
    my $lpar                       = "";
    my $lpar_id                    = "";
    my $curr_proc_units            = "";
    my $curr_procs                 = "";
    my $curr_sharing_mode          = "";
    my $entitled_cycles            = "";
    my $capped_cycles              = "";
    my $uncapped_cycles            = "";
    my $shared_cycles_while_active = "";

    #if ( $HMC == 1 ) {
    #  ($time, $lpar, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles,
    #    $capped_cycles, $uncapped_cycles, $shared_cycles_while_active) = split(/,/,$line);
    #} else {
    #  ($time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles,
    #    $capped_cycles, $uncapped_cycles, $shared_cycles_while_active) = split(/,/,$line);
    #}
    if ( $HMC == 1 ) {
      ( $time, $lpar, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
    }
    if ( $IVM == 1 ) {
      ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
    }
    if ( $SDMC == 1 ) {
      ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
    }

    #print "$time $lpar \n";
    # Check whether the first character is a digit, if not then there is something wrong with the
    # input data
    my $ret = substr( $time, 0, 1 );

    #if (($ret =~ /\D/) || ( $lpar eq '' ))  {
    # do not put there $lpar as it might be NULL when the systems is down, seen it for memory
    if ( $ret =~ /\D/ ) {
      error("Wrong input data, file : $input-$type_sam");

      # leave it as wrong input data
      if ( $type_sam =~ "d" ) {
        error("Might be caused by freshly enabled new server and daily data is not yet collected, then it should disapear after 1 day");
      }
      if ( $type_sam =~ "h" ) {
        error("Might be caused by freshly enabled new server and hourly data is not yet collected, then it should disapear after 1 hour");
      }
      error("Here is the content of the file:");
      error("\$ head -2 \"$input-$type_sam\"");
      my $res = `head -2 \"$input-$type_sam\"`;
      error("$res");
      close(FH);
      return 0;
    }

    if ( $HMC == 0 ) {    # IVM translation ids to names
                          # this will have a problem whether a "," is inside lpar name
      foreach my $li (@lpar_trans) {
        chomp($li);
        ( my $id, my $name ) = split( /,/, $li );

        #print "-- $id - $lpar_id\n";
        if ( $id == $lpar_id ) {
          $lpar = $name;
          last;
        }
      }
    }

    # replace / by &&1, install-html.sh does the reverse thing
    $lpar =~ s/\//\&\&1/g;

    my $t = str2time( substr( $time, 0, 19 ) );
    if ( length($t) < 10 ) {

      # leave it as wrong input data
      error("No valid lpar data time format got from HMC");
      close(FH);
      return 0;
    }

    if ( $step == 3600 ) {

      # Put on the last time possition "00"!!!
      substr( $t, 8, 2, "00" );

      #print "$t $lpar\n";
      #print "Input data: $lpar\n";
    }

    #$rrd = "$idir-$lpar.rr$type_sam";
    # --PH REALT

    #create rrd db if necessary
    #create_rrd($rrd,$t,$counter_tot);
    # --PH REALT --> not necessary

    my $l;
    my $l_count = 0;
    my $found   = -1;
    my $ltime;
    foreach $l (@lpar_name) {
      if ( ( $l =~ $lpar ) && ( length($l) == length($lpar) ) ) {
        $found = $l_count;
      }
      $l_count++;
    }
    if ( $found > -1 ) {
      $ltime   = $lpar_time[$found];
      $l_count = $found;
    }
    else {
      # find out last record in the db
      # as this makes it slowly to test it each time then it is done
      # once per a lpar for whole load and saved into the array
      RRDp::cmd qq(last "$rrd" );
      $last_rec = RRDp::read;
      chomp($$last_rec);
      $lpar_name[$l_count] = $lpar;
      $lpar_time[$l_count] = $$last_rec;
      $ltime               = $$last_rec;
    }

    # when dedicated partitions then there is not set up $curr_proc_units as it is useless
    # I put curr_procs into curr_proc_units to make some gratphs for dedicated lpars
    if ( length($curr_proc_units) == 0 ) {
      $curr_proc_units = $curr_procs;
    }

    # if $curr_proc_units == 0 then lpar is not running and it causing a problem with donated cycles
    if ( $curr_proc_units > 0 ) {

      # exclude POWER5 systems where $shared_cycles_while_active does not exist
      # it is for donation of dedicated CPU lpars
      #if ( $HMC == 1) {   # IVM does not have shared_cycles_while_active
      # IVM supports it now, might be it is a new feature ....
      if ( $curr_sharing_mode =~ "share_idle_procs" || $curr_sharing_mode =~ "share_idle_procs_active" || \$curr_sharing_mode =~ "share_idle_procs_always" ) {

        #if ( length($shared_cycles_while_active) > 0 ) {
        #if ( $shared_cycles_while_active !~ "" ) {
        if ( !$shared_cycles_while_active eq '' ) {

          #print "- $entitled_cycles $shared_cycles_while_active\n";
          $entitled_cycles = $entitled_cycles - $shared_cycles_while_active;

          # necesary due to Perl behaviour whe it convert it to format X.YZ+eXY
          $entitled_cycles = Math::BigInt->new($entitled_cycles);
        }
      }

      #}
    }

    #print "last : $ltime $$last_rec  actuall: $t\n";
    if ( $t > $ltime && length($curr_proc_units) > 0 ) {
      $counter_ins++;

      #print "$lpar: $time $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles \n";
      if ( $keep_virtual == 0 ) {

        # old way without storing number of virtual processors
        RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      }
      else {
        # new one, DHL needs to keep virtual processors for accounting
        RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      }
      my $answer = RRDp::read;

      # to avoid a bug on HMC when it sometimes reports 2 different values for the same time!!
      $lpar_time[$l_count] = $t;
    }
  }
  close(FH);
  return 0;
}

sub load_data_pool {
  my $managedname = shift;

  #  my $counter=0;
  #  my $counter_tot=0;
  my $counter_ins = 0;
  my $ltime       = 0;

  print OUT "updating RRD   : $host:pool:$input_pool-$type_sam, $lpar\n" if $DEBUG;
  open( FH, "< $input_pool-$type_sam" ) || error( "Can't open $input_pool-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my @lines = reverse <FH>;
  foreach my $line (@lines) {
    chomp($line);
    ( my $time, my $total_pool_cycles, my $utilized_pool_cyc, my $configurable_pool_proc_units, my $borrowed_pool_proc_units ) = split( /,/, $line );

    # Check whether first character is a digit, if not then there is something wrong with the
    # input data
    my $ret = substr( $time, 0, 1 );
    if ( $ret =~ /\D/ ) {

      # leave it as wrong input data
      error("$act_time:$host:$managedname : No valid cpu data got from HMC :$ret");
      error("Here is the content of the file:");
      error("\$ head -2 \"$input_pool-$type_sam\"");
      my $res = `head -2 \"$input_pool-$type_sam\"`;
      error("$res");
      close(FH);
      return 0;
    }
    my $t = str2time( substr( $time, 0, 19 ) );
    if ( length($t) < 10 ) {

      # leave it as wrong input data
      error("$act_time:$host:$managedname : No valid cpu data time format got from HMC $t");
      error("Here is the content of the file:");
      error("\$ head -2 \"$input_pool-$type_sam\"");
      my $res = `head -2 \"$input_pool-$type_sam\"`;
      error("$res");
      close(FH);
      return 0;
    }
    if ( $step == 3600 ) {

      # Put on the last time possition "00"!!!
      substr( $t, 8, 2, "00" );
    }

    #$rrd = "$idir-pool.rr$type_sam";
    # --PH REALT

    #create rrd db if necessary
    #create_rrd_pool($rrd,$t);
    # --PH REALT --> not necessary

    # find out last record in the db, do it just once
    if ( !$ltime > 0 ) {
      RRDp::cmd qq(last "$rrd" );
      my $last_rec = RRDp::read;
      chomp($$last_rec);
      $ltime = $$last_rec;
    }

    # print "last pool : $ltime  actuall: $t\n";
    # it updates only if time is newer and there is the data (fix for situation that the data is missing)
    if ( $t > $ltime && length($total_pool_cycles) > 0 ) {
      $counter_ins++;

      #print "$time $t:$total_pool_cycles:$utilized_pool_cyc:$configurable_pool_proc_units:$borrowed_pool_proc_units \n";
      RRDp::cmd qq(update "$rrd" $t:$total_pool_cycles:$utilized_pool_cyc:$configurable_pool_proc_units:$borrowed_pool_proc_units);
      my $answer = RRDp::read;

      # update the time of last record
      $ltime = $t;
    }
  }
  close(FH);
  return 0;
}

sub load_data_pool_sh {
  my $managedname = shift;

  #  my $counter=0;
  #  my $counter_tot=0;
  my $counter_ins         = 0;
  my @shared_pool         = "";
  my $max_pool_units      = "";
  my $reserved_pool_units = "";
  my $ltime               = 0;

  print OUT "updating RRD   : $host:pool_sh:$input_pool_sh-$type_sam,$hmc_user,\@$host,$managedname,$SSH,\n" if $DEBUG;
  print OUT "fetching HMC   : $host:$managedname shared pools\n"                                             if $DEBUG;

  my $def_pool = `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -r pool -m \\"$managedname\\" -F configurable_pool_proc_units,borrowed_pool_proc_units  --filter \"event_types=sample\""`;

  my $ret1 = substr( $def_pool, 0, 1 );
  if ( $ret1 =~ /\D/ ) {

    # leave it, it does not contain a digit, probably is there "No results were found"
    return 0;
  }
  my @def_pool_list = split( /,/, $def_pool );
  my $max_def_pool  = $def_pool_list[0] + $def_pool_list[1];

  # `echo "0081,$max_def_pool," >> /tmp/e1`;

  if ( $max_def_pool <= 0 ) {    # if no answer from SDMC
    $max_def_pool = 1;
  }
  @pool_list           = `$SSH -i $ident $hmc_user\@$host "export LANG=en_US; lshwres -r procpool  -m \\"$managedname\\" -F shared_proc_pool_id,max_pool_proc_units,curr_reserved_pool_proc_units,name"  2>&1 |egrep -iv "Could not create directory|known hosts"`;
  $max_pool_units      = $max_def_pool;
  $reserved_pool_units = $max_def_pool;
  foreach my $linep (@pool_list) {
    ( my $id, $max_pool_units, $reserved_pool_units ) = split( /,/, $linep );
    if ( $sharepool_id == $id ) {
      last;
    }
  }
  if ( $max_pool_units eq "null" ) {    # in case SharedPool0
    $max_pool_units      = $max_def_pool;
    $reserved_pool_units = $max_def_pool;
  }

  #`echo "008x ,ident ,$ident, @pool_list, mpu ,$max_pool_units, rpu ,$reserved_pool_units," >> /tmp/e1`;
  open( FH, "< $input_pool_sh-$type_sam" ) || return 0;
  my @lines = reverse <FH>;
  foreach my $line (@lines) {
    chomp($line);
    ( my $time, my $shared_proc_pool_id, my $total_pool_cycles, my $utilized_pool_cyc ) = split( /,/, $line );

    # Check whether first character is a digit, if not then there is something wrong with the
    # input data
    my $ret = substr( $time, 0, 1 );
    if ( $ret =~ /\D/ ) {
      close(FH);
      return 0;
    }

    if ( $shared_proc_pool_id != $sharepool_id ) {next}

    my $t = str2time( substr( $time, 0, 19 ) );
    if ( length($t) < 10 ) {

      # leave it as wrong input data
      error("$act_time:$host:$managedname : No valid shared cpu pool data time format got from HMC : $t");
      error("Here is the content of the file:");
      error("\$ head -2 \"$input_pool_sh-$type_sam\"");
      my $res = `head -2 \"$input_pool_sh-$type_sam\"`;
      error("$res");
      close(FH);
      return 0;
    }
    if ( $step == 3600 ) {

      # Put on the last time possition "00"!!!
      substr( $t, 8, 2, "00" );
    }

    #$rrd = "$idir-SharedPool$shared_proc_pool_id.rr$type_sam";
    # --PH REALT

    #create rrd db if necessary
    # create_rrd_pool_shared($rrd,$t);
    # --PH REALT --> not necessary

    # find out last record in the db, do it just once
    if ( !$ltime > 0 ) {
      RRDp::cmd qq(last "$rrd" );
      my $last_rec = RRDp::read;
      chomp($$last_rec);
      $ltime = $$last_rec;
    }

    # it updates only if time is newer and there is the data (fix for situation that the data is missing)
    if ( $t > $ltime && length($total_pool_cycles) > 0 ) {

      #  `echo "000,$shared_proc_pool_id,:  $t > $ltime" >> /tmp/e1`;
      $counter_ins++;
      print OUT "$time $t:$total_pool_cycles:$utilized_pool_cyc:$max_pool_units:$reserved_pool_units \n";
      RRDp::cmd qq(update "$rrd" $t:$total_pool_cycles:$utilized_pool_cyc:$max_pool_units:$reserved_pool_units);
      my $answer = RRDp::read;

      # update the time of last record
      $ltime = $t;
    }
  }
  close(FH);
  return 0;
}

sub draw_graph {
  my $text        = shift;
  my $type        = shift;
  my $xgrid       = shift;
  my $lpar        = shift;
  my $managedname = shift;
  my $type_sam    = shift;
  my $t           = "COMMENT: ";
  my $t2          = "COMMENT:\\n";
  my $step_new    = $step;
  my $last        = "COMMENT: ";

  #$step = $STEP;

  if ( $lpar =~ "SharedPool[0-9]" || $lpar =~ "SharedPool[0-9][0-9]" ) {
    my $rrd      = "$idir-$lpar.rr$type_sam";
    my $lpar_sep = $lpar;
    $lpar_sep =~ s/SharedPool/CPU pool /g;
    my $header = "$lpar_sep : last $text";

    # add CPU pool alias into png header (if exists and it is not a default CPU pool)
    my $pool_id = $lpar;
    $pool_id =~ s/SharedPool//g;
    foreach my $pool (@pool_list) {
      my @shared_p = split( /,/, $pool );
      my $name     = $shared_p[3];
      my $id       = $shared_p[0];

      #print STDERR "$pool_id -- $id -- $name";
      if ( $id =~ "HSCL" || $id =~ "VIOSE0" ) {
        next;
      }
      if ( $pool_id == $id ) {
        chomp($name);
        if ( $name !~ "DefaultPool" && $name !~ "SharedPool[0-9]" && $name !~ "SharedPool[0-9][0-9]" ) {
          $header = "$lpar_sep ($name): last $text";
        }
      }
    }

    print OUT "creating graph : $host:$managedname:$lpar:$type_sam:$type\n" if $DEBUG;

    #print "Graph pool :$lpar\n";
    if ( $type =~ "d" ) {
      $header = $header . " (sample rate $step secs)";
      RRDp::cmd qq(last "$rrd");
      my $last_tt = RRDp::read;
      my $l       = localtime($$last_tt);

      # following must be for RRD 1.2+
      $l =~ s/:/\\:/g;
      $t = "COMMENT:Updated\\: $l ";

      # get LAST value from RRD
      RRDp::cmd qq(fetch "$rrd" "AVERAGE" "-s $$last_tt-$step" "-e $$last_tt-$step");
      my $row = RRDp::read;
      chomp($$row);
      my @row_arr = split( /\n/, $$row );
      my $m       = "";
      my $i       = 0;
      foreach $m (@row_arr) {
        chomp($m);
        $i++;
        if ( $i == 3 ) {
          my @m_arr = split( / /, $m );

          # go further ony if it is a digit (avoid it when NaNQ (== no data) is there)
          if ( $m_arr[1] =~ /\d/ && $m_arr[2] =~ /\d/ && $m_arr[3] =~ /\d/ && $m_arr[4] =~ /\d/ ) {

            #print "m : $m\n" if $DEBUG ;
            #print "\n$m_arr[1] $m_arr[2]" if $DEBUG ;
            my $total_pool_cycles = sprintf( "%e", $m_arr[1] );
            my $utilized_pool_cyc = sprintf( "%e", $m_arr[2] );
            my $max_pool_units    = sprintf( "%e", $m_arr[3] );
            my $res_pool_units    = sprintf( "%e", $m_arr[4] );
            if ( $total_pool_cycles != 0 ) {
              my $util = sprintf( "%.2f", ( $utilized_pool_cyc / $total_pool_cycles ) * $max_pool_units );

              #print ("\n $util $curr_proc $entitled_cycles $capped_cycles $uncapped_cycles\n");

              $last = "COMMENT:Last utilization in CPU cores\\:$util";
            }
          }
        }
      }
    }

    if ( !-f "$rrd" ) {
      error("$act_time:$rrd does not exists");
      return 0;
    }

    if ( $lpar =~ "SharedPool[1-9]" || $lpar =~ "SharedPool[1-9][0-9]" ) {

      #print "creating graph : $rrd\n" if $DEBUG ;
      #print "               : $name.png\n" if $DEBUG ;
      # SharedPool0
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$name.png"
        "--title" "$header"
        "--start" "now-1$type"
        "--end" "now-1$type+1$type"
        "--imgformat" "PNG"
        "$disable_rrdtool_tag"
        "--slope-mode"
        "--width=$width"
        "--height=$height"
        "--step=$step_new"
        "--lower-limit=0"
        "--color=BACK#$pic_col"
        "--color=SHADEA#$pic_col"
        "--color=SHADEB#$pic_col"
        "--color=CANVAS#$pic_col"
        "--vertical-label=Utilization in CPU cores"
        "--alt-autoscale-max"
        "--upper-limit=0.2"
        "--units-exponent=1.00"
        "--alt-y-grid"
        "--x-grid=$xgrid"
        "DEF:max=$rrd:max_pool_units:AVERAGE"
        "DEF:res=$rrd:res_pool_units:AVERAGE"
        "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
        "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
        "CDEF:max1=max,res,-"
        "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
        "CDEF:cpuutiltot=cpuutil,max,*"
        "CDEF:utilisa=cpuutil,100,*"
        "COMMENT:   Average   \\n"
        "AREA:res#00FF00: Reserved CPU cores      "
        "GPRINT:res:AVERAGE: %2.1lf"
        "$t2"
        "STACK:max1#FFFF00: Max CPU cores           "
        "GPRINT:max1:AVERAGE: %2.1lf"
        "$t2"
        "LINE1:cpuutiltot#FF0000: Utilization in CPU cores"
        "GPRINT:cpuutiltot:AVERAGE: %2.2lf"
        "COMMENT:("
        "GPRINT:utilisa:AVERAGE: %2.1lf"
        "COMMENT:\%)"
        "$t2"
        "$t2"
        "$last"
        "$t2"
        "$t"
        "$t2"
        "HRULE:0#000000"
        "VRULE:0#000000"
      );
      my $answer = RRDp::read;
      unlink("$rrd");    # delete source RRD DB
      if ( $$answer =~ "ERROR" ) {
        error("Graph rrdtool error : $$answer");
        if ( $$answer =~ "is not an RRD file" ) {
          ( my $err, my $file, my $txt ) = split( /'/, $$answer );
          error("Removing as it seems to be corrupted: $file");
          unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        }
        else {
          error("Graph rrdtool error : $$answer");
        }
      }

      #chomp ($$answer);
    }
    else {
      #print "creating graph : $rrd\n" if $DEBUG ;
      #print "               : $name.png\n" if $DEBUG ;
      # except SharedPool0
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$name.png"
        "--title" "$header"
        "--start" "now-1$type"
        "--end" "now-1$type+1$type"
        "--imgformat" "PNG"
        "$disable_rrdtool_tag"
        "--slope-mode"
        "--width=$width"
        "--height=$height"
        "--step=$step_new"
        "--lower-limit=0"
        "--color=BACK#$pic_col"
        "--color=SHADEA#$pic_col"
        "--color=SHADEB#$pic_col"
        "--color=CANVAS#$pic_col"
        "--vertical-label=Utilization in CPU cores"
        "--alt-autoscale-max"
        "--upper-limit=0.2"
        "--units-exponent=1.00"
        "--alt-y-grid"
        "--x-grid=$xgrid"
        "DEF:max=$rrd:max_pool_units:AVERAGE"
        "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
        "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
        "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
        "CDEF:cpuutiltot=cpuutil,max,*"
        "CDEF:utilisa=cpuutil,100,*"
        "COMMENT:   Average   \\n"
        "AREA:max#00FF00: Max CPU cores           "
        "GPRINT:max:AVERAGE: %2.1lf"
        "$t2"
        "LINE1:cpuutiltot#FF0000: Utilization in CPU cores"
        "GPRINT:cpuutiltot:AVERAGE: %2.2lf"
        "COMMENT:("
        "GPRINT:utilisa:AVERAGE: %2.1lf"
        "COMMENT:\%)"
        "$t2"
        "$t2"
        "$last"
        "$t2"
        "$t"
        "$t2"
        "HRULE:0#000000"
        "VRULE:0#000000"
      );
      my $answer = RRDp::read;
      unlink("$rrd");    # delete source RRD DB
      if ( $$answer =~ "ERROR" ) {
        error("Graph rrdtool error : $$answer");
        if ( $$answer =~ "is not an RRD file" ) {
          ( my $err, my $file, my $txt ) = split( /'/, $$answer );
          error("Removing as it seems to be corrupted: $file");
          unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        }
        else {
          error("Graph rrdtool error : $$answer");
        }
      }

      #chomp ($$answer);
    }
  }
  else {

    if ( $lpar eq "pool" ) {
      my $rrd = "$idir-pool.rr$type_sam";

      # --PH REALT
      #print "creating graph : $rrd\n" if $DEBUG ;
      #print "               : $name.png\n" if $DEBUG ;
      my $header = "CPU pool : last $text";

      print OUT "creating graph : $host:$managedname:$lpar:$type_sam:$type\n" if $DEBUG;

      #print "Graph pool :$lpar\n";
      if ( $type =~ "d" ) {
        $header = $header . " (sample rate $step secs)";
        RRDp::cmd qq(last "$rrd");
        my $last_tt = RRDp::read;
        my $l       = localtime($$last_tt);

        # following must be for RRD 1.2+
        $l =~ s/:/\\:/g;
        $t = "COMMENT:Updated\\: $l ";

        # get LAST value from RRD
        RRDp::cmd qq(fetch "$rrd" "AVERAGE" "-s $$last_tt-$step" "-e $$last_tt-$step");
        my $row = RRDp::read;
        chomp($$row);
        my @row_arr = split( /\n/, $$row );
        my $m       = "";
        my $i       = 0;
        foreach $m (@row_arr) {
          chomp($m);
          $i++;
          if ( $i == 3 ) {
            my @m_arr = split( / /, $m );

            # go further ony if it is a digit (avoid it when NaNQ (== no data) is there)
            if ( $m_arr[1] =~ /\d/ && $m_arr[2] =~ /\d/ && $m_arr[3] =~ /\d/ && $m_arr[4] =~ /\d/ ) {

              #print "m : $m\n" if $DEBUG ;
              #print "\n$m_arr[1] $m_arr[2]" if $DEBUG ;
              my $total_pool_cycles = sprintf( "%e", $m_arr[1] );
              my $utilized_pool_cyc = sprintf( "%e", $m_arr[2] );
              my $conf_proc_units   = sprintf( "%e", $m_arr[3] );
              my $bor_proc_units    = sprintf( "%e", $m_arr[4] );
              if ( $total_pool_cycles != 0 ) {
                my $util = sprintf( "%.2f", ( $conf_proc_units + $bor_proc_units ) * ( $utilized_pool_cyc / $total_pool_cycles ) );

                #print ("\n $util $curr_proc $entitled_cycles $capped_cycles $uncapped_cycles\n");

                $last = "COMMENT:Last utilization in CPU cores\\:$util";
              }
            }
          }
        }
      }

      if ( !-f "$rrd" ) {
        error("$act_time:$rrd does not exists");
        return 0;
      }

      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$name.png"
      "--title" "$header"
      "--start" "now-1$type"
      "--end" "now-1$type+1$type"
      "--imgformat" "PNG"
      "$disable_rrdtool_tag"
      "--slope-mode"
      "--width=$width"
      "--height=$height"
      "--step=$step_new"
      "--lower-limit=0"
      "--color=BACK#$pic_col"
      "--color=SHADEA#$pic_col"
      "--color=SHADEB#$pic_col"
      "--color=CANVAS#$pic_col"
      "--vertical-label=CPU cores"
      "--alt-autoscale-max"
      "--upper-limit=1.00"
      "--units-exponent=1.00"
      "--alt-y-grid"
      "--x-grid=$xgrid"
      "DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
      "DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
      "DEF:cpu=$rrd:conf_proc_units:AVERAGE"
      "DEF:cpubor=$rrd:bor_proc_units:AVERAGE"
      "CDEF:totcpu=cpu,cpubor,+"
      "CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
      "CDEF:cpuutiltot=cpuutil,totcpu,*"
      "CDEF:utilisa=cpuutil,100,*"
      "COMMENT:   Average   \\n"
      "AREA:cpu#00FF00: Configured CPU cores    "
      "GPRINT:cpu:AVERAGE: %2.1lf"
      "$t2"
      "STACK:cpubor#FFFF00: Not assigned CPU cores  "
      "GPRINT:cpubor:AVERAGE: %2.1lf"
      "$t2"
      "LINE1:cpuutiltot#FF0000: Utilization in CPU cores"
      "GPRINT:cpuutiltot:AVERAGE: %2.2lf"
      "COMMENT:("
      "GPRINT:utilisa:AVERAGE: %2.1lf"
      "COMMENT:\%)"
      "$t2"
      "$t2"
      "$last"
      "$t2"
      "$t"
      "$t2"
      "HRULE:0#000000"
      "VRULE:0#000000"
    );
      my $answer = RRDp::read;
      unlink("$rrd");    # delete source RRD DB
      if ( $$answer =~ "ERROR" ) {
        error("Graph rrdtool error : $$answer");
        if ( $$answer =~ "is not an RRD file" ) {
          ( my $err, my $file, my $txt ) = split( /'/, $$answer );
          error("Removing as it seems to be corrupted: $file");
          unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        }
        else {
          error("Graph rrdtool error : $$answer");
        }
      }

      #chomp ($$answer);
      #print "answer: $$answer\n" if $$answer;
    }

    else {    #lpars (everything except pool and mem)

      my $lpar_no_slash = $lpar;
      $lpar_no_slash =~ s/\//\&\&1/g;
      my $rrd = "$idir-$lpar_no_slash.rr$type_sam";

      # --PH REALT
      my $lpar_slash = $lpar;
      $lpar_slash =~ s/\&\&1/\//g;    # to show slash and not &&1 which is general replacemnt for it
      my $header = "LPAR: $lpar_slash : last $text";

      $lpar_slash = $lpar;
      $lpar_slash =~ s/\&\&1/\//g;

      if ( $type =~ "d" ) {
        $header = $header . " (sample rate $step secs)";
        RRDp::cmd qq(last "$rrd");
        my $last_tt = RRDp::read;
        chomp($$last_tt);
        my $l = localtime($$last_tt);

        # following must be for RRD 1.2+
        $l =~ s/:/\\:/g;
        $t = "COMMENT:Updated\\: $l ";

        # get LAST value from RRD
        RRDp::cmd qq(fetch "$rrd" "AVERAGE" "-s $$last_tt-$step" "-e $$last_tt-$step");
        my $row = RRDp::read;
        chomp($$row);
        my @row_arr = split( /\n/, $$row );
        my $m       = "";
        my $i       = 0;

        foreach $m (@row_arr) {
          chomp($m);
          $i++;
          if ( $i == 3 ) {
            my @m_arr = split( / /, $m );

            # go further ony if it is a digit (avoid it when NaNQ (== no data) is there)
            if ( $m_arr[1] =~ /\d/ && $m_arr[2] =~ /\d/ && $m_arr[3] =~ /\d/ && $m_arr[4] =~ /\d/ ) {

              #print "m : $m\n" if $DEBUG ;
              #print "\n$m_arr[1] $m_arr[2]" if $DEBUG ;

              my $entitled_cycles = sprintf( "%e", $m_arr[2] );
              my $capped_cycles   = sprintf( "%e", $m_arr[3] );
              my $uncapped_cycles = sprintf( "%e", $m_arr[4] );
              my $curr_proc       = sprintf( "%e", $m_arr[1] );
              if ( $entitled_cycles != 0 ) {
                my $util = sprintf( "%.2f", ( $capped_cycles + $uncapped_cycles ) / $entitled_cycles ) * $curr_proc;

                #print ("\n $util $curr_proc $entitled_cycles $capped_cycles $uncapped_cycles\n");

                $last = "COMMENT:Last utilization in CPU cores\\:$util";
              }
            }
          }
        }
      }

      if ( !-f "$rrd" ) {
        error("$act_time:$rrd does not exists");
        return 0;
      }

      print OUT "creating graph : $host:$managedname:$lpar_slash:$type_sam:$type\n" if $DEBUG;
      $rrd =~ s/:/\\:/g;
      RRDp::cmd qq(graph "$name.png"
        "--title" "$header"
        "--start" "now-1$type"
        "--end" "now-1$type+1$type"
        "--imgformat" "PNG"
        "$disable_rrdtool_tag"
        "--slope-mode"
        "--width=$width"
        "--height=$height"
        "--step=$step_new"
        "--lower-limit=0.00"
        "--color=BACK#$pic_col"
        "--color=SHADEA#$pic_col"
        "--color=SHADEB#$pic_col"
        "--color=CANVAS#$pic_col"
        "--alt-autoscale-max"
        "--upper-limit=0.1"
        "--vertical-label=CPU cores"
        "--units-exponent=1.00"
	"--alt-y-grid"
        "--x-grid=$xgrid"
        "DEF:cur=$rrd:curr_proc_units:AVERAGE"
        "DEF:ent=$rrd:entitled_cycles:AVERAGE"
        "DEF:cap=$rrd:capped_cycles:AVERAGE"
        "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
        "CDEF:tot=cap,uncap,+"
        "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
        "CDEF:utilperct=util,100,*"
        "CDEF:utiltot=util,cur,*"
        "COMMENT:   Average   \\n"
        "AREA:cur#00FF00: Entitled processor cores"
        "GPRINT:cur:AVERAGE: %2.2lf"
        "$t2"
        "LINE1:utiltot#FF0000: Utilization in CPU cores"
        "GPRINT:utiltot:AVERAGE: %3.3lf"
        "COMMENT:(Entitled CPU utilization"
        "GPRINT:utilperct:AVERAGE: %2.1lf"
        "COMMENT:\%)"
        "$t2"
        "$t2"
        "$last"
        "$t2"
        "$t"
        "$t2"
        "HRULE:0#000000"
        "VRULE:0#000000"
      );
      my $answer = RRDp::read;
      unlink("$rrd");    # delete source RRD DB
      if ( $$answer =~ "ERROR" ) {
        error("Graph rrdtool error : $$answer");
        if ( $$answer =~ "is not an RRD file" ) {
          ( my $err, my $file, my $txt ) = split( /'/, $$answer );
          error("Removing as it seems to be corrupted: $file");
          unlink("$file") || error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        }
        else {
          error("Graph rrdtool error : $$answer");
        }
      }

      #chomp ($$answer);
      #print "answer: $$answer\n" if $$answer;
    }
  }
  return 0;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

sub isdigit {
  my $digit = shift;

  my $digit_work = $digit;
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

