use strict;

#use lib qw (/opt/freeware/lib/perl/5.8.0);
# no longer need to use "use lib qw" as the library PATH is already in PERL5LIB (lpar2rrd.cfg)

use Env qw(QUERY_STRING);
use Date::Parse;
use POSIX qw(strftime);
use RRDp;
use MIME::Base64;
use XoruxEdition;

#$QUERY_STRING .= ":.";

my $inputdir = $ENV{INPUTDIR};
my $tmpdir   = "$inputdir/tmp";
if ( defined $ENV{TMPDIR} ) {
  $tmpdir = $ENV{TMPDIR};
}
my $webdir  = $ENV{WEBDIR};
my $rrdtool = $ENV{RRDTOOL};
my $pic_col = $ENV{PICTURE_COLOR};
my $wrkdir  = "$inputdir/data";
my $STEP    = $ENV{SAMPLE_RATE};
my $DEBUG   = $ENV{DEBUG};
my $errlog  = $ENV{ERRLOG};

# disable Tobi's promo
#my $disable_rrdtool_tag = "COMMENT: ";
#my $disable_rrdtool_tag_agg = "COMMENT:\" \"";
my $disable_rrdtool_tag     = "--interlaced";    # just nope string, it is deprecated anyway
my $disable_rrdtool_tag_agg = "--interlaced";    # just nope string, it is deprecated anyway
my $rrd_ver                 = $RRDp::VERSION;
if ( isdigit($rrd_ver) && $rrd_ver > 1.35 ) {
  $disable_rrdtool_tag     = "--disable-rrdtool-tag";
  $disable_rrdtool_tag_agg = "--disable-rrdtool-tag";
}

my $bindir = $ENV{BINDIR};

open( OUT, ">> $errlog" ) if $DEBUG == 2;

my $compress_head = "AAAAA";                     # when query strings starts by that that it is compressed

my $query = $QUERY_STRING;
if ( $QUERY_STRING =~ m/$compress_head/ ) {
  $QUERY_STRING =~ s/^$compress_head//;
  $query = decompress_base64($QUERY_STRING);
}

# workaround for Estimator: URL length exceeded limit (even gzipped) when bunch of LPARs selected
# complete URL is loaded from temp file
elsif ( $QUERY_STRING =~ m/cwehash/ ) {
  my ( undef, $cwehash ) = split( /=/, $QUERY_STRING );
  my $cwetmpfile = "$tmpdir/cwe_$cwehash.tmp";
  if ( -e $cwetmpfile && -f _ && -r _ ) {
    $query = file_read($cwetmpfile);
    unlink $cwetmpfile;
  }
  else {
    print "Content-type: image/png\n\n";
    exit;
  }
}

( my $shour, my $smon, my $sday, my $syear, my $ehour, my $emon, my $eday, my $eyear, my $type, my $rrdheight, my $rrdwidth, my $yaxis, my $xport, my $sort_order, my $pool, my $lpar_list, my $srcfix, my $dstfix, my $none ) = split( /&/, $query );

$shour      =~ s/shour=//;
$smon       =~ s/smon=//;
$sday       =~ s/sday=//;
$syear      =~ s/syear=//;
$ehour      =~ s/ehour=//;
$emon       =~ s/emon=//;
$eday       =~ s/eday=//;
$eyear      =~ s/eyear=//;
$type       =~ s/type=//;
$rrdheight  =~ s/height=//;
$rrdwidth   =~ s/width=//;
$xport      =~ s/xport=//;
$sort_order =~ s/sort=//;
$pool       =~ s/POOL=//;     # only used for CPU workload estimator
$pool       =~ s/pool=//;     # only used for CPU workload estimator
$yaxis      =~ s/yaxis=//;
$dstfix     =~ s/dstfix=//;

$srcfix =~ s/srcfix=//;
if ( $srcfix =~ /none=1/ ) {    # this is not to show: none=1623053960617
  $srcfix = "";
}
chomp($dstfix);                 # it must be there, enter appear there

#print STDERR "58 lpar-list-rep.pl query: $query : $dstfix $srcfix\n";

$type = 'm' if $type eq 'x';    # from glob hist rep

# XPORT is export to XML and then to CVS
my $showtime = "";

if ($xport) {

  # It should be here to do not influence normal report when XML is not in Perl
  require "$bindir/xml.pl";

  # use XML::Simple; --> it has to be in separete file
  print "Content-type: application/octet-stream\n";

  # for normal content type is printed just before picture print to be able print
  # text/html error if appears
  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $showtime = " --showtime";
  }
}
else {
  print "Content-type: image/png\n";
  print "Cache-Control: max-age=60, must-revalidate\n\n";    # workaround for caching on Chrome
}

if ( !$pool eq '' ) {
  $xport = 0;                                                # do not need it when CPU workload estimator
  chomp($pool);
  $pool =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  $pool =~ s/\+/ /g;
}

# Loop per each chosen lpar/CPU pool/Memory
my @rperf_legend       = "";
my $rperf_legend_count = 0;
my @managedname_all    = "";
my @hmc_all            = "";
my @lpar_all           = "";
my @rperf_all          = "";
my @cpu_ghz_all        = "";
my @cores_all          = "";
my $indx               = 0;
chomp($lpar_list);
$lpar_list =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
$lpar_list =~ s/Report=Generate\+Report//g;
$lpar_list =~ s/\+/ /g;

#print OUT "00 $lpar_list\n"  if $DEBUG == 2 ;
( my @lpar_row ) = split( /LPAR=/, $lpar_list );

# print STDERR "lpar-list-rep.pl 122 \@lpar_row @lpar_row\n";
foreach my $line (@lpar_row) {
  chomp($line);
  $line =~ s/ CGROUP.*$//;    # glob hist rep sends with last LPAR when chosen LPAR + CGROUP
  if ( length($line) == 0 ) {
    next;
  }

  # print STDERR "lpar-list-rep.pl 127 $line\n";
  #( my $hmc_pool , my $managedname_pool, $lpar_pool, $rperf, $cpu_ghz, $cores) = split (/\|/,$pool);

  # parse each lpar line to get details passed here
  ( $hmc_all[$indx], $managedname_all[$indx], $lpar_all[$indx], $rperf_all[$indx], $cpu_ghz_all[$indx], $cores_all[$indx] ) = split( /\|/, $line );
  if ( $lpar_all[$indx] eq '' ) {
    error( "Could not find a lpar : $line " . __FILE__ . ":" . __LINE__ );
    $hmc_all[$indx]         = "";
    $managedname_all[$indx] = "";
    next;    # some problem
  }
  $lpar_all[$indx] =~ s/ $//;
  $lpar_all[$indx] =~ s/\//\&\&1/g;

  #print STDERR "11 $hmc_all[$indx] -- $managedname_all[$indx] -- $lpar_all[$indx] -- $rperf_all[$indx] -- $cpu_ghz_all[$indx] -- $cores_all[$indx]\n";
  # print STDERR "lpar-list-rep.pl 142 $hmc_all[$indx] -- $managedname_all[$indx] -- $lpar_all[$indx]\n";
  $indx++;
}
$indx++;

# print STDERR "lpar-list-rep.pl 145 \@lpar_all @lpar_all\n";
my $start_unix  = str2time( $syear . "-" . $smon . "-" . $sday . " " . $shour . ":00:00" );
my $end_unix    = str2time( $eyear . "-" . $emon . "-" . $eday . " " . $ehour . ":00:00" );
my $human_start = $shour . ":00:00 " . $sday . "." . $smon . "." . $syear;
my $human_end   = $ehour . ":00:00 " . $eday . "." . $emon . "." . $eyear;
my $start       = "";
if ( $shour == 24 ) {

  # workaround for rrdtool when it parses date with 24 on the start badly
  # RRDTool: ERROR: end time: did you really mean month 24?
  $start = "23:59 " . $sday . "." . $smon . "." . $syear;
}
else {
  $start = $shour . ":00 " . $sday . "." . $smon . "." . $syear;
}
my $end = "";
if ( $ehour == 24 ) {

  # workaround for rrdtool when it parses date with 24 on the start badly
  # RRDTool: ERROR: end time: did you really mean month 24?
  $end = "23:59 " . $eday . "." . $emon . "." . $eyear;
}
else {
  $end = $ehour . ":00 " . $eday . "." . $emon . "." . $eyear;
}

# it must go into a temp file as direct stdout from RRDTOOL somehow does not work for me
my $name = "/var/tmp/lpar2rrd-$$.png";

#$name = "-";
my $act_time = localtime();

if ( !-d "$webdir" ) {
  die "$act_time: Pls set correct path to Web server pages, it does not exist here: $webdir\n";
}

# start RRD via a pipe
if ( !-f "$rrdtool" ) {
  die "$act_time: Set correct path to rrdtool binarry, it does not exist here: $rrdtool\n";
}
RRDp::start "$rrdtool";

multiview( $name, $indx, $type, time(), $start, $end, $start_unix, $end_unix, $sort_order, $pool, $srcfix, $dstfix );

# close RRD pipe
RRDp::end;

# exclude Export here
if ( !$xport ) {
  print_png();
}

exit(0);

# Print the png out
sub print_png {

  open( PNG, "< $name" ) || die "Cannot open  $name: $!";
  binmode(PNG);
  while ( read( PNG, $b, 4096 ) ) {
    print "$b";
  }
  unlink("$name");
}

sub xport_print {
  my $xml_org = shift;
  my $multi   = shift;
  my $xml     = "";
  my $sep     = $ENV{'CSV_SEPARATOR'} ||= ";";

  if ( $multi == 1 ) {

    #print OUT "--xport-- $xml_org\n";
    $xml = XMLin($xml_org);
  }
  else {
    #print OUT "--xport++ $$xml_org\n";
    $xml = XMLin($$xml_org);
  }
  if ( ref $xml->{meta}{legend}{entry} eq "ARRAY" ) {
    foreach my $item ( @{ $xml->{meta}{legend}{entry} } ) {    # in case semicolon in lpar name
      $item = "\"" . $item . "\"";
    }
  }
  else {
    $xml->{meta}{legend}{entry} = "\"" . $xml->{meta}{legend}{entry} . "\"";
  }

  print join( "$sep", 'Timestamp DD.MM.YYYY HH:MM', @{ $xml->{meta}{legend}{entry} } ), "\n";
  foreach my $row ( @{ $xml->{data}{row} } ) {
    my $time = strftime "%d.%m.%y %H:%M:%S", localtime( $row->{t} );
    my $line = join( "$sep", $time, @{ $row->{v} } );
    $line =~ s/NaNQ|NaN|nan/0/g;
    print "$line\n";
  }
  return 0;
}

sub multiview {
  my $name         = shift;
  my $indx         = shift;
  my $type         = shift;
  my $act_time     = shift;
  my $start        = shift;
  my $end          = shift;
  my $start_unix   = shift;
  my $end_unix     = shift;
  my $sort_order   = shift;
  my $pool         = shift;
  my $srcfix       = shift;
  my $dstfix       = shift;
  my $sh_pool_name = "";

  # now there are 54 colours going round
  # 1st color == red i excuded and used manually for pool purposes
  my @color     = ( "#0000FF", "#C0C0C0", "#FFFF00", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#FF00FF", "#800080", "#FDD017", "#0000A0", "#3BB9FF", "#008000", "#800000", "#ADD8E6", "#F778A1", "#800517", "#736F6E", "#F52887", "#C11B17", "#5CB3FF", "#A52A2A", "#FF8040", "#2B60DE", "#736AFF", "#1589FF", "#98AFC7", "#8D38C9", "#307D7E", "#F6358A", "#151B54", "#6D7B8D", "#FDEEF4", "#FF0080", "#F88017", "#2554C7", "#FFF8C6", "#D4A017", "#306EFF", "#151B8D", "#9E7BFF", "#EAC117", "#E0FFFF", "#15317E", "#6C2DC7", "#FBB917", "#FCDFFF", "#15317E", "#254117", "#FAAFBE", "#357EC7", "#4AA02C", "#38ACEC" );
  my $color_max = 52;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          # 0 - 53 is 54 colors --> no, no, red is not there used, so 53 color only

  my $step = $STEP;

  if ( $type =~ "d" ) {
    $step = 86400;
  }
  else {
    if ( $type =~ "m" ) {
      $step = 60;
    }
    else {
      if ( $type =~ "n" ) {
        $type = "m";
        $step = 600;
      }
      else {
        if ( $type =~ "h" ) {
          $step = 3600;
        }
      }
    }
  }

  my $unit = "";
  if ( $yaxis =~ m/r/ ) {
    $unit = "rPerfs";
  }
  else {
    if ( $yaxis =~ m/w/ ) {
      $unit = "CPWs";
    }
    else {
      $unit = "CPU cores";
    }
  }

  my $i         = 0;                                             # index for colors
  my $type_sam  = $type;
  my $header    = "LPARs in $unit: $human_start : $human_end";
  my $cmd       = "";
  my $cmd_xport = "";

  $cmd .= "graph \\\"$name\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start \\\"$start\\\"";
  $cmd .= " --end \\\"$end\\\"";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag_agg";
  $cmd .= " --slope-mode";
  $cmd .= " --width=$rrdwidth";
  $cmd .= " --height=$rrdheight";
  $cmd .= " --step=$step";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --upper-limit=0.1";

  if ( $yaxis =~ m/r/ ) {
    $cmd .= " --vertical-label=\\\"rPerf units\\\"";
  }
  else {
    if ( $yaxis =~ m/w/ ) {
      $cmd .= " --vertical-label=\\\"CPW units\\\"";
    }
    else {
      $cmd .= " --vertical-label=\\\"CPU cores\\\"";
    }
  }
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";

  if ( $pool eq '' ) {

    # exclude CPU workload ....
    if ( $sort_order =~ m/lpar/ ) {

      # sorting per lpar
      $cmd .= " COMMENT:\\\"Average utilization in $unit (LPAR - Server)                AVG       Max\\l\\\"";
    }
    else {
      if ( $sort_order =~ m/hmc/ ) {

        # sorting per hmcr
        $cmd .= " COMMENT:\\\"Average utilization in $unit (Server - LPAR)                AVG       Max\\l\\\"";
      }
      else {
        # sorting per server
        $cmd .= " COMMENT:\\\"Average utilization in $unit (Server - LPAR)                AVG       Max\\l\\\"";
      }
    }
  }

  my $gtype            = "AREA";
  my $j                = 0;
  my $legent_length    = 60;
  my $name_all         = "";
  my $max_cpu_txt      = "";
  my $res_cpu_txt      = "";
  my $lpar_pool        = "";       # must be here
  my $managedname_pool = "";       # must be here
  my $rperf            = "";
  my $cpu_ghz          = "";
  my $cores            = "";
  my $rperf_pool       = "";
  my $cpu_ghz_pool     = "";
  my $cores_pool       = "";
  my $newsrv           = 0;
  my $rperf_pool_act   = "";

  # section used only for CPU workload estimator (add as first CPU pool)
  if ( !$pool eq '' ) {
    ( my $hmc_pool, $managedname_pool, $lpar_pool, $rperf_pool, $cpu_ghz_pool, $cores_pool ) = split( /\|/, $pool );

    # -PH: workaround, from UI now comes total instead of pool, perhaps partly implemented pool_total, kept original functionality
    if ( $lpar_pool eq 'total' ) {
      $lpar_pool = "pool";
    }

    my $rperf_pool_act_tmp = get_rperf_one( $rperf_pool, -1, -1, $yaxis );    # SMT8 prefered
    ( $rperf_pool_act, my $smt ) = split( /:/, $rperf_pool_act_tmp );
    if ( $rperf_pool_act == -1 ) {
      if ( $yaxis =~ m/w/ && $yaxis =~ m/r/ ) {
        error( "Cannot find rperf for $hmc_pool:$managedname_pool:$lpar_pool:$cpu_ghz_pool:$cores_pool:$yaxis " . __FILE__ . ":" . __LINE__ );
      }
    }
    if ( $yaxis !~ m/w/ && $yaxis !~ m/r/ ) {
      $rperf_pool_act = 1;
      $smt            = "";
    }
    if ( $yaxis =~ m/w/ ) {
      $smt = "";
    }

    #print STDERR "044 $rperf_pool_act === $rperf_pool\n";

    $rperf_legend[$rperf_legend_count] = $managedname_pool . "|" . $lpar_pool . "|" . $rperf_pool_act . "|" . $cpu_ghz_pool . "|" . $cores_pool;
    $rperf_legend[$rperf_legend_count] =~ s/__XXX__//;
    $rperf_legend_count++;
    my $file = "";
    if ( $type =~ "d" ) {
      $file = $lpar_pool . ".rrd";
      if ( !-f "$wrkdir/$managedname_pool/$hmc_pool/$file" ) {

        # IVM & SDMC daily stats are here
        $file = $lpar_pool . ".rrm";
        if ( !-f "$wrkdir/$managedname_pool/$hmc_pool/$file" ) {
          print OUT " does not exists $wrkdir/$managedname_pool/$hmc_pool/$file and even .rrd\n" if ( $DEBUG == 2 );
        }
      }
    }
    if ( ( $type =~ "h" ) || ( $type =~ "m" ) || ( $type =~ "n" ) ) {
      $file = $lpar_pool . ".rrm";
      if ( !-f "$wrkdir/$managedname_pool/$hmc_pool/$file" ) {
        $file = $lpar_pool . ".rrt";
        if ( !-f "$wrkdir/$managedname_pool/$hmc_pool/$file" ) {
          print OUT " does not exists $wrkdir/$managedname_pool/$hmc_pool/$file and even .rrm\n" if ( $DEBUG == 2 );
        }
      }
    }
    print OUT "66 $hmc_pool $managedname_pool $lpar_pool $file\n" if ( $DEBUG == 2 );

    print OUT "77 $wrkdir/$managedname_pool/$hmc_pool/$file \n" if ( $DEBUG == 2 );

    # find out name of shared pool from given SharedPoolXY name
    $sh_pool_name = $lpar_pool;
    if ( $lpar_pool =~ m/SharedPool[1-9]/ && -f "$inputdir/data/$managedname_pool/$hmc_pool/cpu-pools-mapping.txt" ) {
      open( FR, "< $inputdir/data/$managedname_pool/$hmc_pool/cpu-pools-mapping.txt" );
      my $pool_id = $lpar_pool;
      $pool_id =~ s/SharedPool//;
      foreach my $linep (<FR>) {
        chomp($linep);
        ( my $id, my $pool_name ) = split( /,/, $linep );
        if ( $id == $pool_id ) {
          $sh_pool_name = $pool_name;
          last;
        }
      }
      close(FR);
    }
    else {
      #if ( $lpar_pool =~ m/^pool$/ ) {
      $sh_pool_name = "CPU Pool";

      #}
    }

    if ( $sort_order =~ m/lpar/ ) {

      # sorting per lpar
      $name_all = $sh_pool_name . " - " . $managedname_pool;
    }
    else {
      if ( $sort_order =~ m/hmc/ ) {

        # sorting per hmc
        $name_all = $managedname_pool . " - " . $sh_pool_name;
      }
      else {
        # sorting per server
        $name_all = $managedname_pool . " - " . $sh_pool_name;
      }
    }

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    $legent_length = length($name_all);
    if ( $legent_length < 60 ) {
      $legent_length = 60;
    }

    for ( my $k = length($name_all); $k < $legent_length; $k++ ) {
      $name_all .= " ";
    }

    $max_cpu_txt = "Max $unit";
    for ( my $k = length($max_cpu_txt); $k < $legent_length; $k++ ) {
      $max_cpu_txt .= " ";
    }

    $res_cpu_txt = "Reserved $unit";
    for ( my $k = length($res_cpu_txt); $k < $legent_length; $k++ ) {
      $res_cpu_txt .= " ";
    }

    $cmd .= " COMMENT:\\\" \\l\\\"";

    #$cmd .= " COMMENT:\\\"Average utilization in $unit\\l\\\"";
    $cmd .= " COMMENT:\\\" \\l\\\"";

    if ( $name_all =~ m/__XXX__/ ) {
      $newsrv = 1;    # mean it is for new HW estimation only
      $name_all         =~ s/__XXX__//;
      $managedname_pool =~ s/__XXX__//;
    }

    if ( $newsrv == 0 ) {

      # except new HW server est
      if ( $sort_order =~ m/lpar/ ) {

        # sorting per lpar
        if ( $yaxis =~ m/w/ ) {
          $cmd .= " COMMENT:\\\"  POOL - Server (already existing load on the target) in $unit      avrg             max  Fix\\l\\\"";
        }
        if ( $yaxis =~ m/r/ ) {
          $cmd .= " COMMENT:\\\"  POOL - Server (already existing load on the target) in $unit  avrg      max  SMT  Fix  \\l\\\"";
        }
        if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
          $cmd .= " COMMENT:\\\"  POOL - Server (already existing load on the target) in cores   avrg      max  \\l\\\"";
        }
      }
      else {
        if ( $sort_order =~ m/hmc/ ) {

          # sorting per hmcr
          if ( $yaxis =~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - POOL (already existing load on the target) in $unit      avrg             max  Fix\\l\\\"";
          }
          if ( $yaxis =~ m/r/ ) {
            $cmd .= " COMMENT:\\\"  Server - POOL (already existing load on the target) in $unit  avrg      max  SMT  Fix  \\l\\\"";
          }
          if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - POOL (already existing load on the target) in cores   avrg      max  \\l\\\"";
          }
        }
        else {
          # sorting per server
          if ( $yaxis =~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - POOL (already existing load on the target) in $unit      avrg             max  Fix\\l\\\"";
          }
          if ( $yaxis =~ m/r/ ) {
            $cmd .= " COMMENT:\\\"  Server - POOL (already existing load on the target) in $unit  avrg      max  SMT  Fix  \\l\\\"";
          }
          if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - POOL (already existing load on the target) in cores   avrg      max  \\l\\\"";
          }
        }
      }

      # find our rPerf --> it is already just, just assure everything is ok
      if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {
        if ( $rperf_pool_act eq '' || $cpu_ghz_pool eq '' || $cores_pool eq '' ) {
          err_html("Contact LPAR2RRD support : rperf_pool:$rperf_pool_act cpu_ghz_pool:$cpu_ghz_pool cores_pool:$cores_pool");
        }

        # it exit before in case of any problem in finding rperf
      }

      my $rrd = "$wrkdir/$managedname_pool/$hmc_pool/$file";

      # bulid RRDTool cmd
      if ( $lpar_pool =~ "SharedPool[1-9]" || $lpar_pool =~ "SharedPool[1-9][0-9]" ) {

        # --PH somehow re-solve SharedPool[0]
        $cmd .= " DEF:max${i}=\\\"$rrd\\\":max_pool_units:AVERAGE";
        $cmd .= " DEF:res${i}=\\\"$rrd\\\":res_pool_units:AVERAGE";
        $cmd .= " DEF:totcyc${i}=\\\"$rrd\\\":total_pool_cycles:AVERAGE";
        $cmd .= " DEF:uticyc${i}=\\\"$rrd\\\":utilized_pool_cyc:AVERAGE";
        $cmd .= " CDEF:cpuutil${i}=uticyc${i},totcyc${i},GT,UNKN,uticyc${i},totcyc${i},/,IF";
        if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {

          # rPerf
          $cmd .= " CDEF:cpuutiltot_r${i}=cpuutil${i},max${i},*";
          $cmd .= " CDEF:cpuutiltot${i}=cpuutiltot_r${i},$rperf_pool_act,*";
        }
        else {
          $cmd .= " CDEF:cpuutiltot${i}=cpuutil${i},max${i},*";
        }
        $cmd .= " $gtype:cpuutiltot${i}#FF0000:\\\"$name_all\\\"";
        if ( $yaxis =~ m/w/ ) {
          $cmd .= " GPRINT:cpuutiltot${i}:AVERAGE:\\\"%7.0lf\\t\\\"";
          $cmd .= " GPRINT:cpuutiltot${i}:MAX:\\\"%7.0lf       $dstfix\\l\\\"";
        }
        if ( $yaxis =~ m/r/ ) {
          $cmd .= " GPRINT:cpuutiltot${i}:AVERAGE:\\\"%4.0lf\\t\\\"";
          $cmd .= " GPRINT:cpuutiltot${i}:MAX:\\\"%4.0lf   $smt   $dstfix\\l\\\"";
        }
        if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
          $cmd .= " GPRINT:cpuutiltot${i}:AVERAGE:\\\"%4.1lf\\t\\\"";
          $cmd .= " GPRINT:cpuutiltot${i}:MAX:\\\"%4.1lf  \\l\\\"";
        }
      }
      else {
        # for default pool
        $cmd .= " DEF:totcyc${i}=\\\"$rrd\\\":total_pool_cycles:AVERAGE";
        $cmd .= " DEF:uticyc${i}=\\\"$rrd\\\":utilized_pool_cyc:AVERAGE";
        $cmd .= " DEF:cpu${i}=\\\"$rrd\\\":conf_proc_units:AVERAGE";
        $cmd .= " DEF:cpubor${i}=\\\"$rrd\\\":bor_proc_units:AVERAGE";
        $cmd .= " CDEF:totcpu${i}=cpu${i},cpubor${i},+";
        $cmd .= " CDEF:cpuutil${i}=uticyc${i},totcyc${i},GT,UNKN,uticyc${i},totcyc${i},/,IF";
        if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {

          # rPerf
          $cmd .= " CDEF:cpuutiltot_r${i}=cpuutil${i},totcpu${i},*";
          $cmd .= " CDEF:cpuutiltot${i}=cpuutiltot_r${i},$rperf_pool_act,*";
        }
        else {
          $cmd .= " CDEF:cpuutiltot${i}=cpuutil${i},totcpu${i},*";
        }
        $cmd .= " $gtype:cpuutiltot${i}#FF0000:\\\"$name_all\\\"";
        if ( $yaxis =~ m/w/ ) {
          $cmd .= " GPRINT:cpuutiltot${i}:AVERAGE:\\\"%7.0lf \\t\\\"";
          $cmd .= " GPRINT:cpuutiltot${i}:MAX:\\\"%7.0lf      $dstfix\\l\\\"";
        }
        if ( $yaxis =~ m/r/ ) {
          $cmd .= " GPRINT:cpuutiltot${i}:AVERAGE:\\\"%4.0lf \\t\\\"";
          $cmd .= " GPRINT:cpuutiltot${i}:MAX:\\\"%4.0lf   $smt   $dstfix\\l\\\"";
        }
        if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
          $cmd .= " GPRINT:cpuutiltot${i}:AVERAGE:\\\"%4.1lf \\t\\\"";
          $cmd .= " GPRINT:cpuutiltot${i}:MAX:\\\"%4.1lf\\l\\\"";
        }
      }
      $cmd .= " COMMENT:\\\" \\l\\\"";
      $gtype = "STACK";
    }

    if ( $sort_order =~ m/lpar/ ) {

      # sorting per lpar
      if ( $yaxis =~ m/w/ ) {
        $cmd .= " COMMENT:\\\"  LPAR - Server (will be migrated)  in $unit                         avrg            max  Fix\\l\\\"";
      }
      if ( $yaxis =~ m/r/ ) {
        $cmd .= " COMMENT:\\\"  LPAR - Server (will be migrated)  in $unit                    avrg      max  SMT  Fix\\l\\\"";
      }
      if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
        $cmd .= " COMMENT:\\\"  LPAR - Server (will be migrated)  in $unit                 avrg      max  \\l\\\"";
      }
    }
    else {
      if ( $newsrv == 1 ) {
        if ( $sort_order =~ m/hmc/ ) {

          # sorting per hmcr
          if ( $yaxis =~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)  in $unit                         avrg            max  Fix\\l\\\"";
          }
          if ( $yaxis =~ m/r/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)  in $unit                    avrg      max  SMT  Fix\\l\\\"";
          }
          if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)  in $unit                 avrg      max \\l\\\"";
          }
        }
        else {
          # sorting per server
          if ( $yaxis =~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)  in $unit                         avrg            max  Fix\\l\\\"";
          }
          if ( $yaxis =~ m/r/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)  in $unit                    avrg      max  SMT  Fix\\l\\\"";
          }
          if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)  in $unit                 avrg      max \\l\\\"";
          }
        }
      }
      else {    # for existing HW there must not be average and max ..
        if ( $sort_order =~ m/hmc/ ) {

          # sorting per hmcr
          if ( $yaxis =~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)                                                   Fix\\l\\\"";
          }
          if ( $yaxis =~ m/r/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)                                              SMT  Fix\\l\\\"";
          }
          if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated) \\l\\\"";
          }
        }
        else {
          # sorting per server
          if ( $yaxis =~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)                               avrg      max       Fix\\l\\\"";
          }
          if ( $yaxis =~ m/r/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)                               avrg      max  SMT  Fix\\l\\\"";
          }
          if ( $yaxis !~ m/r/ && $yaxis !~ m/w/ ) {
            $cmd .= " COMMENT:\\\"  Server - LPAR (will be migrated)  \\l\\\"";
          }
        }
      }
    }
  }

  print OUT "88 $name - $indx - $start - $end\n" if ( $DEBUG == 2 );

#############################
  # main loop through all lpars
#############################

  my $color_indx = 0;    # must be independent from $i --> 3.64 change

  $i = -1;
  foreach my $hmc (@hmc_all) {
    $i++;
    my $managedname = @managedname_all[$i];
    my $lpar        = @lpar_all[$i];
    $cpu_ghz = @cpu_ghz_all[$i];
    $cores   = @cores_all[$i];
    $cores =~ s/ //g;
    my $smt_real = -1;

    my $rperf_tmp = get_rperf_one( @rperf_all[$i], -1, $cores, $yaxis );    # SMT8 prefered, default
    my ( $rperf, $smt ) = split( /:/, $rperf_tmp );
    if ( $rperf == -1 ) {
      if ( $yaxis =~ m/w/ && $yaxis =~ m/r/ ) {
        error( "Cannot find rperf for $hmc:$managedname:$lpar:$cpu_ghz:$cores:$yaxis " . __FILE__ . ":" . __LINE__ );
        next;
      }
    }
    my $smt_act = get_smt_details( $inputdir, $managedname, $lpar );
    if ( $smt_act > -1 && $smt_act != $smt ) {

      # SMT has been found in OS agent data (OS agent 4.70.7+)
      $rperf_tmp = get_rperf_one( @rperf_all[$i], $smt_act, $cores, $yaxis );
      my ( $rperf_smt, $smt_tmp ) = split( /:/, $rperf_tmp );
      if ( $rperf_smt > -1 ) {
        $rperf = $rperf_smt;    # use real SMT obtained from the OS agent
      }
      else {
        # There is no rperf data for actual SMT, it will be printed out in the graph
        $smt_real = $smt_act;
      }
    }

    if ( $yaxis =~ m/w/ ) {
      $smt = "";
    }
    if ( $yaxis !~ m/w/ && $yaxis !~ m/r/ ) {
      $rperf = 1;
    }

    #print STDERR "011 @rperf_all[$i] - $cores - $rperf - $smt\n";
    my $file = "";
    if ( $type =~ "d" ) {
      $file = $lpar . ".rrd";
      if ( !-f "$wrkdir/$managedname/$hmc/$file" ) {

        # IVM & SDMC daily stats are here
        $file = $lpar . ".rrm";
        if ( !-f "$wrkdir/$managedname/$hmc/$file" ) {
          print OUT " does not exists $wrkdir/$managedname/$hmc/$file and even .rrd\n" if ( $DEBUG == 2 );
          next;
        }
      }
    }
    if ( ( $type =~ "h" ) || ( $type =~ "m" ) || ( $type =~ "n" ) ) {
      $file = $lpar . ".rrm";
      if ( !-f "$wrkdir/$managedname/$hmc/$file" ) {
        $file = $lpar . ".rrh";
        if ( !-f "$wrkdir/$managedname/$hmc/$file" ) {
          print OUT " does not exists $wrkdir/$managedname/$hmc/$file and even .rrm\n" if ( $DEBUG == 2 );
          next;
        }
      }
    }

    #print STDERR "lpar-list-rep.pl 739 $hmc $managedname $lpar : $rperf_act : $cpu_ghz : $cores\n";
    # print STDERR "lpar-list-rep.pl 739 $hmc $managedname $lpar\n";
    print OUT "88 $hmc $managedname $lpar $file\n" if ( $DEBUG == 2 );

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = ( stat("$wrkdir/$managedname/$hmc/$file") )[9];
    if ( $rrd_upd_time < $start_unix ) {
      next;
    }

    if ( $sort_order =~ m/lpar/ ) {

      # sorting per lpar
      $name_all = $lpar . " - " . $managedname;
    }
    else {
      if ( $sort_order =~ m/hmc/ ) {

        # sorting per hmcr
        $name_all = $managedname . " - " . $lpar;
      }
      else {
        # sorting per server
        $name_all = $managedname . " - " . $lpar;
      }
    }

    # add spaces to lpar name to have 60 chars total (for formating graph legend)
    my $name_all_slash = $name_all;
    $name_all_slash =~ s/\&\&1/\//g;
    for ( my $k = length($name_all_slash); $k < $legent_length; $k++ ) {
      $name_all_slash .= " ";
    }

    # find our rPerf --> it is already just, just assure everything is ok
    if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {
      if ( $rperf eq '' || $cpu_ghz eq '' || $cores eq '' ) {
        err_html( "could not found rPerf: $hmc:$managedname:$lpar $rperf:$cpu_ghz:$cores " . __FILE__ . ":" . __LINE__ );

        # it exit before in case of any problem in finding rperf
      }

      # fill in server legend table
      $rperf_legend[$rperf_legend_count] = $managedname . "||" . $rperf . "|" . $cpu_ghz . "|" . $cores;
      $rperf_legend_count++;

      #print STDERR "89 $hmc $managedname $lpar : $rperf : $cpu_ghz : $cores -- $rperf_legend_count\n";
    }
    my $rrd_target = "$wrkdir/$managedname/$hmc/$file";
    $rrd_target     =~ s/:/\\:/g;
    $name_all_slash =~ s/:/\\:/g;

    # bulid RRDTool cmd
    $cmd .= " DEF:cap${i}=\\\"$rrd_target\\\":capped_cycles:AVERAGE";
    $cmd .= " DEF:uncap${i}=\\\"$rrd_target\\\":uncapped_cycles:AVERAGE";
    $cmd .= " DEF:ent${i}=\\\"$rrd_target\\\":entitled_cycles:AVERAGE";
    $cmd .= " DEF:cur${i}=\\\"$rrd_target\\\":curr_proc_units:AVERAGE";
    $cmd .= " CDEF:tot${i}=cap${i},uncap${i},+";
    $cmd .= " CDEF:util${i}=tot${i},ent${i},/";
    if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {

      # rPerf
      $cmd .= " CDEF:utiltotu_n${i}=util${i},cur${i},*";
      $cmd .= " CDEF:utiltotu${i}=utiltotu_n${i},$rperf,*";
    }
    else {
      $cmd .= " CDEF:utiltotu${i}=util${i},cur${i},*";
    }
    $cmd       .= " CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF";
    $cmd       .= " $gtype:utiltot${i}$color[$color_indx]:\\\"$name_all_slash\\\"";
    $cmd_xport .= "\\\"DEF:cap${i}=$rrd_target:capped_cycles:AVERAGE\\\"\n";
    $cmd_xport .= "\\\"DEF:uncap${i}=$rrd_target:uncapped_cycles:AVERAGE\\\"\n";
    $cmd_xport .= "\\\"DEF:ent${i}=$rrd_target:entitled_cycles:AVERAGE\\\"\n";
    $cmd_xport .= "\\\"DEF:cur${i}=$rrd_target:curr_proc_units:AVERAGE\\\"\n";
    $cmd_xport .= "\\\"CDEF:tot${i}=cap${i},uncap${i},+\\\"\n";
    $cmd_xport .= "\\\"CDEF:util${i}=tot${i},ent${i},/\\\"\n";
    $cmd_xport .= "\\\"CDEF:utiltotu${i}=util${i},cur${i},*\\\"\n";
    $cmd_xport .= "\\\"CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF\\\"\n";
    $cmd_xport .= "\\\"XPORT:utiltot${i}:$name_all_slash\\\"\n";

    my $smt_real_text = "";

    if ( $smt_real > -1 && $yaxis =~ m/r/ ) {
      $smt_real      = $smt_real;
      $smt_real_text = "(real SMT is $smt_real)";
    }

    if ( $yaxis =~ m/w/ ) {
      $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%7.0lf \\t\\\"";
      $cmd .= " GPRINT:utiltot${i}:MAX:\\\"%7.0lf \\l\\\"";
    }
    else {
      $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%4.1lf \\t\\\"";
      $cmd .= " GPRINT:utiltot${i}:MAX:\\\"%4.1lf   $smt  $smt_real_text $srcfix\\l\\\"";

      # print STDERR "872 \$smt $smt \$smt_real_text $smt_real_text \$srcfix $srcfix\n";
    }

    $gtype = "STACK";

    $color_indx++;
    if ( $color_indx > $color_max ) {
      $color_indx = 0;
    }

  }

  # section used only for CPU workload estimator (add as first CPU pool)
  # max pool legend on the bottom of the graph

  if ( !$pool eq '' ) {
    $i = 0;
    if ( $lpar_pool =~ "SharedPool[1-9]" || $lpar_pool =~ "SharedPool[1-9][0-9]" ) {
      $cmd .= " COMMENT:\\\" \\l\\\"";
      $cmd .= " COMMENT:\\\"CPU pool limit for\\: $managedname_pool / $sh_pool_name\\l\\\"";
      if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {

        # rPerf
        $cmd .= " CDEF:max_n${i}=max${i},$rperf_pool_act,*";
        $cmd .= " CDEF:res_n${i}=res${i},$rperf_pool_act,*";
      }
      else {
        $cmd .= " CDEF:max_n${i}=max${i},1,*";
        $cmd .= " CDEF:res_n${i}=res${i},1,*";
      }
      $cmd .= " LINE2:max_n${i}#000000:\\\"$max_cpu_txt\\\"";
      $cmd .= " GPRINT:max_n${i}:AVERAGE:\\\"%2.1lf\\l\\\"";
      $cmd .= " LINE2:res_n${i}#444444:\\\"$res_cpu_txt\\\"";
      $cmd .= " GPRINT:res_n${i}:AVERAGE:\\\"%2.1lf\\l\\\"";
    }
    else {
      ( my $mod, my $typ, my $cpu ) = split( / /, $managedname_pool );
      my $new_srv_name = "IBM Power $typ (model $mod)";
      for ( my $k = length($new_srv_name); $k < $legent_length; $k++ ) {
        $new_srv_name .= " ";
      }
      if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {

        # rPerf
        if ( $newsrv == 0 ) {
          $cmd .= " CDEF:cpu_n${i}=totcpu${i},$rperf_pool_act,*";
          $cmd .= " COMMENT:\\\" \\l\\\"";
          $cmd .= " COMMENT:\\\"CPU pool limits for\\: $managedname_pool / Number of CPU cores in $sh_pool_name\\: \\\"";
          $cmd .= " GPRINT:totcpu${i}:AVERAGE:\\\"%3.1lf\\l\\\"";
          $cmd .= " LINE3:cpu_n${i}#000000:\\\"$max_cpu_txt\\\"";
          $cmd .= " GPRINT:cpu_n${i}:AVERAGE:\\\"%4.0lf\\l\\\"";
        }
        else {
          $cmd .= " COMMENT:\\\" \\l\\\"";
          my $rperf_act = "";
          if ( $yaxis =~ m/w/ ) {
            $cmd .= " COMMENT:\\\"CPU limit for target server\\:                                       $unit  \\l\\\"";
            $rperf_act = get_rperf_one( $rperf_pool, 1, $cpu, $yaxis );
            if ( $rperf_act == -1 ) {
              error( "Cannot find rperf for $managedname_pool:$cpu:$yaxis " . __FILE__ . ":" . __LINE__ );
              next;
            }
            if ( $rperf_act > 0 ) {
              my $cpu_n_unrounded = $cores_pool * $rperf_act;
              my $cpu_space       = sprintf( "%8.0f", $cpu_n_unrounded );
              my $cpu_n           = sprintf( "%.0f",  $cpu_n_unrounded );
              $cmd .= " LINE2:$cpu_n#000000:\\\"$new_srv_name  $cpu_space \\\"";
              $cmd .= " COMMENT:\\\" \\l\\\"";
            }
          }
          if ( $yaxis =~ m/r/ ) {
            $cmd .= " COMMENT:\\\"CPU limit for target server\\:                                       $unit  SMT\\l\\\"";

            # check each SMT and print the line
            $rperf_act = get_rperf_one( $rperf_pool, 8, $cpu, $yaxis );

            #print STDERR "088 $rperf_pool : $rperf_act - $cpu\n";
            if ( $rperf_act > -1 ) {
              my $cpu_n_unrounded = $cores_pool * $rperf_act;
              my $cpu_space       = sprintf( "%8.0f", $cpu_n_unrounded );
              my $cpu_n           = sprintf( "%.0f",  $cpu_n_unrounded );
              $cmd .= " LINE2:$cpu_n#000000:\\\"$new_srv_name  $cpu_space    8 \\\"";
              $cmd .= " COMMENT:\\\" \\l\\\"";
            }
            $rperf_act = get_rperf_one( $rperf_pool, 4, $cpu, $yaxis );
            if ( $rperf_act > -1 ) {
              my $cpu_n_unrounded = $cores_pool * $rperf_act;
              my $cpu_space       = sprintf( "%8.0f", $cpu_n_unrounded );
              my $cpu_n           = sprintf( "%.0f",  $cpu_n_unrounded );
              $cmd .= " LINE2:$cpu_n#000000:\\\"$new_srv_name  $cpu_space    4 \\\"";
              $cmd .= " COMMENT:\\\" \\l\\\"";
            }
            $rperf_act = get_rperf_one( $rperf_pool, 2, $cpu, $yaxis );
            if ( $rperf_act > -1 ) {
              my $cpu_n_unrounded = $cores_pool * $rperf_act;
              my $cpu_space       = sprintf( "%8.0f", $cpu_n_unrounded );
              my $cpu_n           = sprintf( "%.0f",  $cpu_n_unrounded );
              $cmd .= " LINE2:$cpu_n#000000:\\\"$new_srv_name  $cpu_space    2 \\\"";
              $cmd .= " COMMENT:\\\" \\l\\\"";
            }
            $rperf_act = get_rperf_one( $rperf_pool, 0, $cpu, $yaxis );    # single thread
            if ( $rperf_act > -1 ) {
              my $cpu_n_unrounded = $cores_pool * $rperf_act;
              my $cpu_space       = sprintf( "%8.0f", $cpu_n_unrounded );
              my $cpu_n           = sprintf( "%.0f",  $cpu_n_unrounded );
              $cmd .= " LINE2:$cpu_n#000000:\\\"$new_srv_name  $cpu_space    0 \\\"";
              $cmd .= " COMMENT:\\\" \\l\\\"";
            }
            $rperf_act = get_rperf_one( $rperf_pool, 1, $cpu, $yaxis );    #default one for old server, no SMT info provided by the IBM
            if ( $rperf_act > 0 ) {
              my $cpu_n_unrounded = $cores_pool * $rperf_act;
              my $cpu_space       = sprintf( "%8.0f", $cpu_n_unrounded );
              my $cpu_n           = sprintf( "%.0f",  $cpu_n_unrounded );
              $cmd .= " LINE2:$cpu_n#000000:\\\"$new_srv_name  $cpu_space \\\"";
              $cmd .= " COMMENT:\\\" \\l\\\"";
            }
          }
        }
      }
      else {
        # CPU cores only
        if ( $newsrv == 0 ) {

          # for a existing server with CPU core yaxis
          $cmd .= " CDEF:cpu_n${i}=cpu${i},1,*";
          $cmd .= " COMMENT:\\\" \\l\\\"";
          $cmd .= " COMMENT:\\\"CPU pool limit for\\: $managedname_pool / $sh_pool_name\\l\\\"";
          $cmd .= " LINE2:cpu_n${i}#000000:\\\"$max_cpu_txt\\\"";
          $cmd .= " GPRINT:cpu_n${i}:AVERAGE:\\\"%4.0lf\\l\\\"";
        }
        else {
          # for a new server with CPU core yaxis
          my $cpu_n = $cores_pool;
          for ( my $k = length($new_srv_name); $k < $legent_length; $k++ ) {
            $new_srv_name .= " ";
          }
          $cmd .= " COMMENT:\\\" \\l\\\"";
          $cmd .= " COMMENT:\\\"CPU pool limits for\\: $managedname_pool / $sh_pool_name\\l\\\"";
          $cmd .= " LINE2:$cpu_n#000000:\\\"$new_srv_name   $cpu_n\\\"";
        }
      }
    }

    if ( $yaxis =~ m/w/ || $yaxis =~ m/r/ ) {

      # append there server legend : server: cores x GHZ, rPerf/core ..."
      $cmd .= " COMMENT:\\\" \\l\\\"";
      if ( $yaxis =~ m/w/ ) {
        $cmd .= " COMMENT:\\\"Server details                                            number of cores   GHz        CPW/core\\l\\\"";
      }
      if ( $yaxis =~ m/r/ ) {
        $cmd .= " COMMENT:\\\"Server details                                            number of cores   GHz     rPerf/core\\l\\\"";
      }
      my @servers_used = "";
      my $count_srv    = 0;
      foreach my $liner (@rperf_legend) {

        #print STDERR "$liner \n";
        ( my $server_l, my $lpar_l, my $rperf_l, my $cpu_l, my $cores_l ) = split( /\|/, $liner );

        # Exclde from legent server duplicates
        my $found = 0;
        foreach my $server_used (@servers_used) {
          if ( $server_used =~ m/^$server_l$/ ) {
            $found = 1;
            last;
          }
        }
        if ( $found == 1 ) {
          next;
        }
        @servers_used[$count_srv] = $server_l;
        $count_srv++;

        if ( $newsrv == 1 && $count_srv == 1 ) {

          # decode server type if it is a new server
          ( my $mod, my $typ, my $cpu ) = split( / /, $managedname_pool );
          $server_l = "IBM Power $typ (target)";
        }

        my $rperf_dec = 0;
        if ( $yaxis =~ m/w/ ) {
          $rperf_dec = sprintf( "%7.0f", $rperf_l );
        }
        else {
          $rperf_dec = sprintf( "%4.1f", $rperf_l );
        }
        my $cores_dec = sprintf( "%4.0f", $cores_l );
        for ( my $k = length($server_l); $k < $legent_length + 2; $k++ ) {
          $server_l .= " ";
        }
        for ( my $k = length($cpu_l); $k < 7; $k++ ) {
          $cpu_l .= " ";
        }
        $cores_l =~ s/ //g;
        my $cpu_l = sprintf( "%-5s", $cpu_l );
        $server_l =~ s/:/\\:/g;
        $cmd .= " COMMENT:\\\"$server_l $cores_dec         $cpu_l    $rperf_dec\\l\\\"";
      }
    }
  }

  if ($j) {
    $cmd .= " COMMENT:\\\" \\l\\\"";
  }
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000"; --> it is causing sigsegv on linuxes
  $cmd       =~ s/\\"/"/g;
  $cmd_xport =~ s/\\"/"/g;

  if ($xport) {
    print "Content-Disposition: attachment;filename=\"aggregated.csv\"\n\n";
    RRDp::cmd qq(xport $showtime
		"--start" "$start"
		"--end" "$end"
		"--step" "$step"
		"--maxrows" "128000"
		$cmd_xport
);
    my $ret = RRDp::read;

    #print OUT "---- $ret\n +++ $cmd_xport";
    my $tmp_file = "/var/tmp/lpar2rrd.tmp-$$";
    my $FH;
    open( FH, "> $tmp_file" ) || die "$act_time: Can't open $tmp_file : $!";
    print FH "$$ret";
    close(FH);

    open( FH, "< $tmp_file" ) || die "$act_time: Can't open $tmp_file : $!";
    my $out     = 0;
    my $out_txt = "";
    while ( my $line = <FH> ) {
      if ( $out == 0 ) {
        if ( $line =~ m/xml version=/ ) {
          $out_txt .= $line;
          $out = 1;
        }
      }
      else {
        if ( $line !~ m/^OK u:/ ) {
          $out_txt .= $line;
        }
      }
    }
    close(FH);
    unlink("$tmp_file");

    #print OUT "--xport $out_txt\n";
    #print OUT "++xport $$ret\n";
    xport_print( $out_txt, 1 );
  }
  else {
    # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way

    my $tmp_file = "/var/tmp/lpar2rrd.tmp-$$";
    my $FH;
    open( FH, "> $tmp_file" ) || die "$act_time: Can't open $tmp_file : $!";
    print FH "$cmd\n";
    close(FH);
    my $ret = `$rrdtool - < "$tmp_file" 2>&1`;
    if ( $ret =~ "ERROR" ) {
      error("Multi graph rrdtool error : $ret");
      error("$cmd");
      print OUT "Multi graph rrdtool error : $ret" if ( $DEBUG == 2 );
    }
    unlink("$tmp_file");
  }
  close(OUT) if ( $DEBUG == 2 );
  return 0;
}

sub rperf_not_found {
  my $server = shift;
  print "<br><br><center><strong>rPerf has not been found for server : $server</strong>\n";
  print "</body></html>";

  return 0;
}

# do not use it, it has to create an image
# fake rrdtool file and comment??
# --> find out a
sub err_html {
  my $text = shift;
  my $name = "$inputdir/html/error.png";

  error($text);
  if ( !$xport ) {
    open( PNG, "< $name" ) || die "Cannot open  $name: $!";
    binmode(PNG);
    while ( read( PNG, $b, 4096 ) ) {
      print "$b";
    }
  }

  exit 1;
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

  if ( !defined($digit) || $digit eq '' ) {
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

# Apache has for HTTP GET length hardcoded limitation 8kB
# This make it smaller abou 10x what allows to pass about 1000 lpars in the URL!
# It uses external "gzip" on purpose to do not require any additional Perl module
# as it is not used very frequently then it should not be a problem ...

sub decompress_base64 {
  my $string      = shift;
  my $tmp_file    = "/var/tmp/lpar2rrd_cwe_out.$$";
  my $tmp_file_gz = $tmp_file . ".gz";

  open( FTR, "> $tmp_file_gz" ) || err_html( "Cannot open  $tmp_file_gz: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  binmode(FTR);
  print FTR decode_base64($string);
  close(FTR);
  `gunzip $tmp_file_gz`;

  open( FTR, "< $tmp_file" ) || err_html( "Cannot open  $tmp_file: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  binmode(FTR);
  read( FTR, $string, 1024000 );    #read 1MB block just to be sure, it is big big enough ...
  close(FTR);
  unlink("$tmp_file");
  unlink("$tmp_file_gz");           # just to be sure ...
                                    #`echo "$encoded" > /tmp/xx888`;

  return $string;
}

# find out preferable rperf
sub get_rperf_one {
  my ( $rperf_pool_list, $smt, $cores_passed, $yaxis ) = @_;

  # $smt = -1 --> print the highes  (STM8) if available)

  my ( $cores, $rperf, $rperf_st, $rperf_smt2, $rperf_smt4, $rperf_smt8 ) = split( /:/, $rperf_pool_list );

  if ( isdigit($cores_passed) == 1 && $cores_passed > 0 ) {
    $cores = $cores_passed;
  }
  else {
    if ( !isdigit($cores) || $cores == 0 ) {
      return -1;
    }
  }

  if ( $yaxis =~ m/w/ ) {
    if ( isdigit($rperf) == 1 ) {
      return sprintf( "%.1f", $rperf / $cores ) . ":8";
    }
    else {
      return -1;
    }
  }

  if ( $smt == -1 ) {
    if ( isdigit($rperf_smt8) ) {
      return sprintf( "%.1f", $rperf_smt8 / $cores ) . ":8";
    }
    if ( isdigit($rperf_smt4) ) {
      return sprintf( "%.1f", $rperf_smt4 / $cores ) . ":4";
    }
    if ( isdigit($rperf_smt2) ) {
      return sprintf( "%.1f", $rperf_smt2 / $cores ) . ":2";
    }
    if ( isdigit($rperf_st) ) {
      return sprintf( "%.1f", $rperf_st / $cores ) . ":0";
    }
    if ( isdigit($rperf) ) {
      return sprintf( "%.1f", $rperf / $cores ) . ":1";
    }
  }

  if ( $smt == 8 ) {
    if ( isdigit($rperf_smt8) ) {
      return sprintf( "%.1f", $rperf_smt8 / $cores );
    }
    else {
      return -1;
    }
  }
  if ( $smt == 4 ) {
    if ( isdigit($rperf_smt4) ) {
      return sprintf( "%.1f", $rperf_smt4 / $cores );
    }
    else {
      return -1;
    }
  }
  if ( $smt == 2 ) {
    if ( isdigit($rperf_smt2) ) {
      return sprintf( "%.1f", $rperf_smt2 / $cores );
    }
    else {
      return -1;
    }
  }
  if ( $smt == 0 ) {
    if ( isdigit($rperf_st) ) {
      return sprintf( "%.1f", $rperf_st / $cores );
    }
    else {
      return -1;
    }
  }
  if ( $smt == 1 ) {
    if ( isdigit($rperf) ) {
      return sprintf( "%.1f", $rperf / $cores );
    }
    else {
      return -1;
    }
  }
  return -1;
}

# it returns SMT detail if the OS agent provides it (4.70.7+)
sub get_smt_details {
  my ( $inputdir, $server, $lpar ) = @_;

  my $server_space = $server;
  my $lpar_space   = $lpar;

  # check if exists data/server/hmc/lpar/cpu.txt where the OS agent saves SMT
  if ( $server =~ m/ / ) {
    $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
  }
  if ( $lpar =~ m/ / ) {
    $lpar_space = "\"" . $lpar . "\"";        # it must be here to support space with server names
  }

  my @cpu_files = <$inputdir/data/$server_space/*/$lpar_space/cpu.txt>;
  foreach my $cpu_file (@cpu_files) {
    chomp($cpu_file);
    open( FHCPU, "< $cpu_file" ) || error( "Can't open $cpu_file : $!" . __FILE__ . ":" . __LINE__ );
    my @smt = <FHCPU>;
    close(FHCPU);
    foreach my $line (@smt) {
      chomp($line);
      if ( isdigit($line) ) {
        return $line;
      }
    }
  }

  return -1;
}

sub file_read {
  my $file = shift;
  my $IO;
  if ( !open $IO, '<:encoding(UTF-8)', $file ) {
    warn "Cannot open $file for input: $!";
    exit;
  }
  my @data = <$IO>;
  close $IO;
  wantarray ? @data : join( '' => @data );
}

