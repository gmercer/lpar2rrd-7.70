package LoadDataModuleHyperV;
use strict;
use Date::Parse;
use RRDp;
use File::Copy;
use Xorux_lib;
use Math::BigInt;

# touch tmp/hyperv-debug to have debug info in load output

my $rrdtool = $ENV{RRDTOOL};

# standard data retentions
my $one_minute_sample     = 86400;
my $five_mins_sample      = 25920;
my $one_hour_sample       = 4320;
my $five_hours_sample     = 1734;
my $one_day_sample        = 1080;
my $one_minute_sample_mem = 86400;
my $five_mins_sample_mem  = 25920;
my $one_hour_sample_mem   = 4320;
my $five_hours_sample_mem = 1734;
my $one_day_sample_mem    = 1080;

my $JUMP_DETECT = 900;

my $rename_once = 0;
my @rename      = "";

my $et_VirtualMachine         = "VirtualMachine";
my $et_HostSystem             = "HostSystem";
my $et_Datastore              = "Datastore";
my $et_ResourcePool           = "ResourcePool";
my $et_Datacenter             = "Datacenter";
my $et_ClusterComputeResource = "ClusterComputeResource";
my $et_s2dPhysicalDisk        = "s2dPhysicalDisk";
my $et_s2dVolume              = "s2dVolume";
my $et_s2dCluster             = "s2dCluster";

my $all_vmware_VMs = "hyperv_VMs";
my $no_inserted    = 66;

sub load_data {    # from HyperV
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $job_name_pointer, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $SSH, $hmc_user, $lpar_uuid, $entity_type, $frk ) = @_;

  #print "43 $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $job_name_pointer, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $SSH, $hmc_user, $lpar_uuid, $entity_type, $frk";
  my @lpar_trans  = @{$trans_tmp};
  my $counter     = 0;
  my $counter_tot = 0;
  my $counter_ins = 0;
  my $last_rec    = "";
  my $rrd         = "";
  my $time        = "";
  my $t           = "";
  my $answer      = "";
  my $utime       = time() + 3600;
  $rename_once = 0;
  my $keep_virtual = 0;

  if ( $ENV{KEEP_VIRTUAL} ) {
    $keep_virtual = $ENV{KEEP_VIRTUAL};    # keep number of virt processors in RRD --> etc/.magic
  }
  else {
    $keep_virtual = 0;
  }

  if ( $step > 60 ) {
    $JUMP_DETECT = 10800;                  # 3 hours
  }
  if ( $type_sam =~ m/d/ ) {
    $JUMP_DETECT = 178000                  # 2 days + for daily graphs/feed
  }

  print "updating RRD   : $host:$managedname:data:$wrkdir/$managedname/$host/$lpar_uuid.rr$type_sam \$last_file $last_file $frk\n" if $DEBUG;

  my @lines;
  my $update_line = $$input;

  ( $t, undef ) = split( ",", $update_line );    #first record time to update

  # print "80 LoadDataModulHyperV \$t $t \$update_line $update_line\n";

  my $line      = "";
  my @rrd_exist = "";
  my @rmd_exist = "";
  my @rsd_exist = "";

  my @lpar_name = "";
  my @lpar_time = "";
  my @lpar_jump = "";

  my $l_count_rmd   = 0;
  my $ltime_rmd     = 0;
  my @lpar_name_rmd = "";
  my @lpar_time_rmd = "";

  my $l_count_rsd   = 0;
  my $ltime_rsd     = 0;
  my @lpar_name_rsd = "";
  my @lpar_time_rsd = "";

  my $last_time   = "";
  my $error_once  = 0;
  my $error_count = 0;

  #  foreach $line (@lines) left_curly
  {
    $line = $update_line;

    #print "$line";
    chomp($line);
    $time = "";
    my $lpar                       = "";
    my $lpar_id                    = "";
    my $curr_proc_units            = "";
    my $curr_procs                 = "";
    my $curr_sharing_mode          = "";
    my $entitled_cycles            = "";
    my $capped_cycles              = "";
    my $uncapped_cycles            = "";
    my $shared_cycles_while_active = "";
    my $mem_mode                   = "";
    my $curr_mem                   = "";
    my $phys_run_mem               = "";
    my $curr_io_entitled_mem       = "";
    my $mapped_io_entitled_mem     = "";
    my $mem_overage_cooperation    = "";
    my $idle_cycles                = 0;

    if ( $line =~ "HSCL" || $line =~ "VIOSE0" || $line =~ "No results were found" || $line =~ "invalid parameter was entered" ) {

      # something wrong with the input data
      main::error("$host:$managedname : wrong input data in $host:$managedname:data:$input-$type_sam : $line");
      return 1;
    }
    if ( $line =~ "An invalid parameter value was entered" ) {

      # something wrong with the input data
      main::error("$host:$managedname : wrong input data in $host:$managedname:data:$input-$type_sam : $line");
      next;
    }

    # Check whether the first character is a digit, if not then there is something wrong with the
    # input data
    my $ret = substr( $time, 0, 1 );
    if ( $ret =~ /\D/ ) {
      main::error("Wrong input data, file : $input-$type_sam : $line");

      # leave it as wrong input data
      if ( $type_sam =~ "d" ) {
        main::error("Migh be caused by freshly enabled new server and daily data is not yet collected, then it should disapear after  1 day");
      }
      if ( $type_sam =~ "h" ) {
        main::error("Migh be caused by freshly enabled new server and daily data is not yet collected, then it should disapear after  1 day");
      }
      main::error("$host:$managedname :Here is the content of the file");
      main::error("head -1/tail -1 \"$input-$type_sam\"");
      my $res = `head -1 \"$input-$type_sam\"`;
      chomp($res);
      main::error("$res");
      $res = `tail -1 \"$input-$type_sam\"`;
      chomp($res);
      main::error("$res");

      # close(FH);
      return 1;
    }

    $lpar = $lpar_uuid;
    if ( $lpar =~ m/IOR Collection LP/ ) {    #it is some trash, it exists time to tme, some IBM internal ...
      next;                                   #ignore it
    }
    if ( $lpar eq '' ) {
      next;                                   #again something wrong
    }

    # replace / by &&1, install-html.sh does the reverse thing
    if ( $lpar !~ /JOB\/CPUTOP/ ) {
      $lpar =~ s/\//\&\&1/g;
    }

    if ( $lpar =~ m/\"/ ) {

      # LPAR cannot contain double quote, it is an illegal character in the lpar name, report it once and ignore it
      if ( $error_once == 0 ) {
        main::error( "$host:$managedname :LPAR cannot contain double quote, it is an illegal character in the lpar name: $lpar : $line : " . __FILE__ . ":" . __LINE__ );
      }
      $error_once++;
      next;
    }

    if ( $lpar =~ /JOB\/CPUTOP/ ) {    # change CPUTOP -> cputop
      $lpar =~ s/CPUTOP/cputop/;
      $rrd = "$wrkdir/$managedname/$host/$lpar.mm$type_sam";
    }
    else {
      $rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";
    }

    #  print "LDMV $rrd\n";
    #  create rrd db if necessary
    #  find out if rrd db exist, and place info to the array to do not check its existency every time
    my $rrd_exist_ok  = 0;
    my $rrd_exist_row = 0;
    foreach my $row (@rrd_exist) {
      $rrd_exist_row++;
      if ( $row =~ m/^$lpar$/ ) {
        $rrd_exist_ok = 1;
        last;
      }
    }
    if ( !-f $rrd ) {
      if ( $rrd_exist_ok == 0 ) {
        print "create_rrd_hyperv_vm($rrd,$t,$counter_tot,$step,$type_sam,$DEBUG,$host,$managedname,$no_time,$act_time,$SSH,$hmc_user,$wrkdir,$lpar,$t,$keep_virtual,$entity_type);\n";    #if $DEBUG == 2;

        #        return if $rrd =~ /JOB/;
        my $ret = create_rrd_hyperv_vm( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, $SSH, $hmc_user, $wrkdir, $lpar, $t, $keep_virtual, $entity_type );
        if ( $ret == 1 ) {

          # this lpar has been recently renamed, ignore it then
          return 1;                                                                                                                                                                       # when vmware then no next;
        }
        if ( $ret == 2 ) {
          return 1;                                                                                                                                                                       # RRD creation problem, skip whole load
        }
        $rrd_exist[$rrd_exist_row] = $lpar;
      }
    }

    #  print "find out last record and save it\n";
    # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
    my $l_count = 0;
    my $found   = -1;

    my $ltime;
    my $lpar_meta = quotemeta($lpar);
    foreach my $l (@lpar_name) {
      if ( $l =~ m/^$lpar_meta$/ ) {
        $found = $l_count;
        last;
      }
      $l_count++;
    }
    if ( $found > -1 ) {
      $ltime = $lpar_time[$found];
      print "this is not expected for vmware \$ltime $ltime\n";
      $l_count = $found;
    }
    else {
      # find out last record in the db
      # as this makes it slowly to test it each time then it is done
      # once per a lpar for whole load and saved into the array

      # construction against crashing daemon Perl code when RRDTool error appears
      # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
      # construction is not too costly as it runs once per each load
      # print "254 \$rrd $rrd\n";
      eval {
        RRDp::cmd qq(last "$rrd" );
        $last_rec = RRDp::read;
      };
      if ($@) {
        rrd_error( $@, $rrd );
        if ( $rrd_exist[$rrd_exist_row] =~ m/^$lpar$/ ) {
          $rrd_exist[$rrd_exist_row] = "";
        }
        next;
      }
      chomp($$last_rec);
      $lpar_name[$l_count] = $lpar;
      $lpar_time[$l_count] = $$last_rec;
      $lpar_jump[$l_count] = 0;
      $ltime               = $$last_rec;

      #  print "272 last record from rrdfile $rrd \$ltime $ltime\n";
    }

    my $max_cycles = 0;
    if ( defined $update_line ) {
      $max_cycles = $update_line =~ tr/ //;
      $max_cycles++;    # cycle must go at least one
    }

    # print "\$update_line ,$update_line,\n";
    # $max_cycles prevents infinite the cycle
    while ( defined $t && defined $ltime && $t <= $ltime && $max_cycles > 0 ) {    # try to skip one data piece
      my $skipped = "";
      if ( defined $update_line && $update_line ne "" ) {
        ( $skipped, $update_line ) = split( " ", $update_line, 2 );
      }
      if ( defined $update_line && $update_line ne "" ) {
        ( $t, undef ) = split( ",", $update_line );
      }
      if ( !defined $t || $t eq "" ) {
        $t = $ltime;
      }
      print "data skipped   : $skipped\n";
      $max_cycles--;
    }

    if ( defined $t ) {
      print "               : \$t $t > \$ltime $ltime (first data time to update > last rec) HyperV $frk\n";
    }

    if ( defined $t && defined $ltime && $t > $ltime ) {

      #  print "$lpar: $time $t $update_line \n";
      $update_line =~ s/ $//g;
      my $result   = rindex( $update_line, " " );
      my $fragment = substr $update_line, $result + 1;    #get time of last record in update line
      ( $last_time, undef ) = split( ",", $fragment );
      ( my $sec, my $min, my $hour, my $mday, my $mon, my $year ) = localtime($last_time);
      $mon++;
      $year += 1900;
      $last_time = "$mon/$mday/$year $hour:$min:$sec";    # change day <-> mon for US date format
      $update_line =~ s/,/:/g;

      # last rescue
      # if in update line is for any reason no info, insert "U" instead
      # $update_line 1547899841:0:0:2994772:512:U:68:U:U:U:U:U:U:560::::U:U:1
      if ( index( $update_line, "::" ) != -1 ) {
        main::error("\$update_line contains uninitialised atoms for $rrd $update_line");
        $update_line =~ s/::/:U:/g;
        $update_line =~ s/::/:U:/g;    # must be twice !!!
        $update_line =~ s/:$/:U/g;     # and if colon is at the end
      }
      if ( index( $update_line, "UnDeFiNeD" ) != -1 ) {
        main::error("\$update_line contains UnDeFiNeD $update_line");
        $update_line =~ s/UnDeFiNeD/U/g;
      }

      # print "329 $rrd $update_line\n";
      eval {
        RRDp::cmd qq(update "$rrd" $update_line);
        $answer = RRDp::read;
      };
      if ($@) {
        main::error("\$answer $answer \$update_line $update_line");
        return;
      }

      if ( $counter_ins == 0 ) {
        $counter_ins++;    # just to force update last.txt
      }

      if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
        main::error(" $host:$managedname : $rrd : $t: : $line : $$answer");
        if ( $$answer =~ m/is not an RRD file/ ) {
          ( my $err, my $file, my $txt ) = split( /'/, $$answer );
          main::error("Removing as it seems to be corrupted: $file");
          unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
        }
      }

      if ( $rrd =~ /\/JOB\// ) {    # write JOB info to cfg file
        my $job_name = $$job_name_pointer;

        # $update_line 1636367469:5732:1717.46875:11730944:U
        ( undef, my $job_pid, undef ) = split ":", $update_line;
        $job_pid .= ".cfg";
        my $cfg_file = $rrd;
        $cfg_file =~ s/cputop.*/$job_pid/;

        # print "351 LoadDataModuleHyperV.pm update \$rrd $rrd \$update_line $update_line \$job_pid $job_pid \$job_name $job_name \$cfg_file $cfg_file\n";
        if ( open( my $FHLT, "> $cfg_file" ) ) {
          print $FHLT "noname:$job_name";
          close($FHLT);
        }
        else {
          main::error( " Can't open $rrd : $! " . __FILE__ . ":" . __LINE__ );
        }
      }

    }
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:lpar $counter_ins record(s) $frk\n" if $DEBUG;
  }
  else {
    print "NOT inserted   : $host:$managedname:lpar $counter_ins record(s) $frk\n" if $DEBUG;
    return $no_inserted;    # no success
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 && $last_file ne "" ) {
    my $line = 0;
    if ( -f "$wrkdir/$managedname/$host/$last_file" ) {
      open( my $FHLT, "< $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file \$type_sam ,$type_sam, : $!" . __FILE__ . ":" . __LINE__ );
      $line = <$FHLT>;
      close($FHLT);
    }
    if ( !defined $line ) {    # for sure
      $line = 0;
    }
    chomp($line);
    my $old_time = str2time($line);
    my $new_time = str2time($last_time);
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file $new_time instead of $old_time $frk\n" if $DEBUG;

    # update only when it is newer ! e.g. datastore has 2 rrd files and so on
    if ( $new_time > $old_time ) {
      open( my $FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
      print $FHLT "$last_time";
      close($FHLT);
    }
  }

  return 99;    # symbol of success
}

sub create_rrd_hyperv_vm {
  my $rrd          = shift;
  my $start_time   = shift;
  my $counter_tot  = shift;
  my $step         = shift;
  my $type_sam     = shift;
  my $DEBUG        = shift;
  my $host         = shift;
  my $managedname  = shift;
  my $no_time      = shift;
  my $act_time     = shift;
  my $SSH          = shift;
  my $hmc_user     = shift;
  my $wrkdir       = shift;
  my $lpar         = shift;
  my $time_rec     = shift;
  my $keep_virtual = shift;
  my $entity_type  = shift;
  my $step_new     = $step;
  my $no_time_new  = $no_time;

  # do not use  passed $start_time!!!!
  $start_time = time - ( 20 * 24 * 3600 );    # for hyperv enough
  print "370 test if exists file $rrd\n" if $DEBUG == 2;

  if ( -f "$rrd" ) {
    if ( -s "$rrd" == 0 ) {                   # it was only signal file with no data
      `rm -f "$rrd"`;
    }
    else {
      return 0;
    }
  }
  load_retentions( $step, $act_time );        # load data retentions
                                              # print "0000 $one_minute_sample - $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
  print "381 create_rrd_hyperv_vm: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
  touch("create_rrd_hyperv_vm $rrd");

  # print "++ $rrd $start_time $step_new - $no_time_new \n";

  if ( $entity_type eq $et_ClusterComputeResource ) {
    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:CPU_usage_MHz:GAUGE:$no_time_new:0:U"
          "DS:CPU_usage_Proc:GAUGE:$no_time_new:0:U"
          "DS:CPU_reserved_MHz:GAUGE:$no_time_new:0:U"
          "DS:CPU_total_MHz:GAUGE:$no_time_new:0:U"
          "DS:Cluster_eff_CPU_MHz:GAUGE:$no_time_new:0:U"
          "DS:Cluster_eff_mem_MB:GAUGE:$no_time_new:0:U"
          "DS:Memory_total_MB:GAUGE:$no_time_new:0:U"
          "DS:Memory_shared_KB:GAUGE:$no_time_new:0:U"
          "DS:Memory_zero_KB:GAUGE:$no_time_new:0:U"
          "DS:Memory_baloon_KB:GAUGE:$no_time_new:0:U"
          "DS:Memory_consumed_KB:GAUGE:$no_time_new:0:U"
          "DS:Memory_overhead_KB:GAUGE:$no_time_new:0:U"
          "DS:Memory_active_KB:GAUGE:$no_time_new:0:U"
          "DS:Memory_granted_KB:GAUGE:$no_time_new:0:U"
          "DS:Memory_compress_KB:GAUGE:$no_time_new:0:U"
          "DS:Memory_reserved_MB:GAUGE:$no_time_new:0:U"
          "DS:Memory_swap_KB:GAUGE:$no_time_new:0:U"
          "DS:Mem_cmprssion_KBps:GAUGE:$no_time_new:0:U"
          "DS:Mem_dcompress_KBps:GAUGE:$no_time_new:0:U"
          "DS:Memory_usage_Proc:GAUGE:$no_time_new:0:U"
          "DS:Power_cup_Watt:GAUGE:$no_time_new:0:U"
          "DS:Power_usage_Watt:GAUGE:$no_time_new:0:U"
          "RRA:AVERAGE:0.5:1:$one_minute_sample"
          "RRA:AVERAGE:0.5:5:$five_mins_sample"
          "RRA:AVERAGE:0.5:60:$one_hour_sample"
          "RRA:AVERAGE:0.5:300:$five_hours_sample"
          "RRA:AVERAGE:0.5:1440:$one_day_sample"

        );
  }
  elsif ( $entity_type eq $et_ResourcePool ) {
    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:CPU_usage_MHz:GAUGE:$no_time_new:0:U"
            "DS:Memory_shared_KB:GAUGE:$no_time_new:0:U"
            "DS:Memory_zero_KB:GAUGE:$no_time_new:0:U"
            "DS:Memory_baloon_KB:GAUGE:$no_time_new:0:U"
            "DS:Memory_consumed_KB:GAUGE:$no_time_new:0:U"
            "DS:Memory_overhead_KB:GAUGE:$no_time_new:0:U"
            "DS:Memory_active_KB:GAUGE:$no_time_new:0:U"
            "DS:Memory_granted_KB:GAUGE:$no_time_new:0:U"
            "DS:Memory_compress_KB:GAUGE:$no_time_new:0:U"
            "DS:Memory_swap_KB:GAUGE:$no_time_new:0:U"
            "DS:Mem_cmprssion_KBps:GAUGE:$no_time_new:0:U"
            "DS:Mem_dcompress_KBps:GAUGE:$no_time_new:0:U"
            "DS:CPU_limit:GAUGE:$no_time_new:0:U"
            "DS:CPU_reservation:GAUGE:$no_time_new:0:U"
            "DS:Memory_limit:GAUGE:$no_time_new:0:U"
            "DS:Memory_reservation:GAUGE:$no_time_new:0:U"
            "DS:CPU_usage_Proc:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$one_minute_sample"
            "RRA:AVERAGE:0.5:5:$five_mins_sample"
            "RRA:AVERAGE:0.5:60:$one_hour_sample"
            "RRA:AVERAGE:0.5:300:$five_hours_sample"
            "RRA:AVERAGE:0.5:1440:$one_day_sample"
            );
  }
  elsif ( $entity_type eq $et_s2dPhysicalDisk ) {

    #print "470 LoadDataModuleHyperV.pm \$rrd $rrd\n";
    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:IOPS_Read:GAUGE:$no_time_new:0:U"
            "DS:IOPS_Write:GAUGE:$no_time_new:0:U"
            "DS:Latency_Read_sec:GAUGE:$no_time_new:0:U"
            "DS:Latency_Write_sec:GAUGE:$no_time_new:0:U"
            "DS:Throughput_Read_B:GAUGE:$no_time_new:0:U"
            "DS:Throughput_Write_B:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$five_mins_sample"
            "RRA:AVERAGE:0.5:12:$one_hour_sample"
            "RRA:AVERAGE:0.5:60:$five_hours_sample"
            "RRA:AVERAGE:0.5:288:$one_day_sample"
            );
  }
  elsif ( $entity_type eq $et_s2dVolume ) {
    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:Size_Available:GAUGE:$no_time_new:0:U"
            "DS:Size_Total:GAUGE:$no_time_new:0:U"
            "DS:IOPS_Read:GAUGE:$no_time_new:0:U"
            "DS:IOPS_Write:GAUGE:$no_time_new:0:U"
            "DS:Latency_Read_sec:GAUGE:$no_time_new:0:U"
            "DS:Latency_Write_sec:GAUGE:$no_time_new:0:U"
            "DS:Throughput_Read_B:GAUGE:$no_time_new:0:U"
            "DS:Throughput_Write_B:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$five_mins_sample"
            "RRA:AVERAGE:0.5:12:$one_hour_sample"
            "RRA:AVERAGE:0.5:60:$five_hours_sample"
            "RRA:AVERAGE:0.5:288:$one_day_sample"
            );
  }
  elsif ( $entity_type eq $et_s2dCluster ) {

    #print "504 LoadDataModuleHyperV.pm \$rrd $rrd\n";
    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:vol_IOPS_R:GAUGE:$no_time_new:0:U"
            "DS:vol_IOPS_W:GAUGE:$no_time_new:0:U"
            "DS:vol_Lat_R:GAUGE:$no_time_new:0:U"
            "DS:vol_Lat_W:GAUGE:$no_time_new:0:U"
            "DS:vol_Thru_R:GAUGE:$no_time_new:0:U"
            "DS:vol_Thru_W:GAUGE:$no_time_new:0:U"
            "DS:vol_Size_Av:GAUGE:$no_time_new:0:U"
            "DS:vol_Size_Tot:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$five_mins_sample"
            "RRA:AVERAGE:0.5:12:$one_hour_sample"
            "RRA:AVERAGE:0.5:60:$five_hours_sample"
            "RRA:AVERAGE:0.5:288:$one_day_sample"
            );
  }
  elsif ( $entity_type eq $et_HostSystem ) {

    # print "445 LoadDataModuleHyperV.pm \$rrd $rrd\n";
    if ( $rrd =~ /Local_Fixed_Disk_/ || $rrd =~ /Cluster_Storage_/ ) {
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:FreeSpace:GAUGE:$no_time_new:0:U"
            "DS:Size:GAUGE:$no_time_new:0:U"
            "DS:Timestamp_PerfTime:GAUGE:$no_time_new:0:U"
            "DS:Frequency_PerfTime:GAUGE:$no_time_new:0:U"
            "DS:DiskReadBytesPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskWriteBytesPerse:GAUGE:$no_time_new:0:U"
            "DS:DiskReadsPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskWritesPersec:GAUGE:$no_time_new:0:U"
            "DS:AvgDisksecPerRead:GAUGE:$no_time_new:0:U"
            "DS:AvgDisksecPerReadB:GAUGE:$no_time_new:0:U"
            "DS:AvgDisksecPerWrite:GAUGE:$no_time_new:0:U"
            "DS:AvgDisksecPerWriteB:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$one_minute_sample"
            "RRA:AVERAGE:0.5:5:$five_mins_sample"
            "RRA:AVERAGE:0.5:60:$one_hour_sample"
            "RRA:AVERAGE:0.5:300:$five_hours_sample"
            "RRA:AVERAGE:0.5:1440:$one_day_sample"
            );
    }
    elsif ( $rrd =~ /CPUqueue/ ) {
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:CPU_queue:GAUGE:$no_time_new:0:U"
            "DS:CPU_processes:GAUGE:$no_time_new:0:U"
            "DS:CPU_threads:GAUGE:$no_time_new:0:U"
            "DS:CPU_systemcalls:GAUGE:$no_time_new:0:U"
            "DS:Timestamp_PerfTime:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$one_minute_sample"
            "RRA:AVERAGE:0.5:5:$five_mins_sample"
            "RRA:AVERAGE:0.5:60:$one_hour_sample"
            "RRA:AVERAGE:0.5:300:$five_hours_sample"
            "RRA:AVERAGE:0.5:1440:$one_day_sample"
            );
    }
    elsif ( $lpar =~ /^JOB\/cputop/ ) {
      my $step_for_create = 1800;                ## for jobs is OK
      my $no_time         = $step_for_create;    # heartbeat MUST be same as step!!! do not change it
      $one_minute_sample = 24 * 2 * 8;           # 24 hours x steps in one hour x 8 days
      print "549 \$lpar $lpar \$rrd $rrd\n";

      # prepare dir JOB it not exists
      ( my $job_dir, undef ) = split "cputop", $rrd;
      if ( !-d $job_dir ) {
        print "mkdir          : $job_dir\n";     # if $DEBUG;
        mkdir( "$job_dir", 0755 ) || error( " Cannot mkdir $job_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }

      # return 2;
      RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_for_create"
            "DS:pid:GAUGE:$no_time:0:U"
            "DS:time_diff:GAUGE:$no_time:0:U"
            "DS:rss:GAUGE:$no_time:0:U"
            "DS:vzs:GAUGE:$no_time:0:U"
            "RRA:AVERAGE:0.5:1:$one_minute_sample"
            );
    }
    else {
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:PercentTotalRunTime:GAUGE:$no_time_new:0:U"
            "DS:Timestamp_PerfTime:GAUGE:$no_time_new:0:U"
            "DS:Frequency_PerfTime:GAUGE:$no_time_new:0:U"
            "DS:TotalPhysMemory:GAUGE:$no_time_new:0:U"
            "DS:AvailableMBytes:GAUGE:$no_time_new:0:U"
            "DS:MemoryAvailable:GAUGE:$no_time_new:0:U"
            "DS:CacheBytes:GAUGE:$no_time_new:0:U"
            "DS:DiskBytesPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskReadBytesPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskReadsPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskTransfersPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskWriteBytesPerse:GAUGE:$no_time_new:0:U"
            "DS:DiskWritesPersec:GAUGE:$no_time_new:0:U"
            "DS:BytesReceivedPersec:GAUGE:$no_time_new:0:U"
            "DS:BytesSentPersec:GAUGE:$no_time_new:0:U"
            "DS:BytesTotalPersec:GAUGE:$no_time_new:0:U"
            "DS:PagesInputPersec:GAUGE:$no_time_new:0:U"
            "DS:PagesOutputPersec:GAUGE:$no_time_new:0:U"
            "DS:vCPU:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$one_minute_sample"
            "RRA:AVERAGE:0.5:5:$five_mins_sample"
            "RRA:AVERAGE:0.5:60:$one_hour_sample"
            "RRA:AVERAGE:0.5:300:$five_hours_sample"
            "RRA:AVERAGE:0.5:1440:$one_day_sample"
            );
    }
  }
  elsif ( $entity_type eq $et_Datastore && $rrd =~ /rrs$/ ) {    # irregular update / 30 minutes

    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:freeSpace:GAUGE:$no_time_new:0:U"
            "DS:Disk_used:GAUGE:$no_time_new:0:U"
            "DS:Disk_provisioned:GAUGE:$no_time_new:0:U"
            "DS:Disk_capacity:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$one_minute_sample"
            "RRA:AVERAGE:0.5:5:$five_mins_sample"
            "RRA:AVERAGE:0.5:60:$one_hour_sample"
            "RRA:AVERAGE:0.5:300:$five_hours_sample"
            "RRA:AVERAGE:0.5:1440:$one_day_sample"
            );
  }
  elsif ( $entity_type eq $et_Datastore && $rrd =~ /rrt$/ ) {    # regular update

    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:Datastore_read:GAUGE:$no_time_new:0:U"
            "DS:Datastore_write:GAUGE:$no_time_new:0:U"
            "DS:Datastore_ReadAvg:GAUGE:$no_time_new:0:U"
            "DS:Datastore_WriteAvg:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$one_minute_sample"
            "RRA:AVERAGE:0.5:5:$five_mins_sample"
            "RRA:AVERAGE:0.5:60:$one_hour_sample"
            "RRA:AVERAGE:0.5:300:$five_hours_sample"
            "RRA:AVERAGE:0.5:1440:$one_day_sample"
            );
  }
  else {    # it is VM
    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
            "DS:PercentTotalRunTime:GAUGE:$no_time_new:0:U"
            "DS:Timestamp_PerfTime:GAUGE:$no_time_new:0:U"
            "DS:Frequency_PerfTime:GAUGE:$no_time_new:0:U"
            "DS:TotalPhysMemory:GAUGE:$no_time_new:0:U"
            "DS:AvailableMBytes:GAUGE:$no_time_new:0:U"
            "DS:MemoryAvailable:GAUGE:$no_time_new:0:U"
            "DS:CacheBytes:GAUGE:$no_time_new:0:U"
            "DS:DiskBytesPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskReadBytesPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskReadsPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskTransfersPersec:GAUGE:$no_time_new:0:U"
            "DS:DiskWriteBytesPerse:GAUGE:$no_time_new:0:U"
            "DS:DiskWritesPersec:GAUGE:$no_time_new:0:U"
            "DS:BytesReceivedPersec:GAUGE:$no_time_new:0:U"
            "DS:BytesSentPersec:GAUGE:$no_time_new:0:U"
            "DS:BytesTotalPersec:GAUGE:$no_time_new:0:U"
            "DS:PagesInputPersec:GAUGE:$no_time_new:0:U"
            "DS:PagesOutputPersec:GAUGE:$no_time_new:0:U"
            "DS:vCPU:GAUGE:$no_time_new:0:U"
            "RRA:AVERAGE:0.5:1:$one_minute_sample"
            "RRA:AVERAGE:0.5:5:$five_mins_sample"
            "RRA:AVERAGE:0.5:60:$one_hour_sample"
            "RRA:AVERAGE:0.5:300:$five_hours_sample"
            "RRA:AVERAGE:0.5:1440:$one_day_sample"
            );
  }
  print "676 \$rrd $rrd\n";

  #  if ($rrd =~ /JOB\/cputop/) {
  #    if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample") ) {
  #      main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
  #      RRDp::end;
  #      RRDp::start "$rrdtool";
  #      return 2;
  #    }
  #  }
  #  elsif ( $step_new == 300 ) {
  if ( $step_new == 300 ) {
    if ( !Xorux_lib::create_check("file: $rrd, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
      main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
      RRDp::end;
      RRDp::start "$rrdtool";
      return 2;
    }
  }
  elsif ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
    main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }

  my $vmware_signal_file = "$wrkdir/$managedname/$host/hyperv.txt";
  if ( !-f "$vmware_signal_file" ) {
    `touch "$vmware_signal_file"`;    # say install_html.sh that there was any change
  }

  return 0;
}

sub touch {
  my $text = shift;

  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-run";
  my $host       = $ENV{HMC};
  my $DEBUG      = $ENV{DEBUG};

  if ( !-f $new_change ) {
    `touch $new_change`;    # say install_html.sh that there was any change
    if ( $text eq '' ) {
      print "touch          : $host $new_change\n" if $DEBUG;
    }
    else {
      print "touch          : $host $new_change : $text\n" if $DEBUG;
    }
  }

  return 0;
}

sub load_retentions {
  my $step     = shift;
  my $act_time = shift;
  my $basedir  = $ENV{INPUTDIR};

  # standards
  $one_minute_sample = 86400;
  $five_mins_sample  = 25920;
  $one_hour_sample   = 4320;
  $five_hours_sample = 1734;
  $one_day_sample    = 1080;

  $one_minute_sample_mem = 86400;
  $five_mins_sample_mem  = 25920;
  $one_hour_sample_mem   = 4320;
  $five_hours_sample_mem = 1734;
  $one_day_sample_mem    = 1080;

  if ( !-f "$basedir/etc/retention.cfg" ) {

    # standard retentions in place
    return 0;
  }

  # extra retentions are specifiled in $basedir/etc/retention.cfg
  open( my $FH, "< $basedir/etc/retention.cfg" ) || main::error("Can't read from: $basedir/etc/retention.cfg: $!");

  my @lines = <$FH>;
  foreach my $line (@lines) {
    chomp($line);

    # MEM
    if ( $line =~ m/^1min/ && $line =~ m/MEM/ ) {
      ( my $trash, $one_minute_sample_mem ) = split( /:/, $line );
      next;
    }
    if ( $line =~ m/^5min/ && $line =~ m/MEM/ ) {
      ( my $trash, $five_mins_sample_mem ) = split( /:/, $line );
      next;
    }
    if ( $line =~ m/^60min/ && $line =~ m/MEM/ ) {
      ( my $trash, $one_hour_sample_mem ) = split( /:/, $line );
      next;
    }
    if ( $line =~ m/^300min/ && $line =~ m/MEM/ ) {
      ( my $trash, $five_hours_sample_mem ) = split( /:/, $line );
      next;
    }
    if ( $line =~ m/^1440min/ && $line =~ m/MEM/ ) {
      ( my $trash, $one_day_sample_mem ) = split( /:/, $line );
      next;
    }

    # CPU
    if ( $line =~ m/^1min/ ) {
      ( my $trash, $one_minute_sample ) = split( /:/, $line );
    }
    if ( $line =~ m/^5min/ ) {
      ( my $trash, $five_mins_sample ) = split( /:/, $line );
    }
    if ( $line =~ m/^60min/ ) {
      ( my $trash, $one_hour_sample ) = split( /:/, $line );
    }
    if ( $line =~ m/^300min/ ) {
      ( my $trash, $five_hours_sample ) = split( /:/, $line );
    }
    if ( $line =~ m/^1440min/ ) {
      ( my $trash, $one_day_sample ) = split( /:/, $line );
    }
  }

  close($FH);

  $step              = $step / 60;
  $one_minute_sample = $one_minute_sample / $step;
  $five_mins_sample  = $five_mins_sample / $step;
  $one_hour_sample   = $one_hour_sample / $step;
  $five_hours_sample = $five_hours_sample / $step;
  $one_day_sample    = $one_day_sample / $step;

  $one_minute_sample_mem = $one_minute_sample_mem / $step;
  $five_mins_sample_mem  = $five_mins_sample_mem / $step;
  $one_hour_sample_mem   = $one_hour_sample_mem / $step;
  $five_hours_sample_mem = $five_hours_sample_mem / $step;
  $one_day_sample_mem    = $one_day_sample_mem / $step;
  return 1;
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

sub recent_rename {
  my $host          = shift;
  my $managedname   = shift;
  my $lpar          = shift;
  my $wrkdir        = shift;
  my $DEBUG         = shift;
  my $time_rec      = shift;
  my $act_time      = shift;
  my $RENAME_PERIOD = 600;     # if there is detected same lpar name 10 minutes after a rename then it is ignored

  my $rename_tmp = "$wrkdir/$managedname/$host/rename.tmp";
  if ( !-f "$rename_tmp" ) {
    return 0;
  }

  #print "001 $rename_tmp $lpar\n";

  open( my $FR, "< $rename_tmp" ) || main::error( " Can't open $rename_tmp : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my @lines = <$FR>;
  close($FR);
  foreach my $line (@lines) {
    chomp($line);
    ( my $time, my $lpar_act ) = split( /:/, $line );

    #print "002 $line $time - $lpar_act - $lpar - ($time + $RENAME_PERIOD) > $time_rec\n";
    if ( $lpar_act eq '' ) {
      next;    # some trash
    }
    if ( $lpar_act =~ m/^$lpar$/ && ( $time + $RENAME_PERIOD ) > $time_rec ) {
      print "rename ignore  : $host:$managedname:$lpar : rename period ignore : ($time + $RENAME_PERIOD) > $time_rec\n" if $DEBUG;
      return 1;
    }
  }

  return 0;
}

sub rrd_error {
  my $err_text = shift;
  my $rrd_file = shift;
  my $basedir  = $ENV{INPUTDIR};
  my $tmpdir   = "$basedir/tmp";
  if ( defined $ENV{TMPDIR_LPAR} ) {
    $tmpdir = $ENV{TMPDIR_LPAR};
  }

  chomp($err_text);

  if ( !-f "$rrd_file" ) {
    return 0;
  }

  if ( $err_text =~ m/ERROR:/ ) {

    # copy of the corrupted file into "save" place and remove the original one
    copy( "$rrd_file", "$tmpdir/" ) || main::error("Cannot: cp $rrd_file $tmpdir/: $!");
    unlink("$rrd_file")             || main::error("Cannot rm $rrd_file : $!");
    main::error("$err_text, moving it into: $tmpdir/");
  }
  else {
    main::error("$err_text");
  }
  return 0;
}

return 1;
