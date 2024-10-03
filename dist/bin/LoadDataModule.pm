package LoadDataModule;    #
use strict;
use Date::Parse;
use RRDp;
use File::Copy;
use Xorux_lib;
use PowerDataWrapper;
use Math::BigInt;
use Data::Dumper;
use JSON;
use POSIX;
use File::Copy qw(copy);

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

my $DEBUG_REST_API;
if   ( defined $ENV{DEBUG_REST_API} ) { $DEBUG_REST_API = $ENV{DEBUG_REST_API}; }
else                                  { $DEBUG_REST_API = 0; }
my $PROXY_SEND;
if   ( defined $ENV{PROXY_SEND} ) { $PROXY_SEND = $ENV{PROXY_SEND}; }
else                              { $PROXY_SEND = 0; }

my $rename_once = 0;
my @rename      = "";



sub load_data {
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $SSH, $hmc_user, $json_configured, $save_files, $model, $serial, $hmc_timezone ) = @_;
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
  my $jump = 0;

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

  my $input_lpar = "$input-$type_sam";
  if ( $ENV{LPAR_LOAD_EXTERNAL} ) {
    if ( -f $ENV{LPAR_LOAD_EXTERNAL} ) {
      $input_lpar = $ENV{LPAR_LOAD_EXTERNAL};    # keep number of virt processors in RRD --> etc/.magic
    }
  }

  my $line      = "";
  my @rrd_exist = "";
  my @rmd_exist = "";
  my @rsd_exist = "";

  my @lpar_name = "";
  my @lpar_idle = "";
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

  my $rrd_cpupool = PowerDataWrapper::get_filepath_rrd_cpupool($managedname, $host, "rrt");
  my $rrd_cpupool_max = PowerDataWrapper::get_filepath_rrd_cpupool($managedname, $host, "rxm");
  if (defined $json_configured && $json_configured == 1 ){
    my $perf_string = "lpars_perf";
    my $iostatdir = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files = sort { lc $a cmp lc $b } @files_unsorted;
    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    my $last_known_ts_prev = 0;
    if (-e "$wrkdir/$managedname/$host/iostat/last_ts.lpars"){
      open ($ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.lpars") || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.lpars at".__LINE__);
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else{
      $saved_ts = "not_defined";
    }
    if (! (-e "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt")){
      if ( open (my $fh_last_ts, ">", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt") ){
        print $fh_last_ts "null";
        close($fh_last_ts);
      }
      else{
       main::error( " Cannot open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
    if ( open (my $fh_last_ts, "<", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt") ){
      $last_known_ts_prev = readline($fh_last_ts);
      if (!(main::isdigit($last_known_ts_prev))){
        $last_known_ts_prev = 0;
      }
      close($fh_last_ts);
    }
    else{
      main::error( " Cannot open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
    }
    my $last_known_timestamp = "";
    my $act_time_upd = time;
    my $lll;
    my $act_sys_cores_api = PowerDataWrapper::get_server_metric($managedname, "ConfigurableSystemProcessorUnits", 0);
    my $CurrentProcessingUnitsTotal = PowerDataWrapper::get_server_metric($managedname, "CurrentProcessingUnitsTotal", 0);
    foreach my $file(@files){
      if ( Xorux_lib::file_time_diff ( $file ) > 3600 ){ next; }
      my $datestring = localtime();
      print "Rest API       " . strftime("%FT%H:%M:%S", localtime(time)) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path = "$iostatdir$file";
      my $content = [];
      $content  = Xorux_lib::read_json($path) if (-e $path);
      if (!defined $content || $content eq "-1" || ref($content) eq "HASH"){
        print "$file is not valid : $content\n";
        unlink($path);
        print "no content in $path\n";
        next;
      }
      my $temp_ts;
      my $changed_curr_proc_units;
      foreach my $arr_ts_sample (@{$content}){
        my $t = str2time( $arr_ts_sample->[0] );
        $last_known_timestamp = $t;
        $temp_ts = $t;
        my $lpar = $arr_ts_sample->[1];

        #if ($lpar =~ m/p770-demo/){ next; }
        if (defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar}){
          next;
        }
        my $powered_on = $arr_ts_sample->[3] + $arr_ts_sample->[4] + $arr_ts_sample->[5]+ $arr_ts_sample->[6];
        if (!$powered_on ){
          next;
        }

        $lll->{$t}{mode} = $arr_ts_sample->[7] if (defined $arr_ts_sample->[7])  ;

        $lll->{$t}{cores} = $CurrentProcessingUnitsTotal;
        $lll->{$t}{configured_proc_units} = $act_sys_cores_api;
#        print "LPAR XXX $managedname : $lpar (tot cpu: $lll->{$t}{cores}) : $lll->{$t}{mode} c:$arr_ts_sample->[3] u:$arr_ts_sample->[4] e:$arr_ts_sample->[5] i:$arr_ts_sample->[6]\n";
        if ($lll->{$t}{cores} == 0){
          #print "skip total pool update : $managedname ($host): $lpar (tot cpu: $lll->{$t}{cores}) : $lll->{$t}{mode} c:$arr_ts_sample->[3] u:$arr_ts_sample->[4] e:$arr_ts_sample->[5] i:$arr_ts_sample->[6]\n";
        }

        if (!defined $lll->{$t}{capped_cycles}) { $lll->{$t}{capped_cycles} = 0; }

        $lll->{$t}{capped_cycles} += $arr_ts_sample->[3] if defined $arr_ts_sample->[3];
        #print "LPAR MODE : $lpar $arr_ts_sample->[7]\n" if ($lpar eq 'p770-demo');
        if ($arr_ts_sample->[7] =~ m/share_idle/ || $arr_ts_sample->[7] =~ m/keep_idle/ ){
          #print "LPAR MODE C:$arr_ts_sample->[3] I:$arr_ts_sample->[6]\n" if ($lpar eq 'p770-demo');
          $lll->{$t}{capped_cycles} -= $arr_ts_sample->[6];
          #print "LPAR MODE C odectene : $lll->{$t}{capped_cycles}\n" if ($lpar eq 'p770-demo');
        }

        if (!defined $lll->{$t}{uncapped_cycles}) { $lll->{$t}{uncapped_cycles} = 0; }
        $lll->{$t}{uncapped_cycles} += $arr_ts_sample->[4] if defined $arr_ts_sample->[4];

        if (!defined $lll->{$t}{entitled_cycles}) { $lll->{$t}{entitled_cycles} = 0; }
        $lll->{$t}{entitled_cycles} += $arr_ts_sample->[5] if defined $arr_ts_sample->[5];

        if (!defined $lll->{$t}{idle_cycles}) { $lll->{$t}{idle_cycles} = 0; }
        $lll->{$t}{idle_cycles} += $arr_ts_sample->[6] if defined $arr_ts_sample->[6];

        $lpar =~ s/\//\&\&1/g;
        $rrd = PowerDataWrapper::get_filepath_rrd_vm($lpar, $managedname, "rrm");
        my $rrd_vcpu = PowerDataWrapper::get_filepath_rrd_vm($lpar, $managedname, "rvm");
        my $rsm = PowerDataWrapper::get_filepath_rrd_vm($lpar, $managedname, "rsm");
        #$rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";
        if (!-e $rrd){
          my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, "", "", $wrkdir, $lpar, $t, $keep_virtual );
          if ( $ret == 2 ) {
            next;
          }
        }
        if (!-e $rsm){
#         my $ret = create_rrd( $rsm, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, "", "", $wrkdir, $lpar, $t, $keep_virtual );
          my $ret = create_lpar_mem_ded( $rsm, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
          if ( $ret == 2 ) {
            next;
          }
        }
        if (!-e $rrd_vcpu){
          my $ret = create_rrd_vcpu( $rrd_vcpu , "AVERAGE");
          if ( $ret == 2 ) {
            print "Cannot create rrd_vcpu $rrd_vcpu\n";
          }
        }
        my $curr_proc_units="U"; my $entitled_cycles="U"; my $capped_cycles="U"; my $uncapped_cycles="U"; my $mode="U"; my $idle_proc_cycles="U"; my $memory = 0; my $min_vcpu = "U"; my $max_vcpu = "U"; my $curr_min_vcpu = "U"; my $curr_max_vcpu = "U"; my $allocated_vcpu = "U"; my $desired_vcpu = "U";
        $capped_cycles = $arr_ts_sample->[3]      if (defined $arr_ts_sample->[3])  ;
        #if ( $arr_ts_sample->[7] =~ m/share_idle/ || $arr_ts_sample->[7] =~ m/keep_idle/ ){
        #  $capped_cycles -= $idle_proc_cycles;
        #}

        $uncapped_cycles = $arr_ts_sample->[4]    if (defined $arr_ts_sample->[4])  ;

        $entitled_cycles = $arr_ts_sample->[5]    if (defined $arr_ts_sample->[5])  ;

        $idle_proc_cycles = $arr_ts_sample->[6]   if (defined $arr_ts_sample->[6])  ;

        $mode = $arr_ts_sample->[7]               if (defined $arr_ts_sample->[7])  ;
        $memory = $arr_ts_sample->[13]            if (defined $arr_ts_sample->[13]) ;

        $curr_proc_units = $arr_ts_sample->[14]   if (defined $arr_ts_sample->[14]) ;

        $curr_proc_units = $arr_ts_sample->[15]   if (defined $arr_ts_sample->[15] || $curr_proc_units eq "U");

        $allocated_vcpu = $arr_ts_sample->[18]    if (defined $arr_ts_sample->[18])  ;
        #$min_vcpu = $arr_ts_sample->[18]    if (defined $arr_ts_sample->[18])  ;
        #$curr_min_vcpu = $arr_ts_sample->[19]    if (defined $arr_ts_sample->[19])  ;
        #$max_vcpu = $arr_ts_sample->[20]    if (defined $arr_ts_sample->[20])  ;
        #$curr_max_vcpu = $arr_ts_sample->[21]    if (defined $arr_ts_sample->[21])  ;
        #$desired_vcpu = $arr_ts_sample->[22]    if (defined $arr_ts_sample->[22])  ;
        if ($mode =~ m/^share_idle_/ || $mode=~ m/^keep_idle_/ ) {
          $capped_cycles = $capped_cycles - $idle_proc_cycles if ($capped_cycles >= $idle_proc_cycles);
        }
        my $last_curr_proc_units = "";
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
          RRDp::cmd qq(lastupdate "$rrd" );
          my $last_update = RRDp::read;
          (undef, my $values) = split (":", $$last_update);
          my @vals = split (" ", $values);
          $last_curr_proc_units = $vals[0];
        };
        if ($@) {
          #RRDp::error_mode = "catch";
          rrd_error( $@, $rrd );
          next;
        }

        my $last_rec_rsm = 0;

        eval {
          RRDp::cmd qq(last "$rsm" );
          $last_rec_rsm = RRDp::read;
        };
        if ($@) {
          #RRDp::error_mode = "catch";
          rrd_error( $@, $rsm );
          next;
        }
        chomp($$last_rec_rsm);
        chomp($$last_rec);
        my $last_update_rrd = $$last_rec;
        my $last_update_rsm = $$last_rec_rsm;

        if ( $t > $last_update_rrd ) {
          $entitled_cycles = Math::BigInt->new($entitled_cycles);
          $capped_cycles = Math::BigInt->new($capped_cycles);
          $uncapped_cycles = Math::BigInt->new($uncapped_cycles);


          if (!(main::isdigit($curr_proc_units))){ $curr_proc_units = "U"; }
          if (!(main::isdigit($entitled_cycles))){ $entitled_cycles = "U"; }
          if (!(main::isdigit($capped_cycles))){ $capped_cycles = "U"; }
          if (!(main::isdigit($uncapped_cycles))){ $uncapped_cycles = "U"; }
          if ( (main::isdigit($curr_proc_units) && $curr_proc_units < 0) ||  (main::isdigit($entitled_cycles) && $entitled_cycles < 0) ||  (main::isdigit($capped_cycles) && $capped_cycles < 0) ||  (main::isdigit($uncapped_cycles) && $uncapped_cycles < 0)){
            my $capped_cycles_or = $capped_cycles + $idle_proc_cycles;
            main::error( "$host:$managedname : Not valid counters in lpars $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles \n Original line: $curr_proc_units:$entitled_cycles:$capped_cycles_or:$uncapped_cycles " . __FILE__ . ":" . __LINE__ );
            next;
          }
          #$curr_proc_units = 0.2 if ($lpar eq "Accept");
          if (defined $curr_proc_units && $curr_proc_units eq "U"){
            next;
          }
          if ($last_curr_proc_units ne "U" && $last_curr_proc_units != $curr_proc_units || (defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} == 1)) {
            if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} && $act_time_upd <= $last_known_ts_prev ) {
              next;
            }
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:U:U:U);
            if (!defined $changed_curr_proc_units->{$lpar}) { $changed_curr_proc_units->{$lpar} = 0; }
            #$changed_curr_proc_units->{$lpar} = $changed_curr_proc_units->{$lpar} + 1;
            $changed_curr_proc_units->{$lpar} = 1;
          }
          else{
            if (defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} || (main::isdigit($act_time_upd) && $act_time_upd <= $last_known_ts_prev ) ){
              next;
            }
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          eval {
            $answer    = RRDp::read;
          };
          if ($@){
            #rrd_error( $@, $rrd );
            next;
          }
          RRDp::cmd qq(update "$rrd_vcpu" $t:$allocated_vcpu);
          eval {
            $answer    = RRDp::read;
          };
          if ($@){
            #rrd_error( $@, $rrd );
            next;
          }
        }
        if ( $t > $last_update_rsm ) {
#          $memory = Math::BigInt->new($memory);
          RRDp::cmd qq(update "$rsm" $t:$memory);
          eval {
            $answer    = RRDp::read;
          };
          if ($@){
            #rrd_error( $@, $rrd );
            next;
          }
        }
      }
      ##unlink ($path) || print("Cannot delete file $path ". __FILE__. ":". __LINE__);
      if (defined $file && defined $files[-1] && defined $files[-2]){
      if ($file eq $files[-1]){
        copy ($path, "$ENV{INPUTDIR}/tmp/$managedname/lpars_perf1");
      }
      if ($file eq $files[-2]){
        copy ($path, "$ENV{INPUTDIR}/tmp/$managedname/lpars_perf2");
      }
      }
      if ($save_files =~ /^-?\d+$/){
        if ($save_files == 0){
          if ($PROXY_SEND != 2){
            unlink($path) || main::error ("Cannot unlink $path in ".__FILE__.":".__LINE__);
          }
        }
      }
      else{
        if ($save_files ne $managedname){
          if ($PROXY_SEND != 2){
            unlink($path) || main::error ("Cannot unlink $path in ".__FILE__.":".__LINE__);
          }
        }
      }
      if ( open ($ltiph, ">", "$wrkdir/$managedname/$host/iostat/last_ts.lpars") ){
        print $ltiph "$temp_ts";
        close($ltiph);
      }
      else{
        main::error( " Can't open $wrkdir/$managedname/$host/iostat/last_ts.lpars : $!" . __FILE__ . ":" . __LINE__ )
      }
    }
    if ( open (my $fh, ">", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt") ){
      print $fh "$last_known_timestamp\n";
      close($fh);
    }
    else{
        main::error( " Can't open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ )
    }
    #my $rrd_cpupool = PowerDataWrapper::get_filepath_rrd("CPUPOOL", "rrm");
    if (!-e $rrd_cpupool){
      print "Creating rrd pool_total api \nRRD CPUPOOL : $rrd_cpupool\n";
      touch("create_rrd_pool_total $rrd_cpupool");
      my $ret = create_rrd_pool_total( $rrd_cpupool , "AVERAGE");
      if ( $ret == 2 ) {
        print "cannot create rrd pool_total api $rrd_cpupool\n";
        next;
      }
    }
    if (!-e $rrd_cpupool_max){
      print "Creating rrd pool_total max api\nRRD CPUPOOL : $rrd_cpupool_max\n";
      touch("create_rrd_pool_total $rrd_cpupool_max");
      my $ret = create_rrd_pool_total( $rrd_cpupool_max, "MAX");
      if ( $ret == 2 ) {
        print "cannot create rrd pool_total max api $rrd_cpupool_max\n";
        next;
      }
    }
    RRDp::end;
    RRDp::start "$rrdtool";

    RRDp::cmd qq(last "$rrd_cpupool" );
    $last_rec = RRDp::read;
    chomp($$last_rec);
    my $last_update = $$last_rec;
    foreach my $t (sort keys %{$lll}){
      my $entitled_cycles = 0;
      my $uncapped_cycles = 0;
      my $capped_cycles   = 0;
      my $idle_cycles     = 0;
      $entitled_cycles    = $lll->{$t}{entitled_cycles} if (defined $lll->{$t}{entitled_cycles});
      $uncapped_cycles    = $lll->{$t}{uncapped_cycles} if (defined $lll->{$t}{uncapped_cycles});
      $capped_cycles      = $lll->{$t}{capped_cycles}   if (defined $lll->{$t}{capped_cycles});
      $idle_cycles        = $lll->{$t}{idle_cycles}     if (defined $lll->{$t}{idle_cycles});

      if ($t <= $last_update) { next; }
      #print STDERR strftime("%FT%H:%M:%S", localtime(time)) . "        : DEBUG GAPS pool_total update : $rrd_cpupool | $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles\n";
      #print "Rest API       " . strftime("%FT%H:%M:%S", localtime(time)) . "        : pool_total update : $rrd_cpupool $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{capped_cycles}\n";
      $entitled_cycles    = Math::BigInt->new($entitled_cycles) if (defined $entitled_cycles);
      $uncapped_cycles    = Math::BigInt->new($uncapped_cycles)if (defined $uncapped_cycles);
      $capped_cycles      = Math::BigInt->new($capped_cycles) if (defined $capped_cycles);
      $idle_cycles        = Math::BigInt->new($idle_cycles) if (defined $idle_cycles);
      RRDp::cmd qq(update "$rrd_cpupool" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      eval {
        $answer    = RRDp::read;
      }; if ($@){
        rrd_error( $@, $rrd );
        next;
      }
      RRDp::cmd qq(update "$rrd_cpupool_max" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      eval {
        $answer    = RRDp::read;
      }; if ($@){
        rrd_error( $@, $rrd );
        next;
      }
    }
  }
  else { #old, ssh cli
   my $act_sys_cores_ssh = PowerDataWrapper::get_metric_from_config_cfg("$wrkdir/$managedname/$host/config.cfg", "configurable_sys_proc_units");
   print "INPUT LPAR     : $input_lpar\n";
   open( FH, "< $input_lpar" ) || main::error( " Can't open $input_lpar : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
   my @lines = reverse <FH>;
   close(FH);
   my $lll;
   foreach $line (@lines) {
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
    } ## end if ( $line =~ "HSCL" ||...)

    if ( $line =~ "An invalid parameter value was entered" ) {

      # something wrong with the input data
      main::error("$host:$managedname : wrong input data in $host:$managedname:data:$input-$type_sam : $line");
      next;
    } ## end if ( $line =~ "An invalid parameter value was entered")

    if ( $HMC == 1 ) {
      ( $time, $lpar, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation, $idle_cycles ) = split( /,/, $line );
    }
    if ( $IVM == 1 ) {
      ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
    }
    if ( $SDMC == 1 ) {
      ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
    }

    # print "001 $lpar : $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles $capped_cycles, $uncapped_cycles, $idle_cycles\n";
    # $curr_proc_units can be null for dedicated partitions so do not test it here!!!!
    if ( $curr_procs eq '' || $curr_sharing_mode eq '' || $entitled_cycles eq '' || $capped_cycles eq '' || $uncapped_cycles eq '' ) {

      # something wrong with input data, skipping it
      # it migh happen, here is en example : 05/03/2012 22:34:50,1,,,,,,
      next;
    } ## end if ( $curr_procs eq ''...)

    #print "$time $lpar \n";
    # Check whether the first character is a digit, if not then there is something wrong with the
    # input data
    my $ret = substr( $time, 0, 1 );

    #if (($ret =~ /\D/) || ( $lpar eq '' ))  left_curly
    # do not put there $lpar as it might be NULL when the systems is down, seen it for memory
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
      close(FH);
      return 1;
    } ## end if ( $ret =~ /\D/ )

    if ( $HMC == 0 ) {    # IVM translation ids to names
                          # this will have a problem whether a "," is inside lpar name
      foreach my $li (@lpar_trans) {
        chomp($li);
        ( my $id, my $name ) = split( /,/, $li );

        #print "---02 $li -- $id - $lpar_id\n";
        if ( $id == $lpar_id ) {
          $lpar = $name;
          last;
        }
      } ## end foreach my $li (@lpar_trans)
    } ## end if ( $HMC == 0 )

    if ( $lpar =~ m/IOR Collection LP/ ) {    #it is some trash, it exists time to tme, some IBM internal ...
      next;                                   #ignore it
    }
    if ( $lpar eq '' ) {
      next;                                   #again something wrong
    }

    # replace / by &&1, install-html.sh does the reverse thing
    $lpar =~ s/\//\&\&1/g;

    $t = str2time( substr( $time, 0, 19 ) );


    #here???

    $t = correct_to_local_timezone ($t, $hmc_timezone);

#sub correct_to_local_timezone{
#    my $t = shift;
#    my $hmc_timezone = shift;
#    my $tz_n = substr($hmc_timezone,1,4);
#    $tz_n /= 100;
#    if (substr($hmc_timezone,0,1) eq "+"){
#      $t = $t + ($tz_n * 3600);
#    } else { # -
#      $t = $t - ($tz_n * 3600);
#    }
#    return $t;
#}


    if ( length($t) < 10 ) {

      # leave it as wrong input data
      main::error( "$host:$managedname :No valid lpar data time format got from HMC : $t : $line : " . __FILE__ . ":" . __LINE__ );
      next;                                   # next only, could  happen that there appears unix 0 time on the HMC after the upgrade, then just ignore it
    } ## end if ( length($t) < 10 )

    if ( $step == 3600 ) {

      # Put on the last time possition "00"!!!
      substr( $t, 8, 2, "00" );

      #print "$t $lpar\n";
      #print "Input data: $lpar\n";
    } ## end if ( $step == 3600 )
    if ( $lpar =~ m/\"/ ) {

      # LPAR cannot contain double quote, it is an illegal character in the lpar name, report it once and ignore it
      if ( $error_once == 0 ) {
        main::error( "$host:$managedname :LPAR cannot contain double quote, it is an illegal character in the lpar name: $lpar : $line : " . __FILE__ . ":" . __LINE__ );
      }
      $error_once++;
      next;
    } ## end if ( $lpar =~ m/\"/ )

    $rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";
    #print "RRDNAME = $lpar.rr$type_sam\n";

    #create rrd db if necessary
    # find out if rrd db exist, and place info to the array to do not check its existency every time
    my $rrd_exist_ok  = 0;
    my $rrd_exist_row = 0;
    foreach my $row (@rrd_exist) {
      $rrd_exist_row++;
      if ( $row =~ m/^$lpar$/ ) {
        $rrd_exist_ok = 1;
        last;
      }
    } ## end foreach my $row (@rrd_exist)
    if ( $rrd_exist_ok == 0 ) {
      my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, $SSH, $hmc_user, $wrkdir, $lpar, $t, $keep_virtual );

      my $rrd_vcpu = $rrd; $rrd_vcpu =~ s/rrm/rvm/g;

      if (!-e $rrd_vcpu){
        my $ret = create_rrd_vcpu( $rrd_vcpu , "AVERAGE");
        if ( $ret == 2 ) {
          print "Cannot create rrd_vcpu $rrd_vcpu\n";
        }
      }

      if ( $ret == 1 ) {
        # this lpar has been recently renamed, ignore it then
        next;
      }
      if ( $ret == 2 ) {
        return 1;    # RRD creation problem, skip whole load
      }
      $rrd_exist[$rrd_exist_row] = $lpar;
    } ## end if ( $rrd_exist_ok == ...)

    # found out last record and save it
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
    } ## end foreach my $l (@lpar_name)
    if ( $found > -1 ) {
      $ltime   = $lpar_time[$found];
      $l_count = $found;
    }
    else {
      # find out last record in the db
      # as this makes it slowly to test it each time then it is done
      # once per a lpar for whole load and saved into the array

      # construction against crashing daemon Perl code when RRDTool error appears
      # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
      # construction is not too costly as it runs once per each load
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
      } ## end if ($@)
      chomp($$last_rec);
      $lpar_name[$l_count] = $lpar;
      $lpar_time[$l_count] = $$last_rec;
      $lpar_jump[$l_count] = 0;
      $lpar_idle[$l_count] = 0;
      $ltime               = $$last_rec;
    } ## end else [ if ( $found > -1 ) ]

    # when dedicated partitions then there is not set up $curr_proc_units as it is useless
    # I put curr_procs into curr_proc_units to make some gratphs for dedicated lpars
    if ( $curr_sharing_mode =~ m/^share_idle_/ || $curr_sharing_mode =~ m/^keep_idle_/ || length($curr_proc_units) == 0 ) {
      $curr_proc_units = $curr_procs;
      if ( defined($idle_cycles) && !$idle_cycles eq '' && $idle_cycles > 0 ) {

        # CPU lpars have reported idle cycles on new HMC firmwares --> use it for utilization
        $capped_cycles -= $idle_cycles;
        if ( $capped_cycles < 0 ) {

          # capped_cycles can be negative --> CPU dedicated LPARs after LPM might have more idle than capped -->
          # it is a big problem, only the solution is store initial big $idle counter and always use it for decrement of $idle
          # ideal solution would be storing $idle into rrd, but problem with compatability ... :(
          if ( $lpar_idle[$l_count] == 0 ) {
            $lpar_idle[$l_count] = get_lpar_idle_count( $wrkdir, $host, $managedname, $lpar_name[$l_count], $idle_cycles, "get" );
          }
          $capped_cycles = $capped_cycles + $lpar_idle[$l_count];
          if ( $capped_cycles < 0 ) {

            # might appear that it is still negative after several LPM, original saved $idle must be refreshed
            $capped_cycles = $capped_cycles - $lpar_idle[$l_count];    # return saved one
            $lpar_idle[$l_count] = get_lpar_idle_count( $wrkdir, $host, $managedname, $lpar_name[$l_count], $idle_cycles, "force" );
            $capped_cycles = $capped_cycles + $lpar_idle[$l_count];
          } ## end if ( $capped_cycles < ...)
          if ( $capped_cycles < 0 ) {

            # if still < 0 then something works bad, note error and skip it
            if ( $error_count == 0 ) {
              main::error( "counter < 0! :  $rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles - $idle_cycles,$lpar_idle[$l_count], skipping LPAR $lpar_name[$l_count] " . __FILE__ . ":" . __LINE__ );
              $error_count++;
            }
            next;
          } ## end if ( $capped_cycles < ...)
        } ## end if ( $capped_cycles < ...)
      } ## end if ( defined($idle_cycles...))

      # no, no here, shared_syscles* modes containg right $capped_cycles data
      #if ( defined ($shared_cycles_while_active) && ! $shared_cycles_while_active eq '' &&  main::isdigit($shared_cycles_while_active) ) {
      #  $capped_cycles -= $shared_cycles_while_active; # only for LPARs in share_idle_procs_always mode
      #}
      $capped_cycles = $capped_cycles + 0;    #conversion to format understable for rrdtool
    } ## end if ( $curr_sharing_mode...)

    # when CPU dedicated LPARs and modes "share_idle*" then there is already capped shown correctly in data!
    #   --> then do not lower entitlement as this produce wrong numbers then
    # if $curr_proc_units == 0 then lpar is not running and it causing a problem with donated cycles
    #if ($curr_proc_units > 0) {
    #  # exclude POWER5 systems where $shared_cycles_while_active does not exist
    #  # it is for donation of dedicated CPU lpars
    #  if ($curr_sharing_mode =~ "share_idle_procs" || $curr_sharing_mode =~ "share_idle_procs_active" || \
    #      $curr_sharing_mode =~ "share_idle_procs_always" ) {
    #    if ( ! $shared_cycles_while_active eq '' ) {
    #      if ( $entitled_cycles < $shared_cycles_while_active ) {
    #         main::error ("$rrd $t:$entitled_cycles - $shared_cycles_while_active < 0 !!! ".__FILE__.":".__LINE__);
    #         next;
    #      }
    #      # necesary due to Perl behaviour whe it convert it to format X.YZ+eXY
    #      $entitled_cycles= $entitled_cycles - $shared_cycles_while_active;
    #      $entitled_cycles = Math::BigInt->new($entitled_cycles);
    #    }
    #  }
    #}

    if ( $t > $ltime && length($curr_proc_units) > 0 ) {

      #print "$lpar: $time $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles \n";
      if ( data_check( $entitled_cycles, $capped_cycles, $uncapped_cycles, $lpar, $host, $managedname ) == 0 ) {

        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $lpar_jump[$l_count] == 0 ) {
            $lpar_jump[$l_count] = 1;

            #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
            #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            next;
          } ## end if ( $lpar_jump[$l_count...])

          # looks like it is ok as it is second timestap in a row
        } ## end if ( $t > $jump_time )
        $lpar_jump[$l_count] = 0;

        # It does not go there even when partition is switched off and counters are 0
        if ( $entitled_cycles < 0 || $uncapped_cycles < 0 || $capped_cycles < 0 ) {
          if ( $error_count == 0 ) {
            main::error( "counter < 0! :  $rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles " . __FILE__ . ":" . __LINE__ );
            $error_count++;
          }
          next;
        } ## end if ( $entitled_cycles ...)

        # conversion from scientific X.YeYY format to usual decimal format
        #$curr_proc_units = $curr_proc_units + 0;
        #$curr_procs = $curr_procs + 0;
        #$entitled_cycles = $entitled_cycles + 0;
        #$capped_cycles = $capped_cycles + 0;
        #$uncapped_cycles = $uncapped_cycles + 0;
        # It does not work good (always!), use below one instead
        #$curr_proc_units = Math::BigInt->new($curr_proc_units); --> never use it for this, it is integer --> it cut everything behind decimal
        #$curr_procs      = Math::BigInt->new($curr_procs); --> never use it for this, it is integer --> it cut everything behind decimal

        if (!(main::isdigit($curr_proc_units))){ $curr_proc_units = "U"; }
        if (!(main::isdigit($curr_procs))){ $curr_procs = "U"; }
        if (!(main::isdigit($entitled_cycles))){ $entitled_cycles = "U"; }
        if (!(main::isdigit($capped_cycles))){ $capped_cycles = "U"; }
        if (!(main::isdigit($uncapped_cycles))){ $uncapped_cycles = "U"; }
        print "$lpar PROCS: $curr_procs PROC_UNITS : $curr_proc_units\n" if $DEBUG_REST_API;
        print "$lpar counters : $capped_cycles $uncapped_cycles $entitled_cycles $idle_cycles\n" if $DEBUG_REST_API;
        my $powered_on = $uncapped_cycles + $capped_cycles + $entitled_cycles + $idle_cycles;
        #here
        #$lll->{$t}{cores} += $curr_proc_units;
        if (! $powered_on ){
          print "skip powered off $lpar\n" if $DEBUG_REST_API;
          next;
        }
        $lll->{$t}{configured_proc_units} = $act_sys_cores_ssh;
        $lll->{$t}{cores} += $curr_proc_units;
        $lll->{$t}{entitled_cycles} += $entitled_cycles;
        $lll->{$t}{capped_cycles} += $capped_cycles;
        $lll->{$t}{idle_cycles} += $idle_cycles;
        $lll->{$t}{uncapped_cycles} += $uncapped_cycles;

        $entitled_cycles = Math::BigInt->new($entitled_cycles) if (defined $entitled_cycles);
        $uncapped_cycles = Math::BigInt->new($uncapped_cycles);
        $capped_cycles   = Math::BigInt->new($capped_cycles);

        if ( $keep_virtual == 1 ) {

          # new one, DHL needs to keep virtual processors for accounting
          my $datestring = localtime();
          print "Debug-004a-$rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles\n" if $DEBUG_REST_API;
          RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles);
        }
        else {
          # old way without storing number of virtual processors
          my $datestring = localtime();
          print "Debug-004b-$rrd $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles (- no curr_procs)\n" if $DEBUG_REST_API;
          RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles);
        }
        $answer    = RRDp::read;
        $last_time = $time;
        $counter_ins++;
        if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
          main::error(" $host:$managedname : $rrd : $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles : $line : $$answer");
          if ( $$answer =~ m/is not an RRD file/ ) {
            ( my $err, my $file, my $txt ) = split( /'/, $$answer );
            main::error("Removing as it seems to be corrupted: $file");
            unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          }
        } ## end if ( !$$answer eq '' &&...)
        my $rrd_vcpu = $rrd; $rrd_vcpu =~ s/rrm/rvm/g;

        if (!-e $rrd_vcpu){
          my $ret = create_rrd_vcpu( $rrd_vcpu , "AVERAGE");
            if ( $ret == 2 ) {
            print "Cannot create rrd_vcpu $rrd_vcpu\n";
          }
        }
        RRDp::cmd qq(update "$rrd_vcpu" $t:$curr_procs);
        $answer    = RRDp::read;

        if (defined $$answer && $$answer ne '' && $$answer =~ m/ERROR/ ) {
          main::error(" $host:$managedname : $rrd_vcpu : $t:$curr_procs");
          if ( $$answer =~ m/is not an RRD file/ ) {
            ( my $err, my $file, my $txt ) = split( /'/, $$answer );
            main::error("Removing as it seems to be corrupted: $file");
            unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
          }
        }

        # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
        $lpar_time[$l_count] = $t;
      } ## end if ( data_check( $entitled_cycles...))

      # memory should go through although switched off partition
      # sometimes (? when partition is halted??) it might have still allocated memory although it is off!!!

      #
      #  memory stuff
      #

      if ( !$mem_mode eq '' ) {
        if ( $mem_mode =~ m/shared/ ) {

          # AMS memory stuff only if it is activated
          if ( $curr_mem eq '' || $phys_run_mem eq '' || $curr_io_entitled_mem eq '' || $mapped_io_entitled_mem eq '' || $mem_overage_cooperation eq '' ) {

            #main::error ("$host:$managedname : wrong mem input, shared defined but some value is null : $line");
            #main::error ("$host:$managedname: future timestamp: $rrd");
            #print "$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation\n";
          } ## end if ( $curr_mem eq '' ||...)
          else {
            #create rrd db if necessary
            # find out if rrd db exist, and place info to the array to do not check its existency every time
            my $rmd_exist_ok  = 0;
            my $rmd_exist_row = 0;
            foreach my $row1 (@rmd_exist) {
              $rmd_exist_row++;
              if ( $row1 =~ m/^$lpar$/ ) {
                $rmd_exist_ok = 1;
                last;
              }
            } ## end foreach my $row1 (@rmd_exist)
            my $rmd = "$wrkdir/$managedname/$host/$lpar.rm$type_sam";
            if ( $rmd_exist_ok == 0 ) {
              $rmd_exist[$rmd_exist_row] = $lpar;
              my $ret = create_lpar_mem( $rmd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
              if ( $ret == 2 ) {
                return 1;    # RRD creation problem, skip whole load
              }
            } ## end if ( $rmd_exist_ok == ...)

            # found out last record and save it
            # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
            $l_count_rmd = 0;
            my $found_rmd = -1;
            my $lpar_meta = quotemeta($lpar);
            foreach my $l (@lpar_name_rmd) {
              if ( $l =~ m/^$lpar_meta$/ ) {
                $found_rmd = $l_count_rmd;
                last;
              }
              $l_count_rmd++;
            } ## end foreach my $l (@lpar_name_rmd)

            #print "RMD 01: $lpar $found_rmd - $t\n";
            if ( $found_rmd > -1 ) {
              $ltime_rmd   = $lpar_time_rmd[$found_rmd];
              $l_count_rmd = $found_rmd;
            }
            else {
              # find out last record in the db
              # as this makes it slowly to test it each time then it is done
              # once per a lpar for whole load and saved into the array

              # construction against crashing daemon Perl code when RRDTool error appears
              # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
              # construction is not too costly as it runs once per each load
              eval {
                RRDp::cmd qq(last "$rmd" );
                $last_rec = RRDp::read;
              };
              if ($@) {
               rrd_error( $@, $rmd );
                if ( $rmd_exist[$rmd_exist_row] =~ m/^$lpar$/ ) {
                  $rmd_exist[$rmd_exist_row] = "";
                }
                next;
              } ## end if ($@)
              chomp($$last_rec);
              $lpar_name_rmd[$l_count_rmd] = $lpar;
              $lpar_time_rmd[$l_count_rmd] = $$last_rec;
              $ltime_rmd                   = $$last_rec;

              #print "RMD 01: $lpar $ltime_rmd - $t\n";
            } ## end else [ if ( $found_rmd > -1 )]

            #print "RMD 02: $lpar $ltime_rmd - $t\n";

            if ( $t > $ltime_rmd ) {
              my $datestring = localtime();
              print "Debug-005-$datestring-$rmd $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation\n" if $DEBUG_REST_API;
              if (!(main::isdigit($curr_mem))){ $curr_mem = "U"; }
              if (!(main::isdigit($phys_run_mem))){ $phys_run_mem = "U"; }
              if (!(main::isdigit($curr_io_entitled_mem))){ $curr_io_entitled_mem = "U"; }
              if (!(main::isdigit($mapped_io_entitled_mem))){ $mapped_io_entitled_mem = "U"; }
              if (!(main::isdigit($mem_overage_cooperation))){ $mem_overage_cooperation = "U"; }
              RRDp::cmd qq(update "$rmd" $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation);
              $last_time = $time;
              if ( $counter_ins == 0 ) {
                $counter_ins++;    # just to force update last.txt
              }
              $answer = RRDp::read;
              if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
                main::error(" $host:$managedname : $rmd : $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation : $line : $$answer");
                if ( $$answer =~ m/is not an RRD file/ ) {
                  ( my $err, my $file, my $txt ) = split( /'/, $$answer );
                  main::error("Removing as it seems to be corrupted: $file");
                  unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                }
              } ## end if ( !$$answer eq '' &&...)

              # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
              $lpar_time_rmd[$l_count_rmd] = $t;
            } ## end if ( $t > $ltime_rmd )
          } ## end else [ if ( $curr_mem eq '' ||...)]
        } ## end if ( $mem_mode =~ m/shared/)
        else {
          # dedicated mode, just 1 item inside
          if ( $curr_mem eq '' ) {
            #main::error("$host:$managedname : wrong mem input, dedicated mem defined but curr_mem is null : $line");

            #print "$curr_mem\n";
          }
          else {
            #create rrd db if necessary
            # find out if rrd db exist, and place info to the array to do not check its existency every time
            my $rsd_exist_ok  = 0;
            my $rsd_exist_row = 0;
            foreach my $row1 (@rsd_exist) {
              $rsd_exist_row++;
              if ( $row1 =~ m/^$lpar$/ ) {
                $rsd_exist_ok = 1;
                last;
              }
            } ## end foreach my $row1 (@rsd_exist)
            $lpar =~ s/\//\&\&1/g ;
            my $rsd = "$wrkdir/$managedname/$host/$lpar.rs$type_sam";
            if ( $rsd_exist_ok == 0 ) {
              $rsd_exist[$rsd_exist_row] = $lpar;
              my $ret = create_lpar_mem_ded( $rsd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
              if ( $ret == 2 ) {
                return 1;    # RRD creation problem, skip whole load
              }
            } ## end if ( $rsd_exist_ok == ...)

            # found out last record and save it
            # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
            $l_count_rsd = 0;
            my $found_rsd = -1;
            my $lpar_meta = quotemeta($lpar);
            foreach my $l (@lpar_name_rsd) {
              if ( $l =~ m/^$lpar_meta$/ ) {
                $found_rsd = $l_count_rsd;

                #print "RSD 01: $lpar - $found_rsd - $lpar_meta\n";
                last;
              } ## end if ( $l =~ m/^$lpar_meta$/)
              $l_count_rsd++;
            } ## end foreach my $l (@lpar_name_rsd)

            #print "RSD 01: $lpar $found_rsd - $t\n";
            if ( $found_rsd > -1 ) {
              $ltime_rsd   = $lpar_time_rsd[$found_rsd];
              $l_count_rsd = $found_rsd;

              #print "RSD 02: $lpar $ltime_rsd - $found_rsd\n";
            } ## end if ( $found_rsd > -1 )
            else {
              # find out last record in the db
              # as this makes it slowly to test it each time then it is done
              # once per a lpar for whole load and saved into the array

              # construction against crashing daemon Perl code when RRDTool error appears
              # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
              # construction is not too costly as it runs once per each load
              eval {
                RRDp::cmd qq(last "$rsd" );
                $last_rec = RRDp::read;
              };
              if ($@) {
               rrd_error( $@, $rsd );
                if ( $rsd_exist[$rsd_exist_row] =~ m/^$lpar$/ ) {
                  $rsd_exist[$rsd_exist_row] = "";
                }
                next;
              } ## end if ($@)
              chomp($$last_rec);
              $lpar_name_rsd[$l_count_rsd] = $lpar;
              $lpar_time_rsd[$l_count_rsd] = $$last_rec;
              $ltime_rsd                   = $$last_rec;

              #print "RSD 03: $lpar $ltime_rsd - $$last_rec\n";
            } ## end else [ if ( $found_rsd > -1 )]

            #print "RSD 04: $lpar $ltime_rsd - $t\n";

            if ( $t > $ltime_rsd ) {
              my $datestring = localtime();
              print "Debug-006-$datestring-$rsd $t:$curr_mem\n" if $DEBUG_REST_API;
              if (!(main::isdigit($curr_mem))){ $curr_mem = "U"; }
              RRDp::cmd qq(update "$rsd" $t:$curr_mem);
              if ( $counter_ins == 0 ) {
                $counter_ins++;    # just to force update last.txt
              }
              $last_time = $time;
              $answer    = RRDp::read;
              if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
                main::error(" $host:$managedname : $rsd : $t:$curr_mem : $line : $$answer");
                if ( $$answer =~ m/is not an RRD file/ ) {
                  ( my $err, my $file, my $txt ) = split( /'/, $$answer );
                  main::error("Removing as it seems to be corrupted: $file");
                  unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                }
              } ## end if ( !$$answer eq '' &&...)

              # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
              $lpar_time_rsd[$l_count_rsd] = $t;
            } ## end if ( $t > $ltime_rsd )
          } ## end else [ if ( $curr_mem eq '' )]
        } ## end else [ if ( $mem_mode =~ m/shared/)]

      }    #memory

    } ## end if ( $t > $ltime && length...)
  } ## end foreach $line (@lines)
  #RRDp::start "$rrdtool";
  if (!-e $rrd_cpupool){
     print "Creating rrd pool_total ssh \nRRD CPUPOOL : $rrd_cpupool\n";
     touch("create_rrd_pool_total $rrd_cpupool");
     my $ret = create_rrd_pool_total( $rrd_cpupool , "AVERAGE");
     if ( $ret == 2 ) {
      print "cannot create rrd pool_total ssh $rrd_cpupool\n";
      return;
    }
  }
  if (!-e $rrd_cpupool_max){
    print "Creating rrd pool_total max ssh\nRRD CPUPOOL : $rrd_cpupool_max\n";
    touch("create_rrd_pool_total $rrd_cpupool_max");
    my $ret = create_rrd_pool_total( $rrd_cpupool_max, "MAX");
    if ( $ret == 2 ) {
      print "cannot create rrd pool_total max ssh $rrd_cpupool_max\n";
      return;
    }
  }
  RRDp::cmd qq(last "$rrd_cpupool" );
  my $last_rec = RRDp::read;
  chomp($$last_rec);
  my $last_update = $$last_rec;
  my $capped_last = 0;
  foreach my $t (sort keys %{$lll}){
    if ($t <= $last_update) { next; }
    $lll->{$t}{capped_cycles} = Math::BigInt->new($lll->{$t}{capped_cycles});
    $lll->{$t}{entitled_cycles} = Math::BigInt->new($lll->{$t}{entitled_cycles});
    $lll->{$t}{uncapped_cycles} = Math::BigInt->new($lll->{$t}{uncapped_cycles});
    $lll->{$t}{idle_cycles} = Math::BigInt->new($lll->{$t}{idle_cycles});
    #check the counter value and skip if the newer counter is wrong (lower than the previous one)
    if ($capped_last > $lll->{$t}{capped_cycles}){
      #skip, the counter cannot be lower than the previous correct one
      main::error ( "error when updating $rrd_cpupool (and max) - got wrong data from HMC - capped (current):$lll->{$t}{capped_cycles} vs. capped (previous):$capped_last - skip timestamp $t");
      next;
    }
    #counter is ok, continue with update of the rrds
    $capped_last = $lll->{$t}{capped_cycles};
    #print STDERR strftime("%FT%H:%M:%S", localtime(time)) . "        : DEBUG GAPS pool_total ssh update : $rrd_cpupool | $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles}\n";
    RRDp::cmd qq(update "$rrd_cpupool" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles});
    eval {
      $answer    = RRDp::read;
    };
    if ($@){
      rrd_error( $@, $rrd );
      next;
    }
    RRDp::cmd qq(update "$rrd_cpupool_max" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles});
    eval {
      $answer    = RRDp::read;
    };
    if ($@){
      rrd_error( $@, $rrd );
      next;
    }
  }
  } #end else (if json !configured
  if ( $error_count > 1 ) {
    main::error( "error count  : $host:$managedname:lpar $error_count " . __FILE__ . ":" . __LINE__ );
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:lpar $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  } ## end if ( $type_sam !~ "d" ...)

  return 0;
} ## end sub load_data

sub load_data_h {
  my $LPA;
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $SSH, $hmc_user, $json_configured, $save_files, $model, $serial, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $model) { $model = ""; }
  if (!defined $serial) { $serial = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
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
  my $jump         = 0;

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

  my $input_lpar = "$input-$type_sam";
  if ( $ENV{LPAR_LOAD_EXTERNAL} ) {
    if ( -f $ENV{LPAR_LOAD_EXTERNAL} ) {
      $input_lpar = $ENV{LPAR_LOAD_EXTERNAL};    # keep number of virt processors in RRD --> etc/.magic
    }
  }

  my $line      = "";
  my @rrd_exist = "";
  my @rmd_exist = "";
  my @rsd_exist = "";

  my @lpar_name = "";
  my @lpar_idle = "";
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

  my $rrd_cpupool     = PowerDataWrapper::get_filepath_rrd_cpupool( $managedname, $host, "rrt" );
  my $rrd_cpupool_max = PowerDataWrapper::get_filepath_rrd_cpupool( $managedname, $host, "rxm" );
  if ( defined $json_configured && $json_configured == 1 ) {
    my $perf_string = "lpars_perf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    my $last_known_ts_prev = 0;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.lpars" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.lpars" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.lpars at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    if ( !( -e "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
      if ( open( my $fh_last_ts, ">", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
        print $fh_last_ts "null";
        close($fh_last_ts);
      }
      else {
        main::error( " Cannot open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
    if ( open( my $fh_last_ts, "<", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
      $last_known_ts_prev = readline($fh_last_ts);
      if ( !( main::isdigit($last_known_ts_prev) ) ) {
        $last_known_ts_prev = 0;
      }
      close($fh_last_ts);
    }
    else {
      main::error( " Cannot open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
    }
    my $last_known_timestamp = "";
    my $act_time_upd         = time;
    my $lll;
    my $act_sys_cores_api           = PowerDataWrapper::get_server_metric( $managedname, "ConfigurableSystemProcessorUnits", 0 );
    my $CurrentProcessingUnitsTotal = PowerDataWrapper::get_server_metric( $managedname, "CurrentProcessingUnitsTotal",      0 );
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path    = "$iostatdir$file";
      my $content = [];
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) eq "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        print "no content in $path\n";
        next;
      }
      my $temp_ts;
      my $changed_curr_proc_units;
      foreach my $arr_ts_sample ( @{$content} ) {
        my $t = str2time( $arr_ts_sample->[0] );
        $last_known_timestamp = $t;
        $temp_ts              = $t;
        my $lpar = $arr_ts_sample->[1];

        #if ($lpar =~ m/p770-demo/){ next; }
        if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} ) {
          next;
        }
        my $powered_on = $arr_ts_sample->[3] + $arr_ts_sample->[4] + $arr_ts_sample->[5] + $arr_ts_sample->[6];
        if ( !$powered_on ) {
          next;
        }

        $lll->{$t}{mode}                  = $arr_ts_sample->[7]          ? $arr_ts_sample->[7]          : "U";
        $lll->{$t}{cores}                 = $CurrentProcessingUnitsTotal ? $CurrentProcessingUnitsTotal : "U";
        $lll->{$t}{configured_proc_units} = $act_sys_cores_api           ? $act_sys_cores_api           : "U";
        $lll->{$t}{capped_cycles}         = $lll->{$t}{capped_cycles}    ? $lll->{$t}{capped_cycles}    : 0;

        #        print "LPAR XXX $managedname : $lpar (tot cpu: $lll->{$t}{cores}) : $lll->{$t}{mode} c:$arr_ts_sample->[3] u:$arr_ts_sample->[4] e:$arr_ts_sample->[5] i:$arr_ts_sample->[6]\n";
        $lll->{$t}{capped_cycles} += $arr_ts_sample->[3] if defined $arr_ts_sample->[3];
        if ( $arr_ts_sample->[7] =~ m/share_idle/ || $arr_ts_sample->[7] =~ m/keep_idle/ ) {
          $lll->{$t}{capped_cycles} -= $arr_ts_sample->[6];
        }

        if ( !defined $lll->{$t}{uncapped_cycles} ) { $lll->{$t}{uncapped_cycles} = 0; }
        $lll->{$t}{uncapped_cycles} += $arr_ts_sample->[4] if defined $arr_ts_sample->[4];

        if ( !defined $lll->{$t}{entitled_cycles} ) { $lll->{$t}{entitled_cycles} = 0; }
        $lll->{$t}{entitled_cycles} += $arr_ts_sample->[5] if defined $arr_ts_sample->[5];

        if ( !defined $lll->{$t}{idle_cycles} ) { $lll->{$t}{idle_cycles} = 0; }
        $lll->{$t}{idle_cycles} += $arr_ts_sample->[6] if defined $arr_ts_sample->[6];

        $lpar =~ s/\//\&\&1/g;
        $rrd = PowerDataWrapper::get_filepath_rrd_vm( $lpar, $managedname, "rrm" );
        my $rrd_vcpu = PowerDataWrapper::get_filepath_rrd_vm( $lpar, $managedname, "rvm" );
        my $rsm      = PowerDataWrapper::get_filepath_rrd_vm( $lpar, $managedname, "rsm" );

        #$rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";
        if (!defined $LPA->{$rrd}{last_update}){
          if ( !-e $rrd ) {
            my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, "", "", $wrkdir, $lpar, $t, $keep_virtual );
            if ( $ret == 2 ) {
              next;
            }
          }
        }
        if (!defined $LPA->{$rsm}{last_update}){
          if ( !-e $rsm ) {

            #         my $ret = create_rrd( $rsm, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, "", "", $wrkdir, $lpar, $t, $keep_virtual );
            my $ret = create_lpar_mem_ded( $rsm, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
            if ( $ret == 2 ) {
              next;
            }
          }
        }
        if (!defined $LPA->{$rrd_vcpu}{last_update}){
          if ( !-e $rrd_vcpu ) {
            my $ret = create_rrd_vcpu( $rrd_vcpu, "AVERAGE" );
            if ( $ret == 2 ) {
              print "Cannot create rrd_vcpu $rrd_vcpu\n";
            }
          }
        }
        my $curr_proc_units  = "U";
        my $entitled_cycles  = "U";
        my $capped_cycles    = "U";
        my $uncapped_cycles  = "U";
        my $mode             = "U";
        my $idle_proc_cycles = "U";
        my $memory           = 0;
        my $min_vcpu         = "U";
        my $max_vcpu         = "U";
        my $curr_min_vcpu    = "U";
        my $curr_max_vcpu    = "U";
        my $allocated_vcpu   = "U";
        my $desired_vcpu     = "U";
        $capped_cycles = $arr_ts_sample->[3] if ( defined $arr_ts_sample->[3] );

        #if ( $arr_ts_sample->[7] =~ m/share_idle/ || $arr_ts_sample->[7] =~ m/keep_idle/ ){
        #  $capped_cycles -= $idle_proc_cycles;
        #}

        $uncapped_cycles = $arr_ts_sample->[4] if ( defined $arr_ts_sample->[4] );

        $entitled_cycles = $arr_ts_sample->[5] if ( defined $arr_ts_sample->[5] );

        $idle_proc_cycles = $arr_ts_sample->[6] if ( defined $arr_ts_sample->[6] );

        $mode   = $arr_ts_sample->[7]  if ( defined $arr_ts_sample->[7] );
        $memory = $arr_ts_sample->[13] if ( defined $arr_ts_sample->[13] );

        $curr_proc_units = $arr_ts_sample->[14] if ( defined $arr_ts_sample->[14] );

        $curr_proc_units = $arr_ts_sample->[15] if ( defined $arr_ts_sample->[15] || $curr_proc_units eq "U" );

        $allocated_vcpu = $arr_ts_sample->[18] if ( defined $arr_ts_sample->[18] );

        #$min_vcpu = $arr_ts_sample->[18]    if (defined $arr_ts_sample->[18])  ;
        #$curr_min_vcpu = $arr_ts_sample->[19]    if (defined $arr_ts_sample->[19])  ;
        #$max_vcpu = $arr_ts_sample->[20]    if (defined $arr_ts_sample->[20])  ;
        #$curr_max_vcpu = $arr_ts_sample->[21]    if (defined $arr_ts_sample->[21])  ;
        #$desired_vcpu = $arr_ts_sample->[22]    if (defined $arr_ts_sample->[22])  ;
        if ( $mode =~ m/^share_idle_/ || $mode =~ m/^keep_idle_/ ) {
          $capped_cycles = $capped_cycles - $idle_proc_cycles if ( $capped_cycles >= $idle_proc_cycles );
        }
        if (!defined $LPA->{$rrd}{last_curr_proc_units} || !defined $LPA->{$rrd}{last_update}){
          eval {
            RRDp::cmd qq(last "$rrd" );
            my $last_rec = RRDp::read;
            RRDp::cmd qq(lastupdate "$rrd" );
            my $last_update = RRDp::read;

            ( undef, my $values ) = split( ":", $$last_update );
            my @vals = split( " ", $values );
            my $last_curr_proc_units = $vals[0];

            $LPA->{$rrd}{last_curr_proc_units} = $last_curr_proc_units;
            $LPA->{$rrd}{last_update} = $$last_rec;
          };
          if ($@) {

            #RRDp::error_mode = "catch";
            rrd_error( $@, $rrd );
            next;
          }
        }

        my $last_rec_rsm = 0;

        if (!defined $LPA->{$rsm}{last_update}){
          eval {
            RRDp::cmd qq(last "$rsm" );
            $last_rec_rsm = RRDp::read;
          };
          if ($@) {
            #RRDp::error_mode = "catch";
            rrd_error( $@, $rsm );
            next;
          }
          chomp($$last_rec_rsm);
          my $last_update_rsm = $$last_rec_rsm;

          $LPA->{$rsm}{last_update} = $last_update_rsm;

        }

        if ( $t > $LPA->{$rrd}{last_update} ) {
          $entitled_cycles = Math::BigInt->new($entitled_cycles);
          $capped_cycles   = Math::BigInt->new($capped_cycles);
          $uncapped_cycles = Math::BigInt->new($uncapped_cycles);

          if ( !( main::isdigit($curr_proc_units) ) ) { $curr_proc_units = "U"; }
          if ( !( main::isdigit($entitled_cycles) ) ) { $entitled_cycles = "U"; }
          if ( !( main::isdigit($capped_cycles) ) )   { $capped_cycles   = "U"; }
          if ( !( main::isdigit($uncapped_cycles) ) ) { $uncapped_cycles = "U"; }
          if ( ( main::isdigit($curr_proc_units) && $curr_proc_units < 0 ) || ( main::isdigit($entitled_cycles) && $entitled_cycles < 0 ) || ( main::isdigit($capped_cycles) && $capped_cycles < 0 ) || ( main::isdigit($uncapped_cycles) && $uncapped_cycles < 0 ) ) {
            my $capped_cycles_or = $capped_cycles + $idle_proc_cycles;
            main::error( "$host:$managedname : Not valid counters in lpars $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles \n Original line: $curr_proc_units:$entitled_cycles:$capped_cycles_or:$uncapped_cycles " . __FILE__ . ":" . __LINE__ );
            next;
          }

          #$curr_proc_units = 0.2 if ($lpar eq "Accept");
          if ( defined $curr_proc_units && $curr_proc_units eq "U" ) {
            next;
          }
          if ( $LPA->{$rrd}{last_curr_proc_units} ne "U" && $LPA->{$rrd}{last_curr_proc_units} != $curr_proc_units || ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} == 1 ) ) {
            if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} && $act_time_upd <= $last_known_ts_prev ) {
              next;
            }
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:U:U:U);
            if ( !defined $changed_curr_proc_units->{$lpar} ) { $changed_curr_proc_units->{$lpar} = 0; }

            #$changed_curr_proc_units->{$lpar} = $changed_curr_proc_units->{$lpar} + 1;
            $changed_curr_proc_units->{$lpar} = 1;
          }
          else {
            if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} || ( main::isdigit($act_time_upd) && $act_time_upd <= $last_known_ts_prev ) ) {
              next;
            }
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          eval { $answer = RRDp::read; };
          if ($@) {

            #rrd_error( $@, $rrd );
            next;
          }
          RRDp::cmd qq(update "$rrd_vcpu" $t:$allocated_vcpu);
          eval { $answer = RRDp::read; };
          if ($@) {

            #rrd_error( $@, $rrd );
            next;
          }
          $LPA->{$rrd_vcpu}{last_update} = $t;
        }
        if ( $t > $LPA->{$rsm}{last_update} ) {

          #          $memory = Math::BigInt->new($memory);
          RRDp::cmd qq(update "$rsm" $t:$memory);
          eval { $answer = RRDp::read; };
          if ($@) {

            #rrd_error( $@, $rrd );
            next;
          }
          $LPA->{$rsm}{last_update} = $t;
        }
      }
      ##unlink ($path) || print("Cannot delete file $path ". __FILE__. ":". __LINE__);
      if ( defined $file && defined $files[-1] && defined $files[-2] ) {
        if ( $file eq $files[-1] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/lpars_perf1" );
        }
        if ( $file eq $files[-2] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/lpars_perf2" );
        }
      }
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      if ( open( $ltiph, ">", "$wrkdir/$managedname/$host/iostat/last_ts.lpars" ) ) {
        print $ltiph "$temp_ts";
        close($ltiph);
      }
      else {
        main::error( " Can't open $wrkdir/$managedname/$host/iostat/last_ts.lpars : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
    if ( open( my $fh, ">", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
      print $fh "$last_known_timestamp\n";
      close($fh);
    }
    else {
      main::error( " Can't open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
    }

    #my $rrd_cpupool = PowerDataWrapper::get_filepath_rrd("CPUPOOL", "rrm");
    if (!defined $LPA->{$rrd_cpupool}{last_update}){
      if ( !-e $rrd_cpupool ) {
        print "Creating rrd pool_total api \nRRD CPUPOOL : $rrd_cpupool\n";
        touch("create_rrd_pool_total $rrd_cpupool");
        my $ret = create_rrd_pool_total( $rrd_cpupool, "AVERAGE" );
        if ( $ret == 2 ) {
          print "cannot create rrd pool_total api $rrd_cpupool\n";
          next;
        }
      }
    }
    if (!defined $LPA->{$rrd_cpupool_max}{last_update}){
      if ( !-e $rrd_cpupool_max ) {
        print "Creating rrd pool_total max api\nRRD CPUPOOL : $rrd_cpupool_max\n";
        touch("create_rrd_pool_total $rrd_cpupool_max");
        my $ret = create_rrd_pool_total( $rrd_cpupool_max, "MAX" );
        if ( $ret == 2 ) {
          print "cannot create rrd pool_total max api $rrd_cpupool_max\n";
          next;
        }
      }
    }
    RRDp::end;
    RRDp::start "$rrdtool";


    if (!defined $LPA->{$rrd_cpupool}{last_update}){
      RRDp::cmd qq(last "$rrd_cpupool" );
      $last_rec = RRDp::read;
      chomp($$last_rec);
      my $last_update = $$last_rec;
      $LPA->{$rrd_cpupool}{last_update} = $last_update;
    }
    my $prev_sample = {
      'entitled_cycles_c' => 0,
      'uncapped_cycles_c' => 0,
      'capped_cycles_c' => 0,
    };
    foreach my $t ( sort keys %{$lll} ) {
      my $entitled_cycles = "U";
      my $uncapped_cycles = "U";
      my $capped_cycles   = "U";
      my $idle_cycles     = "U";
      $entitled_cycles = $lll->{$t}{entitled_cycles} ? $lll->{$t}{entitled_cycles} : "U";
      $uncapped_cycles = $lll->{$t}{uncapped_cycles} ? $lll->{$t}{uncapped_cycles} : "U";
      $capped_cycles   = $lll->{$t}{capped_cycles}   ? $lll->{$t}{capped_cycles}   : "U";
      $idle_cycles     = $lll->{$t}{idle_cycles}     ? $lll->{$t}{idle_cycles}     : "U";

      if ( $t < $LPA->{$rrd_cpupool}{last_update} ) { next; }

      #print STDERR strftime("%FT%H:%M:%S", localtime(time)) . "        : DEBUG GAPS pool_total update : $rrd_cpupool | $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles\n";
      #print "Rest API       " . strftime("%FT%H:%M:%S", localtime(time)) . "        : pool_total update : $rrd_cpupool $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{capped_cycles}\n";
      $entitled_cycles = Math::BigInt->new($entitled_cycles) if ( defined $entitled_cycles );
      $uncapped_cycles = Math::BigInt->new($uncapped_cycles) if ( defined $uncapped_cycles );
      $capped_cycles   = Math::BigInt->new($capped_cycles)   if ( defined $capped_cycles );
      $idle_cycles     = Math::BigInt->new($idle_cycles)     if ( defined $idle_cycles );
      #zde
      if (!defined $uncapped_cycles || $uncapped_cycles eq '' || $uncapped_cycles eq "U"){
        $uncapped_cycles=0;
      }
      if (defined $prev_sample->{entitled_cycles} && $entitled_cycles > $prev_sample->{entitled_cycles} * 10 && $entitled_cycles > 1000000 && $prev_sample->{entitled_cycles_c} < 10){
        $entitled_cycles = "U";
        $prev_sample->{entitled_cycles_c}++;
      }
      if (defined $prev_sample->{uncapped_cycles} && $uncapped_cycles > $prev_sample->{uncapped_cycles} * 10 && $uncapped_cycles > 1000000 && $prev_sample->{uncapped_cycles_c} < 10){
        $uncapped_cycles = "U";
        $prev_sample->{uncapped_cycles_c}++;
      }
      if (defined $prev_sample->{capped_cycles} && $capped_cycles > $prev_sample->{capped_cycles} * 10 && $capped_cycles > 1000000 && $prev_sample->{capped_cycles_c} < 10){
        $capped_cycles = "U";
        $prev_sample->{capped_cycles_c}++;
      }

      $prev_sample->{entitled_cycles} = $entitled_cycles;
      $prev_sample->{capped_cycles} = $capped_cycles;
      $prev_sample->{uncapped_cycles} = $uncapped_cycles;

      RRDp::cmd qq(update "$rrd_cpupool" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
      RRDp::cmd qq(update "$rrd_cpupool_max" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
    }
  }
  else {    #old, ssh cli
    my $act_sys_cores_ssh = PowerDataWrapper::get_metric_from_config_cfg( "$wrkdir/$managedname/$host/config.cfg", "configurable_sys_proc_units" );
    print "INPUT LPAR     : $input_lpar\n";
    open( FH, "< $input_lpar" ) || main::error( " Can't open $input_lpar : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = reverse <FH>;
    close(FH);
    my $lll;
    foreach $line (@lines) {
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

      if ( $HMC == 1 ) {
        ( $time, $lpar, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation, $idle_cycles ) = split( /,/, $line );
      }
      if ( $IVM == 1 ) {
        ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
      }
      if ( $SDMC == 1 ) {
        ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
      }

      # print "001 $lpar : $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles $capped_cycles, $uncapped_cycles, $idle_cycles\n";
      # $curr_proc_units can be null for dedicated partitions so do not test it here!!!!
      if ( $curr_procs eq '' || $curr_sharing_mode eq '' || $entitled_cycles eq '' || $capped_cycles eq '' || $uncapped_cycles eq '' ) {

        # something wrong with input data, skipping it
        # it migh happen, here is en example : 05/03/2012 22:34:50,1,,,,,,
        next;
      }

      #print "$time $lpar \n";
      # Check whether the first character is a digit, if not then there is something wrong with the
      # input data
      my $ret = substr( $time, 0, 1 );

      #if (($ret =~ /\D/) || ( $lpar eq '' ))  left_curly
      # do not put there $lpar as it might be NULL when the systems is down, seen it for memory
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
        close(FH);
        return 1;
      }

      if ( $HMC == 0 ) {    # IVM translation ids to names
                            # this will have a problem whether a "," is inside lpar name
        foreach my $li (@lpar_trans) {
          chomp($li);
          ( my $id, my $name ) = split( /,/, $li );

          #print "---02 $li -- $id - $lpar_id\n";
          if ( $id == $lpar_id ) {
            $lpar = $name;
            last;
          }
        }
      }

      if ( $lpar =~ m/IOR Collection LP/ ) {    #it is some trash, it exists time to tme, some IBM internal ...
        next;                                   #ignore it
      }
      if ( $lpar eq '' ) {
        next;                                   #again something wrong
      }

      # replace / by &&1, install-html.sh does the reverse thing
      $lpar =~ s/\//\&\&1/g;

      $t = str2time( substr( $time, 0, 19 ) );

      #print "DEBUG Timestamp : $t, $time\n";

      #here???

      $t = correct_to_local_timezone( $t, $hmc_timezone, $local_timezone );

      #sub correct_to_local_timezone{
      #    my $t = shift;
      #    my $hmc_timezone = shift;
      #    my $tz_n = substr($hmc_timezone,1,4);
      #    $tz_n /= 100;
      #    if (substr($hmc_timezone,0,1) eq "+"){
      #      $t = $t + ($tz_n * 3600);
      #    } else { # -
      #      $t = $t - ($tz_n * 3600);
      #    }
      #    return $t;
      #}

      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname :No valid lpar data time format got from HMC : $t : $line : " . __FILE__ . ":" . __LINE__ );
        next;    # next only, could  happen that there appears unix 0 time on the HMC after the upgrade, then just ignore it
      }

      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );

        #print "$t $lpar\n";
        #print "Input data: $lpar\n";
      }
      if ( $lpar =~ m/\"/ ) {

        # LPAR cannot contain double quote, it is an illegal character in the lpar name, report it once and ignore it
        if ( $error_once == 0 ) {
          main::error( "$host:$managedname :LPAR cannot contain double quote, it is an illegal character in the lpar name: $lpar : $line : " . __FILE__ . ":" . __LINE__ );
        }
        $error_once++;
        next;
      }

      $rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";

      #print "RRDNAME = $lpar.rr$type_sam\n";

      #create rrd db if necessary
      # find out if rrd db exist, and place info to the array to do not check its existency every time
      my $rrd_exist_ok  = 0;
      my $rrd_exist_row = 0;
      foreach my $row (@rrd_exist) {
        $rrd_exist_row++;
        if ( $row =~ m/^$lpar$/ ) {
          $rrd_exist_ok = 1;
          last;
        }
      }
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, $SSH, $hmc_user, $wrkdir, $lpar, $t, $keep_virtual );

        my $rrd_vcpu = $rrd;
        $rrd_vcpu =~ s/rrm/rvm/g;

        if ( !-e $rrd_vcpu ) {
          my $ret = create_rrd_vcpu( $rrd_vcpu, "AVERAGE" );
          if ( $ret == 2 ) {
            print "Cannot create rrd_vcpu $rrd_vcpu\n";
          }
        }

        if ( $ret == 1 ) {

          # this lpar has been recently renamed, ignore it then
          next;
        }
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist[$rrd_exist_row] = $lpar;
      }

      # found out last record and save it
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
        $ltime   = $lpar_time[$found];
        $l_count = $found;
      }
      else {
        # find out last record in the db
        # as this makes it slowly to test it each time then it is done
        # once per a lpar for whole load and saved into the array

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
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
        $lpar_idle[$l_count] = 0;
        $ltime               = $$last_rec;
      }

      # when dedicated partitions then there is not set up $curr_proc_units as it is useless
      # I put curr_procs into curr_proc_units to make some gratphs for dedicated lpars
      if ( $curr_sharing_mode =~ m/^share_idle_/ || $curr_sharing_mode =~ m/^keep_idle_/ || length($curr_proc_units) == 0 ) {
        $curr_proc_units = $curr_procs;
        if ( defined($idle_cycles) && !$idle_cycles eq '' && $idle_cycles > 0 ) {

          # CPU lpars have reported idle cycles on new HMC firmwares --> use it for utilization
          $capped_cycles -= $idle_cycles;
          if ( $capped_cycles < 0 ) {

            # capped_cycles can be negative --> CPU dedicated LPARs after LPM might have more idle than capped -->
            # it is a big problem, only the solution is store initial big $idle counter and always use it for decrement of $idle
            # ideal solution would be storing $idle into rrd, but problem with compatability ... :(
            if ( $lpar_idle[$l_count] == 0 ) {
              $lpar_idle[$l_count] = get_lpar_idle_count( $wrkdir, $host, $managedname, $lpar_name[$l_count], $idle_cycles, "get" );
            }
            $capped_cycles = $capped_cycles + $lpar_idle[$l_count];
            if ( $capped_cycles < 0 ) {

              # might appear that it is still negative after several LPM, original saved $idle must be refreshed
              $capped_cycles       = $capped_cycles - $lpar_idle[$l_count];                                                              # return saved one
              $lpar_idle[$l_count] = get_lpar_idle_count( $wrkdir, $host, $managedname, $lpar_name[$l_count], $idle_cycles, "force" );
              $capped_cycles       = $capped_cycles + $lpar_idle[$l_count];
            }
            if ( $capped_cycles < 0 ) {

              # if still < 0 then something works bad, note error and skip it
              if ( $error_count == 0 ) {
                main::error( "counter < 0! :  $rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles - $idle_cycles,$lpar_idle[$l_count], skipping LPAR $lpar_name[$l_count] " . __FILE__ . ":" . __LINE__ );
                $error_count++;
              }
              next;
            }
          }
        }

        # no, no here, shared_syscles* modes containg right $capped_cycles data
        #if ( defined ($shared_cycles_while_active) && ! $shared_cycles_while_active eq '' &&  main::isdigit($shared_cycles_while_active) ) {
        #  $capped_cycles -= $shared_cycles_while_active; # only for LPARs in share_idle_procs_always mode
        #}
        $capped_cycles = $capped_cycles + 0;    #conversion to format understable for rrdtool
      }

      # when CPU dedicated LPARs and modes "share_idle*" then there is already capped shown correctly in data!
      #   --> then do not lower entitlement as this produce wrong numbers then
      # if $curr_proc_units == 0 then lpar is not running and it causing a problem with donated cycles
      #if ($curr_proc_units > 0) {
      #  # exclude POWER5 systems where $shared_cycles_while_active does not exist
      #  # it is for donation of dedicated CPU lpars
      #  if ($curr_sharing_mode =~ "share_idle_procs" || $curr_sharing_mode =~ "share_idle_procs_active" || \
      #      $curr_sharing_mode =~ "share_idle_procs_always" ) {
      #    if ( ! $shared_cycles_while_active eq '' ) {
      #      if ( $entitled_cycles < $shared_cycles_while_active ) {
      #         main::error ("$rrd $t:$entitled_cycles - $shared_cycles_while_active < 0 !!! ".__FILE__.":".__LINE__);
      #         next;
      #      }
      #      # necesary due to Perl behaviour whe it convert it to format X.YZ+eXY
      #      $entitled_cycles= $entitled_cycles - $shared_cycles_while_active;
      #      $entitled_cycles = Math::BigInt->new($entitled_cycles);
      #    }
      #  }
      #}

      if ( $t > $ltime && length($curr_proc_units) > 0 ) {

        #print "$lpar: $time $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles \n";
        if ( data_check( $entitled_cycles, $capped_cycles, $uncapped_cycles, $lpar, $host, $managedname ) == 0 ) {

          my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
          if ( $t > $jump_time ) {

            # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
            # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
            if ( $lpar_jump[$l_count] == 0 ) {
              $lpar_jump[$l_count] = 1;

              #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
              #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
              next;
            }

            # looks like it is ok as it is second timestap in a row
          }
          $lpar_jump[$l_count] = 0;

          # It does not go there even when partition is switched off and counters are 0
          if ( $entitled_cycles < 0 || $uncapped_cycles < 0 || $capped_cycles < 0 ) {
            if ( $error_count == 0 ) {
              main::error( "counter < 0! :  $rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles " . __FILE__ . ":" . __LINE__ );
              $error_count++;
            }
            next;
          }

          # conversion from scientific X.YeYY format to usual decimal format
          #$curr_proc_units = $curr_proc_units + 0;
          #$curr_procs = $curr_procs + 0;
          #$entitled_cycles = $entitled_cycles + 0;
          #$capped_cycles = $capped_cycles + 0;
          #$uncapped_cycles = $uncapped_cycles + 0;
          # It does not work good (always!), use below one instead
          #$curr_proc_units = Math::BigInt->new($curr_proc_units); --> never use it for this, it is integer --> it cut everything behind decimal
          #$curr_procs      = Math::BigInt->new($curr_procs); --> never use it for this, it is integer --> it cut everything behind decimal

          if ( !( main::isdigit($curr_proc_units) ) ) { $curr_proc_units = "U"; }
          if ( !( main::isdigit($curr_procs) ) )      { $curr_procs      = "U"; }
          if ( !( main::isdigit($entitled_cycles) ) ) { $entitled_cycles = "U"; }
          if ( !( main::isdigit($capped_cycles) ) )   { $capped_cycles   = "U"; }
          if ( !( main::isdigit($uncapped_cycles) ) ) { $uncapped_cycles = "U"; }
          print "$lpar PROCS: $curr_procs PROC_UNITS : $curr_proc_units\n"                         if $DEBUG_REST_API;
          print "$lpar counters : $capped_cycles $uncapped_cycles $entitled_cycles $idle_cycles\n" if $DEBUG_REST_API;
          my $powered_on = $uncapped_cycles + $capped_cycles + $entitled_cycles + $idle_cycles;

          #here
          #$lll->{$t}{cores} += $curr_proc_units;
          if ( !$powered_on ) {
            print "skip powered off $lpar\n" if $DEBUG_REST_API;
            next;
          }
          $lll->{$t}{configured_proc_units} = defined $act_sys_cores_ssh ? $act_sys_cores_ssh : "U";
          $lll->{$t}{cores}           += $curr_proc_units;
          $lll->{$t}{entitled_cycles} += $entitled_cycles;
          $lll->{$t}{capped_cycles}   += $capped_cycles;
          $lll->{$t}{idle_cycles}     += $idle_cycles;
          $lll->{$t}{uncapped_cycles} += $uncapped_cycles;

          $entitled_cycles = Math::BigInt->new($entitled_cycles) if ( defined $entitled_cycles );
          $uncapped_cycles = Math::BigInt->new($uncapped_cycles);
          $capped_cycles   = Math::BigInt->new($capped_cycles);

          if ( $keep_virtual == 1 ) {

            # new one, DHL needs to keep virtual processors for accounting
            my $datestring = localtime();
            print "Debug-004a-$rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles\n" if $DEBUG_REST_API;
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          else {
            # old way without storing number of virtual processors
            my $datestring = localtime();
            print "Debug-004b-$rrd $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles (- no curr_procs)\n" if $DEBUG_REST_API;
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          $answer    = RRDp::read;
          $last_time = $time;
          $counter_ins++;
          if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
            main::error(" $host:$managedname : $rrd : $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles : $line : $$answer");
            if ( $$answer =~ m/is not an RRD file/ ) {
              ( my $err, my $file, my $txt ) = split( /'/, $$answer );
              main::error("Removing as it seems to be corrupted: $file");
              unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
            }
          }
          my $rrd_vcpu = $rrd;
          $rrd_vcpu =~ s/rrm/rvm/g;

          if ( !-e $rrd_vcpu ) {
            my $ret = create_rrd_vcpu( $rrd_vcpu, "AVERAGE" );
            if ( $ret == 2 ) {
              print "Cannot create rrd_vcpu $rrd_vcpu\n";
            }
          }
          RRDp::cmd qq(update "$rrd_vcpu" $t:$curr_procs);
          $answer = RRDp::read;

          if ( defined $$answer && $$answer ne '' && $$answer =~ m/ERROR/ ) {
            main::error(" $host:$managedname : $rrd_vcpu : $t:$curr_procs");
            if ( $$answer =~ m/is not an RRD file/ ) {
              ( my $err, my $file, my $txt ) = split( /'/, $$answer );
              main::error("Removing as it seems to be corrupted: $file");
              unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
            }
          }

          # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
          $lpar_time[$l_count] = $t;
        }

        # memory should go through although switched off partition
        # sometimes (? when partition is halted??) it might have still allocated memory although it is off!!!

        #
        #  memory stuff
        #

        if ( !$mem_mode eq '' ) {
          if ( $mem_mode =~ m/shared/ ) {

            # AMS memory stuff only if it is activated
            if ( $curr_mem eq '' || $phys_run_mem eq '' || $curr_io_entitled_mem eq '' || $mapped_io_entitled_mem eq '' || $mem_overage_cooperation eq '' ) {

              #main::error ("$host:$managedname : wrong mem input, shared defined but some value is null : $line");
              #main::error ("$host:$managedname: future timestamp: $rrd");
              #print "$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation\n";
            }
            else {
              #create rrd db if necessary
              # find out if rrd db exist, and place info to the array to do not check its existency every time
              my $rmd_exist_ok  = 0;
              my $rmd_exist_row = 0;
              foreach my $row1 (@rmd_exist) {
                $rmd_exist_row++;
                if ( $row1 =~ m/^$lpar$/ ) {
                  $rmd_exist_ok = 1;
                  last;
                }
              }
              my $rmd = "$wrkdir/$managedname/$host/$lpar.rm$type_sam";
              if ( $rmd_exist_ok == 0 ) {
                $rmd_exist[$rmd_exist_row] = $lpar;
                my $ret = create_lpar_mem( $rmd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
                if ( $ret == 2 ) {
                  return 1;    # RRD creation problem, skip whole load
                }
              }

              # found out last record and save it
              # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
              $l_count_rmd = 0;
              my $found_rmd = -1;
              my $lpar_meta = quotemeta($lpar);
              foreach my $l (@lpar_name_rmd) {
                if ( $l =~ m/^$lpar_meta$/ ) {
                  $found_rmd = $l_count_rmd;
                  last;
                }
                $l_count_rmd++;
              }

              #print "RMD 01: $lpar $found_rmd - $t\n";
              if ( $found_rmd > -1 ) {
                $ltime_rmd   = $lpar_time_rmd[$found_rmd];
                $l_count_rmd = $found_rmd;
              }
              else {
                # find out last record in the db
                # as this makes it slowly to test it each time then it is done
                # once per a lpar for whole load and saved into the array

                # construction against crashing daemon Perl code when RRDTool error appears
                # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
                # construction is not too costly as it runs once per each load
                eval {
                  RRDp::cmd qq(last "$rmd" );
                  $last_rec = RRDp::read;
                };
                if ($@) {
                  rrd_error( $@, $rmd );
                  if ( $rmd_exist[$rmd_exist_row] =~ m/^$lpar$/ ) {
                    $rmd_exist[$rmd_exist_row] = "";
                  }
                  next;
                }
                chomp($$last_rec);
                $lpar_name_rmd[$l_count_rmd] = $lpar;
                $lpar_time_rmd[$l_count_rmd] = $$last_rec;
                $ltime_rmd                   = $$last_rec;

                #print "RMD 01: $lpar $ltime_rmd - $t\n";
              }

              #print "RMD 02: $lpar $ltime_rmd - $t\n";

              if ( $t > $ltime_rmd ) {
                my $datestring = localtime();
                print "Debug-005-$datestring-$rmd $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation\n" if $DEBUG_REST_API;
                if ( !( main::isdigit($curr_mem) ) )                { $curr_mem                = "U"; }
                if ( !( main::isdigit($phys_run_mem) ) )            { $phys_run_mem            = "U"; }
                if ( !( main::isdigit($curr_io_entitled_mem) ) )    { $curr_io_entitled_mem    = "U"; }
                if ( !( main::isdigit($mapped_io_entitled_mem) ) )  { $mapped_io_entitled_mem  = "U"; }
                if ( !( main::isdigit($mem_overage_cooperation) ) ) { $mem_overage_cooperation = "U"; }
                RRDp::cmd qq(update "$rmd" $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation);
                $last_time = $time;

                if ( $counter_ins == 0 ) {
                  $counter_ins++;    # just to force update last.txt
                }
                $answer = RRDp::read;
                if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
                  main::error(" $host:$managedname : $rmd : $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation : $line : $$answer");
                  if ( $$answer =~ m/is not an RRD file/ ) {
                    ( my $err, my $file, my $txt ) = split( /'/, $$answer );
                    main::error("Removing as it seems to be corrupted: $file");
                    unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  }
                }

                # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
                $lpar_time_rmd[$l_count_rmd] = $t;
              }
            }
          }
          else {
            # dedicated mode, just 1 item inside
            if ( $curr_mem eq '' ) {

              #main::error("$host:$managedname : wrong mem input, dedicated mem defined but curr_mem is null : $line");

              #print "$curr_mem\n";
            }
            else {
              #create rrd db if necessary
              # find out if rrd db exist, and place info to the array to do not check its existency every time
              my $rsd_exist_ok  = 0;
              my $rsd_exist_row = 0;
              foreach my $row1 (@rsd_exist) {
                $rsd_exist_row++;
                if ( $row1 =~ m/^$lpar$/ ) {
                  $rsd_exist_ok = 1;
                  last;
                }
              }
              $lpar =~ s/\//\&\&1/g;
              my $rsd = "$wrkdir/$managedname/$host/$lpar.rs$type_sam";
              if ( $rsd_exist_ok == 0 ) {
                $rsd_exist[$rsd_exist_row] = $lpar;
                my $ret = create_lpar_mem_ded( $rsd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
                if ( $ret == 2 ) {
                  return 1;    # RRD creation problem, skip whole load
                }
              }

              # found out last record and save it
              # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
              $l_count_rsd = 0;
              my $found_rsd = -1;
              my $lpar_meta = quotemeta($lpar);
              foreach my $l (@lpar_name_rsd) {
                if ( $l =~ m/^$lpar_meta$/ ) {
                  $found_rsd = $l_count_rsd;

                  #print "RSD 01: $lpar - $found_rsd - $lpar_meta\n";
                  last;
                }
                $l_count_rsd++;
              }

              #print "RSD 01: $lpar $found_rsd - $t\n";
              if ( $found_rsd > -1 ) {
                $ltime_rsd   = $lpar_time_rsd[$found_rsd];
                $l_count_rsd = $found_rsd;

                #print "RSD 02: $lpar $ltime_rsd - $found_rsd\n";
              }
              else {
                # find out last record in the db
                # as this makes it slowly to test it each time then it is done
                # once per a lpar for whole load and saved into the array

                # construction against crashing daemon Perl code when RRDTool error appears
                # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
                # construction is not too costly as it runs once per each load
                eval {
                  RRDp::cmd qq(last "$rsd" );
                  $last_rec = RRDp::read;
                };
                if ($@) {
                  rrd_error( $@, $rsd );
                  if ( $rsd_exist[$rsd_exist_row] =~ m/^$lpar$/ ) {
                    $rsd_exist[$rsd_exist_row] = "";
                  }
                  next;
                }
                chomp($$last_rec);
                $lpar_name_rsd[$l_count_rsd] = $lpar;
                $lpar_time_rsd[$l_count_rsd] = $$last_rec;
                $ltime_rsd                   = $$last_rec;

                #print "RSD 03: $lpar $ltime_rsd - $$last_rec\n";
              }

              #print "RSD 04: $lpar $ltime_rsd - $t\n";

              if ( $t > $ltime_rsd ) {
                my $datestring = localtime();
                print "Debug-006-$datestring-$rsd $t:$curr_mem\n" if $DEBUG_REST_API;
                if ( !( main::isdigit($curr_mem) ) ) { $curr_mem = "U"; }
                RRDp::cmd qq(update "$rsd" $t:$curr_mem);
                if ( $counter_ins == 0 ) {
                  $counter_ins++;    # just to force update last.txt
                }
                $last_time = $time;
                $answer    = RRDp::read;
                if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
                  main::error(" $host:$managedname : $rsd : $t:$curr_mem : $line : $$answer");
                  if ( $$answer =~ m/is not an RRD file/ ) {
                    ( my $err, my $file, my $txt ) = split( /'/, $$answer );
                    main::error("Removing as it seems to be corrupted: $file");
                    unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  }
                }

                # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
                $lpar_time_rsd[$l_count_rsd] = $t;
              }
            }
          }

        }    #memory

      }
    }
             #RRDp::start "$rrdtool";
    if ( !-e $rrd_cpupool ) {
      print "Creating rrd pool_total ssh \nRRD CPUPOOL : $rrd_cpupool\n";
      touch("create_rrd_pool_total $rrd_cpupool");
      my $ret = create_rrd_pool_total( $rrd_cpupool, "AVERAGE" );
      if ( $ret == 2 ) {
        print "cannot create rrd pool_total ssh $rrd_cpupool\n";
        return;
      }
    }
    if ( !-e $rrd_cpupool_max ) {
      print "Creating rrd pool_total max ssh\nRRD CPUPOOL : $rrd_cpupool_max\n";
      touch("create_rrd_pool_total $rrd_cpupool_max");
      my $ret = create_rrd_pool_total( $rrd_cpupool_max, "MAX" );
      if ( $ret == 2 ) {
        print "cannot create rrd pool_total max ssh $rrd_cpupool_max\n";
        return;
      }
    }
    RRDp::cmd qq(last "$rrd_cpupool" );
    my $last_rec = RRDp::read;
    chomp($$last_rec);
    my $last_update = $$last_rec;
    my $capped_last = 0;
    foreach my $t ( sort keys %{$lll} ) {
      if ( $t <= $last_update ) { next; }
      $lll->{$t}{capped_cycles}   = $lll->{$t}{capped_cycles}   ? Math::BigInt->new( $lll->{$t}{capped_cycles} )   : "U";
      $lll->{$t}{entitled_cycles} = $lll->{$t}{entitled_cycles} ? Math::BigInt->new( $lll->{$t}{entitled_cycles} ) : "U";
      $lll->{$t}{uncapped_cycles} = $lll->{$t}{uncapped_cycles} ? Math::BigInt->new( $lll->{$t}{uncapped_cycles} ) : "U";
      $lll->{$t}{idle_cycles}     = $lll->{$t}{idle_cycles}     ? Math::BigInt->new( $lll->{$t}{idle_cycles} )     : "U";

      if (!defined $lll->{$t}{uncapped_cycles} || $lll->{$t}{uncapped_cycles} eq '' || $lll->{$t}{uncapped_cycles} eq "U"){
        $lll->{$t}{uncapped_cycles}=0;
      }
      #check the counter value and skip if the newer counter is wrong (lower than the previous one)
      if ( $capped_last > $lll->{$t}{capped_cycles} ) {

        #skip, the counter cannot be lower than the previous correct one
        main::error("error when updating $rrd_cpupool (and max) - got wrong data from HMC - capped (current):$lll->{$t}{capped_cycles} vs. capped (previous):$capped_last - skip timestamp $t");
        next;
      }

      #counter is ok, continue with update of the rrds
      $capped_last = $lll->{$t}{capped_cycles};

      #print STDERR strftime("%FT%H:%M:%S", localtime(time)) . "        : DEBUG GAPS pool_total ssh update : $rrd_cpupool | $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles}\n";
      RRDp::cmd qq(update "$rrd_cpupool" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles});
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
      RRDp::cmd qq(update "$rrd_cpupool_max" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles});
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
    }
  }    #end else (if json !configured
  if ( $error_count > 1 ) {
    main::error( "error count  : $host:$managedname:lpar $error_count " . __FILE__ . ":" . __LINE__ );
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:lpar $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_older {
  my $LPA;
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $SSH, $hmc_user, $json_configured, $save_files, $model, $serial, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $model) { $model = ""; }
  if (!defined $serial) { $serial = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
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
  my $jump         = 0;

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

  my $input_lpar = "$input-$type_sam";
  if ( $ENV{LPAR_LOAD_EXTERNAL} ) {
    if ( -f $ENV{LPAR_LOAD_EXTERNAL} ) {
      $input_lpar = $ENV{LPAR_LOAD_EXTERNAL};    # keep number of virt processors in RRD --> etc/.magic
    }
  }

  my $line      = "";
  my @rrd_exist = "";
  my @rmd_exist = "";
  my @rsd_exist = "";

  my @lpar_name = "";
  my @lpar_idle = "";
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

  my $rrd_cpupool     = PowerDataWrapper::get_filepath_rrd_cpupool( $managedname, $host, "rrt" );
  my $rrd_cpupool_max = PowerDataWrapper::get_filepath_rrd_cpupool( $managedname, $host, "rxm" );
  if ( defined $json_configured && $json_configured == 1 ) {
    my $perf_string = "lpars_perf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    my $last_known_ts_prev = 0;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.lpars" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.lpars" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.lpars at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    if ( !( -e "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
      if ( open( my $fh_last_ts, ">", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
        print $fh_last_ts "null";
        close($fh_last_ts);
      }
      else {
        main::error( " Cannot open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
    if ( open( my $fh_last_ts, "<", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
      $last_known_ts_prev = readline($fh_last_ts);
      if ( !( main::isdigit($last_known_ts_prev) ) ) {
        $last_known_ts_prev = 0;
      }
      close($fh_last_ts);
    }
    else {
      main::error( " Cannot open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
    }
    my $last_known_timestamp = "";
    my $act_time_upd         = time;
    my $lll;
    my $act_sys_cores_api           = PowerDataWrapper::get_server_metric( $managedname, "ConfigurableSystemProcessorUnits", 0 );
    my $CurrentProcessingUnitsTotal = PowerDataWrapper::get_server_metric( $managedname, "CurrentProcessingUnitsTotal",      0 );
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path    = "$iostatdir$file";
      my $content = [];
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) eq "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        print "no content in $path\n";
        next;
      }
      my $temp_ts;
      my $changed_curr_proc_units;
      foreach my $arr_ts_sample ( @{$content} ) {
        my $t = str2time( $arr_ts_sample->[0] );
        $last_known_timestamp = $t;
        $temp_ts              = $t;
        my $lpar = $arr_ts_sample->[1];

        #if ($lpar =~ m/p770-demo/){ next; }
        if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} ) {
          next;
        }
        my $powered_on = $arr_ts_sample->[3] + $arr_ts_sample->[4] + $arr_ts_sample->[5] + $arr_ts_sample->[6];
        if ( !$powered_on ) {
          next;
        }

        $lll->{$t}{mode}                  = $arr_ts_sample->[7]          ? $arr_ts_sample->[7]          : "U";
        $lll->{$t}{cores}                 = $CurrentProcessingUnitsTotal ? $CurrentProcessingUnitsTotal : "U";
        $lll->{$t}{configured_proc_units} = $act_sys_cores_api           ? $act_sys_cores_api           : "U";
        $lll->{$t}{capped_cycles}         = $lll->{$t}{capped_cycles}    ? $lll->{$t}{capped_cycles}    : 0;

        #        print "LPAR XXX $managedname : $lpar (tot cpu: $lll->{$t}{cores}) : $lll->{$t}{mode} c:$arr_ts_sample->[3] u:$arr_ts_sample->[4] e:$arr_ts_sample->[5] i:$arr_ts_sample->[6]\n";
        $lll->{$t}{capped_cycles} += $arr_ts_sample->[3] if defined $arr_ts_sample->[3];
        if ( $arr_ts_sample->[7] =~ m/share_idle/ || $arr_ts_sample->[7] =~ m/keep_idle/ ) {
          $lll->{$t}{capped_cycles} -= $arr_ts_sample->[6];
        }

        if ( !defined $lll->{$t}{uncapped_cycles} ) { $lll->{$t}{uncapped_cycles} = 0; }
        $lll->{$t}{uncapped_cycles} += $arr_ts_sample->[4] if defined $arr_ts_sample->[4];

        if ( !defined $lll->{$t}{entitled_cycles} ) { $lll->{$t}{entitled_cycles} = 0; }
        $lll->{$t}{entitled_cycles} += $arr_ts_sample->[5] if defined $arr_ts_sample->[5];

        if ( !defined $lll->{$t}{idle_cycles} ) { $lll->{$t}{idle_cycles} = 0; }
        $lll->{$t}{idle_cycles} += $arr_ts_sample->[6] if defined $arr_ts_sample->[6];

        $lpar =~ s/\//\&\&1/g;
        $rrd = PowerDataWrapper::get_filepath_rrd_vm( $lpar, $managedname, "rrm" );
        my $rrd_vcpu = PowerDataWrapper::get_filepath_rrd_vm( $lpar, $managedname, "rvm" );
        my $rsm      = PowerDataWrapper::get_filepath_rrd_vm( $lpar, $managedname, "rsm" );

        #$rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";
        if (!defined $LPA->{$rrd}{last_update}){
          if ( !-e $rrd ) {
            my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, "", "", $wrkdir, $lpar, $t, $keep_virtual );
            if ( $ret == 2 ) {
              next;
            }
          }
        }
        if (!defined $LPA->{$rsm}{last_update}){
          if ( !-e $rsm ) {

            #         my $ret = create_rrd( $rsm, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, "", "", $wrkdir, $lpar, $t, $keep_virtual );
            my $ret = create_lpar_mem_ded( $rsm, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
            if ( $ret == 2 ) {
              next;
            }
          }
        }
        if (!defined $LPA->{$rrd_vcpu}{last_update}){
          if ( !-e $rrd_vcpu ) {
            my $ret = create_rrd_vcpu( $rrd_vcpu, "AVERAGE" );
            if ( $ret == 2 ) {
              print "Cannot create rrd_vcpu $rrd_vcpu\n";
            }
          }
        }
        my $curr_proc_units  = "U";
        my $entitled_cycles  = "U";
        my $capped_cycles    = "U";
        my $uncapped_cycles  = "U";
        my $mode             = "U";
        my $idle_proc_cycles = "U";
        my $memory           = 0;
        my $min_vcpu         = "U";
        my $max_vcpu         = "U";
        my $curr_min_vcpu    = "U";
        my $curr_max_vcpu    = "U";
        my $allocated_vcpu   = "U";
        my $desired_vcpu     = "U";
        $capped_cycles = $arr_ts_sample->[3] if ( defined $arr_ts_sample->[3] );

        #if ( $arr_ts_sample->[7] =~ m/share_idle/ || $arr_ts_sample->[7] =~ m/keep_idle/ ){
        #  $capped_cycles -= $idle_proc_cycles;
        #}

        $uncapped_cycles = $arr_ts_sample->[4] if ( defined $arr_ts_sample->[4] );

        $entitled_cycles = $arr_ts_sample->[5] if ( defined $arr_ts_sample->[5] );

        $idle_proc_cycles = $arr_ts_sample->[6] if ( defined $arr_ts_sample->[6] );

        $mode   = $arr_ts_sample->[7]  if ( defined $arr_ts_sample->[7] );
        $memory = $arr_ts_sample->[13] if ( defined $arr_ts_sample->[13] );

        $curr_proc_units = $arr_ts_sample->[14] if ( defined $arr_ts_sample->[14] );

        $curr_proc_units = $arr_ts_sample->[15] if ( defined $arr_ts_sample->[15] || $curr_proc_units eq "U" );

        $allocated_vcpu = $arr_ts_sample->[18] if ( defined $arr_ts_sample->[18] );

        #$min_vcpu = $arr_ts_sample->[18]    if (defined $arr_ts_sample->[18])  ;
        #$curr_min_vcpu = $arr_ts_sample->[19]    if (defined $arr_ts_sample->[19])  ;
        #$max_vcpu = $arr_ts_sample->[20]    if (defined $arr_ts_sample->[20])  ;
        #$curr_max_vcpu = $arr_ts_sample->[21]    if (defined $arr_ts_sample->[21])  ;
        #$desired_vcpu = $arr_ts_sample->[22]    if (defined $arr_ts_sample->[22])  ;
        if ( $mode =~ m/^share_idle_/ || $mode =~ m/^keep_idle_/ ) {
          $capped_cycles = $capped_cycles - $idle_proc_cycles if ( $capped_cycles >= $idle_proc_cycles );
        }
        if (!defined $LPA->{$rrd}{last_curr_proc_units} || !defined $LPA->{$rrd}{last_update}){
          eval {
            RRDp::cmd qq(last "$rrd" );
            my $last_rec = RRDp::read;
            RRDp::cmd qq(lastupdate "$rrd" );
            my $last_update = RRDp::read;

            ( undef, my $values ) = split( ":", $$last_update );
            my @vals = split( " ", $values );
            my $last_curr_proc_units = $vals[0];

            $LPA->{$rrd}{last_curr_proc_units} = $last_curr_proc_units;
            $LPA->{$rrd}{last_update} = $$last_rec;
          };
          if ($@) {

            #RRDp::error_mode = "catch";
            rrd_error( $@, $rrd );
            next;
          }
        }

        my $last_rec_rsm = 0;

        if (!defined $LPA->{$rsm}{last_update}){
          eval {
            RRDp::cmd qq(last "$rsm" );
            $last_rec_rsm = RRDp::read;
          };
          if ($@) {
            #RRDp::error_mode = "catch";
            rrd_error( $@, $rsm );
            next;
          }
          chomp($$last_rec_rsm);
          my $last_update_rsm = $$last_rec_rsm;

          $LPA->{$rsm}{last_update} = $last_update_rsm;

        }

        if ( $t > $LPA->{$rrd}{last_update} ) {
          $entitled_cycles = Math::BigInt->new($entitled_cycles);
          $capped_cycles   = Math::BigInt->new($capped_cycles);
          $uncapped_cycles = Math::BigInt->new($uncapped_cycles);

          if ( !( main::isdigit($curr_proc_units) ) ) { $curr_proc_units = "U"; }
          if ( !( main::isdigit($entitled_cycles) ) ) { $entitled_cycles = "U"; }
          if ( !( main::isdigit($capped_cycles) ) )   { $capped_cycles   = "U"; }
          if ( !( main::isdigit($uncapped_cycles) ) ) { $uncapped_cycles = "U"; }
          if ( ( main::isdigit($curr_proc_units) && $curr_proc_units < 0 ) || ( main::isdigit($entitled_cycles) && $entitled_cycles < 0 ) || ( main::isdigit($capped_cycles) && $capped_cycles < 0 ) || ( main::isdigit($uncapped_cycles) && $uncapped_cycles < 0 ) ) {
            my $capped_cycles_or = $capped_cycles + $idle_proc_cycles;
            main::error( "$host:$managedname : Not valid counters in lpars $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles \n Original line: $curr_proc_units:$entitled_cycles:$capped_cycles_or:$uncapped_cycles " . __FILE__ . ":" . __LINE__ );
            next;
          }

          #$curr_proc_units = 0.2 if ($lpar eq "Accept");
          if ( defined $curr_proc_units && $curr_proc_units eq "U" ) {
            next;
          }
          if ( $LPA->{$rrd}{last_curr_proc_units} ne "U" && $LPA->{$rrd}{last_curr_proc_units} != $curr_proc_units || ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} == 1 ) ) {
            if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} && $act_time_upd <= $last_known_ts_prev ) {
              next;
            }
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:U:U:U);
            if ( !defined $changed_curr_proc_units->{$lpar} ) { $changed_curr_proc_units->{$lpar} = 0; }

            #$changed_curr_proc_units->{$lpar} = $changed_curr_proc_units->{$lpar} + 1;
            $changed_curr_proc_units->{$lpar} = 1;
          }
          else {
            if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} || ( main::isdigit($act_time_upd) && $act_time_upd <= $last_known_ts_prev ) ) {
              next;
            }
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          eval { $answer = RRDp::read; };
          if ($@) {

            #rrd_error( $@, $rrd );
            next;
          }
          RRDp::cmd qq(update "$rrd_vcpu" $t:$allocated_vcpu);
          eval { $answer = RRDp::read; };
          if ($@) {

            #rrd_error( $@, $rrd );
            next;
          }
          $LPA->{$rrd_vcpu}{last_update} = $t;
        }
        if ( $t > $LPA->{$rsm}{last_update} ) {

          #          $memory = Math::BigInt->new($memory);
          RRDp::cmd qq(update "$rsm" $t:$memory);
          eval { $answer = RRDp::read; };
          if ($@) {

            #rrd_error( $@, $rrd );
            next;
          }
          $LPA->{$rsm}{last_update} = $t;
        }
      }
      ##unlink ($path) || print("Cannot delete file $path ". __FILE__. ":". __LINE__);
      if ( defined $file && defined $files[-1] && defined $files[-2] ) {
        if ( $file eq $files[-1] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/lpars_perf1" );
        }
        if ( $file eq $files[-2] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/lpars_perf2" );
        }
      }
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      if ( open( $ltiph, ">", "$wrkdir/$managedname/$host/iostat/last_ts.lpars" ) ) {
        print $ltiph "$temp_ts";
        close($ltiph);
      }
      else {
        main::error( " Can't open $wrkdir/$managedname/$host/iostat/last_ts.lpars : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
    if ( open( my $fh, ">", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
      print $fh "$last_known_timestamp\n";
      close($fh);
    }
    else {
      main::error( " Can't open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
    }

    #my $rrd_cpupool = PowerDataWrapper::get_filepath_rrd("CPUPOOL", "rrm");
    if (!defined $LPA->{$rrd_cpupool}{last_update}){
      if ( !-e $rrd_cpupool ) {
        print "Creating rrd pool_total api \nRRD CPUPOOL : $rrd_cpupool\n";
        touch("create_rrd_pool_total $rrd_cpupool");
        my $ret = create_rrd_pool_total( $rrd_cpupool, "AVERAGE" );
        if ( $ret == 2 ) {
          print "cannot create rrd pool_total api $rrd_cpupool\n";
          next;
        }
      }
    }
    if (!defined $LPA->{$rrd_cpupool_max}{last_update}){
      if ( !-e $rrd_cpupool_max ) {
        print "Creating rrd pool_total max api\nRRD CPUPOOL : $rrd_cpupool_max\n";
        touch("create_rrd_pool_total $rrd_cpupool_max");
        my $ret = create_rrd_pool_total( $rrd_cpupool_max, "MAX" );
        if ( $ret == 2 ) {
          print "cannot create rrd pool_total max api $rrd_cpupool_max\n";
          next;
        }
      }
    }
    RRDp::end;
    RRDp::start "$rrdtool";


    if (!defined $LPA->{$rrd_cpupool}{last_update}){
      RRDp::cmd qq(last "$rrd_cpupool" );
      $last_rec = RRDp::read;
      chomp($$last_rec);
      my $last_update = $$last_rec;
      $LPA->{$rrd_cpupool}{last_update} = $last_update;
    }
    my $prev_sample = {
      'entitled_cycles_c' => 0,
      'uncapped_cycles_c' => 0,
      'capped_cycles_c' => 0,
    };
    foreach my $t ( sort keys %{$lll} ) {
      my $entitled_cycles = "U";
      my $uncapped_cycles = "U";
      my $capped_cycles   = "U";
      my $idle_cycles     = "U";
      $entitled_cycles = $lll->{$t}{entitled_cycles} ? $lll->{$t}{entitled_cycles} : "U";
      $uncapped_cycles = $lll->{$t}{uncapped_cycles} ? $lll->{$t}{uncapped_cycles} : "U";
      $capped_cycles   = $lll->{$t}{capped_cycles}   ? $lll->{$t}{capped_cycles}   : "U";
      $idle_cycles     = $lll->{$t}{idle_cycles}     ? $lll->{$t}{idle_cycles}     : "U";

      if ( $t < $LPA->{$rrd_cpupool}{last_update} ) { next; }

      #print STDERR strftime("%FT%H:%M:%S", localtime(time)) . "        : DEBUG GAPS pool_total update : $rrd_cpupool | $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles\n";
      #print "Rest API       " . strftime("%FT%H:%M:%S", localtime(time)) . "        : pool_total update : $rrd_cpupool $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{capped_cycles}\n";
      $entitled_cycles = Math::BigInt->new($entitled_cycles) if ( defined $entitled_cycles );
      $uncapped_cycles = Math::BigInt->new($uncapped_cycles) if ( defined $uncapped_cycles );
      $capped_cycles   = Math::BigInt->new($capped_cycles)   if ( defined $capped_cycles );
      $idle_cycles     = Math::BigInt->new($idle_cycles)     if ( defined $idle_cycles );
      #zde
      if (!defined $uncapped_cycles || $uncapped_cycles eq '' || $uncapped_cycles eq "U"){
        $uncapped_cycles=0;
      }
      if (defined $prev_sample->{entitled_cycles} && $entitled_cycles > $prev_sample->{entitled_cycles} * 10 && $entitled_cycles > 1000000 && $prev_sample->{entitled_cycles_c} < 10){
        $entitled_cycles = "U";
        $prev_sample->{entitled_cycles_c}++;
      }
      if (defined $prev_sample->{uncapped_cycles} && $uncapped_cycles > $prev_sample->{uncapped_cycles} * 10 && $uncapped_cycles > 1000000 && $prev_sample->{uncapped_cycles_c} < 10){
        $uncapped_cycles = "U";
        $prev_sample->{uncapped_cycles_c}++;
      }
      if (defined $prev_sample->{capped_cycles} && $capped_cycles > $prev_sample->{capped_cycles} * 10 && $capped_cycles > 1000000 && $prev_sample->{capped_cycles_c} < 10){
        $capped_cycles = "U";
        $prev_sample->{capped_cycles_c}++;
      }

      $prev_sample->{entitled_cycles} = $entitled_cycles;
      $prev_sample->{capped_cycles} = $capped_cycles;
      $prev_sample->{uncapped_cycles} = $uncapped_cycles;

      RRDp::cmd qq(update "$rrd_cpupool" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
      RRDp::cmd qq(update "$rrd_cpupool_max" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
    }
  }
  else {    #old, ssh cli
    my $act_sys_cores_ssh = PowerDataWrapper::get_metric_from_config_cfg( "$wrkdir/$managedname/$host/config.cfg", "configurable_sys_proc_units" );
    print "INPUT LPAR     : $input_lpar\n";
    open( FH, "< $input_lpar" ) || main::error( " Can't open $input_lpar : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = reverse <FH>;
    close(FH);
    my $lll;
    foreach $line (@lines) {
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

      if ( $HMC == 1 ) {
        ( $time, $lpar, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation, $idle_cycles ) = split( /,/, $line );
      }
      if ( $IVM == 1 ) {
        ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
      }
      if ( $SDMC == 1 ) {
        ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
      }

      # print "001 $lpar : $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles $capped_cycles, $uncapped_cycles, $idle_cycles\n";
      # $curr_proc_units can be null for dedicated partitions so do not test it here!!!!
      if ( $curr_procs eq '' || $curr_sharing_mode eq '' || $entitled_cycles eq '' || $capped_cycles eq '' || $uncapped_cycles eq '' ) {

        # something wrong with input data, skipping it
        # it migh happen, here is en example : 05/03/2012 22:34:50,1,,,,,,
        next;
      }

      #print "$time $lpar \n";
      # Check whether the first character is a digit, if not then there is something wrong with the
      # input data
      my $ret = substr( $time, 0, 1 );

      #if (($ret =~ /\D/) || ( $lpar eq '' ))  left_curly
      # do not put there $lpar as it might be NULL when the systems is down, seen it for memory
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
        close(FH);
        return 1;
      }

      if ( $HMC == 0 ) {    # IVM translation ids to names
                            # this will have a problem whether a "," is inside lpar name
        foreach my $li (@lpar_trans) {
          chomp($li);
          ( my $id, my $name ) = split( /,/, $li );

          #print "---02 $li -- $id - $lpar_id\n";
          if ( $id == $lpar_id ) {
            $lpar = $name;
            last;
          }
        }
      }

      if ( $lpar =~ m/IOR Collection LP/ ) {    #it is some trash, it exists time to tme, some IBM internal ...
        next;                                   #ignore it
      }
      if ( $lpar eq '' ) {
        next;                                   #again something wrong
      }

      # replace / by &&1, install-html.sh does the reverse thing
      $lpar =~ s/\//\&\&1/g;

      $t = str2time( substr( $time, 0, 19 ) );

      #print "DEBUG Timestamp : $t, $time\n";

      #here???

      $t = correct_to_local_timezone( $t, $hmc_timezone, $local_timezone );

      #sub correct_to_local_timezone{
      #    my $t = shift;
      #    my $hmc_timezone = shift;
      #    my $tz_n = substr($hmc_timezone,1,4);
      #    $tz_n /= 100;
      #    if (substr($hmc_timezone,0,1) eq "+"){
      #      $t = $t + ($tz_n * 3600);
      #    } else { # -
      #      $t = $t - ($tz_n * 3600);
      #    }
      #    return $t;
      #}

      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname :No valid lpar data time format got from HMC : $t : $line : " . __FILE__ . ":" . __LINE__ );
        next;    # next only, could  happen that there appears unix 0 time on the HMC after the upgrade, then just ignore it
      }

      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );

        #print "$t $lpar\n";
        #print "Input data: $lpar\n";
      }
      if ( $lpar =~ m/\"/ ) {

        # LPAR cannot contain double quote, it is an illegal character in the lpar name, report it once and ignore it
        if ( $error_once == 0 ) {
          main::error( "$host:$managedname :LPAR cannot contain double quote, it is an illegal character in the lpar name: $lpar : $line : " . __FILE__ . ":" . __LINE__ );
        }
        $error_once++;
        next;
      }

      $rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";

      #print "RRDNAME = $lpar.rr$type_sam\n";

      #create rrd db if necessary
      # find out if rrd db exist, and place info to the array to do not check its existency every time
      my $rrd_exist_ok  = 0;
      my $rrd_exist_row = 0;
      foreach my $row (@rrd_exist) {
        $rrd_exist_row++;
        if ( $row =~ m/^$lpar$/ ) {
          $rrd_exist_ok = 1;
          last;
        }
      }
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, $SSH, $hmc_user, $wrkdir, $lpar, $t, $keep_virtual );

        my $rrd_vcpu = $rrd;
        $rrd_vcpu =~ s/rrm/rvm/g;

        if ( !-e $rrd_vcpu ) {
          my $ret = create_rrd_vcpu( $rrd_vcpu, "AVERAGE" );
          if ( $ret == 2 ) {
            print "Cannot create rrd_vcpu $rrd_vcpu\n";
          }
        }

        if ( $ret == 1 ) {

          # this lpar has been recently renamed, ignore it then
          next;
        }
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist[$rrd_exist_row] = $lpar;
      }

      # found out last record and save it
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
        $ltime   = $lpar_time[$found];
        $l_count = $found;
      }
      else {
        # find out last record in the db
        # as this makes it slowly to test it each time then it is done
        # once per a lpar for whole load and saved into the array

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
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
        $lpar_idle[$l_count] = 0;
        $ltime               = $$last_rec;
      }

      # when dedicated partitions then there is not set up $curr_proc_units as it is useless
      # I put curr_procs into curr_proc_units to make some gratphs for dedicated lpars
      if ( $curr_sharing_mode =~ m/^share_idle_/ || $curr_sharing_mode =~ m/^keep_idle_/ || length($curr_proc_units) == 0 ) {
        $curr_proc_units = $curr_procs;
        if ( defined($idle_cycles) && !$idle_cycles eq '' && $idle_cycles > 0 ) {

          # CPU lpars have reported idle cycles on new HMC firmwares --> use it for utilization
          $capped_cycles -= $idle_cycles;
          if ( $capped_cycles < 0 ) {

            # capped_cycles can be negative --> CPU dedicated LPARs after LPM might have more idle than capped -->
            # it is a big problem, only the solution is store initial big $idle counter and always use it for decrement of $idle
            # ideal solution would be storing $idle into rrd, but problem with compatability ... :(
            if ( $lpar_idle[$l_count] == 0 ) {
              $lpar_idle[$l_count] = get_lpar_idle_count( $wrkdir, $host, $managedname, $lpar_name[$l_count], $idle_cycles, "get" );
            }
            $capped_cycles = $capped_cycles + $lpar_idle[$l_count];
            if ( $capped_cycles < 0 ) {

              # might appear that it is still negative after several LPM, original saved $idle must be refreshed
              $capped_cycles       = $capped_cycles - $lpar_idle[$l_count];                                                              # return saved one
              $lpar_idle[$l_count] = get_lpar_idle_count( $wrkdir, $host, $managedname, $lpar_name[$l_count], $idle_cycles, "force" );
              $capped_cycles       = $capped_cycles + $lpar_idle[$l_count];
            }
            if ( $capped_cycles < 0 ) {

              # if still < 0 then something works bad, note error and skip it
              if ( $error_count == 0 ) {
                main::error( "counter < 0! :  $rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles - $idle_cycles,$lpar_idle[$l_count], skipping LPAR $lpar_name[$l_count] " . __FILE__ . ":" . __LINE__ );
                $error_count++;
              }
              next;
            }
          }
        }

        # no, no here, shared_syscles* modes containg right $capped_cycles data
        #if ( defined ($shared_cycles_while_active) && ! $shared_cycles_while_active eq '' &&  main::isdigit($shared_cycles_while_active) ) {
        #  $capped_cycles -= $shared_cycles_while_active; # only for LPARs in share_idle_procs_always mode
        #}
        $capped_cycles = $capped_cycles + 0;    #conversion to format understable for rrdtool
      }

      # when CPU dedicated LPARs and modes "share_idle*" then there is already capped shown correctly in data!
      #   --> then do not lower entitlement as this produce wrong numbers then
      # if $curr_proc_units == 0 then lpar is not running and it causing a problem with donated cycles
      #if ($curr_proc_units > 0) {
      #  # exclude POWER5 systems where $shared_cycles_while_active does not exist
      #  # it is for donation of dedicated CPU lpars
      #  if ($curr_sharing_mode =~ "share_idle_procs" || $curr_sharing_mode =~ "share_idle_procs_active" || \
      #      $curr_sharing_mode =~ "share_idle_procs_always" ) {
      #    if ( ! $shared_cycles_while_active eq '' ) {
      #      if ( $entitled_cycles < $shared_cycles_while_active ) {
      #         main::error ("$rrd $t:$entitled_cycles - $shared_cycles_while_active < 0 !!! ".__FILE__.":".__LINE__);
      #         next;
      #      }
      #      # necesary due to Perl behaviour whe it convert it to format X.YZ+eXY
      #      $entitled_cycles= $entitled_cycles - $shared_cycles_while_active;
      #      $entitled_cycles = Math::BigInt->new($entitled_cycles);
      #    }
      #  }
      #}

      if ( $t > $ltime && length($curr_proc_units) > 0 ) {

        #print "$lpar: $time $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles \n";
        if ( data_check( $entitled_cycles, $capped_cycles, $uncapped_cycles, $lpar, $host, $managedname ) == 0 ) {

          my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
          if ( $t > $jump_time ) {

            # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
            # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
            if ( $lpar_jump[$l_count] == 0 ) {
              $lpar_jump[$l_count] = 1;

              #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
              #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
              next;
            }

            # looks like it is ok as it is second timestap in a row
          }
          $lpar_jump[$l_count] = 0;

          # It does not go there even when partition is switched off and counters are 0
          if ( $entitled_cycles < 0 || $uncapped_cycles < 0 || $capped_cycles < 0 ) {
            if ( $error_count == 0 ) {
              main::error( "counter < 0! :  $rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles " . __FILE__ . ":" . __LINE__ );
              $error_count++;
            }
            next;
          }

          # conversion from scientific X.YeYY format to usual decimal format
          #$curr_proc_units = $curr_proc_units + 0;
          #$curr_procs = $curr_procs + 0;
          #$entitled_cycles = $entitled_cycles + 0;
          #$capped_cycles = $capped_cycles + 0;
          #$uncapped_cycles = $uncapped_cycles + 0;
          # It does not work good (always!), use below one instead
          #$curr_proc_units = Math::BigInt->new($curr_proc_units); --> never use it for this, it is integer --> it cut everything behind decimal
          #$curr_procs      = Math::BigInt->new($curr_procs); --> never use it for this, it is integer --> it cut everything behind decimal

          if ( !( main::isdigit($curr_proc_units) ) ) { $curr_proc_units = "U"; }
          if ( !( main::isdigit($curr_procs) ) )      { $curr_procs      = "U"; }
          if ( !( main::isdigit($entitled_cycles) ) ) { $entitled_cycles = "U"; }
          if ( !( main::isdigit($capped_cycles) ) )   { $capped_cycles   = "U"; }
          if ( !( main::isdigit($uncapped_cycles) ) ) { $uncapped_cycles = "U"; }
          print "$lpar PROCS: $curr_procs PROC_UNITS : $curr_proc_units\n"                         if $DEBUG_REST_API;
          print "$lpar counters : $capped_cycles $uncapped_cycles $entitled_cycles $idle_cycles\n" if $DEBUG_REST_API;
          my $powered_on = $uncapped_cycles + $capped_cycles + $entitled_cycles + $idle_cycles;

          #here
          #$lll->{$t}{cores} += $curr_proc_units;
          if ( !$powered_on ) {
            print "skip powered off $lpar\n" if $DEBUG_REST_API;
            next;
          }
          $lll->{$t}{configured_proc_units} = defined $act_sys_cores_ssh ? $act_sys_cores_ssh : "U";
          $lll->{$t}{cores}           += $curr_proc_units;
          $lll->{$t}{entitled_cycles} += $entitled_cycles;
          $lll->{$t}{capped_cycles}   += $capped_cycles;
          $lll->{$t}{idle_cycles}     += $idle_cycles;
          $lll->{$t}{uncapped_cycles} += $uncapped_cycles;

          $entitled_cycles = Math::BigInt->new($entitled_cycles) if ( defined $entitled_cycles );
          $uncapped_cycles = Math::BigInt->new($uncapped_cycles);
          $capped_cycles   = Math::BigInt->new($capped_cycles);

          if ( $keep_virtual == 1 ) {

            # new one, DHL needs to keep virtual processors for accounting
            my $datestring = localtime();
            print "Debug-004a-$rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles\n" if $DEBUG_REST_API;
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          else {
            # old way without storing number of virtual processors
            my $datestring = localtime();
            print "Debug-004b-$rrd $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles (- no curr_procs)\n" if $DEBUG_REST_API;
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          $answer    = RRDp::read;
          $last_time = $time;
          $counter_ins++;
          if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
            main::error(" $host:$managedname : $rrd : $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles : $line : $$answer");
            if ( $$answer =~ m/is not an RRD file/ ) {
              ( my $err, my $file, my $txt ) = split( /'/, $$answer );
              main::error("Removing as it seems to be corrupted: $file");
              unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
            }
          }
          my $rrd_vcpu = $rrd;
          $rrd_vcpu =~ s/rrm/rvm/g;

          if ( !-e $rrd_vcpu ) {
            my $ret = create_rrd_vcpu( $rrd_vcpu, "AVERAGE" );
            if ( $ret == 2 ) {
              print "Cannot create rrd_vcpu $rrd_vcpu\n";
            }
          }
          RRDp::cmd qq(update "$rrd_vcpu" $t:$curr_procs);
          $answer = RRDp::read;

          if ( defined $$answer && $$answer ne '' && $$answer =~ m/ERROR/ ) {
            main::error(" $host:$managedname : $rrd_vcpu : $t:$curr_procs");
            if ( $$answer =~ m/is not an RRD file/ ) {
              ( my $err, my $file, my $txt ) = split( /'/, $$answer );
              main::error("Removing as it seems to be corrupted: $file");
              unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
            }
          }

          # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
          $lpar_time[$l_count] = $t;
        }

        # memory should go through although switched off partition
        # sometimes (? when partition is halted??) it might have still allocated memory although it is off!!!

        #
        #  memory stuff
        #

        if ( !$mem_mode eq '' ) {
          if ( $mem_mode =~ m/shared/ ) {

            # AMS memory stuff only if it is activated
            if ( $curr_mem eq '' || $phys_run_mem eq '' || $curr_io_entitled_mem eq '' || $mapped_io_entitled_mem eq '' || $mem_overage_cooperation eq '' ) {

              #main::error ("$host:$managedname : wrong mem input, shared defined but some value is null : $line");
              #main::error ("$host:$managedname: future timestamp: $rrd");
              #print "$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation\n";
            }
            else {
              #create rrd db if necessary
              # find out if rrd db exist, and place info to the array to do not check its existency every time
              my $rmd_exist_ok  = 0;
              my $rmd_exist_row = 0;
              foreach my $row1 (@rmd_exist) {
                $rmd_exist_row++;
                if ( $row1 =~ m/^$lpar$/ ) {
                  $rmd_exist_ok = 1;
                  last;
                }
              }
              my $rmd = "$wrkdir/$managedname/$host/$lpar.rm$type_sam";
              if ( $rmd_exist_ok == 0 ) {
                $rmd_exist[$rmd_exist_row] = $lpar;
                my $ret = create_lpar_mem( $rmd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
                if ( $ret == 2 ) {
                  return 1;    # RRD creation problem, skip whole load
                }
              }

              # found out last record and save it
              # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
              $l_count_rmd = 0;
              my $found_rmd = -1;
              my $lpar_meta = quotemeta($lpar);
              foreach my $l (@lpar_name_rmd) {
                if ( $l =~ m/^$lpar_meta$/ ) {
                  $found_rmd = $l_count_rmd;
                  last;
                }
                $l_count_rmd++;
              }

              #print "RMD 01: $lpar $found_rmd - $t\n";
              if ( $found_rmd > -1 ) {
                $ltime_rmd   = $lpar_time_rmd[$found_rmd];
                $l_count_rmd = $found_rmd;
              }
              else {
                # find out last record in the db
                # as this makes it slowly to test it each time then it is done
                # once per a lpar for whole load and saved into the array

                # construction against crashing daemon Perl code when RRDTool error appears
                # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
                # construction is not too costly as it runs once per each load
                eval {
                  RRDp::cmd qq(last "$rmd" );
                  $last_rec = RRDp::read;
                };
                if ($@) {
                  rrd_error( $@, $rmd );
                  if ( $rmd_exist[$rmd_exist_row] =~ m/^$lpar$/ ) {
                    $rmd_exist[$rmd_exist_row] = "";
                  }
                  next;
                }
                chomp($$last_rec);
                $lpar_name_rmd[$l_count_rmd] = $lpar;
                $lpar_time_rmd[$l_count_rmd] = $$last_rec;
                $ltime_rmd                   = $$last_rec;

                #print "RMD 01: $lpar $ltime_rmd - $t\n";
              }

              #print "RMD 02: $lpar $ltime_rmd - $t\n";

              if ( $t > $ltime_rmd ) {
                my $datestring = localtime();
                print "Debug-005-$datestring-$rmd $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation\n" if $DEBUG_REST_API;
                if ( !( main::isdigit($curr_mem) ) )                { $curr_mem                = "U"; }
                if ( !( main::isdigit($phys_run_mem) ) )            { $phys_run_mem            = "U"; }
                if ( !( main::isdigit($curr_io_entitled_mem) ) )    { $curr_io_entitled_mem    = "U"; }
                if ( !( main::isdigit($mapped_io_entitled_mem) ) )  { $mapped_io_entitled_mem  = "U"; }
                if ( !( main::isdigit($mem_overage_cooperation) ) ) { $mem_overage_cooperation = "U"; }
                RRDp::cmd qq(update "$rmd" $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation);
                $last_time = $time;

                if ( $counter_ins == 0 ) {
                  $counter_ins++;    # just to force update last.txt
                }
                $answer = RRDp::read;
                if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
                  main::error(" $host:$managedname : $rmd : $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation : $line : $$answer");
                  if ( $$answer =~ m/is not an RRD file/ ) {
                    ( my $err, my $file, my $txt ) = split( /'/, $$answer );
                    main::error("Removing as it seems to be corrupted: $file");
                    unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  }
                }

                # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
                $lpar_time_rmd[$l_count_rmd] = $t;
              }
            }
          }
          else {
            # dedicated mode, just 1 item inside
            if ( $curr_mem eq '' ) {

              #main::error("$host:$managedname : wrong mem input, dedicated mem defined but curr_mem is null : $line");

              #print "$curr_mem\n";
            }
            else {
              #create rrd db if necessary
              # find out if rrd db exist, and place info to the array to do not check its existency every time
              my $rsd_exist_ok  = 0;
              my $rsd_exist_row = 0;
              foreach my $row1 (@rsd_exist) {
                $rsd_exist_row++;
                if ( $row1 =~ m/^$lpar$/ ) {
                  $rsd_exist_ok = 1;
                  last;
                }
              }
              $lpar =~ s/\//\&\&1/g;
              my $rsd = "$wrkdir/$managedname/$host/$lpar.rs$type_sam";
              if ( $rsd_exist_ok == 0 ) {
                $rsd_exist[$rsd_exist_row] = $lpar;
                my $ret = create_lpar_mem_ded( $rsd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
                if ( $ret == 2 ) {
                  return 1;    # RRD creation problem, skip whole load
                }
              }

              # found out last record and save it
              # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
              $l_count_rsd = 0;
              my $found_rsd = -1;
              my $lpar_meta = quotemeta($lpar);
              foreach my $l (@lpar_name_rsd) {
                if ( $l =~ m/^$lpar_meta$/ ) {
                  $found_rsd = $l_count_rsd;

                  #print "RSD 01: $lpar - $found_rsd - $lpar_meta\n";
                  last;
                }
                $l_count_rsd++;
              }

              #print "RSD 01: $lpar $found_rsd - $t\n";
              if ( $found_rsd > -1 ) {
                $ltime_rsd   = $lpar_time_rsd[$found_rsd];
                $l_count_rsd = $found_rsd;

                #print "RSD 02: $lpar $ltime_rsd - $found_rsd\n";
              }
              else {
                # find out last record in the db
                # as this makes it slowly to test it each time then it is done
                # once per a lpar for whole load and saved into the array

                # construction against crashing daemon Perl code when RRDTool error appears
                # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
                # construction is not too costly as it runs once per each load
                eval {
                  RRDp::cmd qq(last "$rsd" );
                  $last_rec = RRDp::read;
                };
                if ($@) {
                  rrd_error( $@, $rsd );
                  if ( $rsd_exist[$rsd_exist_row] =~ m/^$lpar$/ ) {
                    $rsd_exist[$rsd_exist_row] = "";
                  }
                  next;
                }
                chomp($$last_rec);
                $lpar_name_rsd[$l_count_rsd] = $lpar;
                $lpar_time_rsd[$l_count_rsd] = $$last_rec;
                $ltime_rsd                   = $$last_rec;

                #print "RSD 03: $lpar $ltime_rsd - $$last_rec\n";
              }

              #print "RSD 04: $lpar $ltime_rsd - $t\n";

              if ( $t > $ltime_rsd ) {
                my $datestring = localtime();
                print "Debug-006-$datestring-$rsd $t:$curr_mem\n" if $DEBUG_REST_API;
                if ( !( main::isdigit($curr_mem) ) ) { $curr_mem = "U"; }
                RRDp::cmd qq(update "$rsd" $t:$curr_mem);
                if ( $counter_ins == 0 ) {
                  $counter_ins++;    # just to force update last.txt
                }
                $last_time = $time;
                $answer    = RRDp::read;
                if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
                  main::error(" $host:$managedname : $rsd : $t:$curr_mem : $line : $$answer");
                  if ( $$answer =~ m/is not an RRD file/ ) {
                    ( my $err, my $file, my $txt ) = split( /'/, $$answer );
                    main::error("Removing as it seems to be corrupted: $file");
                    unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  }
                }

                # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
                $lpar_time_rsd[$l_count_rsd] = $t;
              }
            }
          }

        }    #memory

      }
    }
             #RRDp::start "$rrdtool";
    if ( !-e $rrd_cpupool ) {
      print "Creating rrd pool_total ssh \nRRD CPUPOOL : $rrd_cpupool\n";
      touch("create_rrd_pool_total $rrd_cpupool");
      my $ret = create_rrd_pool_total( $rrd_cpupool, "AVERAGE" );
      if ( $ret == 2 ) {
        print "cannot create rrd pool_total ssh $rrd_cpupool\n";
        return;
      }
    }
    if ( !-e $rrd_cpupool_max ) {
      print "Creating rrd pool_total max ssh\nRRD CPUPOOL : $rrd_cpupool_max\n";
      touch("create_rrd_pool_total $rrd_cpupool_max");
      my $ret = create_rrd_pool_total( $rrd_cpupool_max, "MAX" );
      if ( $ret == 2 ) {
        print "cannot create rrd pool_total max ssh $rrd_cpupool_max\n";
        return;
      }
    }
    RRDp::cmd qq(last "$rrd_cpupool" );
    my $last_rec = RRDp::read;
    chomp($$last_rec);
    my $last_update = $$last_rec;
    my $capped_last = 0;
    foreach my $t ( sort keys %{$lll} ) {
      if ( $t <= $last_update ) { next; }
      $lll->{$t}{capped_cycles}   = $lll->{$t}{capped_cycles}   ? Math::BigInt->new( $lll->{$t}{capped_cycles} )   : "U";
      $lll->{$t}{entitled_cycles} = $lll->{$t}{entitled_cycles} ? Math::BigInt->new( $lll->{$t}{entitled_cycles} ) : "U";
      $lll->{$t}{uncapped_cycles} = $lll->{$t}{uncapped_cycles} ? Math::BigInt->new( $lll->{$t}{uncapped_cycles} ) : "U";
      $lll->{$t}{idle_cycles}     = $lll->{$t}{idle_cycles}     ? Math::BigInt->new( $lll->{$t}{idle_cycles} )     : "U";

      if (!defined $lll->{$t}{uncapped_cycles} || $lll->{$t}{uncapped_cycles} eq '' || $lll->{$t}{uncapped_cycles} eq "U"){
        $lll->{$t}{uncapped_cycles}=0;
      }
      #check the counter value and skip if the newer counter is wrong (lower than the previous one)
      if ( $capped_last > $lll->{$t}{capped_cycles} ) {

        #skip, the counter cannot be lower than the previous correct one
        main::error("error when updating $rrd_cpupool (and max) - got wrong data from HMC - capped (current):$lll->{$t}{capped_cycles} vs. capped (previous):$capped_last - skip timestamp $t");
        next;
      }

      #counter is ok, continue with update of the rrds
      $capped_last = $lll->{$t}{capped_cycles};

      #print STDERR strftime("%FT%H:%M:%S", localtime(time)) . "        : DEBUG GAPS pool_total ssh update : $rrd_cpupool | $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles}\n";
      RRDp::cmd qq(update "$rrd_cpupool" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles});
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
      RRDp::cmd qq(update "$rrd_cpupool_max" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles});
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
    }
  }    #end else (if json !configured
  if ( $error_count > 1 ) {
    main::error( "error count  : $host:$managedname:lpar $error_count " . __FILE__ . ":" . __LINE__ );
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:lpar $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_old {
  my $LPA;
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $SSH, $hmc_user, $json_configured, $save_files, $model, $serial, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $model) { $model = ""; }
  if (!defined $serial) { $serial = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
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
  my $jump         = 0;

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

  my $input_lpar = "$input-$type_sam";
  if ( $ENV{LPAR_LOAD_EXTERNAL} ) {
    if ( -f $ENV{LPAR_LOAD_EXTERNAL} ) {
      $input_lpar = $ENV{LPAR_LOAD_EXTERNAL};    # keep number of virt processors in RRD --> etc/.magic
    }
  }

  my $line      = "";
  my @rrd_exist = "";
  my @rmd_exist = "";
  my @rsd_exist = "";

  my @lpar_name = "";
  my @lpar_idle = "";
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

  my $rrd_cpupool     = PowerDataWrapper::get_filepath_rrd_cpupool( $managedname, $host, "rrt" );
  my $rrd_cpupool_max = PowerDataWrapper::get_filepath_rrd_cpupool( $managedname, $host, "rxm" );
  if ( defined $json_configured && $json_configured == 1 ) {
    my $perf_string = "lpars_perf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    my $last_known_ts_prev = 0;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.lpars" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.lpars" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.lpars at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    if ( !( -e "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
      if ( open( my $fh_last_ts, ">", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
        print $fh_last_ts "null";
        close($fh_last_ts);
      }
      else {
        main::error( " Cannot open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
    if ( open( my $fh_last_ts, "<", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
      $last_known_ts_prev = readline($fh_last_ts);
      if ( !( main::isdigit($last_known_ts_prev) ) ) {
        $last_known_ts_prev = 0;
      }
      close($fh_last_ts);
    }
    else {
      main::error( " Cannot open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
    }
    my $last_known_timestamp = "";
    my $act_time_upd         = time;
    my $lll;
    my $act_sys_cores_api           = PowerDataWrapper::get_server_metric( $managedname, "ConfigurableSystemProcessorUnits", 0 );
    my $CurrentProcessingUnitsTotal = PowerDataWrapper::get_server_metric( $managedname, "CurrentProcessingUnitsTotal",      0 );
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path    = "$iostatdir$file";
      my $content = [];
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) eq "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        print "no content in $path\n";
        next;
      }
      my $temp_ts;
      my $changed_curr_proc_units;
      foreach my $arr_ts_sample ( @{$content} ) {
        my $t = str2time( $arr_ts_sample->[0] );
        $last_known_timestamp = $t;
        $temp_ts              = $t;
        my $lpar = $arr_ts_sample->[1];

        #if ($lpar =~ m/p770-demo/){ next; }
        if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} ) {
          next;
        }
        my $powered_on = $arr_ts_sample->[3] + $arr_ts_sample->[4] + $arr_ts_sample->[5] + $arr_ts_sample->[6];
        if ( !$powered_on ) {
          next;
        }

        $lll->{$t}{mode}                  = $arr_ts_sample->[7]          ? $arr_ts_sample->[7]          : "U";
        $lll->{$t}{cores}                 = $CurrentProcessingUnitsTotal ? $CurrentProcessingUnitsTotal : "U";
        $lll->{$t}{configured_proc_units} = $act_sys_cores_api           ? $act_sys_cores_api           : "U";
        $lll->{$t}{capped_cycles}         = $lll->{$t}{capped_cycles}    ? $lll->{$t}{capped_cycles}    : 0;

        #        print "LPAR XXX $managedname : $lpar (tot cpu: $lll->{$t}{cores}) : $lll->{$t}{mode} c:$arr_ts_sample->[3] u:$arr_ts_sample->[4] e:$arr_ts_sample->[5] i:$arr_ts_sample->[6]\n";
        $lll->{$t}{capped_cycles} += $arr_ts_sample->[3] if defined $arr_ts_sample->[3];
        if ( $arr_ts_sample->[7] =~ m/share_idle/ || $arr_ts_sample->[7] =~ m/keep_idle/ ) {
          $lll->{$t}{capped_cycles} -= $arr_ts_sample->[6];
        }

        if ( !defined $lll->{$t}{uncapped_cycles} ) { $lll->{$t}{uncapped_cycles} = 0; }
        $lll->{$t}{uncapped_cycles} += $arr_ts_sample->[4] if defined $arr_ts_sample->[4];

        if ( !defined $lll->{$t}{entitled_cycles} ) { $lll->{$t}{entitled_cycles} = 0; }
        $lll->{$t}{entitled_cycles} += $arr_ts_sample->[5] if defined $arr_ts_sample->[5];

        if ( !defined $lll->{$t}{idle_cycles} ) { $lll->{$t}{idle_cycles} = 0; }
        $lll->{$t}{idle_cycles} += $arr_ts_sample->[6] if defined $arr_ts_sample->[6];

        $lpar =~ s/\//\&\&1/g;
        $rrd = PowerDataWrapper::get_filepath_rrd_vm( $lpar, $managedname, "rrm" );
        my $rrd_vcpu = PowerDataWrapper::get_filepath_rrd_vm( $lpar, $managedname, "rvm" );
        my $rsm      = PowerDataWrapper::get_filepath_rrd_vm( $lpar, $managedname, "rsm" );

        #$rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";
        if (!defined $LPA->{$rrd}{last_update}){
          if ( !-e $rrd ) {
            my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, "", "", $wrkdir, $lpar, $t, $keep_virtual );
            if ( $ret == 2 ) {
              next;
            }
          }
        }
        if (!defined $LPA->{$rsm}{last_update}){
          if ( !-e $rsm ) {

            #         my $ret = create_rrd( $rsm, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, "", "", $wrkdir, $lpar, $t, $keep_virtual );
            my $ret = create_lpar_mem_ded( $rsm, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
            if ( $ret == 2 ) {
              next;
            }
          }
        }
        if (!defined $LPA->{$rrd_vcpu}{last_update}){
          if ( !-e $rrd_vcpu ) {
            my $ret = create_rrd_vcpu( $rrd_vcpu, "AVERAGE" );
            if ( $ret == 2 ) {
              print "Cannot create rrd_vcpu $rrd_vcpu\n";
            }
          }
        }
        my $curr_proc_units  = "U";
        my $entitled_cycles  = "U";
        my $capped_cycles    = "U";
        my $uncapped_cycles  = "U";
        my $mode             = "U";
        my $idle_proc_cycles = "U";
        my $memory           = 0;
        my $min_vcpu         = "U";
        my $max_vcpu         = "U";
        my $curr_min_vcpu    = "U";
        my $curr_max_vcpu    = "U";
        my $allocated_vcpu   = "U";
        my $desired_vcpu     = "U";
        $capped_cycles = $arr_ts_sample->[3] if ( defined $arr_ts_sample->[3] );

        #if ( $arr_ts_sample->[7] =~ m/share_idle/ || $arr_ts_sample->[7] =~ m/keep_idle/ ){
        #  $capped_cycles -= $idle_proc_cycles;
        #}

        $uncapped_cycles = $arr_ts_sample->[4] if ( defined $arr_ts_sample->[4] );

        $entitled_cycles = $arr_ts_sample->[5] if ( defined $arr_ts_sample->[5] );

        $idle_proc_cycles = $arr_ts_sample->[6] if ( defined $arr_ts_sample->[6] );

        $mode   = $arr_ts_sample->[7]  if ( defined $arr_ts_sample->[7] );
        $memory = $arr_ts_sample->[13] if ( defined $arr_ts_sample->[13] );

        $curr_proc_units = $arr_ts_sample->[14] if ( defined $arr_ts_sample->[14] );

        $curr_proc_units = $arr_ts_sample->[15] if ( defined $arr_ts_sample->[15] || $curr_proc_units eq "U" );

        $allocated_vcpu = $arr_ts_sample->[18] if ( defined $arr_ts_sample->[18] );

        #$min_vcpu = $arr_ts_sample->[18]    if (defined $arr_ts_sample->[18])  ;
        #$curr_min_vcpu = $arr_ts_sample->[19]    if (defined $arr_ts_sample->[19])  ;
        #$max_vcpu = $arr_ts_sample->[20]    if (defined $arr_ts_sample->[20])  ;
        #$curr_max_vcpu = $arr_ts_sample->[21]    if (defined $arr_ts_sample->[21])  ;
        #$desired_vcpu = $arr_ts_sample->[22]    if (defined $arr_ts_sample->[22])  ;
        if ( $mode =~ m/^share_idle_/ || $mode =~ m/^keep_idle_/ ) {
          $capped_cycles = $capped_cycles - $idle_proc_cycles if ( $capped_cycles >= $idle_proc_cycles );
        }
        if (!defined $LPA->{$rrd}{last_curr_proc_units} || !defined $LPA->{$rrd}{last_update}){
          eval {
            RRDp::cmd qq(last "$rrd" );
            my $last_rec = RRDp::read;
            RRDp::cmd qq(lastupdate "$rrd" );
            my $last_update = RRDp::read;

            ( undef, my $values ) = split( ":", $$last_update );
            my @vals = split( " ", $values );
            my $last_curr_proc_units = $vals[0];

            $LPA->{$rrd}{last_curr_proc_units} = $last_curr_proc_units;
            $LPA->{$rrd}{last_update} = $$last_rec;
          };
          if ($@) {

            #RRDp::error_mode = "catch";
            rrd_error( $@, $rrd );
            next;
          }
        }

        my $last_rec_rsm = 0;

        if (!defined $LPA->{$rsm}{last_update}){
          eval {
            RRDp::cmd qq(last "$rsm" );
            $last_rec_rsm = RRDp::read;
          };
          if ($@) {
            #RRDp::error_mode = "catch";
            rrd_error( $@, $rsm );
            next;
          }
          chomp($$last_rec_rsm);
          my $last_update_rsm = $$last_rec_rsm;

          $LPA->{$rsm}{last_update} = $last_update_rsm;

        }

        if ( $t > $LPA->{$rrd}{last_update} ) {
          $entitled_cycles = Math::BigInt->new($entitled_cycles);
          $capped_cycles   = Math::BigInt->new($capped_cycles);
          $uncapped_cycles = Math::BigInt->new($uncapped_cycles);

          if ( !( main::isdigit($curr_proc_units) ) ) { $curr_proc_units = "U"; }
          if ( !( main::isdigit($entitled_cycles) ) ) { $entitled_cycles = "U"; }
          if ( !( main::isdigit($capped_cycles) ) )   { $capped_cycles   = "U"; }
          if ( !( main::isdigit($uncapped_cycles) ) ) { $uncapped_cycles = "U"; }
          if ( ( main::isdigit($curr_proc_units) && $curr_proc_units < 0 ) || ( main::isdigit($entitled_cycles) && $entitled_cycles < 0 ) || ( main::isdigit($capped_cycles) && $capped_cycles < 0 ) || ( main::isdigit($uncapped_cycles) && $uncapped_cycles < 0 ) ) {
            my $capped_cycles_or = $capped_cycles + $idle_proc_cycles;
            main::error( "$host:$managedname : Not valid counters in lpars $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles \n Original line: $curr_proc_units:$entitled_cycles:$capped_cycles_or:$uncapped_cycles " . __FILE__ . ":" . __LINE__ );
            next;
          }

          #$curr_proc_units = 0.2 if ($lpar eq "Accept");
          if ( defined $curr_proc_units && $curr_proc_units eq "U" ) {
            next;
          }
          if ( $LPA->{$rrd}{last_curr_proc_units} ne "U" && $LPA->{$rrd}{last_curr_proc_units} != $curr_proc_units || ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} == 1 ) ) {
            if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} && $act_time_upd <= $last_known_ts_prev ) {
              next;
            }
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:U:U:U);
            if ( !defined $changed_curr_proc_units->{$lpar} ) { $changed_curr_proc_units->{$lpar} = 0; }

            #$changed_curr_proc_units->{$lpar} = $changed_curr_proc_units->{$lpar} + 1;
            $changed_curr_proc_units->{$lpar} = 1;
          }
          else {
            if ( defined $changed_curr_proc_units->{$lpar} && $changed_curr_proc_units->{$lpar} || ( main::isdigit($act_time_upd) && $act_time_upd <= $last_known_ts_prev ) ) {
              next;
            }
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          eval { $answer = RRDp::read; };
          if ($@) {

            #rrd_error( $@, $rrd );
            next;
          }
          RRDp::cmd qq(update "$rrd_vcpu" $t:$allocated_vcpu);
          eval { $answer = RRDp::read; };
          if ($@) {

            #rrd_error( $@, $rrd );
            next;
          }
          $LPA->{$rrd_vcpu}{last_update} = $t;
        }
        if ( $t > $LPA->{$rsm}{last_update} ) {

          #          $memory = Math::BigInt->new($memory);
          RRDp::cmd qq(update "$rsm" $t:$memory);
          eval { $answer = RRDp::read; };
          if ($@) {

            #rrd_error( $@, $rrd );
            next;
          }
          $LPA->{$rsm}{last_update} = $t;
        }
      }
      ##unlink ($path) || print("Cannot delete file $path ". __FILE__. ":". __LINE__);
      if ( defined $file && defined $files[-1] && defined $files[-2] ) {
        if ( $file eq $files[-1] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/lpars_perf1" );
        }
        if ( $file eq $files[-2] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/lpars_perf2" );
        }
      }
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      if ( open( $ltiph, ">", "$wrkdir/$managedname/$host/iostat/last_ts.lpars" ) ) {
        print $ltiph "$temp_ts";
        close($ltiph);
      }
      else {
        main::error( " Can't open $wrkdir/$managedname/$host/iostat/last_ts.lpars : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
    if ( open( my $fh, ">", "$wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt" ) ) {
      print $fh "$last_known_timestamp\n";
      close($fh);
    }
    else {
      main::error( " Can't open $wrkdir/../tmp/last_known_ts\_$managedname\_$host.txt : $!" . __FILE__ . ":" . __LINE__ );
    }

    #my $rrd_cpupool = PowerDataWrapper::get_filepath_rrd("CPUPOOL", "rrm");
    if (!defined $LPA->{$rrd_cpupool}{last_update}){
      if ( !-e $rrd_cpupool ) {
        print "Creating rrd pool_total api \nRRD CPUPOOL : $rrd_cpupool\n";
        touch("create_rrd_pool_total $rrd_cpupool");
        my $ret = create_rrd_pool_total( $rrd_cpupool, "AVERAGE" );
        if ( $ret == 2 ) {
          print "cannot create rrd pool_total api $rrd_cpupool\n";
          next;
        }
      }
    }
    if (!defined $LPA->{$rrd_cpupool_max}{last_update}){
      if ( !-e $rrd_cpupool_max ) {
        print "Creating rrd pool_total max api\nRRD CPUPOOL : $rrd_cpupool_max\n";
        touch("create_rrd_pool_total $rrd_cpupool_max");
        my $ret = create_rrd_pool_total( $rrd_cpupool_max, "MAX" );
        if ( $ret == 2 ) {
          print "cannot create rrd pool_total max api $rrd_cpupool_max\n";
          next;
        }
      }
    }
    RRDp::end;
    RRDp::start "$rrdtool";


    if (!defined $LPA->{$rrd_cpupool}{last_update}){
      RRDp::cmd qq(last "$rrd_cpupool" );
      $last_rec = RRDp::read;
      chomp($$last_rec);
      my $last_update = $$last_rec;
      $LPA->{$rrd_cpupool}{last_update} = $last_update;
    }
    my $prev_sample = {
      'entitled_cycles_c' => 0,
      'uncapped_cycles_c' => 0,
      'capped_cycles_c' => 0,
    };
    foreach my $t ( sort keys %{$lll} ) {
      my $entitled_cycles = 0;
      my $uncapped_cycles = 0;
      my $capped_cycles   = 0;
      my $idle_cycles     = 0;
      $entitled_cycles = $lll->{$t}{entitled_cycles} ? $lll->{$t}{entitled_cycles} : 0;
      $uncapped_cycles = $lll->{$t}{uncapped_cycles} ? $lll->{$t}{uncapped_cycles} : 0;
      $capped_cycles   = $lll->{$t}{capped_cycles}   ? $lll->{$t}{capped_cycles}   : 0;
      $idle_cycles     = $lll->{$t}{idle_cycles}     ? $lll->{$t}{idle_cycles}     : 0;

      if ( $t < $LPA->{$rrd_cpupool}{last_update} ) { next; }

      #print STDERR strftime("%FT%H:%M:%S", localtime(time)) . "        : DEBUG GAPS pool_total update : $rrd_cpupool | $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles\n";
      #print "Rest API       " . strftime("%FT%H:%M:%S", localtime(time)) . "        : pool_total update : $rrd_cpupool $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{capped_cycles}\n";
      $entitled_cycles = Math::BigInt->new($entitled_cycles) if ( defined $entitled_cycles );
      $uncapped_cycles = Math::BigInt->new($uncapped_cycles) if ( defined $uncapped_cycles );
      $capped_cycles   = Math::BigInt->new($capped_cycles)   if ( defined $capped_cycles );
      $idle_cycles     = Math::BigInt->new($idle_cycles)     if ( defined $idle_cycles );
      #zde
      if (!defined $uncapped_cycles || $uncapped_cycles eq '' || $uncapped_cycles eq "U"){
        $uncapped_cycles=0;
      }
      if (defined $prev_sample->{entitled_cycles} && $entitled_cycles > $prev_sample->{entitled_cycles} * 10 && $entitled_cycles > 1000000 && $prev_sample->{entitled_cycles_c} < 10){
        $entitled_cycles = "U";
        $prev_sample->{entitled_cycles_c}++;
      }
      if (defined $prev_sample->{uncapped_cycles} && $uncapped_cycles > $prev_sample->{uncapped_cycles} * 10 && $uncapped_cycles > 1000000 && $prev_sample->{uncapped_cycles_c} < 10){
        $uncapped_cycles = "U";
        $prev_sample->{uncapped_cycles_c}++;
      }
      if (defined $prev_sample->{capped_cycles} && $capped_cycles > $prev_sample->{capped_cycles} * 10 && $capped_cycles > 1000000 && $prev_sample->{capped_cycles_c} < 10){
        $capped_cycles = "U";
        $prev_sample->{capped_cycles_c}++;
      }

      $prev_sample->{entitled_cycles} = $entitled_cycles;
      $prev_sample->{capped_cycles} = $capped_cycles;
      $prev_sample->{uncapped_cycles} = $uncapped_cycles;

      RRDp::cmd qq(update "$rrd_cpupool" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
      RRDp::cmd qq(update "$rrd_cpupool_max" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$entitled_cycles:$capped_cycles:$uncapped_cycles);
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
    }
  }
  else {    #old, ssh cli
    my $act_sys_cores_ssh = PowerDataWrapper::get_metric_from_config_cfg( "$wrkdir/$managedname/$host/config.cfg", "configurable_sys_proc_units" );
    print "INPUT LPAR     : $input_lpar\n";
    open( FH, "< $input_lpar" ) || main::error( " Can't open $input_lpar : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = reverse <FH>;
    close(FH);
    my $lll;
    foreach $line (@lines) {
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

      if ( $HMC == 1 ) {
        ( $time, $lpar, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation, $idle_cycles ) = split( /,/, $line );
      }
      if ( $IVM == 1 ) {
        ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
      }
      if ( $SDMC == 1 ) {
        ( $time, $lpar_id, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $mem_mode, $curr_mem, $phys_run_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation ) = split( /,/, $line );
      }

      # print "001 $lpar : $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles $capped_cycles, $uncapped_cycles, $idle_cycles\n";
      # $curr_proc_units can be null for dedicated partitions so do not test it here!!!!
      if ( $curr_procs eq '' || $curr_sharing_mode eq '' || $entitled_cycles eq '' || $capped_cycles eq '' || $uncapped_cycles eq '' ) {

        # something wrong with input data, skipping it
        # it migh happen, here is en example : 05/03/2012 22:34:50,1,,,,,,
        next;
      }

      #print "$time $lpar \n";
      # Check whether the first character is a digit, if not then there is something wrong with the
      # input data
      my $ret = substr( $time, 0, 1 );

      #if (($ret =~ /\D/) || ( $lpar eq '' ))  left_curly
      # do not put there $lpar as it might be NULL when the systems is down, seen it for memory
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
        close(FH);
        return 1;
      }

      if ( $HMC == 0 ) {    # IVM translation ids to names
                            # this will have a problem whether a "," is inside lpar name
        foreach my $li (@lpar_trans) {
          chomp($li);
          ( my $id, my $name ) = split( /,/, $li );

          #print "---02 $li -- $id - $lpar_id\n";
          if ( $id == $lpar_id ) {
            $lpar = $name;
            last;
          }
        }
      }

      if ( $lpar =~ m/IOR Collection LP/ ) {    #it is some trash, it exists time to tme, some IBM internal ...
        next;                                   #ignore it
      }
      if ( $lpar eq '' ) {
        next;                                   #again something wrong
      }

      # replace / by &&1, install-html.sh does the reverse thing
      $lpar =~ s/\//\&\&1/g;

      $t = str2time( substr( $time, 0, 19 ) );

      #print "DEBUG Timestamp : $t, $time\n";

      #here???

      $t = correct_to_local_timezone( $t, $hmc_timezone, $local_timezone );

      #sub correct_to_local_timezone{
      #    my $t = shift;
      #    my $hmc_timezone = shift;
      #    my $tz_n = substr($hmc_timezone,1,4);
      #    $tz_n /= 100;
      #    if (substr($hmc_timezone,0,1) eq "+"){
      #      $t = $t + ($tz_n * 3600);
      #    } else { # -
      #      $t = $t - ($tz_n * 3600);
      #    }
      #    return $t;
      #}

      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname :No valid lpar data time format got from HMC : $t : $line : " . __FILE__ . ":" . __LINE__ );
        next;    # next only, could  happen that there appears unix 0 time on the HMC after the upgrade, then just ignore it
      }

      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );

        #print "$t $lpar\n";
        #print "Input data: $lpar\n";
      }
      if ( $lpar =~ m/\"/ ) {

        # LPAR cannot contain double quote, it is an illegal character in the lpar name, report it once and ignore it
        if ( $error_once == 0 ) {
          main::error( "$host:$managedname :LPAR cannot contain double quote, it is an illegal character in the lpar name: $lpar : $line : " . __FILE__ . ":" . __LINE__ );
        }
        $error_once++;
        next;
      }

      $rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";

      #print "RRDNAME = $lpar.rr$type_sam\n";

      #create rrd db if necessary
      # find out if rrd db exist, and place info to the array to do not check its existency every time
      my $rrd_exist_ok  = 0;
      my $rrd_exist_row = 0;
      foreach my $row (@rrd_exist) {
        $rrd_exist_row++;
        if ( $row =~ m/^$lpar$/ ) {
          $rrd_exist_ok = 1;
          last;
        }
      }
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, $SSH, $hmc_user, $wrkdir, $lpar, $t, $keep_virtual );

        my $rrd_vcpu = $rrd;
        $rrd_vcpu =~ s/rrm/rvm/g;

        if ( !-e $rrd_vcpu ) {
          my $ret = create_rrd_vcpu( $rrd_vcpu, "AVERAGE" );
          if ( $ret == 2 ) {
            print "Cannot create rrd_vcpu $rrd_vcpu\n";
          }
        }

        if ( $ret == 1 ) {

          # this lpar has been recently renamed, ignore it then
          next;
        }
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist[$rrd_exist_row] = $lpar;
      }

      # found out last record and save it
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
        $ltime   = $lpar_time[$found];
        $l_count = $found;
      }
      else {
        # find out last record in the db
        # as this makes it slowly to test it each time then it is done
        # once per a lpar for whole load and saved into the array

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
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
        $lpar_idle[$l_count] = 0;
        $ltime               = $$last_rec;
      }

      # when dedicated partitions then there is not set up $curr_proc_units as it is useless
      # I put curr_procs into curr_proc_units to make some gratphs for dedicated lpars
      if ( $curr_sharing_mode =~ m/^share_idle_/ || $curr_sharing_mode =~ m/^keep_idle_/ || length($curr_proc_units) == 0 ) {
        $curr_proc_units = $curr_procs;
        if ( defined($idle_cycles) && !$idle_cycles eq '' && $idle_cycles > 0 ) {

          # CPU lpars have reported idle cycles on new HMC firmwares --> use it for utilization
          $capped_cycles -= $idle_cycles;
          if ( $capped_cycles < 0 ) {

            # capped_cycles can be negative --> CPU dedicated LPARs after LPM might have more idle than capped -->
            # it is a big problem, only the solution is store initial big $idle counter and always use it for decrement of $idle
            # ideal solution would be storing $idle into rrd, but problem with compatability ... :(
            if ( $lpar_idle[$l_count] == 0 ) {
              $lpar_idle[$l_count] = get_lpar_idle_count( $wrkdir, $host, $managedname, $lpar_name[$l_count], $idle_cycles, "get" );
            }
            $capped_cycles = $capped_cycles + $lpar_idle[$l_count];
            if ( $capped_cycles < 0 ) {

              # might appear that it is still negative after several LPM, original saved $idle must be refreshed
              $capped_cycles       = $capped_cycles - $lpar_idle[$l_count];                                                              # return saved one
              $lpar_idle[$l_count] = get_lpar_idle_count( $wrkdir, $host, $managedname, $lpar_name[$l_count], $idle_cycles, "force" );
              $capped_cycles       = $capped_cycles + $lpar_idle[$l_count];
            }
            if ( $capped_cycles < 0 ) {

              # if still < 0 then something works bad, note error and skip it
              if ( $error_count == 0 ) {
                main::error( "counter < 0! :  $rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles - $idle_cycles,$lpar_idle[$l_count], skipping LPAR $lpar_name[$l_count] " . __FILE__ . ":" . __LINE__ );
                $error_count++;
              }
              next;
            }
          }
        }

        # no, no here, shared_syscles* modes containg right $capped_cycles data
        #if ( defined ($shared_cycles_while_active) && ! $shared_cycles_while_active eq '' &&  main::isdigit($shared_cycles_while_active) ) {
        #  $capped_cycles -= $shared_cycles_while_active; # only for LPARs in share_idle_procs_always mode
        #}
        $capped_cycles = $capped_cycles + 0;    #conversion to format understable for rrdtool
      }

      # when CPU dedicated LPARs and modes "share_idle*" then there is already capped shown correctly in data!
      #   --> then do not lower entitlement as this produce wrong numbers then
      # if $curr_proc_units == 0 then lpar is not running and it causing a problem with donated cycles
      #if ($curr_proc_units > 0) {
      #  # exclude POWER5 systems where $shared_cycles_while_active does not exist
      #  # it is for donation of dedicated CPU lpars
      #  if ($curr_sharing_mode =~ "share_idle_procs" || $curr_sharing_mode =~ "share_idle_procs_active" || \
      #      $curr_sharing_mode =~ "share_idle_procs_always" ) {
      #    if ( ! $shared_cycles_while_active eq '' ) {
      #      if ( $entitled_cycles < $shared_cycles_while_active ) {
      #         main::error ("$rrd $t:$entitled_cycles - $shared_cycles_while_active < 0 !!! ".__FILE__.":".__LINE__);
      #         next;
      #      }
      #      # necesary due to Perl behaviour whe it convert it to format X.YZ+eXY
      #      $entitled_cycles= $entitled_cycles - $shared_cycles_while_active;
      #      $entitled_cycles = Math::BigInt->new($entitled_cycles);
      #    }
      #  }
      #}

      if ( $t > $ltime && length($curr_proc_units) > 0 ) {

        #print "$lpar: $time $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles \n";
        if ( data_check( $entitled_cycles, $capped_cycles, $uncapped_cycles, $lpar, $host, $managedname ) == 0 ) {

          my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
          if ( $t > $jump_time ) {

            # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
            # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
            if ( $lpar_jump[$l_count] == 0 ) {
              $lpar_jump[$l_count] = 1;

              #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
              #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
              next;
            }

            # looks like it is ok as it is second timestap in a row
          }
          $lpar_jump[$l_count] = 0;

          # It does not go there even when partition is switched off and counters are 0
          if ( $entitled_cycles < 0 || $uncapped_cycles < 0 || $capped_cycles < 0 ) {
            if ( $error_count == 0 ) {
              main::error( "counter < 0! :  $rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles " . __FILE__ . ":" . __LINE__ );
              $error_count++;
            }
            next;
          }

          # conversion from scientific X.YeYY format to usual decimal format
          #$curr_proc_units = $curr_proc_units + 0;
          #$curr_procs = $curr_procs + 0;
          #$entitled_cycles = $entitled_cycles + 0;
          #$capped_cycles = $capped_cycles + 0;
          #$uncapped_cycles = $uncapped_cycles + 0;
          # It does not work good (always!), use below one instead
          #$curr_proc_units = Math::BigInt->new($curr_proc_units); --> never use it for this, it is integer --> it cut everything behind decimal
          #$curr_procs      = Math::BigInt->new($curr_procs); --> never use it for this, it is integer --> it cut everything behind decimal

          if ( !( main::isdigit($curr_proc_units) ) ) { $curr_proc_units = "U"; }
          if ( !( main::isdigit($curr_procs) ) )      { $curr_procs      = "U"; }
          if ( !( main::isdigit($entitled_cycles) ) ) { $entitled_cycles = "U"; }
          if ( !( main::isdigit($capped_cycles) ) )   { $capped_cycles   = "U"; }
          if ( !( main::isdigit($uncapped_cycles) ) ) { $uncapped_cycles = "U"; }
          print "$lpar PROCS: $curr_procs PROC_UNITS : $curr_proc_units\n"                         if $DEBUG_REST_API;
          print "$lpar counters : $capped_cycles $uncapped_cycles $entitled_cycles $idle_cycles\n" if $DEBUG_REST_API;
          my $powered_on = $uncapped_cycles + $capped_cycles + $entitled_cycles + $idle_cycles;

          #here
          #$lll->{$t}{cores} += $curr_proc_units;
          if ( !$powered_on ) {
            print "skip powered off $lpar\n" if $DEBUG_REST_API;
            next;
          }
          $lll->{$t}{configured_proc_units} = defined $act_sys_cores_ssh ? $act_sys_cores_ssh : "U";
          $lll->{$t}{cores}           += $curr_proc_units;
          $lll->{$t}{entitled_cycles} += $entitled_cycles;
          $lll->{$t}{capped_cycles}   += $capped_cycles;
          $lll->{$t}{idle_cycles}     += $idle_cycles;
          $lll->{$t}{uncapped_cycles} += $uncapped_cycles;

          $entitled_cycles = Math::BigInt->new($entitled_cycles) if ( defined $entitled_cycles );
          $uncapped_cycles = Math::BigInt->new($uncapped_cycles);
          $capped_cycles   = Math::BigInt->new($capped_cycles);

          if ( $keep_virtual == 1 ) {

            # new one, DHL needs to keep virtual processors for accounting
            my $datestring = localtime();
            print "Debug-004a-$rrd $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles\n" if $DEBUG_REST_API;
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$curr_procs:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          else {
            # old way without storing number of virtual processors
            my $datestring = localtime();
            print "Debug-004b-$rrd $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles (- no curr_procs)\n" if $DEBUG_REST_API;
            RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles);
          }
          $answer    = RRDp::read;
          $last_time = $time;
          $counter_ins++;
          if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
            main::error(" $host:$managedname : $rrd : $t:$curr_proc_units:$entitled_cycles:$capped_cycles:$uncapped_cycles : $line : $$answer");
            if ( $$answer =~ m/is not an RRD file/ ) {
              ( my $err, my $file, my $txt ) = split( /'/, $$answer );
              main::error("Removing as it seems to be corrupted: $file");
              unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
            }
          }
          my $rrd_vcpu = $rrd;
          $rrd_vcpu =~ s/rrm/rvm/g;

          if ( !-e $rrd_vcpu ) {
            my $ret = create_rrd_vcpu( $rrd_vcpu, "AVERAGE" );
            if ( $ret == 2 ) {
              print "Cannot create rrd_vcpu $rrd_vcpu\n";
            }
          }
          RRDp::cmd qq(update "$rrd_vcpu" $t:$curr_procs);
          $answer = RRDp::read;

          if ( defined $$answer && $$answer ne '' && $$answer =~ m/ERROR/ ) {
            main::error(" $host:$managedname : $rrd_vcpu : $t:$curr_procs");
            if ( $$answer =~ m/is not an RRD file/ ) {
              ( my $err, my $file, my $txt ) = split( /'/, $$answer );
              main::error("Removing as it seems to be corrupted: $file");
              unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
            }
          }

          # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
          $lpar_time[$l_count] = $t;
        }

        # memory should go through although switched off partition
        # sometimes (? when partition is halted??) it might have still allocated memory although it is off!!!

        #
        #  memory stuff
        #

        if ( !$mem_mode eq '' ) {
          if ( $mem_mode =~ m/shared/ ) {

            # AMS memory stuff only if it is activated
            if ( $curr_mem eq '' || $phys_run_mem eq '' || $curr_io_entitled_mem eq '' || $mapped_io_entitled_mem eq '' || $mem_overage_cooperation eq '' ) {

              #main::error ("$host:$managedname : wrong mem input, shared defined but some value is null : $line");
              #main::error ("$host:$managedname: future timestamp: $rrd");
              #print "$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation\n";
            }
            else {
              #create rrd db if necessary
              # find out if rrd db exist, and place info to the array to do not check its existency every time
              my $rmd_exist_ok  = 0;
              my $rmd_exist_row = 0;
              foreach my $row1 (@rmd_exist) {
                $rmd_exist_row++;
                if ( $row1 =~ m/^$lpar$/ ) {
                  $rmd_exist_ok = 1;
                  last;
                }
              }
              my $rmd = "$wrkdir/$managedname/$host/$lpar.rm$type_sam";
              if ( $rmd_exist_ok == 0 ) {
                $rmd_exist[$rmd_exist_row] = $lpar;
                my $ret = create_lpar_mem( $rmd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
                if ( $ret == 2 ) {
                  return 1;    # RRD creation problem, skip whole load
                }
              }

              # found out last record and save it
              # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
              $l_count_rmd = 0;
              my $found_rmd = -1;
              my $lpar_meta = quotemeta($lpar);
              foreach my $l (@lpar_name_rmd) {
                if ( $l =~ m/^$lpar_meta$/ ) {
                  $found_rmd = $l_count_rmd;
                  last;
                }
                $l_count_rmd++;
              }

              #print "RMD 01: $lpar $found_rmd - $t\n";
              if ( $found_rmd > -1 ) {
                $ltime_rmd   = $lpar_time_rmd[$found_rmd];
                $l_count_rmd = $found_rmd;
              }
              else {
                # find out last record in the db
                # as this makes it slowly to test it each time then it is done
                # once per a lpar for whole load and saved into the array

                # construction against crashing daemon Perl code when RRDTool error appears
                # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
                # construction is not too costly as it runs once per each load
                eval {
                  RRDp::cmd qq(last "$rmd" );
                  $last_rec = RRDp::read;
                };
                if ($@) {
                  rrd_error( $@, $rmd );
                  if ( $rmd_exist[$rmd_exist_row] =~ m/^$lpar$/ ) {
                    $rmd_exist[$rmd_exist_row] = "";
                  }
                  next;
                }
                chomp($$last_rec);
                $lpar_name_rmd[$l_count_rmd] = $lpar;
                $lpar_time_rmd[$l_count_rmd] = $$last_rec;
                $ltime_rmd                   = $$last_rec;

                #print "RMD 01: $lpar $ltime_rmd - $t\n";
              }

              #print "RMD 02: $lpar $ltime_rmd - $t\n";

              if ( $t > $ltime_rmd ) {
                my $datestring = localtime();
                print "Debug-005-$datestring-$rmd $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation\n" if $DEBUG_REST_API;
                if ( !( main::isdigit($curr_mem) ) )                { $curr_mem                = "U"; }
                if ( !( main::isdigit($phys_run_mem) ) )            { $phys_run_mem            = "U"; }
                if ( !( main::isdigit($curr_io_entitled_mem) ) )    { $curr_io_entitled_mem    = "U"; }
                if ( !( main::isdigit($mapped_io_entitled_mem) ) )  { $mapped_io_entitled_mem  = "U"; }
                if ( !( main::isdigit($mem_overage_cooperation) ) ) { $mem_overage_cooperation = "U"; }
                RRDp::cmd qq(update "$rmd" $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation);
                $last_time = $time;

                if ( $counter_ins == 0 ) {
                  $counter_ins++;    # just to force update last.txt
                }
                $answer = RRDp::read;
                if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
                  main::error(" $host:$managedname : $rmd : $t:$curr_mem:$phys_run_mem:$curr_io_entitled_mem:$mapped_io_entitled_mem:$mem_overage_cooperation : $line : $$answer");
                  if ( $$answer =~ m/is not an RRD file/ ) {
                    ( my $err, my $file, my $txt ) = split( /'/, $$answer );
                    main::error("Removing as it seems to be corrupted: $file");
                    unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  }
                }

                # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
                $lpar_time_rmd[$l_count_rmd] = $t;
              }
            }
          }
          else {
            # dedicated mode, just 1 item inside
            if ( $curr_mem eq '' ) {

              #main::error("$host:$managedname : wrong mem input, dedicated mem defined but curr_mem is null : $line");

              #print "$curr_mem\n";
            }
            else {
              #create rrd db if necessary
              # find out if rrd db exist, and place info to the array to do not check its existency every time
              my $rsd_exist_ok  = 0;
              my $rsd_exist_row = 0;
              foreach my $row1 (@rsd_exist) {
                $rsd_exist_row++;
                if ( $row1 =~ m/^$lpar$/ ) {
                  $rsd_exist_ok = 1;
                  last;
                }
              }
              $lpar =~ s/\//\&\&1/g;
              my $rsd = "$wrkdir/$managedname/$host/$lpar.rs$type_sam";
              if ( $rsd_exist_ok == 0 ) {
                $rsd_exist[$rsd_exist_row] = $lpar;
                my $ret = create_lpar_mem_ded( $rsd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
                if ( $ret == 2 ) {
                  return 1;    # RRD creation problem, skip whole load
                }
              }

              # found out last record and save it
              # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
              $l_count_rsd = 0;
              my $found_rsd = -1;
              my $lpar_meta = quotemeta($lpar);
              foreach my $l (@lpar_name_rsd) {
                if ( $l =~ m/^$lpar_meta$/ ) {
                  $found_rsd = $l_count_rsd;

                  #print "RSD 01: $lpar - $found_rsd - $lpar_meta\n";
                  last;
                }
                $l_count_rsd++;
              }

              #print "RSD 01: $lpar $found_rsd - $t\n";
              if ( $found_rsd > -1 ) {
                $ltime_rsd   = $lpar_time_rsd[$found_rsd];
                $l_count_rsd = $found_rsd;

                #print "RSD 02: $lpar $ltime_rsd - $found_rsd\n";
              }
              else {
                # find out last record in the db
                # as this makes it slowly to test it each time then it is done
                # once per a lpar for whole load and saved into the array

                # construction against crashing daemon Perl code when RRDTool error appears
                # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
                # construction is not too costly as it runs once per each load
                eval {
                  RRDp::cmd qq(last "$rsd" );
                  $last_rec = RRDp::read;
                };
                if ($@) {
                  rrd_error( $@, $rsd );
                  if ( $rsd_exist[$rsd_exist_row] =~ m/^$lpar$/ ) {
                    $rsd_exist[$rsd_exist_row] = "";
                  }
                  next;
                }
                chomp($$last_rec);
                $lpar_name_rsd[$l_count_rsd] = $lpar;
                $lpar_time_rsd[$l_count_rsd] = $$last_rec;
                $ltime_rsd                   = $$last_rec;

                #print "RSD 03: $lpar $ltime_rsd - $$last_rec\n";
              }

              #print "RSD 04: $lpar $ltime_rsd - $t\n";

              if ( $t > $ltime_rsd ) {
                my $datestring = localtime();
                print "Debug-006-$datestring-$rsd $t:$curr_mem\n" if $DEBUG_REST_API;
                if ( !( main::isdigit($curr_mem) ) ) { $curr_mem = "U"; }
                RRDp::cmd qq(update "$rsd" $t:$curr_mem);
                if ( $counter_ins == 0 ) {
                  $counter_ins++;    # just to force update last.txt
                }
                $last_time = $time;
                $answer    = RRDp::read;
                if ( !$$answer eq '' && $$answer =~ m/ERROR/ ) {
                  main::error(" $host:$managedname : $rsd : $t:$curr_mem : $line : $$answer");
                  if ( $$answer =~ m/is not an RRD file/ ) {
                    ( my $err, my $file, my $txt ) = split( /'/, $$answer );
                    main::error("Removing as it seems to be corrupted: $file");
                    unlink("$file") || main::error( "Cannot rm $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
                  }
                }

                # to avoid a bug on HMC when it sometimes reports twice same value (for the same timestamp)
                $lpar_time_rsd[$l_count_rsd] = $t;
              }
            }
          }

        }    #memory

      }
    }
             #RRDp::start "$rrdtool";
    if ( !-e $rrd_cpupool ) {
      print "Creating rrd pool_total ssh \nRRD CPUPOOL : $rrd_cpupool\n";
      touch("create_rrd_pool_total $rrd_cpupool");
      my $ret = create_rrd_pool_total( $rrd_cpupool, "AVERAGE" );
      if ( $ret == 2 ) {
        print "cannot create rrd pool_total ssh $rrd_cpupool\n";
        return;
      }
    }
    if ( !-e $rrd_cpupool_max ) {
      print "Creating rrd pool_total max ssh\nRRD CPUPOOL : $rrd_cpupool_max\n";
      touch("create_rrd_pool_total $rrd_cpupool_max");
      my $ret = create_rrd_pool_total( $rrd_cpupool_max, "MAX" );
      if ( $ret == 2 ) {
        print "cannot create rrd pool_total max ssh $rrd_cpupool_max\n";
        return;
      }
    }
    RRDp::cmd qq(last "$rrd_cpupool" );
    my $last_rec = RRDp::read;
    chomp($$last_rec);
    my $last_update = $$last_rec;
    my $capped_last = 0;
    foreach my $t ( sort keys %{$lll} ) {
      if ( $t <= $last_update ) { next; }
      $lll->{$t}{capped_cycles}   = $lll->{$t}{capped_cycles}   ? Math::BigInt->new( $lll->{$t}{capped_cycles} )   : "U";
      $lll->{$t}{entitled_cycles} = $lll->{$t}{entitled_cycles} ? Math::BigInt->new( $lll->{$t}{entitled_cycles} ) : "U";
      $lll->{$t}{uncapped_cycles} = $lll->{$t}{uncapped_cycles} ? Math::BigInt->new( $lll->{$t}{uncapped_cycles} ) : "U";
      $lll->{$t}{idle_cycles}     = $lll->{$t}{idle_cycles}     ? Math::BigInt->new( $lll->{$t}{idle_cycles} )     : "U";

      if (!defined $lll->{$t}{uncapped_cycles} || $lll->{$t}{uncapped_cycles} eq '' || $lll->{$t}{uncapped_cycles} eq "U"){
        $lll->{$t}{uncapped_cycles}=0;
      }
      #check the counter value and skip if the newer counter is wrong (lower than the previous one)
      if ( $capped_last > $lll->{$t}{capped_cycles} ) {

        #skip, the counter cannot be lower than the previous correct one
        main::error("error when updating $rrd_cpupool (and max) - got wrong data from HMC - capped (current):$lll->{$t}{capped_cycles} vs. capped (previous):$capped_last - skip timestamp $t");
        next;
      }

      #counter is ok, continue with update of the rrds
      $capped_last = $lll->{$t}{capped_cycles};

      #print STDERR strftime("%FT%H:%M:%S", localtime(time)) . "        : DEBUG GAPS pool_total ssh update : $rrd_cpupool | $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles}\n";
      RRDp::cmd qq(update "$rrd_cpupool" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles});
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
      RRDp::cmd qq(update "$rrd_cpupool_max" $t:$lll->{$t}{configured_proc_units}:$lll->{$t}{cores}:$lll->{$t}{entitled_cycles}:$lll->{$t}{capped_cycles}:$lll->{$t}{uncapped_cycles});
      eval { $answer = RRDp::read; };
      if ($@) {
        rrd_error( $@, $rrd );
        next;
      }
    }
  }    #end else (if json !configured
  if ( $error_count > 1 ) {
    main::error( "error count  : $host:$managedname:lpar $error_count " . __FILE__ . ":" . __LINE__ );
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:lpar $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_pool_mem {
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_pool, $no_time, $json_configured, $save_files, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
  my @lpar_trans   = @{$trans_tmp};
  my $counter      = 0;
  my $counter_tot  = 0;
  my $counter_ins  = 0;
  my $rrd          = "";
  my $ltime        = 0;
  my $time         = "";
  my $rrd_exist_ok = 0;
  my $jump         = 0;
  my $last_time    = "";

  if ( $step > 60 ) {
    $JUMP_DETECT = 10800;    # 3 hours
  }
  if ( $type_sam =~ m/d/ ) {
    $JUMP_DETECT = 178000    # 2 days + for daily graphs/feed
  }

  if ( !-f "$input_pool-$type_sam" ) {
    print "updating RRD   : $host:$managedname:ams:$input_pool-$type_sam - no AMS file detected\n" if $DEBUG;
    return 0;
  }
  else {
    print "updating RRD   : $host:$managedname:ams:$input_pool-$type_sam - AMS\n" if $DEBUG;
  }

  if ( $json_configured == 1 ) {
  }
  else {
    open( FH, "< $input_pool-$type_sam" ) || main::error( " Can't open $input_pool-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = reverse <FH>;
    close(FH);
    foreach my $line (@lines) {
      chomp($line);

      if ( $line =~ "HSCL" || $line =~ "VIOSE0" || $line =~ "No results were found" || $line =~ "invalid parameter was entered" ) {

        # something wrong with the input data
        # exceptionaly here also : No results were found as without AMS support it prints a lot of warnings
        if ( $line !~ m/No results were found/ ) {
          main::error("$host:$managedname : wrong input data in $host:$managedname:data:$input_pool-$type_sam : $line");
        }
        return 1;
      }

      ( $time, my $curr_pool_mem, my $lpar_curr_io_entitled_mem, my $lpar_mapped_io_entitled_mem, my $lpar_run_mem, my $sys_firmware_pool_mem ) = split( /,/, $line );

      # Check whether first character is a digit, if not then there is something wrong with the
      # input data
      my $ret = substr( $time, 0, 1 );
      if ( $ret =~ /\D/ ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid cpu data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      my $t = str2time( substr( $time, 0, 19 ) );
      $t = correct_to_local_timezone( $t, $hmc_timezone, $local_timezone );
      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid cpu data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );
      }

      $rrd = "$wrkdir/$managedname/$host/mem-pool.rr$type_sam";

      #create rrd db if necessary
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd_pool_mem( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist_ok = 1;
      }

      # find out last record in the db, do it just once
      if ( $ltime == 0 ) {

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        my $last_rec = 0;
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          $rrd_exist_ok = 0;
          next;
        }
        chomp($$last_rec);
        $ltime = $$last_rec;
        $jump  = 0;
      }

      # print "last pool : $ltime  actuall: $t\n";
      # it updates only if time is newer and there is the data (fix for situation that the data is missing)
      if ( $t > $ltime && length($curr_pool_mem) > 0 ) {

        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $jump == 0 ) {
            $jump = 1;

            #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
            #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            next;
          }

          # looks like it is ok as it is second timestap in a row
        }
        $jump = 0;

        $counter_ins++;
        my $datestring = localtime();
        print "Debug-007-$datestring-$rrd $t:$curr_pool_mem:$lpar_curr_io_entitled_mem:$lpar_mapped_io_entitled_mem:$lpar_run_mem:$sys_firmware_pool_mem\n" if $DEBUG_REST_API;
        if ( !( main::isdigit($curr_pool_mem) ) )               { $curr_pool_mem               = "U"; }
        if ( !( main::isdigit($lpar_curr_io_entitled_mem) ) )   { $lpar_curr_io_entitled_mem   = "U"; }
        if ( !( main::isdigit($lpar_mapped_io_entitled_mem) ) ) { $lpar_mapped_io_entitled_mem = "U"; }
        if ( !( main::isdigit($lpar_run_mem) ) )                { $lpar_run_mem                = "U"; }
        if ( !( main::isdigit($sys_firmware_pool_mem) ) )       { $sys_firmware_pool_mem       = "U"; }
        RRDp::cmd qq(update "$rrd" $t:$curr_pool_mem:$lpar_curr_io_entitled_mem:$lpar_mapped_io_entitled_mem:$lpar_run_mem:$sys_firmware_pool_mem);
        $last_time = $time;
        my $answer = RRDp::read;

        # update the time of last record
        $ltime = $t;
      }
    }
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:ams $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_pool {
  my $CPL;
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_pool, $no_time, $json_configured, $save_files, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
  my @lpar_trans       = @{$trans_tmp};
  my $counter          = 0;
  my $counter_tot      = 0;
  my $counter_ins      = 0;
  my $rrd              = "";
  my $rrd_max          = "";
  my $ltime            = 0;
  my $time             = "";
  my $rrd_exist_ok     = 0;
  my $rrd_exist_ok_max = 0;
  my $utime            = time() + 3600;
  my $jump             = 0;
  my $last_time        = "";

  if ( $step > 60 ) {
    $JUMP_DETECT = 10800;    # 3 hours
  }
  if ( $type_sam =~ m/d/ ) {
    $JUMP_DETECT = 178000    # 2 days + for daily graphs/feed
  }

  if ( defined $json_configured && $json_configured == 1 ) {
    my $perf_string = "pool_conf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.pool" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.pool" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.pool at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    my $cpu_pool_lim_cpu = 0;
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path    = "$iostatdir$file";
      my $content = {};
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) ne "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        next;
      }
      my $temp_ts;
      foreach my $timestamp ( sort keys %{$content} ) {
        $temp_ts = $timestamp;
        my $assignedProcCycles     = "";
        my $utilizedPoolCycles     = "";
        my $borrowedPoolProcUnits  = "";
        my $maxProcUnits           = "";
        my $reservedPoolCycles     = "";
        my $currAvailPoolProcUnits = "";
        my $availableProcUnits     = "";

        if   ( defined $content->{$timestamp}{assignedProcCycles} ) { $assignedProcCycles = $content->{$timestamp}{assignedProcCycles}; }
        else                                                        { $assignedProcCycles = "U"; }
        if   ( defined $content->{$timestamp}{utilizedPoolCycles} ) { $utilizedPoolCycles = $content->{$timestamp}{utilizedPoolCycles}; }
        else                                                        { $utilizedPoolCycles = "U"; }
        if   ( defined $content->{$timestamp}{borrowedPoolProcUnits} ) { $borrowedPoolProcUnits = $content->{$timestamp}{borrowedPoolProcUnits}; }
        else                                                           { $borrowedPoolProcUnits = "U"; }
        if   ( defined $content->{$timestamp}{maxProcUnits} ) { $maxProcUnits = $content->{$timestamp}{maxProcUnits}; }
        else                                                  { $maxProcUnits = "U"; }
        if   ( defined $content->{$timestamp}{reservedPoolCycles} ) { $reservedPoolCycles = $content->{$timestamp}{reservedPoolCycles}; }
        else                                                        { $reservedPoolCycles = "U"; }
        if   ( defined $content->{$timestamp}{currAvailPoolProcUnits} ) { $currAvailPoolProcUnits = $content->{$timestamp}{currAvailPoolProcUnits}; }
        else                                                            { $currAvailPoolProcUnits = "U"; }
        if   ( defined $content->{$timestamp}{availableProcUnits} ) { $availableProcUnits = $content->{$timestamp}{availableProcUnits}; }
        else                                                        { $availableProcUnits = "U"; }
        my $testing_out = " $timestamp : $assignedProcCycles $utilizedPoolCycles $borrowedPoolProcUnits $maxProcUnits $reservedPoolCycles";
        my $ret         = substr( $timestamp, 0, 1 );

        if ( $ret =~ /\D/ ) {

          # leave it as wrong input data
          main::error( "$host:$managedname : No valid lpars data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
          next;
        }
        my $t = str2time( substr( $timestamp, 0, 19 ) );
        if ( length($t) < 10 ) {

          # leave it as wrong input data
          main::error( "$host:$managedname : No valid lpars data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
          next;
        }
        if ( $step == 3600 ) {

          # Put on the last time possition "00"!!!
          substr( $t, 8, 2, "00" );
        }
        my $dirname_tmp = "$wrkdir/$managedname/$host/iostat/";
        $rrd     = "$wrkdir/$managedname/$host/pool.rr$type_sam";    #m;
        $rrd_max = "$wrkdir/$managedname/$host/pool.xr$type_sam";    #m;

        #create rrd db if necessary
        if (!defined $CPL->{$rrd}{last_update}){
          if ( !( -e $rrd ) ) {
            if ( $rrd_exist_ok == 0 ) {
              my $ret = create_rrd_pool( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
              if ( $ret == 2 ) {

                #print "parametry: $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time\n";
                next;                                                  # muj test????
                                                                      #return 1;    # RRD creation problem, skip whole load
              }
              $rrd_exist_ok = 1;
            }
            if ( $rrd_exist_ok_max == 0 ) {
              my $ret = create_rrd_pool( $rrd_max, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
              if ( $ret == 2 ) {

                #print "parametry: $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time\n";
                next;                                                  # muj test????
                                                                      #return 1;    # RRD creation problem, skip whole load
              }
              $rrd_exist_ok_max = 1;
            }
          }    #end if (!(-e $rrd))
        }
        
        if ( !defined $CPL->{$rrd}{last_update} ) {

          # construction against crashing daemon Perl code when RRDTool error appears
          # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
          # construction is not too costly as it runs once per each load
          my $last_rec = 0;
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;
          };
          if ($@) {

            #RRDp::error_mode = "catch";
            rrd_error( $@, $rrd );
            $rrd_exist_ok = 0;
            next;
          }
          chomp($$last_rec);
          $CPL->{$rrd}{last_update} = $$last_rec;
        }

        # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
        if ( $t > $CPL->{$rrd}{last_update} ) {    #&& length($vios_name) > 0 )
          my $jump_time = $CPL->{$rrd}{last_update} + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
          if ( $t > $jump_time ) {

            # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
            # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
            if ( $jump == 0 ) {
              $jump = 1;

              #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
              #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
              next;
            }
                # looks like it is ok as it is second timestap in a row
          }
          $jump = 0;
          $counter_ins++;
          $assignedProcCycles = Math::BigInt->new($assignedProcCycles);

          #$borrowedPoolProcUnits = Math::BigInt->new($borrowedPoolProcUnits);
          $utilizedPoolCycles = Math::BigInt->new($utilizedPoolCycles);

          #$maxProcUnits = Math::BigInt->new($maxProcUnits);
          my $maxProcUnits2 = 0;
          if ( defined $borrowedPoolProcUnits && $borrowedPoolProcUnits ne "" ) {
            $maxProcUnits2 += $borrowedPoolProcUnits;
          }
          if ( defined $maxProcUnits && $maxProcUnits ne "" ) {
            $maxProcUnits2 += $maxProcUnits;
          }

          #            goo1: 8 = 3 + 5
          #            goo2: 5.7
          #            -5.7
          #print "goo1: $maxProcUnits2 = $maxProcUnits + $borrowedPoolProcUnits\n";
          #print "goo2: $availableProcUnits\n";
          #print "goo3: $maxProcUnits2 - $availableProcUnits = ". $maxProcUnits2 - $availableProcUnits . "\n";
          if ( $availableProcUnits ne "U" ) {
            $maxProcUnits2 = $maxProcUnits2 - $availableProcUnits;
          }

          #print "updating $rrd from json files\n";
          if ( !( main::isdigit($assignedProcCycles) ) ) { $assignedProcCycles = "U"; }
          if ( !( main::isdigit($utilizedPoolCycles) ) ) { $utilizedPoolCycles = "U"; }
          if ( !( main::isdigit($maxProcUnits2) ) )      { $maxProcUnits2      = "U"; }
          if ( !( main::isdigit($availableProcUnits) ) ) { $availableProcUnits = "U"; }
          my $datestring = localtime();
          print "Debug-008-$datestring-$rrd $t:$assignedProcCycles:$utilizedPoolCycles:$maxProcUnits2:$availableProcUnits\n" if $DEBUG_REST_API;
          $cpu_pool_lim_cpu = $maxProcUnits2 + $availableProcUnits;
          RRDp::cmd qq(update "$rrd" $t:$assignedProcCycles:$utilizedPoolCycles:$maxProcUnits2:$availableProcUnits);
          $last_time = $timestamp;
          my $answer = RRDp::read;

          print "Debug-008max-$rrd_max $t:$assignedProcCycles:$utilizedPoolCycles:$maxProcUnits2:$availableProcUnits\n" if $DEBUG_REST_API;
          RRDp::cmd qq(update "$rrd_max" $t:$assignedProcCycles:$utilizedPoolCycles:$maxProcUnits2:$availableProcUnits);
          my $answer_max = RRDp::read;

          # update the time of last record
          $CPL->{$rrd}{last_update} = $t;
        }
      }    #end foreach my $timestamp
      ##unlink ($path) || print("Cannot delete file $path ". __FILE__. ":". __LINE__);
      if ( defined $file && defined $files[-2] && defined $files[-1] ) {
        if ( $file eq $files[-1] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/pool_perf1" );
        }
        if ( $file eq $files[-2] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/pool_perf2" );
        }
      }
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      open( $ltiph, ">", "$wrkdir/$managedname/$host/iostat/last_ts.pool" );
      print $ltiph "$temp_ts";
      close($ltiph);
    }
    Xorux_lib::write_json( "$ENV{INPUTDIR}/tmp/curr_pool_lim_cpu_$managedname.json", ["$cpu_pool_lim_cpu"] );
  }
  else {
    my $cpu_pool_lim_cpu = 0;
    print "updating RRD   : $host:$managedname:pool:$input_pool-$type_sam\n" if $DEBUG;
    my $date_file = time;
    open( FH, "< $input_pool-$type_sam" ) || main::error( " Can't open $input_pool-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = reverse <FH>;
    close(FH);
    foreach my $line (@lines) {
      chomp($line);

      if ( $line =~ "HSCL" || $line =~ "VIOSE0" || $line =~ "No results were found" || $line =~ "invalid parameter was entered" ) {

        # something wrong with the input data
        main::error("$host:$managedname : wrong input data in $host:$managedname:data:$input_pool-$type_sam : $line");
        return 1;
      }
      ( $time, my $total_pool_cycles, my $utilized_pool_cyc, my $configurable_pool_proc_units, my $borrowed_pool_proc_units, my $curr_avail_pool_proc_units ) = split( /,/, $line );
      if ( !defined $total_pool_cycles            || $total_pool_cycles eq "" )            { $total_pool_cycles            = "U"; }
      if ( !defined $utilized_pool_cyc            || $utilized_pool_cyc eq "" )            { $utilized_pool_cyc            = "U"; }
      if ( !defined $configurable_pool_proc_units || $configurable_pool_proc_units eq "" ) { $configurable_pool_proc_units = "U"; }
      if ( !defined $borrowed_pool_proc_units     || $borrowed_pool_proc_units eq "" )     { $borrowed_pool_proc_units     = "U"; }
      if ( !defined $curr_avail_pool_proc_units   || $curr_avail_pool_proc_units eq "" )   { $curr_avail_pool_proc_units   = "U"; }

      # configurable_pool_proc_units: The number of processing units assigned to all shared processor partitions, rounded up to a whole processor.
      # replacing configurable_pool_proc_units with real number (not rounded), since 5.05-15
      if ( defined($curr_avail_pool_proc_units) && !$curr_avail_pool_proc_units eq '' ) {
        if ( main::isdigit($curr_avail_pool_proc_units) && main::isdigit($borrowed_pool_proc_units) && main::isdigit($configurable_pool_proc_units) ) {
          my $temp = $configurable_pool_proc_units + $borrowed_pool_proc_units - $curr_avail_pool_proc_units;
          $configurable_pool_proc_units = $temp;
          $borrowed_pool_proc_units     = $curr_avail_pool_proc_units;
        }
      }

      # Check whether first character is a digit, if not then there is something wrong with the
      # input data
      my $ret = substr( $time, 0, 1 );
      if ( $ret =~ /\D/ ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid cpu data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      my $t = str2time( substr( $time, 0, 19 ) );
      $t = correct_to_local_timezone( $t, $hmc_timezone, $local_timezone );
      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid cpu data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );
      }

      $rrd     = "$wrkdir/$managedname/$host/pool.rr$type_sam";
      $rrd_max = "$wrkdir/$managedname/$host/pool.xr$type_sam";

      #create rrd db if necessary
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd_pool( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist_ok = 1;
      }

      # create pool.xrm (rrdfile with RRA:MAX)
      if ( $rrd_exist_ok_max == 0 ) {
        my $ret_max = create_rrd_pool( $rrd_max, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret_max == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist_ok_max = 1;
      }

      # find out last record in the db, do it just once
      if ( $ltime == 0 ) {

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        my $last_rec = 0;
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          $rrd_exist_ok = 0;
          next;
        }
        chomp($$last_rec);
        $ltime = $$last_rec;
      }

      # print "last pool : $ltime  actuall: $t\n";
      # it updates only if time is newer and there is the data (fix for situation that the data is missing)
      if ( $t > $ltime && length($total_pool_cycles) > 0 ) {

        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $jump == 0 ) {
            $jump = 1;

            #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
            #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            next;
          }

          # looks like it is ok as it is second timestap in a row
        }
        $jump = 0;

        $counter_ins++;

        #print "$counter_ins : $time $t:$total_pool_cycles:$utilized_pool_cyc:$configurable_pool_proc_units:$borrowed_pool_proc_units \n";
        $total_pool_cycles = Math::BigInt->new($total_pool_cycles);
        $utilized_pool_cyc = Math::BigInt->new($utilized_pool_cyc);
        my $datestring = localtime();
        print "Debug-009-$datestring-$rrd $t:$total_pool_cycles:$utilized_pool_cyc:$configurable_pool_proc_units:$borrowed_pool_proc_units\n" if $DEBUG_REST_API;
        if ( !( main::isdigit($total_pool_cycles) ) )            { $total_pool_cycles            = "U"; }
        if ( !( main::isdigit($utilized_pool_cyc) ) )            { $utilized_pool_cyc            = "U"; }
        if ( !( main::isdigit($configurable_pool_proc_units) ) ) { $configurable_pool_proc_units = "U"; }
        if ( !( main::isdigit($borrowed_pool_proc_units) ) )     { $borrowed_pool_proc_units     = "U"; }
        $cpu_pool_lim_cpu = $configurable_pool_proc_units + $borrowed_pool_proc_units;
        RRDp::cmd qq(update "$rrd" $t:$total_pool_cycles:$utilized_pool_cyc:$configurable_pool_proc_units:$borrowed_pool_proc_units);
        $last_time = $time;
        my $answer = RRDp::read;

        # update pool.xrm
        print "Debug-010-$datestring-$rrd_max $t:$total_pool_cycles:$utilized_pool_cyc:$configurable_pool_proc_units:$borrowed_pool_proc_units\n" if $DEBUG_REST_API;
        RRDp::cmd qq(update "$rrd_max" $t:$total_pool_cycles:$utilized_pool_cyc:$configurable_pool_proc_units:$borrowed_pool_proc_units);
        my $answer_max = RRDp::read;

        # update the time of last record
        $ltime = $t;
      }
    }
    Xorux_lib::write_json( "$ENV{INPUTDIR}/tmp/curr_pool_lim_cpu_$managedname.json", ["$cpu_pool_lim_cpu"] );
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:pool $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_pool_sh {
  my $SHP;
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_pool_sh, $SSH, $hmc_user, $pool_tmp, $pool_list_file, $no_time, $json_configured, $save_files, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
  my @lpar_trans          = @{$trans_tmp};
  my @pool_list           = @{$pool_tmp};
  my $counter             = 0;
  my $counter_tot         = 0;
  my $counter_ins         = 0;
  my $rrd                 = "";
  my $rrd_max             = "";
  my @shared_pool         = "";
  my $max_pool_units      = "";
  my $reserved_pool_units = "";
  my $time                = "";
  my @rrd_exist           = "";
  my $last_rec            = 0;
  my $last_time           = "";
  my $jump                = 0;

  print "debug $hmc_timezone\n";

  my @pool_name = "";
  my @pool_time = "";
  my @pool_jump = "";

  if ( $step > 60 ) {
    $JUMP_DETECT = 10800;    # 3 hours
  }
  if ( $type_sam =~ m/d/ ) {
    $JUMP_DETECT = 178000    # 2 days + for daily graphs/feed
  }

  if ( $json_configured == 1 ) {
    print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : $host $managedname updating rrd poolsh\n" if $DEBUG;
    my $perf_string = "poolsh_conf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.poolsh" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.poolsh" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.poolsh at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path    = "$iostatdir$file";
      my $content = {};
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) ne "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        next;
      }
      foreach my $timestamp ( sort keys %{$content} ) {
        foreach my $pool ( keys %{ $content->{$timestamp} } ) {
          my $utilizedPoolCycles    = "";
          my $assignedProcCycles    = "";
          my $borrowedPoolProcUnits = "";
          my $maxProcUnits          = "";
          my $reservedPoolUnits     = "";
          my $id                    = "";
          my $rrd_exist_ok          = 0;
          my $rrd_exist_ok_max      = 0;
          if   ( defined $content->{$timestamp}{$pool}{assignedProcCycles} ) { $assignedProcCycles = $content->{$timestamp}{$pool}{assignedProcCycles}; }
          else                                                               { $assignedProcCycles = "U"; }
          if   ( defined $content->{$timestamp}{$pool}{utilizedPoolCycles} ) { $utilizedPoolCycles = $content->{$timestamp}{$pool}{utilizedPoolCycles}; }
          else                                                               { $utilizedPoolCycles = "U"; }
          if   ( defined $content->{$timestamp}{$pool}{maxProcUnits} ) { $maxProcUnits = $content->{$timestamp}{$pool}{maxProcUnits}; }
          else                                                         { $maxProcUnits = "U"; }
          if   ( defined $content->{$timestamp}{$pool}{borrowedPoolProcUnits} ) { $borrowedPoolProcUnits = $content->{$timestamp}{$pool}{borrowedPoolProcUnits}; }
          else                                                                  { $borrowedPoolProcUnits = "U"; }
          if   ( defined $content->{$timestamp}{$pool}{reservedPoolUnits} ) { $reservedPoolUnits = $content->{$timestamp}{$pool}{reservedPoolUnits}; }
          else                                                              { $reservedPoolUnits = 0; }
          if ( defined $content->{$timestamp}{$pool}{id} ) { $id = $content->{$timestamp}{$pool}{id}; }
          else {
            main::error( "Missing id of shared pool at " . __FILE__ . ":" . __LINE__ );
            next;    #shared pool without id is not possible
          }
          my $testing_out = "pool sh test: $id $assignedProcCycles $utilizedPoolCycles $maxProcUnits $borrowedPoolProcUnits";

          my $ret = substr( $timestamp, 0, 1 );
          if ( $ret =~ /\D/ ) {

            # leave it as wrong input data
            main::error( "$host:$managedname : No valid lpars data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
            next;
          }
          my $t = str2time( substr( $timestamp, 0, 19 ) );
          if ( length($t) < 10 ) {

            # leave it as wrong input data
            main::error( "$host:$managedname : No valid lpars data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
            next;
          }
          if ( $step == 3600 ) {

            # Put on the last time possition "00"!!!
            substr( $t, 8, 2, "00" );
          }
          my $dirname_tmp = "$wrkdir/$managedname/$host";
          $rrd     = "$wrkdir/$managedname/$host/SharedPool$id.rr$type_sam";    #m;
          $rrd_max = "$wrkdir/$managedname/$host/SharedPool$id.xr$type_sam";    #m;

          #create rrd db if necessary
          if (!defined $SHP->{$rrd}{last_update}){
            if ( !( -e $rrd ) ) {
              if ( $rrd_exist_ok == 0 ) {
                my $ret = create_rrd_pool_shared( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
                if ( $ret == 2 ) {

                  #print "parametry: $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time\n";
                  #next; # muj test???? EDIT
                  #return 1;    # RRD creation problem, skip whole load
                }
                $rrd_exist_ok = 1;
              }
              if ( $rrd_exist_ok_max == 0 ) {
                my $ret = create_rrd_pool_shared( $rrd_max, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
                if ( $ret == 2 ) {

                  #print "parametry: $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time\n";
                  #next; # muj test???? EDIT
                  #return 1;    # RRD creation problem, skip whole load
                }
                $rrd_exist_ok_max = 1;
              }
            }    #end if (!(-e $rrd))
          }
          if ( !defined $SHP->{$rrd}{last_update} ) {

            # construction against crashing daemon Perl code when RRDTool error appears
            # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
            # construction is not too costly as it runs once per each load
            my $last_rec = 0;
            eval {
              RRDp::cmd qq(last "$rrd" );
              $last_rec = RRDp::read;
            };
            if ($@) {

              #RRDp::error_mode = "catch";
              rrd_error( $@, $rrd );
              $rrd_exist_ok = 0;
              next;
            }
            chomp($$last_rec);
            $SHP->{$rrd}{last_update} = $$last_rec;
          }

          # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
          if ( $t > $SHP->{$rrd}{last_update} ) {    #&& length($vios_name) > 0 )
            my $jump_time = $SHP->{$rrd}{last_update} + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
            if ( $t > $jump_time ) {

              # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
              # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
              if ( $jump == 0 ) {
                $jump = 1;

                #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
                #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
                next;
              }
                  # looks like it is ok as it is second timestap in a row
            }
            $jump = 0;
            $counter_ins++;

            #RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write);
            if ( !defined $reservedPoolUnits || $reservedPoolUnits eq '' ) { $reservedPoolUnits = 0; }
            $utilizedPoolCycles = Math::BigInt->new($utilizedPoolCycles);
            $assignedProcCycles = Math::BigInt->new($assignedProcCycles);
            my $datestring = localtime();
            print "Debug-011-$datestring-$rrd $t:$assignedProcCycles:$utilizedPoolCycles:$maxProcUnits:$reservedPoolUnits\n" if $DEBUG_REST_API;
            if ( !( main::isdigit($assignedProcCycles) ) ) { $assignedProcCycles = "U"; }
            if ( !( main::isdigit($utilizedPoolCycles) ) ) { $utilizedPoolCycles = "U"; }
            if ( !( main::isdigit($maxProcUnits) ) )       { $maxProcUnits       = "U"; }
            if ( !( main::isdigit($reservedPoolUnits) ) )  { $reservedPoolUnits  = "U"; }
            RRDp::cmd qq(update "$rrd" $t:$assignedProcCycles:$utilizedPoolCycles:$maxProcUnits:$reservedPoolUnits);

            #print "1207 probehl update shpool $t:$assignedProcCycles:$utilizedPoolCycles:$maxProcUnits:$reservedPoolUnits\n";
            $last_time = $timestamp;
            my $answer;
            $answer = RRDp::read;
            print "Debug-011max-$rrd_max $t:$assignedProcCycles:$utilizedPoolCycles:$maxProcUnits:$reservedPoolUnits\n" if $DEBUG_REST_API;
            RRDp::cmd qq(update "$rrd_max" $t:$assignedProcCycles:$utilizedPoolCycles:$maxProcUnits:$reservedPoolUnits);
            $answer = RRDp::read;

            #update the time of last record
            $SHP->{$rrd}{last_update} = $t;
          }
        }
      }
      if ( defined $file && defined $files[-1] && defined $files[-2] ) {
        if ( $file eq $files[-1] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/poolsh_perf1" );
        }
        if ( $file eq $files[-2] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/poolsh_perf2" );
        }
      }
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
    }
  }
  else {
    print "updating RRD   : $host:$managedname:pool_sh:$input_pool_sh-$type_sam\n" if $DEBUG;

    # first check whether it supports more CPU pools (POWER6+), if not then return
    open( FH, "< $input_pool_sh-$type_sam" ) || main::error("Cannot open :$input_pool_sh-$type_sam") && return 0;
    while ( my $line = <FH> ) {
      chomp($line);
      if ( $line =~ "No results were found." ) {
        print "info           : $host:$managedname No shared CPU pools\n" if $DEBUG;
        close(FH);
        return 0;
      }
    }
    close(FH);

    print "fetching HMC   : $host:$managedname shared pools\n" if $DEBUG;
    my $def_pool = `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -r pool -m \\"$managedname\\" -F configurable_pool_proc_units,borrowed_pool_proc_units  --filter \"event_types=sample\""`;
    if ( !defined($def_pool) || $def_pool eq '' ) {
      print "info           : $host:$managedname Probably no shared CPU pools are supported or configured\n" if $DEBUG;
      return 0;
    }
    my $ret1 = substr( $def_pool, 0, 1 );
    if ( $ret1 =~ /\D/ ) {

      # leave it, it does not contain a digit, probably is there "No results were found"
      print "info           : $host:$managedname Probably no shared CPU pools are supported or configured\n" if $DEBUG;
      return 0;
    }
    my @def_pool_list = split( /,/, $def_pool );
    my $max_def_pool  = $def_pool_list[0] + $def_pool_list[1];

    #print "Default pool : $max_def_pool $def_pool_list[0] $def_pool_list[1] \n";
    print "fetching HMC   : $host:$managedname shared pool list\n" if $DEBUG;
    @pool_list = `$SSH $hmc_user\@$host "export LANG=en_US; lshwres -r procpool  -m \\"$managedname\\" -F shared_proc_pool_id,max_pool_proc_units,curr_reserved_pool_proc_units,name"`;
    #print "DDDDDD : lshwres -r procpool  -m  $managedname -F shared_proc_pool_id,max_pool_proc_units,curr_reserved_pool_proc_units,name\n";
    my @pool_list_no_gap = "";
    my $pool_indx        = 0;

    # create mapping table between pool id and alias name
    open( FP, "> $wrkdir/$managedname/$host/cpu-pools-mapping.txt" ) || main::error("Cannot open : $wrkdir/$managedname/cpu-pools-mapping.txt : $!");
    foreach my $pool (@pool_list) {
      if ( $pool =~ "HSCL" || $pool =~ "VIOSE0" ) {

        # something wrong with the input data
        main::error("$host:$managedname : wrong input data in $wrkdir/$managedname/$host/cpu-pools-mapping.txt : $pool");
        return 1;
      }

      if ( length($pool) > 1 ) {
        my @shared_p = split( /,/, $pool );

        # if there is not a digit than the server probably does not support shared CPU pools
        if ( $shared_p[0] =~ /\d/ ) {
          my $name = $shared_p[3];
          my $id   = $shared_p[0];
          if ( $id =~ "HSCL" || $name =~ "HSCL" ) {
            next;
          }

          # lshwres avoid pools with no reserved CPU cores --> means they cannot be used what causes the gap
          # and brings problems in further processing
          while ( $id > $pool_indx ) {
            $pool_list_no_gap[$pool_indx] = "$pool_indx,0,0,SharedPool$pool_indx";
            print FP "$pool_indx,SharedPool$pool_indx\n";
            $pool_indx++;
          }
          $pool_list_no_gap[$pool_indx] = $pool;
          $pool_indx++;
          print FP "$id,$name";

          #print "$id,$name";
        }
      }
    }
    close(FP);

    my $do_pool_agg = 0;
    open( FH, "< $input_pool_sh-$type_sam" ) || main::error("Cannot open input pool sh : $input_pool_sh-$type_sam : $!") && return 0;
    my @lines = reverse <FH>;
    close(FH);

    foreach my $line (@lines) {
      chomp($line);

      ( $time, my $shared_proc_pool_id, my $total_pool_cycles, my $utilized_pool_cyc ) = split( /,/, $line );

      if ( defined($shared_proc_pool_id) && !$shared_proc_pool_id eq '' && main::isdigit($shared_proc_pool_id) && $shared_proc_pool_id > 0 && $do_pool_agg == 0 ) {

        # get pools list for pool aggregated charts
        `$SSH $hmc_user\@$host "lshwres -r procpool -m \\"$managedname\\" -F shared_proc_pool_id,lpar_names" > "$wrkdir/$managedname/$host/$pool_list_file"`;
        $do_pool_agg = 1;
      }

      #if ($shared_proc_pool_id > 0 ) {
      #   $do_pool_agg=1;
      # }

      # Check whether first character is a digit, if not then there is something wrong with the
      # input data
      my $ret = substr( $time, 0, 1 );
      if ( $ret =~ /\D/ ) {

        # leave it as wrong input data
        print "info           : $host:$managedname Probably no shared CPU pools are supported or configured\n" if $DEBUG;
        close(FH);
        return 0;
      }

      # only for shared pools, not for default pool (id=0)
      #if ( $shared_proc_pool_id) {
      my $t = str2time( substr( $time, 0, 19 ) );
      $t = correct_to_local_timezone( $t, $hmc_timezone, $local_timezone );
      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid shared cpu pool data time format got from HMC : $t : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );
      }

      $rrd     = "$wrkdir/$managedname/$host/SharedPool$shared_proc_pool_id.rr$type_sam";
      $rrd_max = "$wrkdir/$managedname/$host/SharedPool$shared_proc_pool_id.xr$type_sam";

      #create rrd db if necessary
      # find out if rrd db exist, and place info to the array to do not check its existency every time
      my $rrd_exist_ok     = 0;
      my $rrd_exist_ok_max = 0;
      my $rrd_exist_row    = 0;
      foreach my $row (@rrd_exist) {
        $rrd_exist_row++;
        if ( $row =~ m/^$shared_proc_pool_id$/ ) {    # from some reason must be string comparsion
          $rrd_exist_ok = 1;
          last;
        }
      }
      if ( $rrd_exist_ok == 0 ) {
        $rrd_exist[$rrd_exist_row] = $shared_proc_pool_id;
        my $ret = create_rrd_pool_shared( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret == 2 ) {
          return 1;                                   # RRD creation problem, skip whole load
        }
      }

      # create .xrm
      if ( $rrd_exist_ok_max == 0 ) {
        my $ret_max = create_rrd_pool_shared( $rrd_max, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret_max == 2 ) {
          return 1;                                   # RRD creation problem, skip whole load
        }
      }

      # found out last record and save it
      # it has to be done dou to better stability, when updating older record that the latest one update and process crashes
      my $l_count = 0;
      my $found   = -1;
      my $ltime;
      my $pool_meta = quotemeta($shared_proc_pool_id);
      foreach my $l (@pool_name) {
        if ( $l =~ m/^$pool_meta$/ ) {
          $found = $l_count;
          last;
        }
        $l_count++;
      }
      if ( $found > -1 ) {
        $ltime   = $pool_time[$found];
        $l_count = $found;
      }
      else {
        # find out last record in the db

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          if ( $rrd_exist[$rrd_exist_row] =~ m/^$shared_proc_pool_id$/ ) {
            $rrd_exist[$rrd_exist_row] = "";
          }
          next;
        }
        chomp($$last_rec);
        $pool_name[$l_count] = $shared_proc_pool_id;
        $pool_time[$l_count] = $$last_rec;
        $pool_jump[$l_count] = 0;
        $ltime               = $$last_rec;
      }

      # print "last pool : $$last_rec  actuall: $t\n";
      # it updates only if time is newer and there is the data (fix for situation that the data is missing)
      if ( $t > $pool_time[$l_count] && length($total_pool_cycles) > 0 ) {
        if ($shared_proc_pool_id) {
          @shared_pool         = split( /,/, $pool_list_no_gap[$shared_proc_pool_id] );
          $max_pool_units      = $shared_pool[1];
          $reserved_pool_units = $shared_pool[2];
        }
        else {
          $max_pool_units      = $max_def_pool;
          $reserved_pool_units = $max_def_pool;
        }

        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $pool_jump[$l_count] == 0 ) {
            $pool_jump[$l_count] = 1;
            if ( $shared_proc_pool_id > 0 ) {

              # do not print out that message for SharedPool0 it probably does not exist if there are no shared pools defined
              #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
              #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            }
            next;
          }

          # looks like it is ok as it is second timestap in a row
        }
        $pool_jump[$l_count] = 0;

        #print "$time $t:$total_pool_cycles:$utilized_pool_cyc:$max_pool_units:$reserved_pool_units \n";
        if ( !$max_pool_units eq '' && !$reserved_pool_units eq '' ) {

          # can happen in certain circumstance that the last pool is deleted but then cannot be
          # found $max_pool_units and $reserved_pool_units
          $total_pool_cycles = Math::BigInt->new($total_pool_cycles);
          $utilized_pool_cyc = Math::BigInt->new($utilized_pool_cyc);
          my $datestring = localtime();
          print "Debug-012-$datestring-$rrd $t:$total_pool_cycles:$utilized_pool_cyc:$max_pool_units:$reserved_pool_units\n" if $DEBUG_REST_API;
          if ( !( main::isdigit($total_pool_cycles) ) )   { $total_pool_cycles   = "U"; }
          if ( !( main::isdigit($utilized_pool_cyc) ) )   { $utilized_pool_cyc   = "U"; }
          if ( !( main::isdigit($max_pool_units) ) )      { $max_pool_units      = "U"; }
          if ( !( main::isdigit($reserved_pool_units) ) ) { $reserved_pool_units = "U"; }
          RRDp::cmd qq(update "$rrd" $t:$total_pool_cycles:$utilized_pool_cyc:$max_pool_units:$reserved_pool_units);
          $counter_ins++;
          $last_time = $time;
          my $answer = RRDp::read;

          print "Debug-012max-$rrd_max $t:$total_pool_cycles:$utilized_pool_cyc:$max_pool_units:$reserved_pool_units\n" if $DEBUG_REST_API;
          RRDp::cmd qq(update "$rrd_max" $t:$total_pool_cycles:$utilized_pool_cyc:$max_pool_units:$reserved_pool_units);
          my $answer_max = RRDp::read;

          $pool_time[$l_count] = $t;
        }
      }

      #}
    }
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:pool_sh $counter_ins record(s)\n" if $DEBUG;
  }

  # moved to lpar2rrd.pl, a problem with yearly graphs
  #if ($do_pool_agg == 1) {
  # there are more CPU pools, will be created aggregated chart for each pool
  # download data now (list of lpars)
  #main::procpoolagg($host,$managedname);
  #}

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_mem {
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_mem, $no_time, $json_configured, $save_files, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
  my @lpar_trans   = @{$trans_tmp};
  my $counter      = 0;
  my $counter_tot  = 0;
  my $counter_ins  = 0;
  my $rrd          = "";
  my $ltime        = 0;
  my $time         = "";
  my $rrd_exist_ok = 0;
  my $jump         = 0;
  my $last_time    = "";

  if ( $step > 60 ) {
    $JUMP_DETECT = 10800;    # 3 hours
  }
  if ( $type_sam =~ m/d/ ) {
    $JUMP_DETECT = 178000    # 2 days + for daily graphs/feed
  }

  if ( $json_configured == 1 ) {
    my $perf_string = "mem_conf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $wrkdir/$managedname/$host/iostat/ " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    my $last_ts_file = "$wrkdir/$managedname/$host/iostat/last_ts.mem";
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.mem" ) {
      open( $ltiph, "<", $last_ts_file ) || main::error( "Cannot open file $last_ts_file at " . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path = "$iostatdir$file";

      #$content = HASH(###);
      my $content = {};
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) ne "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        next;
      }
      foreach my $timestamp ( sort keys %{$content} ) {
        if ( $timestamp eq $saved_ts ) { next; }
        $temp_ts = $timestamp;
        my $availableMem          = "";
        my $assignedMemToFirmware = "";
        my $configurableMem       = "";

        if   ( defined $content->{$timestamp}{availableMem} ) { $availableMem = $content->{$timestamp}{availableMem}; }
        else                                                  { $availableMem = "U"; }
        if   ( defined $content->{$timestamp}{assignedMemToFirmware} ) { $assignedMemToFirmware = $content->{$timestamp}{assignedMemToFirmware}; }
        else                                                           { $assignedMemToFirmware = "U"; }
        if   ( defined $content->{$timestamp}{configurableMem} ) { $configurableMem = $content->{$timestamp}{configurableMem}; }
        else                                                     { $configurableMem = "U"; }
        my $testing_out = "mem test: $availableMem $assignedMemToFirmware $configurableMem\n";
        my $ret         = substr( $timestamp, 0, 1 );

        if ( $ret =~ /\D/ ) {

          # leave it as wrong input data
          main::error( "$host:$managedname : No valid memory data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
          next;
        }
        my $t = str2time( substr( $timestamp, 0, 19 ) );
        if ( length($t) < 10 ) {

          # leave it as wrong input data
          main::error( "$host:$managedname : No valid memory data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
          next;
        }
        if ( $step == 3600 ) {

          # Put on the last time possition "00"!!!
          substr( $t, 8, 2, "00" );
        }
        $rrd = "$wrkdir/$managedname/$host/mem.rr$type_sam";    #m;

        #create rrd db if necessary
        if ( !( -e $rrd ) ) {
          if ( $rrd_exist_ok == 0 ) {
            my $ret = create_rrd_mem( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );

            #my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, "", "", $wrkdir, $lpar, $t, $keep_virtual );
            if ( $ret == 2 ) {

              #print "parametry: $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time\n";
              next;                                             # muj test????
                                                                #return 1;    # RRD creation problem, skip whole load
            }
            $rrd_exist_ok = 1;
          }
        }    #end if (!(-e $rrd))
        if ( $ltime == 0 ) {

          # construction against crashing daemon Perl code when RRDTool error appears
          # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
          # construction is not too costly as it runs once per each load
          my $last_rec = 0;
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;
          };
          if ($@) {

            #RRDp::error_mode = "catch";
            rrd_error( $@, $rrd );
            $rrd_exist_ok = 0;
            next;
          }
          chomp($$last_rec);
          $ltime = $$last_rec;
        }

        # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
        if ( $t > $ltime ) {    #&& length($vios_name) > 0 )
          my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
          if ( $t > $jump_time ) {

            # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
            # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
            if ( $jump == 0 ) {
              $jump = 1;

              #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
              #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
              next;
            }
                # looks like it is ok as it is second timestap in a row
          }
          $jump = 0;
          $counter_ins++;

          #print "updating $rrd from json files\n";
          my $datestring = localtime();
          print "Debug-013-$datestring-$rrd $t:$availableMem:$configurableMem:$assignedMemToFirmware\n" if $DEBUG_REST_API;
          if ( !( main::isdigit($availableMem) ) )          { $availableMem          = "U"; }
          if ( !( main::isdigit($configurableMem) ) )       { $configurableMem       = "U"; }
          if ( !( main::isdigit($assignedMemToFirmware) ) ) { $assignedMemToFirmware = "U"; }
          RRDp::cmd qq(update "$rrd" $t:$availableMem:$configurableMem:$assignedMemToFirmware);
          $last_time = $timestamp;
          my $answer = RRDp::read;

          # update the time of last record
          $ltime = $t;
        }
      }    #end foreach my $timestamp
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
    }
  }
  else {
    print "updating RRD   : $host:$managedname:mem:$input_mem-$type_sam\n" if $DEBUG;
    open( FH, "< $input_mem-$type_sam" ) || main::error( " Can't open $input-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = reverse <FH>;
    close(FH);

    foreach my $line (@lines) {
      chomp($line);

      if ( $line =~ "HSCL" || $line =~ "VIOSE0" || $line =~ "No results were found" || $line =~ "invalid parameter was entered" ) {

        # something wrong with the input data
        # do not alert for memory, this causing problems and logs a lot of errors but it is minor feature ...
        main::error("$host:$managedname : wrong input data in $host:$managedname:data:$input_mem-$type_sam : $line");
        return 1;
      }

      ( $time, my $curr_avail_sys_mem, my $configurable_sys_mem, my $sys_firmware_mem ) = split( /,/, $line );

      if ( $curr_avail_sys_mem eq '' || $configurable_sys_mem eq '' || $sys_firmware_mem eq '' ) {

        # problem with data
        #main::error ("$host:$managedname : wrong input data in $host:$managedname:data:$input_mem-$type_sam : $line");
        next;
      }

      # Check whether first character is a digit, if not then there is something wrong with the
      # input data
      my $ret = substr( $time, 0, 1 );
      if ( $ret =~ /\D/ ) {
        main::error( "$host:$managedname : No valid mem data got from HMC : $ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      my $t = str2time( substr( $time, 0, 19 ) );
      $t = correct_to_local_timezone( $t, $hmc_timezone, $local_timezone );
      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );
      }

      $rrd = "$wrkdir/$managedname/$host/mem.rr$type_sam";

      #create rrd db if necessary
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd_mem( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist_ok = 1;
      }

      # find out last record in the db
      if ( $ltime == 0 ) {

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        my $last_rec = 0;
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          $rrd_exist_ok = 0;
          next;
        }
        chomp($$last_rec);
        $ltime = $$last_rec;
      }

      # print "last mem  : $ltime actuall: $t\n";
      # it updates only if time is newer and there is the data (fix for situation that the data is missing)
      if ( $t > $ltime && length($curr_avail_sys_mem) > 0 ) {

        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $jump == 0 ) {
            $jump = 1;

            #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
            #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            next;
          }

          # looks like it is ok as it is second timestap in a row
        }
        $jump = 0;

        $counter_ins++;

        #print "++ 01 $time $t:$curr_avail_sys_mem \n";
        my $datestring = localtime();
        print "Debug-014-$datestring-$rrd $t:$curr_avail_sys_mem:$configurable_sys_mem:$sys_firmware_mem\n" if $DEBUG_REST_API;
        if ( !( main::isdigit($curr_avail_sys_mem) ) )   { $curr_avail_sys_mem   = "U"; }
        if ( !( main::isdigit($configurable_sys_mem) ) ) { $configurable_sys_mem = "U"; }
        if ( !( main::isdigit($sys_firmware_mem) ) )     { $sys_firmware_mem     = "U"; }
        RRDp::cmd qq(update "$rrd" $t:$curr_avail_sys_mem:$configurable_sys_mem:$sys_firmware_mem);
        $last_time = $time;
        my $answer = RRDp::read;

        # update the time of last record
        $ltime = $t;
      }
    }
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:mem $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_cod {
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_cod, $no_time, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
  my @lpar_trans               = @{$trans_tmp};
  my $counter                  = 0;
  my $counter_tot              = 0;
  my $counter_ins              = 0;
  my $rrd                      = "";
  my $ltime                    = 0;
  my $time                     = "";
  my $rrd_exist_ok             = 0;
  my $jump                     = 0;
  my $last_time                = "";
  my $unreported_proc_min_last = 0;

  if ( $step > 60 ) {
    $JUMP_DETECT = 10800;    # 3 hours
  }
  if ( $type_sam =~ m/d/ ) {
    $JUMP_DETECT = 178000    # 2 days + for daily graphs/feed
  }

  if ( !-f "$input_cod-$type_sam" ) {
    print "CoD data load  : $host:$managedname:CoD:$input_cod-$type_sam - no input file found\n" if $DEBUG;
    return 1;
  }

  print "updating RRD   : $host:$managedname:CoD:$input_cod-$type_sam\n" if $DEBUG;
  open( FH, "< $input_cod-$type_sam" ) || main::error( " Can't open $input_cod-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  my @lines = reverse <FH>;
  close(FH);

  foreach my $line (@lines) {
    chomp($line);

    if ( $line =~ "HSCL" || $line =~ "VIOSE0" || $line =~ "No results were found" || $line =~ "invalid parameter was entered" ) {

      # something wrong with the input data
      # do not alert for memory, this causing problems and logs a lot of errors but it is minor feature ...
      #main::error ("$host:$managedname : wrong input data in $host:$managedname:data:$input_mem-$type_sam : $line");
      return 1;
    }

    ( $time, my $used_proc_min, my $unreported_proc_min ) = split( /,/, $line );

    if ( !defined($used_proc_min) || !defined($unreported_proc_min) || $used_proc_min eq '' || $unreported_proc_min eq '' ) {

      # problem with data
      # main::error ("$host:$managedname : wrong input data in $host:$managedname:data:$input_cod-$type_sam : $line");
      # ignore it quietly, old HMC v6 does not support Co
      next;
    }

    # Check whether first character is a digit, if not then there is something wrong with the
    # input data
    my $ret = substr( $time, 0, 1 );
    if ( $ret =~ /\D/ ) {
      main::error( "$host:$managedname : No valid cod data got from HMC : $ret : $line " . __FILE__ . ":" . __LINE__ );
      next;
    }
    my $t = str2time( substr( $time, 0, 19 ) );
    $t = correct_to_local_timezone( $t, $hmc_timezone, $local_timezone );
    if ( $step == 3600 ) {

      # Put on the last time possition "00"!!!
      substr( $t, 8, 2, "00" );
    }

    $rrd = "$wrkdir/$managedname/$host/cod.rr$type_sam";

    #create rrd db if necessary
    if ( $rrd_exist_ok == 0 ) {
      if ( !-f "$rrd" ) {

        # check if it is realy first run or just first run for that input file
        $ltime = -1;
      }
      my $ret = create_rrd_cod( $rrd, $t - 60, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
      if ( $ret == 2 ) {
        return 1;    # RRD creation problem, skip whole load
      }
      $rrd_exist_ok = 1;
    }

    # find out last record in the db
    if ( $ltime == 0 ) {

      # construction against crashing daemon Perl code when RRDTool error appears
      # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
      # construction is not too costly as it runs once per each load
      my $last_rec = 0;
      eval {
        RRDp::cmd qq(last "$rrd" );
        $last_rec = RRDp::read;
      };
      if ($@) {
        rrd_error( $@, $rrd );
        $rrd_exist_ok = 0;
        next;
      }
      chomp($$last_rec);
      $ltime = $$last_rec;

      # find out last value of unreported_proc_min
      my $l = localtime($$last_rec);

      # get LAST value from RRD
      #RRDp::cmd qq(fetch "$rrd" "MAX" "-s $$last_rec-$step" "-e $$last_rec-$step");
      RRDp::cmd qq(fetch "$rrd" "AVERAGE" "-s $$last_rec-$step" "-e $$last_rec-$step");
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
          if ( $m_arr[1] =~ /\d/ && $m_arr[2] =~ /\d/ ) {

            #print "m : $m\n" if $DEBUG ;
            #print "\n$m_arr[1] $m_arr[2]" if $DEBUG ;
            $unreported_proc_min_last = sprintf( "%d", $m_arr[2] );
          }
        }
      }

      #print "001 $ltime -----  $l : $$last_rec : $$row : $time $unreported_proc_min_last \n";
    }

    #print "002 $ltime -----  $time $unreported_proc_min_last \n";

    # print "last cod  : $ltime actuall: $t\n";
    # it updates only if time is newer and there is the data (fix for situation that the data is missing)
    if ( $t > $ltime && length($used_proc_min) > 0 ) {

      # Do not use that for CoD, it is pretty normal here!!!
      #my $jump_time = $ltime + $JUMP_DETECT; #set time for sudden jump detection (15mins)
      #if ( $t > $jump_time ) {
      #
      # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
      # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
      #if ( $jump == 0 ) {
      #  $jump = 1;
      #  main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
      #  main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
      #  next;
      #}
      # looks like it is ok as it is second timestap in a row
      #}
      #$jump = 0;

      # there has to be filled in data gaps
      #print "003 $time $t:$used_proc_min:$unreported_proc_min \n";
      while ( $t > ( $ltime + 60 ) ) {
        if ( $ltime == -1 ) {

          # initial CoD load with creation of rrd, skip it this time
          last;
        }
        $ltime = $ltime + 60;

        #print "004 $ltime:0:$unreported_proc_min_last  --- $t\n";
        RRDp::cmd qq(update "$rrd" $ltime:0:$unreported_proc_min_last);
        my $answer = RRDp::read;
      }

      $counter_ins++;
      RRDp::cmd qq(update "$rrd" $t:$used_proc_min:$unreported_proc_min);
      $last_time = $time;
      my $answer = RRDp::read;

      # update the time of last record
      $ltime                    = $t;
      $unreported_proc_min_last = $unreported_proc_min;
    }
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:cod $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

### SAME FUNCTION I HAVE TO USE TO LOAD DADA FROM JSONS ###########################

sub load_data_sriov {
  my $time        = "";
  my $counter     = 0;
  my $counter_tot = 0;
  my $counter_ins = 0;
  my $rrd         = "";
  my $rrd_max     = "";
  my $utime       = time() + 3600;
  my $jump        = 0;
  my $last_time   = "";

  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_sriov, $no_time, $json_configured, $save_files, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
  if ( $json_configured eq "1" ) {
    my $perf_string = "sriov_perf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.sriov" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.sriov" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.sriov at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path    = "$iostatdir$file";
      my $content = [];
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || $content eq "0" || ref($content) eq "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        next;
      }
      foreach my $sample ( @{$content} ) {
        my $ts                     = $sample->[0];
        my $vios                   = $sample->[1];
        my $physicalLocation       = $sample->[2];
        my $configurationType      = $sample->[3];
        my $drcIndex               = $sample->[4];
        my $droppedReceivedPackets = $sample->[5];
        my $droppedSentPackets     = $sample->[6];
        my $errorIn                = $sample->[7];
        my $errorOut               = $sample->[8];
        my $physicalDrcIndex       = $sample->[9];
        my $physicalPortId         = $sample->[10];
        my $read                   = $sample->[11];
        my $io_read                = $sample->[12];
        my $write                  = $sample->[13];
        my $io_write               = $sample->[14];
        my $vnicDeviceMode         = $sample->[14];
        my $t                      = str2time( substr( $ts, 0, 19 ) );
        $temp_ts = $t;

        ( undef, undef, my $short_physloc ) = split( '\\.', $physicalLocation );
        $short_physloc = "" if (!defined $short_physloc);
        $rrd = "$wrkdir/$managedname/$host/adapters/$short_physloc.rasr$type_sam";

        if ( !-e ($rrd) ) {
          my $ret = create_rrd_sriov2( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
          if ( $ret == 2 ) {
            next;
          }
        }
        my $last_rec;
        eval {
          RRDp::cmd qq(last "$rrd");
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          next;
        }
        chomp($$last_rec);
        my $ltime = $$last_rec;
        if ( $t > $ltime ) {    #&& length($vios_name) > 0 )
          if ( !( main::isdigit($read) ) )                   { $read                   = "U"; }
          if ( !( main::isdigit($io_read) ) )                { $io_read                = "U"; }
          if ( !( main::isdigit($io_write) ) )               { $io_write               = "U"; }
          if ( !( main::isdigit($write) ) )                  { $write                  = "U"; }
          if ( !( main::isdigit($droppedReceivedPackets) ) ) { $droppedReceivedPackets = "U"; }
          if ( !( main::isdigit($droppedSentPackets) ) )     { $droppedSentPackets     = "U"; }
          if ( !( main::isdigit($errorIn) ) )                { $errorIn                = "U"; }
          if ( !( main::isdigit($errorOut) ) )               { $errorOut               = "U"; }

          #print "updating $rrd from jsons\n";
          RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write:$droppedReceivedPackets:$droppedSentPackets:$errorIn:$errorOut);

          $last_time = $ts;
          my $answer = RRDp::read;

          # update the time of last record
          $ltime = $t;
        }
      }

      #$reversed_sriov->{$ts}{$lpar}{$physLoc}{configurationType} = $configurationType;

=cut
      foreach my $timestamp (sort keys %{$content}){
        foreach my $lpar (sort keys %{$content->{$timestamp}}){
          foreach my $physLoc (keys %{$content->{$timestamp}{$lpar}}){
          my $ltime            = 0;
          my $rrd_exist_ok     = 0;
          my $rrd_exist_ok_max = 0;
          my ($configurationType,$drcIndex,$droppedReceivedPackets,$droppedSentPackets,$errorIn,$errorOut,$physicalDrcIndex,$physicalPortId,$read ,$io_read,$write,$io_write,$vnicDeviceMode);
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{configurationType}){$configurationType = $content->{$timestamp}{$lpar}{$physLoc}{configurationType};}
          else {$configurationType = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{drcIndex}){$drcIndex = $content->{$timestamp}{$lpar}{$physLoc}{drcIndex};}
          else {$drcIndex = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{droppedReceivedPackets}){$droppedReceivedPackets = $content->{$timestamp}{$lpar}{$physLoc}{droppedReceivedPackets};}
          else {$droppedReceivedPackets = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{droppedSentPackets}){$droppedSentPackets = $content->{$timestamp}{$lpar}{$physLoc}{droppedSentPackets};}
          else {$droppedSentPackets = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{errorIn}){$errorIn = $content->{$timestamp}{$lpar}{$physLoc}{errorIn};}
          else {$errorIn = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{errorOut}){$errorOut = $content->{$timestamp}{$lpar}{$physLoc}{errorOut};}
          else {$errorOut = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{physicalDrcIndex}){$physicalDrcIndex = $content->{$timestamp}{$lpar}{$physLoc}{physicalDrcIndex};}
          else {$physicalDrcIndex = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{physicalPortId}){$physicalPortId = $content->{$timestamp}{$lpar}{$physLoc}{physicalPortId};}
          else {$physicalPortId = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{receivedBytes}){$read = $content->{$timestamp}{$lpar}{$physLoc}{receivedBytes};}
          else {$read = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{receivedPackets}){$io_read = $content->{$timestamp}{$lpar}{$physLoc}{receivedPackets};}
          else {$io_read = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{sentBytes}){$write = $content->{$timestamp}{$lpar}{$physLoc}{sentBytes};}
          else {$write = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{sentBytes}){$io_write = $content->{$timestamp}{$lpar}{$physLoc}{sentPackets};}
          else {$io_write = "U";}
          if (defined $content->{$timestamp}{$lpar}{$physLoc}{vnicDeviceMode}){$vnicDeviceMode = $content->{$timestamp}{$lpar}{$physLoc}{vnicDeviceMode};}
          else {$vnicDeviceMode = "U";}
          my $testing_out = "$lpar $physLoc $configurationType $drcIndex $droppedReceivedPackets $droppedSentPackets $errorIn $errorOut $physicalDrcIndex $physicalPortId, $read $io_read $write $io_write  $vnicDeviceMode\n";
        my $ret = substr( $timestamp, 0, 1 );
        if ( $ret =~ /\D/ ) {
          # leave it as wrong input data
          main::error( "$host:$managedname : No valid lpars data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
          next;
        } ## end if ( $ret =~ /\D/ )
        my $t = str2time( substr( $timestamp, 0, 19 ) );
        if ( length($t) < 10 ) {
          # leave it as wrong input data
          main::error( "$host:$managedname : No valid lpars data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
          next;
        } ## end if ( length($t) < 10 )
        if ( $step == 3600 ) {
          # Put on the last time possition "00"!!!
          substr( $t, 8, 2, "00" );
        }
        my $dirname_tmp = "$wrkdir/$managedname/$host/iostat/";
        (undef,undef,my $short_physloc) = split ('\\.', $physLoc);
        $short_phys_loc = "" if (!defined  $short_physloc);
        $rrd     = "$wrkdir/$managedname/$host/adapters/$short_physloc.rasr$type_sam"; #m;
        if (!(-e $rrd)){
          if ( $rrd_exist_ok == 0 ) {
            my $ret = create_rrd_sriov2( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
            if ( $ret == 2 ) {
              #print "parametry: $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time\n";
              next; # muj test????
              #return 1;    # RRD creation problem, skip whole load
            }
            $rrd_exist_ok = 1;
          }## end if ( $rrd_exist_ok == ...)
        } #end if (!(-e $rrd))
        if ( $ltime == 0 ) {

          # construction against crashing daemon Perl code when RRDTool error appears
          # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
         # construction is not too costly as it runs once per each load
          my $last_rec = 0;
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;
          };
          if ($@) {
           #RRDp::error_mode = "catch";
            rrd_error( $@, $rrd );
            $rrd_exist_ok = 0;
            next;
          }
          chomp($$last_rec);
          $ltime = $$last_rec;
        } ## end if ( $ltime == 0 )
        # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
        if ( $t > $ltime ) { #&& length($vios_name) > 0 )
          my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
          if ( $t > $jump_time ) {

            # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
            # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
            if ( $jump == 0 ) {
              $jump = 1;
              #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
              #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
              next;
            } ## end if ( $jump == 0 )
            # looks like it is ok as it is second timestap in a row
          } ## end if ( $t > $jump_time )
          $jump = 0;
          $counter_ins++;
          #RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write);
          if (!(main::isdigit($read))){ $read = "U"; }
          if (!(main::isdigit($io_read))){ $io_read = "U"; }
          if (!(main::isdigit($io_write))){ $io_write = "U"; }
          if (!(main::isdigit($write))){ $write = "U"; }
          if (!(main::isdigit($droppedReceivedPackets))){ $droppedReceivedPackets = "U"; }
          if (!(main::isdigit($droppedSentPackets))){ $droppedSentPackets = "U"; }
          if (!(main::isdigit($errorIn))){ $errorIn = "U"; }
          if (!(main::isdigit($errorOut))){ $errorOut = "U"; }
          #print "updating $rrd from jsons\n";
          RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write:$droppedReceivedPackets:$droppedSentPackets:$errorIn:$errorOut);

          $last_time = $timestamp;
          my $answer = RRDp::read;
          # update the time of last record
          $ltime = $t;
        } ## end if ( $t > $ltime && length...)
      } ##end foreach my physloc
    } ## end foreach my lpar
    } ## end foreach my timestamp
=cut

      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || print( "Cannot delete file $path " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
    }
  }
  else {
    if ( -e "$input_sriov-$type_sam" ) {
      open( FH, "< $input_sriov-$type_sam" ) || main::error( " Can't open $input_sriov-$type_sam : $!" . __FILE__ . ":" . __LINE__ );
    }
    else {
      #main::error( " File doesn't exist $input_sriov-$type_sam : $! " . __FILE__ . ":" . __LINE__ );
      return 1;
    }
    my @lines = <FH>;
    close(FH);
    foreach my $line (@lines) {
      my $ltime            = 0;
      my $rrd_exist_ok     = 0;
      my $rrd_exist_ok_max = 0;
      chomp($line);
      ( $time, my $lpar, my $physicalLocation, my $confType, my $drcIndex, my $droppedReceivedPackets, my $droppedSentPackets, my $errorIn, my $errorOut, my $physicalDrcIndex, my $physicalPortId, my $read, my $io_read, my $write, my $io_write, my $vnicDeviceMode ) = split( /,/, $line );
      my $ret = substr( $time, 0, 1 );
      if ( $ret =~ /\D/ ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid sriov data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      my $t = str2time( substr( $time, 0, 19 ) );
      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid sriov data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );
      }
      my $dirname_tmp = "$wrkdir/$managedname/$host/adapters/";
      ( undef, undef, my $short_physloc ) = split( '\\.', $physicalLocation );
      $short_physloc = "" if (!defined $short_physloc);
      $rrd = "$wrkdir/$managedname/$host/adapters/$short_physloc.rasr$type_sam";

      #create rrd db if necessary
      if ( !( -e $rrd ) ) {
        if ( $rrd_exist_ok == 0 ) {
          my $ret = create_rrd_sriov2( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
          if ( $ret == 2 ) {
            return 1;    # RRD creation problem, skip whole load
          }
          $rrd_exist_ok = 1;
        }
      }

      if ( $ltime == 0 ) {

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        my $last_rec = 0;
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          $rrd_exist_ok = 0;
          next;
        }
        chomp($$last_rec);
        $ltime = $$last_rec;
      }

      # print "last sriov : $ltime  actuall: $t\n";
      # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
      if ( $t > $ltime ) {    #&& length($vios_name) > 0 )
        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $jump == 0 ) {
            $jump = 1;

            #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
            #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            next;
          }

          # looks like it is ok as it is second timestap in a row
        }
        $jump = 0;
        $counter_ins++;

        #print "$counter_ins : $time $t:$promenne \n"    if (!(main::isdigit($read))){ $read = "U"; }
        if ( !( main::isdigit($io_read) ) )                { $io_read                = "U"; }
        if ( !( main::isdigit($io_write) ) )               { $io_write               = "U"; }
        if ( !( main::isdigit($write) ) )                  { $write                  = "U"; }
        if ( !( main::isdigit($read) ) )                   { $read                   = "U"; }
        if ( !( main::isdigit($droppedReceivedPackets) ) ) { $droppedReceivedPackets = "U"; }
        if ( !( main::isdigit($droppedSentPackets) ) )     { $droppedSentPackets     = "U"; }
        if ( !( main::isdigit($errorIn) ) )                { $errorIn                = "U"; }
        if ( !( main::isdigit($errorOut) ) )               { $errorOut               = "U"; }
        RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write:$droppedReceivedPackets:$droppedSentPackets:$errorIn:$errorOut);
        $last_time = $time;
        my $answer = RRDp::read;

        # update the time of last record
        $ltime = $t;
      }
    }
  }    ##end else (if $jsonconfigured)

  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:sriov $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}    # end sub load_data_sriov

sub load_data_lan {
  my $LLL;
  my $time        = "";
  my $counter     = 0;
  my $counter_tot = 0;
  my $counter_ins = 0;
  my $rrd         = "";
  my $rrd_max     = "";
  my $utime       = time() + 3600;
  my $jump        = 0;
  my $last_time   = "";

  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_adapters, $no_time, $json_configured, $save_files, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
  if ( $json_configured eq "1" ) {
    my $perf_string = "lan_perf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;
    ##001 PUVODNI CAST KODU ##
    ##open (FH, "< $input_file-$type_sam") || main::error( " Can't open $input_file-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    ##my @lines = reverse <FH>;
    ##close(FH);
    ## END 001###

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.lan" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.lan" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.lan at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path    = "$iostatdir$file";
      my $content = [];
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) eq "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        next;
      }
      foreach my $sample ( @{$content} ) {
        ( my $ts, my $vios_name, my $adapter_id, my $physicalLocation, my $type, my $io_read, my $io_write, my $read, my $write, my $dropped_packets ) = ( "U", "U", "U", "U", "U", "U", "U", "U", "U", "U" );
        $ts               = $sample->[0];
        $vios_name        = $sample->[1];
        $adapter_id       = $sample->[2];
        $type             = $sample->[3];
        $dropped_packets  = $sample->[4];
        $io_write         = $sample->[5];
        $io_read          = $sample->[6];
        $write            = $sample->[7];
        $read             = $sample->[8];
        $physicalLocation = $sample->[9];
        my $t = str2time( substr( $ts, 0, 19 ) );
        $temp_ts = $t;

        ( undef, undef, my $short_physloc ) = split( '\\.', $physicalLocation );
        $short_physloc = "" if (!defined $short_physloc);
        $rrd = "$wrkdir/$managedname/$host/adapters/$short_physloc.ral$type_sam";

        my $last_rec;
        my $ltime;

        if (!defined $LLL->{$rrd}{last_update}){
          if ( !-e ($rrd) ) {
            my $ret = create_rrd_lan( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
            if ( $ret == 2 ) {
              next;
            }
          }
        }
        if (!defined $LLL->{$rrd}{last_update}){
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;
          };
          if ($@) {
            rrd_error( $@, $rrd );
            next;
          }
          chomp($$last_rec);
          $ltime = $$last_rec;
          $LLL->{$rrd}{last_update} = $$last_rec;
        }
        if ( $t > $LLL->{$rrd}{last_update} ) {    #&& length($vios_name) > 0 )
          if ( !( main::isdigit($io_read) ) )         { $io_read         = "U"; }
          if ( !( main::isdigit($read) ) )            { $read            = "U"; }
          if ( !( main::isdigit($io_write) ) )        { $io_write        = "U"; }
          if ( !( main::isdigit($write) ) )           { $write           = "U"; }
          if ( !( main::isdigit($dropped_packets) ) ) { $dropped_packets = "U"; }
          RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write:$dropped_packets);
          $last_time = $ts;
          my $answer = RRDp::read;
          $ltime = $t;
          $LLL->{$rrd}{last_update} = $t;
        }
      }

      open( $ltiph, ">", "$wrkdir/$managedname/$host/iostat/last_ts.lan" );
      print $ltiph "$temp_ts";
      close($ltiph);
      if ( defined $file && defined $files[-1] && defined $files[-2] ) {
        if ( $file eq $files[-1] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/lan_perf1" );
        }
        if ( $file eq $files[-2] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/lan_perf2" );
        }
      }
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
    }    #end foreach my $file
  }    #end if (json configured)
  else {
    if ( -e "$input_adapters-$type_sam" ) {
      open( FH, "< $input_adapters-$type_sam" ) || main::error( " Can't open $input_adapters-$type_sam : $!" . __FILE__ . ":" . __LINE__ );
    }
    else {
      #main::error( " File doesn't exist $input_adapters-$type_sam : $! " . __FILE__ . ":" . __LINE__ );
      return 1;
    }
    my @lines = reverse <FH>;
    close(FH);
    foreach my $line (@lines) {
      my $ltime            = 0;
      my $rrd_exist_ok     = 0;
      my $rrd_exist_ok_max = 0;

      #12/11/2017 12:11:30,vios-770,ent0,U78C0.001.DBJB578-P2-C1-T1,45548556957,51573237,13209643948,20294831,0,physical
      chomp($line);

      #print "$line\n";
      ( $time, my $vios_name, my $id, my $physicalLocation, my $read, my $io_read, my $write, my $io_write, my $droppedPackets, my $type ) = split( /,/, $line );
      my $ret = substr( $time, 0, 1 );
      if ( $ret =~ /\D/ ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid adapters data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      my $t = str2time( substr( $time, 0, 19 ) );
      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid adapters data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );
      }
      ( undef, undef, my $short_physloc ) = split( '\\.', $physicalLocation );
      $short_physloc = "" if (!defined $short_physloc);
      $rrd = "$wrkdir/$managedname/$host/adapters/$short_physloc.ral$type_sam";
      my $dirname_tmp = "$wrkdir/$managedname/$host/adapters/";

      #create rrd db if necessary
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd_lan( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist_ok = 1;
      }

      if ( $ltime == 0 ) {

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        my $last_rec = 0;
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          $rrd_exist_ok = 0;
          next;
        }
        chomp($$last_rec);
        $ltime = $$last_rec;
      }

      # print "last adapter : $ltime  actuall: $t\n";
      # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
      if ( $t > $ltime ) {    #&& length($vios_name) > 0 ) {
        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $jump == 0 ) {
            $jump = 1;

            #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
            #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            next;
          }

          # looks like it is ok as it is second timestap in a row
        }
        $jump = 0;
        $counter_ins++;

        #print "$counter_ins : $time $t:$promenne \n";
        if ( !( main::isdigit($write) ) )          { $write          = "U"; }
        if ( !( main::isdigit($io_write) ) )       { $io_write       = "U"; }
        if ( !( main::isdigit($read) ) )           { $read           = "U"; }
        if ( !( main::isdigit($io_read) ) )        { $io_read        = "U"; }
        if ( !( main::isdigit($droppedPackets) ) ) { $droppedPackets = "U"; }
        RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write:$droppedPackets);
        $last_time = $time;
        my $answer = RRDp::read;

        # update the time of last record
        $ltime = $t;
      }
    }

    if ( $counter_ins > 0 ) {
      print "inserted       : $host:$managedname:adapters $counter_ins record(s)\n" if $DEBUG;
    }
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_gpa {
  my $GPA;
  my $time        = "";
  my $counter     = 0;
  my $counter_tot = 0;
  my $counter_ins = 0;
  my $rrd         = "";
  my $rrd_max     = "";
  my $utime       = time() + 3600;
  my $jump        = 0;
  my $last_time   = "";

  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_gpa, $no_time, $json_configured, $save_files, $hmc_timezone, $local_timezone ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
  if ( $json_configured eq "1" ) {
    my $perf_string = "gpa_perf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.gpa" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.gpa" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.gpa at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path    = "$iostatdir$file";
      my $content = [];
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) eq "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        next;
      }
      foreach my $sample ( @{$content} ) {
        ( my $ts, my $vios_name, my $adapter_id, my $physicalLocation, my $type, my $io_read, my $io_write, my $read, my $write ) = ( "U", "U", "U", "U", "U", "U", "U", "U", "U" );
        $ts               = $sample->[0];
        $vios_name        = $sample->[1];
        $adapter_id       = $sample->[2];
        $physicalLocation = $sample->[3];
        $type             = $sample->[4];
        $io_read          = $sample->[5];
        $io_write         = $sample->[6];
        $read             = $sample->[7];
        $write            = $sample->[8];
        my $t = str2time( substr( $ts, 0, 19 ) );
        $temp_ts = $t;

        ( undef, undef, my $short_physloc ) = split( '\\.', $physicalLocation );
        $short_physloc = "" if (!defined $short_physloc);
        $rrd = "$wrkdir/$managedname/$host/adapters/$short_physloc.rap$type_sam";
        if (!defined $GPA->{$rrd}{last_update}){
          if ( !-e ($rrd) ) {
            my $ret = create_rrd_gpa( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
            if ( $ret == 2 ) {
              next;
            }
          }
        }
        my $last_rec;
        my $ltime;
        if (!defined $GPA->{$rrd}{last_update}){
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;
          };
          if ($@) {
            rrd_error( $@, $rrd );
            next;
          }
          chomp($$last_rec);
          $ltime = $$last_rec;
          $GPA->{$rrd}{last_update} = $$last_rec;
        }
        if ( $t > $GPA->{$rrd}{last_update} ) {    #&& length($vios_name) > 0 )
          if ( !( main::isdigit($io_read) ) )  { $io_read  = "U"; }
          if ( !( main::isdigit($read) ) )     { $read     = "U"; }
          if ( !( main::isdigit($io_write) ) ) { $io_write = "U"; }
          if ( !( main::isdigit($write) ) )    { $write    = "U"; }
          RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write);
          $last_time = $ts;
          my $answer = RRDp::read;
          $ltime = $t;
          $GPA->{$rrd}{last_update} = $t;
        }
      }

      ##unlink ($path) || print("Cannot delete file $path ". __FILE__. ":". __LINE__);
      if ( defined $file && defined $files[-1] && defined $files[-2] ) {
        if ( $file eq $files[-1] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/gpa_perf1" );
        }
        if ( $file eq $files[-2] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/gpa_perf2" );
        }
      }
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      open( $ltiph, ">", "$wrkdir/$managedname/$host/iostat/last_ts.gpa" );
      print $ltiph "$temp_ts";
      close($ltiph);
    }    #end foreach my $file
  }    #end if (json configured)
  else {
    if ( -e "$input_gpa-$type_sam" ) {
      open( FH, "< $input_gpa-$type_sam" ) || main::error( " Can't open $input_gpa-$type_sam : $!" . __FILE__ . ":" . __LINE__ );
    }
    else {
      #main::error( " File doesn't exist $input_gpa-$type_sam : $! " . __FILE__ . ":" . __LINE__ );
      return 1;
    }
    my @lines = reverse <FH>;
    close(FH);
    foreach my $line (@lines) {
      my $ltime            = 0;
      my $rrd_exist_ok     = 0;
      my $rrd_exist_ok_max = 0;
      chomp($line);
      ( $time, my $vios_name, my $id, my $physicalLocation, my $io_read, my $io_write, my $read, my $write ) = split( /,/, $line );
      my $ret = substr( $time, 0, 1 );
      if ( $ret =~ /\D/ ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid adapters data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      my $t = str2time( substr( $time, 0, 19 ) );
      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid adapters data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );
      }
      my $dirname_tmp = "$wrkdir/$managedname/$host/adapters/";
      ( undef, undef, my $short_physloc ) = split( '\\.', $physicalLocation );
      $short_physloc = "" if (!defined $short_physloc);
      $rrd = "$wrkdir/$managedname/$host/adapters/$short_physloc.rap$type_sam";

      #create rrd db if necessary
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd_gpa( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist_ok = 1;
      }

      if ( $ltime == 0 ) {

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        my $last_rec = 0;
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          $rrd_exist_ok = 0;
          next;
        }
        chomp($$last_rec);
        $ltime = $$last_rec;
      }

      # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
      if ( $t > $ltime ) {    #&& length($vios_name) > 0 ) {
        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $jump == 0 ) {
            $jump = 1;

            #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
            #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            next;
          }

          # looks like it is ok as it is second timestap in a row
        }
        $jump = 0;
        $counter_ins++;

        #print "$counter_ins : $time $t:$promenne \n";

        #RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write);
        if ( !( main::isdigit($io_read) ) )  { $io_read  = "U"; }
        if ( !( main::isdigit($read) ) )     { $read     = "U"; }
        if ( !( main::isdigit($io_write) ) ) { $io_write = "U"; }
        if ( !( main::isdigit($write) ) )    { $write    = "U"; }
        RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write);

        $last_time = $time;
        my $answer = RRDp::read;

        # update the time of last record
        $ltime = $t;
      }
    }
    if ( $counter_ins > 0 ) {
      print "inserted       : $host:$managedname:fiber_channel_adapters $counter_ins record(s)\n" if $DEBUG;
    }
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_fcs {
  my $FCS;
  my $time        = "";
  my $counter     = 0;
  my $counter_tot = 0;
  my $counter_ins = 0;
  my $rrd         = "";
  my $rrd_max     = "";
  my $utime       = time() + 3600;
  my $jump        = 0;
  my $last_time   = "";

  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_fcs, $no_time, $json_configured, $save_files, $hmc_timezone, $local_timezone ) = @_;
  if ( $json_configured == 1 ) {
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if (!defined $hmc_timezone) { $hmc_timezone = ""; }
  if (!defined $local_timezone) { $local_timezone = ""; }
    my $perf_string = "san_perf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ );

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.fcs" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.fcs" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.fcs at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
      my $datestring = localtime();
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path    = "$iostatdir$file";
      my $content = [];
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) eq "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        next;
      }
      my $temp_ts;
      foreach my $sample ( @{$content} ) {
        my $ts            = $sample->[0];
        my $lpar          = $sample->[1];
        my $fcs           = $sample->[2];
        my $loc           = $sample->[3];
        my $io_read       = $sample->[4];
        my $io_write      = $sample->[5];
        my $read          = $sample->[6];
        my $write         = $sample->[7];
        my $running_speed = $sample->[8];
        my $wwpn          = $sample->[9];
        my $t             = str2time( substr( $ts, 0, 19 ) );
        $temp_ts = $t;
        ( undef, undef, my $short_physloc ) = split( '\\.', $loc );
        $short_physloc = "" if (!defined $short_physloc);
        $rrd = "$wrkdir/$managedname/$host/adapters/$short_physloc.ras$type_sam";    #m;
        if (!defined $FCS->{$rrd}{last_update}){
          if ( !-e $rrd ) {
            my $ret = create_rrd_fcs( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
            if ( $ret == 2 ) {
              next;
            }
          }
        }
        my $last_rec;
        my $ltime;
        if (!defined $FCS->{$rrd}{last_update}){
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;
          };
          if ($@) {
            rrd_error( $@, $rrd );
            next;
          }
          chomp($$last_rec);
          $ltime = $$last_rec;
          $FCS->{$rrd}{last_update} = $$last_rec;
        }
        if ( $t > $FCS->{$rrd}{last_update} ) {    #&& length($vios_name) > 0 )
          if ( !( main::isdigit($io_read) ) )       { $io_read       = "U"; }
          if ( !( main::isdigit($read) ) )          { $read          = "U"; }
          if ( !( main::isdigit($io_write) ) )      { $io_write      = "U"; }
          if ( !( main::isdigit($write) ) )         { $write         = "U"; }
          if ( !( main::isdigit($running_speed) ) ) { $running_speed = "U"; }
          RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write:$running_speed);
          $last_time = $ts;
          my $answer = RRDp::read;
          $ltime = $t;
          $FCS->{$rrd}{last_update} = $t;
        }
      }

      ##unlink ($path) || print("Cannot delete file $path ". __FILE__. ":". __LINE__);
      if ( defined $file && defined $files[-1] && defined $files[-2] ) {
        if ( $file eq $files[-1] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/san_perf1" );
        }
        if ( $file eq $files[-2] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/san_perf2" );
        }
      }
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      open( $ltiph, ">", "$wrkdir/$managedname/$host/iostat/last_ts.fcs" );
      print $ltiph "$temp_ts";
      close($ltiph);
    }
  }
  else {
    if ( -e "$input_fcs-$type_sam" ) {
      open( FH, "< $input_fcs-$type_sam" ) || main::error( " Can't open $input_fcs-$type_sam : $!" . __FILE__ . ":" . __LINE__ );
    }
    else {
      #main::error( " File doesn't exist $input_fcs-$type_sam : $! " . __FILE__ . ":" . __LINE__ );
      return 1;
    }
    my @lines = reverse <FH>;
    close(FH);
    foreach my $line (@lines) {
      my $ltime            = 0;
      my $rrd_exist_ok     = 0;
      my $rrd_exist_ok_max = 0;

      #12/11/2017 12:11:30,vios-770,ent0,U78C0.001.DBJB578-P2-C1-T1,45548556957,51573237,13209643948,20294831,0,physical
      chomp($line);
      ( $time, my $vios_name, my $id, my $physicalLocation, my $io_read, my $io_write, my $read, my $write, my $running_speed, my $type ) = split( /,/, $line );
      my $ret = substr( $time, 0, 1 );
      if ( $ret =~ /\D/ ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid adapters data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      my $t = str2time( substr( $time, 0, 19 ) );
      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid adapters data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );
      }
      my $dirname_tmp = "$wrkdir/$managedname/$host/adapters/";
      ( undef, undef, my $short_physloc ) = split( '\\.', $physicalLocation );
      $short_physloc = "" if (!defined $short_physloc);
      $rrd = "$wrkdir/$managedname/$host/adapters/$short_physloc.ras$type_sam";

      #create rrd db if necessary
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd_fcs( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist_ok = 1;
      }

      if ( $ltime == 0 ) {

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        my $last_rec = 0;
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          $rrd_exist_ok = 0;
          next;
        }
        chomp($$last_rec);
        $ltime = $$last_rec;
      }

      # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
      if ( $t > $ltime ) {    #&& length($vios_name) > 0 ) {
        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $jump == 0 ) {
            $jump = 1;

            #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
            #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            next;
          }

          # looks like it is ok as it is second timestap in a row
        }
        $jump = 0;
        $counter_ins++;

        #print "$counter_ins : $time $t:$promenne \n";
        if ( !( main::isdigit($io_read) ) )       { $io_read       = "U"; }
        if ( !( main::isdigit($read) ) )          { $read          = "U"; }
        if ( !( main::isdigit($io_write) ) )      { $io_write      = "U"; }
        if ( !( main::isdigit($write) ) )         { $write         = "U"; }
        if ( !( main::isdigit($running_speed) ) ) { $running_speed = "U"; }
        RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write:$running_speed);
        $last_time = $time;
        my $answer = RRDp::read;

        # update the time of last record
        $ltime = $t;
      }
    }
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:fiber_channel_adapters $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub load_data_json_lpars_all {
  my $time        = "";
  my $counter     = 0;
  my $counter_tot = 0;
  my $counter_ins = 0;
  my $rrd         = "";
  my $rrd_max     = "";
  my $utime       = time() + 3600;
  my $jump        = 0;
  my $last_time   = "";

  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_file, $no_time, $grep_string, $json_configured, $save_files, $hmc_timezone ) = @_;
  my $perf_string = $grep_string;

  #my $perf_string = "lpars_perf";
  my $iostatdir = "$wrkdir/$managedname/$host/iostat/";
  opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

  my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
  my @files          = reverse sort { lc $a cmp lc $b } @files_unsorted;
  ##001 PUVODNI CAST KODU ##
  ##open (FH, "< $input_file-$type_sam") || main::error( " Can't open $input_file-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  ##my @lines = reverse <FH>;
  ##close(FH);
  ## END 001###

  #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
  #foreach my $line (@lines) {
  foreach my $file (@files) {
    if ( Xorux_lib::file_time_diff($file) > 3600 ) { next; }
    my $datestring = localtime();
    print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
    my $path    = "$iostatdir$file";
    my $content = {};
    $content = Xorux_lib::read_json($path) if ( -e $path );
    if ( !defined $content || $content eq "-1" || ref($content) eq "HASH" ) {
      print "$file is not valid : $content\n";
      unlink($path);
      next;
    }
    foreach my $timestamp ( reverse sort keys %{$content} ) {
      foreach my $lpar ( sort keys %{ $content->{$timestamp} } ) {
        my $curr_proc_units            = 0;
        my $curr_procs                 = 0;
        my $phys_run_mem               = 0;
        my $curr_io_entitled_mem       = 0;
        my $mapped_io_mem              = 0;
        my $entitledProcCycles         = 0;
        my $donatedProcCycles          = 0;
        my $mode                       = 0;
        my $idleProcCycles             = 0;
        my $utilizedUnCappedProcCycles = 0;
        my $utilizedCappedProcCycles   = 0;

        my $memory = $content->{$timestamp}{$lpar}{'memory'};
        if ( defined $memory->{'curr_io_entitled_mem'} ) { $curr_io_entitled_mem = $memory->{'curr_io_entitled_mem'}; }
        if ( defined $memory->{'mapped_io_mem'} )        { $mapped_io_mem        = $memory->{'mapped_io_mem'}; }
        if ( defined $memory->{'phys_run_mem'} )         { $phys_run_mem         = $memory->{'phys_run_mem'}; }

        my $processor = $content->{$timestamp}{$lpar}{'processor'};
        if   ( defined $processor->{'entitledProcCycles'} ) { $entitledProcCycles = $processor->{'entitledProcCycles'}; }
        else                                                { $entitledProcCycles = "U" }
        if   ( defined $processor->{'donatedProcCycles'} ) { $donatedProcCycles = $processor->{'donatedProcCycles'}; }
        else                                               { $donatedProcCycles = "U" }
        if   ( defined $processor->{'mode'} )       { $mode       = $processor->{'mode'}; }
        if   ( defined $processor->{'curr_procs'} ) { $curr_procs = $processor->{'curr_procs'}; }
        else                                        { $curr_procs = "U" }
        if   ( defined $processor->{'curr_proc_units'} ) { $curr_proc_units = $processor->{'curr_proc_units'}; }
        else                                             { $curr_proc_units = "U" }
        if   ( defined $processor->{'idleProcCycles'} ) { $idleProcCycles = $processor->{'idleProcCycles'}; }
        else                                            { $idleProcCycles = "U" }
        if   ( defined $processor->{'utilizedUnCappedProcCycles'} ) { $utilizedUnCappedProcCycles = $processor->{'utilizedUnCappedProcCycles'}; }
        else                                                        { $utilizedUnCappedProcCycles = "U" }
        if   ( defined $processor->{'utilizedCappedProcCycles'} ) { $utilizedCappedProcCycles = $processor->{'utilizedCappedProcCycles'}; }
        else                                                      { $utilizedCappedProcCycles = "U" }

        ###( $time, $lpar, $curr_proc_units, $curr_procs, $curr_sharing_mode, $entitled_cycles, $capped_cycles, $uncapped_cycles, $shared_cycles_while_active, $mem_mode, $curr_mem, $phys_ru     n_mem, $curr_io_entitled_mem, $mapped_io_entitled_mem, $mem_overage_cooperation, $idle_cycles ) = split( /,/, $line );
        #TU
        my $testing_out = "$timestamp, $lpar, $curr_proc_units, $curr_procs,$mode,$entitledProcCycles,$utilizedCappedProcCycles,$utilizedUnCappedProcCycles,'shared_cycles_while_active','m     em_mode','curr_mem',$phys_run_mem,$curr_io_entitled_mem,$mapped_io_mem,'mem_overage_cooperation',$idleProcCycles";

        my $ltime            = 0;
        my $rrd_exist_ok     = 0;
        my $rrd_exist_ok_max = 0;
        my $ret              = substr( $timestamp, 0, 1 );
        if ( $ret =~ /\D/ ) {

          # leave it as wrong input data
          main::error( "$host:$managedname : No valid lpars data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
          next;
        }
        my $t = str2time( substr( $timestamp, 0, 19 ) );
        if ( length($t) < 10 ) {

          # leave it as wrong input data
          main::error( "$host:$managedname : No valid lpars data got from HMC :$ret : $testing_out " . __FILE__ . ":" . __LINE__ );
          next;
        }
        if ( $step == 3600 ) {

          # Put on the last time possition "00"!!!
          substr( $t, 8, 2, "00" );
        }
        my $dirname_tmp = "$wrkdir/$managedname/$host/iostat/";
        $lpar =~ s/\//\&\&1/g;
        $rrd = "$wrkdir/$managedname/$host/$lpar.rrj";    #type_sam;

        #create rrd db if necessary
        if ( !( -e $rrd ) ) {
          if ( $rrd_exist_ok == 0 ) {

            #my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
            #my $ret = create_rrd( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, $SSH, $hmc_user, $wrkdir, $lpar, $t, $keep_virtual );
            if ( $ret == 2 ) {
              next;    # muj test????
                       #return 1;    # RRD creation problem, skip whole load
            }
            $rrd_exist_ok = 1;
          }
        }

        if ( $ltime == 0 ) {

          # construction against crashing daemon Perl code when RRDTool error appears
          # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
          # construction is not too costly as it runs once per each load
          my $last_rec = 0;
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;
          };
          if ($@) {

            #RRDp::error_mode = "catch";
            rrd_error( $@, $rrd );
            $rrd_exist_ok = 0;
            next;
          }
          chomp($$last_rec);
          $ltime = $$last_rec;
        }

        # print "last adapter : $ltime  actuall: $t\n";
        # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
        if ( $t > $ltime ) {    #&& length($vios_name) > 0 ) {
          my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
          if ( $t > $jump_time ) {

            # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
            # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
            if ( $jump == 0 ) {
              $jump = 1;

              #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
              #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
              next;
            }
                # looks like it is ok as it is second timestap in a row
          }
          $jump = 0;
          $counter_ins++;
          if ( !( main::isdigit($curr_proc_units) ) )            { $curr_proc_units            = "U"; }
          if ( !( main::isdigit($curr_procs) ) )                 { $curr_procs                 = "U"; }
          if ( !( main::isdigit($entitledProcCycles) ) )         { $entitledProcCycles         = "U"; }
          if ( !( main::isdigit($utilizedCappedProcCycles) ) )   { $utilizedCappedProcCycles   = "U"; }
          if ( !( main::isdigit($utilizedUnCappedProcCycles) ) ) { $utilizedUnCappedProcCycles = "U"; }
          RRDp::cmd qq(update "$rrd" $t:$curr_proc_units:$curr_procs:$entitledProcCycles:$utilizedCappedProcCycles:$utilizedUnCappedProcCycles);
          my $answer = RRDp::read;
          my $rvm    = $rrd;
          $rvm =~ s/rrm/rvm/g;

          RRDp::cmd qq(update "$rvm" $t:$curr_procs);
          $answer    = RRDp::read;
          $last_time = $timestamp;

          # update the time of last record
          $ltime = $t;
        }
            #} ## end foreach my $line (@lines)
      }
    }
    if ( $save_files == 0 ) {
      unlink($path) || print( "Cannot delete file $path " . __FILE__ . ":" . __LINE__ );
    }
  }    #end foreach my $file(@files)

  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:lpars $counter_ins record(s)\n" if $DEBUG;
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }
  return 0;
}

sub create_rrd_cod {
  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;

  #my $no_time_new = $no_time;
  my $no_time_new = $step_new;

  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!

  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_cod : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_cod $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:used_proc_min:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:unreported_proc_min:GAUGE:$no_time_new:-100000000000:100000000000"
          "RRA:AVERAGE:0.1:1:10000"
          "RRA:AVERAGE:0.1:24:1000"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 10000, 1000") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:used_proc_min:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:unreported_proc_min:GAUGE:$no_time_new:-100000000000:100000000000"
          "RRA:AVERAGE:0.1:1:1825"
          "RRA:AVERAGE:0.1:7:260"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 1825, 260") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_cod : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_cod $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:used_proc_min:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:unreported_proc_min:GAUGE:$no_time_new:-100000000000:100000000000"
          "RRA:AVERAGE:0.1:1:$one_minute_sample"
          "RRA:AVERAGE:0.1:24:$one_hour_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $one_hour_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:used_proc_min:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:unreported_proc_min:GAUGE:$no_time_new:-100000000000:100000000000"
          "RRA:AVERAGE:0.1:1:$one_minute_sample"
          "RRA:AVERAGE:0.1:60:$one_hour_sample"
          "RRA:AVERAGE:0.1:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $one_hour_sample, $one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_lpar_mem_ded {
  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!

  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_mem_lpar: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_lpar_mem_ded $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:curr_mem:GAUGE:$no_time_new:0:10000000"
          "RRA:AVERAGE:0.5:1:10000"
          "RRA:AVERAGE:0.5:6:1500"
          "RRA:AVERAGE:0.5:24:1000"
          "RRA:AVERAGE:0.5:288:1000"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:curr_mem:GAUGE:$no_time_new:0:10000000"
          "RRA:AVERAGE:0.5:1:1825"
          "RRA:AVERAGE:0.5:7:260"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 1825, 260") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
                                              #print "0000 $one_minute_sample - $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "create_mem_lpar: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_lpar_mem_ded $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:curr_mem:GAUGE:$no_time_new:0:10000000"
          "RRA:AVERAGE:0.5:1:$one_minute_sample_mem"
          "RRA:AVERAGE:0.5:6:$five_mins_sample_mem"
          "RRA:AVERAGE:0.5:24:$one_hour_sample_mem"
          "RRA:AVERAGE:0.5:288:$five_hours_sample_mem"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample_mem, $five_mins_sample_mem, $one_hour_sample_mem, $five_hours_sample_mem") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        #print "++ $rrd $start_time $step_new\n";
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:curr_mem:GAUGE:$no_time_new:0:10000000"
          "RRA:AVERAGE:0.5:1:$one_minute_sample_mem"
          "RRA:AVERAGE:0.5:5:$five_mins_sample_mem"
          "RRA:AVERAGE:0.5:60:$one_hour_sample_mem"
          "RRA:AVERAGE:0.5:300:$five_hours_sample_mem"
          "RRA:AVERAGE:0.5:1440:$one_day_sample_mem"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample_mem, $five_mins_sample_mem, $one_hour_sample_mem, $five_hours_sample_mem, $one_day_sample_mem") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

# AMS memory
sub create_lpar_mem {
  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!

  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_mem_lpar: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_lpar_mem $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:curr_mem:GAUGE:$no_time_new:0:10000000"
          "DS:phys_run_mem:GAUGE:$no_time_new:0:10000000"
          "DS:io_ent:GAUGE:$no_time_new:0:10000000"
          "DS:mapped_io_ent:GAUGE:$no_time_new:0:10000000"
          "DS:overage:GAUGE:$no_time_new:0:10000000"
          "RRA:AVERAGE:0.5:1:10000"
          "RRA:AVERAGE:0.5:6:1500"
          "RRA:AVERAGE:0.5:24:1000"
          "RRA:AVERAGE:0.5:288:1000"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:curr_mem:GAUGE:$no_time_new:0:10000000"
          "DS:phys_run_mem:GAUGE:$no_time_new:0:10000000"
          "DS:io_ent:GAUGE:$no_time_new:0:10000000"
          "DS:mapped_io_ent:GAUGE:$no_time_new:0:10000000"
          "DS:overage:GAUGE:$no_time_new:0:10000000"
          "RRA:AVERAGE:0.5:1:1825"
          "RRA:AVERAGE:0.5:7:260"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 1825, 260") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
                                              #print "0000 $one_minute_sample - $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "create_mem_lpar: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_lpar_mem $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:curr_mem:GAUGE:$no_time_new:0:10000000"
          "DS:phys_run_mem:GAUGE:$no_time_new:0:10000000"
          "DS:io_ent:GAUGE:$no_time_new:0:10000000"
          "DS:mapped_io_ent:GAUGE:$no_time_new:0:10000000"
          "DS:overage:GAUGE:$no_time_new:0:10000000"
          "RRA:AVERAGE:0.5:1:$one_minute_sample_mem"
          "RRA:AVERAGE:0.5:6:$five_mins_sample_mem"
          "RRA:AVERAGE:0.5:24:$one_hour_sample_mem"
          "RRA:AVERAGE:0.5:288:$five_hours_sample_mem"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample_mem, $five_mins_sample_mem, $one_hour_sample_mem, $five_hours_sample_mem") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        #print "++ $rrd $start_time $step_new\n";
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:curr_mem:GAUGE:$no_time_new:0:10000000"
          "DS:phys_run_mem:GAUGE:$no_time_new:0:10000000"
          "DS:io_ent:GAUGE:$no_time_new:0:10000000"
          "DS:mapped_io_ent:GAUGE:$no_time_new:0:10000000"
          "DS:overage:GAUGE:$no_time_new:0:10000000"
          "RRA:AVERAGE:0.5:1:$one_minute_sample_mem"
          "RRA:AVERAGE:0.5:5:$five_mins_sample_mem"
          "RRA:AVERAGE:0.5:60:$one_hour_sample_mem"
          "RRA:AVERAGE:0.5:300:$five_hours_sample_mem"
          "RRA:AVERAGE:0.5:1440:$one_day_sample_mem"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample_mem, $five_mins_sample_mem, $one_hour_sample_mem, $five_hours_sample_mem, $one_day_sample_mem") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_rrd_pool_mem {
  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!

  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_pool: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;

      # keep 5y 1 day averages, and 5y 7 day averages
      touch("create_rrd_pool_mem $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:curr_pool_mem:GAUGE:$no_time_new:0:100000000"
          "DS:curr_io_ent:GAUGE:$no_time_new:0:100000000"
          "DS:mapped_io_ent:GAUGE:$no_time_new:0:100000000"
          "DS:run_mem:GAUGE:$no_time_new:0:100000000"
          "DS:sys_firmware:GAUGE:$no_time_new:0:100000000"
          "RRA:AVERAGE:0.5:1:10000"
          "RRA:AVERAGE:0.5:6:1500"
          "RRA:AVERAGE:0.5:24:1000"
          "RRA:AVERAGE:0.5:288:1000"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:curr_pool_mem:GAUGE:$no_time_new:0:100000000"
          "DS:curr_io_ent:GAUGE:$no_time_new:0:100000000"
          "DS:mapped_io_ent:GAUGE:$no_time_new:0:100000000"
          "DS:run_mem:GAUGE:$no_time_new:0:100000000"
          "DS:sys_firmware:GAUGE:$no_time_new:0:100000000"
          "RRA:AVERAGE:0.5:1:1825"
          "RRA:AVERAGE:0.5:7:260"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 1825, 260") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_pool: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;

      # keep 30 days of 1m sample interval and then averages
      # 5h averages for 6m, 1day averages for 3y
      touch("create_rrd_pool_mem $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:curr_pool_mem:GAUGE:$no_time_new:0:100000000"
          "DS:curr_io_ent:GAUGE:$no_time_new:0:100000000"
          "DS:mapped_io_ent:GAUGE:$no_time_new:0:100000000"
          "DS:run_mem:GAUGE:$no_time_new:0:100000000"
          "DS:sys_firmware:GAUGE:$no_time_new:0:100000000"
          "RRA:AVERAGE:0.5:1:$one_minute_sample_mem"
          "RRA:AVERAGE:0.5:6:$five_mins_sample_mem"
          "RRA:AVERAGE:0.5:24:$one_hour_sample_mem"
          "RRA:AVERAGE:0.5:288:$five_hours_sample_mem"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample_mem, $five_mins_sample_mem, $one_hour_sample_mem, $five_hours_sample_mem") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:curr_pool_mem:GAUGE:$no_time_new:0:100000000"
          "DS:curr_io_ent:GAUGE:$no_time_new:0:100000000"
          "DS:mapped_io_ent:GAUGE:$no_time_new:0:100000000"
          "DS:run_mem:GAUGE:$no_time_new:0:100000000"
          "DS:sys_firmware:GAUGE:$no_time_new:0:100000000"
          "RRA:AVERAGE:0.5:1:$one_minute_sample_mem"
          "RRA:AVERAGE:0.5:5:$five_mins_sample_mem"
          "RRA:AVERAGE:0.5:60:$one_hour_sample_mem"
          "RRA:AVERAGE:0.5:300:$five_hours_sample_mem"
          "RRA:AVERAGE:0.5:1440:$one_day_sample_mem"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample_mem, $five_mins_sample_mem, $one_hour_sample_mem, $five_hours_sample_mem, $one_day_sample_mem") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_rrd_pool {
  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  my $rra_average = "AVERAGE";
  if ( $rrd =~ /\.xr$type_sam$/ ) {
    $rra_average = "MAX";
  }

  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!

  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_pool: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;

      # keep 5y 1 day averages, and 5y 7 day averages
      touch("create_rrd_pool $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:total_pool_cycles:COUNTER:$no_time_new:0:U"
          "DS:utilized_pool_cyc:COUNTER:$no_time_new:0:U"
          "DS:conf_proc_units:GAUGE:$no_time_new:0:1024"
          "DS:bor_proc_units:GAUGE:$no_time_new:0:1024"
          "RRA:$rra_average:0.5:1:10000"
          "RRA:$rra_average:0.5:6:1500"
          "RRA:$rra_average:0.5:24:1000"
          "RRA:$rra_average:0.5:288:1000"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:total_pool_cycles:COUNTER:$no_time_new:0:U"
          "DS:utilized_pool_cyc:COUNTER:$no_time_new:0:U"
          "DS:conf_proc_units:GAUGE:$no_time_new:0:1024"
          "DS:bor_proc_units:GAUGE:$no_time_new:0:1024"
          "RRA:$rra_average:0.5:1:1825"
          "RRA:$rra_average:0.5:7:260"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 1825, 260") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_pool: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;

      # keep 30 days of 1m sample interval and then averages
      # 5h averages for 6m, 1day averages for 3y
      touch("create_rrd_pool $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:total_pool_cycles:COUNTER:$no_time_new:0:U"
          "DS:utilized_pool_cyc:COUNTER:$no_time_new:0:U"
          "DS:conf_proc_units:GAUGE:$no_time_new:0:1024"
          "DS:bor_proc_units:GAUGE:$no_time_new:0:1024"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:6:$five_mins_sample"
          "RRA:$rra_average:0.5:24:$one_hour_sample"
          "RRA:$rra_average:0.5:288:$five_hours_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:total_pool_cycles:COUNTER:$no_time_new:0:U"
          "DS:utilized_pool_cyc:COUNTER:$no_time_new:0:U"
          "DS:conf_proc_units:GAUGE:$no_time_new:0:1024"
          "DS:bor_proc_units:GAUGE:$no_time_new:0:1024"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_rrd_pool_shared {
  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  my $rra_average = "AVERAGE";
  if ( $rrd =~ /\.xr$type_sam$/ ) {
    $rra_average = "MAX";
  }

  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!

  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "cr_rrd_pool_sh : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;

      # keep 5y 1 day averages, and 5y 7 day averages
      touch("create_rrd_pool_shared $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:total_pool_cycles:COUNTER:$no_time_new:0:U"
          "DS:utilized_pool_cyc:COUNTER:$no_time_new:0:U"
          "DS:max_pool_units:GAUGE:$no_time_new:0:1024"
          "DS:res_pool_units:GAUGE:$no_time_new:0:1024"
          "RRA:$rra_average:0.5:1:10000"
          "RRA:$rra_average:0.5:6:1500"
          "RRA:$rra_average:0.5:24:1000"
          "RRA:$rra_average:0.5:288:1000"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:total_pool_cycles:COUNTER:$no_time_new:0:U"
          "DS:utilized_pool_cyc:COUNTER:$no_time_new:0:U"
          "DS:max_pool_units:GAUGE:$no_time_new:0:1024"
          "DS:res_pool_units:GAUGE:$no_time_new:0:1024"
          "RRA:$rra_average:0.5:1:1825"
          "RRA:$rra_average:0.5:7:260"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 1825, 260") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "cr_rrd_pool_sh : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;

      # keep 30 days of 1m sample interval and then averages
      # 5h averages for 6m, 1day averages for 3y
      touch("create_rrd_pool_shared $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:total_pool_cycles:COUNTER:$no_time_new:0:U"
          "DS:utilized_pool_cyc:COUNTER:$no_time_new:0:U"
          "DS:max_pool_units:GAUGE:$no_time_new:0:1024"
          "DS:res_pool_units:GAUGE:$no_time_new:0:1024"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:6:$five_mins_sample"
          "RRA:$rra_average:0.5:24:$one_hour_sample"
          "RRA:$rra_average:0.5:288:$five_hours_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:total_pool_cycles:COUNTER:$no_time_new:0:U"
          "DS:utilized_pool_cyc:COUNTER:$no_time_new:0:U"
          "DS:max_pool_units:GAUGE:$no_time_new:0:1024"
          "DS:res_pool_units:GAUGE:$no_time_new:0:1024"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_rrd_mem {
  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  # actual memory limit is 1000TB
  # this can be easily even online updated by
  # find $HOMELPAR/data -name "mem.rr*" -exec rrdtool tune {} --maximum curr_avail_mem:1000000000 \;

  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!

  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_mem : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_mem $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:curr_avail_mem:GAUGE:$no_time_new:0:100000000000"
          "DS:conf_sys_mem:GAUGE:$no_time_new:0:1000000000000"
          "DS:sys_firmware_mem:GAUGE:$no_time_new:0:100000000000"
          "RRA:AVERAGE:0.5:1:10000"
          "RRA:AVERAGE:0.5:6:1500"
          "RRA:AVERAGE:0.5:24:1000"
          "RRA:AVERAGE:0.5:288:1000"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:curr_avail_mem:GAUGE:$no_time_new:0:100000000000"
          "DS:conf_sys_mem:GAUGE:$no_time_new:0:1000000000000"
          "DS:sys_firmware_mem:GAUGE:$no_time_new:0:100000000000"
          "RRA:AVERAGE:0.5:1:1825"
          "RRA:AVERAGE:0.5:7:260"
        );
        if ( !Xorux_lib::create_check("file: $rrd, 1825, 260") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_mem : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_mem $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:curr_avail_mem:GAUGE:$no_time_new:0:100000000000"
          "DS:conf_sys_mem:GAUGE:$no_time_new:0:1000000000000"
          "DS:sys_firmware_mem:GAUGE:$no_time_new:0:100000000000"
          "RRA:AVERAGE:0.5:1:$one_minute_sample_mem"
          "RRA:AVERAGE:0.5:6:$five_mins_sample_mem"
          "RRA:AVERAGE:0.5:24:$one_hour_sample_mem"
          "RRA:AVERAGE:0.5:288:$five_hours_sample_mem"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample_mem, $five_mins_sample_mem, $one_hour_sample_mem, $five_hours_sample_mem") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:curr_avail_mem:GAUGE:$no_time_new:0:100000000000"
          "DS:conf_sys_mem:GAUGE:$no_time_new:0:1000000000000"
          "DS:sys_firmware_mem:GAUGE:$no_time_new:0:100000000000"
          "RRA:AVERAGE:0.5:1:$one_minute_sample_mem"
          "RRA:AVERAGE:0.5:5:$five_mins_sample_mem"
          "RRA:AVERAGE:0.5:60:$one_hour_sample_mem"
          "RRA:AVERAGE:0.5:300:$five_hours_sample_mem"
          "RRA:AVERAGE:0.5:1440:$one_day_sample_mem"
        );
        if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample_mem, $five_mins_sample_mem, $one_hour_sample_mem, $five_hours_sample_mem, $one_day_sample_mem") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_rrd_pool_total {
  my $rrd        = shift;
  my $cf         = shift;
  my $start_time = 1400000000;
  my $step       = 60;
  print "create rrd cpupool $rrd with $cf\n";
  print "RRD CPUTOTAL : $rrd\n";
  RRDp::cmd qq(create "$rrd" --start "$start_time" --step "$step"
    "DS:configured:GAUGE:600:0:4096"
    "DS:curr_proc_units:GAUGE:600:0:4096"
    "DS:entitled_cycles:COUNTER:600:0:U"
    "DS:capped_cycles:COUNTER:600:0:U"
    "DS:uncapped_cycles:COUNTER:600:0:U"
    "RRA:$cf:0.5:1:$one_minute_sample"
    "RRA:$cf:0.5:5:$five_mins_sample"
    "RRA:$cf:0.5:60:$one_hour_sample"
    "RRA:$cf:0.5:300:$five_hours_sample"
    "RRA:$cf:0.5:1440:$one_day_sample"
  );

  if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
    main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }
}

sub create_rrd_vcpu {
  my $rrd        = shift;
  my $cf         = shift;
  my $start_time = 1400000000;
  my $step       = 3600;
  print "create rrd vcpu $rrd with $cf\n";
  print "RRD vCPU : $rrd\n";
  RRDp::cmd qq(create "$rrd" --start "$start_time" --step "$step"
    "DS:allocated_cores:GAUGE:7200:0:4096"
    "RRA:$cf:0.5:1:$one_hour_sample"
    "RRA:$cf:0.5:5:$five_hours_sample"
    "RRA:$cf:0.5:24:$one_day_sample"
  );

  if ( !Xorux_lib::create_check("file: $rrd,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
    main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
    RRDp::end;
    RRDp::start "$rrdtool";
    return 2;
  }
}

sub create_rrd_fcs {

  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  my $rra_average = "AVERAGE";

  #if ( $rrd =~ /\.xr$type_sam$/ ) {
  #  $rra_average = "MAX";
  #}
  #print "rrd:$rrd\nstart_time:$start_time\ncounter_tot:$counter_tot\nstep:$step\ntype_sam:$type_sam\nDebug:$DEBUG\nhost:$host\nmanagedname:$managedname\nno_time:$no_time\nact_time:$act_time\nstep_new:$step_new\nno_time_new:$no_time_new\n\n";
  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!
                               #12/12/2017 06:34:00,vios-770,ent4,U9117.MMC.44K8102-V1-C4-T1,15641245826,18814533,45077532734,48129562,0,virtual
  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_fcs : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_fcs $rrd");
      if ( $step == 3600 ) {

        #receivedBytes = read; receivedPackets=io_read; sentbytes=write;
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:running_speed:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:running_speed:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_fcs : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_fcs $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:running_speed:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:running_speed:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

=cut
sub create_rrd_sriov{

  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  my $rra_average = "AVERAGE";
  #if ( $rrd =~ /\.xr$type_sam$/ ) {
  #  $rra_average = "MAX";
  #}
  #print "rrd:$rrd\nstart_time:$start_time\ncounter_tot:$counter_tot\nstep:$step\ntype_sam:$type_sam\nDebug:$DEBUG\nhost:$host\nmanagedname:$managedname\nno_time:$no_time\nact_time:$act_time\nstep_new:$step_new\nno_time_new:$no_time_new\n\n";
  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!
  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_sriov : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_sriov $rrd");
      if ( $step == 3600 ) {
        #receivedBytes = read; receivedPackets=io_read; sentbytes=write;
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:drop_in:GAUGE:$no_time_new:0:50000000"
          "DS:drop_out:GAUGE:$no_time_new:0:50000000"
          "DS:error_i:GAUGE:$no_time_new:0:50000000"
          "DS:error_o:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        } ## end if ( !Xorux_lib::create_check...)
      } ## end if ( $step == 3600 )
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:drop_in:GAUGE:$no_time_new:0:50000000"
          "DS:drop_out:GAUGE:$no_time_new:0:50000000"
          "DS:error_i:GAUGE:$no_time_new:0:50000000"
          "DS:error_o:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        } ## end if ( !Xorux_lib::create_check...)
      } ## end else [ if ( $step == 3600 ) ]
    } ## end if ( not -f $rrd )
  } ## end if ( $type_sam =~ "d" )
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_lan : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_lan $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:drop_in:GAUGE:$no_time_new:0:50000000"
          "DS:drop_out:GAUGE:$no_time_new:0:50000000"
          "DS:error_i:GAUGE:$no_time_new:0:50000000"
          "DS:error_o:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        } ## end if ( !Xorux_lib::create_check...)
      } ## end if ( $step == 3600 )
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:droped_i:GAUGE:$no_time_new:0:50000000"
          "DS:droped_o:GAUGE:$no_time_new:0:50000000"
          "DS:error_in:GAUGE:$no_time_new:0:50000000"
          "DS:error_out:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        } ## end if ( !Xorux_lib::create_check...)
      } ## end else [ if ( $step == 3600 ) ]
    } ## end if ( not -f $rrd )
  } ## end else [ if ( $type_sam =~ "d" )]
  return 0;
} ## end sub create_rrd_sriov
=cut

sub create_rrd_sriov2 {

  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  #$ts,$lpar,$physLoc,$configurationType,$drcIndex,$droppedReceivedPackets,$droppedSentPackets,$errorIn,$errorOut,$physicalDrcIndex,$physicalPortId,$receivedBytes,$receivedPackets,$sentBytes,$sentPackets,$vnicDeviceMode

  my $rra_average = "AVERAGE";
  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!
  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_fcs : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_fcs $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:drop_i:GAUGE:$no_time_new:0:50000000"
          "DS:drop_o:GAUGE:$no_time_new:0:50000000"
          "DS:error_in:GAUGE:$no_time_new:0:50000000"
          "DS:error_out:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:drop_i:GAUGE:$no_time_new:0:50000000"
          "DS:drop_o:GAUGE:$no_time_new:0:50000000"
          "DS:error_in:GAUGE:$no_time_new:0:50000000"
          "DS:error_out:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_fcs : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_fcs $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:drop_i:GAUGE:$no_time_new:0:50000000"
          "DS:drop_o:GAUGE:$no_time_new:0:50000000"
          "DS:error_in:GAUGE:$no_time_new:0:50000000"
          "DS:error_out:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:drop_i:GAUGE:$no_time_new:0:50000000"
          "DS:drop_o:GAUGE:$no_time_new:0:50000000"
          "DS:error_in:GAUGE:$no_time_new:0:50000000"
          "DS:error_out:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_rrd_lan {

  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  my $rra_average = "AVERAGE";

  #if ( $rrd =~ /\.xr$type_sam$/ ) {
  #  $rra_average = "MAX";
  #}
  #print "rrd:$rrd\nstart_time:$start_time\ncounter_tot:$counter_tot\nstep:$step\ntype_sam:$type_sam\nDebug:$DEBUG\nhost:$host\nmanagedname:$managedname\nno_time:$no_time\nact_time:$act_time\nstep_new:$step_new\nno_time_new:$no_time_new\n\n";
  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!
                               #12/12/2017 06:34:00,vios-770,ent4,U9117.MMC.44K8102-V1-C4-T1,15641245826,18814533,45077532734,48129562,0,virtual
  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_lan : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_lan $rrd");
      if ( $step == 3600 ) {

        #receivedBytes = read; receivedPackets=io_read; sentbytes=write;
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:dropped_packets:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:dropped_packets:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );

=cut
 RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:drc_index:GAUGE:$no_time_new:0:50000000"
          "DS:dropped_received_packets:GAUGE:$no_time_new:0:50000000"
          "DS:dropped_sent_packets:GAUGE:$no_time_new:0:50000000"
          "DS:error_in:GAUGE:$no_time_new:0:50000000"
          "DS:error_out:GAUGE:$no_time_new:0:50000000"
          "DS:physical_drc_index:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
=cut

        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_lan : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_lan $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:dropped_packets:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "DS:dropped_packets:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_rrd_json_lpars {
  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  my $rra_average = "AVERAGE";

  #if ( $rrd =~ /\.xr$type_sam$/ ) {
  #  $rra_average = "MAX";
  #}
  #print "rrd:$rrd\nstart_time:$start_time\ncounter_tot:$counter_tot\nstep:$step\ntype_sam:$type_sam\nDebug:$DEBUG\nhost:$host\nmanagedname:$managedname\nno_time:$no_time\nact_time:$act_time\nstep_new:$step_new\nno_time_new:$no_time_new\n\n";
  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!
                               #12/12/2017 06:34:00,vios-770,ent4,U9117.MMC.44K8102-V1-C4-T1,15641245826,18814533,45077532734,48129562,0,virtual
  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_json_lpars : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_json_lpars $rrd");
      if ( $step == 3600 ) {

        #receivedBytes = read; receivedPackets=io_read; sentbytes=write;
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:c_proc_un:GAUGE:$no_time_new:0:50000000"
          "DS:vir_procs:GAUGE:$no_time_new:0:50000000"
          "DS:en_cycles:GAUGE:$no_time_new:0:50000000"
          "DS:ca_cycles:GAUGE:$no_time_new:0:50000000"
          "DS:un_cycles:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:c_proc_un:GAUGE:$no_time_new:0:50000000"
          "DS:vir_procs:GAUGE:$no_time_new:0:50000000"
          "DS:en_cycles:GAUGE:$no_time_new:0:50000000"
          "DS:ca_cycles:GAUGE:$no_time_new:0:50000000"
          "DS:un_cycles:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_lpar : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_json_lpars $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:c_proc_un:GAUGE:$no_time_new:0:50000000"
          "DS:vir_procs:GAUGE:$no_time_new:0:50000000"
          "DS:en_cycles:GAUGE:$no_time_new:0:50000000"
          "DS:ca_cycles:GAUGE:$no_time_new:0:50000000"
          "DS:un_cycles:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:c_proc_un:GAUGE:$no_time_new:0:50000000"
          "DS:vir_procs:GAUGE:$no_time_new:0:50000000"
          "DS:en_cycles:GAUGE:$no_time_new:0:50000000"
          "DS:ca_cycles:GAUGE:$no_time_new:0:50000000"
          "DS:un_cycles:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_rrd_gpa {

  my $rrd         = shift;
  my $start_time  = shift;
  my $counter_tot = shift;
  my $step        = shift;
  my $type_sam    = shift;
  my $DEBUG       = shift;
  my $host        = shift;
  my $managedname = shift;
  my $no_time     = shift;
  my $act_time    = shift;
  my $step_new    = $step;
  my $no_time_new = $no_time;

  my $rra_average = "AVERAGE";

  #if ( $rrd =~ /\.xr$type_sam$/ ) {
  #  $rra_average = "MAX";
  #}
  #print "rrd:$rrd\nstart_time:$start_time\ncounter_tot:$counter_tot\nstep:$step\ntype_sam:$type_sam\nDebug:$DEBUG\nhost:$host\nmanagedname:$managedname\nno_time:$no_time\nact_time:$act_time\nstep_new:$step_new\nno_time_new:$no_time_new\n\n";
  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!
                               #12/12/2017 06:34:00,vios-770,ent4,U9117.MMC.44K8102-V1-C4-T1,15641245826,18814533,45077532734,48129562,0,virtual
  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {
      $step_new    = 86400;
      $no_time_new = 200000;
      print "RRD GPA : $rrd\n";
      print "create_rrd_gpa : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_gpa $rrd");
      if ( $step == 3600 ) {

        #receivedBytes = read; receivedPackets=io_read; sentbytes=write;
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  else {
    if ( not -f $rrd ) {
      load_retentions( $step, $act_time );    # load data retentions
      print "create_rrd_gpa : $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd_fcs $rrd");
      if ( $step == 3600 ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
      else {
        RRDp::cmd qq(create "$rrd"  --start "$start_time" --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:50000000"
          "DS:io_read:GAUGE:$no_time_new:0:50000000"
          "DS:write:GAUGE:$no_time_new:0:50000000"
          "DS:io_write:GAUGE:$no_time_new:0:50000000"
          "RRA:$rra_average:0.5:1:$one_minute_sample"
          "RRA:$rra_average:0.5:5:$five_mins_sample"
          "RRA:$rra_average:0.5:60:$one_hour_sample"
          "RRA:$rra_average:0.5:300:$five_hours_sample"
          "RRA:$rra_average:0.5:1440:$one_day_sample"
        );
        if ( !Xorux_lib::create_check("file: $rrd,$one_minute_sample,$five_mins_sample,$one_hour_sample,$five_hours_sample,$one_day_sample") ) {
          main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
          RRDp::end;
          RRDp::start "$rrdtool";
          return 2;
        }
      }
    }
  }
  return 0;
}

sub create_rrd {
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
  my $step_new     = $step;
  my $no_time_new  = $no_time;

  $start_time = 1400000000;    # something old enough, do not use  passed $start_time!!!!

  my $ret = recent_rename( $host, $managedname, $lpar, $wrkdir, $DEBUG, $time_rec, $act_time );
  if ( $ret == 1 ) {

    # this lpar has been recently renamed, do not create rrdtool files
    return 1;
  }

  if ( $type_sam =~ "d" ) {
    if ( not -f $rrd ) {       # do it once more, rename could create it
      $step_new    = 86400;
      $no_time_new = 200000;
      print "create_rrd_lpar: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd $rrd");
      if ( $step == 3600 ) {
        if ( $keep_virtual == 1 ) {
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
              "DS:curr_proc_units:GAUGE:$no_time_new:0:4096"
              "DS:virtual_procs:GAUGE:$no_time_new:0:4096"
              "DS:entitled_cycles:COUNTER:$no_time_new:0:U"
              "DS:capped_cycles:COUNTER:$no_time_new:0:U"
              "DS:uncapped_cycles:COUNTER:$no_time_new:0:U"
              "RRA:AVERAGE:0.5:1:10000"
              "RRA:AVERAGE:0.5:6:1500"
              "RRA:AVERAGE:0.5:24:1000"
              "RRA:AVERAGE:0.5:288:1000"
            );
          if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
            main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
            RRDp::end;
            RRDp::start "$rrdtool";
            return 2;
          }
        }
        else {
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
              "DS:curr_proc_units:GAUGE:$no_time_new:0:4096"
              "DS:entitled_cycles:COUNTER:$no_time_new:0:U"
              "DS:capped_cycles:COUNTER:$no_time_new:0:U"
              "DS:uncapped_cycles:COUNTER:$no_time_new:0:U"
              "RRA:AVERAGE:0.5:1:10000"
              "RRA:AVERAGE:0.5:6:1500"
              "RRA:AVERAGE:0.5:24:1000"
              "RRA:AVERAGE:0.5:288:1000"
            );
          if ( !Xorux_lib::create_check("file: $rrd, 10000, 1500, 1000, 1000") ) {
            main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
            RRDp::end;
            RRDp::start "$rrdtool";
            return 2;
          }
        }
      }
      else {
        if ( $keep_virtual == 1 ) {
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
              "DS:curr_proc_units:GAUGE:$no_time_new:0:4096"
              "DS:virtual_procs:GAUGE:$no_time_new:0:4096"
              "DS:entitled_cycles:COUNTER:$no_time_new:0:U"
              "DS:capped_cycles:COUNTER:$no_time_new:0:U"
              "DS:uncapped_cycles:COUNTER:$no_time_new:0:U"
              "RRA:AVERAGE:0.5:1:1825"
              "RRA:AVERAGE:0.5:7:260"
            );
          if ( !Xorux_lib::create_check("file: $rrd, 1825, 260") ) {
            main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
            RRDp::end;
            RRDp::start "$rrdtool";
            return 2;
          }
        }
        else {
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
              "DS:curr_proc_units:GAUGE:$no_time_new:0:4096"
              "DS:entitled_cycles:COUNTER:$no_time_new:0:U"
              "DS:capped_cycles:COUNTER:$no_time_new:0:U"
              "DS:uncapped_cycles:COUNTER:$no_time_new:0:U"
              "RRA:AVERAGE:0.5:1:1825"
              "RRA:AVERAGE:0.5:7:260"
            );
          if ( !Xorux_lib::create_check("file: $rrd, 1825, 260") ) {
            main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
            RRDp::end;
            RRDp::start "$rrdtool";
            return 2;
          }
        }
      }
    }
  }
  else {
    rename_lpar( $host, $managedname, $lpar, $act_time, $SSH, $hmc_user, $wrkdir, $DEBUG, $time_rec );
    if ( not -f $rrd ) {    # do it once more, rename could create it

      load_retentions( $step, $act_time );    # load data retentions
                                              #print "0000 $one_minute_sample - $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "create_rrd_lpar: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
      touch("create_rrd $rrd");
      touch_LPM("create_rrd LPM $rrd");       # force to run LPM search in install-html.sh
      if ( $step == 3600 ) {
        if ( $keep_virtual == 1 ) {
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
              "DS:curr_proc_units:GAUGE:$no_time_new:0:4096"
              "DS:virtual_procs:GAUGE:$no_time_new:0:4096"
              "DS:entitled_cycles:COUNTER:$no_time_new:0:U"
              "DS:capped_cycles:COUNTER:$no_time_new:0:U"
              "DS:uncapped_cycles:COUNTER:$no_time_new:0:U"
              "RRA:AVERAGE:0.5:1:$one_minute_sample"
              "RRA:AVERAGE:0.5:6:$five_mins_sample"
              "RRA:AVERAGE:0.5:24:$one_hour_sample"
              "RRA:AVERAGE:0.5:288:$five_hours_sample"
            );
          if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample") ) {
            main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );

            #RRDp::end;
            #RRDp::start "$rrdtool";
            return 2;
          }
        }
        else {
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
              "DS:curr_proc_units:GAUGE:$no_time_new:0:4096"
              "DS:entitled_cycles:COUNTER:$no_time_new:0:U"
              "DS:capped_cycles:COUNTER:$no_time_new:0:U"
              "DS:uncapped_cycles:COUNTER:$no_time_new:0:U"
              "RRA:AVERAGE:0.5:1:$one_minute_sample"
              "RRA:AVERAGE:0.5:6:$five_mins_sample"
              "RRA:AVERAGE:0.5:24:$one_hour_sample"
              "RRA:AVERAGE:0.5:288:$five_hours_sample"
            );
          if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample") ) {
            main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
            RRDp::end;
            RRDp::start "$rrdtool";
            return 2;
          }
        }
      }
      else {
        #print "++ $rrd $start_time $step_new - $no_time_new \n";
        if ( $keep_virtual == 1 ) {
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
              "DS:curr_proc_units:GAUGE:$no_time_new:0:4096"
              "DS:virtual_procs:GAUGE:$no_time_new:0:4096"
              "DS:entitled_cycles:COUNTER:$no_time_new:0:U"
              "DS:capped_cycles:COUNTER:$no_time_new:0:U"
              "DS:uncapped_cycles:COUNTER:$no_time_new:0:U"
              "RRA:AVERAGE:0.5:1:$one_minute_sample"
              "RRA:AVERAGE:0.5:5:$five_mins_sample"
              "RRA:AVERAGE:0.5:60:$one_hour_sample"
              "RRA:AVERAGE:0.5:300:$five_hours_sample"
              "RRA:AVERAGE:0.5:1440:$one_day_sample"
            );
          if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
            main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
            RRDp::end;
            RRDp::start "$rrdtool";
            return 2;
          }
        }
        else {
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
              "DS:curr_proc_units:GAUGE:$no_time_new:0:4096"
              "DS:entitled_cycles:COUNTER:$no_time_new:0:U"
              "DS:capped_cycles:COUNTER:$no_time_new:0:U"
              "DS:uncapped_cycles:COUNTER:$no_time_new:0:U"
              "RRA:AVERAGE:0.5:1:$one_minute_sample"
              "RRA:AVERAGE:0.5:5:$five_mins_sample"
              "RRA:AVERAGE:0.5:60:$one_hour_sample"
              "RRA:AVERAGE:0.5:300:$five_hours_sample"
              "RRA:AVERAGE:0.5:1440:$one_day_sample"
            );
          if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
            main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
            RRDp::end;
            RRDp::start "$rrdtool";
            return 2;
          }
        }
      }
    }
  }
  return 0;
}

# workaround for situation when during LPM move
# those counters appears all 0 on the targed systems what causes
# huge peak in the graph

sub data_check {
  my $ent         = shift;
  my $cap         = shift;
  my $uncap       = shift;
  my $lpar        = shift;
  my $host        = shift;
  my $managedname = shift;

  if ( $ent eq '' ) {
    main::error("$host:$managedname:$lpar : ent is NULL, ignoring the line");
    return 1;
  }
  if ( $cap eq '' ) {
    main::error("$host:$managedname:$lpar : cap is NULL, ignoring the line");
    return 1;
  }
  if ( $uncap eq '' ) {
    main::error("$host:$managedname:$lpar : uncap is NULL, ignoring the line");
    return 1;
  }
  if ( $ent == 0 && $cap == 0 && $uncap == 0 ) {

    #main::error ("$host:$managedname:$lpar : LPM issue: $ent:$cap:$uncap - fixed, continue ...");
    return 1;
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

################################
# SDMC
################################

sub sdmc_procpool_load {
  my $SSH         = shift;
  my $hmc_user    = shift;
  my $host        = shift;
  my $ivmy        = shift;
  my $ivmm        = shift;
  my $ivmd        = shift;
  my $ivmh        = shift;
  my $ivmmin      = shift;
  my $managedname = shift;
  my $out_file    = shift;
  my $type_sam    = shift;
  my $timerange   = shift;

  #return 1;

  if ( $type_sam =~ "d" ) {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r procpool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,shared_proc_pool_id,total_pool_cycles,utilized_pool_cycles  --filter \"event_types=sample\""|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }
  else {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -r procpool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,shared_proc_pool_id,total_pool_cycles,utilized_pool_cycles "|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }

  return 1;
}

sub sdmc_cod_load {
  my $SSH         = shift;
  my $hmc_user    = shift;
  my $host        = shift;
  my $ivmy        = shift;
  my $ivmm        = shift;
  my $ivmd        = shift;
  my $ivmh        = shift;
  my $ivmmin      = shift;
  my $managedname = shift;
  my $out_file    = shift;
  my $type_sam    = shift;
  my $loadhours   = shift;

  #print "**** COD load switched off\n";
  #return 1;

  if ( $type_sam =~ "d" ) {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r all --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,used_proc_min,unreported_proc_min --filter \"event_types=utility_cod_proc_usage\""|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }
  else {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -r all --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,used_proc_min,unreported_proc_min --filter \"event_types=utility_cod_proc_usage\" "|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }

  return 1;
}

sub sdmc_pool_load {
  my $SSH         = shift;
  my $hmc_user    = shift;
  my $host        = shift;
  my $ivmy        = shift;
  my $ivmm        = shift;
  my $ivmd        = shift;
  my $ivmh        = shift;
  my $ivmmin      = shift;
  my $managedname = shift;
  my $out_file    = shift;
  my $type_sam    = shift;
  my $loadhours   = shift;

  #return 1;

  if ( $type_sam =~ "d" ) {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r pool  --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units  --filter \"event_types=sample\""|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }
  else {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -r pool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,total_pool_cycles,utilized_pool_cycles,configurable_pool_proc_units,borrowed_pool_proc_units"|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }

  return 1;
}

sub sdmc_lpar_load {
  my $SSH         = shift;
  my $hmc_user    = shift;
  my $host        = shift;
  my $ivmy        = shift;
  my $ivmm        = shift;
  my $ivmd        = shift;
  my $ivmh        = shift;
  my $ivmmin      = shift;
  my $managedname = shift;
  my $out_file    = shift;
  my $type_sam    = shift;
  my $loadhours   = shift;
  my $lpars       = shift;    # for alerting, just get selectively data for particular lpars
  my $mem_params  = shift;

  #return 1;

  if ( $type_sam =~ "d" ) {
    if ( $lpars eq '' ) {
      `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r lpar --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,lpar_id,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles$mem_params"|egrep -iv "Could not create directory|known hosts" > $out_file`;
    }
    else {
      `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r lpar --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,lpar_id,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles$mem_params  --filter \\\\\\"lpar_names=$lpars\\\\\\""|egrep -iv "Could not create directory|known hosts" > $out_file`;
    }
  }
  else {
    if ( $lpars eq '' ) {
      `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -r lpar --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,lpar_id,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles$mem_params"|egrep -iv "Could not create directory|known hosts" > $out_file`;
    }
    else {
      `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -r lpar --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,lpar_id,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles$mem_params --filter \\\\\\"lpar_names=$lpars\\\\\\""|egrep -iv "Could not create directory|known hosts" > $out_file`;
    }
  }

  return 1;
}

sub sdmc_pool_mem_load {
  my $SSH         = shift;
  my $hmc_user    = shift;
  my $host        = shift;
  my $ivmy        = shift;
  my $ivmm        = shift;
  my $ivmd        = shift;
  my $ivmh        = shift;
  my $ivmmin      = shift;
  my $managedname = shift;
  my $out_file    = shift;
  my $type_sam    = shift;
  my $loadhours   = shift;

  if ( $type_sam =~ "d" ) {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r mempool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,curr_pool_mem,lpar_curr_io_entitled_mem,lpar_mapped_io_entitled_mem,lpar_run_mem,sys_firmware_pool_mem --filter \"event_types=sample\""|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }
  else {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -r mempool --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,curr_pool_mem,lpar_curr_io_entitled_mem,lpar_mapped_io_entitled_mem,lpar_run_mem,sys_firmware_pool_mem "|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }

  return 1;
}

sub sdmc_sys_load {
  my $SSH         = shift;
  my $hmc_user    = shift;
  my $host        = shift;
  my $ivmy        = shift;
  my $ivmm        = shift;
  my $ivmd        = shift;
  my $ivmh        = shift;
  my $ivmmin      = shift;
  my $managedname = shift;
  my $out_file    = shift;
  my $type_sam    = shift;
  my $loadhours   = shift;

  if ( $type_sam =~ "d" ) {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -s $type_sam -r sys --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin  -m \\"$managedname\\" -F time,curr_avail_sys_mem,configurable_sys_mem,sys_firmware_mem --filter \"event_types=sample\""|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }
  else {
    `$SSH $hmc_user\@$host "export LANG=en_US; lslparutil -r sys --startyear $ivmy --startmonth $ivmm --startday $ivmd --starthour $ivmh --startminute $ivmmin -m \\"$managedname\\" -F time,curr_avail_sys_mem,configurable_sys_mem,sys_firmware_mem "|egrep -iv "Could not create directory|known hosts" > $out_file`;
  }

  return 1;
}

sub smdc_touch {
  my $SDMC        = shift;
  my $wrkdir      = shift;
  my $managedname = shift;
  my $host        = shift;
  my $act_time    = shift;

  if ( $SDMC == 1 ) {
    if ( !-f "$wrkdir/$managedname/$host/SDMC" ) {
      open( FH, "> $wrkdir/$managedname/$host/SDMC" ) || main::error( " Can't create $wrkdir/$managedname/$host/IVM : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      print FH "SDMC\n";
      close(FH);
    }
  }
  else {
    if ( -f "$wrkdir/$managedname/$host/SDMC" ) {
      unlink("$wrkdir/$managedname/$host/SDMC");
    }
  }

  return 1;
}

################################
# End of SDMC
################################

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
  open( FH, "< $basedir/etc/retention.cfg" ) || main::error("Can't read from: $basedir/etc/retention.cfg: $!");

  my @lines = <FH>;
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

  close(FH);

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

  # cut off any decimals if appears there (for step=300 it is there for 5 hours!)
  $one_minute_sample =~ s/\..*//;
  $five_mins_sample  =~ s/\..*//;
  $one_hour_sample   =~ s/\..*//;
  $five_hours_sample =~ s/\..*//;
  $one_day_sample    =~ s/\..*//;

  $one_minute_sample_mem =~ s/\..*//;
  $five_mins_sample_mem  =~ s/\..*//;
  $one_hour_sample_mem   =~ s/\..*//;
  $five_hours_sample_mem =~ s/\..*//;
  $one_day_sample_mem    =~ s/\..*//;

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

sub rename_lpar {
  my $host        = shift;
  my $managedname = shift;
  my $lpar        = shift;
  my $act_time    = shift;
  my $SSH         = shift;
  my $hmc_user    = shift;
  my $wrkdir      = shift;
  my $DEBUG       = shift;
  my $time_rec    = shift;
  my $serial      = "";
  my $lpar_slash  = $lpar;
  $lpar_slash =~ s/\&\&1/\//g;

  # do not use it! it might corrupt data by renaming wrong lpars after LPM, 5.05-1 -PH
  return 1;

  if ( $rename_once == 0 ) {

    # do it only once per a server
    @rename = `$SSH $hmc_user\@$host "lssyscfg -m \\"$managedname\\" -r lpar -F name,logical_serial_num" 2>&1`;
  }
  $rename_once = 1;

  # new lpar has been detected here, found its serial and check whether any already existing lpar has it
  foreach my $line (@rename) {
    chomp($line);
    ( my $name, my $serial_new ) = split( /,/, $line );
    if ( $name =~ m/^$lpar_slash$/ ) {
      $serial = $serial_new;
      last;
    }
  }

  if ( $serial eq '' ) {

    #main::error("$host:$managedname:$lpar have not been found serial, ignore that if that lpar has been recently renamed");
    # --> error message is confusing ... do not print it at all
    return 0;
  }

  # now go through all cpu-cfg-$lpar and search serial
  my $tstamp      = 0;
  my $lpar_recent = "";
  my $lpar_old    = "";
  foreach my $cfg (<"$wrkdir/$managedname/$host/cpu.cfg-*">) {
    open( FHCPU, "< $cfg" ) || main::error( " Can't open $cfg : $! " . __FILE__ . ":" . __LINE__ ) && next;
    my @lines = <FHCPU>;

    #print "001 $cfg $serial\n";
    $lpar_old = $cfg;
    $lpar_old =~ s/^.*cpu\.cfg-//;

    foreach my $line (@lines) {
      chomp($line);
      if ( $line =~ m/logical_serial_num/ && $line =~ m/\>$serial\</ ) {

        #print "002 $lpar_old\n";

        # find out a lpar with the last record --> this one was most probably used before rename last time
        if ( -f "$wrkdir/$managedname/$host/$lpar_old.rrm" ) {

          #print "003 $lpar_old $lpar\n";
          RRDp::cmd qq(last "$wrkdir/$managedname/$host/$lpar_old.rrm" );
          my $last_rec = RRDp::read;
          chomp($$last_rec);
          if ( $$last_rec > $tstamp ) {

            #print "004 $wrkdir/$managedname/$host/$lpar_old.rrm $$last_rec $tstamp\n";
            $tstamp      = $$last_rec;
            $lpar_recent = $lpar_old;
          }
        }
        if ( -f "$wrkdir/$managedname/$host/$lpar_old.rrh" ) {
          RRDp::cmd qq(last "$wrkdir/$managedname/$host/$lpar_old.rrh" );
          my $last_rec = RRDp::read;
          chomp($$last_rec);
          if ( $$last_rec > $tstamp ) {

            #print "004 $wrkdir/$managedname/$host/$lpar_old.rrh $$last_rec $tstamp\n";
            $tstamp      = $$last_rec;
            $lpar_recent = $lpar_old;
          }
        }
      }
    }
  }
  $lpar_old = $lpar_recent;

  if ( $lpar_old =~ m/^$lpar$/ ) {
    return 1;    # actual lpar has most recent data, keep it as it is
  }

  if ( !$lpar_recent eq '' ) {

    # Temporary -PH to debug an issue after LPM
    print STDERR "LPAR rename    : $host:$managedname: $lpar_old --> $lpar_slash : $serial\n" if $DEBUG;
    return 1;

    print "LPAR rename    : $host:$managedname: $lpar_old --> $lpar_slash\n" if $DEBUG;
    touch("lpar rename $host:$managedname: $lpar");

    # place lpar name and time spamp into rename.tmp file
    # there will not be created for 10minutes since then timestap a lpar with the same name
    # problem after a rename is that during next run there appear a few record with the originl lpar and
    #  new rrdtool files are created altough they should not --> problem with aggregated graphs (lpar & mem)
    my $rename_tmp = "$wrkdir/$managedname/$host/rename.tmp";
    open( FR, ">> $rename_tmp" ) || main::error( " Can't open $rename_tmp : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FR "$time_rec:$lpar_old\n";
    close(FR);

    # at first find out last used if there is found more same serial (some rename in the past)
    if ( -f "$wrkdir/$managedname/$host/$lpar_old.rrm" ) {
      if ( -f "$wrkdir/$managedname/$host/$lpar.rrm" ) {
        print "LPAR rename org: $host:$managedname: $lpar.rrm --> $lpar.rrm-old\n" if $DEBUG;
        rename( "$wrkdir/$managedname/$host/$lpar.rrm", "$wrkdir/$managedname/$host/$lpar.rrm-old" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar.rrm $wrkdir/$managedname/$host/$lpar.rrm-old: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print "LPAR rename    : $host:$managedname: $lpar_old --> $lpar_slash : rrm\n" if $DEBUG;
      rename( "$wrkdir/$managedname/$host/$lpar_old.rrm", "$wrkdir/$managedname/$host/$lpar.rrm" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar_old.rrm $wrkdir/$managedname/$host/$lpar.rrm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    if ( -f "$wrkdir/$managedname/$host/$lpar_old.rrd" ) {
      if ( -f "$wrkdir/$managedname/$host/$lpar.rrd" ) {
        print "LPAR rename org: $host:$managedname: $lpar.rrd --> $lpar.rrd-old\n" if $DEBUG;
        rename( "$wrkdir/$managedname/$host/$lpar.rrd", "$wrkdir/$managedname/$host/$lpar.rrd-old" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar.rrd $wrkdir/$managedname/$host/$lpar.rrd-old: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print "LPAR rename    : $host:$managedname: $lpar_old --> $lpar_slash : rrd\n" if $DEBUG;
      rename( "$wrkdir/$managedname/$host/$lpar_old.rrd", "$wrkdir/$managedname/$host/$lpar.rrd" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar_old.rrd $wrkdir/$managedname/$host/$lpar.rrd: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    if ( -f "$wrkdir/$managedname/$host/$lpar_old.rrh" ) {
      if ( -f "$wrkdir/$managedname/$host/$lpar.rrh" ) {
        print "LPAR rename org: $host:$managedname: $lpar.rrh --> $lpar.rrh-old\n" if $DEBUG;
        rename( "$wrkdir/$managedname/$host/$lpar.rrh", "$wrkdir/$managedname/$host/$lpar.rrh-old" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar.rrh $wrkdir/$managedname/$host/$lpar.rrh-old: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print "LPAR rename    : $host:$managedname: $lpar_old --> $lpar_slash : rrh\n" if $DEBUG;
      rename( "$wrkdir/$managedname/$host/$lpar_old.rrh", "$wrkdir/$managedname/$host/$lpar.rrh" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar_old.rrh $wrkdir/$managedname/$host/$lpar.rrh: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    if ( -f "$wrkdir/$managedname/$host/$lpar_old.rmm" ) {
      if ( -f "$wrkdir/$managedname/$host/$lpar.rmm" ) {
        print "LPAR rename org: $host:$managedname: $lpar.rmm --> $lpar.rmm-old\n" if $DEBUG;
        rename( "$wrkdir/$managedname/$host/$lpar.rmm", "$wrkdir/$managedname/$host/$lpar.rmm-old" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar.rmm $wrkdir/$managedname/$host/$lpar.rmm-old: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print "LPAR rename    : $host:$managedname: $lpar_old --> $lpar_slash : rmm\n" if $DEBUG;
      rename( "$wrkdir/$managedname/$host/$lpar_old.rmm", "$wrkdir/$managedname/$host/$lpar.rmm" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar_old.rmm $wrkdir/$managedname/$host/$lpar.rmm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    if ( -f "$wrkdir/$managedname/$host/$lpar_old.rsm" ) {
      if ( -f "$wrkdir/$managedname/$host/$lpar.rsm" ) {
        print "LPAR rename org: $host:$managedname: $lpar.rsm --> $lpar.rsm-old\n" if $DEBUG;
        rename( "$wrkdir/$managedname/$host/$lpar.rsm", "$wrkdir/$managedname/$host/$lpar.rsm-old" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar.rsm $wrkdir/$managedname/$host/$lpar.rsm-old: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print "LPAR rename    : $host:$managedname: $lpar_old --> $lpar_slash : rsd\n" if $DEBUG;
      rename( "$wrkdir/$managedname/$host/$lpar_old.rsm", "$wrkdir/$managedname/$host/$lpar.rsm" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar_old.rsm $wrkdir/$managedname/$host/$lpar.rsm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    if ( -f "$wrkdir/$managedname/$host/$lpar_old.rsd" ) {
      if ( -f "$wrkdir/$managedname/$host/$lpar.rsd" ) {
        print "LPAR rename org: $host:$managedname: $lpar.rsd --> $lpar.rsd-old\n" if $DEBUG;
        rename( "$wrkdir/$managedname/$host/$lpar.rsd", "$wrkdir/$managedname/$host/$lpar.rsd-old" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar.rsd $wrkdir/$managedname/$host/$lpar.rsd-old: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print "LPAR rename    : $host:$managedname: $lpar_old --> $lpar_slash : rsd\n" if $DEBUG;
      rename( "$wrkdir/$managedname/$host/$lpar_old.rsd", "$wrkdir/$managedname/$host/$lpar.rsd" ) || main::error( " Cannot mv $wrkdir/$managedname/$host/$lpar_old.rsd $wrkdir/$managedname/$host/$lpar.rsd: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }

    # here delete LPM stuff, it will be recreated during next run for proper lpar names
    foreach my $lpm (<"$wrkdir/$managedname/$host/$lpar_old=====*=====*rrk">) {
      my $file_link = readlink("$lpm");
      print "LPAR rename lpm: $host:$managedname: $lpar_old --> $lpar_slash : $lpm --> $file_link\n" if $DEBUG;
      unlink("$file_link");
      unlink("$lpm");
    }
    foreach my $lpm (<"$wrkdir/$managedname/$host/$lpar_old=====*=====*rrl">) {
      my $file_link = readlink("$lpm");
      print "LPAR rename lpm: $host:$managedname: $lpar_old --> $lpar_slash : $lpm --> $file_link\n" if $DEBUG;
      unlink("$file_link");
      unlink("$lpm");
    }
  }

  #else {
  #  print "LPAR rename    : $host:$managedname: $lpar:$serial has not been found for rename\n" if $DEBUG ;
  #}

  return 1;
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

  open( FR, "< $rename_tmp" ) || main::error( " Can't open $rename_tmp : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my @lines = <FR>;
  close(FR);
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
  return;
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

  if ( !-s "$rrd_file" ) {

    # fila has 0 size, remove it directly
    main::error("file $rrd_file has zero size, removing it");
    unlink("$rrd_file") || main::error( "Cannot rm $rrd_file : $!" . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  # Since 5.06: remove rrd file only if these errors appear:
  # ERROR: fetching cdp from rra at-
  # ERROR: reading the cookie off-
  # ERROR: short read while reading header rrd->stat_head
  # ERROR: mmaping file

  # Ignore everything else like to do not remove live data by a mistake
  # ERROR: This RRD was created on another architecture

  if ( $err_text =~ m/ERROR:/ && ( $err_text =~ m/mmaping file/ || $err_text =~ m/fetching cdp from rra/ || $err_text =~ m/reading the cookie off/ || $err_text =~ m/short read while reading header/ ) ) {

    # copy of the corrupted file into "save" place and remove the original one
    my $hmc_dir       = dirname($rrd_file);
    my $server_dir    = dirname($hmc_dir);
    my $server        = basename($server_dir);
    my $all_save_path = "$tmpdir/$server";
    if ( !-d "$all_save_path" ) {
      mkdir( "$all_save_path", 0755 ) || main::error( " Cannot mkdir $all_save_path: $!" . __FILE__ . ":" . __LINE__ );
    }
    copy( "$rrd_file", "$all_save_path/" ) || main::error( "Cannot: cp $rrd_file $all_save_path/: $!" . __FILE__ . ":" . __LINE__ );

    unlink("$rrd_file") || main::error( "Cannot rm $rrd_file : $!" . __FILE__ . ":" . __LINE__ );
    main::error("$err_text, moving it into: $all_save_path/");
  }
  else {
    main::error("$err_text");    # do no6t place here file & row because it is already in the message
  }
  return 0;
}

sub touch_LPM {
  my $text = shift;

  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-LPM";
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

# it return idle cycles_init from $lpar_name-idle.txt or saves it and returns original one
sub get_lpar_idle_count {
  my $wrkdir      = shift;
  my $host        = shift;
  my $managedname = shift;
  my $lpar_name   = shift;
  my $cycles_init = shift;
  my $type        = shift;

  my $file_idle = "$wrkdir/$managedname/$host/$lpar_name-idle.txt";

  if ( $type =~ m/force/ ) {

    # do not get anything from file, save actual one
    open( FHLT, "> $file_idle" ) || main::error( " Can't open $file_idle : $! " . __FILE__ . ":" . __LINE__ ) && return $cycles_init;
    print FHLT "$cycles_init";
    close(FHLT);
    return $cycles_init;
  }

  if ( !-f $file_idle ) {
    open( FHLT, "> $file_idle" ) || main::error( " Can't open $file_idle : $! " . __FILE__ . ":" . __LINE__ ) && return $cycles_init;
    print FHLT "$cycles_init";
    close(FHLT);
  }
  else {
    open( FHLT, "< $file_idle" ) || main::error( " Can't open $file_idle : $! " . __FILE__ . ":" . __LINE__ ) && return $cycles_init;
    my @lines = <FHLT>;
    close(FHLT);
    foreach my $line (@lines) {
      chomp($line);
      $cycles_init = $line;
      last;
    }
  }

  return $cycles_init;
}

sub load_data_hea {
  my $HEA;
  my $time        = "";
  my $counter     = 0;
  my $counter_tot = 0;
  my $counter_ins = 0;
  my $rrd         = "";
  my $rrd_max     = "";
  my $utime       = time() + 3600;
  my $jump        = 0;
  my $last_time   = "";

  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $input_hea, $no_time, $json_configured, $save_files ) = @_;
  if (!defined $json_configured) { $json_configured = ""; }
  if (!defined $save_files) { $save_files = ""; }
  if ( $json_configured eq "1" ) {
    my $perf_string = "hea_perf";
    my $iostatdir   = "$wrkdir/$managedname/$host/iostat/";
    opendir( DIR, $iostatdir ) || main::error( "directory does not exists : $iostatdir " . __FILE__ . ":" . __LINE__ ) && return 0;

    my @files_unsorted = grep( /$perf_string/, readdir(DIR) );
    my @files          = sort { lc $a cmp lc $b } @files_unsorted;

    #cyklus prochazejici json file po timestamp -> cyklus proch. json file po lparech (ziskam stejnou lajnu)
    my $ltiph;
    my $saved_ts;
    my $temp_ts;
    if ( -e "$wrkdir/$managedname/$host/iostat/last_ts.hea" ) {
      open( $ltiph, "<", "$wrkdir/$managedname/$host/iostat/last_ts.hea" ) || main::error( "Cannot open file $wrkdir/$managedname/$host/iostat/last_ts.hea at" . __LINE__ );
      $saved_ts = readline($ltiph);
      close($ltiph);
    }
    else {
      $saved_ts = "not_defined";
    }
    if ( !@files ) {
      return;
    }
    foreach my $file (@files) {
      print "Rest API       " . strftime( "%FT%H:%M:%S", localtime(time) ) . "        : inserting $host $managedname $file to rrd files\n" if $DEBUG;
      my $path = "$iostatdir$file";
      if ( !( -e $path ) ) {
        next;
      }

      #$content = HASH(###);
      my $content = [];
      $content = Xorux_lib::read_json($path) if ( -e $path );
      if ( !defined $content || $content eq "-1" || ref($content) eq "HASH" ) {
        print "$file is not valid : $content\n";
        unlink($path);
        next;
      }
      my $temp_ts;
      foreach my $sample ( @{$content} ) {
        my $ts = $sample->[0];
        my $t  = str2time( substr( $ts, 0, 19 ) );
        $temp_ts = $t;
        my $physicalLocation = $sample->[1];
        my $read             = $sample->[2];
        my $io_read          = $sample->[3];
        my $write            = $sample->[4];
        my $io_write         = $sample->[5];
        ( undef, undef, my $short_physloc ) = split( "\\.", $physicalLocation );
        $short_physloc = "" if (!defined $short_physloc);
        $rrd = "$wrkdir/$managedname/$host/adapters/$short_physloc.rah$type_sam";    #m;
        if (!defined $HEA->{$rrd}{last_update}){
          if ( !-e $rrd ) {
            my $ret = create_rrd_gpa( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
          }
        }
        my $last_rec;
        my $ltime;
        if (!defined $HEA->{$rrd}{last_update}){
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;
          };
          if ($@) {
            rrd_error( $@, $rrd );
            next;
          }
          chomp($$last_rec);
          $ltime = $$last_rec;
          $HEA->{$rrd}{last_update} = $$last_rec;
        }
        if ( $t > $HEA->{$rrd}{last_update} ) {    #&& length($vios_name) > 0 )
          if ( !( main::isdigit($io_read) ) )  { $io_read  = "U"; }
          if ( !( main::isdigit($read) ) )     { $read     = "U"; }
          if ( !( main::isdigit($io_write) ) ) { $io_write = "U"; }
          if ( !( main::isdigit($write) ) )    { $write    = "U"; }
          RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write);
          $last_time = $ts;
          my $answer = RRDp::read;
          $ltime = $t;
        }
      }

      ##unlink ($path) || print("Cannot delete file $path ". __FILE__. ":". __LINE__);
      if ( defined $file && defined $files[-1] && defined $files[-2] ) {
        if ( $file eq $files[-1] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/hea_perf1" );
        }
        if ( $file eq $files[-2] ) {
          copy( $path, "$ENV{INPUTDIR}/tmp/$managedname/hea_perf2" );
        }
      }
      if ( $save_files =~ /^-?\d+$/ ) {
        if ( $save_files == 0 ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      else {
        if ( $save_files ne $managedname ) {
          if ( $PROXY_SEND != 2 ) {
            unlink($path) || main::error( "Cannot unlink $path in " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      open( $ltiph, ">", "$wrkdir/$managedname/$host/iostat/last_ts.hea" );
      print $ltiph "$temp_ts";
      close($ltiph);
    }    #end foreach my $file
  }    #end if (json configured)
  else {
    return;    # HEA is loaded from separated cron job or Rest API, no in-m file is supported
    open( FH, "< $input_hea-$type_sam" ) || main::error( " Can't open $input_hea-$type_sam : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lines = reverse <FH>;
    close(FH);
    foreach my $line (@lines) {
      my $ltime            = 0;
      my $rrd_exist_ok     = 0;
      my $rrd_exist_ok_max = 0;
      chomp($line);
      ( $time, my $vios_name, my $id, my $physicalLocation, my $io_read, my $io_write, my $read, my $write ) = split( /,/, $line );
      my $ret = substr( $time, 0, 1 );
      if ( $ret =~ /\D/ ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid adapters data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      my $t = str2time( substr( $time, 0, 19 ) );
      if ( length($t) < 10 ) {

        # leave it as wrong input data
        main::error( "$host:$managedname : No valid adapters data got from HMC :$ret : $line " . __FILE__ . ":" . __LINE__ );
        next;
      }
      if ( $step == 3600 ) {

        # Put on the last time possition "00"!!!
        substr( $t, 8, 2, "00" );
      }
      my $dirname_tmp = "$wrkdir/$managedname/$host/adapters/";
      $rrd = "$wrkdir/$managedname/$host/adapters/$physicalLocation.rap$type_sam";

      #create rrd db if necessary
      if ( $rrd_exist_ok == 0 ) {
        my $ret = create_rrd_gpa( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time );
        if ( $ret == 2 ) {
          return 1;    # RRD creation problem, skip whole load
        }
        $rrd_exist_ok = 1;
      }

      if ( $ltime == 0 ) {

        # construction against crashing daemon Perl code when RRDTool error appears
        # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
        # construction is not too costly as it runs once per each load
        my $last_rec = 0;
        eval {
          RRDp::cmd qq(last "$rrd" );
          $last_rec = RRDp::read;
        };
        if ($@) {
          rrd_error( $@, $rrd );
          $rrd_exist_ok = 0;
          next;
        }
        chomp($$last_rec);
        $ltime = $$last_rec;
      }

      # it updates only ifl time is newer and there is the data (fix for situation that the data is missing)
      if ( $t > $ltime ) {    #&& length($vios_name) > 0 ) {
        my $jump_time = $ltime + $JUMP_DETECT;    #set time for sudden jump detection (15mins)
        if ( $t > $jump_time ) {

          # here appeared sudden gap in the data, migh be an issue with HMC 77202 when appears a row with future timestamp
          # ignore this line, if that happens next time then it is ok, just one data stamp has been lost :)
          if ( $jump == 0 ) {
            $jump = 1;

            #main::error ("$host:$managedname: future data timestamp detected : $line, last rec: $ltime utime data:$t");
            #main::error ("$host:$managedname: future timestamp: $rrd : ignoring the line ...");
            next;
          }

          # looks like it is ok as it is second timestap in a row
        }
        $jump = 0;
        $counter_ins++;

        #print "$counter_ins : $time $t:$promenne \n";

        #RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write);
        if ( !( main::isdigit($read) ) )     { $read     = "U"; }
        if ( !( main::isdigit($io_read) ) )  { $io_read  = "U"; }
        if ( !( main::isdigit($write) ) )    { $write    = "U"; }
        if ( !( main::isdigit($io_write) ) ) { $io_write = "U"; }
        RRDp::cmd qq(update "$rrd" $t:$read:$io_read:$write:$io_write);

        $last_time = $time;
        my $answer = RRDp::read;

        # update the time of last record
        $ltime = $t;
      }
    }
    if ( $counter_ins > 0 ) {
      print "inserted       : $host:$managedname:fiber_channel_adapters $counter_ins record(s)\n" if $DEBUG;
    }
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file\n" if $DEBUG;
    open( FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    print FHLT "$last_time";
    close(FHLT);
  }

  return 0;
}

sub correct_to_local_timezone {
  my $t              = shift;
  my $hmc_timezone   = shift;
  my $local_timezone = shift;

  if ( !( main::isdigit($hmc_timezone) && ( main::isdigit($local_timezone) ) ) ) {
    return $t;
  }

  if ( !defined $hmc_timezone || $hmc_timezone eq "") {
    $hmc_timezone = "+0000";
  }
  if ( !defined $local_timezone || $local_timezone eq "") {
    $local_timezone = "+0000";
  }

  my $hmc_t = $hmc_timezone / 100;
  my $loc_t = $local_timezone / 100;
  if ( $hmc_t > $loc_t ) {
    my $c = $hmc_t - $loc_t;
    $t = $t - ( $c * 3600 );
  }
  else {
    my $c = $loc_t - $hmc_t;
    $t = $t + ( $c * 3600 );
  }

  return $t;
}
