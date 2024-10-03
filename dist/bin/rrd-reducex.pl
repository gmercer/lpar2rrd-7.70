
use strict;

# use warnings;
use lib "/opt/freeware/lib/perl/5.8.0";
use RRDp;
use Date::Parse;
use File::Copy;
use File::Compare;

#       my $basedir = "/home/lpar2rrd/lpar2rrd";
#          my $basedir = "/cps/pavel";
my $version = "$ENV{version}";
my $rrdtool = $ENV{RRDTOOL};

#         my $rrdtool = "/usr/bin/rrdtool";
my $DEBUG = $ENV{DEBUG};
$DEBUG = 3;
my $pic_col = $ENV{PICTURE_COLOR};
my $STEP    = $ENV{SAMPLE_RATE};
my $basedir = $ENV{INPUTDIR};

#        my $tmpdir = "$basedir/tmp";
my $tmpdir = "$basedir";

#if (defined $ENV{TMPDIR}) {
#  $tmpdir = $ENV{TMPDIR};
#}

my $wrkdir = "$basedir/data";

# flush after every write
$| = 1;

#example of $data here incl item names for docum purpose ! data is one line !
# 8233-E8B*5383FP:BSRV21LPAR5-pavel:5:1392202714:Wed Feb 12 11:58:34 2014:::::
# mem:::3932160:3804576:127584:1267688:2369200:1435376:
# pgs:::0:0:4096:1:::
# lan:en2:172.31.241.171:1418275448:444418173:::::
# lan:en4:172.31.216.135:22069646900:1249033690:::::
# san:fcs0:0xC050760329FB00C0:24671446454:16462307328:798417:1908861:::
# san:fcs1:0xC050760329FB00C2:678475916:1048829952:22837:13854::

# [server|serial]:lpar:lpar_id:time_stamp_unix:time_stamp_text:  #mandatory
#      future_usage1:future_usage2:future_usage3:future_usage4:  #mandatory
# other non-mandatory items depends on machine HW and SW
# :mem:::$size:$inuse:$free:$pin:$in_use_work:$in_use_clnt
# :pgs:::$page_in:$page_out:$paging_space:$pg_percent::
# :lan:$en:$inet:$transb:$recb::::
# :san:$line:$wwn:$inpb:$outb:$inprq:$outrq::
# :ame:::$comem:$coratio:$codefic:::
# :cpu:::$entitled:$cpu_sy:$cpu_us:$cpu_wa::
# :sea:$back_en:$en:$transb:$recb::::

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

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

sub rrd_error {
  my $err_text = shift;
  my $rrd_file = shift;
  my $tmpdir   = "$basedir/tmp";
  if ( defined $ENV{TMPDIR} ) {
    $tmpdir = $ENV{TMPDIR};
  }

  chomp($err_text);

  if ( $err_text =~ m/ERROR:/ && !$rrd_file eq '' ) {

    # copy of the corrupted file into "save" place and remove the original one
    copy( "$rrd_file", "$tmpdir/" ) || error( "Cannot: cp $rrd_file $tmpdir/: $!" . __FILE__ . ":" . __LINE__ );
    unlink("$rrd_file")             || error( "Cannot rm $rrd_file : $!" . __FILE__ . ":" . __LINE__ );
    error("$err_text, moving it into: $tmpdir/");
  }
  else {
    error("$err_text");
  }
  return 0;
}

# reduce files 'lpar.mmm' into 'lpar/mem.mmm'
# at the same time creating 'lpar/pgs.mm'
# reduction:
# leave out data streams X
# data streams O export to new pgs.mmm
#
#  RRDp::cmd qq(create "$rrd"  --start "$time"  --step "$STEP"
#   "DS:size:GAUGE:$no_time:0:102400000"
#   "DS:nuse:GAUGE:$no_time:0:102400000"
#   "DS:free:GAUGE:$no_time:0:102400000"
#   "DS:pin:GAUGE:$no_time:0:102400000"
# X  "DS:virtual:GAUGE:$no_time:0:102400000"
# X  "DS:available:GAUGE:$no_time:0:102400000"
# X  "DS:loaned:GAUGE:$no_time:0:102400000"
# X  "DS:mmode:GAUGE:$no_time:0:20"
# X  "DS:size_pg:GAUGE:$no_time:0:102400000"
# X  "DS:inuse_pg:GAUGE:$no_time:0:102400000"
# X  "DS:pin_work:GAUGE:$no_time:0:102400000"
# X  "DS:pin_pers:GAUGE:$no_time:0:102400000"
# X  "DS:pin_clnt:GAUGE:$no_time:0:102400000"
# X  "DS:pin_other:GAUGE:$no_time:0:102400000"
#   "DS:in_use_work:GAUGE:$no_time:0:102400000"
# X  "DS:in_use_pers:GAUGE:$no_time:0:102400000"
#   "DS:in_use_clnt:GAUGE:$no_time:0:102400000"
# O  "DS:page_in:COUNTER:$no_time:0:U"
# O  "DS:page_out:COUNTER:$no_time:0:U"
#
#  retentions are taken from original file 'lpar.mmm'

#  creating pgs.mmm
#
#   RRDp::cmd qq(create "$rrd"  --start "$time" --step "$STEP"
#    "DS:page_in:COUNTER:$no_time:0:U"
#    "DS:page_out:COUNTER:$no_time:0:U"
#    "DS:paging_space:GAUGE:$no_time:0:U"
#    "DS:percent:GAUGE:$no_time:0:100"
#
#  retentions are taken from original file 'lpar.mmm'
#
#  algorithm:
#  cycle on workdir/servers - take only directories
#   |   cycle on workdir/servers/hmcs - take only directories
#   |   |   cycle on workdir/servers/hmcs/*.mmm - means 'lpar'.mmm
#   |   |   |  -  if exists workdir/servers/hmcs/lpar/mem.mmm      -> next - already done
#   |   |   |  -  if workdir/servers/hmcs/'lpar'.mmm ds names are as above ? no -> next
#   |   |   |  -  if not exists dir workdir/servers/hmcs/lpar/ then create
#   |   |   |  -  convert from 'lpar.mmm' -> lpar/mem.mmm and lpar/pgs.mmm
#   |   |   |  -  create hard links if dual hmc setup
#   --------------

# original data 'lpar.mmm'

#<!-- Round Robin Database Dump --><rrd> <version> 0003 </version>
#       <step> 60 </step> <!-- Seconds -->
#       <lastupdate> 1392645960 </lastupdate> <!-- 2014-02-17 15:06:00 GMT+01:00 -->
#
#       <ds>
#               <name> size </name>
#               <type> GAUGE </type>
#               <minimal_heartbeat> 120 </minimal_heartbeat>
#               <min> 0.0000000000e+00 </min>
#               <max> 1.0240000000e+08 </max>
#
#               <!-- PDP Status -->
#               <last_ds> UNKN </last_ds>
#               <value> 0.0000000000e+00 </value>
#               <unknown_sec> 0 </unknown_sec>
#       </ds>
#
#       <ds>
#               <name> nuse </name>
# and so on
#                <unknown_sec> 0 </unknown_sec>
#       </ds>

#<!-- Round Robin Archives -->   <rra>
#               <cf> AVERAGE </cf>
#               <pdp_per_row> 1 </pdp_per_row> <!-- 60 seconds -->

#               <params>
#               <xff> 5.0000000000e-01 </xff>
#               </params>
#               <cdp_prep>
#                       <ds>
#                       <primary_value> 1.0485760000e+06 </primary_value>
#                       <secondary_value> NaN </secondary_value>
#                       <value> NaN </value>
#                       <unknown_datapoints> 0 </unknown_datapoints>
#                       </ds>
#                       <ds>
#                       <primary_value> 1.0402800000e+06 </primary_value>
# and so on
#                         <unknown_datapoints> 0 </unknown_datapoints>
#                       </ds>
#                       <ds>
#                       <primary_value> 0.0000000000e+00 </primary_value>
#                       <secondary_value> NaN </secondary_value>
#                       <value> NaN </value>
#                       <unknown_datapoints> 0 </unknown_datapoints>
#                       </ds>
#               </cdp_prep>
#               <database>
#                       <!-- 2013-12-22 08:45:00 CET / 1387698300 --> <row><v> 1.0485760000e+06 </v><v> 1.0434915333e+06 </v><v> 5.0805333333e+03 </v><v> 4.0328000000e+05 </v><v> 6.2166573333e+05 </v><v> 3.7554233333e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v><v> 3.2768000000e+06 </v><v> 6.5034000000e+03 </v><v> 3.5370000000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v><v> 4.9580000000e+04 </v><v> 6.2166573333e+05 </v><v> 0.0000000000e+00 </v><v> 4.2182580000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v></row>
#                       <!-- 2013-12-22 08:46:00 CET / 1387698360 --> <row><v> 1.0485760000e+06 </v><v> 1.0446240000e+06 <
# and so on
#                        <!-- 2014-02-20 08:44:00 CET / 1392882240 --> <row><v> 1.0485760000e+06 </v><v> 1.0402800000e+06 </v><v> 7.7720000000e+03 </v><v> 4.1174000000e+05 </v><v> 6.3619600000e+05 </v><v> 3.6001200000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v><v> 3.2768000000e+06 </v><v> 6.5280000000e+03 </v><v> 3.6216000000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v><v> 4.9580000000e+04 </v><v> 6.3567200000e+05 </v><v> 0.0000000000e+00 </v><v> 4.0460800000e+05 </v><v> 0.0000000000e+00 </v><v> 0.0000000000e+00 </v></row>
#                </database>
#       </rra>
#       <rra>
#               <cf> AVERAGE </cf>
#               <pdp_per_row> 5 </pdp_per_row> <!-- 300 seconds -->

#                <params>
#               <xff> 5.0000000000e-01 </xff>
#               </params>
#               <cdp_prep>
#                       <ds>
#                       <primary_value> 1.0485760000e+06 </primary_value>
# and so on
#
#              <pdp_per_row> 60 </pdp_per_row> <!-- 3600 seconds -->
#              <pdp_per_row> 300 </pdp_per_row> <!-- 18000 seconds -->
#              <pdp_per_row> 1440 </pdp_per_row> <!-- 86400 seconds -->

#

#  ****    main  ****
#

my @pids;
my $max      = 8;
my $children = 0;
my $started  = "";
my $substr   = "";
foreach my $rrd_file (<$wrkdir/*/*/*.mmm>) {

  print "convert processing $rrd_file\n";
  my @partnames = split( /\//, $rrd_file );
  my $lpar      = $partnames[-1];
  my $hmc       = $partnames[-2];
  my $server    = $partnames[-3];
  if ( -l "$wrkdir/$server" ) {
    print " skip link $wrkdir/$server\n";
    next;
  }
  chomp($lpar);
  $lpar =~ s/\.mmm$//;
  my $rrd_dir = "$wrkdir/$server/$hmc/$lpar";
  if ( -f "$rrd_dir/mem.mmm" ) {
    print "$rrd_dir/mem.mmm exists\n";
    next;
  }
  $substr = $server . $lpar . "tttt";
  if ( index( $started, $substr ) != -1 ) {
    print "$server.$lpar has already been started\n";
    next;
  }
  $started .= $server . $lpar . "tttt ";

  #   if ( -d "$tmpdir/$server.$lpar.tttt" ) {
  #      print "$tmpdir/$server.$lpar.tttt exists, currently preparing\n";
  #      next;
  #   }
  my $pid;
  if ( $children == $max ) {

    # --------------------------------
    # for full process comment next 5 lines
    #for my $pid(@pids) {
    #    waitpid $pid, 0;
    #}
    #print "!end of convert\n";
    #exit;

    $pid = wait();
    $children--;
  }
  if ( defined( $pid = fork() ) ) {
    if ($pid) {
      $children++;
      print "Parent: forked child ($pid)\n";
      push @pids, $pid;
    }
    else {
      conv_lpar( $rrd_file, $server, $lpar, $rrd_dir, $tmpdir );

      #         child($i);
      exit;
    }
  }
  else {
    print "Error: failed to fork\n";
    exit;
  }
}

for my $pid (@pids) {
  waitpid $pid, 0;
}

print "!end of convert\n";
exit;

sub conv_lpar {
  my $rrd_file = shift;
  my $server   = shift;
  my $lpar     = shift;
  my $rrd_dir  = shift;
  my $tmpd     = shift;

  # start RRD pipe
  RRDp::start "$rrdtool";

  # return 1;
  my $tmpdir = "$tmpd/$server.$lpar.tttt";

  #    if ( -d "$tmpdir" ) { return 1 };     # is currently preparing
  mkdir("$tmpdir") || error( "Cannot mkdir $tmpdir: $!" . __FILE__ . ":" . __LINE__ );
  my $f_dumped = "$tmpdir/rrd_dump";
  unlink($f_dumped);    #in any case

  RRDp::cmd qq(dump "$rrd_file" "$f_dumped");
  my $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }

  open( DF_IN, "< $f_dumped" ) || error( "Cannot open for reading $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $f_pgs = "$tmpdir/rrd_dump_pgs";
  open( DF_OUT, "> $f_pgs" ) || error( "Cannot open for writing $f_pgs: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  my $line;
  while ( $line = <DF_IN> ) {    # beginning
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {
    last if ( $line =~ "<name> page_in </name>" );
  }
  print DF_OUT "$line";
  while ( $line = <DF_IN> ) {    #R&W page_in page_out
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {
    print DF_OUT "$line";
    last if ( $line =~ "</ds>" );
  }
  print DF_OUT "
	<ds>
		<name> paging_space </name>
		<type> GAUGE </type>
		<minimal_heartbeat> 120 </minimal_heartbeat>
		<min> 0.0000000000e+00 </min>
		<max> NaN </max>

		<!-- PDP Status -->
		<last_ds> UNKN </last_ds>
		<value> 0.0000000000e+00 </value>
		<unknown_sec> 0 </unknown_sec>
	</ds>

	<ds>
		<name> percent </name>
		<type> GAUGE </type>
		<minimal_heartbeat> 120 </minimal_heartbeat>
		<min> 0.0000000000e+00 </min>
		<max> 1.0000000000e+02 </max>

		<!-- PDP Status -->
		<last_ds> UNKN </last_ds>
		<value> 0.0000000000e+00 </value>
		<unknown_sec> 0 </unknown_sec>
	</ds>
";

  # <!-- Round Robin Archives -->   <rra>
  # reading data points - 5 cycles (RRA definition and data points) and till the end

  my $rra_lines = "			<ds>
			<primary_value> NaN </primary_value>
			<secondary_value> NaN </secondary_value>
			<value> NaN </value>
			<unknown_datapoints> 0 </unknown_datapoints>
			</ds>
			<ds>
			<primary_value> NaN </primary_value>
			<secondary_value> NaN </secondary_value>
			<value> NaN </value>
			<unknown_datapoints> 0 </unknown_datapoints>
			</ds>
";

  for ( my $cycle = 0; $cycle <= 4; $cycle++ ) {
    while ( $line = <DF_IN> ) {    # until ds
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    for ( my $ix = 1; $ix < 18; $ix++ ) {
      while ( $line = <DF_IN> ) {    # leave out until page_in ds
        last if ( $line =~ "<ds>" );
      }
    }
    while ( $line = <DF_IN> ) {      # for page_in
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {      # for page_out_
      print DF_OUT "$line";
      last if ( $line =~ "</ds>" );
    }
    print DF_OUT "$rra_lines";       # and next two ds
    $line = <DF_IN>;
    print DF_OUT "$line";

    while ( $line = <DF_IN> ) {
      if ( $line =~ /<\/v><\/row>/ ) {
        ( my $p1, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, my $p2, my $p3 ) = split( /<v>/, $line );
        $p3 =~ s/<\/row>/<v> NaN <\/v><v> NaN <\/v><\/row>/;
        $line = $p1 . "<v>" . $p2 . "<v>" . $p3;
      }
      print DF_OUT "$line";
      last if ( $line =~ "<cdp_prep>" );
    }
  }    # end of for cycle

  while ( $line = <DF_IN> ) {    # until end of file
    print DF_OUT "$line";
  }    # end of file

  close(DF_OUT) || error( "Cannot close $f_pgs: $!" . __FILE__ . ":" . __LINE__ )    && return 0;
  close(DF_IN)  || error( "Cannot close $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  #   2nd part: read dumped 'lpar.mmm', create mem.mmm,

  open( DF_IN, "< $f_dumped" ) || error( "Cannot open for reading $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  my $f_mem = "$tmpdir/rrd_dump_mem";
  open( DF_OUT, "> $f_mem" ) || error( "Cannot open for writing $f_mem: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  while ( $line = <DF_IN> ) {    # beginning
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {    # size
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {    # nuse
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {    # free
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {    # pin
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {
    last if ( $line =~ "<name> in_use_work </name>" );
  }
  print DF_OUT "$line";
  while ( $line = <DF_IN> ) {    # in_use_work
    print DF_OUT "$line";
    last if ( $line =~ "<ds>" );
  }
  while ( $line = <DF_IN> ) {
    last if ( $line =~ "<name> in_use_clnt </name>" );
  }
  print DF_OUT "$line";
  while ( $line = <DF_IN> ) {    # in_use_clnt_
    print DF_OUT "$line";
    last if ( $line =~ "</ds>" );
  }
  while ( $line = <DF_IN> ) {
    last if ( $line =~ "Round Robin" );
  }
  print DF_OUT "\n$line";

  for ( my $cycle = 0; $cycle <= 4; $cycle++ ) {

    while ( $line = <DF_IN> ) {    # until ds
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {    # size
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {    # nuse
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {    # free
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {    # pin
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    for ( my $ix = 1; $ix < 11; $ix++ ) {
      while ( $line = <DF_IN> ) {    # leave out until in_use_work
        last if ( $line =~ "<ds>" );
      }
    }
    while ( $line = <DF_IN> ) {      # in_use_work
      print DF_OUT "$line";
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {      # leave out until in_use_clnt
      last if ( $line =~ "<ds>" );
    }
    while ( $line = <DF_IN> ) {      # in_use_clnt
      print DF_OUT "$line";
      last if ( $line =~ "</ds>" );
    }
    while ( $line = <DF_IN> ) {      # leave out until in_use_clnt
      last if ( $line =~ "</cdp_prep>" );
    }
    print DF_OUT "$line";
    while ( $line = <DF_IN> ) {
      if ( $line =~ /<\/v><\/row>/ ) {
        ( my $p1, my $size, my $nuse, my $free, my $pin, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, my $in_use_work, undef, my $in_use_clnt, undef, undef ) = split( /<v>/, $line );
        $line = $p1 . "<v>" . $size . "<v>" . $nuse . "<v>" . $free . "<v>" . $pin . "<v>" . $in_use_work . "<v>" . $in_use_clnt . "<\/row>\n";
      }
      print DF_OUT "$line";
      last if ( $line =~ "<cdp_prep>" );
    }
  }    # end of for cycle

  #$| = 1;
  while ( $line = <DF_IN> ) {    # until end of file
    print DF_OUT "$line";
  }    # end of file

  close(DF_OUT) || error( "Cannot close $f_mem: $!" . __FILE__ . ":" . __LINE__ )    && return 0;
  close(DF_IN)  || error( "Cannot close $f_dumped: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  # test file pgs

  my $tmp_pgs = "$tmpdir/rrd_pgs";
  unlink("$tmp_pgs");

  RRDp::cmd qq(restore "$f_pgs" "$tmp_pgs");
  $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }

  $rrd_file = $tmp_pgs;
  $f_dumped = "$tmpdir/rrd_dump_pgs2";
  unlink($f_dumped);    #in any case

  RRDp::cmd qq(dump "$rrd_file" "$f_dumped");
  $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }
  my $f_one = "$tmpdir/rrd_dump_pgs";
  my $f_two = "$tmpdir/rrd_dump_pgs2";
  if ( compare( "$f_one", "$f_two" ) != 0 ) {
    error( "$f_one, $f_two are not the same for $rrd_dir : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  unlink("$f_one");
  unlink("$f_two");

  # test file mem

  my $tmp_mem = "$tmpdir/rrd_mem";
  unlink("$tmp_mem");

  RRDp::cmd qq(restore "$f_mem" "$tmp_mem");
  $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }

  $rrd_file = $tmp_mem;
  $f_dumped = "$tmpdir/rrd_dump_mem2";
  unlink($f_dumped);    #in any case

  RRDp::cmd qq(dump "$rrd_file" "$f_dumped");
  $answer = RRDp::read;
  if ( $$answer =~ "ERROR" ) {
    error(" Convert rrdtool error : $$answer");
    if ( $$answer =~ "is not an RRD file" ) {
      ( my $err, my $file, my $txt ) = split( /'/, $$answer );
      error("It needs to be removed due to corruption: $file");
    }
    else {
      error("Convert rrdtool error : $$answer");
    }
    return 0;
  }
  $f_one = "$tmpdir/rrd_dump_mem";
  $f_two = "$tmpdir/rrd_dump_mem2";
  if ( compare( "$f_one", "$f_two" ) != 0 ) {
    error( "$f_one, $f_two are not the same for $rrd_dir : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  unlink("$f_one");
  unlink("$f_two");

  # ready to place files in dir lpar/

  if ( !-d "$rrd_dir/" ) {
    mkdir("$rrd_dir/") || error( "Cannot mkdir $rrd_dir/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }
  my $rrd_file_pgs = "$rrd_dir/pgs.mmm";
  my $rrd_file_mem = "$rrd_dir/mem.mmm";
  move( "$tmpdir/rrd_pgs", "$rrd_file_pgs" ) || error( "Cannot move $rrd_dir/pgs.mmm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  move( "$tmpdir/rrd_mem", "$rrd_file_mem" ) || error( "Cannot move $rrd_dir/pgs.mmm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  unlink("$tmpdir/rrd_dump");

  # create lpar directory and file hard link into the other HMC if there is dual HMC setup

  my $found        = 0;
  my $server_space = $server;
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }
  my @files = <$wrkdir/$server_space/*>;

  $rrd_dir = "";
  foreach my $rrd_dir_tmp (@files) {
    chomp($rrd_dir_tmp);
    if ( -d $rrd_dir_tmp ) {
      $found   = 1;
      $rrd_dir = $rrd_dir_tmp;
      last;
    }
  }
  if ( $found == 0 ) {
    error( "Convert: Could not found a HMC in : $wrkdir/$server $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  my $rrd_dir_base = basename($rrd_dir);
  foreach my $rrd_dir_new (@files) {
    chomp($rrd_dir_new);
    my $rrd_dir_new_base = basename($rrd_dir_new);
    if ( -d $rrd_dir_new && $rrd_dir_new_base !~ m/^$rrd_dir_base$/ ) {
      if ( !-d "$rrd_dir_new/$lpar/" ) {
        print "mkdir dual     : $rrd_dir_new/$lpar/\n" if $DEBUG;
        mkdir("$rrd_dir_new/$lpar/") || error( "Cannot mkdir $rrd_dir_new/$lpar/: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
      }
      print " hard link      : $rrd_file_mem --> $rrd_dir_new/$lpar/mem.mmm\n" if $DEBUG;
      my $rrd_link_new = "$rrd_dir_new/$lpar/mem.mmm";
      unlink("$rrd_dir_new/$lpar/mem.mmm");    #for every case
      link( $rrd_file_mem, "$rrd_dir_new/$lpar/mem.mmm" ) || error( "Cannot link $rrd_dir_new/$lpar/mem.mmm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

      print " hard link      : $rrd_file_pgs --> $rrd_dir_new/$lpar/pgs.mmm\n" if $DEBUG;
      $rrd_link_new = "$rrd_dir_new/$lpar/pgs.mmm";
      unlink("$rrd_dir_new/$lpar/pgs.mmm");    #for every case
      link( $rrd_file_pgs, "$rrd_dir_new/$lpar/pgs.mmm" ) || error( "Cannot link $rrd_dir_new/$lpar/pgs.mmm: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
  }

  #  unlink the original 'lpar.mmm', care if double hmc
  foreach my $rrd_dir_new (@files) {
    chomp($rrd_dir_new);
    if ( -f "$rrd_dir_new/$lpar.mmm" ) {
      print "unlinking $rrd_dir_new/$lpar.mmm  ??!!??!!\n";

      #    unlink("$rrd_dir_new/$lpar.mmm");
    }
  }
  rmdir("$tmpdir") || error( "Cannot rmdir $tmpdir: $!" . __FILE__ . ":" . __LINE__ ) && return 0;

  # close RRD pipe
  RRDp::end;

  return 1;
}

