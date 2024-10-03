#
### Global Historical reports
#
use strict;
use Date::Parse;
use MIME::Base64;
use Data::Dumper;
use XoruxEdition;
use OracleVmDataWrapperOOP;

my $bindir   = $ENV{BINDIR};
my $DEBUG    = $ENV{DEBUG};
my $errlog   = $ENV{ERRLOG};
my $xport    = $ENV{EXPORT_TO_CSV};
my $inputdir = $ENV{INPUTDIR};
my $tmpdir   = "$inputdir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $detail_yes    = 1;
my $detail_no     = 0;
my $detail_9      = 9;
my $entitle       = 0;
my $lpm           = $ENV{LPM};
my $basedir       = $ENV{INPUTDIR};
my $wrkdir        = $basedir . "/data";
my $orvm_metadata = OracleVmDataWrapperOOP->new( { acl_check => 0 } );

my $width_detail  = 1200;
my $height_detail = 450;
open( OUT, ">> $errlog" ) if $DEBUG == 2;

# print HTML header
print "Content-type: text/html\n\n";

my $premium = 0;
if ( length( premium() ) == 6 ) {
  $premium = 1;
}

#foreach $key (sort keys(%ENV)) {
#   print "$key = $ENV{$key}<p>";
#}

# get QUERY_STRING
use Env qw(QUERY_STRING);

#$QUERY_STRING .= ":.";
print OUT "-- $QUERY_STRING\n" if $DEBUG == 2;

my $shour          = "";
my $sday           = "";
my $smon           = "";
my $syear          = "";
my $ehour          = "";
my $eday           = "";
my $emon           = "";
my $eyear          = "";
my $type           = "";
my $height         = "";
my $width          = "";
my $lpar_list      = "";
my @lpar_row       = "";
my @pool_row       = "";
my @pool_total_row = "";
my @cgroup_row     = "";
my $sort_order     = "";
my $new_gui        = 0;
my $pool           = "";
my $new_server     = "";
my $lparform       = 0;            # LPAR or POOL from global reports
my $yaxis          = "";
my $newsrv         = "";
my $srcfix         = 0;
my $dstfix         = 0;
my $estimator      = 1;            # euither CPU estimator or historical reporting
my $referer        = "";
my $mname          = "";
my $NMON           = "--NMON--";

# First check whether POST or GET
my $r_method = $ENV{'REQUEST_METHOD'};
if ( $r_method eq '' ) {
  $r_method = "GET";
}
else {
  $r_method =~ tr/a-z/A-Z/;
}

if ( $r_method =~ m/POST/ ) {

  # POST is being used, it is just a workaround when GET reaches
  #   Request-URI Too Large, and The requested URL's length exceeds the capacity limit for this server.
  # only historical report so far implemented

  my $buffer          = "";
  my @pairs           = "";
  my $pair            = "";
  my $name            = "";
  my $value           = "";
  my %FORM            = "";
  my $lpar_indx       = 0;
  my $pool_indx       = 0;
  my $pool_total_indx = 0;
  my $cgroup_indx     = 0;

  read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );

  # Split information into name/value pairs
  @pairs = split( /&/, $buffer );

  foreach $pair (@pairs) {

    #`echo "00: $pair" >> /tmp/e8`;
    ( $name, $value ) = split( /=/, $pair );
    $value =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
    $value =~ tr/+/ /;

    #print "N: $name, v:$value\n";
    my $string   = $value;
    my @vals     = split( '\|', $string );
    my $prev_hmc = $vals[0];

    my @pool_total_files = <$inputdir/data/$vals[1]/*\/pool_total.rrt>;
    if ( defined $pool_total_files[0] ) {

      #print STDERR "file paths: $inputdir/data/$vals[1]/*\/pool_total.rrt\n";
      #print STDERR Dumper \@pool_total_files;

      my $newest_pool_total = "";
      my $newest_ts         = -1;

      foreach my $file (@pool_total_files) {
        my $file_time_diff = Xorux_lib::file_time_diff("$file");
        if ( $newest_ts == -1 || $newest_ts >= $file_time_diff ) {
          $newest_pool_total = $file;
          $newest_ts         = $file_time_diff;
        }
      }

      my @hmc_check = split( '\/', $newest_pool_total );

      #print STDERR "NEWES: $newest_pool_total is $newest_ts old\n";

      my $hmc_current = $hmc_check[-2];
      $value =~ s/$prev_hmc/$hmc_current/g;
    }

    #print STDERR "VALUE NEW : $value\n";

    if ( $name =~ m/^LPAR$/ ) {
      $lparform = 1;

      # specil handling of pasing lpars
      # do not do here pack ....
      $lpar_row[$lpar_indx] = $name . "=" . $value;
      $lpar_indx++;
      next;
    }
    elsif ( $name =~ m/^POOL$/ && $value !~ m/total$/ ) {

      # specil handling of pasing lpars
      # do not do here pack ....
      $pool_row[$pool_indx] = $name . "=" . $value;
      $pool_indx++;
      next;
    }
    elsif ( $name =~ m/^POOL$/ && $value =~ m/total$/ ) {
      $pool_total_row[$pool_total_indx] = $name . "=" . $value;
      $pool_total_indx++;
      next;
    }
    elsif ( $name =~ m/^CGROUP$/ ) {

      # specil handling of pasing lpars
      # do not do here pack ....
      $cgroup_row[$cgroup_indx] = $name . "=" . $value;
      $cgroup_indx++;
      next;
    }
    $FORM{$name} = $value;

    #`echo "$name - $value - $FORM{$name} " >> /tmp/e12`;
  }

  #print STDERR Dumper \%FORM;

  # join LPAR and CGROUP
  if ( $lpar_indx == 0 ) {
    @lpar_row = @cgroup_row;
  }
  else {
    if ( $cgroup_indx > 0 ) {
      my @merged = ( @lpar_row, @cgroup_row );
      @lpar_row = @merged;
    }
  }

  $smon       = $FORM{"start-mon"};
  $sday       = $FORM{"start-day"};
  $shour      = $FORM{"start-hour"};
  $syear      = $FORM{"start-yr"};
  $emon       = $FORM{"end-mon"};
  $eday       = $FORM{"end-day"};
  $ehour      = $FORM{"end-hour"};
  $eyear      = $FORM{"end-yr"};
  $type       = $FORM{"type"};
  $height     = $FORM{"HEIGHT"};
  $width      = $FORM{"WIDTH"};
  $sort_order = $FORM{"sort"};
  $new_gui    = $FORM{"gui"};
  $new_server = $FORM{"NEW"};
  $pool       = $FORM{"pool"};
  $newsrv     = $FORM{"newsrv"};
  $srcfix     = $FORM{"srcfix"};
  $dstfix     = $FORM{"dstfix"};
  $mname      = $FORM{"MNAME"};

  if ( $srcfix eq '' ) {
    $srcfix = 0;
  }
  if ( $dstfix eq '' ) {
    $dstfix = 0;
  }

  if ( $newsrv eq '' ) {

    # historical report, there is no "newsrv" item passed
    $newsrv    = 0;
    $estimator = 0;
  }
  else {
    if ( $newsrv == 0 && defined $pool_row[0] && !$pool_row[0] eq '' ) {

      # existing pool estimation, it is in that env, just 1 row is passed for estimator usage
      $pool = $pool_row[0];
    }
  }
  $yaxis   = $FORM{"yaxis"};
  $referer = $FORM{"referer"};
  $entitle = $FORM{"entitle"};
}

else {
  # GET, standard way ...
  # POST is used now, this might be ignored, there is no fix implementation (dstfix & srcfix)

  # first time just separate if new or already existing server
  # complication can be if are highlighted some rows in both new and existing
  ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $sort_order, $new_gui, my $newsrv1, my $newsrv2, my $check1, my $check2, $entitle ) = split( /&/, $QUERY_STRING );

  if ( $newsrv1 =~ m/^newsrv=/ ) {
    $newsrv = $newsrv1;
  }
  else {
    if ( $newsrv2 =~ m/^newsrv=/ ) {
      $newsrv = $newsrv2;
    }
    else {
      $estimator = 0;    # it was called from historical reporting therefore not CPU estimation
      if ( $new_gui =~ /MNAME=Solaris--unknown/ ) {
        ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $sort_order, $new_gui,, @lpar_row, $entitle ) = split( /&/, $QUERY_STRING );
      }
      elsif ( $new_gui =~ /MNAME=hyperv/ ) {
        ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $sort_order, $new_gui,, @lpar_row, $entitle ) = split( /&/, $QUERY_STRING );
      }
      else {
        ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $sort_order, $new_gui, $pool, @lpar_row, $entitle ) = split( /&/, $QUERY_STRING );
      }
    }
  }

  if ($estimator) {
    $newsrv =~ s/newsrv=//;
    if ( $newsrv == 0 ) {

      # usage with existing server / CPU pool
      if ( $newsrv1 =~ m/^newsrv=/ && $newsrv2 =~ m/^POOL=/ && $check1 =~ m/^LPAR/ ) {
        ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $sort_order, $new_gui, $newsrv, $pool, @lpar_row, $entitle ) = split( /&/, $QUERY_STRING );
      }
      else {
        if ( $newsrv1 =~ m/^NEW=/ && $newsrv2 =~ m/^newsrv=/ && $check1 =~ m/^POOL/ && $check2 =~ m/^LPAR/ ) {
          ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $sort_order, $new_gui, my $trash, $newsrv, $pool, @lpar_row, $entitle ) = split( /&/, $QUERY_STRING );
        }
        else {
          $new_gui =~ s/gui=//;
          err_html("Existing server has been checked but have not been chosen anyone");
        }
      }
    }

    if ( $newsrv == 1 ) {

      # usage with new server
      if ( $newsrv1 =~ m/^newsrv=/ && $newsrv2 =~ m/^NEW=/ && $check1 =~ m/^POOL/ && $check2 =~ m/^LPAR/ ) {
        ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $sort_order, $new_gui, $newsrv, $new_server,, my $trash, @lpar_row, $entitle ) = split( /&/, $QUERY_STRING );
      }
      else {
        if ( $newsrv1 =~ m/^newsrv=/ && $newsrv2 =~ m/^NEW=/ && $check1 =~ m/^LPAR/ ) {
          ( $shour, $sday, $smon, $syear, $ehour, $eday, $emon, $eyear, $type, $height, $width, $yaxis, $sort_order, $new_gui, $newsrv, $new_server,, @lpar_row, $entitle ) = split( /&/, $QUERY_STRING );
        }
        else {
          $new_gui =~ s/gui=//;
          err_html("New server has been checked but has not been selected any");
        }
      }
    }
  }

  # `echo "000 $new_server " >> /tmp/e10`;
  #foreach my $i (@lpar_row) {
  #  `echo "001 $i" >> /tmp/e8`;
  #}
  #  `echo "002 " >> /tmp/e8`;
  #
  #`echo "EST:$estimator NEW:$newsrv" >> /tmp/e8`;
  print STDERR"5$QUERY_STRING\n";

  $smon       =~ s/start-mon=//;
  $sday       =~ s/start-day=//;
  $shour      =~ s/start-hour=//;
  $syear      =~ s/start-yr=//;
  $emon       =~ s/end-mon=//;
  $eday       =~ s/end-day=//;
  $ehour      =~ s/end-hour=//;
  $eyear      =~ s/end-yr=//;
  $type       =~ s/type=//;
  $height     =~ s/\+//g;
  $height     =~ s/HEIGHT=//;
  $width      =~ s/\+//g;
  $width      =~ s/WIDTH=//;
  $sort_order =~ s/sort=//;
  $newsrv     =~ s/newsrv=//;
  $pool       =~ s/pool=//;
  $yaxis      =~ s/yaxis=//;
  $entitle    =~ s/entitle=//;
  $new_gui    =~ s/gui=//;

}    # end of HTML GET

# if == 1 then restrict views (only CPU and mem)
if ( $entitle eq '' || isdigit($entitle) == 0 ) {
  $entitle = 0;    # when eny problem then allow it!
}

# http_base must be passed through cgi-bin script to get location of jquery scripts and others
# it is taken from HTTP_REFERER first time and then passed in the HTML GET
my $html_base = "";

#`echo "01 $referer " >> /tmp/xx32`;
#if ( $referer ne "" && $referer !~ m/none=none/ && $referer =~ m/^referer=/ ) {
# when is referer set then it is already html_base --> not call html_base($refer) again
#  $referer =~ s/referer=//;
#  $referer =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
#  $referer =~ s/\+/ /g;
#  $html_base = $referer ;
#}
#else {
#  $referer = $ENV{HTTP_REFERER};
#  $html_base = html_base($referer); # it must be here behind $base setting
#}

# find count number of lpars' files "lpar.rrm"
my $count_rrm = 0;

# find count number of selected lpars
my $count = 0;
foreach my $line10 (@lpar_row) {
  $count++;
}

# only agent system $wrkdir/$server--unknown/no_hmc
# "--unknown" must be added to server name
# if "--unknown" exists -> do not care for not "--unknown" !!
foreach my $line10 (@lpar_row) {
  ( undef, my $server_qs, undef ) = split( /\|/, $line10 );
  my $server = $server_qs;
  $server =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;

  # $server =~ s/\+/ /g;
  # print STDERR "319 $server $server_qs\n";
  if ( -d "$wrkdir/$server--unknown/" ) {
    my $name_idx = index $line10, $server_qs;
    if ( $name_idx >= 0 ) {
      substr( $line10, $name_idx, length($server_qs), "$server_qs--unknown" );
    }

    # print STDERR "326 lpar-list-cgi.pl --unknown $server \$line10 $line10\n";
  }
}

# print STDERR "328 lpar-list-cgi.pl \@lpar_row @lpar_row\n";

if ( ( $yaxis =~ m/w/ || $yaxis =~ m/s/ || $yaxis =~ m/r/ ) && $premium == 0 ) {
  if ( $new_gui == 0 ) {
    print_head( 0, $referer );
  }

  # it is free version which does not support rPerf
  not_available();
  exit(0);
}
if ( $yaxis =~ m/s/ ) {

  # SAPs
  not_implemented();
  exit 0;
}

my $start       = $syear . $smon . $sday;
my $end         = $eyear . $emon . $eday;
my $human_start = $shour . ":00:00 " . $sday . "." . $smon . "." . $syear;
my $human_end   = $ehour . ":00:00 " . $eday . "." . $emon . "." . $eyear;

my $start_unix = str2time( $syear . "-" . $smon . "-" . $sday . " " . $shour . ":00:00" );
my $end_unix   = "";

# workaround for 24:00. If is used proper 00:00 of the next day then there are 2 extra records in cvs after the midnight
# looks like rrdtool issue
if ( $ehour == 24 ) {
  $end_unix = str2time( $eyear . "-" . $emon . "-" . $eday . " 23:59:00" );
}
else {
  $end_unix = str2time( $eyear . "-" . $emon . "-" . $eday . " " . $ehour . ":00:00" );
}

my $l = length($start_unix);
print OUT "$human_start : $human_end : $start_unix : $end_unix : $l \n" if $DEBUG == 2;

if ( length($start_unix) < 1 ) {
  if ( $new_gui == 0 ) {
    print_head( 0, $referer );
  }
  print "<center><br>Start date (<B>$sday.$smon.$syear</B>) does not seem to be valid</center>\n";
  if ( $new_gui == 0 ) {
    print "</BODY></HTML>";
  }
  exit(0);
}

if ( length($end_unix) < 1 ) {
  if ( $new_gui == 0 ) {
    print_head( 0, $referer );
  }
  print "<center><br>End date (<B>$eday.$emon.$eyear</B>) does not seem to be valid</center>\n";
  if ( $new_gui == 0 ) {
    print "</BODY></HTML>";
  }
  exit(0);
}

if ( $end_unix <= $start_unix ) {
  if ( $new_gui == 0 ) {
    print_head( 0, $referer );
  }
  print "<center><br>Start (<B>$human_start</B>) should be less than end (<B>$human_end</B>)</center>\n";
  if ( $new_gui == 0 ) {
    print "</BODY></HTML>";
  }
  exit(0);
}

my $agent           = 0;
my $agent_oscpu     = 0;
my $agent_ame       = 0;
my $agent_pgs       = 0;
my $agent_mem       = 0;
my $agent_san       = 0;
my $agent_lan       = 0;
my $agent_sea       = 0;
my $agent_san_resp  = 0;
my $agent_queue_cpu = 0;

# NMON part
my $agent_oscpu_n = 0;
my $agent_ame_n   = 0;
my $agent_pgs_n   = 0;
my $agent_mem_n   = 0;
my $agent_san_n   = 0;
my $agent_lan_n   = 0;
my $agent_sea_n   = 0;

my $agent_as400 = 0;
my $path_as400  = "";

#
# Windows part
#
my $menu_txt              = "$basedir/tmp/menu.txt";
my $agent_win             = 0;
my $agent_data_win        = 0;
my $agent_win_server      = 0;
my $agent_data_win_server = 0;
my @menu;
if ( -f $menu_txt ) {
  open( MENU, "<$menu_txt" ) || error( "Couldn't open file $menu_txt $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
  @menu = <MENU>;
  chomp @menu;
  close(MENU);
}
if ( $mname =~ /hyperv/ ) {
  foreach my $line_tmp (@lpar_row) {
    my $line = $line_tmp;
    if ( $line =~ m/^LPAR=hyperv-vm/ ) {
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      ( my $host, my $vm_uuid ) = split( /\|/, $line );
      my ($grep_line) = grep ( /$vm_uuid/, @menu );
      ( undef, my $domain, my $server_windows, undef, my $vm_name ) = split( /\:/, $grep_line );

      #if ( $lpar eq '' ) {
      #  error( "Could not find a lpar : $line " . __FILE__ . ":" . __LINE__ );
      #  next;    # some problem
      #}

      my $type_sam          = $type;
      my $upper             = 0;
      my $legend            = "legend";
      my $uuid_name_for_csv = $vm_uuid;
      $uuid_name_for_csv =~ s/([^a-zA-Z0-9\+-_])/sprintf("%%%02X", ord($1))/ge;
      $vm_uuid           =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      $vm_uuid           =~ s/\//&&1/g;                                           # general replacement for file system
      my $test_dir = "$wrkdir/windows/domain_$domain/hyperv_VMs";
      $agent_win++;

      if ( test_file_in_directory( "$test_dir", "$vm_uuid", "rrm" ) ) {
        $agent_data_win++;
      }
    }
    if ( $line =~ m/^LPAR=hyperv-server/ ) {
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      ( my $host, my $server_name ) = split( /\|/, $line );
      my ($grep_line) = grep ( /^S:.*:$server_name:Totals:/, @menu );
      ( undef, my $domain ) = split( /\:/, $grep_line );

      my $type_sam = $type;
      my $upper    = 0;
      my $legend   = "legend";

      #my $uuid_name_for_csv = $vm_uuid;
      #$uuid_name_for_csv =~ s/([^a-zA-Z0-9\+-_])/sprintf("%%%02X", ord($1))/ge;
      #$vm_uuid =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      #$vm_uuid =~ s/\//&&1/g;    # general replacement for file system
      my $test_dir = "$wrkdir/windows/domain_$domain/$server_name";
      $agent_win_server++;
      if ( test_file_in_directory( "$test_dir", "pool", "rrm" ) ) {
        $agent_data_win_server++;
      }
    }
  }
}

if ( $mname =~ /hyperv/ ) {
  print "<div  id=\"tabs\"> <ul>\n";
  if ( $agent_data_win > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-0\">CPU</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-1\">MEM</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-2\">DISK</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-3\">LAN</a></li>\n";
  }
  if ( $agent_data_win_server > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-0\">CPU</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-1\">CPU queue</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-2\">Process</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-3\">Allocation</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-4\">Paging</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-5\">Paging2</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-6\">LAN</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-7\">Data</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-8\">IOPS</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-9\">Latency</a></li>\n";
  }
  print "   </ul> \n";
}
#
# end Windows part
#

#
# Solaris part
#
my $agent_sol           = 0;
my $agent_cpu_sol       = 0;
my $agent_queue_cpu_sol = 0;
my $agent_oscpu_sol     = 0;
my $agent_mem_sol       = 0;
my $agent_pgs_sol       = 0;
my $agent_lan_sol       = 0;
my $agent_san_sol       = 0;
my $agent_sanmon_sol    = 0;

if ( $mname =~ /Solaris--unknown/ ) {
  foreach my $line_tmp (@lpar_row) {
    my $line = $line_tmp;

    #print STDERR "$QUERY_STRING\n";
    if ( $line =~ m/^LPAR=/ ) {
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      ( my $host, my $server, my $lpar ) = split( /\|/, $line );
      my ( $host, $server, $lpar ) = "";
      ( $host, $server, $lpar ) = split( /\|/, $line );
      if ( $server =~ /:/ ) {
        ($server) = split( /\:/, $server );
      }
      if ( $lpar eq "" ) {
        $lpar = $server;
      }

      #print STDERR"line-537=====$host,$server,$lpar===========\n";
      if ( $lpar eq '' ) {
        error( "Could not find a lpar : $line " . __FILE__ . ":" . __LINE__ );
        next;    # some problem
      }

      my $type_sam          = $type;
      my $upper             = 0;
      my $legend            = "legend";
      my $lpar_name_for_csv = $lpar;
      $lpar_name_for_csv =~ s/([^a-zA-Z0-9\+-_])/sprintf("%%%02X", ord($1))/ge;
      $lpar              =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      $lpar              =~ s/\//&&1/g;                                           # general replacement for file system
      my $server_dom   = "$server:$lpar";
      my $test_dir_dom = "$wrkdir/Solaris/$server_dom";
      my $test_dir_os  = "$wrkdir/Solaris--unknown/no_hmc/$server_dom";
      $agent_sol++;

      #print STDERR"$test_dir_dom ||??| $test_dir_os\n";
      if ( test_file_in_directory( "$test_dir_dom", "$lpar\_ldom" ) ) {
        $agent_cpu_sol++;
      }
      if ( test_file_in_directory( "$test_dir_os", "cpu" ) ) {
        $agent_oscpu_sol++;
      }
      if ( test_file_in_directory( "$test_dir_os", "queue_cpu" ) ) {
        $agent_queue_cpu_sol++;
      }
      if ( test_file_in_directory( "$test_dir_os", "mem" ) ) {
        $agent_mem_sol++;
      }
      if ( test_file_in_directory( "$test_dir_os", "pgs" ) ) {
        $agent_pgs_sol++;
      }
      if ( test_file_in_directory( "$test_dir_os", "lan-" ) ) {
        $agent_lan_sol++;
      }
      if ( test_file_in_directory( "$test_dir_dom", "san-" ) ) {
        $agent_san_sol++;
      }
      if ( test_file_in_directory( "$test_dir_os", "total-san" ) ) {
        $agent_sanmon_sol++;
      }
    }
  }
}

if ( $mname =~ /Solaris--unknown/ ) {

  print "<div  id=\"tabs\"> <ul>\n";
  if ( $agent_cpu_sol > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-0\">CPU</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-1\">MEM</a></li>\n";
  }
  if ( $agent_oscpu_sol > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-2\">CPU OS</a></li>\n";
  }
  if ( $agent_queue_cpu_sol > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-3\">CPU QUEUE</a></li>\n";
  }
  if ( $agent_mem_sol > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-4\">Memory</a></li>\n";
  }
  if ( $agent_pgs_sol > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-5\">Paging 1</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-6\">Paging 2</a></li>\n";
  }
  if ( $agent_lan_sol > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-7\">LAN</a></li>\n";
  }
  if ( $agent_san_sol > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-8\">SAN</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-9\">SAN IOPS</a></li>\n";
  }
  if ( $agent_sanmon_sol > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-10\">SAN [N]</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-11\">SAN IOPS [N]</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-12\">SAN RESP [N]</a></li>\n";
  }
  print "   </ul> \n";
}

#
# end Solaris part
#

#
# OracleVM part
#
my $agent_orvm                     = 0;
my $agent_sys_orvm_vm              = 0;
my $agent_sys_orvm_server          = 0;
my $agent_sys_orvm_cpu_os_agent    = 0;
my $agent_sys_orvm_cpu_queue_agent = 0;
my $agent_sys_orvm_mem_agent       = 0;
my $agent_sys_orvm_pg_agent        = 0;
my $agent_sys_orvm_lan_agent       = 0;

if ( $mname =~ /oraclevm/ ) {
  foreach my $line_tmp (@lpar_row) {
    my $line = $line_tmp;
    if ( $line =~ m/^LPAR=/ ) {
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      ( my $type_machine, my $uuid ) = split( /\|/, $line );
      my $vm_label = $orvm_metadata->get_label( 'vm', $uuid );

      my $type_sam = $type;
      my $upper    = 0;
      my $legend   = "legend";
      $agent_orvm++;
      if ( $type_machine eq "oraclevm-vm" ) {
        my $test_dir_vm       = "$wrkdir/OracleVM/vm/$uuid";
        my $test_dir_vm_agent = "$wrkdir/Linux--unknown/no_hmc/$vm_label";
        if ( test_file_in_directory( "$test_dir_vm", "sys", "rrd" ) ) {
          $agent_sys_orvm_vm++;
        }
        if ( test_file_in_directory( "$test_dir_vm_agent", "cpu", "mmm" ) ) {
          $agent_sys_orvm_cpu_os_agent++;
        }
        if ( test_file_in_directory( "$test_dir_vm_agent", "queue_cpu", "mmm" ) ) {
          $agent_sys_orvm_cpu_queue_agent++;
        }
        if ( test_file_in_directory( "$test_dir_vm_agent", "mem", "mmm" ) ) {
          $agent_sys_orvm_mem_agent++;
        }
        if ( test_file_in_directory( "$test_dir_vm_agent", "pgs", "mmm" ) ) {
          $agent_sys_orvm_pg_agent++;
        }
        if ( test_file_in_directory( "$test_dir_vm_agent", "lan", "mmm" ) ) {
          $agent_sys_orvm_lan_agent++;
        }
      }
      if ( $type_machine eq "oraclevm-server" ) {
        my $test_dir_vm = "$wrkdir/OracleVM/server/$uuid";
        if ( test_file_in_directory( "$test_dir_vm", "sys", "rrd" ) ) {
          $agent_sys_orvm_server++;
        }
      }
    }
  }
}

if ( $mname =~ /oraclevm/ ) {
  print "<div  id=\"tabs\"> <ul>\n";
  if ( $agent_sys_orvm_vm > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-0\">CPU</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-1\">MEM</a></li>\n";
  }
  if ( $agent_sys_orvm_cpu_os_agent > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-2\">CPU OS</a></li>\n";
  }
  if ( $agent_sys_orvm_cpu_queue_agent > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-3\">CPU QUEUE</a></li>\n";
  }
  if ( $agent_sys_orvm_mem_agent > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-4\">Memory</a></li>\n";
  }
  if ( $agent_sys_orvm_pg_agent > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-5\">Paging 1</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-6\">Paging 2</a></li>\n";
  }
  if ( $agent_sys_orvm_lan_agent > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-7\">LAN</a></li>\n";
  }
  if ( $agent_sys_orvm_server > 0 ) {
    print "  <li class=\"tabagent\"><a href=\"#tabs-0\">CPU</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-1\">MEM</a></li>\n";
  }
  print "   </ul> \n";
}

if ( $estimator == 0 && $mname !~ /Solaris--unknown|hyperv|oraclevm/ ) {

  # reporting, check if agent is in place and print out tabs
  foreach my $line_tmp (@lpar_row) {
    my $line = $line_tmp;    # must be like that to do not modify the original script
                             # print STDERR "408 lpar-list-cgi.pl from \@lpar_row ,@lpar_row, \$line ,$line,\n";
    if ( $line =~ m/^LPAR=/ || $line =~ m/^CGROUP=/ ) {
      my $line_org = $line;
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;

      # $line =~ s/\+/ /g;
      ( my $host, my $server, my $lpar ) = split( /\|/, $line );

      my $cust_yes = 0;
      if ( $line =~ m/^CGROUP=/ ) {

        # cust group
        $lpar = $line;
        $lpar =~ s/^CGROUP=//;
        $cust_yes = 1;
      }

      if ( $lpar eq '' && $cust_yes == 0 ) {
        error( "Could not find a lpar : $line " . __FILE__ . ":" . __LINE__ );
        next;    # some problem
      }

      # print STDERR "004 $host $server $lpar \$cust_yes ,$cust_yes, : $line\n";
      my $lpar_slash = $lpar;           #must be in separate env!!
      $lpar_slash =~ s/--AS400--//g;    # this is probably eclipse compared to detail-cgi or detail-graph-cgi
      $lpar_slash =~ s/\//\&\&1/g;      # replace for "/"
      if ( $cust_yes == 0 ) {
        my $go_next = 0;
        $go_next++     if -d "$wrkdir/$server/$host/$lpar_slash";
        $go_next++     if -d "$wrkdir/$server/$host/$lpar_slash--NMON--";
        $agent_as400++ if -d "$wrkdir/$server/$host/$lpar_slash--AS400--";
        $path_as400 = "$wrkdir/$server/$host/$lpar_slash--AS400--";

        # print STDERR "451 lpar-list-cgi.pl $wrkdir/$server/$host/$lpar_slash\n";
        #$agent_as400++ if -d "$wrkdir/$server/$host/$lpar_slash";
        $count_rrm++ if -f "$wrkdir/$server/$host/$lpar_slash.rrm";
        next         if $go_next == 0;
      }
      $count_rrm++ if $cust_yes == 1;
      my $test_dir      = "$wrkdir/$server/$host/$lpar_slash";
      my $test_dir_nmon = "$wrkdir/$server/$host/$lpar_slash$NMON";

      $agent++;
      if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", "cpu" ) || test_custom( $lpar_slash, "cpu", $cust_yes ) ) ) {
        $agent_oscpu++;
      }
      $agent_oscpu_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "cpu" ) );

      if ( test_file_in_directory( "$test_dir", "mem" ) || test_custom( $lpar_slash, "mem", $cust_yes ) ) {
        $agent_mem++;
      }
      $agent_mem_n++ if ( test_file_in_directory( "$test_dir_nmon", "mem" ) );

      if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", "pgs" ) || test_custom( $lpar_slash, "pgs", $cust_yes ) ) ) {
        $agent_pgs++;
      }
      $agent_pgs_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "pgs" ) );

      if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", "ame" ) || test_custom( $lpar_slash, "ame", $cust_yes ) ) ) {
        $agent_ame++;
      }
      $agent_ame_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "ame" ) );

      if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", "san" ) || test_custom( $lpar_slash, "san", $cust_yes ) ) ) {
        $agent_san++;
      }
      $agent_san_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "san" ) );

      if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", "san2" ) || test_custom( $lpar_slash, "san2", $cust_yes ) ) ) {
        $agent_san++;
      }

      if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", "lan" ) || test_custom( $lpar_slash, "lan", $cust_yes ) ) ) {
        $agent_lan++;
      }
      $agent_lan_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "lan" ) );

      if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", "sea" ) || test_custom( $lpar_slash, "sea", $cust_yes ) ) ) {
        $agent_sea++;
      }
      $agent_sea_n++ if ( $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "sea" ) );

      if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", "san_resp" ) || test_custom( $lpar_slash, "san_resp", $cust_yes ) ) ) {
        $agent_san_resp++;
      }
      if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", "queue_cpu" ) || test_custom( $lpar_slash, "queue_cpu", $cust_yes ) ) ) {
        $agent_queue_cpu++;
      }
    }
  }
}

my $html_base = "";
if ( $new_gui == 0 ) {
  if ( $agent > 0 ) {
    $html_base = print_head( 1, $referer );
  }
  else {
    $html_base = print_head( 0, $referer );
  }
}

if ( $estimator == 0 ) {

  # print STDERR "486 lpar-list-cgi.pl \$agent ,$agent,\n";
  if ( $agent > 0 ) {
    print "<div  id=\"tabs\"> <ul>\n";
    if ( $count_rrm > 0 ) {
      print "  <li class=\"tabhmc\"><a href=\"#tabs-0\">CPU</a></li>\n";
    }
    if ( $agent_oscpu > 0 ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-1\">CPU OS</a></li>\n";
    }
    if ( $agent_queue_cpu > 0 ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-11\">CPU Queue</a></li>\n";
    }
    if ( $agent_mem > 0 ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-2\">Memory</a></li>\n";
    }
    if ( $agent_pgs > 0 ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-3\">Paging 1</a></li>\n";
      print "  <li class=\"tabagent\"><a href=\"#tabs-4\">Paging 2</a></li>\n";
    }
    if ( $agent_lan > 0 ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-5\">LAN</a></li>\n";
    }
    if ( $agent_san > 0 ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-6\">SAN</a></li>\n";
      print "  <li class=\"tabagent\"><a href=\"#tabs-7\">SAN IOPS</a></li>\n";
    }
    if ( $agent_sea > 0 ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-8\">SEA</a></li>\n";
    }
    if ( $agent_ame > 0 ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-9\">AME</a></li>\n";
    }
    if ( $agent_san_resp > 0 ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-10\">SAN RESP</a></li>\n";
    }

    my $tabagent = "tabnmon";
    print "  <li class=\"$tabagent\"><a href=\"#tabs-21\">CPU OS</a></li>\n"   if $agent_oscpu_n > 0;
    print "  <li class=\"$tabagent\"><a href=\"#tabs-22\">Memory</a></li>\n"   if $agent_mem_n > 0;
    print "  <li class=\"$tabagent\"><a href=\"#tabs-23\">Paging 1</a></li>\n" if $agent_pgs_n > 0;
    print "  <li class=\"$tabagent\"><a href=\"#tabs-24\">Paging 2</a></li>\n" if $agent_pgs_n > 0;
    print "  <li class=\"$tabagent\"><a href=\"#tabs-25\">LAN</a></li>\n"      if $agent_lan_n > 0;
    print "  <li class=\"$tabagent\"><a href=\"#tabs-26\">SAN</a></li>\n"      if $agent_san_n > 0;
    print "  <li class=\"$tabagent\"><a href=\"#tabs-27\">SAN IOPS</a></li>\n" if $agent_san_n > 0;
    print "  <li class=\"$tabagent\"><a href=\"#tabs-28\">SEA</a></li>\n"      if $agent_sea_n > 0;
    print "  <li class=\"$tabagent\"><a href=\"#tabs-29\">AME</a></li>\n"      if $agent_ame_n > 0;

    print "   </ul> \n";
    print "<div id=\"tabs-0\">\n";    ### CPU tab start
  }
  elsif ( $agent_as400 > 0 ) {
    print "<div  id=\"tabs\"> <ul>\n";
    if ( $count_rrm > 0 ) {
      print "  <li class=\"tabhmc\"><a href=\"#tabs-0\">CPU</a></li>\n";
    }
    print "  <li class=\"tabagent\"><a href=\"#tabs-1\">JOBS</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-2\">SIZE</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-3\">THREADS</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-4\">FAULTS</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-5\">PAGES</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-6\">ASP USED</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-7\">ASP FREE</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-8\">ASP DATA</a></li>\n";
    print "  <li class=\"tabagent\"><a href=\"#tabs-9\">ASP IOPS</a></li>\n";
    my $test_dir = "$path_as400/IFC";

    # print STDERR "580 lpar-list-cgi.pl $test_dir\n";
    if ( $entitle == 0 && ( test_file_in_directory( "$test_dir", ".*", "mmc" ) ) ) {
      print "  <li class=\"tabagent\"><a href=\"#tabs-10\">LAN</a></li>\n";
    }
    print "   </ul> \n";
    print "<div id=\"tabs-0\">\n";    ### CPU tab start
  }
}

print "<table align=\"center\" summary=\"Graphs\">\n";

if ($estimator) {
  use Digest::MD5 qw(md5_hex);

  print "<a href=\"http://www.lpar2rrd.com/cpu_workload_estimator.html\">How it works</a>\n";

  if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {

    # If rPerf then find our rPerfs now, as in lpar-list-rep.pl it is too late as it generates only graphs
    # and there is no chance for error loging and CPU speed input

    my @rperf_all  = "";
    my @rperf_user = "";

    # SAPs & rPerf: open cfg file and keep it in mem
    if ( !-f "$inputdir/etc/rperf_table.txt" ) {
      print "</table></div>\n";
      err_html("$inputdir/etc/rperf_table.txt doe not exist!! Cannot continue, contact the support");
    }
    if ( !-f "$inputdir/etc/rperf_user.txt" ) {
      print "</table></div>\n";
      err_html("$inputdir/etc/rperf_user.txt doe not exist!! Cannot continue, contact the support");
    }
    open( FR, "< $inputdir/etc/rperf_table.txt" ) || print "</table></div>\n" && err_html( "Can't open $inputdir/etc/rperf_table.txt : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
    @rperf_all = <FR>;
    close(FR);
    open( FR, "< $inputdir/etc/rperf_user.txt" ) || print "</table></div>\n" && err_html( "Can't open $inputdir/etc/rperf_user.txt: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
    @rperf_user = <FR>;
    close(FR);
    my $cpu_ghz_trash   = "";
    my $cores_trash     = "";
    my $rperf_cpu_cores = "";
    my $rperf           = "";

    # example how it looks here
    #new_server : 8203-E4A|520|P6+/4|4.7|39.73|18300|1
    #pool: sdmc|p710|SharedPool1|11.2825|3.0|4

    if ( $newsrv == 1 ) {

      # rperf is already provided as it is a new HW defined
      if ( !defined $new_server || $new_server eq '' ) {
        print "</table></div>\n";
        err_html("New server was selected but has not been passed, contact LPAR2RRD support");
      }
      $new_server =~ s/NEW=//;                                             # only used for CPU workload estimator
      $new_server =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      $new_server =~ s/\+/ /g;
      my $cpu_all = 0;
      ( my $trash1, my $model, $cpu_all, my $ghz, $rperf, my $rperf_st, my $rperf_smt2, my $rperf_smt4, my $rperf_smt8, my $cpw, my $fix ) = split( /\|/, $new_server );
      my $cpu = $cpu_all;
      $cpu_all =~ s/\/.*$//;
      $cpu     =~ s/.*\///;
      my $ret = isdigit($cpu);

      if ( $ret == 0 ) {

        # $cpu must be a digit
        print "</table></div>\n";
        err_html("Could not find out number of cores, contact LPAR2RRD support, data:$cpu");
      }

      if ( $yaxis =~ m/w/ ) {
        $cpw =~ s/,//;
        if ( $cpw == 0 ) {
          print "</table></div>\n";
          err_html("This model $model:$trash1 does not have defined CPW by IBM, use other one");
          error("This model $model:$trash1 does not have defined rPerf: $new_server ");    # to get all messages into the error log
        }
        $pool = "__XXX__|__XXX__" . $trash1 . " " . $model . " " . $cpu_all . "|default|" . $cpu . ":" . $cpw . "|" . $ghz . "|" . $cpu;
      }
      else {
        if ( $rperf == 0 && !isdigit($rperf_st) && !isdigit($rperf_smt2) && !isdigit($rperf_smt4) && !isdigit($rperf_smt8) ) {
          print "</table></div>\n";
          err_html("This model $model:$trash1 does not have defined rPerf by IBM, use other one");
          error("This model $model:$trash1 does not have defined rPerf: $new_server ");    # to get all messages into the error log
        }
        $pool = "__XXX__|__XXX__" . $trash1 . " " . $model . " " . $cpu_all . "|default pool|" . $cpu . ":" . $rperf . ":" . $rperf_st . ":" . $rperf_smt2 . ":" . $rperf_smt4 . ":" . $rperf_smt8 . "|" . $ghz . "|" . $cpu;
      }
    }
    else {
      if ( !defined $pool || $pool eq '' ) {
        print "</table></div>\n";
        err_html("Existing server was selected but has not been passed, contact LPAR2RRD support");
      }
      $pool =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      $pool =~ s/\+/ /g;
      $pool =~ s/POOL=//;                                            # only used for CPU workload estimator
      $pool =~ s/pool=//;                                            # only used for CPU workload estimator

      ( my $hmc_pool, my $server_pool, my $fix, my $trash2 ) = split( /\|/, $pool );

      $rperf_cpu_cores = get_rperf_all( $dstfix, $yaxis, $inputdir, $server_pool, $hmc_pool, \@rperf_user, \@rperf_all );
      if ( $rperf_cpu_cores eq '' ) {
        print "</table></div>\n";
        err_html("$hmc_pool:$server_pool - get_rperf_all returned null");
      }
      ( $rperf, $cpu_ghz_trash, $cores_trash ) = split( /\|/, $rperf_cpu_cores );
      if ( $rperf eq '' || $cpu_ghz_trash eq '' || $cores_trash eq '' ) {
        print "</table></div>\n";
        err_html("$hmc_pool:$server_pool - rperf has not been found, check realt-error.log for more");
      }
      $pool = $pool . "|" . $rperf_cpu_cores;
    }

    #`echo "srv : $new_server yaxis=$yaxis" >> /tmp/e9`;
    #`echo "pool: $pool" >> /tmp/e9`;

    # Loop per each choosen lpar/CPU pool/Memory
    my $server_old   = "";
    my $indx         = 0;
    my @lpar_row_new = "";
    foreach my $line1 (@lpar_row) {
      my $line = $line1;    # --> keep original line without change
      chomp($line);
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      $line =~ s/Report=Generate\+Report//g;
      $line =~ s/\+/ /g;
      if ( length($line) == 0 ) {
        next;
      }

      #print OUT "10 $line\n"  if $DEBUG == 2 ;
      ( my $hmc, my $managedname, my $lpar, my $fix ) = split( /\|/, $line );
      if ( $lpar eq '' ) {
        error( "Could not find a lpar : $line " . __FILE__ . ":" . __LINE__ );
        next;    # some problem
      }

      $lpar =~ s/ $//;
      $lpar =~ s/\//\&\&1/g;
      print OUT "11 $hmc -- $managedname -- $lpar\n" if $DEBUG == 2;

      #print STDERR "11 $hmc -- $managedname -- $lpar\n";

      # avoid finding rperf on already founded servers
      # tried also exclude there pool server, but it is not good idea ...

      if ( $managedname !~ m/^$server_old$/ ) {
        $rperf_cpu_cores = get_rperf_all( $srcfix, $yaxis, $inputdir, $managedname, $hmc, \@rperf_user, \@rperf_all );

        #error("$0: $rperf_cpu_cores: $hmc -- $managedname -- $lpar\n" if $DEBUG == 2 ;
        if ( $rperf_cpu_cores eq '' ) {
          print "</table></div>\n";
          err_html("$hmc:$managedname - get_rperf_all returned null");
        }
        ( $rperf, $cpu_ghz_trash, $cores_trash ) = split( /\|/, $rperf_cpu_cores );
        if ( $rperf eq '' || $cpu_ghz_trash eq '' || $cores_trash eq '' ) {
          print "</table></div>\n";
          err_html("$hmc:$managedname - rperf has not been found, check logs/error-cgi.log for more");
        }
        $server_old = $managedname;
      }
      $lpar_row_new[$indx] = $line1 . "|" . $rperf_cpu_cores;
      $indx++;
    }
    @lpar_row = @lpar_row_new;    # workaround for filtering wrong records
  }

  if ( $newsrv == 1 ) {
    if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {
      my $url     = "shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=0&sort=$sort_order&pool=$pool&@lpar_row&srcfix=$srcfix&dstfix=$dstfix";
      my $urlhash = substr( md5_hex($url), 0, 7 );
      file_write( "$tmpdir/cwe_$urlhash.tmp", $url );
      $url = compress_base64($url);
      if ( $new_gui == 0 ) {
        print "<tr><td><img src=\"/lpar2rrd-cgi/lpar-list-rep.sh?$url\" ></td>";
      }
      else {
        print "<tr><td class=\"relpos\"><img src=\"/lpar2rrd-cgi/lpar-list-rep.sh?cwehash=$urlhash\" ></td>";
      }
    }
    else {    # For CPU cores & new server
      $new_server =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      ( my $model, my $machine_short, my $cpu, my $ghz, my $rperf, my $cpw ) = split( /\|/, $new_server );
      $model =~ s/NEW=//;
      my $cpu_type = $cpu;
      $cpu_type =~ s/\/.*//;
      $cpu      =~ s/^.*\///;
      $pool = "__XXX__|__XXX__" . $model . " " . $machine_short . " " . $cpu_type . "|default pool|" . $rperf . "|" . $ghz . "|" . $cpu;

      #pool=__XXX__|__XXX__8203-E4A 520 P6|default pool|7.87|4.2|4
      my $url     = "shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=0&sort=$sort_order&pool=$pool&@lpar_row&srcfix=$srcfix&dstfix=$dstfix";
      my $urlhash = substr( md5_hex($url), 0, 7 );
      file_write( "$tmpdir/cwe_$urlhash.tmp", $url );
      $url = compress_base64($url);
      if ( $new_gui == 0 ) {
        print "<tr><td><img src=\"/lpar2rrd-cgi/lpar-list-rep.sh?$url\"></td>\n";
      }
      else {
        print "<tr><td class=\"relpos\"><img src=\"/lpar2rrd-cgi/lpar-list-rep.sh?$urlhash\"></td>\n";
      }
    }
  }
  else {
    # not new server
    my $url     = "shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=0&sort=$sort_order&pool=$pool&@lpar_row&srcfix=$srcfix&dstfix=$dstfix";
    my $urlhash = substr( md5_hex($url), 0, 7 );
    file_write( "$tmpdir/cwe_$urlhash.tmp", $url );
    $url = compress_base64($url);
    if ( $new_gui == 0 ) {
      print "<tr><td><img src=\"/lpar2rrd-cgi/lpar-list-rep.sh?$url\"></td>\n";
    }
    else {
      print "<tr><td class=\"relpos\"><img src=\"/lpar2rrd-cgi/lpar-list-rep.sh?cwehash=$urlhash\"></td>\n";
    }
  }

  # only for CPU workload estimator where need just 1 aggregated graph, nothing more
  print "</td></tr></table></div><br>\n";
  print "<ul style=\"display: none\"><li class=\"tabhmc\"></li></ul>\n";    # to add the data source icon

  if ( $new_gui == 0 ) {
    print "</BODY></HTML>\n";
  }
  close(OUT) if $DEBUG == 2;
  exit(0);
}

# print STDERR "lpar-list-cgi.pl 771 \$count_rrm $count_rrm \$lparform $lparform\n";
if ( $count_rrm > 2 && $lparform == 1 ) {

  # show aggregated only if there is more than 1 lpar!!!
  # necessary do url
  # print STDERR "lpar-list-cgi.pl 683 \@lpar_row @lpar_row\n";
  my @lpar_url = ();
  my @orig     = @lpar_row;
  my $line;
  foreach $line (@lpar_row) {
    $line =~ s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
    push @lpar_url, $line;
  }

  #@lpar_row = @lpar_url;
  #@lpar_url = @lpar_row;
  @lpar_row = @orig;
  print "<tr><td><center><h3>LPARs</h3><h4>Aggregated graph - all selected lpars in one</h4></center></td></tr>\n";
  print "<tr><td class=\"relpos\"><img class=\"lazy\" data-src=\"/lpar2rrd-cgi/lpar-list-rep.sh?shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=0&sort=$sort_order&pool=$pool&@lpar_url\" src=\"$html_base/css/images/loading.gif\"></td>\n";
  if ( $xport == 1 ) {
    print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar-list-rep.sh?shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&sort=$sort_order&pool=$pool&@lpar_url\">CSV</A></font></td>";
  }
  print "</tr>\n";

  print "<tr><td><A HREF=\"/lpar2rrd-cgi/lpar-list-rep.sh?shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=0&sort=$sort_order&pool=$pool&@lpar_url\" target=\"_blank\">Graph link</A></td></tr>\n";
}

if ( $mname !~ /Solaris--unknown|hyperv|oraclevm/ ) {
  print "<tr><td><center><h4>Individual graphs</h4></center></td></tr>\n";
}

# print STDERR "lpar-list-cgi.pl 733 # Loop per each chosen lpar/CPU pool/Memory\n";
foreach my $line_tmp (@lpar_row) {
  if ( $mname =~ /Solaris--unknown|hyperv|oraclevm/ ) {next}    # only Linux platform running here, so other platform next

  my $line = $line_tmp;

  # print STDERR "759 lpar-list-cgi.pl \$line je $line\n";
  if ( $line =~ m/^CGROUP=/ ) {
    $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $line =~ s/\+/ /g;

    # cust group
    $line =~ s/CGROUP=//;
    if ( test_custom( $line, "lpar", 1 ) ) {
      print_item( "na", "na", $line, "custom", $type, "d", $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
      if ( $xport == 1 ) {
        print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/detail-graph.sh?host=na&server=na&lpar=$line&item=customxport&time=d&type_sam=m&detail=0&upper=0&entitle=$entitle&sunix=$start_unix&eunix=$end_unix&height=$height&width=$width\">CSV</A></font></td>";
      }
      print "</tr>\n";
    }
    next;
  }

  if ( $line =~ m/^LPAR=/ ) {
    $line =~ s/LPAR=//;
    ( my $hmc, my $managedname, my $lpar ) = split( /\|/, $line );
    if ( $lpar eq '' ) {
      error( "Could not find a lpar : $line " . __FILE__ . ":" . __LINE__ );
      next;    # some problem
    }

    my $type_sam          = $type;
    my $upper             = 0;
    my $item              = "lpar";
    my $legend            = "legend";
    my $lpar_name_for_csv = $lpar;
    $lpar_name_for_csv =~ s/([^a-zA-Z0-9\+-_])/sprintf("%%%02X", ord($1))/ge;
    $lpar              =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $lpar              =~ s/\//&&1/g;                                           # general replacement for file system

    # print STDERR "791 lpar-list-cgi.pl \$hmc $hmc \$managedname $managedname \$lpar $lpar\n";
    # only if data exists
    if ( -f "$wrkdir/$managedname/$hmc/$lpar.rrm" ) {
      print_item( $hmc, $managedname, $lpar, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $legend, "notr" );

      if ( $xport == 1 ) {
        print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?hmc=$hmc&mname=$managedname&lpar=$lpar_name_for_csv&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1\">CSV</A></font></td>";
      }
      print "</tr>\n";
    }
  }
}

my $pool_once = 0;

foreach my $lpar (@pool_row) {
  if ( $lpar =~ "POOL=" ) {

    if ( $pool_once == 0 ) {
      print "<tr><td><center><h3>Servers and CPU pools</h3></center></td></tr>\n";
      $pool_once = 1;
    }
    $lpar =~ s/POOL=//;
    ( my $hmc, my $managedname, $lpar ) = split( /\|/, $lpar );

    my $type_sam = $type;
    my $upper    = 0;
    my $item     = "pool";
    ( $lpar =~ /SharedPool/ ) && ( $item = "shpool" );
    my $legend            = "legend";
    my $lpar_name_for_csv = $lpar;
    $lpar =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $lpar =~ s/\+/ /g;

    # -PH: workaround, from UI now comes total instead of pool, perhaps partly implemented pool_total, kept original functionality
    # -HD: hash workaround when partially implemented pool_total, now implemented fully - no need for workaround
    #if ( $lpar eq 'total' ) {
    #   $lpar = "pool";
    #}
    print_item( $hmc, $managedname, $lpar, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $legend, "notr" );

    if ( $xport == 1 ) {
      print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?hmc=$hmc&mname=$managedname&lpar=$lpar_name_for_csv&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1\">CSV</A></font></td>";
    }
    print "</tr>\n";
  }
}

#print "</table>\n";

foreach my $total_pool (@pool_total_row) {
  if ( $total_pool eq '' ) {
    next;
  }

  if ( $pool_once == 0 ) {
    print "<tr><td><center><h3>CPU Totals</h3></center></td></tr>\n";
    $pool_once = 1;
  }
  $total_pool =~ s/POOL=//;
  ( my $hmc, my $managedname, $total_pool ) = split( /\|/, $total_pool );

  my $type_sam          = $type;
  my $upper             = 0;
  my $item              = "pool-total";
  my $legend            = "legend";
  my $lpar_name_for_csv = $total_pool;
  $total_pool =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  $total_pool =~ s/\+/ /g;

  print_item( $hmc, $managedname, $total_pool, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $legend, "notr" );

  if ( $xport == 1 ) {
    print "<td valign=\"top\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?hmc=$hmc&mname=$managedname&lpar=$lpar_name_for_csv&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1\">CSV</A></font></td>";
  }
  print "</tr>\n";
}

print "</table>\n";    # must be after foreach lpar, foreach pool, foreach pool_total

if ( $agent > 0 ) {
  print "</div>\n";
}
elsif ( $agent_as400 > 0 ) {
  print "</div>\n";

  print "<div id=\"tabs-1\">\n";
  agent( "S0200ASPJOB", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-2\">\n";
  agent( "size", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-3\">\n";
  agent( "threads", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-4\">\n";
  agent( "faults", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-5\">\n";
  agent( "pages", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-6\">\n";
  agent( "cap_used", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-7\">\n";
  agent( "cap_free", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-8\">\n";
  agent( "data_as", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-9\">\n";
  agent( "iops_as", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "<div id=\"tabs-10\">\n";
  agent( "data_ifcb", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "<tr><td><center><h4>Packets received/sent IFCB</h4></center></td></tr>";
  agent( "paket_ifcb", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "<tr><td><center><h4>Packets Discarded IFCB</h4></center></td></tr>";
  agent( "dpaket_ifcb", $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";

  print "</div><br>\n";
  if ( $new_gui == 0 ) {
    print "</BODY></HTML>";
  }
  close(OUT) if $DEBUG == 2;

  exit(0);
}
elsif ( $agent_win > 0 ) {
  #
  # Windows agent
  #
  my $type_hyperv = "hyperv-vm";
  if ( $agent_data_win > 0 ) {
    print "<div id=\"tabs-0\">\n";
    my $item = "hyp-cpu";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-1\">\n";
    my $item = "hyp-mem";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-2\">\n";
    my $item = "hyp-disk";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-3\">\n";
    my $item = "hyp-net";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
  }
}
elsif ( $agent_win_server > 0 ) {
  #
  # Windows agent
  #
  my $type_hyperv = "hyperv-server";
  if ( $agent_data_win_server > 0 ) {
    print "<div id=\"tabs-0\">\n";
    my $item = "pool";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-1\">\n";
    my $item = "cpuqueue";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-2\">\n";
    my $item = "cpu_process";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-3\">\n";
    my $item = "memalloc";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-4\">\n";
    my $item = "hyppg1";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-5\">\n";
    my $item = "hyppg2";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-6\">\n";
    my $item = "vmnetrw";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-7\">\n";
    my $item = "hdt_data";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-8\">\n";
    my $item = "hdt_io";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-9\">\n";
    my $item = "hdt_latency";
    agent_win( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, \@lpar_row );
    print "</div>\n";
  }
}
elsif ( $agent_sol > 0 ) {
  #
  # Solaris agent
  #
  if ( $agent_cpu_sol > 0 ) {
    print "<div id=\"tabs-0\">\n";
    my $item = "solaris_ldom_cpu";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-1\">\n";
    $item = "solaris_ldom_mem";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_oscpu_sol > 0 ) {
    print "<div id=\"tabs-2\">\n";
    my $item = "oscpu";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_queue_cpu_sol > 0 ) {
    print "<div id=\"tabs-3\">\n";
    my $item = "queue_cpu";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_mem_sol > 0 ) {
    print "<div id=\"tabs-4\">\n";
    my $item = "mem";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_pgs_sol > 0 ) {
    print "<div id=\"tabs-5\">\n";
    my $item = "pg1";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-6\">\n";
    my $item = "pg2";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_lan_sol > 0 ) {
    print "<div id=\"tabs-7\">\n";
    my $item = "lan";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_san_sol > 0 ) {
    print "<div id=\"tabs-8\">\n";
    my $item = "solaris_ldom_san1";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-9\">\n";
    my $item = "solaris_ldom_san2";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_sanmon_sol > 0 ) {
    print "<div id=\"tabs-10\">\n";
    my $item = "sarmon_san";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-11\">\n";
    my $item = "sarmon_iops";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-12\">\n";
    my $item = "sarmon_latency";
    agent_sol( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
}
elsif ( $agent_orvm > 0 ) {
  #
  # OracleVM
  #
  # VM
  if ( $agent_sys_orvm_vm > 0 ) {
    print "<div id=\"tabs-0\">\n";
    my $item = "ovm_vm_cpu_core";
    agent_orvm( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-1\">\n";
    $item = "ovm_vm_mem";
    agent_orvm( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }

  # VM agent (Linux)
  if ( $agent_sys_orvm_cpu_os_agent > 0 ) {
    print "<div id=\"tabs-2\">\n";
    my $item = "oscpu";
    agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_sys_orvm_cpu_queue_agent > 0 ) {
    print "<div id=\"tabs-3\">\n";
    my $item = "queue_cpu";
    agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_sys_orvm_mem_agent > 0 ) {
    print "<div id=\"tabs-4\">\n";
    my $item = "mem";
    agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_sys_orvm_pg_agent > 0 ) {
    print "<div id=\"tabs-5\">\n";
    my $item = "pg1";
    agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-6\">\n";
    my $item = "pg2";
    agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
  if ( $agent_sys_orvm_lan_agent > 0 ) {
    print "<div id=\"tabs-7\">\n";
    my $item = "lan";
    agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }

  # Server
  if ( $agent_sys_orvm_server > 0 ) {
    print "<div id=\"tabs-0\">\n";
    my $item = "ovm_server_cpu_core";
    agent_orvm( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
    print "<div id=\"tabs-1\">\n";
    $item = "ovm_server_mem_server";
    agent_orvm( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
    print "</div>\n";
  }
}
else {
  # Exit, no agent in place
  if ( $new_gui == 0 ) {
    print "</BODY></HTML>";
  }
  exit(0);
}

#
# OS CPU
#

if ( $agent_oscpu > 0 ) {
  print "<div id=\"tabs-1\">\n";
  my $item = "oscpu";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_oscpu_n > 0 ) {
  print "<div id=\"tabs-21\">\n";
  my $item = "nmon_oscpu";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS mem
#

if ( $agent_mem > 0 ) {
  print "<div id=\"tabs-2\">\n";
  my $item = "mem";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_mem_n > 0 ) {
  print "<div id=\"tabs-22\">\n";
  my $item = "nmon_mem";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS paging
#

if ( $agent_pgs > 0 ) {
  print "<div id=\"tabs-3\">\n";
  my $item = "pg1";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
  print "<div id=\"tabs-4\">\n";
  my $item = "pg2";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_pgs_n > 0 ) {
  print "<div id=\"tabs-23\">\n";
  my $item = "nmon_pg1";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
  print "<div id=\"tabs-24\">\n";
  my $item = "nmon_pg2";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS Ethernet
#

if ( $agent_lan > 0 ) {
  print "<div id=\"tabs-5\">\n";
  my $item = "lan";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_lan_n > 0 ) {
  print "<div id=\"tabs-25\">\n";
  my $item = "nmon_lan";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS FC
#

if ( $agent_san > 0 ) {
  print "<div id=\"tabs-6\">\n";
  my $item = "san1";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
  print "<div id=\"tabs-7\">\n";
  my $item = "san2";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_san_n > 0 ) {
  print "<div id=\"tabs-26\">\n";
  my $item = "nmon_san1";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
  print "<div id=\"tabs-27\">\n";
  my $item = "nmon_san2";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS SEA
#

if ( $agent_sea > 0 ) {
  print "<div id=\"tabs-8\">\n";
  my $item = "sea";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_sea_n > 0 ) {
  print "<div id=\"tabs-28\">\n";
  my $item = "nmon_sea";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS AME
#

if ( $agent_ame > 0 ) {
  print "<div id=\"tabs-9\">\n";
  my $item = "ame";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}
if ( $agent_ame_n > 0 ) {
  print "<div id=\"tabs-29\">\n";
  my $item = "nmon_ame";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# OS SAN-RESP
#

if ( $agent_san_resp > 0 ) {
  print "<div id=\"tabs-10\">\n";
  my $item = "san_resp";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

#
# CPU QUEUE
#

if ( $agent_queue_cpu > 0 ) {
  print "<div id=\"tabs-11\">\n";
  my $item = "queue_cpu";
  agent( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, \@lpar_row );
  print "</div>\n";
}

print "</div><br>\n";
if ( $new_gui == 0 ) {
  print "</BODY></HTML>";
}
close(OUT) if $DEBUG == 2;

exit(0);

sub not_implemented {
  print "<br><br><center><strong>rPerf scaling is not implemented yet</strong>\n";
  if ( $new_gui == 0 ) {
    print "</body></html>";
  }

  return 0;
}

sub err_html {
  my $text = shift;

  print "<strong> ERROR: $text</strong>\n";
  if ( $new_gui == 0 ) {
    print "</body></html>";
  }
  exit(1);
}

sub not_available {
  print "<br><br><strong>CPU Workload Estimator based on <a href=\"http://www-03.ibm.com/systems/power/hardware/notices/rperf.html\" target=\"_blank\">rPerf</a> or <a href=\"http://www-03.ibm.com/systems/power/hardware/notices/cpw.html\" target=\"_blank\">CPW</a> benchmarks is not supported in free LPAR2RRD distribution.\n";
  print "<br>You might either buy <a href=\"http://www.lpar2rrd.com/support.htm\" target=\"_blank\">support</a> or use estimations based on CPU cores (go back and choice \"CPU core\" for \"Y-axis\").\n";
  print "<br><br>Note that comparing of CPU load based on CPU cores for different IBM Power server models is only informative.<br></strong>\n";
  if ( $new_gui == 0 ) {
    print "</body></html>";
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
  my $text  = shift;

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
  return 0;
}

sub print_head {
  my $agent   = shift;
  my $referer = shift;

  my $html_base = html_base($referer);

  # print HTML header
  print "<HTML><HEAD>
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
<link rel=\"stylesheet\" href=\"$html_base/jquery/jquery-ui-1.10.3.custom.min.css\">
<link rel=\"stylesheet\" href=\"$html_base/jquery/magnific-popup.css\">

<script src=\"$html_base/jquery/jquery-1.11.1.min.js\"></script>
<script src=\"$html_base/jquery/jquery-ui-1.10.4.custom.min.js\"></script>
<script src=\"$html_base/jquery/jquery.lazy.min.js\"></script>
<script src='$html_base/jquery/magnific-popup.min.js'></script>
<script>
\$( document ).ready(function() {
        \$( \"#tabs\" ).tabs({
                activate: function() {
                        \$(\"img.lazy\").lazy({
                                bind: \"event\",
                                effect: \"fadeIn\",
                                effectTime: 1000
                                });
                }
        });
        \$( \"img.lazy\" ).lazy({
                        effect: \"fadeIn\",
                        effectTime: 1000
                        }
        );

        \$( 'a.detail' ).magnificPopup({
                type: 'image',
                closeOnContentClick: true,
                closeBtnInside: false,
                fixedContentPos: true,
                mainClass: 'mfp-no-margins mfp-with-zoom', // class to remove default margin from left and right side
                image: {
                        verticalFit: true
                },
                zoom: {
                        enabled: true,
                        duration: 300 // don't foget to change the duration also in CSS
                }
        });
});


</script>

</HEAD>
<BODY BGCOLOR=\"#D3D2D2\" TEXT=\"#000000\" LINK=\"#0000FF\" VLINK=\"#0000FF\" ALINK=\"#FF0000\">\n";

  return $html_base;
}

sub html_base {

  # Print link to full lpar cfg (must find out at first html_base
  # find out HTML_BASE
  # renove from the path last 3 things
  # http://nim.praha.cz.ibm.com/lpar2rrd/hmc1/PWR6B-9117-MMA-SN103B5C0%20ttt/pool/top.html
  # --> http://nim.praha.cz.ibm.com/lpar2rrd
  # my $refer = $ENV{HTTP_REFERER}; --> no, no, here is cgi-bin referer already
  my $referer   = shift;
  my $html_base = "";
  my $base      = 0;

  if ( $referer !~ m/^na$/ ) {    # when is http refer pasing then it is enough ... via lpar search
    my @full_path = split( /\//, $referer );
    my $k         = 0;
    foreach my $path (@full_path) {
      $k++;
    }
    $k--;
    $k--;
    $k--;
    my $j = 0;
    foreach my $path (@full_path) {
      if ( $j < $k ) {
        if ( $j == 0 ) {
          $html_base .= $path;
        }
        else {
          $html_base .= "/" . $path;
        }
        $j++;
      }
    }
  }
  else {
    $html_base = $referer;
  }
  return $html_base;
}

sub agent_win {
  my ( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, $lpar_list_tmp ) = @_;

  #print STDERR "line1562- $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, $lpar_list_tmp\n";
  my @lpar_list = @{$lpar_list_tmp};
  my $type_sam  = "x";                 # whatever, it is not significant for OS agent graphs
  print "<table align=\"center\" summary=\"$item\">\n";

  foreach my $line_tmp (@lpar_list) {
    my $line = $line_tmp;
    if ( $line =~ m/^LPAR=/ ) {
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      $line =~ s/\+/ /g;
      if ( $type_hyperv =~ /hyperv-vm/ ) {
        ( my $host, my $vm_uuid ) = split( /\|/, $line );
        my ($grep_line) = grep ( /$vm_uuid/, @menu );
        ( undef, my $domain, my $server_windows, undef, my $vm_name ) = split( /\:/, $grep_line );
        my $item_all = $item;
        my $vm_url   = $vm_uuid;
        my $test_dir = "$wrkdir/windows/domain_$domain/hyperv_VMs";
        if ( -d "$test_dir" ) {
          if ( $item =~ m/^hyp-cpu|^hyp-mem|^hyp-disk|^hyp-net/ && ( test_file_in_directory( "$test_dir", "$vm_uuid", "rrm" ) ) ) {
            my $host_url     = "no_hmc";
            my $server_url   = "windows/domain_$domain";
            my $vm_url_e     = urlencode($vm_url);
            my $server_url_e = urlencode($server_url);
            print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$domain&mname=windows&lpar=$vm_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
            print_item( $host_url, $server_url, $vm_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, "legend" );
            next;
          }
        }
      }
      if ( $type_hyperv =~ /hyperv-server/ ) {
        ( my $host, my $server_name ) = split( /\|/, $line );
        my ($grep_line) = grep ( /^S:.*:$server_name:Totals:/, @menu );
        ( undef, my $domain ) = split( /\:/, $grep_line );
        my $vm_url             = "pool";
        my $server_name_to_csv = "$server_name";
        my $test_dir           = "$wrkdir/windows/domain_$domain/$server_name";
        if ( $item =~ m/pool|memalloc|hyppg1|hyppg2|vmnetrw|hdt_data|hdt_io|hdt_latency/ && ( test_file_in_directory( "$test_dir", "pool", "rrm" ) ) ) {
          my $host_url     = "$server_name";
          my $server_url   = "windows/domain_$domain";
          my $vm_url_e     = urlencode($vm_url);
          my $server_url_e = urlencode($server_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$domain&mname=windows&lpar=$server_name_to_csv&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          my $legend_form = "legend";
          $legend_form = "nolegend" if $item eq "hdt_latency";
          print_item( $host_url, $server_url, $vm_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, $legend_form );
          next;
        }
        if ( $item =~ m/cpuqueue|cpu_process/ && ( test_file_in_directory( "$test_dir", "CPUqueue", "rrm" ) ) ) {
          my $host_url     = "$server_name";
          my $server_url   = "windows/domain_$domain";
          my $vm_url_e     = urlencode($vm_url);
          my $server_url_e = urlencode($server_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$domain&mname=windows&lpar=$server_name_to_csv&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $vm_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $type_hyperv, "legend" );
          next;
        }
      }
    }
  }

  print "</table>\n";
  return 1;
}

sub agent_sol {
  my ( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $lpar_list_tmp ) = @_;

  #print STDERR "line1562- $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $lpar_list_tmp\n";
  my @lpar_list = @{$lpar_list_tmp};
  my $type_sam  = "x";                 # whatever, it is not significant for OS agent graphs
  print "<table align=\"center\" summary=\"$item\">\n";

  foreach my $line_tmp (@lpar_list) {
    my $line = $line_tmp;
    if ( $line =~ m/^LPAR=/ ) {
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      $line =~ s/\+/ /g;
      my ( $host, $server, $lpar ) = "";
      ( $host, $server, $lpar ) = split( /\|/, $line );
      if ( $server =~ /:/ ) {
        ($server) = split( /\:/, $server );
      }
      if ( $lpar eq "" ) {
        $lpar = $server;
      }

      # print STDERR "1120 $line: $lpar : cust_yes == $cust_yes : entitle = $entitle : item = $item \n";
      #print STDERR "1578 line: $line\n";
      my $host_url   = $host;
      my $server_url = $server;
      my $lpar_slash = $lpar;
      $lpar_slash =~ s/\//\&\&1/g;    # replace for "/"
      my $item_all     = $item;
      my $lpar_url     = $lpar;
      my $server_dom   = "$server:$lpar";
      my $test_dir     = "$wrkdir/Solaris--unknown/no_hmc/$server_dom";
      my $test_dir_dom = "$wrkdir/Solaris/$server_dom";

      if ( -d "$test_dir" or "$test_dir_dom" ) {
        if ( $item =~ m/^solaris_ldom_cpu$/ && ( test_file_in_directory( "$test_dir_dom", "$lpar\_ldom" ) ) ) {
          my $lpar_url   = "$server:$lpar";
          my $host_url   = "0";
          my $server_url = "Solaris--unknown";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );

          #print_item( $hmc, $managedname, $lpar, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $legend, "notr" ); ### csv zarovnani
          next;
        }
        if ( $item =~ m/^solaris_ldom_mem$/ && ( test_file_in_directory( "$test_dir_dom", "$lpar\_ldom" ) ) ) {
          my $lpar_url   = "$server:$lpar";
          my $host_url   = "0";
          my $server_url = "Solaris--unknown";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^oscpu$/ && ( test_file_in_directory( "$test_dir", "cpu" ) ) ) {
          my $lpar_url   = "$server:$lpar";
          my $host_url   = "no_hmc";
          my $server_url = "Solaris--unknown";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^queue_cpu$/ && ( test_file_in_directory( "$test_dir", "queue_cpu" ) ) ) {
          my $lpar_url   = "$server:$lpar";
          my $host_url   = "no_hmc";
          my $server_url = "Solaris--unknown";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^mem$/ && ( test_file_in_directory( "$test_dir", "mem" ) ) ) {
          my $lpar_url   = "$server:$lpar";
          my $host_url   = "no_hmc";
          my $server_url = "Solaris--unknown";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^pg/ && ( test_file_in_directory( "$test_dir", "pgs" ) ) ) {
          my $lpar_url   = "$server:$lpar";
          my $host_url   = "no_hmc";
          my $server_url = "Solaris--unknown";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^lan/ && ( test_file_in_directory( "$test_dir", "lan" ) ) ) {
          my $lpar_url   = "$server:$lpar";
          my $host_url   = "no_hmc";
          my $server_url = "Solaris--unknown";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
          next;
        }
        if ( $item =~ m/^solaris_ldom_san[1-2]/ && ( test_file_in_directory( "$test_dir_dom", "san" ) ) ) {
          my $lpar_url   = "$server:$lpar";
          my $server_url = "Solaris--unknown";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
          next;
        }
        if ( $item =~ m/^sarmon/ && ( test_file_in_directory( "$test_dir", "total-san" ) ) ) {
          my $lpar_url   = "$server:$lpar";
          my $server_url = "Solaris--unknown";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
      }
    }
  }

  print "</table>\n";
  return 1;
}

sub agent_orvm {
  my ( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $lpar_list_tmp ) = @_;

  my @lpar_list = @{$lpar_list_tmp};
  my $type_sam  = "x";                 # whatever, it is not significant for OS agent graphs
  print "<table align=\"center\" summary=\"$item\">\n";

  foreach my $line_tmp (@lpar_list) {
    my $line = $line_tmp;
    if ( $line =~ m/^LPAR=/ ) {
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      $line =~ s/\+/ /g;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      ( my $type_machine, my $uuid ) = split( /\|/, $line );
      my $vm_label        = $orvm_metadata->get_label( 'vm',     $uuid );
      my $server_label    = $orvm_metadata->get_label( 'server', $uuid );
      my $test_dir_vm     = "$wrkdir/OracleVM/vm/$uuid";
      my $test_dir_server = "$wrkdir/OracleVM/server/$uuid";

      # VM
      if ( -d "$test_dir_vm" ) {
        if ( $item =~ m/^ovm_vm_cpu_core$/ && ( test_file_in_directory( "$test_dir_vm", "sys", "rrd" ) ) ) {
          my $lpar_url   = "$uuid";
          my $host_url   = "OracleVM";
          my $server_url = "nope";
          my $lpar_url_e = urlencode($lpar_url);

          # CSV
          #print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^ovm_vm_mem$/ && ( test_file_in_directory( "$test_dir_vm", "sys", "rrd" ) ) ) {
          my $lpar_url   = "$uuid";
          my $host_url   = "OracleVM";
          my $server_url = "nope";
          my $lpar_url_e = urlencode($lpar_url);

          # CSV
          #print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
      }

      # Server
      if ( -d "$test_dir_server" ) {

        # http://10.22.11.105/lpar2rrd-cgi/detail-graph.sh?host=OracleVM&server=nope&lpar=9303b6f8fcfe438a8ab398cfff840ff3&item=ovm_server_cpu_core&time=d&type_sam=m&detail=1&entitle=0&none=none
        if ( $item =~ m/^ovm_server_cpu_core$/ && ( test_file_in_directory( "$test_dir_server", "sys", "rrd" ) ) ) {
          my $lpar_url   = "$uuid";
          my $host_url   = "OracleVM";
          my $server_url = "nope";
          my $lpar_url_e = urlencode($lpar_url);

          # CSV
          #print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^ovm_server_mem_server$/ && ( test_file_in_directory( "$test_dir_server", "sys", "rrd" ) ) ) {
          my $lpar_url   = "$uuid";
          my $host_url   = "OracleVM";
          my $server_url = "nope";
          my $lpar_url_e = urlencode($lpar_url);

          # CSV
          #print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=no_hmc&mname=Solaris--unknown&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
      }
    }
  }

  print "</table>\n";
  return 1;
}

sub agent {
  my ( $item, $type, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $lpar_list_tmp ) = @_;
  my @lpar_list = @{$lpar_list_tmp};
  my $type_sam  = "x";                 # whatever, it is not significant for OS agent graphs
  print "<table align=\"center\" summary=\"$item\">\n";

  foreach my $line_tmp (@lpar_list) {
    my $line = $line_tmp;
    if ( $line =~ m/^LPAR=/ || $line =~ m/^CGROUP=/ ) {
      $line =~ s/LPAR=//;
      $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
      $line =~ s/\+/ /g;
      ( my $host, my $server, my $lpar ) = split( /\|/, $line );
      my $cust_yes = 0;

      if ( $line =~ m/^CGROUP=/ ) {

        # cust group
        $lpar = $line;
        $lpar =~ s/^CGROUP=//;
        $server   = "na";
        $host     = "na";
        $cust_yes = 1;
      }
      if ( $line =~ m/^oraclevm-vm/ ) {
        ( my $type_machine, my $uuid ) = split( /\|/, $line );
        $lpar   = $orvm_metadata->get_label( 'vm', $uuid );
        $server = "Linux--unknown";
        $host   = "no_hmc";
      }

      if ( $lpar eq '' && $cust_yes == 0 ) {
        error( "Could not find a lpar : $line " . __FILE__ . ":" . __LINE__ );
        next;    # some problem
      }

      # print STDERR "1120 $line: $lpar : cust_yes == $cust_yes : entitle = $entitle : item = $item \n";
      my $host_url   = $host;
      my $server_url = $server;
      my $lpar_slash = $lpar;
      $lpar_slash =~ s/\//\&\&1/g;    # replace for "/"
      my $item_all = $item;
      my $lpar_url = $lpar;

      # if ( ! -d "$wrkdir/$server/$host/$lpar_slash" && -d "$wrkdir/$server/$host/$lpar_slash--AS400--" ) {
      # OS agent data does not exist, use AS400 instead
      # $lpar_url .= "--AS400--";
      # }

      # DO NOT DO IT HERE!! IT DOES NOT WORK THEN (both 2 lines)
      #$lpar_url =~ s/\//\&\&1/g; # replace for "/"
      #$lpar_url =~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
      #print STDERR "005 $lpar: $wrkdir/$server/$host/$lpar_slash.mmm\n";
      #print STDERR "004 $host $server $lpar : $line : $wrkdir/$server/$host/$lpar_slash.mmm\n";

      if ( -d "$wrkdir/$server/$host/$lpar_slash--AS400--" ) {    #exclude as400 agent data from hist. rep., HD, 24.06.2021

        #if ( -d "$wrkdir/$server/$host/$lpar_slash" || -d "$wrkdir/$server/$host/$lpar_slash--AS400--" ) {
        my $legend = "nolegend";
        if ( $item eq "S0200ASPJOB" ) { $legend = "legend"; }

        #print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
        #print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $legend );
        next;
      }
      my $test_dir      = "$wrkdir/$server/$host/$lpar_slash";
      my $test_dir_nmon = "$wrkdir/$server/$host/$lpar_slash--NMON--";

      if ( -d "$test_dir" || $cust_yes == 1 || -d "$test_dir_nmon" ) {
        if ( $item =~ m/^oscpu$/ && $entitle == 0 && ( test_file_in_directory( "$test_dir", "cpu" ) || test_custom( $lpar_slash, $item, $cust_yes ) ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^nmon_oscpu$/ && $entitle == 0 ) {
          if ( test_file_in_directory( "$test_dir_nmon", "cpu" ) ) {
            my $lpar_url_e = urlencode($lpar_url);
            print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
            print_item( $host_url, $server_url, "$lpar_url--NMON--", "oscpu", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          }
          next;
        }
        if ( $item =~ m/^mem$/ && ( test_file_in_directory( "$test_dir", "mem" ) || test_custom( $lpar_slash, "mem", $cust_yes ) ) ) {
          my $cust_legend = "legend";
          if ($cust_yes) { $item_all = "customos$item"; $cust_legend = "nolegend"; }

          #print STDERR "1362 lpar-list-cgi.pl \$item $item \$item_all $item_all \$test_dir $test_dir \$lpar_slash $lpar_slash \$cust_yes $cust_yes\n";
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if !$cust_yes;
          print_item( $host_url, $server_url, $lpar_url, $item_all, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, $cust_legend );
          next;
        }
        if ( $item =~ m/^nmon_mem$/ && test_file_in_directory( "$test_dir_nmon", "mem" ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, "$lpar_url$NMON", "mem", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^pg/ && $entitle == 0 && ( test_file_in_directory( "$test_dir", "pgs" ) || test_custom( $lpar_slash, $item, $cust_yes ) ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^nmon_pg/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "pgs" ) ) {
          my $itm = $item;
          $itm =~ s/nmon_//;
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, "$lpar_url$NMON", $itm, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^lan$/ && $entitle == 0 && ( test_file_in_directory( "$test_dir", "lan" ) || test_custom( $lpar_slash, $item, $cust_yes ) ) ) {
          if ($cust_yes) { $item_all = "customos$item"; }
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if !$cust_yes;
          print_item( $host_url, $server_url, $lpar_url, $item_all, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
          next;
        }
        if ( $item =~ m/^nmon_lan$/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "lan" ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, "$lpar_url$NMON", "lan", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
          next;
        }
        if ( $item =~ m/^san[1-2]/ && $entitle == 0 && ( test_file_in_directory( "$test_dir", "san" ) || test_custom( $lpar_slash, $item, $cust_yes ) ) ) {
          if ($cust_yes) { $item_all = "customos$item"; }
          my $lpar_url_e = urlencode($lpar_url);

          # print STDERR "1409line\n";
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>" if !$cust_yes;
          print_item( $host_url, $server_url, $lpar_url, $item_all, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
          next;
        }
        if ( $item =~ m/^nmon_san/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "san" ) ) {
          my $itm = $item;
          $itm =~ s/nmon_//;
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, "$lpar_url$NMON", $itm, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
          next;
        }
        if ( $item =~ m/^sea$/ && $entitle == 0 && ( test_file_in_directory( "$test_dir", "sea" ) || test_custom( $lpar_slash, $item, $cust_yes ) ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
          next;
        }
        if ( $item =~ m/^nmon_sea$/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "sea" ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, "$lpar_url$NMON", "sea", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
          next;
        }
        if ( $item =~ m/^ame$/ && $entitle == 0 && ( test_file_in_directory( "$test_dir", "ame" ) || test_custom( $lpar_slash, $item, $cust_yes ) ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^nmon_ame$/ && $entitle == 0 && test_file_in_directory( "$test_dir_nmon", "ame" ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, "$lpar_url$NMON", "ame", $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
        if ( $item =~ m/^san_resp/ ) {

          # print STDERR "1170 $item $entitle".test_file_in_directory( "$wrkdir/$server/$host/$lpar_slash","san_resp" ).test_custom ($lpar_slash,$item,$cust_yes)."\n";
        }
        if ( $item =~ m/^san_resp/ && $entitle == 0 && ( test_file_in_directory( "$test_dir", "san_resp" ) || test_custom( $lpar_slash, $item, $cust_yes ) ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "nolegend" );
          next;
        }
        if ( $item =~ m/^queue_cpu$/ && $entitle == 0 && ( test_file_in_directory( "$test_dir", "queue_cpu" ) || test_custom( $lpar_slash, $item, $cust_yes ) ) ) {
          my $lpar_url_e = urlencode($lpar_url);
          print "<td valign=\"top\" align=\"right\"><font size=-1><A class=\"csvfloat\" HREF=\"/lpar2rrd-cgi/lpar2rrd-rep.sh?host=$host_url&mname=$server_url&lpar=$lpar_url_e&shour=$shour&smon=$smon&sday=$sday&syear=$syear&ehour=$ehour&emon=$emon&eday=$eday&eyear=$eyear&type=$type&height=$height&width=$width&yaxis=$yaxis&xport=1&item=$item\">CSV</A></font></td>";
          print_item( $host_url, $server_url, $lpar_url, $item, $type, $type_sam, $entitle, $detail_yes, $start_unix, $end_unix, $html_base, "legend" );
          next;
        }
      }
    }
  }

  print "</table>\n";
  return 1;
}

# not use anymore
#sub type_sam
#{
#  my $host = shift;
#  my $server = shift;
#  my $lpar = shift;
#  my $type = shift;
#
#  my $lpar_slash = $lpar;
#  $lpar_slash =~ s/\//\&\&1/g; # replace for "/"
#  if ( $type =~ m/d/ ) {
#    if ( -f "$wrkdir/$server/$host/$lpar_slash.rrd" ) {
#      return "d";
#    }
#    return "m";
#  }
#
#  if ( -f "$wrkdir/$server/$host/$lpar_slash.rrm" ) {
#    return "m";
#  }
#
#  if ( -f "$wrkdir/$server/$host/$lpar_slash.rrh" ) {
#    return "h";
#  }
#
#  return "m";
#}

# print a link with detail
sub print_item {
  my ( $host_url, $server_url, $lpar_url, $item, $time_graph, $type_sam, $entitle, $detail, $start_unix, $end_unix, $html_base, $legend, $notr ) = @_;

  #print " $host_url, $server_url, $lpar_url, $item, $time_graph, $type_sam, $entitle, $detail, $start_unix, $end_unix, $html_base, $legend, $notr \n";
  #HD, tried to eliminate as400 from agent data, it can be done easily other way, find "exclude as400"
  #my $IBMi_lpar = "$basedir/data/$server_url/$host_url/$lpar_url";
  #$IBMi_lpar = urldecode($IBMi_lpar);
  #$IBMi_lpar = "$IBMi_lpar--AS400--";
  #exclude lan, mem, oscpu...graphs, when the LPAR is AS400, IBMi
  #if (-e $IBMi_lpar && ($item eq "lan" || $item eq "mem" || $item eq "sea" || $item eq "oscpu" || $item eq "pg1" || $item eq "pg2" ||  $item eq "san1" ||   $item eq "san2" ||  $item eq "san_resp" || $item eq "nmon_oscpu" || $item eq "nmon_mem" || $item eq "nmon_pg1" || $item eq "nmon_pg2" || $item eq "nmon_lan" || $item eq "nmon_san1" || $item eq "nmon_san2")){
  #return 0;
  #}

  my $upper        = 0;    # same limit for all 4 graphs, not used in hist graphs
  my $legend_class = "";
  if ( $legend =~ m/nolegend/ ) {
    $legend_class = "nolegend";
  }
  my $detail_graph = "detail-graph";

  $lpar_url   =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
  $host_url   =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
  $server_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;

  my $table_row_end = "</tr>\n";
  if ( $item =~ m/^custom$/ || ( defined $notr && $notr eq "notr" ) ) {

    # do not finish the table row due to CSV
    $table_row_end = "";
  }

  # $lpar_url =~ s/\//&&1/g;
  # print STDERR "lpar-list-cgi.pl 1194 $lpar_url,$item\n";
  if ( $detail > 0 ) {

    #print "line2136-$host_url,$server_url,$lpar_url,$item,$time_graph\n";
    print "<tr>
           <td class=\"relpospar\">
            <div class=\"relpos\">
              <div>
                <div class=\"g_title\">
                  <div class=\"popdetail\"></div>
                  <div class=\"g_text\" data-server=\"$server_url\"data-lpar=\"$lpar_url\_$host_url\" data-item=\"$item\" data-time=\"$time_graph\"><span class='tt_span'></span></div>
                </div>
                  <a class=\"detail\" href=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=1&upper=$upper&entitle=$entitle&sunix=$start_unix&eunix=$end_unix&height=$height_detail&width=$width_detail\">
                     <div title=\"Click to show detail\"><img class=\"$legend_class lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=$detail_9&upper=$upper&entitle=$entitle&sunix=$start_unix&eunix=$end_unix&height=$height&width=$width\" src=\"css/images/sloading.gif\" >
                       <div class=\"zoom\" title=\"Click and drag to select range\"></div>
                     </div>
                  </a>
              </div>
              <div class=\"legend\"></div>
            <div>
           </td>
           $table_row_end\n";
  }
  else {
    print "<tr><td class=\"relpospar\">
           <div class=\"relpos\">
             <div>
               <img class=\"lazy\" border=\"0\" data-src=\"/lpar2rrd-cgi/$detail_graph.sh?host=$host_url&server=$server_url&lpar=$lpar_url&item=$item&time=$time_graph&type_sam=$type_sam&detail=0&upper=$upper&entitle=$entitle&sunix=$start_unix&eunix=$end_unix&height=$height&width=$width\"src=\"css/images/sloading.gif\" >
                 <div class=\"zoom\" title=\"Click and drag to select range\"></div>
             </div>
           </div>
           </td>
           $table_row_end\n";
  }
  return 1;
}

sub test_file_in_directory {

  # same sub in detail-cgi.pl
  # Use a regular expression to find files
  #    beginning by $fpn
  #    ending by .mmm or ending is 3rd param - if used
  #    returns 0 (zero) or first filename found i.e. non zero
  #    special care for san- sea-

  my $dir    = shift;
  my $fpn    = shift;
  my $ending = shift;

  $ending = "mmm" if !defined $ending;

  # searching OS agent file
  my $found = 0;
  if ( !-d $dir ) { return $found; }
  opendir( DIR, $dir ) || error( "Error in opening dir $dir $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  while ( my $file = readdir(DIR) ) {
    if ( $file =~ m/^$fpn.*\.$ending$/ ) {
      $found = "$dir/$file";
      last;
    }
  }
  closedir(DIR);
  return $found;
}

sub test_custom {
  my $cgroup   = shift;
  my $type     = shift;
  my $cust_yes = shift;

  #`echo "090 $cgroup : $type : $cust_yes : " >> /tmp/xx4`;
  if ( $cust_yes == 0 || $type =~ m/cpu/ || $type =~ m/^sea$/ || $type =~ m/^ame$/ || $type =~ m/^pgs$/ || $type =~ m/^san_resp$/ ) {

    # custom group does not implement all OS metrics
    return 0;
  }

  if ( $type =~ m/lpar/ ) {
    $type = "";
  }
  else {
    $type .= "-os-";
  }

  #`echo "091 $tmpdir/custom-group-$type$cgroup-d.cmd : " >> /tmp/xx4`;

  # tmp/custom-group-san2-os-AIX group-w.cmd
  # tmp/custom-group-mem-AIX group-w.cmd
  # tmp/custom-group-AIX group-y.cmd

  #print STDERR "file name $tmpdir/custom-group-$type$cgroup-d.cmd\n";
  if ( -f "$tmpdir/custom-group-$type$cgroup-d.cmd" ) {
    return 1;
  }

  return 0;
}

# compress the URL line (then base64) to make it smaller
# Apache has for HTTP GET length hardcoded limitation 8kB
# This make it smaller abou 10x what allows to pass about 1000 lpars in the URL!
# It uses external "gzip" on purpose to do not require any additional Perl module
# as it is not used very frequently then it should not be a problem ...
# usage only for CPU Workload Estimator

sub compress_base64 {
  my $string        = shift;
  my $tmp_file      = "/var/tmp/lpar2rrd_cwe.$$";
  my $compress_head = "AAAAA";

  `echo "$string"| gzip -c9 > $tmp_file`;
  open( FTR, "< $tmp_file" ) || err_html( "Can't open $tmp_file: $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  binmode(FTR);
  read( FTR, $string, 102400 );    #read 100kB block just to be sure, it is big big enough ...
  close(FTR);

  my $encoded = encode_base64( $string, "" );
  unlink($tmp_file);

  #`echo "$encoded" > /tmp/xx8`;

  return $compress_head . $encoded;
}

sub urlencode {
  my $s = shift;
  $s =~ s/([^a-zA-Z0-9!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;
  return $s;
}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  $s =~ s/\+/ /g;
  return $s;
}

sub file_write {
  my $file = shift;
  open my $IO, ">", $file or die "Cannot open $file for output: $!\n";
  print $IO @_;
  close $IO;
}
