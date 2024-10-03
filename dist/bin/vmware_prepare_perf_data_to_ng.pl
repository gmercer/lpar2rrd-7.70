# prepare csv for NG
use strict;
use Date::Parse;
use File::Copy;
use Xorux_lib;
use Math::BigInt;

my $JUMP_DETECT = 900;

my $et_VirtualMachine         = "VirtualMachine";
my $et_HostSystem             = "HostSystem";
my $et_Datastore              = "Datastore";
my $et_ResourcePool           = "ResourcePool";
my $et_Datacenter             = "Datacenter";
my $et_ClusterComputeResource = "ClusterComputeResource";

my $all_vmware_VMs = "vmware_VMs";
my $no_inserted    = 66;

my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $DEBUG  = $ENV{DEBUG};
my $wrkdir = "$basedir/data";

my $vmware_data_dir = "$tmpdir/VMWARE/";
my $data_file       = "$tmpdir/VMWARE/perf.txt";
my $data_file_tmp   = "$tmpdir/VMWARE/perf.tmp";
my $data_file_snd   = "$tmpdir/VMWARE/perf.snd";

# export VMWARE_PROXY_SEND=1 or 2
my $store_data = 1;
if ( defined $ENV{VMWARE_PROXY_SEND} && $ENV{VMWARE_PROXY_SEND} == 1 ) {
  $store_data = 0;
}

my $host_name = "10.22.111.4";

$host_name = "10.22.66.35";
my $FH;

my $exit_value = push_data_from_timed_files($host_name);
print "sub: push_data_from_timed_files has \$exit_value $exit_value\n";
exit;

sub push_data_from_timed_files {    # from VMWARE
  my $host_name = shift;
  my @arr       = ();

  my $dh;
  if ( !opendir( $dh, $vmware_data_dir ) ) {
    print " Can't open $vmware_data_dir : $! " . __FILE__ . ":" . __LINE__ . "\n";
    return 0;
  }

  # read whole dir
  my @all_items = readdir $dh;
  closedir($dh);

  # take files like 1599813464_10.22.11.10.txt.NG # host_name is 10.22.11.10
  my @files = grep /^\d\d\d\d\d\d\d\d\d\d_$host_name\.txt\.NG$/, @all_items;

  if ( scalar @files < 1 ) {
    print "push_data_from_timed_files: no files.txt.NG for host name $host_name detected\n";
    return 0;
  }

  #  my @snd_files    = grep /^\d\d\d\d\d\d\d\d\d\d_$host_name.snd$/,          @all_items;
  #  my @tar_files    = grep /^\d\d\d\d\d\d\d\d\d\d_$host_name\.txt\.tar$/,    @all_items;
  #  my @tar_gz_files = grep /^\d\d\d\d\d\d\d\d\d\d_$host_name\.txt\.tar.gz$/, @all_items;

  print "start VMW csv  : " . localtime() . " host name $host_name\n" if $DEBUG;

  foreach my $file_n ( sort @files ) {
    my $file       = "$vmware_data_dir$file_n";
    my $file_write = $file;
    $file_write =~ s/\.txt/\.csv/;
    print "reading file   : $vmware_data_dir$file_n " . localtime() . "\n";
    print "writing file   : $file_write " . localtime() . "\n";
    print "\$store_data $store_data\n";
    if ($store_data) {
      open( my $XFHLT, "< $file" ) || main::error( " Can't open $file : $!" . __FILE__ . ":" . __LINE__ ) && next;
      open $FH, ">$file_write" or error( "can't open $file_write $!" . __FILE__ . ":" . __LINE__ ) && next;

      while ( my $line = <$XFHLT> ) {
        my ( $frase, $managedname, $host, $wrkdir_upd, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $vm_uuid, $hmc_user, $lpar_uuid, $entity_type, $frk, $data_line ) = split( ",", $line, 21 );

        #$wrkdir_upd is not used
        next if $frase ne "update_line";
        my $update_word = "update_";
        my $count       = () = $line =~ /$update_word/g;
        if ( $count != 2 ) {    # the string must be there 2x
          main::error("push_data_from_timed_files \$count of update_ is $count, line is skipped \$data_line $data_line");
          next;
        }
        chomp $data_line;
        if ( $data_line =~ /,xorux_sentinel$/ ) {
          $data_line =~ s/,xorux_sentinel$//;
        }
        else {
          main::error("no ,xorux_sentinel at the end of update_line $data_line");
          next;
        }

        # next if data_line contains not allowed chars
        my $test_line = $data_line;
        $test_line =~ s/[\d\s\,U\.\'\-e]//g;

        # next if $test_line ne "";
        if ( $test_line ne "" ) {
          main::error("\$test_line has notallowed chars $test_line\n $data_line");
          next;
        }

        # print "$managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $vm_uuid, $hmc_user, $lpar_uuid, $entity_type, $frk, $data_line\n";
        push_data_to_csv( $managedname, $host, $wrkdir, \$data_line, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@arr, $last_file, $no_time, $vm_uuid, $hmc_user, $lpar_uuid, $entity_type, $frk );
      }
      close($XFHLT);
      close $FH;
    }    ## if ($store_data)
    else {
      print "do not store  : data cus VMWARE_PROXY_SEND=1\n";
    }

    #    my $tar_result = `cd $vmware_data_dir; tar -cvhf "$file.tar" "$file_n" 2>&1`;    #
    #    print "tar_result $tar_result\n";
    #    if ( -f "$file.tar" ) {
    #      if ( !unlink $file ) {
    #        main::error("cannot unlink $file");
    #      }
    #      else {
    #        utime undef, undef, "$file.tar";
    #      }
    #    }
    #    else {
    #      main::error("cannot tar $file");
    #    }
  }

  # delete older snd files
  #  foreach my $file_n (@snd_files) {
  #    my $file  = "$vmware_data_dir$file_n";
  #    my $mtime = ( stat($file) )[9];
  #    if ( time - $mtime > 150 * 60 ) {
  #      if ( !unlink "$file" ) {
  #        main::error( " Can't unlink $file : $!" . __FILE__ . ":" . __LINE__ );
  #      }
  #    }
  #  }

  # delete older tar files
  #  foreach my $file_n (@tar_files) {
  #    my $file  = "$vmware_data_dir$file_n";
  #    my $mtime = ( stat($file) )[9];
  #    if ( time - $mtime > 150 * 60 ) {
  #      if ( !unlink "$file" ) {
  #        main::error( " Can't unlink $file : $!" . __FILE__ . ":" . __LINE__ );
  #      }
  #    }
  #  }

  # delete older tar.gz files
  #  foreach my $file_n (@tar_gz_files) {
  #    my $file  = "$vmware_data_dir$file_n";
  #    my $mtime = ( stat($file) )[9];
  #    if ( time - $mtime > 150 * 60 ) {
  #      if ( !unlink "$file" ) {
  #        main::error( " Can't unlink $file : $!" . __FILE__ . ":" . __LINE__ );
  #      }
  #    }
  #  }

  print "end VMWARE csv : " . localtime() . " host name $host_name\n" if $DEBUG;

  return 99;    # symbol of success
}

sub push_data_to_csv {    # read data from $data_file
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $vm_uuid, $hmc_user, $lpar_uuid, $entity_type, $frk ) = @_;

  #update_line,10.22.66.27,10.22.66.35,/home/lpar2rrd/lpar2rrd/data,$update_string,m,Tue May 10 14:17:26 2022,1,0,0,60,1,@lpar_trans,last.txt,1080,,lpar2rrd,pool,HostSystem,(88307F0)
  my @lpar_trans   = @{$trans_tmp};
  my $counter      = 0;
  my $counter_tot  = 0;
  my $counter_ins  = 0;
  my $last_rec     = "";
  my $rrd          = "";
  my $time         = "";
  my $t            = "";
  my $answer       = "";
  my $utime        = time() + 3600;
  my $keep_virtual = 0;
  my $control_line = "";

  if ( $step > 60 ) {
    $JUMP_DETECT = 10800;    # 3 hours
  }
  if ( $type_sam =~ m/d/ ) {
    $JUMP_DETECT = 178000    # 2 days + for daily graphs/feed
  }

  # print "updating RRD   : $host:$managedname:data:$wrkdir/$managedname/$host/$lpar_uuid.rr$type_sam $frk\n" if $DEBUG;

  my @lines;
  my $update_line = $$input;
  chomp $update_line;
  $update_line =~ s/,/;/g;
  $update_line =~ s/ $/;/g;
  $update_line =~ s/ /\|/g;
  $update_line =~ s/U//g;
  {
    $et_HostSystem eq $entity_type && do {

      # $control_line = "199 chytil js Hostsystem a zde je uuid $managedname;val1;val2;...\n";
      $control_line = "ESXI uuid;time;cpu_alloc;cpu_usage;host;memory_active;memory_granted;memory_baloon;disk_usage;disk_read;disk_write;network_usage;network_received;network_transmitted;memory_swapin;memory_swapout;memory_compress;memory_decompress;cpu_usage_proc;memory_host_size;cpu_ready;\n";
      $update_line  = "$managedname;$update_line";
      last;
    };
    $et_VirtualMachine eq $entity_type && do {

      # $control_line = "199 chytil js $et_VirtualMachine a zde je uuid $lpar_uuid;val1;val2;...\n";
      $control_line = "VM uuid;time;cpu_alloc;cpu_usage;host_hz;memory_active;memory_granted;memory_baloon;disk_usage;disk_read;disk_write;network_usage;network_received;network_transmitted;memory_swapin;memory_swapout;memory_compress;memory_decompress;cpu_usage_proc;vcpu;cpu_ready;\n";
      $update_line  = "$lpar_uuid;$update_line";
      last;
    };
    $et_ResourcePool eq $entity_type && do {

      # $control_line = "199 chytil js $et_ResourcePool a zde je uuid $managedname" . "_" . "$lpar_uuid;val1;val2;...\n";
      $control_line = "RESOURCEPOOL uuid;time;cpu_usage;memory_shared;memory_zero;memory_baloon;memory_consumed;memory_overhead;memory_active;memory_granted;memory_compress;memory_swap;memory_cmprssion;memory_dcompress;cpu_limit;cpu_reservation;memory_limit;memory_reservation;cpu_usage_proc;\n";
      $update_line  = "$managedname" . "_" . "$lpar_uuid;$update_line";
      last;
    };
    $et_ClusterComputeResource eq $entity_type && do {

      # $control_line = "199 chytil js $et_ClusterComputeResource a zde je uuid $managedname" . "_" . "$host;val1;val2;...\n";
      $control_line = "CLUSTER uuid;time;cpu_usage;cpu_usage_proc;cpu_reserved;cpu_total;cluster_eff_cpu;cluster_eff_mem;memory_total;memory_shared;memory_zero;memory_baloon;memory_consumed;memory_overhead;memory_active;memory_granted;memory_compress;memory_reserved;memory_swap;memory_cmprssion;memory_dcompress;memory_usage_proc;\n";
      $update_line  = "$managedname" . "_" . "$host;$update_line";
      last;
    };
    ( $et_Datastore eq $entity_type && $type_sam eq "NG" ) && do {

      # $control_line = "199 chytil js $et_Datastore a zde je uuid $lpar_uuid;val1;val2;...\n";
      $control_line = "DATASTORE uuid;time;free_space;disk_used;disk_provisioned;disk_capacity;read;write;read_avg;write_avg;read_latency;write_latency;max_depth;\n";
      $update_line  = "$lpar_uuid;$update_line";
      last;
    };

    #update_line,vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28,datastore_datacenter-2,/home/lpar2rrd/lpar2rrd/data,$update_string,v,Tue May 10 14:17:26 2022,1,0,0,60,1,@lpar_trans,,5400,501ccfdf-20ac-cf81-09d4-0e0b20240e7e,lpar2rrd,59300962-070f1f4a-646e-18a90577a87c,Datastore,(88238F3)
    ( $et_Datastore eq $entity_type && $type_sam eq "v" ) && do {

      # $control_line = "199 chytil js $et_Datastore IOPS/VM a zde je uuid $lpar_uuid" . "_" . "$vm_uuid;val1;val2;...\n";
      $control_line = "DATASTORE_VM uuid;time;iops_read;iops_write;\n";
      $update_line  = "$lpar_uuid" . "_" . "$vm_uuid;$update_line";
    };
  }
  if ( $control_line eq "" ) {
    print "Unknown line $entity_type $type_sam $update_line\n";
  }
  else {
    print "\n\$control_line $control_line prepared line $update_line\n";
    print $FH "\n\$control_line $control_line prepared line $update_line\n";
  }
  return;

  ( $t, undef ) = split( ",", $update_line );    #first record time to update

  #  print "LoadDataModulVMWare \$t $t \$update_line $update_line\n";

  my @rrd_exist = "";

  my @lpar_name = "";
  my @lpar_time = "";
  my @lpar_jump = "";

  my $last_time       = "";
  my $error_once      = 0;
  my $last_time_print = 0;
  my $line            = $update_line;

  #print "$line";
  chomp($line);
  $time = "";
  my $lpar = $lpar_uuid;

  $rrd = "$wrkdir/$managedname/$host/$lpar.rr$type_sam";

  if ( $type_sam eq "v" ) {    # datastore/vm_uuid.rrv for VM IOPS in this datastore
    my $dir = "$wrkdir/$managedname/$host/$lpar";
    if ( !-d $dir ) {
      print "create dir     : datastore $dir\n";
      mkdir($dir) || main::error( "Cannot create dir  $dir : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    $rrd = "$dir/$vm_uuid.rr$type_sam";
  }

  print "updating RRD   : $rrd $frk\n" if $DEBUG;

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
  if ( $rrd_exist_ok == 0 ) {

    #print " create_rrd_vmware_vm($rrd,$t,$counter_tot,$step,$type_sam,$DEBUG,$host,$managedname,$no_time,$act_time,$vm_uuid,$hmc_user,$wrkdir,$lpar,$t,$keep_virtual,$entity_type);\n";
    my $ret = create_rrd_vmware_vm( $rrd, $t, $counter_tot, $step, $type_sam, $DEBUG, $host, $managedname, $no_time, $act_time, $vm_uuid, $hmc_user, $wrkdir, $lpar, $t, $keep_virtual, $entity_type );
    if ( $ret == 1 ) {

      # this lpar has been recently renamed, ignore it then
      return 1;    # when vmware then no next;
    }
    if ( $ret == 2 ) {
      return 1;    # RRD creation problem, skip whole load
    }
    $rrd_exist[$rrd_exist_row] = $lpar;
  }

  #  print "find out last record and save it\n";
  # it has to be done due to better stability, when updating older record than the latest one update and process crashes
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
    main::error( " this is not expected for vmware \$ltime ,$ltime, \$lpar ,$lpar, \@lpar_name ,@lpar_name, :" . __FILE__ . ":" . __LINE__ ) && return;
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
      return;
    }
    chomp($$last_rec);
    $lpar_name[$l_count] = $lpar;
    $lpar_time[$l_count] = $$last_rec;
    $lpar_jump[$l_count] = 0;
    $ltime               = $$last_rec;

    #  print "last record from rrdfile $rrd \$ltime $ltime\n";
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
    if ( !defined $t || $t eq "" ) {    # || $t !~ /\d\d\d\d\d\d\d\d\d\d/) left_curly
      $t = $ltime;
    }
    print "data skipped   : $skipped\n";
    if ( $t !~ /\d\d\d\d\d\d\d\d\d\d/ ) {    # bad unix time
      last;
    }
    $max_cycles--;
  }

  if ( defined $t ) {

    # print "               : \$t $t > \$ltime $ltime (first data time to update > last rec) VMWare $frk\n";
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
    $last_time       = "$mon/$mday/$year $hour:$min:$sec";    # change day <-> mon for US date format
    $last_time_print = "$hour:$min:$sec";                     # time is enough as it is never older one hour
    $update_line =~ s/,/:/g;

    eval {
      RRDp::cmd qq(update "$rrd" $update_line);

      if ( $counter_ins == 0 ) {
        $counter_ins++;    # just to force update last.txt
      }
      $answer = RRDp::read;
    };
    if ($@) {
      main::error(" $host:$managedname : $rrd : $t: : $line");
    }
  }
  else {
    if ( defined $t && defined $ltime ) {
      main::error("LoadDataModuleVMWare.pm: line skipped:$managedname,$host,$rrd,act time=$t,last time=$ltime $line\n");
    }
    else {
      main::error("LoadDataModuleVMWare.pm: line skipped:$managedname,$host,$rrd $line\n");
    }
  }
  if ( $counter_ins > 0 ) {
    print "inserted       : $host:$managedname:lpar $counter_ins record(s) $frk\n" if $DEBUG;
  }
  else {
    return $no_inserted;    # no success
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 ) {
    my $line = 0;
    if ( -f "$wrkdir/$managedname/$host/$last_file" ) {
      open( my $FHLT, "< $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ );
      $line = <$FHLT>;
      close($FHLT);
    }
    if ( !defined $line || index( $line, "/" ) < 0 ) {    # for sure
      $line = 0;
    }
    chomp($line);
    my $old_time = str2time($line);
    my $new_time = str2time($last_time);

    # print "upd last_file  : $host:$managedname $last_time : $wrkdir/$managedname/$host/$last_file $new_time instead of $old_time $frk\n" if $DEBUG;

    # update only when it is newer ! e.g. datastore has 2 rrd files and so on
    if ( $new_time > $old_time && $last_file ne "" ) {
      print "upd last_file  : $host: $last_time_print : $wrkdir/$managedname/$host/$last_file $new_time instead of $old_time $frk\n" if $DEBUG;
      open( my $FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      print $FHLT "$last_time";
      close($FHLT);
    }
  }

  return 99;    # symbol of success
}

sub touch {
  my $text = shift;

  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-vmware";
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

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  # print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
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

# return 1;
