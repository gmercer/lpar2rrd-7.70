package LoadDataModuleVMWare;    #
use strict;
use Date::Parse;

# use RRDp;
use File::Copy;
use File::Basename;
use Xorux_lib;
use Math::BigInt;

# Next Generation
my $NG = ( defined $ENV{NG} ) ? 1 : 0;

use if !$NG, "RRDp";

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

# export VMWARE_PROXY_SEND=1 or 2
my $store_data = 1;
if ( defined $ENV{VMWARE_PROXY_SEND} && $ENV{VMWARE_PROXY_SEND} == 1 ) {
  $store_data = 0;
}

# it checks if rrdtool supports graphv --> then zoom is supported
# it checks if rrdtool supports --right-axis (used for vmware cpu graphing - since 1.2015)
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

  $graph_cmd   = "--right-axis";
  $graphv_file = "$tmpdir/graph-right-axis";
  $ansx        = `$rrdtool graph $graph_cmd 2>&1`;

  if ( index( $ansx, "$graph_cmd" ) == -1 ) {    # OK when doesn't contain
                                                 # right-axis exists, create a file to pass it to cgi-bin commands
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

  # take files like 1599813464_10.22.11.10.txt # host_name is 10.22.11.10
  my @files = grep /^\d\d\d\d\d\d\d\d\d\d_$host_name\.txt$/, @all_items;

  if ( scalar @files < 1 ) {
    print "push_data_from_timed_files: no files.txt for host name $host_name detected\n";
    return 0;
  }
  my @snd_files    = grep /^\d\d\d\d\d\d\d\d\d\d_$host_name.snd$/,          @all_items;
  my @tar_files    = grep /^\d\d\d\d\d\d\d\d\d\d_$host_name\.txt\.tar$/,    @all_items;
  my @tar_gz_files = grep /^\d\d\d\d\d\d\d\d\d\d_$host_name\.txt\.tar.gz$/, @all_items;

  # delete older tar files
  # do it before the rrd operation because it can stuck and then the files can fill disk space
  foreach my $file_n (@tar_files) {
    my $file  = "$vmware_data_dir$file_n";
    my $mtime = ( stat($file) )[9];
    if ( time - $mtime > 150 * 60 ) {
      if ( !unlink "$file" ) {
        main::error( " Can't unlink $file : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
  }

  print "\$wrkdir is     : $wrkdir\n";
  if ( !$NG ) {

    # start RRD via a pipe
    RRDp::start "$rrdtool";

    my $rrdtool_version = 'Unknown';
    $_ = `$rrdtool`;
    if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
      $rrdtool_version = $1;
    }
    print "RRDp    version: $RRDp::VERSION \n";
    print "RRDtool version: $rrdtool_version\n";

    rrdtool_graphv();
  }
  print "sta VMWARE push: " . localtime() . " host name $host_name\n" if $DEBUG;

  my $total_files = scalar @files;
  my $file_index  = 1;
  foreach my $file_n ( sort @files ) {
    my $file_txt = "$vmware_data_dir$file_n";
    my $file     = $file_txt;
    $file =~ s/txt$/snd/;
    if ( !move( $file_txt, $file ) ) {    # rename file as 1st so it is not sent again if any error
      main::error("cannot move $file_txt to $file");
      next;
    }

    print "reading file   : $file " . localtime() . " ($file_index). from $total_files\n";
    $file_index++;
    my $skipped_lines = 0;
    my $line_count    = 0;

    if ($store_data) {
      open( my $XFHLT, "< $file" ) || main::error( " Can't open $file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      while ( my $line = <$XFHLT> ) {
        $line_count++;
        my ( $frase, $managedname, $host, $wrkdir_upd, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $vm_uuid, $hmc_user, $lpar_uuid, $entity_type, $frk, $data_line ) = split( ",", $line, 21 );

        #$wrkdir_upd is not used
        my $update_word = "update_";
        my $count       = () = $line =~ /$update_word/g;
        if ( $count != 2 ) {    # the string must be there 2x
          main::error("push_data_from_timed_files \$count of update_ is $count, line $line_count is skipped \$data_line $data_line");
          $skipped_lines++;
          next;
        }
        chomp $data_line;
        if ( $data_line =~ /,xorux_sentinel$/ ) {
          $data_line =~ s/,xorux_sentinel$//;
        }
        else {
          main::error("no ,xorux_sentinel at the end of update_line $line_count $data_line");
          $skipped_lines++;
          next;
        }

        # next if data_line contains not allowed chars
        my $test_line = $data_line;
        $test_line =~ s/[\d\s\,U\.\'\-]//g;

        # next if $test_line ne "";
        if ( $test_line ne "" ) {
          main::error("\$test_line $line_count has notallowed chars $test_line\n $data_line");
          $skipped_lines++;
          next;
        }

        # print "$managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $vm_uuid, $hmc_user, $lpar_uuid, $entity_type, $frk, $data_line\n";
        push_data_to_rrd( $managedname, $host, $wrkdir, \$data_line, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, \@arr, $last_file, $no_time, $vm_uuid, $hmc_user, $lpar_uuid, $entity_type, $frk );
      }
      close($XFHLT);
      print "reading file   : end $vmware_data_dir$file_n " . localtime() . " \$skipped_lines=$skipped_lines from total $line_count\n";
    }    ## if ($store_data)
    else {
      print "do not store  : data cus VMWARE_PROXY_SEND=1\n";
    }

    # if proxy NG then adjust/overwrite next if
    if ( !$NG ) {

      # rename the file back to txt
      if ( !copy( $file, $file_txt ) ) {
        main::error("cannot move $file to $file_txt");
        next;
      }

      my $tar_result = `cd $vmware_data_dir; tar -cvhf "$file_txt.tar" "$file_n" 2>&1`;    #
      print "tar_result $tar_result\n";
      if ( -f "$file_txt.tar" ) {
        if ( !unlink $file_txt ) {
          main::error("cannot unlink $file_txt");
        }
        else {
          utime undef, undef, "$file_txt.tar";    # set the file's access and modification times to the current time
        }
      }
      else {
        main::error("cannot tar $file_txt");
      }
    }
  }

  # delete older snd files
  foreach my $file_n (@snd_files) {
    my $file  = "$vmware_data_dir$file_n";
    my $mtime = ( stat($file) )[9];
    if ( time - $mtime > 150 * 60 ) {
      if ( !unlink "$file" ) {
        main::error( " Can't unlink $file : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
  }

  #  # delete older tar files
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
  foreach my $file_n (@tar_gz_files) {
    my $file  = "$vmware_data_dir$file_n";
    my $mtime = ( stat($file) )[9];
    if ( time - $mtime > 150 * 60 ) {
      if ( !unlink "$file" ) {
        main::error( " Can't unlink $file : $!" . __FILE__ . ":" . __LINE__ );
      }
    }
  }

  if ( !$NG ) {

    # close RRD pipe
    RRDp::end;
  }

  print "end VMWARE push: " . localtime() . " host name $host_name\n" if $DEBUG;

  return 99;    # symbol of success
}

#sub load_data {    # from VMWARE
#  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $vm_uuid, $hmc_user, $lpar_uuid, $entity_type, $frk ) = @_;
#
#  if ( -f "$data_file" && ( !move "$data_file", "$data_file_tmp" ) ) {
#    main::error( " Can't move $data_file to $data_file_tmp : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
#  }
#  open( my $fhload, ">> $data_file_tmp" ) || main::error( " Can't open $data_file_tmp : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
#  print $fhload "$managedname,$host,$wrkdir,$input,$type_sam,$act_time,$HMC,$IVM,$SDMC,$step,$DEBUG,$trans_tmp,$last_file,$no_time,$vm_uuid,$hmc_user,$lpar_uuid,$entity_type,$frk,$$input\n";
#  close($fhload);
#  if ( !move "$data_file_tmp", "$data_file" ) {
#    main::error( " Can't move $data_file_tmp to $data_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
#  }
#  return 99;       # symbol of success
#}

sub push_data_to_rrd {    # read data from $data_file
  my ( $managedname, $host, $wrkdir, $input, $type_sam, $act_time, $HMC, $IVM, $SDMC, $step, $DEBUG, $trans_tmp, $last_file, $no_time, $vm_uuid, $hmc_user, $lpar_uuid, $entity_type, $frk ) = @_;
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

  if ( $step > 60 ) {
    $JUMP_DETECT = 10800;    # 3 hours
  }
  if ( $type_sam =~ m/d/ ) {
    $JUMP_DETECT = 178000    # 2 days + for daily graphs/feed
  }

  # print "updating RRD   : $host:$managedname:data:$wrkdir/$managedname/$host/$lpar_uuid.rr$type_sam $frk\n" if $DEBUG;

  my @lines;
  my $update_line = $$input;

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

    # print "updating RRD   : \$wrkdir/$managedname/$host/$lpar/$vm_uuid.rr$type_sam $frk\n" if $DEBUG;
    print "updating RRD   : \$wrkdir/$managedname/$host/$lpar/$vm_uuid.rr$type_sam\n" if $DEBUG;
  }
  else {
    # print "updating RRD   : \$wrkdir/$managedname/$host/$lpar.rr$type_sam $frk\n" if $DEBUG;
    print "updating RRD   : \$wrkdir/$managedname/$host/$lpar.rr$type_sam\n" if $DEBUG;
  }

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
    if ( !$NG ) {
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
    }
    else {
      if ( !-f $rrd ) {
        main::error("LoadDataModuleVMWare.pm: line skipped:$managedname,$host,$rrd(! exists) $line\n");
        return $no_inserted;    # no success
      }
      my $epoch_timestamp = ( stat($rrd) )[9];
      $lpar_name[$l_count] = $lpar;
      $lpar_time[$l_count] = $epoch_timestamp;
      $lpar_jump[$l_count] = 0;
      $ltime               = $epoch_timestamp;
      print "last record from rrdfile $rrd \$ltime ,$ltime,\n";
    }

    # print "last record from rrdfile $rrd \$ltime ,$ltime,\n";
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

  my $not = "   ";    # to tell the true if inserted or not
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

    if ( !$NG ) {

      # for esxi test if rrd has DS 'Power_usage_Watt', if not then add it by tune or dump->restore for older rrdtool version
      if ( index( $rrd, "pool.rrm" ) > -1 ) {                 # skip this if when debug old data not having Power usage
        RRDp::cmd qq(info "$rrd");
        my $answer = RRDp::read;
        if ( defined $$answer && $$answer =~ "ERROR" ) {
          main::error("Rrdtool error : $$answer");
        }

        # print "$$answer\n";  # "DS:Power_usage_Watt:GAUGE:$no_time_new:0:U"
        my $new_ds = "Power_usage_Watt";
        if ( index( $$answer, $new_ds ) < 0 ) {
          print "creating DS   : $new_ds in file $rrd\n";
          RRDp::cmd qq(tune "$rrd" "DS:$new_ds:GAUGE:1080:0:U");
          $answer = RRDp::read;
          if ( defined $$answer && $$answer =~ "ERROR" ) {
            main::error("Rrdtool error : $$answer");
          }

          # and test if DS is inserted
          RRDp::cmd qq(info "$rrd");
          $answer = RRDp::read;
          if ( defined $$answer && $$answer =~ "ERROR" ) {
            main::error("Rrdtool error : $$answer");
          }

          # print "$$answer\n";  # "DS:Power_usage_Watt:GAUGE:$no_time_new:0:U"
          if ( index( $$answer, $new_ds ) < 0 ) {

            # probably old rrdtool version < 1.5 where 'tune' was not adding new DS
            # try with rrdtool dump->change the xml->restore
            my $DStoadd      = "$new_ds:GAUGE:1080:0:NaN";
            my $file_name    = basename $rrd;
            my $rrd_file_dir = $rrd;
            $rrd_file_dir =~ s/$file_name//;

            my $result = add_ds_to_rrd( $rrd_file_dir, $file_name, $DStoadd );
            if ( !$result ) {
              main::error( "Cannot add DS:$DStoadd to file $rrd_file_dir/$file_name :" . __FILE__ . ":" . __LINE__ );
            }
          }
        }
      }
      eval {
        RRDp::cmd qq(update "$rrd" $update_line);

        if ( $counter_ins == 0 ) {
          $counter_ins++;    # just to force update last.txt
        }
        $answer = RRDp::read;
      };
      if ($@) {
        main::error(" $host:$managedname : $rrd : $t: : $line");
        $not = "NOT";
      }
    }
    else {    # just touch the file with last update time
      print "touch existing file utime $last_time, $last_time, $rrd\n";
      utime $last_time, $last_time, $rrd;
    }
  }
  else {
    if ( defined $t && defined $ltime ) {
      main::error("LoadDataModuleVMWare.pm: line skipped for file:$rrd,act time=$t,last time=$ltime $line\n");
      if ( ( $t + 86400 ) < $ltime ) {    # looks like more than 1 day future time, remove that file
        if ( unlink($rrd) ) {
          main::error("File $rrd with future last time=$ltime time=$t has been deleted\n");

          # update log
          my $vm_erased_log = "$basedir/logs/vm_erased.log-vmware";
          if ( open( my $info, ">>$vm_erased_log" ) ) {
            print localtime() . " File $rrd with future last time=$ltime time=$t has been deleted\n";
            close $info;
          }
          else {
            print "vmware erase   : cannot append $vm_erased_log\n";
          }
        }
        else {
          main::error("Can't remove file $rrd, it has future last time=$ltime time=$t\n");
        }
      }
    }
    else {
      main::error("LoadDataModuleVMWare.pm: line skipped:$managedname,$host,$rrd $line\n");
    }
  }
  if ( $counter_ins > 0 ) {

    # print "inserted       : $host:$managedname:lpar $counter_ins record(s) $frk\n" if $DEBUG;
    print "inserted $not   : $host:$managedname:lpar $counter_ins record(s)\n" if $DEBUG;
  }
  else {
    return $no_inserted;    # no success
  }

  # write down timestamp of last record
  if ( $type_sam !~ "d" && $counter_ins > 0 && $entity_type ne $et_VirtualMachine ) {
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

      # print "upd last_file  : $host: $last_time_print : \$wrkdir/$managedname/$host/$last_file $new_time instead of $old_time $frk\n" if $DEBUG;
      print "upd last_file  : $host: $last_time_print : \$wrkdir/$managedname/$host/$last_file $new_time instead of $old_time\n" if $DEBUG;
      open( my $FHLT, "> $wrkdir/$managedname/$host/$last_file" ) || main::error( " Can't open $wrkdir/$managedname/$host/$last_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      print $FHLT "$last_time";
      close($FHLT);
    }
  }

  return 99;    # symbol of success
}

sub create_rrd_vmware_vm {
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
  my $vm_uuid      = shift;      # for VM rrd under datastore for IOPS
  my $hmc_user     = shift;
  my $wrkdir       = shift;
  my $lpar         = shift;
  my $time_rec     = shift;
  my $keep_virtual = shift;
  my $entity_type  = shift;
  my $step_new     = $step;
  my $no_time_new  = $no_time;

  #  $start_time = 1430000000; # something old enough, do not use  passed $start_time!!!!
  $start_time = time - ( 24 * 3600 );    # for vmware good
  $start_time = 1662900000;              # for test case you can (have to) change it for older data

  my $ret = recent_rename( $host, $managedname, $lpar, $wrkdir, $DEBUG, $time_rec, $act_time );
  if ( $ret == 1 ) {

    # this lpar has been recently renamed, do not create rrdtool files
    return 1;
  }

  if ( -f "$rrd" ) {
    if ( -s "$rrd" == 0 ) {    # it was only signal file with no data
      if ( !$NG ) {
        `rm -f "$rrd"`;
      }
    }
    else {
      return 0;
    }
  }
  load_retentions( $step, $act_time );    # load data retentions
                                          # print "0000 $one_minute_sample - $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
  print "create_rrd_vmware_vm: $host:$managedname $rrd ; STEP=$step_new \n" if $DEBUG;
  touch("create_rrd_vmware_vm $rrd");

  # print "++ $rrd $start_time $step_new - $no_time_new \n";

  my $file_base_name = basename $rrd;
  my $rrd_file_dir   = $rrd;
  $rrd_file_dir =~ s/$file_base_name//;
  if ( !-d $rrd_file_dir ) {
    makex_path("$rrd_file_dir") || error( "Cannot mkdir $rrd_file_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  if ( $entity_type eq $et_ClusterComputeResource ) {

    # sometimes there is not created cluster directory (in proxy)
    # /home/proxy/lpar2rrd/data/vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28/cluster_domain-c314/cluster.rrc
    my $cluster_dir = $rrd;
    $cluster_dir =~ s/cluster.rrc$//;
    if ( !-d $cluster_dir ) {
      print "mkdir          : $cluster_dir" . __FILE__ . ":" . __LINE__;
      mkdir( "$cluster_dir", 0755 ) || main::error( " Cannot mkdir $cluster_dir: $!" . __FILE__ . ":" . __LINE__ );
    }
    if ( !$NG ) {
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
  }
  elsif ( $entity_type eq $et_ResourcePool && !$NG ) {
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
  elsif ( $entity_type eq $et_HostSystem && !$NG ) {
    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
        "DS:CPU_Alloc:GAUGE:$no_time_new:0:U"
        "DS:CPU_usage:GAUGE:$no_time_new:0:U"
        "DS:host_hz:GAUGE:$no_time_new:0:U"
        "DS:Memory_active:GAUGE:$no_time_new:0:U"
        "DS:Memory_granted:GAUGE:$no_time_new:0:U"
        "DS:Memory_baloon:GAUGE:$no_time_new:0:U"
        "DS:Disk_usage:GAUGE:$no_time_new:0:U"
        "DS:Disk_read:GAUGE:$no_time_new:0:U"
        "DS:Disk_write:GAUGE:$no_time_new:0:U"
        "DS:Network_usage:GAUGE:$no_time_new:0:U"
        "DS:Network_received:GAUGE:$no_time_new:0:U"
        "DS:Network_transmitted:GAUGE:$no_time_new:0:U"
        "DS:Memory_swapin:GAUGE:$no_time_new:0:U"
        "DS:Memory_swapout:GAUGE:$no_time_new:0:U"
        "DS:Memory_compres:GAUGE:$no_time_new:0:U"
        "DS:Memory_decompres:GAUGE:$no_time_new:0:U"
        "DS:CPU_usage_Proc:GAUGE:$no_time_new:0:U"
        "DS:Memory_Host_Size:GAUGE:$no_time_new:0:U"
        "DS:CPU_ready_ms:GAUGE:$no_time_new:0:U"
        "DS:Power_usage_Watt:GAUGE:$no_time_new:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );    #        "DS:Power_usage_Watt:GAUGE:$no_time_new:0:U" # remove above when debug old data not having Power usage
  }
  elsif ( $entity_type eq $et_Datastore && $rrd =~ /rrs$/ && !$NG ) {    # irregular update / 30 minutes

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
  elsif ( $entity_type eq $et_Datastore && $rrd =~ /rrt$/ && !$NG ) {    # regular update

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
  elsif ( $entity_type eq $et_Datastore && $rrd =~ /rru$/ && !$NG ) {    # regular update

    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
        "DS:Dstore_readLatency:GAUGE:$no_time_new:0:U"
        "DS:Dstore_writeLatency:GAUGE:$no_time_new:0:U"
        "DS:Dstore_maxDepth:GAUGE:$no_time_new:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );
  }
  elsif ( $entity_type eq $et_Datastore && $rrd =~ /rrv$/ && !$NG ) {    # regular update into datastore/vm_uuid.rrv IOPS

    RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
        "DS:vm_iops_read:GAUGE:$no_time_new:0:U"
        "DS:vm_iops_write:GAUGE:$no_time_new:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
        );
  }
  else {                                                                 # it is VM
    if ( !$NG ) {
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
        "DS:CPU_Alloc:GAUGE:$no_time_new:0:U"
        "DS:CPU_usage:GAUGE:$no_time_new:0:U"
        "DS:host_hz:GAUGE:$no_time_new:0:U"
        "DS:Memory_active:GAUGE:$no_time_new:0:U"
        "DS:Memory_granted:GAUGE:$no_time_new:0:U"
        "DS:Memory_baloon:GAUGE:$no_time_new:0:U"
        "DS:Disk_usage:GAUGE:$no_time_new:0:U"
        "DS:Disk_read:GAUGE:$no_time_new:0:U"
        "DS:Disk_write:GAUGE:$no_time_new:0:U"
        "DS:Network_usage:GAUGE:$no_time_new:0:U"
        "DS:Network_received:GAUGE:$no_time_new:0:U"
        "DS:Network_transmitted:GAUGE:$no_time_new:0:U"
        "DS:Memory_swapin:GAUGE:$no_time_new:0:U"
        "DS:Memory_swapout:GAUGE:$no_time_new:0:U"
        "DS:Memory_compres:GAUGE:$no_time_new:0:U"
        "DS:Memory_decompres:GAUGE:$no_time_new:0:U"
        "DS:CPU_usage_Proc:GAUGE:$no_time_new:0:U"
        "DS:vCPU:GAUGE:$no_time_new:0:U"
        "DS:CPU_ready_ms:GAUGE:$no_time_new:0:U"
        "RRA:AVERAGE:0.5:1:$one_minute_sample"
        "RRA:AVERAGE:0.5:5:$five_mins_sample"
        "RRA:AVERAGE:0.5:60:$one_hour_sample"
        "RRA:AVERAGE:0.5:300:$five_hours_sample"
        "RRA:AVERAGE:0.5:1440:$one_day_sample"
      );
    }
  }

  if ($NG) {
    `touch "$rrd"`;
  }
  else {
    if ( !Xorux_lib::create_check("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
      main::error( "unable to create $rrd : at " . __FILE__ . ": line " . __LINE__ );
      RRDp::end;
      RRDp::start "$rrdtool";
      return 2;
    }
  }

  my $vmware_signal_file = "$wrkdir/$managedname/$host/vmware.txt";
  if ( !-f "$vmware_signal_file" ) {
    `touch "$vmware_signal_file"`;    # it must be there
    touch("$vmware_signal_file");     # say install_html.sh that there was any change
  }
  return 0;
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
  open( my $fhret, "< $basedir/etc/retention.cfg" ) || main::error("Can't read from: $basedir/etc/retention.cfg: $!");

  my @lines = <$fhret>;
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

  close($fhret);

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

  open( my $fhrec, "< $rename_tmp" ) || main::error( " Can't open $rename_tmp : $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my @lines = <$fhrec>;
  close($fhrec);
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

sub makex_path {
  my $mypath = shift;

  #print "create this path $mypath\n"; # like mkdir -p
  my @base   = split( /\//, $mypath );
  my $c_path = "";
  foreach my $m (@base) {
    $c_path .= $m . "/";
    if ( -d $c_path )        {next}
    if ( !mkdir("$c_path") ) { return 0 }
    ;    # no success
    next;
  }
  return 1    # success
}

# sub to add a DS to an rrd
# add_ds_to_rrd (<path>, <filename>, <DS defintion>)
# Example: how to add a DS to the file vmstat.rrd in /home/users/hobbit/data/rrd
#  add_ds_to_rrd.pl( "/home/users/hobbit/data/rrd", "vmstat.rrd", "cpu_pc:GAUGE:600:1:NaN");

#my $DStoadd = "Power_usage_watt:GAUGE:1080:0:NaN";

sub add_ds_to_rrd {
  my $rrddir  = shift;
  my $infile  = shift;
  my $DStoadd = shift;

  my ( $dsname, $dstype, $dshb, $dsmin, $dsmax, $undef ) = split( /:/, $DStoadd );

  my $outfile_tmp = "/tmp/$infile" . "." . $$;
  print "$infile  ->  $outfile_tmp, add DS $DStoadd\n";
  my $f_dumped     = "$outfile_tmp" . ".xml";
  my $f_dumped_new = "$f_dumped" . ".new";

  RRDp::cmd qq(dump "$rrddir/$infile" "$f_dumped");
  my $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    main::error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      main::error("It needs to be removed due to corruption: $file");
    }
    else {
      main::error("Convert rrdtool error : $$answer");
    }
    return 0;
  }

  open( DF_IN,  "< $f_dumped" )    || main::error( "Cannot open for reading $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  open( DF_OUT, ">$f_dumped_new" ) || main::error( "Cannot open for writing $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $line;
  while ( $line = <DF_IN> ) {

    # Define new data source
    $line =~ s/<!-- Round Robin Archives -->/
	<ds>
		<name> $dsname <\/name>
		<type> $dstype <\/type>
		<minimal_heartbeat> $dshb <\/minimal_heartbeat>
		<min> $dsmin <\/min>
		<max> $dsmax <\/max>

		<!-- PDP Status -->
		<last_ds> NaN <\/last_ds>
		<value> 0.0000000000e+00 <\/value>
		<unknown_sec> 0 <\/unknown_sec>
	<\/ds>

	<!\-\- Round Robin Archives \-\->/;

    # Add empty entry to the values
    $line =~ s/<\/cdp_prep>/
	<ds>
		<primary_value> NaNic <\/primary_value>
		<secondary_value> NaN <\/secondary_value>
		<value> NaN <\/value>
		<unknown_datapoints> 0 <\/unknown_datapoints>
	<\/ds>
	<\/cdp_prep>/;

    # Add empty entries to the database
    $line =~ s/<\/row>/<v>NaN<\/v><\/row>/;

    #print "73 $line";
    print DF_OUT $line;
  }

  close(DF_IN)  or main::error( "Cannot close $f_dumped: $!" . __FILE__ . ":" . __LINE__ )     && return 0;
  close(DF_OUT) or main::error( "Cannot close $f_dumped_new: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  RRDp::cmd qq(restore "$f_dumped_new" "$outfile_tmp");
  $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    main::error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      main::error("It needs to be removed due to corruption: $file");
    }
    else {
      main::error("Convert rrdtool error : $$answer");
    }
    return 0;
  }
  move( "$rrddir/$infile", "$rrddir/$infile" . ".orig" ) || main::error( "Cannot move $rrddir/$infile to $rrddir/$infile" . ".orig: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  move( "$outfile_tmp",    "$rrddir/$infile" )           || main::error( "Cannot move $outfile_tmp to $rrddir/$infile: $!" . __FILE__ . ":" . __LINE__ )              && return 0;

  unlink $outfile_tmp;    #should not be here
  unlink $f_dumped;
  unlink $f_dumped_new;
  return 1;
}
return 1;
