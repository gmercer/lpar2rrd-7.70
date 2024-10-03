# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=perl
use strict;
use warnings;
use utf8;
use RRDp;
use CGI::Carp qw(fatalsToBrowser);
use Env qw(QUERY_STRING);
use Date::Parse;
use POSIX qw(strftime);
use File::Temp qw/ tempfile/;
use Xorux_lib;
use XoruxEdition;
use Data::Dumper;

use utf8;

#my @worksheet = ();
my $app_lc         = "lpar2rrd";
my $app_uc         = uc($app_lc);
my $cpu_max_filter = 100;           # my $cpu_max_filter = 100;  # max 10k peak in % is allowed (in fact it cannot by higher than 1k now when 1 logical CPU == 0.1 entitlement)
if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}
my $inputdir = $ENV{INPUTDIR} ||= "";
my $bindir   = $ENV{BINDIR};
my $perl     = $ENV{PERL};
my $basedir  = $ENV{INPUTDIR};
my $wrkdir   = "$basedir/data";
my $rrdtool  = $ENV{RRDTOOL};
my $now;
my $xls_s        = ";";
my %hash_data    = ();
my %hash_data_vm = ();
my $list_of_vm   = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
my @vm_list;
my $act_unix = time();
my $max_rows = 128000;
my $step     = 60;

if ( -e $list_of_vm ) {    ####### ALL VM servers in @vm_list
  open( FC, "< $list_of_vm" ) || error( "Cannot read $list_of_vm: $!" . __FILE__ . ":" . __LINE__ ) && return 1;
  @vm_list = <FC>;
  close(FC);
}

my ( $time, $rec_bytes, $trans_bytes, $used, $fs_cache, $free, $pinned, $rec_bytes_s, $trans_bytes_s, $sys, $user, $io_wait, $idle, $page_out, $page_in, $paging_space, $percent_pag, $iops_in, $iops_out, $read_res, $write_res, $ent_core, $util_cpu, $ent_cpu, $load, $virtual, $blocked, $iops_read, $iops_write, $data_read, $data_write, $latency_read, $latency_write, $cpucount, $stog2 ) = "";    ##### values for POWER SECTION

my ( $reserved_cpu, $cpu_usage, $v_cpu, $cpu_usage_proc, $v_cpu_units, $mem_garanted, $mem_baloon, $mem_active, $disk_usage, $disk_net, $swap_in, $swap_out, $compres, $decompres ) = "";                                                                                                                                                                                                                  ### values for VM section

my ( $server, $hmc, $lpar, $item, $start, $end, $lan_en, $san_resp, $san_en );

if ( !defined $ENV{'REQUEST_METHOD'} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";
  exit;
}

my $buffer;

if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
  read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
}
else {
  $buffer = $ENV{'QUERY_STRING'};
}

my %PAR = %{ Xorux_lib::parse_url_params($buffer) };

my $xport = 1;
if ($xport) {

  # It should be here to do not influence normal report when XML is not in Perl
  require "$bindir/xml.pl";

  #use XML::Simple; --> it has to be in separete file
  #use XML::Simple; # this hat to be in separate file /HD 29.5.19
  print "Content-type: application/octet-stream\n";
}
else {
  print "Content-type: image/png\n";
  print "Cache-Control: max-age=60, public\n\n";    # workaround for caching on Chrome
}

# print STDERR Dumper \%PAR;

if ( !defined $PAR{cmd} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";
  exit;
}
if ( $PAR{cmd} eq "list" ) {
  print "Content-type: text/html\n\n";
  print "<pre>";
  print Dumper \%ENV;
  print Dumper \%PAR;

}
elsif ( $PAR{cmd} eq "test" ) {
  print "Content-type: application/json\n\n";
  my $errors  = "";
  my @reqmods = qw(OLE::Storage_Lite Spreadsheet::WriteExcel Parse::RecDescent);

  #my @reqmods = ("PDF::API2");

  for my $mod (@reqmods) {
    eval {
      ( my $file = $mod ) =~ s|::|/|g;
      require $file . '.pm';
      $mod->import();
      1;
    } or do {
      $errors .= "$@";
    }
  }

  if ($errors) {
    result( 0, "XLS export", $errors );
  }
  else {
    result( 1, "XLS export" );

    #my $err = eval "&testPDF(); 1;";
    #if (!defined $err) {
    #result(0, "PDF export", "$@");
    #} else {
    #result(1, "PDF export");
    #}
  }

}
elsif ( $PAR{cmd} eq "stop" ) {
  if ( open( STOP, ">", "/tmp/xlsgen.$PAR{id}.stop" ) ) {
    close STOP;
    print "Content-type: application/json\n\n";
    print "{ \"status\": \"terminated\", \"id\": \"$PAR{id}\"}";
  }

}
elsif ( $PAR{cmd} eq "status" ) {
  print "Content-type: application/json\n\n";

  if ( -e "/tmp/xlsgen.$PAR{id}.done" ) {
    print "{ \"status\": \"done\", \"id\": \"$PAR{id}\"}";

  }
  elsif ( -e "/tmp/xlsgen.$PAR{id}.stopped" ) {
    print "{ \"status\": \"terminated\", \"id\": \"$PAR{id}\"}";
    unlink "/tmp/xlsgen.$PAR{id}.xls";
    unlink "/tmp/xlsgen.$PAR{id}.stopped";
    unlink "/tmp/xlsgen.$PAR{id}.done";
    unlink "/tmp/xlsgen.$PAR{id}";

  }
  elsif ( open( my $sf, "<", "/tmp/xlsgen.$PAR{id}" ) ) {
    my $stat = <$sf>;
    if ($stat) {
      chomp $stat;
      my ( $c, $t ) = split ":", $stat;
      print "{ \"status\": \"pending\", \"id\": \"$PAR{id}\", \"done\": $c, \"total\": $t}";
      close $sf;
    }
  }
  else {

    # print STDERR "$inputdir/tmp/pdfgen.$PAR{id} $!\n";
    print "{ \"status\": \"unknown\", \"id\": \"$PAR{id}\"}";
  }

}
elsif ( $PAR{cmd} eq "get" ) {    ### Get generated XLS
                                  #print "Content-type: text/html\n";

  if ( open( XLS, "<", "/tmp/xlsgen.$PAR{id}.xls" ) ) {
    print "Content-Disposition:attachment;filename=$app_uc-report-" . epoch2iso() . ".xls\n\n";
    binmode XLS;
    while (<XLS>) {
      print $_;
    }
    close XLS;
  }
  else {
    print "\n";
  }
  unlink "/tmp/xlsgen.$PAR{id}.xls";
  unlink "/tmp/xlsgen.$PAR{id}.stop";
  unlink "/tmp/xlsgen.$PAR{id}.done";
  unlink "/tmp/xlsgen.$PAR{id}";

}
elsif ( $PAR{cmd} eq "gen" ) {
  print "Content-type: application/json\n\n";
  print "{ \"status\": \"pending\", \"id\": \"$PAR{id}\"}";

  require Spreadsheet::WriteExcel;

  if ( !-f "$rrdtool" ) {
    error("Set correct path to rrdtool binary, it does not exist here: $rrdtool");
    exit;
  }
  RRDp::start "$rrdtool";
  my ( $hmc_a, $server_a, $lpar_a, $item_a, $time_step, $start_a, $end_a, $start_h_unix, $start_m_unix, $start_d_unix, $start_y_unix, $end_h_unix, $end_m_unix, $end_d_unix, $end_y_unix ) = "";
  my @unsorted_value;

  if ( ref $PAR{graphs} ne "ARRAY" ) {
    my $firstVal = $PAR{graphs};
    $PAR{graphs} = [];
    push @{ $PAR{graphs} }, $firstVal;
  }
  my $urlcnt  = scalar @{ $PAR{graphs} };
  my $urlidx  = 0;
  my $stopped = 0;

  foreach my $key ( @{ $PAR{graphs} } ) {

    if ( $key =~ /lpar-list-rep\.sh/ ) { next; }
    if ( $key =~ /lpar2rrd-rep\.sh/ ) {            ###### OLD SCRIPT PARSING
      my ( undef, $key_a ) = split( /hmc=/, $key );
      ( $hmc_a, $server_a, $lpar_a, $start_h_unix, $start_m_unix, $start_d_unix, $start_y_unix, $end_h_unix, $end_m_unix, $end_d_unix, $end_y_unix, $time_step ) = split( /&/, $key_a );    ######## parsing item,server,hmc etc
                                                                                                                                                                                            #print STDERR "$start_h_unix,$start_m_unix,$start_d_unix,$start_y_unix, $end_h_unix,$end_m_unix,$end_d_unix,$end_y_unix\n";
      $server_a     =~ s/mname=//;
      $lpar_a       =~ s/lpar=//;
      $start_h_unix =~ s/shour=//;
      $start_m_unix =~ s/smon=//;
      $start_d_unix =~ s/sday=//;
      $start_y_unix =~ s/syear=//;
      $end_h_unix   =~ s/ehour=//;
      $end_m_unix   =~ s/emon=//;
      $end_d_unix   =~ s/eday=//;
      $end_y_unix   =~ s/eyear=//;
      chomp( $start_h_unix, $start_m_unix, $start_d_unix, $start_y_unix, $end_h_unix, $end_m_unix, $end_d_unix, $end_y_unix );
      $item_a  = "lpar";
      $start_a = "$start_y_unix-$start_m_unix-$start_d_unix $start_h_unix:00:00\n";
      $end_a   = "$end_y_unix-$end_m_unix-$end_d_unix $end_h_unix:00:00\n";
      chomp( $start_a, $end_a );
      $start_a = str2time($start_a);
      $end_a   = str2time($end_a);

      #print STDERR "238,,start_time:$start_a,,endtime:$end_a,,\n";
    }
    else {    ###### DETAIL_GRAPH parsing
              #print STDERR "$key\n";
      my ( undef, $key_a ) = split( /host=/, $key );
      ( $hmc_a, $server_a, $lpar_a, $item_a, $time_step, undef, undef, undef, undef, $start_a, $end_a ) = split( /&/, $key_a );    ######## parsing item,server,hmc etc
      $time_step =~ s/time=//;
      $server_a  =~ s/server=//;
      $lpar_a    =~ s/lpar=//;
      $item_a    =~ s/item=//;
      $start_a   =~ s/sunix=//;
      $end_a     =~ s/eunix=//;
    }
    chomp( $lpar_a, $item_a, $hmc_a, $server_a, $start_a, $end_a );
    my $lpar_dir_a = "$wrkdir/$server_a/$hmc_a/$lpar_a";

    # check if eunix time is not higher than actual unix time
    if ( defined $end_a && isdigit($end_a) && $end_a > $act_unix ) {
      $end_a = $act_unix;    # if eunix higher than act unix - set it up to act unix
    }

    #print STDERR"259 $server_a&$hmc_a&$lpar_a&$item_a&$start_a&$end_a\n";
    push( @unsorted_value, "$server_a&$hmc_a&$lpar_a&$item_a&$start_a&$end_a\n" );
  }

  my $lpar_v = premium();    #### version of LPAR

  my @files = sort { lc $a cmp lc $b } @unsorted_value;

  # print STDERR "267 genxls.pl,,@files,,\n";
  my ( $lpar_dir, $item, $server, $hmc, $lpar, $start, $end ) = "";
  my $last_lpar_sheet = "";

  foreach my $file (@files) {
    if ( -e "/tmp/xlsgen.$PAR{id}.stop" ) {
      rename "/tmp/xlsgen.$PAR{id}.stop", "/tmp/xlsgen.$PAR{id}.stopped";
      $stopped = 1;
      last;
    }
    $urlidx++;
    if ( open( STATFILE, ">", "/tmp/xlsgen.$PAR{id}" ) ) {
      print STATFILE "$urlidx:$urlcnt";
      close STATFILE;
    }

    ( $server, $hmc, $lpar, $item, $start, $end ) = split( /&/, $file );
    $lpar = urldecode($lpar);
    $lpar =~ s/\//&&1/g;
    $lpar = urlencode($lpar);
    chomp( $lpar_dir, $item, $start, $end );
    chomp( $server, $hmc, $lpar );
################################ VM XLS PART
    if ( $server eq "vmware_VMs" ) {

      if ( $item eq "vmw-mem" ) {    ######## MEM
        my $lpar_dec   = urldecode($lpar);
        my $server_dec = urldecode($server);
        $lpar_dec =~ s/\//&&1/g;
        my $lpar_dir_rrm = "$wrkdir/$server_dec/$lpar_dec.rrm";
        my $rrd          = $lpar_dir_rrm;
        $rrd =~ s/:/\\:/g;
        my $kbmb    = 1024;
        my $cmd_xpo = "";
        $cmd_xpo = "xport ";

        if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

          # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
          $cmd_xpo .= " --showtime";
        }
        $cmd_xpo .= " --start \"$start\"";
        $cmd_xpo .= " --end \"$end\"";
        $cmd_xpo .= " --step \"$step\"";
        $cmd_xpo .= " --maxrows \"$max_rows\"";
        $cmd_xpo .= " DEF:first=\"$rrd\":Memory_granted:AVERAGE";
        $cmd_xpo .= " DEF:second=\"$rrd\":Memory_active:AVERAGE";
        $cmd_xpo .= " DEF:third=\"$rrd\":Memory_baloon:AVERAGE";
        $cmd_xpo .= " CDEF:usage=first,$kbmb,/,$kbmb,/";
        $cmd_xpo .= " CDEF:pageout_b_nf=third,$kbmb,/,$kbmb,/";                      # baloon is MB ?
        $cmd_xpo .= " CDEF:pagein_b=second,$kbmb,/,$kbmb,/";                         # active
        $cmd_xpo .= " CDEF:pagein_b_nf=second,$kbmb,/,$kbmb,/";                      # active-
        $cmd_xpo .= " CDEF:usage_res=usage,100,*,0.5,+,FLOOR,100,/";
        $cmd_xpo .= " CDEF:pageout_b_nf_res=pageout_b_nf,100,*,0.5,+,FLOOR,100,/";
        $cmd_xpo .= " CDEF:pagein_b_nf_res=pagein_b_nf,100,*,0.5,+,FLOOR,100,/";
        $cmd_xpo .= " XPORT:usage_res:\"Usage\"";
        $cmd_xpo .= " XPORT:pageout_b_nf_res:\"Activ\"";                             ################### ZKONTROLOVAT SPRAVNOST ZITRA!!
        $cmd_xpo .= " XPORT:pagein_b_nf_res:\"Baloon\"";
        RRDp::cmd qq($cmd_xpo);
        my $answer = RRDp::read;

        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
        }
        else {
          $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

          #print STDERR"$$answer\n";
          # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
          xport_print( $answer, 0, $server, $lpar, $item );
        }
      }

      if ( $item eq "lpar" ) {    ######## CPU GHZ
        my $lpar_dec   = urldecode($lpar);
        my $server_dec = urldecode($server);
        $lpar_dec =~ s/\//&&1/g;
        my $lpar_dir_rrm = "$wrkdir/$server_dec/$lpar_dec.rrm";
        my $rrd          = $lpar_dir_rrm;
        $rrd =~ s/:/\\:/g;
        my $cmd_xpo = "";
        $cmd_xpo = "xport ";

        if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

          # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
          $cmd_xpo .= " --showtime";
        }
        $cmd_xpo .= " --start \"$start\"";
        $cmd_xpo .= " --end \"$end\"";
        $cmd_xpo .= " --step \"$step\"";
        $cmd_xpo .= " DEF:ent=\"$rrd\":CPU_Alloc:AVERAGE";
        $cmd_xpo .= " DEF:utl=\"$rrd\":CPU_usage:AVERAGE";
        $cmd_xpo .= " DEF:hz=\"$rrd\":host_hz:AVERAGE";
        $cmd_xpo .= " DEF:vcpu=\"$rrd\":vCPU:AVERAGE";
        $cmd_xpo .= " CDEF:cpu_entitl_mhz=ent";
        $cmd_xpo .= " CDEF:utiltot_mhz=utl";
        $cmd_xpo .= " CDEF:one_core_hz=hz";
        $cmd_xpo .= " CDEF:vcpu_num=vcpu";
        $cmd_xpo .= " CDEF:utiltotgp=utiltot_mhz,1000,/";
        $cmd_xpo .= " CDEF:cpu_entitlgp=cpu_entitl_mhz,1000,/";
        $cmd_xpo .= " CDEF:utiltot=utiltot_mhz,1000,*,1000,*";
        $cmd_xpo .= " CDEF:cpu_entitl=cpu_entitl_mhz,1000,*,1000,*";
        $cmd_xpo .= " CDEF:cpu_entitlgp_res=cpu_entitlgp,100,*,0.5,+,FLOOR,100,/";
        $cmd_xpo .= " CDEF:utiltotgp_res=utiltotgp,100,*,0.5,+,FLOOR,100,/";
        $cmd_xpo .= " XPORT:cpu_entitlgp_res:\"Entitled\"";
        $cmd_xpo .= " XPORT:utiltotgp_res:\"Utiltot - in GHZ\"";
        RRDp::cmd qq($cmd_xpo);
        my $answer = RRDp::read;

        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
        }
        else {
          $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

          #print STDERR"$$answer\n";
          # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
          xport_print( $answer, 0, $server, $lpar, $item );
        }

        #$cmd .= " CDEF:cpu_entitl_ghz=cpu_entitl_mhz,1000,/";
        #$cmd .= " GPRINT:cpu_entitl_ghz:AVERAGE:\" %5.2lf\"";
      }

      if ( $item eq "vmw-proc" ) {    ######## CPU
        my $lpar_dec   = urldecode($lpar);
        my $server_dec = urldecode($server);
        $lpar_dec =~ s/\//&&1/g;
        my $lpar_dir_rrm = "$wrkdir/$server_dec/$lpar_dec.rrm";
        my $rrd          = $lpar_dir_rrm;
        $rrd =~ s/:/\\:/g;
        if ( -f $lpar_dir_rrm ) {
          my $cmd_xpo = "";
          $cmd_xpo = "xport ";
          if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

            # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
            $cmd_xpo .= " --showtime";
          }
          $cmd_xpo .= " --start \"$start\"";
          $cmd_xpo .= " --end \"$end\"";
          $cmd_xpo .= " --step \"$step\"";
          $cmd_xpo .= " --maxrows \"$max_rows\"";
          my $kbmb = 100;
          $cmd_xpo .= " DEF:first=\"$rrd\":CPU_usage_Proc:AVERAGE";
          $cmd_xpo .= " DEF:second=\"$rrd\":vCPU:AVERAGE";
          $cmd_xpo .= " DEF:third=\"$rrd\":host_hz:AVERAGE";
          $cmd_xpo .= " DEF:fourth=\"$rrd\":CPU_usage:AVERAGE";
          $cmd_xpo .= " CDEF:CPU_usage_Proc=first,$kbmb,/";                                                # orig-
          $cmd_xpo .= " CDEF:pageout_b_nf=second,$kbmb,/";
          $cmd_xpo .= " CDEF:vCPU=second,1,/";                                                             # number-
          $cmd_xpo .= " CDEF:host_MHz=third,1000,/,1000,/";                                                # to be in MHz
          $cmd_xpo .= " CDEF:CPU_usage=fourth,1,/";                                                        # MHz
          $cmd_xpo .= " CDEF:CPU_usage_res=CPU_usage,host_MHz,/,vCPU,/,100,*";                             # usage proc counted
          $cmd_xpo .= " CDEF:pagein_b_raw=CPU_usage_Proc,UN,CPU_usage_res,CPU_usage_Proc,IF";
          $cmd_xpo .= " CDEF:pagein_b=pagein_b_raw,UN,UNKN,pagein_b_raw,100,GT,100,pagein_b_raw,IF,IF";    # cut more than 100%, VMware does the same
          $cmd_xpo .= " CDEF:vcpu=pageout_b_nf,$kbmb,*";
          $cmd_xpo .= " CDEF:pagein_b_res=pagein_b,100,*,0.5,+,FLOOR,100,/";
          $cmd_xpo .= " XPORT:pagein_b_res:\"CPU usage\"";
          $cmd_xpo .= " XPORT:vcpu:\"CPU usage\"";

          #$cmd_xpo .= " XPORT:vcpu:MAX:\"%6.0lf\"";
          RRDp::cmd qq($cmd_xpo);
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

            #print STDERR"$$answer\n";
            # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
            xport_print( $answer, 0, $server, $lpar, $item );
          }
        }
      }

      if ( $item eq "vmw-disk" ) {    ########## DISK
        my $lpar_dec   = urldecode($lpar);
        my $server_dec = urldecode($server);
        $lpar_dec =~ s/\//&&1/g;
        my $lpar_dir_rrm = "$wrkdir/$server_dec/$lpar_dec.rrm";
        my $rrd          = $lpar_dir_rrm;
        $rrd =~ s/:/\\:/g;
        if ( -f $lpar_dir_rrm ) {
          my $cmd_xpo = "";
          $cmd_xpo = "xport ";
          my $kbmb = 1024;
          if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

            # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
            $cmd_xpo .= " --showtime";
          }
          $cmd_xpo .= " --start \"$start\"";
          $cmd_xpo .= " --end \"$end\"";
          $cmd_xpo .= " --step \"$step\"";
          $cmd_xpo .= " --maxrows \"$max_rows\"";
          $cmd_xpo .= " DEF:first=\"$rrd\":Disk_usage:AVERAGE";
          $cmd_xpo .= " DEF:second=\"$rrd\":Disk_usage:AVERAGE";
          $cmd_xpo .= " CDEF:pagein_b=first,$kbmb,/";
          $cmd_xpo .= " CDEF:pageout_b_nf=second,$kbmb,/";
          $cmd_xpo .= " CDEF:pagein_b_nf=first,-$kbmb,/";
          $cmd_xpo .= " CDEF:pagein_b_res=pagein_b,100,*,0.5,+,FLOOR,100,/";
          $cmd_xpo .= " XPORT:pagein_b_res:\"disk usage\"";
          RRDp::cmd qq($cmd_xpo);
          my $answer = RRDp::read;

          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

            #print STDERR"$$answer\n";
            # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
            xport_print( $answer, 0, $server, $lpar, $item );
          }
        }
      }

      if ( $item eq "vmw-net" ) {    ######## NET
        my $lpar_dec   = urldecode($lpar);
        my $server_dec = urldecode($server);
        $lpar_dec =~ s/\//&&1/g;
        my $lpar_dir_rrm = "$wrkdir/$server_dec/$lpar_dec.rrm";
        my $rrd          = $lpar_dir_rrm;
        $rrd =~ s/:/\\:/g;
        if ( -f $lpar_dir_rrm ) {
          my $cmd_xpo = "";
          $cmd_xpo = "xport ";
          my $kbmb = 1024;
          if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

            # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
            $cmd_xpo .= " --showtime";
          }
          $cmd_xpo .= " --start \"$start\"";
          $cmd_xpo .= " --end \"$end\"";
          $cmd_xpo .= " --step \"$step\"";
          $cmd_xpo .= " --maxrows \"$max_rows\"";
          $cmd_xpo .= " DEF:first=\"$rrd\":Network_usage:AVERAGE";
          $cmd_xpo .= " DEF:second=\"$rrd\":Network_usage:AVERAGE";
          $cmd_xpo .= " CDEF:pagein_b=first,$kbmb,/";
          $cmd_xpo .= " CDEF:pageout_b_nf=second,$kbmb,/";
          $cmd_xpo .= " CDEF:pagein_b_nf=first,-$kbmb,/";
          $cmd_xpo .= " CDEF:pagein_b_res=pagein_b,100,*,0.5,+,FLOOR,100,/";
          $cmd_xpo .= " XPORT:pagein_b_res:\"Network Usage\"";
          RRDp::cmd qq($cmd_xpo);
          my $answer = RRDp::read;

          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

            #print STDERR"$$answer\n";
            # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
            xport_print( $answer, 0, $server, $lpar, $item );
          }
        }
      }

      if ( $item eq "vmw-swap" ) {    ######## SWAP
        my $lpar_dec   = urldecode($lpar);
        my $server_dec = urldecode($server);
        $lpar_dec =~ s/\//&&1/g;
        my $lpar_dir_rrm = "$wrkdir/$server_dec/$lpar_dec.rrm";
        my $rrd          = $lpar_dir_rrm;
        $rrd =~ s/:/\\:/g;
        if ( -f $lpar_dir_rrm ) {
          my $cmd_xpo = "";
          $cmd_xpo = "xport ";
          my $kbmb = 1000;
          if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

            # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
            $cmd_xpo .= " --showtime";
          }
          $cmd_xpo .= " --start \"$start\"";
          $cmd_xpo .= " --end \"$end\"";
          $cmd_xpo .= " --step \"$step\"";
          $cmd_xpo .= " --maxrows \"$max_rows\"";
          $cmd_xpo .= " DEF:first=\"$rrd\":Memory_swapin:AVERAGE";
          $cmd_xpo .= " DEF:second=\"$rrd\":Memory_swapout:AVERAGE";
          $cmd_xpo .= " CDEF:pagein_b=first,$kbmb,/";
          $cmd_xpo .= " CDEF:pageout_b_nf=second,$kbmb,/";
          $cmd_xpo .= " CDEF:pagein_b_nf=first,-$kbmb,/";
          $cmd_xpo .= " CDEF:pagein_b_res=pagein_b,100,*,0.5,+,FLOOR,100,/";
          $cmd_xpo .= " CDEF:pageout_b_nf_res=pageout_b_nf,100,*,0.5,+,FLOOR,100,/";
          $cmd_xpo .= " XPORT:pagein_b_res:\"Swap in\"";
          $cmd_xpo .= " XPORT:pageout_b_nf_res:\"Swap out\"";
          RRDp::cmd qq($cmd_xpo);
          my $answer = RRDp::read;

          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

            #print STDERR"$$answer\n";
            # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
            xport_print( $answer, 0, $server, $lpar, $item );
          }
        }
      }

      if ( $item eq "vmw-comp" ) {    ######### COMP
        my $lpar_dec   = urldecode($lpar);
        my $server_dec = urldecode($server);
        $lpar_dec =~ s/\//&&1/g;
        my $lpar_dir_rrm = "$wrkdir/$server_dec/$lpar_dec.rrm";
        my $rrd          = $lpar_dir_rrm;
        $rrd =~ s/:/\\:/g;
        if ( -f $lpar_dir_rrm ) {
          my $cmd_xpo = "";
          $cmd_xpo = "xport ";
          my $kbmb = 1024;
          if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

            # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
            $cmd_xpo .= " --showtime";
          }
          $cmd_xpo .= " --start \"$start\"";
          $cmd_xpo .= " --end \"$end\"";
          $cmd_xpo .= " --step \"$step\"";
          $cmd_xpo .= " --maxrows \"$max_rows\"";
          $cmd_xpo .= " DEF:first=\"$rrd\":Memory_compres:AVERAGE";
          $cmd_xpo .= " DEF:second=\"$rrd\":Memory_decompres:AVERAGE";
          $cmd_xpo .= " CDEF:pagein_b=first,$kbmb,/";
          $cmd_xpo .= " CDEF:pageout_b_nf=second,$kbmb,/";
          $cmd_xpo .= " CDEF:pagein_b_nf=first,-$kbmb,/";
          $cmd_xpo .= " CDEF:pagein_b_res=pagein_b,100,*,0.5,+,FLOOR,100,/";
          $cmd_xpo .= " CDEF:pageout_b_nf_res=pageout_b_nf,100,*,0.5,+,FLOOR,100,/";
          $cmd_xpo .= " XPORT:pageout_b_nf_res:\"Swap in\"";
          $cmd_xpo .= " XPORT:pagein_b_res:\"Swap out\"";
          RRDp::cmd qq($cmd_xpo);
          my $answer = RRDp::read;

          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

            #print STDERR"$$answer\n";
            # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
            xport_print( $answer, 0, $server, $lpar, $item );
          }
        }
      }

    }

    #print STDERR ",,$server,,$hmc,,$lpar,,---$item\n";

####################### END VM
####################### POWER PART
    if ( $item eq "lpar" ) {    ######### LPAR
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec.rrm";
      if ( -f $lpar_dir_rrm ) {
        my $rrd = $lpar_dir_rrm;
        $rrd =~ s/:/\\:/g;
        my $cmd_xpo = "";
        $cmd_xpo = "xport ";
        if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

          # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
          $cmd_xpo .= " --showtime";
        }
        $cmd_xpo .= " --start \"$start\"";
        $cmd_xpo .= " --end \"$end\"";
        $cmd_xpo .= " --step \"$step\"";
        $cmd_xpo .= " --maxrows \"$max_rows\"";
        $cmd_xpo .= " DEF:cur=\"$rrd\":curr_proc_units:AVERAGE";
        $cmd_xpo .= " DEF:ent=\"$rrd\":entitled_cycles:AVERAGE";
        $cmd_xpo .= " DEF:cap=\"$rrd\":capped_cycles:AVERAGE";
        $cmd_xpo .= " DEF:uncap=\"$rrd\":uncapped_cycles:AVERAGE";
        $cmd_xpo .= " CDEF:tot=cap,uncap,+";
        $cmd_xpo .= " CDEF:util=tot,ent,/,\"$cpu_max_filter\",GT,UNKN,tot,ent,/,IF";
        $cmd_xpo .= " CDEF:utilperct=util,100,*";
        $cmd_xpo .= " CDEF:utiltot=util,cur,*";
        $cmd_xpo .= " CDEF:cur_res=cur,100,*,0.5,+,FLOOR,100,/";
        $cmd_xpo .= " CDEF:utiltot_res=utiltot,100,*,0.5,+,CEIL,100,/";
        $cmd_xpo .= " CDEF:utilperct_res=utilperct,100,*,0.5,+,FLOOR,100,/";
        $cmd_xpo .= " XPORT:cur_res:\"Entitled processor cores\"";
        $cmd_xpo .= " XPORT:utiltot_res:\"Utilization in CPU cores\"";
        $cmd_xpo .= " XPORT:utilperct_res:\"Entitled CPU utilization\"";
        RRDp::cmd qq($cmd_xpo);
        my $answer = RRDp::read;

        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
        }
        else {
          $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

          print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
          xport_print( $answer, 0, $server, $lpar, $item );
        }
      }
    }

####################### LAN
    if ( $item eq "lan" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /lan-en/ ) {
            if ( $lpar_dir_rrm =~ /\.cfg$/ ) { next; }
            my $rrd = $lpar_dir_rrm;
            $lan_en = $lpar_dir;
            my $divider       = 1073741824;
            my $count_avg_day = 1;
            my $minus_one     = -1;
            $lan_en =~ s/lan-//g;
            $lan_en =~ s/\.mmm//g;
            $rrd    =~ s/:/\\:/g;
            my $i = "";

            #print STDERR"?!!?$rrd?!--$lan_en!?\n";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:received_bytes${i}=\"$rrd\":recv_bytes:AVERAGE";
            $cmd_xpo .= " DEF:transfers_bytes${i}=\"$rrd\":trans_bytes:AVERAGE";
            $cmd_xpo .= " CDEF:recv${i}=received_bytes${i}";
            $cmd_xpo .= " CDEF:trans${i}=transfers_bytes${i}";
            $cmd_xpo .= " CDEF:recv_s${i}=recv${i},86400,*";
            $cmd_xpo .= " CDEF:recv_smb${i}=recv_s${i},$divider,/";
            $cmd_xpo .= " CDEF:recv_smb_n${i}=recv_smb${i},$count_avg_day,*";
            $cmd_xpo .= " CDEF:trans_s${i}=trans${i},86400,*";
            $cmd_xpo .= " CDEF:trans_smb${i}=trans_s${i},$divider,/";
            $cmd_xpo .= " CDEF:trans_smb_n${i}=trans_smb${i},$count_avg_day,*";
            $cmd_xpo .= " CDEF:recv_neg${i}=recv_s${i},$minus_one,*";
            $cmd_xpo .= " CDEF:received_bytes_res${i}=received_bytes${i},1,*,0.5,+,FLOOR,1,/";
            $cmd_xpo .= " CDEF:transfers_bytes_res${i}=transfers_bytes${i},1,*,0.5,+,FLOOR,1,/";
            $cmd_xpo .= " XPORT:transfers_bytes_res${i}:\"TRANS bytes - $lan_en - in Bytes\"";
            $cmd_xpo .= " XPORT:received_bytes_res${i}:\"REC bytes - $lan_en - in Bytes\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

####################### MEM
    if ( $item eq "mem" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /mem/ ) {
            my $rrd = $lpar_dir_rrm;
            $rrd =~ s/:/\\:/g;
            my $i = "";

            #print STDERR"??$rrd??\n";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:size=\"$rrd\":size:AVERAGE";
            $cmd_xpo .= " DEF:used=\"$rrd\":nuse:AVERAGE";
            $cmd_xpo .= " DEF:free=\"$rrd\":free:AVERAGE";
            $cmd_xpo .= " DEF:pin=\"$rrd\":pin:AVERAGE";
            $cmd_xpo .= " DEF:in_use_work=\"$rrd\":in_use_work:AVERAGE";
            $cmd_xpo .= " DEF:in_use_clnt=\"$rrd\":in_use_clnt:AVERAGE";
            $cmd_xpo .= " CDEF:free_g=free,1048576,/";
            $cmd_xpo .= " CDEF:usedg=used,1048576,/";
            $cmd_xpo .= " CDEF:in_use_clnt_g=in_use_clnt,1048576,/";
            $cmd_xpo .= " CDEF:used_realg=usedg,in_use_clnt_g,-";
            $cmd_xpo .= " CDEF:pin_g=pin,1048576,/";
            $cmd_xpo .= " CDEF:used_realg_res=used_realg,1000,*,0.5,+,FLOOR,1000,/";
            $cmd_xpo .= " CDEF:in_use_clnt_res=in_use_clnt_g,1000,*,0.5,+,FLOOR,1000,/";
            $cmd_xpo .= " CDEF:free_g_res=free_g,1000,*,0.5,+,FLOOR,1000,/";
            $cmd_xpo .= " CDEF:pin_res=pin_g,1000,*,0.5,+,FLOOR,1000,/";
            $cmd_xpo .= " CDEF:used_realg_res_a=used_realg_res,1000,*";
            $cmd_xpo .= " CDEF:in_use_clnt_res_a=in_use_clnt_res,1000,*";
            $cmd_xpo .= " CDEF:free_g_res_a=free_g_res,1000,*";
            $cmd_xpo .= " CDEF:pin_res_a=pin_res,1000,*";
            $cmd_xpo .= " XPORT:used_realg_res_a:\"Used memory in MB\"";
            $cmd_xpo .= " XPORT:in_use_clnt_res_a:\"FS Cache in MB\"";
            $cmd_xpo .= " XPORT:free_g_res_a:\"Free in MB\"";
            $cmd_xpo .= " XPORT:pin_res_a:\"Pinned in MB\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

######################### CPU
    if ( $item eq "oscpu" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /cpu\.mmm$/ ) {
            if ( $lpar_dir_rrm =~ /\.txt/ ) { next; }
            if ( $lpar_dir_rrm =~ /queue/ ) { next; }
            my $rrd = $lpar_dir_rrm;
            $rrd =~ s/:/\\:/g;

            #print STDERR "??$rrd??\n";
            my $i       = "";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:entitled=\"$rrd\":entitled:AVERAGE";
            $cmd_xpo .= " DEF:cpusy=\"$rrd\":cpu_sy:AVERAGE";
            $cmd_xpo .= " DEF:cpuus=\"$rrd\":cpu_us:AVERAGE";
            $cmd_xpo .= " DEF:cpuwa=\"$rrd\":cpu_wa:AVERAGE";
            $cmd_xpo .= " CDEF:stog=100,cpusy,-,cpuus,-,cpuwa,-";
            $cmd_xpo .= " CDEF:cpusy_res=cpusy,100,*,0.5,+,FLOOR,100,/";
            $cmd_xpo .= " CDEF:cpuus_res=cpuus,100,*,0.5,+,FLOOR,100,/";
            $cmd_xpo .= " CDEF:cpuwa_res=cpuwa,100,*,0.5,+,FLOOR,100,/";
            $cmd_xpo .= " CDEF:stog_res=stog,100,*,0.5,+,FLOOR,100,/";
            $cmd_xpo .= " XPORT:cpusy_res:\"Sys\"";
            $cmd_xpo .= " XPORT:cpuus_res:\"User\"";
            $cmd_xpo .= " XPORT:cpuwa_res:\"IO wait\"";
            $cmd_xpo .= " XPORT:stog_res:\"Idle\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

######################### PAGING 1
    if ( $item eq "pg1" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /pgs\.mmm/ ) {
            if ( $lpar_dir_rrm =~ /\.txt/ ) { next; }
            my $filter = 100000000;
            my $rrd    = $lpar_dir_rrm;
            $rrd =~ s/:/\\:/g;
            my $i       = "";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:pagein=\"$rrd\":page_in:AVERAGE";
            $cmd_xpo .= " DEF:pageout=\"$rrd\":page_out:AVERAGE";
            $cmd_xpo .= " CDEF:pagein_b_nf=pagein,4096,*";
            $cmd_xpo .= " CDEF:pageout_b_nf=pageout,4096,*";
            $cmd_xpo .= " CDEF:pagein_b=pagein_b_nf,\"$filter\",GT,UNKN,pagein_b_nf,IF";
            $cmd_xpo .= " CDEF:pageout_b=pageout_b_nf,\"$filter\",GT,UNKN,pageout_b_nf,IF";
            $cmd_xpo .= " CDEF:pagein_mb=pagein_b,1048576,/";
            $cmd_xpo .= " CDEF:pagein_mb_neg=pagein_mb,-1,*";
            $cmd_xpo .= " CDEF:pageout_mb=pageout_b,1048576,/";
            $cmd_xpo .= " CDEF:pageout_mb_res=pageout_mb,1000,*,0.5,+,FLOOR,1000,/";
            $cmd_xpo .= " CDEF:pagein_mb_res=pagein_mb,1000,*,0.5,+,FLOOR,1000,/";
            $cmd_xpo .= " XPORT:pageout_mb_res:\"Page out\"";
            $cmd_xpo .= " XPORT:pagein_mb_res:\"Page in\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

######################## PAGING 2
    if ( $item eq "pg2" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /pgs\.mmm/ ) {
            if ( $lpar_dir_rrm =~ /\.txt/ ) { next; }
            my $rrd = $lpar_dir_rrm;
            $rrd =~ s/:/\\:/g;
            my $i       = "";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:paging=\"$rrd\":paging_space:AVERAGE";
            $cmd_xpo .= " DEF:percent_a=\"$rrd\":percent:AVERAGE";
            $cmd_xpo .= " XPORT:paging:\"Paging space in MB\"";
            $cmd_xpo .= " XPORT:percent_a:\"percent %\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

############################# SAN_RESP
    if ( $item eq "san_resp" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";

          #print STDERR "!!!$lpar_dir_rrm!!!\n";
          if ( $lpar_dir_rrm =~ /san_resp-/ ) {

            #print STDERR "!!!$lpar_dir_rrm??\n";
            if ( $lpar_dir_rrm =~ /\.txt/ ) { next; }
            my $rrd = $lpar_dir_rrm;
            $san_resp = $lpar_dir;
            $san_resp =~ s/san_resp-//g;
            $san_resp =~ s/\.mmm//g;

            #print STDERR "???$rrd??$san_resp???\n";
            $rrd =~ s/:/\\:/g;
            my $i       = "";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:read${i}=\"$rrd\":resp_t_r:AVERAGE";
            $cmd_xpo .= " DEF:write${i}=\"$rrd\":resp_t_w:AVERAGE";
            $cmd_xpo .= " CDEF:read_res${i}=read${i},100,*,0.5,+,FLOOR,100,/";
            $cmd_xpo .= " CDEF:write_res${i}=write${i},100,*,0.5,+,FLOOR,100,/";
            $cmd_xpo .= " XPORT:read_res${i}:\"READ\"";
            $cmd_xpo .= " XPORT:write_res${i}:\"WRITE\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

############################# SAN1 and SAN2
    if ( $item =~ /san1|san2/ ) {
      my $ds_name_os1 = "";
      my $ds_name_os2 = "";
      my $name_os1    = "";
      my $name_os2    = "";
      if ( $item =~ /san1|nmon_san1/ ) {
        $ds_name_os1 = "recv_bytes";
        $ds_name_os2 = "trans_bytes";
        $name_os1    = "Recv bytes";
        $name_os2    = "Trans bytes";
      }
      if ( $item =~ /san2|nmon_san2/ ) {
        $ds_name_os1 = "iops_in";
        $ds_name_os2 = "iops_out";
        $name_os1    = "IOPS in";
        $name_os2    = "IOPS out";
      }
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /san-/ ) {
            if ( $lpar_dir_rrm =~ /\.cfg/ ) { next; }
            $san_en = $lpar_dir;
            $san_en =~ s/san-//g;
            $san_en =~ s/\.mmm//g;

            #print STDERR "$san_en\n";
            my $rrd = $lpar_dir_rrm;
            $rrd =~ s/:/\\:/g;
            my $i       = "";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:value_os1${i}=\"$rrd\":$ds_name_os1:AVERAGE";
            $cmd_xpo .= " DEF:value_os2${i}=\"$rrd\":$ds_name_os2:AVERAGE";
            $cmd_xpo .= " CDEF:value_os1_res${i}=value_os1${i},1,*,0.5,+,FLOOR,1,/";
            $cmd_xpo .= " CDEF:value_os2_res${i}=value_os2${i},1,*,0.5,+,FLOOR,1,/";
            $cmd_xpo .= " XPORT:value_os1_res${i}:\"$name_os1 - in Bytes\"";
            $cmd_xpo .= " XPORT:value_os2_res${i}:\"$name_os2 - in Bytes\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

######################## CPU CORE
    if ( $item eq "cpu-linux" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {

        #opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        #my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        #closedir(DIR);
        #foreach my $lpar_dir (@lpars_dir_os_all) {
        # $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
        #if ( $lpar_dir_rrm =~ /queue_cpu\.mmm/ ) {
        #if ( $lpar_dir_rrm =~ /\.txt/ ) { next; }
        my $rrd           = "$lpar_dir_rrm/cpu.mmm";
        my $rrd_cpu_linux = "$lpar_dir_rrm/linux_cpu.mmm";
        $rrd           =~ s/:/\\:/g;
        $rrd_cpu_linux =~ s/:/\\:/g;
        my $i       = "";
        my $cmd_xpo = "";
        $cmd_xpo = "xport ";

        if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

          # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
          $cmd_xpo .= " --showtime";
        }
        $cmd_xpo .= " --start \"$start\"";
        $cmd_xpo .= " --end \"$end\"";
        $cmd_xpo .= " --step \"$step\"";
        $cmd_xpo .= " --maxrows \"$max_rows\"";

        # CPU OS % rrd
        $cmd_xpo .= " DEF:entitled=\"$rrd\":entitled:AVERAGE";
        $cmd_xpo .= " DEF:cpusy=\"$rrd\":cpu_sy:AVERAGE";
        $cmd_xpo .= " DEF:cpuus=\"$rrd\":cpu_us:AVERAGE";
        $cmd_xpo .= " DEF:cpuwa=\"$rrd\":cpu_wa:AVERAGE";

        # CPU linux new rrd
        $cmd_xpo .= " DEF:cpucount=\"$rrd_cpu_linux\":cpu_count:AVERAGE";
        $cmd_xpo .= " DEF:cpuinmhz=\"$rrd_cpu_linux\":cpu_in_mhz:AVERAGE";
        $cmd_xpo .= " DEF:threadscore=\"$rrd_cpu_linux\":threads_core:AVERAGE";
        $cmd_xpo .= " DEF:corespersocket=\"$rrd_cpu_linux\":cores_per_socket:AVERAGE";

        # cpu cores counting
        #$cmd .= " CDEF:cpu_cores=cpucount,threadscore,corespersocket,*,*";
        $cmd_xpo .= " CDEF:cpu_cores=cpucount,100,/";
        $cmd_xpo .= " CDEF:stog1=cpusy,cpuus,cpuwa,+,+";
        $cmd_xpo .= " CDEF:stog2=cpu_cores,stog1,*";

        # cpu Ghz counting
        $cmd_xpo .= " CDEF:cpughz=cpuinmhz,1000,/";
        $cmd_xpo .= " CDEF:cpughz1=cpughz,cpucount,*";
        $cmd_xpo .= " CDEF:cpu_ghz_one_perc=cpughz1,100,/";
        $cmd_xpo .= " CDEF:cpu_ghz_util=cpu_ghz_one_perc,stog1,*";

        $cmd_xpo .= " XPORT:cpucount:\"Load Avrg\"";
        $cmd_xpo .= " XPORT:stog2:\"Logical processors\"";
        $i++;
        RRDp::cmd qq($cmd_xpo);
        my $answer = RRDp::read;

        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
        }
        else {
          $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

          #print STDERR"$$answer\n";
          # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
          xport_print( $answer, 0, $server, $lpar, $item );

          #print STDERR "after xport print\n";
        }

        #}
        #}
      }
    }

######################## CPU Queue
    if ( $item eq "queue_cpu" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /queue_cpu\.mmm/ ) {
            if ( $lpar_dir_rrm =~ /\.txt/ ) { next; }
            my $rrd = $lpar_dir_rrm;
            $rrd =~ s/:/\\:/g;
            my $i       = "";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:load=\"$rrd\":load:AVERAGE";
            $cmd_xpo .= " DEF:virtual=\"$rrd\":virtual_p:AVERAGE";
            $cmd_xpo .= " DEF:blocked=\"$rrd\":blocked_p:AVERAGE";
            $cmd_xpo .= " XPORT:load:\"Load Avrg\"";
            $cmd_xpo .= " XPORT:virtual:\"Logical processors\"";
            $cmd_xpo .= " XPORT:blocked:\"Blocked processes\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

######################## Total IOPS
    if ( $item eq "total_iops" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /disk-total\.mmm/ ) {
            if ( $lpar_dir_rrm =~ /\.txt/ ) { next; }
            my $rrd = $lpar_dir_rrm;
            $rrd =~ s/:/\\:/g;
            my $i       = "";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:read_iops=\"$rrd\":read_iops:AVERAGE";
            $cmd_xpo .= " DEF:write_iops=\"$rrd\":write_iops:AVERAGE";
            $cmd_xpo .= " XPORT:read_iops:\"IOPS read\"";
            $cmd_xpo .= " XPORT:write_iops:\"IOPS write\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

######################## Total data
    if ( $item eq "total_data" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /disk-total\.mmm/ ) {
            if ( $lpar_dir_rrm =~ /\.txt/ ) { next; }
            my $rrd = $lpar_dir_rrm;
            $rrd =~ s/:/\\:/g;
            my $i       = "";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:read_data=\"$rrd\":read_data:AVERAGE";
            $cmd_xpo .= " DEF:write_data=\"$rrd\":write_data:AVERAGE";
            $cmd_xpo .= " XPORT:read_data:\"Read Data Bytes/sec\"";
            $cmd_xpo .= " XPORT:write_data:\"Write Data Bytes/sec\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }

######################## total latency
    if ( $item eq "total_latency" ) {
      my $lpar_dec   = urldecode($lpar);
      my $server_dec = urldecode($server);
      $lpar_dec =~ s/\//&&1/g;
      my $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec";
      if ( -d $lpar_dir_rrm ) {
        opendir( DIR, "$wrkdir/$server_dec/$hmc/$lpar_dec" ) || error( "can't opendir $wrkdir/$server_dec/$hmc/$lpar_dec: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_dir (@lpars_dir_os_all) {
          $lpar_dir_rrm = "$wrkdir/$server_dec/$hmc/$lpar_dec/$lpar_dir";
          if ( $lpar_dir_rrm =~ /disk-total\.mmm/ ) {
            if ( $lpar_dir_rrm =~ /\.txt/ ) { next; }
            my $rrd = $lpar_dir_rrm;
            $rrd =~ s/:/\\:/g;
            my $i       = "";
            my $cmd_xpo = "";
            $cmd_xpo = "xport ";
            if ( -f "$basedir/tmp/rrdtool-xport-showtime" ) {

              # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
              $cmd_xpo .= " --showtime";
            }
            $cmd_xpo .= " --start \"$start\"";
            $cmd_xpo .= " --end \"$end\"";
            $cmd_xpo .= " --step \"$step\"";
            $cmd_xpo .= " --maxrows \"$max_rows\"";
            $cmd_xpo .= " DEF:read_latency=\"$rrd\":read_latency:AVERAGE";
            $cmd_xpo .= " DEF:write_latency=\"$rrd\":write_latency:AVERAGE";
            $cmd_xpo .= " XPORT:read_latency:\"Latency read ms\"";
            $cmd_xpo .= " XPORT:write_latency:\"Latency write ms\"";
            $i++;
            RRDp::cmd qq($cmd_xpo);
            my $answer = RRDp::read;

            if ( $$answer =~ "ERROR" ) {
              error("Rrdtool error : $$answer");
            }
            else {
              $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

              #print STDERR"$$answer\n";
              # print "Content-Disposition: attachment;filename=\"$hmc\_$server\_$lpar.xls\"\n\n";
              xport_print( $answer, 0, $server, $lpar, $item );
            }
          }
        }
      }
    }
  }

  my $j = 0;

  open my $fh, '>', \my $str or die "Failed to open filehandle: $!";
  print "Content-type: application/vnd.ms-excel\n";
  print "Content-Disposition:attachment;filename=LPAR2RRD-report-" . epoch2iso('') . ".xls\n\n";
  my $workbook = Spreadsheet::WriteExcel->new($fh);
  $workbook->compatibility_mode();

  if ( $server eq "vmware_VMs" ) {
    foreach my $lpar ( keys %hash_data_vm ) {

      my $lpar_sheet = "";
      $lpar_sheet = substr $lpar, 0, 30;

      #$lpar_sheet = urlencode($lpar_sheet);
      $lpar_sheet =~ s/\///g;

      #print STDERR "$lpar_sheet\n";
      my $worksheet = $workbook->add_worksheet($lpar_sheet);
      $worksheet->freeze_panes( 1, 0 );    # Freeze the first row
      my $num2dp = $workbook->add_format();
      $num2dp->set_num_format('0.00');
      $num2dp->set_align('center');
      ### Set the column width for columns
      $worksheet->set_column( 0, 10, 16 );

      #$worksheet->set_column('C:E', 15, $num2dp); ### center align
      $worksheet->set_column( 'B:B', 15 );
      $worksheet->set_column( 'C:C', 13 );
      $worksheet->set_column( 'D:I', 20 );
      $worksheet->set_column( 'J:K', 19 );
      $worksheet->set_column( 'L:O', 13 );
      my $format = $workbook->add_format();
      $format->set_bold();
      my $fdatetime = $workbook->add_format( num_format => "yyyy-mm-dd hh:mm", align => "left" );
      my @xlheader  = ( "Time", "Cpu-usage in %", "vCPU/units", "Reserved CPU", "Cpu usage in Ghz", "Mem granted in GB", "Mem baloon in GB", "Mem active in GB", "Disk usage in MB/sec", "Net usage in MB/sec", "Swap - IN", "SWAP - OUT", "Compres", "Decompres" );

      $worksheet->write_row( 0, 0, \@xlheader, $format );

      my $i = 1;
      foreach my $time ( sort keys %{ $hash_data_vm{$lpar} } ) {
        my ( $cpu_usage_proc1, $v_cpu1, $reserved_cpu1, $cpu_usage1, $v_cpu_units1, $mem1_garanted, $mem1_baloon, $mem1_active, $disk_usage1, $disk_net1, $swap_in1, $swap_out1, $compres1, $decompres1 ) = "";
        foreach my $item ( sort keys %{ $hash_data_vm{$lpar}{$time} } ) {
          if ( $item eq "vmw-proc" ) {
            ( $cpu_usage_proc1, $v_cpu1 ) = split( /;/, $hash_data_vm{$lpar}{$time}{$item} );
          }
          if ( $item eq "lpar" ) {
            ( $reserved_cpu1, $cpu_usage1 ) = split( /;/, $hash_data_vm{$lpar}{$time}{$item} );
          }
          if ( $item eq "vmw-mem" ) {
            ( $mem1_garanted, $mem1_baloon, $mem1_active ) = split( /;/, $hash_data_vm{$lpar}{$time}{$item} );
          }
          if ( $item eq "vmw-disk" ) {
            ($disk_usage1) = split( /;/, $hash_data_vm{$lpar}{$time}{$item} );
          }
          if ( $item eq "vmw-net" ) {
            ($disk_net1) = split( /;/, $hash_data_vm{$lpar}{$time}{$item} );
          }
          if ( $item eq "vmw-swap" ) {
            ( $swap_in1, $swap_out1 ) = split( /;/, $hash_data_vm{$lpar}{$time}{$item} );
          }
          if ( $item eq "vmw-comp" ) {
            ( $compres1, $decompres1 ) = split( /;/, $hash_data_vm{$lpar}{$time}{$item} );
          }
        }

        my @xlrow = ( $cpu_usage_proc1, $v_cpu1, $reserved_cpu1, $cpu_usage1, $mem1_garanted, $mem1_baloon, $mem1_active, $disk_usage1, $disk_net1, $swap_in1, $swap_out1, $compres1, $decompres1 );
        $worksheet->write_row( $i, 1, \@xlrow );
        $worksheet->write_date_time( $i, 0, $time, $fdatetime );
        $i++;
      }
    }
  }
  else {
    foreach my $lpar ( keys %hash_data ) {
      my $lpar_sheet = "";
      my $lpar_subs  = $lpar;
      $lpar_subs = urldecode($lpar_subs);

      #print STDERR "1489 $lpar_subs\n";
      if ( $lpar_subs =~ /[\[\]\*\?\:\/]/ ) {    #### exceptions for sheet []*?:/\
        $lpar_subs = urlencode($lpar_subs);
      }
      $lpar_sheet = substr $lpar_subs, 0, 30;
      $lpar_sheet =~ s/\///g;

      #$lpar_sheet =~ s/%20/ /g;
      my $fdatetime = $workbook->add_format( num_format => "yyyy-mm-dd hh:mm", align => "left" );
      my $worksheet = $workbook->add_worksheet($lpar_sheet);
      $worksheet->freeze_panes( 1, 0 );          # Freeze the first row
      my $num2dp = $workbook->add_format();
      $num2dp->set_num_format('0.00');
      $num2dp->set_align('center');
      ### Set the column width for columns
      $worksheet->set_column( 0, 10, 16 );

      #$worksheet->set_column('C:E', 15, $num2dp); ### center align
      $worksheet->set_column( 'B:D', 24 );
      $worksheet->set_column( 'E:N', 20 );
      $worksheet->set_column( 'O:P', 20 );
      $worksheet->set_column( 'Q:X', 23 );
      my $format = $workbook->add_format();
      $format->set_bold();
      my $values_row_a   = "";
      my $header_names_a = "";
      my $values_row_b   = "";
      my $values_row_c   = "";
      my $values_row_d   = "";
      my $header_names_b = "";
      my $header_names_c = "";
      my $header_names_d = "";
      my $l              = 2;
      my $i              = 1;

      foreach my $time ( sort keys %{ $hash_data{$lpar} } ) {
        my ( $ent_core, $util_cpu, $ent_cpu, $lan_rec_bytes, $lan_trans_bytes, $mem_used, $mem_fs_cache, $mem_free, $mem_pinned, $cpu_sys, $cpu_user, $cpu_io_wait, $cpu_idle, $pg1_page_out, $pg1_page_in, $pg2_paging_space, $pg2_percent, $san_rec_bytes, $san_trans_bytes, $iops_in, $iops_out, $read_res, $write_res, $load, $virtual, $blocked, $iops_read, $iops_write, $data_read, $data_write, $latency_read, $latency_write ) = "";
        $values_row_a   = "";
        $header_names_a = "";
        $values_row_b   = "";
        $values_row_c   = "";
        $values_row_d   = "";
        $header_names_b = "";
        $header_names_c = "";
        $header_names_d = "";

        foreach my $item ( sort keys %{ $hash_data{$lpar}{$time} } ) {
          foreach my $interface ( keys %{ $hash_data{$lpar}{$time}{$item} } ) {

            #print STDERR "1538,,$lpar -- $time -- $item -- $interface --- $hash_data{$lpar}{$time}{$item}{$interface},,\n";
            if ( $item eq "lpar" ) {
              ( $ent_core, $util_cpu, $ent_cpu ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_a   .= "$ent_core" . "$xls_s" . "$util_cpu" . "$xls_s" . "$ent_cpu" . "$xls_s";
              $header_names_a .= "Entitled processor cores" . "," . "Utilization in CPU cores" . "," . "Entitled CPU utilization in %" . ",";
            }
            if ( $item eq "oscpu" ) {
              ( $cpu_sys, $cpu_user, $cpu_io_wait, $cpu_idle ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_a   .= "$cpu_sys" . "$xls_s" . "$cpu_user" . "$xls_s" . "$cpu_io_wait" . "$xls_s" . "$cpu_idle" . "$xls_s";
              $header_names_a .= "CPU OS - Sys in %" . "," . "CPU OS - User in %" . "," . "CPU OS - IO Wait in %" . "," . "CPU OS - Idle in %" . ",";
            }
            if ( $item eq "mem" ) {
              ( $mem_used, $mem_fs_cache, $mem_free, $mem_pinned ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_c   .= "$mem_used" . "$xls_s" . "$mem_fs_cache" . "$xls_s" . "$mem_free" . "$xls_s" . "$mem_pinned" . "$xls_s";
              $header_names_c .= "MEM - Used in MB" . "," . "MEM - FS cache in MB" . "," . "MEM - Free in MB" . "," . "MEM - Pinned in MB" . ",";
            }
            if ( $item eq "pg1" ) {
              ( $pg1_page_out, $pg1_page_in ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_d   .= "$pg1_page_out" . "$xls_s" . "$pg1_page_in" . "$xls_s";
              $header_names_d .= "Page out" . "," . "Page in" . ",";
            }
            if ( $item eq "pg2" ) {
              ( $pg2_paging_space, $pg2_percent ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_d   .= "$pg2_paging_space" . "$xls_s" . "$pg2_percent" . "$xls_s";
              $header_names_d .= "Paging space in MB" . "," . "Paging utilization in %" . ",";
            }
            if ( $item eq "lan" ) {
              ( $lan_rec_bytes, $lan_trans_bytes ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_b   .= "$lan_rec_bytes" . "$xls_s" . "$lan_trans_bytes" . "$xls_s";
              $header_names_b .= "Read in bytes - $interface" . "," . "Write in bytes - $interface" . ",";
            }
            if ( $item eq "san1" ) {
              ( $san_rec_bytes, $san_trans_bytes ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_b   .= "$san_rec_bytes" . "$xls_s" . "$san_trans_bytes" . "$xls_s";
              $header_names_b .= "Read in bytes - $interface" . "," . "Write in bytes - $interface" . ",";
            }
            if ( $item eq "san2" ) {
              ( $iops_in, $iops_out ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_b   .= "$iops_in" . "$xls_s" . "$iops_out" . "$xls_s";
              $header_names_b .= "Read in IOPS- $interface" . "," . "Write in IOPS - $interface" . ",";
            }
            if ( $item eq "san_resp" ) {
              ( $read_res, $write_res ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_b   .= "$read_res" . "$xls_s" . "$write_res" . "$xls_s";
              $header_names_b .= "Read in ms - $interface" . "," . "Write in ms - $interface" . ",";
            }
            if ( $item eq "cpu-linux" ) {
              ( $cpucount, $stog2 ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_b   .= "$cpucount" . "$xls_s" . "$stog2" . "$xls_s";
              $header_names_b .= "Read in ms - $interface" . "," . "Write in ms - $interface" . ",";
            }
            if ( $item eq "queue_cpu" ) {
              ( $load, $virtual, $blocked ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_a   .= "$load" . "$xls_s" . "$virtual" . "$xls_s" . "$blocked" . "$xls_s";
              $header_names_a .= "Load Avrg" . "," . "Virtual processors" . "," . "Blocked processes" . ",";
            }
            if ( $item eq "total_iops" ) {
              ( $iops_read, $iops_write ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_d   .= "$iops_read" . "$xls_s" . "$iops_write" . "$xls_s";
              $header_names_d .= "IOPS read" . "," . "IOPS write" . ",";
            }
            if ( $item eq "total_data" ) {
              ( $data_read, $data_write ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_d   .= "$data_read" . "$xls_s" . "$data_write" . "$xls_s";
              $header_names_d .= "Data read - Bytes/sec" . "," . "Data write - Bytes/sec" . ",";
            }
            if ( $item eq "total_latency" ) {
              ( $latency_read, $latency_write ) = split( /;/, $hash_data{$lpar}{$time}{$item}{$interface} );
              $values_row_d   .= "$latency_read" . "$xls_s" . "$latency_write" . "$xls_s";
              $header_names_d .= "Latency read - ms" . "," . "Latency write - ms" . ",";
            }
          }
        }

        #print STDERR "$lpar -- $item -- $time -- $string\n";
        #print STDERR"$header_names\n";
        for ( my $j = 0; $j < 1; $j++ ) {
          my @header  = split( /,/, $header_names_a );
          my @header1 = split( /,/, $header_names_c );
          my @header2 = split( /,/, $header_names_d );
          my @header3 = split( /,/, $header_names_b );
          my @xlheader = ( "Time", @header, @header1, @header2, @header3 );
          $worksheet->write_row( 0, 0, \@xlheader, $format );
        }
        my @values_row_array  = split( /;/, $values_row_a );
        my @values_row_array1 = split( /;/, $values_row_c );
        my @values_row_array2 = split( /;/, $values_row_d );
        my @values_row_array3 = split( /;/, $values_row_b );
        my @xlrow             = ( @values_row_array, @values_row_array1, @values_row_array2, @values_row_array3 );
        $worksheet->write_row( $i, 1, \@xlrow );
        $worksheet->write_date_time( $i, 0, $time, $fdatetime );
        $i++;
      }
    }
  }
  if ($stopped) {
    print "Content-type: application/json\n\n";
    print "{ \"status\": \"terminated\", \"id\": \"$PAR{id}\"}";
    sleep(2);    # wait for GUI
    unlink "/tmp/pdfgen.$PAR{id}.stop";

  }
  else {
    $workbook->close();

    # binmode STDOUT;
    # print $str;

    # Save the Excel
    if ( open( XLS, ">", "/tmp/xlsgen.$PAR{id}.xls" ) ) {
      binmode XLS;
      print XLS $str;
      close XLS;
    }
    if ( open( FILE, ">", "/tmp/xlsgen.$PAR{id}.done" ) ) {
      close FILE;
    }

  }
}

sub xport_print {
  my $xml_org = shift;
  my $multi   = shift;
  my $server  = shift;
  my $lpar    = shift;
  my $item    = shift;
  my $xml     = "";

  if ( $multi == 1 ) {

    #print OUT "--xport-- $xml_org\n";
    $xml = XMLin( $xml_org, ForceArray => [ 'entry', 'v' ] );
  }
  else {

    #print OUT "--xport++ $$xml_org\n";
    $xml = XMLin( $$xml_org, ForceArray => [ 'entry', 'v' ] );
  }

  # file_write("/tmp/tmp.xml", Dumper $xml);
  #print STDERR Dumper ($xml);
  foreach my $item ( @{ $xml->{meta}{legend}{entry} } ) {    # in case semicolon in lpar name
    $item = "\"" . $item . "\"";
  }

  #my $i = 1; # skip header line
  foreach my $row ( @{ $xml->{data}{row} } ) {

    # my $time = strftime "%d.%m.%y %H:%M:%S", localtime( $row->{t} );
    my $time = strftime "%FT%H:%M", localtime( $row->{t} );    # yyyy-mm-ddThh:mm:ss
    foreach ( @{ $row->{v} } ) {
      $_ += 0;
    }

    # $row->{v} = map { $_ + 0 } @{ $row->{v} };

    my $line = join( ";", $time, @{ $row->{v} } );
    $line =~ s/NaNQ|NaN|nan/0/g;

    #print STDERR"$line\n";

    if ( $server eq "vmware_VMs" ) {                           ###### VMWARE
      my $uuid_test = $lpar;
      my ($vm_name_a) = grep /\Q$uuid_test/, @vm_list;
      my ( undef, $vm_name ) = split( /,/, $vm_name_a );
      chomp $vm_name;
      my $lpar = $vm_name;
      if ( $item eq "vmw-proc" ) {
        ( $time, $cpu_usage_proc, $v_cpu ) = split( /;/, $line );

        #print STDERR ",,$time,,$cpu_usage_proc,,$v_cpu,,\n";
        if ( defined $hash_data_vm{$lpar}{$time}{$item} && $hash_data_vm{$lpar}{$time}{$item} ne '' ) {
          $hash_data_vm{$lpar}{$time}{$item} = "$hash_data_vm{$lpar}{$time}{$item}" . "$xls_s" . "$cpu_usage_proc" . "$xls_s" . "$v_cpu";
        }
        else {
          $hash_data_vm{$lpar}{$time}{$item} = "$cpu_usage_proc" . "$xls_s" . "$v_cpu";
        }

        # push $hash_data_vm{$lpar}{$item}, ($time, $cpu_usage_proc, $v_cpu);
      }
      if ( $item eq "lpar" ) {
        ( $time, $reserved_cpu, $cpu_usage ) = split( /;/, $line );

        #print STDERR "$time,,$reserved_cpu,,$cpu_usage,,$v_cpu_units,,\n";
        if ( defined $hash_data_vm{$lpar}{$time}{$item} && $hash_data_vm{$lpar}{$time}{$item} ne '' ) {
          $hash_data_vm{$lpar}{$time}{$item} = "$hash_data_vm{$lpar}{$time}{$item}" . "$xls_s" . "$reserved_cpu" . "$xls_s" . "$cpu_usage";
        }
        else {
          $hash_data_vm{$lpar}{$time}{$item} = "$reserved_cpu" . "$xls_s" . "$cpu_usage";
        }
      }

      if ( $item eq "vmw-mem" ) {
        ( $time, $mem_garanted, $mem_baloon, $mem_active ) = split( /;/, $line );

        #print STDERR "$time,,$mem_garanted,,$mem_baloon,,$mem_active,,\n";
        if ( defined $hash_data_vm{$lpar}{$time}{$item} && $hash_data_vm{$lpar}{$time}{$item} ne '' ) {
          $hash_data_vm{$lpar}{$time}{$item} = "$hash_data_vm{$lpar}{$time}{$item}" . "$xls_s" . "$mem_garanted" . "$xls_s" . "$mem_baloon" . "$xls_s" . "$mem_active";
        }
        else {
          $hash_data_vm{$lpar}{$time}{$item} = "$mem_garanted" . "$xls_s" . "$mem_baloon" . "$xls_s" . "$mem_active";
        }
      }

      if ( $item eq "vmw-disk" ) {
        ( $time, $disk_usage ) = split( /;/, $line );
        if ( defined $hash_data_vm{$lpar}{$time}{$item} && $hash_data_vm{$lpar}{$time}{$item} ne '' ) {
          $hash_data_vm{$lpar}{$time}{$item} = "$hash_data_vm{$lpar}{$time}{$item}" . "$xls_s" . "$disk_usage";
        }
        else {
          $hash_data_vm{$lpar}{$time}{$item} = "$disk_usage";
        }
      }
      my ( $cpu_usage_proc1, $v_cpu1, $reserved_cpu1, $cpu_usage1, $v_cpu_units1, $mem1_garanted, $mem1_baloon, $mem1_active, $disk_usage1, $disk_net1, $swap_in1, $swap_out1, $compres1, $decompres1 ) = "";
      if ( $item eq "vmw-net" ) {
        ( $time, $disk_net ) = split( /;/, $line );
        if ( defined $hash_data_vm{$lpar}{$time}{$item} && $hash_data_vm{$lpar}{$time}{$item} ne '' ) {
          $hash_data_vm{$lpar}{$time}{$item} = "$hash_data_vm{$lpar}{$time}{$item}" . "$xls_s" . "$disk_net";
        }
        else {
          $hash_data_vm{$lpar}{$time}{$item} = "$disk_net";
        }
      }
      if ( $item eq "vmw-swap" ) {
        ( $time, $swap_in, $swap_out ) = split( /;/, $line );
        if ( defined $hash_data_vm{$lpar}{$time}{$item} && $hash_data_vm{$lpar}{$time}{$item} ne '' ) {
          $hash_data_vm{$lpar}{$time}{$item} = "$hash_data_vm{$lpar}{$time}{$item}" . "$xls_s" . "$swap_in" . "$xls_s" . "$swap_out";
        }
        else {
          $hash_data_vm{$lpar}{$time}{$item} = "$swap_in" . "$xls_s" . "$swap_out";
        }
      }

      if ( $item eq "vmw-comp" ) {
        ( $time, $compres, $decompres ) = split( /;/, $line );
        if ( defined $hash_data_vm{$lpar}{$time}{$item} && $hash_data_vm{$lpar}{$time}{$item} ne '' ) {
          $hash_data_vm{$lpar}{$time}{$item} = "$hash_data_vm{$lpar}{$time}{$item}" . "$xls_s" . "$compres" . "$xls_s" . "$decompres";
        }
        else {
          $hash_data_vm{$lpar}{$time}{$item} = "$compres" . "$xls_s" . "$decompres";
        }
      }

    }
    else {    ##### POWER
      if ( $item eq "lpar" ) {
        ( $time, $ent_core, $util_cpu, $ent_cpu ) = split( /;/, $line );

        #print STDERR "???$line???\n";
        if ( defined $hash_data{$lpar}{$time}{$item}{lparfile} && $hash_data{$lpar}{$time}{$item}{lparfile} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$hash_data{$lpar}{$time}{$item}{lparfile}" . "$xls_s" . "$ent_core" . "$xls_s" . "$util_cpu" . "$xls_s" . "$ent_cpu";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$ent_core" . "$xls_s" . "$util_cpu" . "$xls_s" . "$ent_cpu";
        }
      }

      if ( $item eq "oscpu" ) {
        ( $time, $sys, $user, $io_wait, $idle ) = split( /;/, $line );
        if ( defined $hash_data{$lpar}{$time}{$item}{cpufile} && $hash_data{$lpar}{$time}{$item}{cpufile} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{cpufile} = "$hash_data{$lpar}{$time}{$item}{cpufile}" . "$xls_s" . "$sys" . "$xls_s" . "$user" . "$xls_s" . "$io_wait" . "$xls_s" . "$idle";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{cpufile} = "$sys" . "$xls_s" . "$user" . "$xls_s" . "$io_wait" . "$xls_s" . "$idle";
        }
      }

      if ( $item eq "mem" ) {
        ( $time, $used, $fs_cache, $free, $pinned ) = split( /;/, $line );
        if ( defined $hash_data{$lpar}{$time}{$item}{memfile} && $hash_data{$lpar}{$time}{$item}{memfile} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{memfile} = "$hash_data{$lpar}{$time}{$item}{memfile}" . "$xls_s" . "$used" . "$xls_s" . "$fs_cache" . "$xls_s" . "$free" . "$xls_s" . "$pinned";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{memfile} = "$used" . "$xls_s" . "$fs_cache" . "$xls_s" . "$free" . "$xls_s" . "$pinned";
        }
      }

      if ( $item eq "pg1" ) {
        ( $time, $page_out, $page_in ) = split( /;/, $line );
        if ( defined $hash_data{$lpar}{$time}{$item}{pg1file} && $hash_data{$lpar}{$time}{$item}{pg1file} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{pg1file} = "$hash_data{$lpar}{$time}{$item}{pg1file}" . "$xls_s" . "$page_out" . "$xls_s" . "$page_in";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{pg1file} = "$page_out" . "$xls_s" . "$page_in";
        }
      }

      if ( $item eq "pg2" ) {
        ( $time, $paging_space, $percent_pag ) = split( /;/, $line );
        if ( defined $hash_data{$lpar}{$time}{$item}{pg2file} && $hash_data{$lpar}{$time}{$item}{pg2file} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{pg2file} = "$hash_data{$lpar}{$time}{$item}{pg2file}" . "$xls_s" . "$paging_space" . "$xls_s" . "$percent_pag";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{pg2file} = "$paging_space" . "$xls_s" . "$percent_pag";
        }
      }

      if ( $item eq "lan" ) {
        ( $time, $rec_bytes, $trans_bytes ) = split( /;/, $line );
        if ( defined $hash_data{$lpar}{$time}{$item}{$lan_en} && $hash_data{$lpar}{$time}{$item}{$lan_en} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{$lan_en} = "$hash_data{$lpar}{$time}{$item}{$lan_en}" . "$xls_s" . "$rec_bytes" . "$xls_s" . "$trans_bytes";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{$lan_en} = "$rec_bytes" . "$xls_s" . "$trans_bytes";
        }

        #print STDERR",,$hash_data{$lpar}{$time}{$item}{$lan_en},,\n";
      }

      if ( $item eq "san1" ) {
        ( $time, $rec_bytes_s, $trans_bytes_s ) = split( /;/, $line );
        if ( defined $hash_data{$lpar}{$time}{$item}{$san_en} && $hash_data{$lpar}{$time}{$item}{$san_en} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{$san_en} = "$hash_data{$lpar}{$time}{$item}{$san_en}" . "$xls_s" . "$rec_bytes_s" . "$xls_s" . "$trans_bytes_s";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{$san_en} = "$rec_bytes_s" . "$xls_s" . "$trans_bytes_s";
        }
      }

      if ( $item eq "san2" ) {
        ( $time, $iops_in, $iops_out ) = split( /;/, $line );
        if ( defined $hash_data{$lpar}{$time}{$item}{$san_en} && $hash_data{$lpar}{$time}{$item}{$san_en} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{$san_en} = "$hash_data{$lpar}{$time}{$item}{$san_en}" . "$xls_s" . "$iops_in" . "$xls_s" . "$iops_out";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{$san_en} = "$iops_in" . "$xls_s" . "$iops_out";
        }
      }

      if ( $item eq "san_resp" ) {
        ( $time, $read_res, $write_res ) = split( /;/, $line );
        if ( defined $hash_data{$lpar}{$time}{$item}{$san_resp} && $hash_data{$lpar}{$time}{$item}{$san_resp} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{$san_resp} = "$hash_data{$lpar}{$time}{$item}{$san_resp}" . "$xls_s" . "$read_res" . "$xls_s" . "$write_res";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{$san_resp} = "$read_res" . "$xls_s" . "$write_res";
        }
      }
      if ( $item eq "cpu-linux" ) {
        ( $time, $cpucount, $stog2 ) = split( /;/, $line );

        #print STDERR "1975 \$line $line\n";
        if ( defined $hash_data{$lpar}{$time}{$item}{lparfile} && $hash_data{$lpar}{$time}{$item}{lparfile} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$hash_data{$lpar}{$time}{$item}{lparfile}" . "$xls_s" . "$cpucount" . "$xls_s" . "$stog2";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$cpucount" . "$xls_s" . "$stog2";
        }
      }
      if ( $item eq "queue_cpu" ) {
        ( $time, $load, $virtual, $blocked ) = split( /;/, $line );

        #print STDERR "???$line???\n";
        if ( defined $hash_data{$lpar}{$time}{$item}{lparfile} && $hash_data{$lpar}{$time}{$item}{lparfile} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$hash_data{$lpar}{$time}{$item}{lparfile}" . "$xls_s" . "$load" . "$xls_s" . "$virtual" . "$xls_s" . "$blocked";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$load" . "$xls_s" . "$virtual" . "$xls_s" . "$blocked";
        }
      }
      if ( $item eq "total_iops" ) {
        ( $time, $iops_read, $iops_write ) = split( /;/, $line );

        #print STDERR "???$line???\n";
        if ( defined $hash_data{$lpar}{$time}{$item}{lparfile} && $hash_data{$lpar}{$time}{$item}{lparfile} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$hash_data{$lpar}{$time}{$item}{lparfile}" . "$xls_s" . "$iops_read" . "$xls_s" . "$iops_write";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$iops_read" . "$xls_s" . "$iops_write";
        }
      }
      if ( $item eq "total_data" ) {
        ( $time, $data_read, $data_write ) = split( /;/, $line );

        #print STDERR "???$line???\n";
        if ( defined $hash_data{$lpar}{$time}{$item}{lparfile} && $hash_data{$lpar}{$time}{$item}{lparfile} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$hash_data{$lpar}{$time}{$item}{lparfile}" . "$xls_s" . "$data_read" . "$xls_s" . "$data_write";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$data_read" . "$xls_s" . "$data_write";
        }
      }
      if ( $item eq "total_latency" ) {
        ( $time, $latency_read, $latency_write ) = split( /;/, $line );

        #print STDERR "???$line???\n";
        if ( defined $hash_data{$lpar}{$time}{$item}{lparfile} && $hash_data{$lpar}{$time}{$item}{lparfile} ne '' ) {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$hash_data{$lpar}{$time}{$item}{lparfile}" . "$xls_s" . "$latency_read" . "$xls_s" . "$latency_write";
        }
        else {
          $hash_data{$lpar}{$time}{$item}{lparfile} = "$latency_read" . "$xls_s" . "$latency_write";
        }
      }
    }
  }
  return 0;
}

#print STDERR Dumper \%hash_data;
#print STDERR Dumper \%hash_data_vm;

sub isdigit {
  my $digit = shift;
  my $text  = shift;

  if ( $digit eq '' ) {
    return 0;
  }
  if ( $digit eq 'U' ) {
    return 1;
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

sub epoch2iso {
  my $tm = shift;    # epoch
  if ( !$tm ) {
    $tm = time();
  }
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($tm);
  my $y   = $year + 1900;
  my $m   = $mon + 1;
  my $mcs = 0;
  my $str = sprintf( "%4d%02d%02d-%02d%02d%02d", $y, $m, $mday, $hour, $min, $sec );
  return ($str);
}

sub urlencode {
  my $s = shift;

  #$s =~ s/ /+/g;
  $s =~ s/([^a-zA-Z0-9!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  #$s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  return $s;
}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;

  #$s =~ s/\+/ /g;
  return $s;
}

sub result {
  my ( $status, $msg, $log ) = @_;
  $log ||= "";
  $msg =~ s/\n/\\n/g;
  $msg =~ s/\\:/\\\\:/g;
  $log =~ s/\n/\\n/g;
  $log =~ s/\\:/\\\\:/g;
  $log =~ s/\t/ /g;
  $status = ($status) ? "true" : "false";
  print "{ \"success\": $status, \"message\" : \"$msg\", \"log\": \"$log\"}";
}

sub file_write {
  my $file = shift;
  open IO, ">$file" or die "Cannot open $file for output: $!\n";
  print IO @_;
  close IO;
}
