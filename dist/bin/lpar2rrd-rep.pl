# Servers' historical reports
# Global reports for lpars too
# Linux historical reports csv too
# hyperv historical reports csv too
# creates graphs & csv

use strict;
use warnings;

#use lib qw (/opt/freeware/lib/perl/5.8.0);
# no longer need to use "use lib qw" as the library PATH is already in PERL5LIB (lpar2rrd.cfg)

use Env qw(QUERY_STRING);
use Date::Parse;
use POSIX qw(strftime);
use RRDp;
use Data::Dumper;
use XoruxEdition;

#$QUERY_STRING .= ":.";

my $inputdir       = $ENV{INPUTDIR};
my $webdir         = $ENV{WEBDIR};
my $bindir         = $ENV{BINDIR};
my $tmpdir         = $ENV{TMPDIR_LPAR};
my $rrdtool        = $ENV{RRDTOOL};
my $pic_col        = $ENV{PICTURE_COLOR};
my $wrkdir         = "$inputdir/data";
my $step           = $ENV{SAMPLE_RATE};
my $DEBUG          = $ENV{DEBUG};
my $errlog         = $ENV{ERRLOG};
my $lpm            = $ENV{LPM};
my @lpm_excl_vio   = "";
my $cpu_max_filter = 100;                   # max 10k peak in % is allowed (in fact it cann by higher than 1k now when 1 logical CPU == 0.1 entitlement
my $act_unix       = time();

if ( defined $ENV{CPU_MAX_FILTER} ) {
  $cpu_max_filter = $ENV{CPU_MAX_FILTER};
}

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

my $vmware = 0;

open( OUT, ">> $errlog" ) if $DEBUG == 2;

#open(OUT, ">> /tmp/e11");

# keep here green - yellow - red - blue ...
my @color     = ( "#FF0000", "#0000FF", "#8fcc66", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#FF00FF", "#800080", "#FDD017", "#0000A0", "#3BB9FF", "#008000", "#800000", "#C0C0C0", "#ADD8E6", "#F778A1", "#800517", "#736F6E", "#F52887", "#C11B17", "#5CB3FF", "#A52A2A", "#FF8040", "#2B60DE", "#736AFF", "#1589FF", "#98AFC7", "#8D38C9", "#307D7E", "#F6358A", "#151B54", "#6D7B8D", "#33cc33", "#FF0080", "#F88017", "#2554C7", "#00a900", "#D4A017", "#306EFF", "#151B8D", "#9E7BFF", "#EAC117", "#99cc00", "#15317E", "#6C2DC7", "#FBB917", "#86b300", "#15317E", "#254117", "#FAAFBE", "#357EC7", "#4AA02C", "#38ACEC" );
my $color_max = 53;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     # 0 - 53 is 54 colors

( my $hmc, my $managedname_all, my $lpar_all, my $shour, my $smon, my $sday, my $syear, my $ehour, my $emon, my $eday, my $eyear, my $type, my $rrdheight, my $rrdwidth, my $yaxis, my $xport, my $lparform ) = split( /&/, $QUERY_STRING );

# print STDERR "68 lpar2rrd-rep.pl $0: $QUERY_STRING\n";
# in case vmware > $lparform is used to send $item
# in case OS agent > $lparform is used to send $item
#print STDERR"$hmc, my $managedname_all, my $lpar_all, my $shour, my $smon, my $sday, my $syear, my $ehour, my $emon, my $eday, my $eyear, my $type, my $rrdheight, my $rrdwidth, my $yaxis, my $xport, my $lparform\n";
$hmc       =~ s/hmc=//;
$hmc       =~ s/host=//;
$hmc       =~ tr/+/ /;
$hmc       =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/seg;
$shour     =~ s/shour=//;
$smon      =~ s/smon=//;
$sday      =~ s/sday=//;
$syear     =~ s/syear=//;
$ehour     =~ s/ehour=//;
$emon      =~ s/emon=//;
$eday      =~ s/eday=//;
$eyear     =~ s/eyear=//;
$type      =~ s/type=//;
$rrdheight =~ s/height=//;
$rrdwidth  =~ s/width=//;
$xport     =~ s/xport=//;
$yaxis     =~ s/yaxis=//;
if ( !defined $lparform ) { $lparform = "" }
;    # not present when CSV export or so
$lparform =~ s/lparform=//;

if ( isdigit($type) == 1 ) {

  # since 4.66 there is passed step and $type is always "m"
  $step = $type;
  $type = "m";
}
else {
  $type = "m";
}

# XPORT is export to XML and then to CVS
my $showtime = "";
if ($xport) {

  # It should be here to do not influence normal report when XML is not in Perl
  require "$bindir/xml.pl";

  # use XML::Simple; --> it has to be in separete file
  print "Content-type: application/octet-stream\n";

  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $showtime = " --showtime";
  }
}
else {
  print "Content-type: image/png\n";
  print "Cache-Control: max-age=60, public\n\n";    # workaround for caching on Chrome
}

print OUT "-- $QUERY_STRING\n" if $DEBUG == 2;

# decode lpar value, there might be special characters in URL format
$lpar_all =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;    # it must be here and even below (? but why?)
$lpar_all =~ s/\+/ /g;

#  $lpar_all =~ s/\//\&\&1/g; not now > after splitting
$lpar_all =~ s/\&\&1/\//g;
my %inp   = ();
my @pairs = split( /&/, $lpar_all );
foreach my $pair (@pairs) {
  $pair =~ s/\//\&\&1/g;
  chomp($pair);
  ( my $name, my $value ) = split( /=/, $pair );
  $value =~ s/ \[.*\]//g;    # remove alias info
  $inp{$name} = $value;
}
my $lpar = $inp{'lpar'};

#$lpar =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
#$lpar =~ s/\+/ /g;
#$lpar =~ s/\//\&\&1/g;

# decode managedname value, there might be special characters in URL format
$managedname_all =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;    # it must be here and even below (? but why?)
@pairs = split( /&/, $managedname_all );
foreach my $pair (@pairs) {
  ( my $name, my $value ) = split( /=/, $pair );
  $value =~ tr/+/ /;
  $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  $inp{$name} = $value;
}
my $managedname = $inp{'mname'};
$managedname =~ s/\+/ /g;

my $start_unix  = str2time( $syear . "-" . $smon . "-" . $sday . " " . $shour . ":00:00" );
my $end_unix    = str2time( $eyear . "-" . $emon . "-" . $eday . " " . $ehour . ":00:00" );
my $human_start = $shour . ":00:00 " . $sday . "." . $smon . "." . $syear;
my $human_end   = $ehour . ":00:00 " . $eday . "." . $emon . "." . $eyear;
my $start       = $shour . ":00 " . $sday . "." . $smon . "." . $syear;
my $end         = "";

# workaround for 24:00. If is used proper 00:00 of the next day then there are 2 extra records in cvs after the midnight
# looks like rrdtool issue
if ( $ehour == 24 ) {
  $end = "23:58 " . $eday . "." . $emon . "." . $eyear;
}
else {
  $end = $ehour . ":00 " . $eday . "." . $emon . "." . $eyear;
}

# check if eunix time is not higher than actual unix time
if ( defined $end_unix && isdigit($end_unix) && $end_unix > $act_unix ) {
  my $date_human = strftime( "%H:%M %d.%m.%Y", localtime($act_unix) );
  $end_unix = $act_unix;      # if eunix higher than act unix - set it up to act unix
  $end      = $date_human;    # date higher than actual_date
}

# print STDERR "155 $lpar lpar2rrd-rep.pl $hmc $managedname $human_start $human_end $start $end $type : $start_unix - $end_unix xport=$xport\n";
print OUT "$lpar $hmc $managedname $human_start $human_end $start $end $type : $start_unix - $end_unix xport=$xport\n" if $DEBUG == 2;

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
if ( $lpar =~ /Solaris/ ) {
  draw_graph_solaris( $lpar, $managedname );
}
else {
  draw_graph( $lpar, $managedname );
}

# close RRD pipe
RRDp::end;

# exclude Export here
if ( !$xport ) {
  print_png();
}

exit(0);

sub xport_file {

  # params: $rrd, <DS_name in $rrd, heading for CSV column> unlimited number of pairs
  # if 2nd par as "" > heading is as DS_name;  the same when last 2nd lpar is omitted
  # global vars: $start $end $step

  my $cmd = "xport $showtime --start \"$start\" --end \"$end\" --step $step --maxrows 128000";
  my $rrd = shift @_;
  my $i   = 0;
  $rrd =~ s/:/\\:/g;
  while ( my $ds_name = shift @_ ) {
    my $csv_heading = shift @_;
    if ( !defined $csv_heading || $csv_heading eq "" ) { $csv_heading = $ds_name }
    $cmd .= " DEF:ds${i}=\"$rrd\":$ds_name:AVERAGE";
    $cmd .= " XPORT:ds${i}:$csv_heading";
    $i++;
  }
  my $answer;
  eval {
    RRDp::cmd qq($cmd);
    $answer = RRDp::read;
  };
  if ($@) {
    error( "xport rrdtool error : $@ " . __FILE__ . ":" . __LINE__ );
    return;
  }
  $$answer =~ s/.*\n.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
  xport_print( $answer, 0 );

  return;
}

sub draw_graph_solaris {
  my ( $lpar, $managedname ) = @_;
  my $t        = "COMMENT: ";
  my $t2       = "COMMENT:\\n";
  my $last     = "COMMENT: ";
  my $lpar_gen = $lpar;

  my $header = "$managedname : $human_start : $human_end";

  print OUT "creating graph : $hmc:$managedname:$lpar:$type\n" if $DEBUG == 2;

  print "Graph solaris :$lpar|$managedname\n";
  my $rrd = "$wrkdir/Solaris/$lpar";
  $rrd =~ s/:/\\:/g;

  #print STDERR"$rrd\n";
}

sub draw_graph {
  my ( $lpar, $managedname ) = @_;
  my $t        = "COMMENT: ";
  my $t2       = "COMMENT:\\n";
  my $last     = "COMMENT: ";
  my $lpar_gen = $lpar;

  if ( $lpar =~ "multiview" ) {
    $lpar_gen = "pool";
  }
  if ( $type =~ "d" ) {
    if ( !-f "$wrkdir/$managedname/$hmc/$lpar_gen.rr$type" ) {
      $type = "m";
    }
    if ( !-f "$wrkdir/$managedname/$hmc/$lpar_gen.rr$type" ) {
      $type = "h";
    }
  }
  else {
    if ( $type =~ "m" ) {
      if ( !-f "$wrkdir/$managedname/$hmc/$lpar_gen.rr$type" ) {
        $type = "h";
      }
    }
    else {
      if ( $type =~ "n" ) {
        $type = "m";
        if ( !-f "$wrkdir/$managedname/$hmc/$lpar_gen.rr$type" ) {
          $type = "h";
        }
      }
      else {
        if ( $type =~ "h" ) {
          if ( !-f "$wrkdir/$managedname/$hmc/$lpar_gen.rr$type" ) {
            $type = "m";
          }
        }
      }
    }
  }

  # testing vmware through $lparform
  # print STDERR "228 lpar2rrd-rep.pl $wrkdir//$managedname//$hmc//$lpar \$lparform $lparform\n";

  if ( defined $lparform ) {    # probably vmware - only for CSV report
                                #("clustser" eq $lparform") && do {
                                #  my $header = "LPARs aggregated: $human_start - $human_end";
                                #  print STDERR "creating mgraph: $hmc:$managedname:multi:$type\n" ;
                                #  multiview($name,time(),$managedname,$start,$end,$header,$start_unix,$end_unix);
                                #  return;
                                #}
    ( "clustcpu" eq $lparform || "clustmem" eq $lparform || "clustpow" eq $lparform ) && do {
      my $rrd = "$wrkdir/$managedname/$hmc/cluster.rrc";
      error( "CSV graph error : file $rrd does not exist " . __FILE__ . ":" . __LINE__ ) if !-f $rrd;
      print "Content-Disposition: attachment;filename=\"$managedname\_$hmc\_cluster.csv\"\n\n";
      ( "clustcpu" eq $lparform ) && xport_file( $rrd, "CPU_total_MHz",    "", "CPU_usage_MHz" );
      ( "clustmem" eq $lparform ) && xport_file( $rrd, "Memory_total_MB",  "", "Memory_granted_KB", "", "Memory_consumed_KB", "", "Memory_active_KB", "", "Memory_baloon_KB", "", "Memory_swap_KB" );
      ( "clustpow" eq $lparform ) && xport_file( $rrd, "Power_usage_Watt", "", "Power_cup_Watt" );
      return;
    };
    ( "rpcpu" eq $lparform || "rpmem" eq $lparform ) && do {
      my $rrd = "$wrkdir/$managedname/$hmc/$lpar.rrc";
      error( "CSV graph error : file $rrd does not exist " . __FILE__ . ":" . __LINE__ ) if !-f $rrd;
      print "Content-Disposition: attachment;filename=\"$managedname\_$hmc\_$lpar.csv\"\n\n";
      ( "rpcpu" eq $lparform ) && xport_file( $rrd, "CPU_usage_MHz", "", "CPU_limit", "", "CPU_reservation" );
      ( "rpmem" eq $lparform ) && xport_file( $rrd, "Memory_reservation", "", "Memory_granted_KB", "", "Memory_consumed_KB", "", "Memory_active_KB", "", "Memory_baloon_KB", "", "Memory_swap_KB", "", "Memory_limit" );
      return;
    };
    ( 'vmware_VMs' eq $managedname ) && do {
      my $rrd = "$wrkdir/$managedname/$lpar.rrm";
      error( "CSV graph error : file $rrd does not exist " . __FILE__ . ":" . __LINE__ ) if !-f $rrd;
      print "Content-Disposition: attachment;filename=\"$managedname\_$lpar.csv\"\n\n";
      ( "vmw-proc" eq $lparform )  && xport_file( $rrd, "CPU_usage_Proc", "CPU_usage_Proc*100", "vCPU" );
      ( "lpar" eq $lparform )      && xport_file( $rrd, "CPU_Alloc",      "", "CPU_usage",     "", "vCPU" );
      ( "vmw-mem" eq $lparform )   && xport_file( $rrd, "Memory_granted", "", "Memory_baloon", "", "Memory_active" );
      ( "vmw-disk" eq $lparform )  && xport_file( $rrd, "Disk_usage" );
      ( "vmw-net" eq $lparform )   && xport_file( $rrd, "Network_usage" );
      ( "vmw-swap" eq $lparform )  && xport_file( $rrd, "Memory_swapin", "", "Memory_swapout" );
      ( "vmw-ready" eq $lparform ) && xport_file( $rrd, "CPU_ready_ms" );
      ( "vmw-comp" eq $lparform )  && xport_file( $rrd, "Memory_compres", "", "Memory_decompres" );
      return;
    };
    ( "dsmem" eq $lparform ) && do {
      my $rrd = "$wrkdir/$managedname/$hmc/$lpar.rrs";
      error( "CSV graph error : file $rrd does not exist " . __FILE__ . ":" . __LINE__ ) if !-f $rrd;
      print "Content-Disposition: attachment;filename=\"$managedname\_$hmc\_$lpar.csv\"\n\n";
      ( "dsmem" eq $lparform ) && xport_file( $rrd, "Disk_capacity", "", "Disk_used", "", "Disk_provisioned" );
      return;
    };
    ( "dsrw" eq $lparform || "dsarw" eq $lparform ) && do {
      my $rrd = "$wrkdir/$managedname/$hmc/$lpar.rrt";
      error( "CSV graph error : file $rrd does not exist " . __FILE__ . ":" . __LINE__ ) if !-f $rrd;
      print "Content-Disposition: attachment;filename=\"$managedname\_$hmc\_$lpar.csv\"\n\n";
      ( "dsrw" eq $lparform )  && xport_file( $rrd, "Datastore_read",    "", "Datastore_write" );
      ( "dsarw" eq $lparform ) && xport_file( $rrd, "Datastore_ReadAvg", "", "Datastore_WriteAvg" );
      return;
    };
    ( "dslat" eq $lparform ) && do {
      my $rrd = "$wrkdir/$managedname/$hmc/$lpar.rru";
      error( "CSV graph error : file $rrd does not exist " . __FILE__ . ":" . __LINE__ ) if !-f $rrd;
      print "Content-Disposition: attachment;filename=\"$managedname\_$hmc\_$lpar.csv\"\n\n";
      xport_file( $rrd, "Dstore_readLatency", "", "Dstore_writeLatency" );
      return;
    };
    ( "memalloc" eq $lparform || "vmdiskrw" eq $lparform || "vmnetrw" eq $lparform ) && do {
      my $rrd = "$wrkdir/$managedname/$hmc/pool.rrm";
      error( "CSV graph error : file $rrd does not exist " . __FILE__ . ":" . __LINE__ ) if !-f $rrd;
      print "Content-Disposition: attachment;filename=\"$managedname\_$hmc\_$lpar.csv\"\n\n";
      ( "memalloc" eq $lparform ) && xport_file( $rrd, "Memory_granted",   "", "Memory_baloon", "", "Memory_active", "", "Memory_Host_Size" );
      ( "vmdiskrw" eq $lparform ) && xport_file( $rrd, "Disk_read",        "", "Disk_write" );
      ( "vmnetrw" eq $lparform )  && xport_file( $rrd, "Network_received", "", "Network_transmitted" );
      return;
    };
  }    # end of vmware section
  $lparform =~ s/item=//g;
  if ( $lpar =~ "SharedPool[0-9]" || $lpar =~ "SharedPool[0-9][0-9]" ) {
    my $rrd      = "$wrkdir/$managedname/$hmc/$lpar.rr$type";
    my $lpar_sep = $lpar;
    $lpar_sep =~ s/SharedPool/Shared CPU pool /g;
    my $lpar_out = $lpar_sep;
    $lpar_out =~ s/ /\\/g;

    # add CPU pool alias into png header (if exists and it is not a default CPU pool)
    my $pool_id = $lpar;
    $pool_id =~ s/SharedPool//g;
    my $lpar_pool_alias = "$lpar_sep $pool_id";

    if ( -f "$wrkdir/$managedname/$hmc/cpu-pools-mapping.txt" ) {
      open( FR, "< $wrkdir/$managedname/$hmc/cpu-pools-mapping.txt" );
      foreach my $linep (<FR>) {
        chomp($linep);
        ( my $id, my $pool_name ) = split( /,/, $linep );
        if ( $id == $pool_id ) {
          $lpar_pool_alias = "$pool_name";
          last;
        }
      }
      close(FR);
    }

    my $header = "$managedname : $lpar_pool_alias : $human_start : $human_end";

    print OUT "creating graph : $hmc:$managedname:$lpar:$type\n" if $DEBUG == 2;

    #print "Graph pool :$lpar\n";

    $rrd =~ s/:/\\:/g;

    if ( $lpar =~ "SharedPool[1-9]" || $lpar =~ "SharedPool[1-9][0-9]" ) {
      if ($xport) {
        print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$lpar_out.csv\"\n\n";

        # export selected data into XML
        RRDp::cmd qq(xport $showtime
	"--start" "$start"
	"--end" "$end"
	"--step" "$step"
	"--maxrows" "128000"
	"DEF:max=$rrd:max_pool_units:AVERAGE"
	"DEF:res=$rrd:res_pool_units:AVERAGE"
	"DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
	"DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
	"CDEF:max1=max,res,-"
	"CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
	"CDEF:cpuutiltot=cpuutil,max,*"
	"CDEF:utilisa=cpuutil,100,*"
	"XPORT:res:Reserved CPU cores"
	"XPORT:max1:Max CPU cores"
	"XPORT:cpuutiltot:Utilization in CPU cores"
	);
        my $answer = RRDp::read;
        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
        }
        else {
          $$answer =~ s/.*\n.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
          xport_print( $answer, 0 );
        }
      }
      else {
        RRDp::cmd qq(graph "$name"
	"--title" "$header"
	"--start" "$start"
	"--end" "$end"
	"--imgformat" "PNG"
	"$disable_rrdtool_tag"
	"--slope-mode"
	"--width=$rrdwidth"
	"--height=$rrdheight"
	"--step=$step"
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
	"COMMENT:(CPU utilization "
	"GPRINT:utilisa:AVERAGE: %2.1lf"
	"COMMENT:\%)"
	"$t2"
	"$t"
	"$last"
	"HRULE:0#000000"
	"VRULE:0#000000"
	);
        my $answer = RRDp::read;

        #chomp ($$answer);
      }
    }
    else {
      # except SharedPool0
      if ($xport) {
        print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$lpar_out.csv\"\n\n";

        # export selected data into XML
        RRDp::cmd qq(xport $showtime
		"--start" "$start"
		"--end" "$end"
		"--step" "$step"
		"--maxrows" "128000"
		"DEF:max=$rrd:max_pool_units:AVERAGE"
		"DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
		"DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
		"CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
		"CDEF:cpuutiltot=cpuutil,max,*"
		"CDEF:utilisa=cpuutil,100,*"
		"XPORT:max:Max CPU cores"
		"XPORT:cpuutiltot:Utilization in CPU cores"
	);
        my $answer = RRDp::read;
        if ( $$answer =~ "ERROR" ) {
          error("Rrdtool error : $$answer");
        }
        else {
          $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
          xport_print( $answer, 0 );
        }
      }
      else {
        RRDp::cmd qq(graph "$name"
		"--title" "$header"
		"--start" "$start"
		"--end" "$end"
		"--imgformat" "PNG"
		"$disable_rrdtool_tag"
		"--slope-mode"
		"--width=$rrdwidth"
		"--height=$rrdheight"
		"--step=$step"
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
		"COMMENT:(CPU utilization "
		"GPRINT:utilisa:AVERAGE: %2.1lf"
		"COMMENT:\%)"
		"$t2"
		"$t"
		"$last"
		"$t2"
		"HRULE:0#000000"
		"VRULE:0#000000"
	);
        my $answer = RRDp::read;

        #chomp ($$answer);
      }
    }
  }
  #
  # Only POWER & VMWARE pool
  #
  elsif ( ( $lpar eq "pool" && $managedname ne "windows" ) && ( length($lpar) == 4 ) ) {
    my $rrd    = "$wrkdir/$managedname/$hmc/pool.rr$type";
    my $header = "$managedname : CPU pool : $human_start - $human_end";

    print OUT "creating graph : $hmc:$managedname:$lpar:$type\n" if ( $DEBUG == 2 );

    # print STDERR "528 lpar2rrd-rep.pl creating graph : $hmc:$managedname:$lpar:$type\n" ;
    $rrd =~ s/:/\\:/g;
    if ($xport) {
      print "Content-Disposition: attachment;filename=\"CPU\_pool\_$hmc\_$managedname\_pool.csv\"\n\n";

      # export selected data into XML
      if ( !-f "$wrkdir/$managedname/$hmc/vmware.txt" ) {
        RRDp::cmd qq(xport $showtime
		"--start" "$start"
		"--end" "$end"
		"--step" "$step"
		"--maxrows" "128000"
		"DEF:totcyc=$rrd:total_pool_cycles:AVERAGE"
		"DEF:uticyc=$rrd:utilized_pool_cyc:AVERAGE"
		"DEF:cpu=$rrd:conf_proc_units:AVERAGE"
		"DEF:cpubor=$rrd:bor_proc_units:AVERAGE"
		"CDEF:totcpu=cpu,cpubor,+"
		"CDEF:cpuutil=uticyc,totcyc,GT,UNKN,uticyc,totcyc,/,IF"
		"CDEF:cpuutiltot=cpuutil,totcpu,*"
		"CDEF:utilisa=cpuutil,100,*"
		"XPORT:cpu:Configured CPUu cores    "
		"XPORT:cpubor:Not assigned CPU cores  "
		"XPORT:cpuutiltot:Utilization in CPU cores"
	);
      }
      else {    # vmware pool
        RRDp::cmd qq(xport $showtime
		"--start" "$start"
		"--end" "$end"
		"--step" "$step"
		"--maxrows" "128000"
		"DEF:cpu_entitl_mhz=$rrd:CPU_Alloc:AVERAGE"
		"DEF:utiltot_mhz=$rrd:CPU_usage:AVERAGE"
		"DEF:one_core_hz=$rrd:host_hz:AVERAGE"
		"XPORT:cpu_entitl_mhz:Configured CPU MHz    "
		"XPORT:one_core_hz:One core Hz  "
		"XPORT:utiltot_mhz:Utilization in CPU MHz"
	);
      }
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
    else {
      RRDp::cmd qq(graph "$name"
	"--title" "$header"
	"--start" "$start"
	"--end" "$end"
	"--imgformat" "PNG"
	"$disable_rrdtool_tag"
	"--slope-mode"
	"--width=$rrdwidth"
	"--height=$rrdheight"
	"--step=$step"
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
	"COMMENT:(CPU utilization "
	"GPRINT:utilisa:AVERAGE: %2.1lf"
	"COMMENT:\%)"
	"$t2"
	"$t"
	"$last"
	"HRULE:0#000000"
	"VRULE:0#000000"
	);
      my $answer = RRDp::read;

      #chomp ($$answer);
      #print "answer: $$answer\n" if $$answer;
    }
  }
  elsif ( ( $lpar eq "mem" ) && ( length($lpar) == 3 ) ) {
    my $rrd    = "$wrkdir/$managedname/$hmc/mem.rr$type";
    my $header = "$managedname : Memory usage: $human_start - $human_end";

    print OUT "creating graph : $hmc:$managedname:$lpar:$type\n" if ( $DEBUG == 2 );
    $rrd =~ s/:/\\:/g;
    if ($xport) {
      print "Content-Disposition: attachment;filename=\"Memory\_usage\_$hmc\_$managedname\_mem.csv\"\n\n";

      # export selected data into XML
      if ( !-f "$wrkdir/$managedname/$hmc/vmware.txt" ) {
        RRDp::cmd qq(xport $showtime
		"--start" "$start"
		"--end" "$end"
		"--step" "$step"
		"--maxrows" "128000"
		"DEF:free=$rrd:curr_avail_mem:AVERAGE"
		"DEF:fw=$rrd:sys_firmware_mem:AVERAGE"
		"DEF:tot=$rrd:conf_sys_mem:AVERAGE"
		"CDEF:freeg=free,1024,/"
		"CDEF:fwg=fw,1024,/"
		"CDEF:totg=tot,1024,/"
		"CDEF:used=totg,freeg,-"
		"CDEF:used1=used,fwg,-"
		"XPORT:fwg:Firmware memory"
		"XPORT:used:Used memory"
		"XPORT:freeg:Free memory"
	);
      }
      else {    # vmware mem is in file pool
        $rrd = "$wrkdir/$managedname/$hmc/pool.rrm";
        $rrd =~ s/:/\\:/g;
        RRDp::cmd qq(xport $showtime
		"--start" "$start"
		"--end" "$end"
		"--step" "$step"
		"--maxrows" "128000"
		"DEF:total=$rrd:Memory_Host_Size:AVERAGE"
		"DEF:baloon=$rrd:Memory_baloon:AVERAGE"
		"DEF:granted=$rrd:Memory_granted:AVERAGE"
		"DEF:active=$rrd:Memory_active:AVERAGE"
		"XPORT:total:Total memory B"
		"XPORT:baloon:Baloon memory kB"
		"XPORT:granted:Granted memory kB"
		"XPORT:active:Active memory kB"
	);
      }
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
    else {

      RRDp::cmd qq(graph "$name"
		"--title" "$header"
		"--start" "$start"
		"--end" "$end"
		"--imgformat" "PNG"
		"$disable_rrdtool_tag"
		"--slope-mode"
		"--width=$rrdwidth"
		"--height=$rrdheight"
		"--step=$step"
		"--lower-limit=0"
		"--color=BACK#$pic_col"
		"--color=SHADEA#$pic_col"
		"--color=SHADEB#$pic_col"
		"--color=CANVAS#$pic_col"
		"--vertical-label=Memory in GBytes"
		"--upper-limit=1"
		"--alt-autoscale-max"
		"--base=1024"
		"DEF:free=$rrd:curr_avail_mem:AVERAGE"
		"DEF:fw=$rrd:sys_firmware_mem:AVERAGE"
		"DEF:tot=$rrd:conf_sys_mem:AVERAGE"
		"CDEF:freeg=free,1024,/"
		"CDEF:fwg=fw,1024,/"
		"CDEF:totg=tot,1024,/"
		"CDEF:used=totg,freeg,-"
		"CDEF:used1=used,fwg,-"
		"COMMENT:   Average   \\n"
		"AREA:fwg#0080FF: Firmware memory"
		"GPRINT:fwg:AVERAGE: %4.2lf GB"
		"$t2"
		"STACK:used1#FF4040: Used memory    "
		"GPRINT:used1:AVERAGE: %4.2lf GB"
		"$t2"
		"STACK:freeg#00FF00: Free memory    "
		"GPRINT:freeg:AVERAGE: %4.2lf GB"
		"$t2"
		"$t"
		"HRULE:0#000000"
		"VRULE:0#000000"
	);
      my $answer = RRDp::read;

      #chomp ($$answer);
      #print "answer: $$answer\n" if $$answer;
    }
  }
  elsif ( $lpar =~ m/^multiview$/ ) {
    my $header = "LPARs aggregated: $human_start - $human_end";
    print OUT "creating mgraph: $hmc:$managedname:multi:$type\n" if ( $DEBUG == 2 );
    multiview( $name, time(), $managedname, $start, $end, $header, $start_unix, $end_unix );

  }
  elsif ( $lparform =~ /oscpu|nmon_oscpu/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "";
    if ( $lparform =~ /nmon_oscpu/ ) {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--NMON--";
    }
    else {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";
    }
    my $lpar_test  = basename($lpar_dir);
    my $actual_hmc = active_hmc( $managedname, $lpar, "cpu.mmm" );
    chomp $actual_hmc;
    if ( -d $lpar_dir ) {
      if ( -f "$lpar_dir/cpu.mmm" ) {
        my $cpu_path = "$wrkdir/$managedname/$actual_hmc/$lpar/cpu.mmm";
        my $header   = "$managedname : CPU usage: $human_start - $human_end";
        my $rrd_file = $cpu_path;
        $rrd_file =~ s/:/\\:/g;
        chomp $rrd_file;
        my $rrd = $rrd_file;
        if ($xport) {
          print "Content-Disposition: attachment;filename=\"OS_CPU\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
          RRDp::cmd qq(xport $showtime
          "--start" "$start"
          "--end" "$end"
          "--step" "$step"
          "--maxrows" "128000"
          "DEF:entitled=$rrd:entitled:AVERAGE"
          "DEF:cpusy=$rrd:cpu_sy:AVERAGE"
          "DEF:cpuus=$rrd:cpu_us:AVERAGE"
          "DEF:cpuwa=$rrd:cpu_wa:AVERAGE"
          "CDEF:stog=100,cpusy,-,cpuus,-,cpuwa,-"
          "CDEF:cpusy_res=cpusy,100,*,0.5,+,FLOOR,100,/"
          "CDEF:cpuus_res=cpuus,100,*,0.5,+,FLOOR,100,/"
          "CDEF:cpuwa_res=cpuwa,100,*,0.5,+,FLOOR,100,/"
          "CDEF:stog_res=stog,100,*,0.5,+,FLOOR,100,/"
          "XPORT:cpusy_res:Sys"
          "XPORT:cpuus_res:User"
          "XPORT:cpuwa_res:IO wait"
          "XPORT:stog_res:Idle"
          );
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            #print STDERR "$$answer\n";
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lparform =~ /total_latency/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";

    my $file_name  = "disk-total.mmm";
    my $lpar       = basename($lpar_dir);
    my $actual_hmc = active_hmc( $managedname, $lpar, "$file_name" );
    chomp $actual_hmc;
    if ( -d $lpar_dir ) {
      if ( -f "$lpar_dir/$file_name" ) {
        my $path = "$wrkdir/$managedname/$actual_hmc/$lpar/$file_name";
        print "Content-Disposition: attachment;filename=\"$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
        my $rrd_file = $path;
        $rrd_file =~ s/:/\\:/g;
        chomp $rrd_file;
        my $rrd = $rrd_file;
        if ($xport) {
          RRDp::cmd qq(xport $showtime
          "--start" "$start"
          "--end" "$end"
          "--step" "$step"
          "--maxrows" "128000"
          "DEF:size=$rrd:read_latency:AVERAGE"
          "DEF:used=$rrd:write_latency:AVERAGE"
          "XPORT:size:Read latency"
          "XPORT:used:Write latency"
          );
          my $answer = RRDp::read;

          #print STDERR "$$answer\n";
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lparform =~ /total_data/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";

    my $file_name  = "disk-total.mmm";
    my $lpar       = basename($lpar_dir);
    my $actual_hmc = active_hmc( $managedname, $lpar, "$file_name" );
    chomp $actual_hmc;
    if ( -d $lpar_dir ) {
      if ( -f "$lpar_dir/$file_name" ) {
        my $path = "$wrkdir/$managedname/$actual_hmc/$lpar/$file_name";
        print "Content-Disposition: attachment;filename=\"$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
        my $rrd_file = $path;
        $rrd_file =~ s/:/\\:/g;
        chomp $rrd_file;
        my $rrd = $rrd_file;
        if ($xport) {
          RRDp::cmd qq(xport $showtime
          "--start" "$start"
          "--end" "$end"
          "--step" "$step"
          "--maxrows" "128000"
          "DEF:size=$rrd:read_data:AVERAGE"
          "DEF:used=$rrd:write_data:AVERAGE"
          "XPORT:size:Read data"
          "XPORT:used:Write data"
          );
          my $answer = RRDp::read;

          #print STDERR "$$answer\n";
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lparform =~ /total_iops/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";

    my $file_name  = "disk-total.mmm";
    my $lpar       = basename($lpar_dir);
    my $actual_hmc = active_hmc( $managedname, $lpar, "$file_name" );
    chomp $actual_hmc;
    if ( -d $lpar_dir ) {
      if ( -f "$lpar_dir/$file_name" ) {
        my $path = "$wrkdir/$managedname/$actual_hmc/$lpar/$file_name";
        print "Content-Disposition: attachment;filename=\"$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
        my $rrd_file = $path;
        $rrd_file =~ s/:/\\:/g;
        chomp $rrd_file;
        my $rrd = $rrd_file;
        if ($xport) {
          RRDp::cmd qq(xport $showtime
          "--start" "$start"
          "--end" "$end"
          "--step" "$step"
          "--maxrows" "128000"
          "DEF:size=$rrd:read_iops:AVERAGE"
          "DEF:used=$rrd:write_iops:AVERAGE"
          "XPORT:size:Read IOPS"
          "XPORT:used:Write IOPS"
          );
          my $answer = RRDp::read;

          #print STDERR "$$answer\n";
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lparform =~ /cpu-linux/ ) {    #CPU CORE
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";

    # it is used both POWER & VMWARE linux agent
    my $core_file_name = "queue_cpu_aix.mmm";
    $core_file_name = "linux_cpu.mmm" if $managedname =~ /^Linux|^Solaris/;

    my $lpar       = basename($lpar_dir);
    my $actual_hmc = active_hmc( $managedname, $lpar, $core_file_name );
    chomp $actual_hmc;

    # print STDERR "966 \$actual_hmc ,$actual_hmc,\$lpar_dir $lpar_dir\n";
    if ( -d $lpar_dir ) {
      if ( -f "$lpar_dir/$core_file_name" ) {
        my $path = "$wrkdir/$managedname/$actual_hmc/$lpar/$core_file_name";
        print "Content-Disposition: attachment;filename=\"CPU_CORE\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
        my $rrd_file = $path;
        $rrd_file =~ s/:/\\:/g;
        chomp $rrd_file;
        my $rrd_cpu_linux = $rrd_file;
        my $rrd           = "$wrkdir/$managedname/$actual_hmc/$lpar/cpu.mmm";
        $rrd =~ s/:/\\:/g;
        chomp $rrd;

        if ($xport) {
          RRDp::cmd qq(xport $showtime
              "--start" "$start"
              "--end" "$end"
              "--step" "$step"
              "--maxrows" "128000"

              "DEF:entitled=\"$rrd\":entitled:AVERAGE"
              "DEF:cpusy=\"$rrd\":cpu_sy:AVERAGE"
              "DEF:cpuus=\"$rrd\":cpu_us:AVERAGE"
              "DEF:cpuwa=\"$rrd\":cpu_wa:AVERAGE"

              "DEF:cpucount=\"$rrd_cpu_linux\":cpu_count:AVERAGE"
              "DEF:cpuinmhz=\"$rrd_cpu_linux\":cpu_in_mhz:AVERAGE"
              "DEF:threadscore=\"$rrd_cpu_linux\":threads_core:AVERAGE"
              "DEF:corespersocket=\"$rrd_cpu_linux\":cores_per_socket:AVERAGE"

              "CDEF:cpu_cores=cpucount,100,/"
              "CDEF:stog1=cpusy,cpuus,cpuwa,+,+"
              "CDEF:stog2=cpu_cores,stog1,*"

              "CDEF:cpughz=cpuinmhz,1000,/"
              "CDEF:cpughz1=cpughz,cpucount,*"
              "CDEF:cpu_ghz_one_perc=cpughz1,100,/"
              "CDEF:cpu_ghz_util=cpu_ghz_one_perc,stog1,*"

                "XPORT:cpucount:Cores"
                "XPORT:stog2:GHz"
                );
          my $answer = RRDp::read;

          #print STDERR "$$answer\n";
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lparform =~ /queue_cpu/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";

    # it is used both POWER & VMWARE linux agent
    my $queue_file_name = "queue_cpu_aix.mmm";

    my $lpar       = basename($lpar_dir);
    my $actual_hmc = active_hmc( $managedname, $lpar, $queue_file_name );
    chomp $actual_hmc;

    # print STDERR "966 \$actual_hmc ,$actual_hmc,\$lpar_dir $lpar_dir\n";
    if ( -d $lpar_dir ) {
      my $test_cpu = "$lpar_dir/$queue_file_name";
      if ( !-f $test_cpu ) {
        $test_cpu        = "$lpar_dir/queue_cpu.mmm";
        $queue_file_name = "queue_cpu.mmm";
        $actual_hmc      = active_hmc( $managedname, $lpar, $queue_file_name );
      }
      if ( -f "$test_cpu" ) {
        my $path = "$wrkdir/$managedname/$actual_hmc/$lpar/$queue_file_name";
        print "Content-Disposition: attachment;filename=\"CPU_QUEUE\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
        my $rrd_file = $path;
        $rrd_file =~ s/:/\\:/g;
        chomp $rrd_file;
        my $rrd = $rrd_file;
        if ($xport) {
          RRDp::cmd qq(xport $showtime
          "--start" "$start"
          "--end" "$end"
          "--step" "$step"
          "--maxrows" "128000"
          "DEF:size=$rrd:load:AVERAGE"
          "DEF:used=$rrd:virtual_p:AVERAGE"
          "DEF:free=$rrd:blocked_p:AVERAGE"
          "XPORT:size:Load"
          "XPORT:used:Logical processors"
          "XPORT:free:Blocked processors"
          );
          my $answer = RRDp::read;

          #print STDERR "$$answer\n";
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lparform =~ /^mem$|nmon_mem/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "";
    if ( $lparform =~ /nmon_mem/ ) {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--NMON--";
    }
    else {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";
    }
    my $lpar       = basename($lpar_dir);
    my $actual_hmc = active_hmc( $managedname, $lpar, "mem.mmm" );
    chomp $actual_hmc;
    if ( -d $lpar_dir ) {
      if ( -f "$lpar_dir/mem.mmm" ) {
        my $mem_path = "$wrkdir/$managedname/$actual_hmc/$lpar/mem.mmm";
        print "Content-Disposition: attachment;filename=\"OS_MEMORY\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
        my $header   = "$managedname : MEM usage: $human_start - $human_end";
        my $rrd_file = $mem_path;
        $rrd_file =~ s/:/\\:/g;
        chomp $rrd_file;
        my $rrd = $rrd_file;
        if ($xport) {
          RRDp::cmd qq(xport $showtime
          "--start" "$start"
          "--end" "$end"
          "--step" "$step"
          "--maxrows" "128000"
          "DEF:size=$rrd:size:AVERAGE"
          "DEF:used=$rrd:nuse:AVERAGE"
          "DEF:free=$rrd:free:AVERAGE"
          "DEF:pin=$rrd:pin:AVERAGE"
          "DEF:in_use_work=$rrd:in_use_work:AVERAGE"
          "DEF:in_use_clnt=$rrd:in_use_clnt:AVERAGE"
          "CDEF:free_g=free,1048576,/"
          "CDEF:usedg=used,1048576,/"
          "CDEF:in_use_clnt_g=in_use_clnt,1048576,/"
          "CDEF:used_realg=usedg,in_use_clnt_g,-"
          "CDEF:pin_g=pin,1048576,/"
          "CDEF:used_realg_res=used_realg,1000,*,0.5,+,FLOOR,1000,/"
          "CDEF:in_use_clnt_res=in_use_clnt_g,1000,*,0.5,+,FLOOR,1000,/"
          "CDEF:free_g_res=free_g,1000,*,0.5,+,FLOOR,1000,/"
          "CDEF:pin_res=pin_g,1000,*,0.5,+,FLOOR,1000,/"
          "CDEF:used_realg_res_a=used_realg_res,1000,*"
          "CDEF:in_use_clnt_res_a=in_use_clnt_res,1000,*"
          "CDEF:free_g_res_a=free_g_res,1000,*"
          "CDEF:pin_res_a=pin_res,1000,*"
          "XPORT:used_realg_res_a:Used memory in MB"
          "XPORT:in_use_clnt_res_a:FS Cache in MB"
          "XPORT:free_g_res_a:Free in MB"
          "XPORT:pin_res_a:Pinned in MB"
          );
          my $answer = RRDp::read;

          #print STDERR "$$answer\n";
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lparform =~ /^pg1|nmon_pg1/ ) {
    my $hmc_all           = "$wrkdir/$managedname/$hmc";
    my $filter_max_paging = 100000000;
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "";
    if ( $lparform =~ /nmon_pg1/ ) {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--NMON--";
    }
    else {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";
    }
    my $lpar       = basename($lpar_dir);
    my $actual_hmc = active_hmc( $managedname, $lpar, "pgs.mmm" );
    chomp $actual_hmc;
    if ( -d $lpar_dir ) {
      if ( -f "$lpar_dir/pgs.mmm" ) {
        my $pgs_path = "$wrkdir/$managedname/$actual_hmc/$lpar/pgs.mmm";
        print "Content-Disposition: attachment;filename=\"PAGING\_USAGE\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
        my $header   = "$managedname : PAGING usage: $human_start - $human_end";
        my $rrd_file = $pgs_path;
        my $filter   = $filter_max_paging;
        $rrd_file =~ s/:/\\:/g;
        chomp $rrd_file;
        my $rrd = $rrd_file;

        if ($xport) {
          RRDp::cmd qq(xport $showtime
          "--start" "$start"
          "--end" "$end"
          "--step" "$step"
          "--maxrows" "128000"
          "DEF:pagein=$rrd:page_in:AVERAGE"
          "DEF:pageout=$rrd:page_out:AVERAGE"
          "CDEF:pagein_b_nf=pagein,4096,*"
          "CDEF:pageout_b_nf=pageout,4096,*"
          "CDEF:pagein_b=pagein_b_nf,$filter,GT,UNKN,pagein_b_nf,IF"
          "CDEF:pageout_b=pageout_b_nf,$filter,GT,UNKN,pageout_b_nf,IF"
          "CDEF:pagein_mb=pagein_b,1048576,/"
          "CDEF:pagein_mb_neg=pagein_mb,-1,*"
          "CDEF:pageout_mb=pageout_b,1048576,/"
          "CDEF:pageout_mb_res=pageout_mb,1000,*,0.5,+,FLOOR,1000,/"
          "CDEF:pagein_mb_res=pagein_mb,1000,*,0.5,+,FLOOR,1000,/"
          "XPORT:pageout_mb_res:Page out"
          "XPORT:pagein_mb_res:Page in"
          );
          my $answer = RRDp::read;

          #print STDERR "$$answer\n";
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lparform =~ /san_resp|nmon_san_resp/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "";
    if ( $lparform =~ /nmon_san_resp/ ) {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--NMON--";
    }
    else {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";
    }
    my $lpar = basename($lpar_dir);
    if ( -d $lpar_dir ) {
      opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $i             = "";
      my $count         = 0;
      my $file_csv_name = "";
      my $cmd_xpo       = "";
      $cmd_xpo = "xport $showtime ";
      $cmd_xpo .= " --start \"$start\"";
      $cmd_xpo .= " --end \"$end\"";
      $cmd_xpo .= " --step \"$step\"";
      $cmd_xpo .= " --maxrows \"128000\"";

      foreach my $lpar_dir_os (@lpars_dir_os_all) {
        my $lpar_os = basename($lpar_dir_os);
        if ( $lpar_dir_os =~ /san_resp|san_resp-sissas/ ) {

          my $header     = "$managedname : SAN Response time: $human_start - $human_end";
          my $actual_hmc = active_hmc( $managedname, $lpar, $lpar_dir_os );
          chomp $actual_hmc;
          if ( $count == 0 ) {
            print "Content-Disposition: attachment;filename=\"SAN\_RESPONSE\_TIME\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
          }
          $count++;
          my $rrd_os_file = "$wrkdir/$managedname/$actual_hmc/$lpar/$lpar_dir_os";
          my $rrd_file    = $rrd_os_file;
          my $fcs         = $lpar_dir_os;
          $fcs      =~ s/san_resp-//g;
          $fcs      =~ s/\.mmm//g;
          $rrd_file =~ s/:/\\:/g;
          chomp $rrd_file;
          my $rrd = $rrd_file;

          if ($xport) {
            $cmd_xpo .= " DEF:read${i}=\"$rrd\":resp_t_r:AVERAGE";
            $cmd_xpo .= " DEF:write${i}=\"$rrd\":resp_t_w:AVERAGE";
            $cmd_xpo .= " CDEF:read_res${i}=read${i},100,*,0.5,+,FLOOR,100,/";
            $cmd_xpo .= " CDEF:write_res${i}=write${i},100,*,0.5,+,FLOOR,100,/";
            $cmd_xpo .= " XPORT:read_res${i}:\"READ - $fcs in ms\"";
            $cmd_xpo .= " XPORT:write_res${i}:\"WRITE - $fcs in ms\"";
            $i++;
          }
        }
      }
      RRDp::cmd qq($cmd_xpo);
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
  }
  elsif ( $lparform =~ /lan|nmon_lan/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "";
    if ( $lparform =~ /nmon_lan/ ) {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--NMON--";
    }
    else {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";
    }
    my $lpar = basename($lpar_dir);
    if ( -d $lpar_dir ) {
      opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $i             = "";
      my $count         = 0;
      my $file_csv_name = "";
      my $cmd_xpo       = "";
      $cmd_xpo = "xport $showtime ";
      $cmd_xpo .= " --start \"$start\"";
      $cmd_xpo .= " --end \"$end\"";
      $cmd_xpo .= " --step \"$step\"";
      $cmd_xpo .= " --maxrows \"128000\"";

      foreach my $lpar_dir_os (@lpars_dir_os_all) {
        my $lpar_os = basename($lpar_dir_os);
        if ( $lpar_dir_os =~ /lan-/ ) {
          if ( $lpar_dir_os =~ /\.cfg$/ ) { next; }
          my $header     = "$managedname : LAN : $human_start - $human_end";
          my $actual_hmc = active_hmc( $managedname, $lpar, $lpar_dir_os );
          chomp $actual_hmc;
          if ( $count == 0 ) {
            print "Content-Disposition: attachment;filename=\"LAN\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
          }
          $count++;
          my $rrd_os_file   = "$wrkdir/$managedname/$actual_hmc/$lpar/$lpar_dir_os";
          my $rrd_file      = $rrd_os_file;
          my $en            = $lpar_dir_os;
          my $divider       = 1073741824;
          my $count_avg_day = 1;
          my $minus_one     = -1;
          $en       =~ s/lan-//g;
          $en       =~ s/\.mmm//g;
          $rrd_file =~ s/:/\\:/g;
          chomp $rrd_file;
          my $rrd = $rrd_file;

          if ($xport) {
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
            $cmd_xpo .= " XPORT:received_bytes_res${i}:\"REC bytes - $en - Bytes/sec \"";
            $cmd_xpo .= " XPORT:transfers_bytes_res${i}:\"TRANS bytes - $en - Bytes/sec \"";
            $i++;
          }
        }
      }
      RRDp::cmd qq($cmd_xpo);
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;

        #print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$file_csv_name.csv\"\n\n";
        xport_print( $answer, 0 );
      }
    }
  }
  elsif ( $lparform =~ /^san|nmon_san/ ) {
    my $ds_name_os1 = "";
    my $ds_name_os2 = "";
    my $name_os1    = "";
    my $name_os2    = "";
    my $comment1    = "";
    if ( $lparform =~ /san1$|nmon_san1/ ) {
      $ds_name_os1 = "recv_bytes";
      $ds_name_os2 = "trans_bytes";
      $name_os1    = "Recv bytes";
      $name_os2    = "Trans bytes";
      $comment1    = "Bytes/sec";
    }
    if ( $lparform =~ /san2$|nmon_san2/ ) {
      $ds_name_os1 = "iops_in";
      $ds_name_os2 = "iops_out";
      $name_os1    = "IOPS in";
      $name_os2    = "IOPS out";
      $comment1    = "IOPS";
    }
    my $lpar_dir = "";
    if ( $lparform =~ /^nmon_san/ ) {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--NMON--";
    }
    elsif ( $lparform =~ /solaris_ldom_san1|solaris_ldom_san2/ ) {
      $lpar_dir = "$wrkdir/Solaris/$lpar";
    }
    elsif ( $lparform =~ /san1|san2/ ) {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";
    }

    #my $lpar = basename($lpar_dir);
    #print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$lpar.csv\"\n\n";
    if ( -d $lpar_dir ) {
      opendir( DIR, "$lpar_dir" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $i             = "";
      my $count         = 0;
      my $file_csv_name = "";
      my $cmd_xpo       = "";
      $cmd_xpo = "xport $showtime ";
      $cmd_xpo .= " --start \"$start\"";
      $cmd_xpo .= " --end \"$end\"";
      $cmd_xpo .= " --step \"$step\"";
      $cmd_xpo .= " --maxrows \"128000\"";

      foreach my $lpar_dir_os (@lpars_dir_os_all) {
        my $lpar_os = basename($lpar_dir_os);

        #print STDERR "$lpar_dir_os\n";
        if ( $lpar_dir_os =~ /san-/ ) {

          #print STDERR "$ds_name_os1 --- $ds_name_os2\n";
          if ( $lpar_dir_os =~ /\.cfg$/ ) { next; }
          my $actual_hmc = active_hmc( $managedname, $lpar, $lpar_dir_os );
          chomp $actual_hmc;
          if ( $count == 0 ) {
            print "Content-Disposition: attachment;filename=\"SAN\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
          }
          $count++;
          my $header      = "$managedname : SAN : $human_start - $human_end";
          my $rrd_os_file = "";

          # Solaris hist rep
          if ( $lparform =~ /solaris_ldom_san1|solaris_ldom_san2/ ) {
            $rrd_os_file = "$lpar_dir/$lpar_dir_os";
          }
          else {
            $rrd_os_file = "$wrkdir/$managedname/$actual_hmc/$lpar/$lpar_dir_os";
          }
          my $rrd_file = $rrd_os_file;
          my $en       = $lpar_dir_os;
          $en       =~ s/san-//g;
          $en       =~ s/\.mmm//g;
          $rrd_file =~ s/:/\\:/g;
          chomp $rrd_file;
          my $rrd = $rrd_file;

          if ($xport) {
            $cmd_xpo .= " DEF:value_os1${i}=\"$rrd\":$ds_name_os1:AVERAGE";
            $cmd_xpo .= " DEF:value_os2${i}=\"$rrd\":$ds_name_os2:AVERAGE";
            $cmd_xpo .= " CDEF:value_os1_res${i}=value_os1${i},1,*,0.5,+,FLOOR,1,/";
            $cmd_xpo .= " CDEF:value_os2_res${i}=value_os2${i},1,*,0.5,+,FLOOR,1,/";
            $cmd_xpo .= " XPORT:value_os1_res${i}:\"$name_os1 - $en - $comment1\"";
            $cmd_xpo .= " XPORT:value_os2_res${i}:\"$name_os2 - $en - $comment1\"";
            $i++;
          }
        }
      }
      RRDp::cmd qq($cmd_xpo);
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
  }
  elsif ( $lparform =~ /sarmon/ ) {
    my $ds_name_os1 = "";
    my $ds_name_os2 = "";
    my $name_os1    = "";
    my $name_os2    = "";
    my $comment1    = "";

    if ( $lparform =~ /sarmon_san/ ) {
      $ds_name_os1 = "disk_read";
      $ds_name_os2 = "disk_write";
      $name_os1    = "READ";
      $name_os2    = "WRITE";
      $comment1    = "Bytes/sec";
    }
    if ( $lparform =~ /sarmon_iops/ ) {
      $ds_name_os1 = "disk_iops";
      $name_os1    = "Total";
      $comment1    = "IOPS";
    }
    if ( $lparform =~ /sarmon_latency/ ) {
      $ds_name_os1 = "disk_latency";
      $name_os1    = "Total";
      $comment1    = "ms";
    }

    #my $lpar = basename($lpar_dir);
    my $count         = 0;
    my $file_csv_name = "";
    my $cmd_xpo       = "";
    $cmd_xpo = "xport $showtime ";
    $cmd_xpo .= " --start \"$start\"";
    $cmd_xpo .= " --end \"$end\"";
    $cmd_xpo .= " --step \"$step\"";
    $cmd_xpo .= " --maxrows \"128000\"";

    #print STDERR "$ds_name_os1 --- $ds_name_os2\n";
    if ( $count == 0 ) {
      print "Content-Disposition: attachment;filename=\"SAN\_$managedname\_$lpar.csv\"\n\n";
    }
    $count++;
    my $header      = "$managedname : SAN : $human_start - $human_end";
    my $rrd_os_file = "$wrkdir/Solaris--unknown/no_hmc/$lpar/total-san.mmm";
    my $rrd_file    = $rrd_os_file;
    $rrd_file =~ s/:/\\:/g;
    chomp $rrd_file;
    my $rrd = $rrd_file;

    if ($xport) {
      if ( $lparform =~ /sarmon_san/ ) {
        $cmd_xpo .= " DEF:value_os1=\"$rrd\":$ds_name_os1:AVERAGE";
        $cmd_xpo .= " DEF:value_os2=\"$rrd\":$ds_name_os2:AVERAGE";
        $cmd_xpo .= " CDEF:value_os1_res=value_os1,1,*,0.5,+,FLOOR,1,/";
        $cmd_xpo .= " CDEF:value_os2_res=value_os2,1,*,0.5,+,FLOOR,1,/";
        $cmd_xpo .= " XPORT:value_os1_res:\"$name_os1 - $comment1\"";
        $cmd_xpo .= " XPORT:value_os2_res:\"$name_os2 - $comment1\"";
      }
      if ( $lparform =~ /sarmon_iops/ ) {
        $cmd_xpo .= " DEF:value_os1=\"$rrd\":$ds_name_os1:AVERAGE";
        $cmd_xpo .= " CDEF:value_os1_res=value_os1,1,*,0.5,+,FLOOR,1,/";
        $cmd_xpo .= " XPORT:value_os1_res:\"$name_os1 - $comment1\"";
      }
      if ( $lparform =~ /sarmon_latency/ ) {
        $cmd_xpo .= " DEF:value_os1=\"$rrd\":$ds_name_os1:AVERAGE";
        $cmd_xpo .= " CDEF:value_os1_res=value_os1,1,*,0.5,+,FLOOR,1,/";
        $cmd_xpo .= " XPORT:value_os1_res:\"$name_os1 - $comment1\"";
      }
    }
    RRDp::cmd qq($cmd_xpo);
    my $answer = RRDp::read;
    if ( $$answer =~ "ERROR" ) {
      error("Rrdtool error : $$answer");
    }
    else {
      $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
      xport_print( $answer, 0 );
    }
  }
  elsif ( $lparform =~ /^pg2|nmon_pg2/ ) {
    my $hmc_all           = "$wrkdir/$managedname/$hmc";
    my $filter_max_paging = 100000000;
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "";
    if ( $lparform =~ /nmon_pg2/ ) {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--NMON--";
    }
    else {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";
    }
    my $lpar = basename($lpar_dir);
    if ( -d $lpar_dir ) {
      if ( -f "$lpar_dir/pgs.mmm" ) {
        my $pgs_path   = "$lpar_dir/pgs.mmm";
        my $actual_hmc = active_hmc( $managedname, $lpar, "pgs.mmm" );
        chomp $actual_hmc;
        print "Content-Disposition: attachment;filename=\"PAGING\_SPACE\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
        my $header   = "$managedname : PAGING usage: $human_start - $human_end";
        my $rrd_file = $pgs_path;
        my $filter   = $filter_max_paging;
        $rrd_file =~ s/:/\\:/g;
        chomp $rrd_file;
        my $rrd = $rrd_file;

        if ($xport) {
          RRDp::cmd qq(xport $showtime
          "--start" "$start"
          "--end" "$end"
          "--step" "$step"
          "--maxrows" "128000"
          "DEF:paging=$rrd:paging_space:AVERAGE"
          "DEF:percent_a=$rrd:percent:AVERAGE"
          "XPORT:paging:Paging space in MB"
          "XPORT:percent_a:percent %"
          );
          my $answer = RRDp::read;

          #print STDERR "$$answer\n";
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lparform =~ /sea|nmon_sea/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "";
    if ( $lparform =~ /nmon_sea/ ) {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--NMON--";
    }
    else {
      $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar";
    }
    my $lpar = basename($lpar_dir);
    if ( -d $lpar_dir ) {
      opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $i             = "";
      my $count         = 0;
      my $file_csv_name = "";
      my $cmd_xpo       = "";
      $cmd_xpo = "xport $showtime ";
      $cmd_xpo .= " --start \"$start\"";
      $cmd_xpo .= " --end \"$end\"";
      $cmd_xpo .= " --step \"$step\"";
      $cmd_xpo .= " --maxrows \"128000\"";

      foreach my $lpar_dir_os (@lpars_dir_os_all) {
        my $lpar_os = basename($lpar_dir_os);
        if ( $lpar_dir_os =~ /sea-ent/ ) {
          if ( $lpar_dir_os =~ /\.cfg$/ ) { next; }

          my $header     = "$managedname : SEA: $human_start - $human_end";
          my $actual_hmc = active_hmc( $managedname, $lpar, $lpar_dir_os );
          chomp $actual_hmc;
          if ( $count == 0 ) {
            print "Content-Disposition: attachment;filename=\"SEA\_$actual_hmc\_$managedname\_$lpar.csv\"\n\n";
          }
          $count++;
          my $rrd_os_file = "$wrkdir/$managedname/$actual_hmc/$lpar/$lpar_dir_os";

          #print STDERR "$rrd_os_file\n";
          my $rrd_file = $rrd_os_file;
          my $en       = $lpar_dir_os;
          $en       =~ s/sea-//g;
          $en       =~ s/\.mmm//g;
          $rrd_file =~ s/:/\\:/g;
          chomp $rrd_file;
          my $rrd = $rrd_file;

          if ($xport) {
            $cmd_xpo .= " DEF:received_bytes${i}=\"$rrd\":recv_bytes:AVERAGE";
            $cmd_xpo .= " DEF:transfers_bytes${i}=\"$rrd\":trans_bytes:AVERAGE";
            $cmd_xpo .= " DEF:received_packets${i}=\"$rrd\":recv_packets:AVERAGE";
            $cmd_xpo .= " DEF:transfers_packets${i}=\"$rrd\":trans_packets:AVERAGE";
            $cmd_xpo .= " XPORT:received_bytes${i}:\"REC bytes - $en\"";
            $cmd_xpo .= " XPORT:transfers_bytes${i}:\"TRANS bytes - $en\"";
            $cmd_xpo .= " XPORT:received_packets${i}:\"REC packets - $en\"";
            $cmd_xpo .= " XPORT:transfers_packets${i}:\"TRANS packets- $en\"";
            $i++;
          }
        }
      }
      RRDp::cmd qq($cmd_xpo);
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
  }

  elsif ( $lparform =~ /S0200ASPJOB/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--AS400--";
    my $lpar     = basename($lpar_dir);
    if ( -d $lpar_dir ) {
      opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $i             = "";
      my $cmd_xpo       = "";
      my $file_csv_name = "";
      $cmd_xpo = "xport $showtime ";
      $cmd_xpo .= " --start \"$start\"";
      $cmd_xpo .= " --end \"$end\"";
      $cmd_xpo .= " --step \"$step\"";
      $cmd_xpo .= " --maxrows \"128000\"";

      foreach my $lpar_dir_os (@lpars_dir_os_all) {
        my $lpar_os = basename($lpar_dir_os);
        if ( -d $lpar_os ) { next; }
        if ( $lpar_os =~ /S0200ASPJOB\.mmm|S0200PROCS\.mmm/ ) {

          #    print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$lpar.csv\"\n\n";
          #print STDERR "$lpar_os\n";
          my $header           = "$managedname : JOBS : $human_start - $human_end";
          my $rrd_file         = "";
          my $rrd_file_threads = "";
          if ( $lpar_os =~ /S0200ASPJOB\.mmm/ ) { $rrd_file         = $lpar_os; }
          if ( $lpar_os =~ /S0200PROCS\.mmm/ )  { $rrd_file_threads = $lpar_os; }
          $rrd_file         =~ s/:/\\:/g;
          $rrd_file_threads =~ s/:/\\:/g;
          chomp $rrd_file;
          my $as400_path = "$lpar_dir/$rrd_file";
          my $rrd_a      = "$lpar_dir/$rrd_file_threads";
          my $rrd        = $as400_path;

          #print STDERR "1246-,,$rrd,, --- ,,$rrd_a,,\n";
          if ($xport) {
            if ( $lpar_os =~ /S0200PROCS\.mmm/ ) {
              $cmd_xpo .= " DEF:threads${i}=\"$rrd_a\":par8:AVERAGE";
              $cmd_xpo .= " CDEF:threads_res${i}=threads${i},1,*,0.5,+,FLOOR,1,/";
              $cmd_xpo .= " XPORT:threads_res${i}:\"Threads\"";
            }
            if ( $lpar_os =~ /S0200ASPJOB\.mmm/ ) {
              $cmd_xpo .= " DEF:jobs_total${i}=\"$rrd\":par3:AVERAGE";
              $cmd_xpo .= " DEF:jobs_activ${i}=\"$rrd\":par7:AVERAGE";
              $cmd_xpo .= " CDEF:jobs_total_res${i}=jobs_total${i},1,*,0.5,+,FLOOR,1,/";
              $cmd_xpo .= " CDEF:jobs_activ_res${i}=jobs_activ${i},1,*,0.5,+,FLOOR,1,/";
              $cmd_xpo .= " XPORT:jobs_total_res${i}:\"JOBS total\"";
              $cmd_xpo .= " XPORT:jobs_activ_res${i}:\"JOBS active\"";
            }
            $i++;
          }
        }
      }
      RRDp::cmd qq($cmd_xpo);
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$file_csv_name.csv\"\n\n";
        xport_print( $answer, 0 );
      }
    }
  }

  elsif ( $lparform =~ /size|threads|faults|pages/ ) {
    my $cmd     = "";
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--AS400--";
    my $lpar     = basename($lpar_dir);
    if ( -d $lpar_dir ) {
      opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $i             = "";
      my $cmd_xpo       = "";
      my $file_csv_name = "";
      $cmd_xpo = "xport $showtime ";
      $cmd_xpo .= " --start \"$start\"";
      $cmd_xpo .= " --end \"$end\"";
      $cmd_xpo .= " --step \"$step\"";
      $cmd_xpo .= " --maxrows \"128000\"";
      my @sort_dir_os_all = sort { lc $a cmp lc $b } @lpars_dir_os_all;

      foreach my $lpar_dir_os (@sort_dir_os_all) {
        my $lpar_os = basename($lpar_dir_os);
        if ( -d $lpar_os ) { next; }
        my $search_parm = "";
        if ( $lparform =~ /size/ )    { $search_parm = "S0400[0-9][0-9]Parm1\.mmm"; $file_csv_name = "size"; }
        if ( $lparform =~ /threads/ ) { $search_parm = "S0400[0-9][0-9]Parm3\.mmm"; $file_csv_name = "threads"; }
        if ( $lparform =~ /faults/ )  { $search_parm = "S0400[0-9][0-9]Parm2\.mmm"; $file_csv_name = "faults"; }
        if ( $lparform =~ /pages/ )   { $search_parm = "S0400[0-9][0-9]Parm2\.mmm"; $file_csv_name = "pages"; }
        if ( $lpar_os  =~ /$search_parm/ ) {
          my $config_file = $lpar_os;
          $config_file =~ s/\.mmm$//g;
          if ( $lparform =~ /size/ )    { $config_file =~ s/1$//g; }
          if ( $lparform =~ /threads/ ) { $config_file =~ s/3$//g; }
          if ( $lparform =~ /faults/ )  { $config_file =~ s/2$//g; }
          if ( $lparform =~ /pages/ )   { $config_file =~ s/2$//g; }
          my $cfg_name       = "$lpar_dir/$config_file.cfg";
          my $cfg_name_print = "";

          if ( -e $cfg_name ) {
            open( FC, "< $cfg_name" ) || error( "Cannot read $cfg_name: $!" . __FILE__ . ":" . __LINE__ );
            $cfg_name_print = <FC>;
            chomp $cfg_name_print;
            close(FC);
          }
          my $as400_path = "$lpar_dir/$lpar_os";
          my $header     = "$managedname : SIZE : $human_start - $human_end";
          my $rrd_file   = $as400_path;
          $rrd_file =~ s/:/\\:/g;
          chomp $rrd_file;
          my $rrd = $rrd_file;
          if ($xport) {

            if ( $lparform =~ /size/ ) {
              $cmd_xpo .= " DEF:cur${i}=\"$rrd\":par5:AVERAGE";
              $cmd_xpo .= " DEF:type${i}=\"$rrd\":par3:AVERAGE";
              $cmd_xpo .= " CDEF:curg_argv${i}=cur${i},1024,/,1024,/";
              $cmd_xpo .= " CDEF:curg_argv_res${i}=curg_argv${i},10,*,0.5,+,FLOOR,10,/";
              $cmd_xpo .= " XPORT:curg_argv_res${i}:\"AVG - $cfg_name_print\"";
            }
            if ( $lparform =~ /threads/ ) {
              $cmd_xpo .= " DEF:cur${i}=\"$rrd\":par6:AVERAGE";
              $cmd_xpo .= " CDEF:curg_argv${i}=cur${i},1,/";
              $cmd_xpo .= " CDEF:curg_argv_res${i}=curg_argv${i},1,*,0.5,+,FLOOR,1,/";
              $cmd_xpo .= " XPORT:curg_argv_res${i}:\"AVG - $cfg_name_print\"";
            }
            if ( $lparform =~ /faults/ ) {
              $cmd_xpo .= " DEF:cur${i}=\"$rrd\":par4:AVERAGE";
              $cmd_xpo .= " DEF:cus${i}=\"$rrd\":par7:AVERAGE";
              $cmd_xpo .= " CDEF:curg_argv${i}=cur${i},1,/";
              $cmd_xpo .= " CDEF:curg_argv_res${i}=curg_argv${i},100,*,0.5,+,FLOOR,100,/";
              $cmd_xpo .= " CDEF:cus_res${i}=cus${i},100,*,0.5,+,FLOOR,100,/";
              $cmd_xpo .= " XPORT:curg_argv${i}:\"DB - AVG - $cfg_name_print\"";
              $cmd_xpo .= " XPORT:cus_res${i}:\"non/DB - AVG - $cfg_name_print\"";
            }
            if ( $lparform =~ /pages/ ) {
              $cmd_xpo .= " DEF:cur${i}=\"$rrd\":par5:AVERAGE";
              $cmd_xpo .= " DEF:cus${i}=\"$rrd\":par6:AVERAGE";
              $cmd_xpo .= " CDEF:curg_argv${i}=cur${i},1,/";
              $cmd_xpo .= " XPORT:curg_argv${i}:\"DB - AVG - $cfg_name_print\"";
              $cmd_xpo .= " XPORT:cus${i}:\"non/DB - AVG - $cfg_name_print\"";
            }
            $i++;
          }
        }
      }
      RRDp::cmd qq($cmd_xpo);
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$file_csv_name.csv\"\n\n";
        xport_print( $answer, 0 );
      }
    }
  }

  elsif ( $lparform =~ /cap_used|cap_free/ ) {
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--AS400--";
    my $lpar     = basename($lpar_dir);
    if ( -d $lpar_dir ) {
      opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $i             = "";
      my $file_csv_name = "";
      my $cmd_xpo       = "";
      $cmd_xpo = "xport $showtime ";
      $cmd_xpo .= " --start \"$start\"";
      $cmd_xpo .= " --end \"$end\"";
      $cmd_xpo .= " --step \"$step\"";
      $cmd_xpo .= " --maxrows \"128000\"";
      my @sort_dir_os_all = sort { lc $a cmp lc $b } @lpars_dir_os_all;

      foreach my $lpar_dir_os (@sort_dir_os_all) {
        my $lpar_os = basename($lpar_dir_os);
        if ( $lpar_os =~ /^ASP/ ) {
          opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar/$lpar_os" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar_os: $! :" . __FILE__ . ":" . __LINE__ ) && next;
          my @lpars_dir_asp_all = grep !/^\.\.?$/, readdir(DIR);
          closedir(DIR);
          foreach my $lpar_asp (@lpars_dir_asp_all) {
            if ( $lpar_asp =~ /Parm3\.mmc$/ ) {
              my $name_col   = "";
              my $lpar_asp_a = $lpar_asp;
              $lpar_asp_a =~ s/ASP//g;
              $lpar_asp_a =~ s/Parm3\.mmc//g;
              my $parm_cfg = "Parm.cfg";
              my $iasp_cfg = "$lpar_dir/$lpar_os/ASP$lpar_asp_a$parm_cfg";

              #print "1424 --- $iasp_cfg\n";
##### ASP compare - 001 = *SYSTEM, 001-032 = ASPXX, ASP033 and more - IASPXX
              if ( $lpar_asp_a =~ /001/ ) {
                $name_col = "*SYSTEM";
              }
              else {
                my $id_a = 1;
                if ( $lpar_asp_a <= 032 ) {
                  $name_col = "ASP$lpar_asp_a";
                }
                else {
                  my @lines_config;
                  if ( -e $iasp_cfg ) {
                    open( FH, "< $iasp_cfg" ) || error( "Cannot read $iasp_cfg: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
                    @lines_config = <FH>;
                    close(FH);
                  }
                  my ($grep_asp) = grep /,Dev name:/, @lines_config;
                  my ( undef, $grep_asp_a ) = split( /,/, $grep_asp );
                  $grep_asp_a =~ s/Dev name://g;
                  $grep_asp_a =~ s/\s+//g;
                  chomp $grep_asp_a;
                  $name_col = $grep_asp_a;
                }
              }

              my $as400_path = "$lpar_dir/$lpar_os/$lpar_asp";
              if ( $lpar_os =~ /\.cfg/ ) { next; }
              my $header   = "$managedname : ASP used : $human_start - $human_end";
              my $rrd_file = $as400_path;
              $rrd_file =~ s/:/\\:/g;
              chomp $rrd_file;
              my $rrd = $rrd_file;
              if ($xport) {
                if ( $lparform =~ /cap_used$/ ) {
                  $file_csv_name = "cap_used";
                  $cmd_xpo .= " DEF:cur${i}=\"$rrd\":par3:AVERAGE";
                  $cmd_xpo .= " DEF:curfree${i}=\"$rrd\":par4:AVERAGE";
                  $cmd_xpo .= " CDEF:curg${i}=cur${i},curfree${i},-,1000,/";
                  $cmd_xpo .= " CDEF:curg_res${i}=curg${i},1,*,0.5,+,FLOOR,1,/";
                  $cmd_xpo .= " XPORT:curg_res${i}:\"AVG - $name_col\"";
                }
                if ( $lparform =~ /cap_free$/ ) {
                  $file_csv_name = "cap_free";
                  $cmd_xpo .= " DEF:cur${i}=\"$rrd\":par3:AVERAGE";
                  $cmd_xpo .= " DEF:curfree${i}=\"$rrd\":par4:AVERAGE";
                  $cmd_xpo .= " CDEF:curg${i}=curfree${i},1000,/";
                  $cmd_xpo .= " CDEF:curg_res${i}=curg${i},1,*,0.5,+,FLOOR,1,/";
                  $cmd_xpo .= " XPORT:curg_res${i}:\"AVG - $name_col\"";
                }
                $i++;
              }
            }
          }
        }
      }
      RRDp::cmd qq($cmd_xpo);
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$file_csv_name.csv\"\n\n";
        xport_print( $answer, 0 );
      }
    }
  }

  elsif ( $lparform =~ /data_as|iops_as/ ) {
    my $parm    = "";
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--AS400--";
    my $lpar     = basename($lpar_dir);
    if ( -d $lpar_dir ) {
      opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $i             = "";
      my $file_csv_name = "";
      my $cmd_xpo       = "";
      $cmd_xpo = "xport $showtime ";
      $cmd_xpo .= " --start \"$start\"";
      $cmd_xpo .= " --end \"$end\"";
      $cmd_xpo .= " --step \"$step\"";
      $cmd_xpo .= " --maxrows \"128000\"";
      my @sort_dir_os_all = sort { lc $a cmp lc $b } @lpars_dir_os_all;

      foreach my $lpar_dir_os (@sort_dir_os_all) {
        my $lpar_os = basename($lpar_dir_os);
        if ( $lpar_os =~ /^ASP/ ) {

          #print STDERR "1523 - $lpar_os\n";
          opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar/$lpar_os" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar_os: $! :" . __FILE__ . ":" . __LINE__ ) && next;
          my @lpars_dir_asp_all = grep !/^\.\.?$/, readdir(DIR);
          closedir(DIR);
          foreach my $lpar_asp (@lpars_dir_asp_all) {
            if ( $lpar_asp =~ /Parm4\.mmc$/ ) {
              my $name_col   = "";
              my $lpar_asp_a = $lpar_asp;
              $lpar_asp_a =~ s/ASP//g;
              $lpar_asp_a =~ s/Parm4\.mmc//g;
              my $parm_cfg = "Parm.cfg";
              my $iasp_cfg = "$lpar_dir/$lpar_os/ASP$lpar_asp_a$parm_cfg";

##### ASP compare - 001 = *SYSTEM, 001-032 = ASPXX, ASP033 and more - IASPXX
              if ( $lpar_asp_a =~ /001/ ) {
                $name_col = "*SYSTEM";
              }
              else {
                my $id_a = 1;
                if ( $lpar_asp_a <= 032 ) {
                  $name_col = "ASP$lpar_asp_a";
                }
                else {
                  my @lines_config;
                  if ( -e $iasp_cfg ) {
                    open( FH, "< $iasp_cfg" ) || error( "Cannot read $iasp_cfg: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
                    @lines_config = <FH>;
                    close(FH);
                  }
                  my ($grep_asp) = grep /,Dev name:/, @lines_config;
                  my ( undef, $grep_asp_a ) = split( /,/, $grep_asp );
                  $grep_asp_a =~ s/Dev name://g;
                  $grep_asp_a =~ s/\s+//g;
                  chomp $grep_asp_a;
                  $name_col = $grep_asp_a;
                }
              }
              my $as400_path = "$lpar_dir/$lpar_os/$lpar_asp";
              if ( $lpar_os =~ /\.cfg/ ) { next; }
              my $header = "$managedname : ASP iops: $human_start - $human_end";
              my ( $value1, $value2 );
              if ( $lparform =~ /iops_as/ ) {
                $file_csv_name = "iops_as";
                $value1        = "par5";
                $value2        = "par6";
              }
              if ( $lparform =~ /data_as/ ) {
                $file_csv_name = "data_as";
                $value1        = "par3";
                $value2        = "par4";
              }
              my $rrd_file = $as400_path;
              $rrd_file =~ s/:/\\:/g;
              chomp $rrd_file;
              my $rrd = $rrd_file;
              if ($xport) {
                $cmd_xpo .= " DEF:cur${i}=\"$rrd\":$value1:AVERAGE";
                $cmd_xpo .= " DEF:curfree${i}=\"$rrd\":$value2:AVERAGE";
                $cmd_xpo .= " CDEF:cur_res${i}=cur${i},1,*,0.5,+,FLOOR,1,/";
                $cmd_xpo .= " CDEF:curfree_res${i}=curfree${i},1,*,0.5,+,FLOOR,1,/";
                $cmd_xpo .= " XPORT:cur_res${i}:\"AVG - READ - $name_col\"";
                $cmd_xpo .= " XPORT:curfree_res${i}:\"AVG - WRITE - $name_col\"";
                $i++;
              }
            }
          }
          RRDp::cmd qq($cmd_xpo);
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$file_csv_name.csv\"\n\n";
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }

  elsif ( $lparform =~ /data_ifcb$/ ) {
    my $parm    = "";
    my $hmc_all = "$wrkdir/$managedname/$hmc";
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || error( "can't opendir $wrkdir/$managedname/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @lpars_dir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);
    my $lpar_dir = "$wrkdir/$managedname/$hmc/$lpar--AS400--";
    my $lpar     = basename($lpar_dir);
    if ( -d $lpar_dir ) {
      opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpars_dir_os_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      my $i             = "";
      my $file_csv_name = "";
      my $cmd_xpo       = "";
      $cmd_xpo = "xport $showtime ";
      $cmd_xpo .= " --start \"$start\"";
      $cmd_xpo .= " --end \"$end\"";
      $cmd_xpo .= " --step \"$step\"";
      $cmd_xpo .= " --maxrows \"128000\"";
      my @sort_dir_os_all = sort { lc $a cmp lc $b } @lpars_dir_os_all;

      foreach my $lpar_dir_os (@sort_dir_os_all) {
        my $lpar_os = basename($lpar_dir_os);
        if ( $lpar_os =~ /IFC/ ) {
          opendir( DIR, "$wrkdir/$managedname/$hmc/$lpar/$lpar_os" ) || error( "can't opendir $wrkdir/$managedname/$hmc/$lpar_os: $! :" . __FILE__ . ":" . __LINE__ ) && next;
          my @lpars_dir_asp_all = grep !/^\.\.?$/, readdir(DIR);
          closedir(DIR);
          foreach my $lpar_asp (@lpars_dir_asp_all) {
            if ( $lpar_asp =~ /ETHLVISION\.mmc$|SECVIS.mmc/ ) {
              my $as400_path = "$lpar_dir/$lpar_os/$lpar_asp";
              $lpar_asp =~ s/\.mmc//g;
              if ( $lpar_os =~ /\.cfg/ ) { next; }
              my $header = "$managedname : LAN iops: $human_start - $human_end";
              my ( $value1, $value2 );
              if ( $lparform =~ /data_ifcb/ ) {
                $file_csv_name = "data_ifcb";
                $value1        = "par3";
                $value2        = "par4";
              }
              my $rrd_file = $as400_path;
              $rrd_file =~ s/:/\\:/g;
              chomp $rrd_file;
              my $rrd = $rrd_file;
              $rrd_file =~ s/\.mmc//g;
              if ($xport) {
                $cmd_xpo .= " DEF:cur${i}=\"$rrd\":$value1:AVERAGE";
                $cmd_xpo .= " DEF:curfree${i}=\"$rrd\":$value2:AVERAGE";
                $cmd_xpo .= " CDEF:cur_res${i}=cur${i},1,*,0.5,+,FLOOR,1,/";
                $cmd_xpo .= " CDEF:curfree_res${i}=curfree${i},1,*,0.5,+,FLOOR,1,/";
                $cmd_xpo .= " XPORT:cur_res${i}:\"AVG - READ - $lpar_asp \"";
                $cmd_xpo .= " XPORT:curfree_res${i}:\"AVG - WRITE - $lpar_asp\"";
                $i++;
              }
            }
          }
          RRDp::cmd qq($cmd_xpo);
          my $answer = RRDp::read;
          if ( $$answer =~ "ERROR" ) {
            error("Rrdtool error : $$answer");
          }
          else {
            $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
            print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$file_csv_name.csv\"\n\n";
            xport_print( $answer, 0 );
          }
        }
      }
    }
  }
  elsif ( $lpar eq "total" ) {
    my $rrd        = "$wrkdir/$managedname/$hmc/pool_total.rrt";
    my $lpar_slash = $lpar;
    $lpar_slash =~ s/\&\&1/\//g;    # to show slash and not &&1 which is general replacemnt for it
    my $header = "$managedname : $lpar_slash : $human_start - $human_end";

    my $lpar_out = $lpar_slash;
    $lpar_out =~ s/ /\\/g;

    # print STDERR "626 lpar2rrd-rep.pl $lpar,$start,$end,$step,$rrd\n";
    $rrd =~ s/:/\\:/g;
    if ($xport) {
      print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$lpar_out.csv\"\n\n";

      # export selected data into XML
      RRDp::cmd qq(xport $showtime
      "--start" "$start"
      "--end" "$end"
      "--step" "$step"
      "--maxrows" "128000"
      "DEF:configured=$rrd:configured:AVERAGE"
      "DEF:cur=$rrd:curr_proc_units:AVERAGE"
      "DEF:ent=$rrd:entitled_cycles:AVERAGE"
      "DEF:cap=$rrd:capped_cycles:AVERAGE"
      "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
      "CDEF:tot=cap,uncap,+"
      "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
      "CDEF:utiltot=util,cur,*"
      "CDEF:utiltot_res=utiltot,100,*,0.5,+,FLOOR,100,/"
      "XPORT:cur:Entitled"
      "XPORT:utiltot_res:Utilization in CPU cores"
      );
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
  }
  #
  # Solaris section LDOMs
  #
  elsif ( $lparform =~ /solaris_ldom_cpu/ ) {
    my ( undef, $ldom_name ) = ( split /:/, $lpar );
    my $rrd        = "$wrkdir/Solaris/$lpar/$ldom_name\_ldom.mmm";
    my $lpar_slash = $lpar;
    $lpar_slash =~ s/\&\&1/\//g;    # to show slash and not &&1 which is general replacemnt for it
    my $header = "$managedname : $lpar_slash : $human_start - $human_end";

    my $lpar_out = $lpar_slash;
    $lpar_out =~ s/ /\\/g;

    # print STDERR "626 lpar2rrd-rep.pl $lpar,$start,$end,$step,$rrd\n";
    $rrd =~ s/:/\\:/g;
    if ($xport) {
      print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$lpar_out.csv\"\n\n";

      # export selected data into XML
      RRDp::cmd qq(xport $showtime
      "--start" "$start"
      "--end" "$end"
      "--step" "$step"
      "--maxrows" "128000"
      "DEF:cpu=$rrd:cpu_util:AVERAGE"
      "XPORT:cpu:Usage[%]"
      );
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
  }
  elsif ( $lparform =~ /solaris_ldom_mem/ ) {
    my ( undef, $ldom_name ) = ( split /:/, $lpar );
    my $rrd        = "$wrkdir/Solaris/$lpar/$ldom_name\_ldom.mmm";
    my $lpar_slash = $lpar;
    $lpar_slash =~ s/\&\&1/\//g;    # to show slash and not &&1 which is general replacemnt for it
    my $header = "$managedname : $lpar_slash : $human_start - $human_end";

    my $lpar_out = $lpar_slash;
    $lpar_out =~ s/ /\\/g;

    # print STDERR "626 lpar2rrd-rep.pl $lpar,$start,$end,$step,$rrd\n";
    $rrd =~ s/:/\\:/g;
    if ($xport) {
      print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$lpar_out.csv\"\n\n";

      # export selected data into XML
      RRDp::cmd qq(xport $showtime
      "--start" "$start"
      "--end" "$end"
      "--step" "$step"
      "--maxrows" "128000"
      "DEF:mem1=$rrd:mem_allocated:AVERAGE"
      "CDEF:mem2=mem1,100000,/,10000,/"
      "XPORT:mem2:MEM allocated[%]"
      );
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
  }
  #
  # HyperV section VMs
  #
  elsif ( $lparform =~ /hyp-cpu|hyp-mem|hyp-disk|hyp-net/ ) {
    my $file_csv_name = "";
    my $cmd_xpo       = "";
    $cmd_xpo = "xport $showtime ";
    $cmd_xpo .= " --start \"$start\"";
    $cmd_xpo .= " --end \"$end\"";

    # $cmd_xpo .= " --step \"$step\"";
    $cmd_xpo .= " --step \"300\"";         # for hyperv 5 mins
                                           # print STDERR "2268 \$step $step\n";
    $cmd_xpo .= " --maxrows \"128000\"";

    print "Content-Disposition: attachment;filename=\"$lparform\_$hmc\_$lpar.csv\"\n\n";
    my $header = "$managedname : CPU : $human_start - $human_end";

    my $rrd  = "$wrkdir/$managedname/domain_$hmc/hyperv_VMs/$lpar.rrm";
    my $kbmb = 1024;

    if ($xport) {

      #   @ds = ( "PercentTotalRunTime", "Timestamp_PerfTime", "Frequency_PerfTime", "vCPU" ) if $item eq "hyp-cpu";
      if ( $lparform =~ /hyp-cpu/ ) {
        $cmd_xpo .= " DEF:value_os1=\"$rrd\":PercentTotalRunTime:AVERAGE";
        $cmd_xpo .= " DEF:value_os2=\"$rrd\":Timestamp_PerfTime:AVERAGE";
        $cmd_xpo .= " DEF:value_os3=\"$rrd\":Frequency_PerfTime:AVERAGE";
        $cmd_xpo .= " DEF:value_os4=\"$rrd\":vCPU:AVERAGE";
        $cmd_xpo .= " CDEF:CPU_usage_Proc=value_os1,value_os2,/,value_os3,*,100000,/,100,/,value_os4,*";    # % to be in cores
        $cmd_xpo .= " CDEF:vcpu=value_os4,1,/";                                                             # number
        $cmd_xpo .= " CDEF:pagein_b=CPU_usage_Proc";
        $cmd_xpo .= " XPORT:vcpu:\"vCPU\"";
        $cmd_xpo .= " XPORT:pagein_b:\"Usage [cores]\"";
      }
      elsif ( $lparform =~ /hyp-mem/ ) {
        $cmd_xpo .= " DEF:size=\"$rrd\":TotalPhysMemory:AVERAGE";
        $cmd_xpo .= " CDEF:sizeg=size,1024,/";
        $cmd_xpo .= " XPORT:sizeg:\"Used memory\"";
      }
      elsif ( $lparform =~ /hyp-disk/ ) {
        $kbmb *= 1000 * 1000;
        $cmd_xpo .= " DEF:pagein=\"$rrd\":DiskReadBytesPersec:AVERAGE";
        $cmd_xpo .= " DEF:pageout=\"$rrd\":DiskWriteBytesPerse:AVERAGE";
        $cmd_xpo .= " CDEF:pagein_b=pagein,$kbmb,/";
        $cmd_xpo .= " CDEF:pageout_b=pageout,$kbmb,/";
        $cmd_xpo .= " XPORT:pagein_b:\"Read\"";
        $cmd_xpo .= " XPORT:pageout_b:\"Write\"";
      }
      elsif ( $lparform =~ /hyp-net/ ) {
        $kbmb *= 1000 * 1000;
        $cmd_xpo .= " DEF:pagein=\"$rrd\":BytesReceivedPersec:AVERAGE";
        $cmd_xpo .= " DEF:pageout=\"$rrd\":BytesSentPersec:AVERAGE";
        $cmd_xpo .= " CDEF:pagein_b=pagein,$kbmb,/";
        $cmd_xpo .= " CDEF:pageout_b=pageout,$kbmb,/";
        $cmd_xpo .= " XPORT:pagein_b:\"Read\"";
        $cmd_xpo .= " XPORT:pageout_b:\"Write\"";
      }
    }
    RRDp::cmd qq($cmd_xpo);
    my $answer = RRDp::read;
    if ( $$answer =~ "ERROR" ) {
      error("Rrdtool error : $$answer");
    }
    else {
      $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
      xport_print( $answer, 0 );
    }
  }
  #
  # HyperV section server
  #
  elsif ( $lparform =~ /pool|memalloc|hyppg1|hyppg2|vmnetrw|hdt_data|hdt_io|cpuqueue|cpu_process|hdt_latency/ ) {
    my $file_csv_name = "";
    my $cmd_xpo       = "";
    $cmd_xpo = "xport $showtime ";
    $cmd_xpo .= " --start \"$start\"";
    $cmd_xpo .= " --end \"$end\"";

    #$cmd_xpo .= " --step \"$step\"";
    $cmd_xpo .= " --step \"300\"";         # for hyperv 5 mins
                                           # print STDERR "2336 \$step $step\n";
    $cmd_xpo .= " --maxrows \"128000\"";

    print "Content-Disposition: attachment;filename=\"$lparform\_$hmc\_$lpar.csv\"\n\n";
    my $header = "$managedname : CPU : $human_start - $human_end";

    my $rrd = "$wrkdir/$managedname/domain_$hmc/$lpar/pool.rrm";

    # Max cpu cores for pool
    my $max_cpu_cores = 10;                # for hyperv
    my $kbmb          = 1024;
    if ( open( FR, "< $wrkdir/windows/domain_$hmc/$lpar/cpu.html" ) ) {
      my $firstLine = <FR>;                # example <BR><CENTER><TABLE class="tabconfig tablesorter"><!cores:8>
      close FR;
      ( undef, my $m_cpu_cores ) = split( "cores:", $firstLine );
      if ( defined $m_cpu_cores ) {
        $m_cpu_cores =~ s/>//;
        $max_cpu_cores = $m_cpu_cores;
        chomp $max_cpu_cores;
        if ( index( $max_cpu_cores, "," ) > -1 ) {
          ( $max_cpu_cores, undef ) = split( ",", $max_cpu_cores );
        }

        #print STDERR "8639 \$max_cpu_cores,$max_cpu_cores,\n";
      }
    }

    if ($xport) {

      #   @ds = ( "PercentTotalRunTime", "Timestamp_PerfTime", "Frequency_PerfTime", "vCPU" ) if $item eq "hyp-cpu";
      if ( $lparform =~ /pool/ ) {
        $cmd_xpo .= " DEF:cpu_perc=\"$rrd\":PercentTotalRunTime:AVERAGE";
        $cmd_xpo .= " DEF:cpu_time=\"$rrd\":Timestamp_PerfTime:AVERAGE";
        $cmd_xpo .= " DEF:cpu_freq=\"$rrd\":Frequency_PerfTime:AVERAGE";
        if ( -f "$wrkdir/windows/domain_$hmc/$lpar/standalone" ) {

          # print STDERR "11627 testing standalone $wrkdir/$server/$host/standalone\n";
          $cmd_xpo .= " CDEF:cpuutiltot=1,cpu_perc,cpu_time,/,-,$max_cpu_cores,*";    # to be in cores
        }
        else {
          $cmd_xpo .= " CDEF:cpuutiltot=cpu_perc,cpu_time,/,cpu_freq,*,100000,/,100,/";    # to be in cores
        }
        $cmd_xpo .= " CDEF:cpuutiltotperc=cpuutiltot,$max_cpu_cores,/,100,*";
        $cmd_xpo .= " XPORT:cpuutiltot:\"Utilization in cores\"";
        $cmd_xpo .= " XPORT:cpuutiltotperc:\"Utilization in percent\"";
      }
      elsif ( $lparform =~ /memalloc/ ) {
        $cmd_xpo .= " DEF:free=\"$rrd\":AvailableMBytes:AVERAGE";
        $cmd_xpo .= " DEF:tot=\"$rrd\":TotalPhysMemory:AVERAGE";
        $cmd_xpo .= " DEF:cachebytes=\"$rrd\":CacheBytes:AVERAGE";
        $cmd_xpo .= " CDEF:freeg=free,1024,/";
        $cmd_xpo .= " CDEF:totg=tot,1024,/,1024,/,1024,/";
        $cmd_xpo .= " CDEF:cacheg=cachebytes,1024,/,1024,/,1024,/";
        $cmd_xpo .= " CDEF:used_comp=totg,freeg,-";
        $cmd_xpo .= " CDEF:used=used_comp,0,LE,0,used_comp,IF";
        $cmd_xpo .= " CDEF:freegc=freeg,cacheg,-";
        $cmd_xpo .= " XPORT:used:\"Used memory\"";
        $cmd_xpo .= " XPORT:cacheg:\"Cache\"";
        $cmd_xpo .= " XPORT:freegc:\"Free memory\"";
      }
      elsif ( $lparform =~ /hyppg1/ ) {
        $cmd_xpo .= " DEF:pagein=\"$rrd\":PagesInputPersec:AVERAGE";
        $cmd_xpo .= " DEF:pageout=\"$rrd\":PagesOutputPersec:AVERAGE";

        # $cmd_xpo .= " CDEF:pagein_mb=pagein,1048576,/,300,/";            # 5 mins perf data
        # $cmd_xpo .= " CDEF:pageout_mb=pageout,1048576,/,300,/";
        $cmd_xpo .= " CDEF:pagein_mb=pagein,4096,*,1048576,/,300,/";     # 5 mins perf data, page is usually 4 kB
        $cmd_xpo .= " CDEF:pageout_mb=pageout,4096,*,1048576,/,300,/";
        $cmd_xpo .= " XPORT:pagein_mb:\"Page in\"";
        $cmd_xpo .= " XPORT:pageout_mb:\"Page out\"";
      }
      elsif ( $lparform =~ /hyppg2/ ) {
        $cmd_xpo .= " DEF:paging=\"$rrd\":DiskBytesPersec:AVERAGE";
        $cmd_xpo .= " DEF:paging_used=\"$rrd\":DiskTransfersPersec:AVERAGE";

        $cmd_xpo .= " CDEF:percent=paging_used,paging,/,100,*";
        $cmd_xpo .= " XPORT:paging:\"Paging space in MB\"";
        $cmd_xpo .= " XPORT:percent:\"percent %\"";
      }
      elsif ( $lparform =~ /vmnetrw/ ) {
        $kbmb *= 1000 * 1000;
        $cmd_xpo .= " DEF:lanread=\"$rrd\":BytesReceivedPersec:AVERAGE";
        $cmd_xpo .= " DEF:lanwrite=\"$rrd\":BytesSentPersec:AVERAGE";
        $cmd_xpo .= " CDEF:lanread_b=lanread,$kbmb,/";
        $cmd_xpo .= " CDEF:lanwrite_b=lanwrite,$kbmb,/";
        $cmd_xpo .= " XPORT:lanread_b:\"READ IO\"";
        $cmd_xpo .= " XPORT:lanwrite_b:\"WRITE IO\"";
      }
      elsif ( $lparform =~ /hdt_data/ ) {
        $kbmb = 1000000;
        $cmd_xpo .= " DEF:diskread=\"$rrd\":DiskReadBytesPersec:AVERAGE";
        $cmd_xpo .= " DEF:diskwrite=\"$rrd\":DiskWriteBytesPerse:AVERAGE";
        $cmd_xpo .= " DEF:timeperf=\"$rrd\":Timestamp_PerfTime:AVERAGE";
        $cmd_xpo .= " DEF:freqperf=\"$rrd\":Frequency_PerfTime:AVERAGE";
        $cmd_xpo .= " CDEF:pageinb=diskread,timeperf,/,freqperf,*,$kbmb,/";
        $cmd_xpo .= " CDEF:pageoutb=diskwrite,timeperf,/,freqperf,*,$kbmb,/";
        $cmd_xpo .= " XPORT:pageinb:\"READ DATA\"";
        $cmd_xpo .= " XPORT:pageoutb:\"WRITE DATA\"";
      }
      elsif ( $lparform =~ /hdt_io/ ) {
        $kbmb = 1;
        $cmd_xpo .= " DEF:diskread=\"$rrd\":DiskReadsPersec:AVERAGE";
        $cmd_xpo .= " DEF:diskwrite=\"$rrd\":DiskWritesPersec:AVERAGE";
        $cmd_xpo .= " DEF:timeperf=\"$rrd\":Timestamp_PerfTime:AVERAGE";
        $cmd_xpo .= " DEF:freqperf=\"$rrd\":Frequency_PerfTime:AVERAGE";
        $cmd_xpo .= " CDEF:pageinb=diskread,timeperf,/,freqperf,*,$kbmb,/";
        $cmd_xpo .= " CDEF:pageoutb=diskwrite,timeperf,/,freqperf,*,$kbmb,/";
        $cmd_xpo .= " XPORT:pageinb:\"READ IO\"";
        $cmd_xpo .= " XPORT:pageoutb:\"WRITE IO\"";
      }
      elsif ( $lparform =~ /cpuqueue/ ) {
        $rrd = "$wrkdir/$managedname/domain_$hmc/$lpar/CPUqueue.rrm";
        $cmd_xpo .= " DEF:cpuqueue=\"$rrd\":CPU_queue:AVERAGE";
        $cmd_xpo .= " XPORT:cpuqueue:\"cpu_queue\"";
      }
      elsif ( $lparform =~ /cpu_process/ ) {
        $rrd = "$wrkdir/$managedname/domain_$hmc/$lpar/CPUqueue.rrm";
        $cmd_xpo .= " DEF:cpuprocesses=\"$rrd\":CPU_processes:AVERAGE";
        $cmd_xpo .= " DEF:cputhreads=\"$rrd\":CPU_threads:AVERAGE";
        $cmd_xpo .= " XPORT:cpuprocesses:\"cpu_process\"";
        $cmd_xpo .= " XPORT:cputhreads:\"cpu_threads\"";
      }
      elsif ( $lparform =~ /hdt_latency/ ) {
        my $dir   = "$wrkdir/$managedname/domain_$hmc/$lpar/";
        my @files = ();
        if ( opendir( my $DIR, "$dir" ) ) {
          my @list = readdir($DIR);
          closedir($DIR);

          # take Local_Fixed_Disks & Cluster storages
          @files = grep ( /Local_Fixed_Disk_|Cluster_Storage_/, @list );

          # print STDERR "2467 \@files @files\n";

          my $i     = "";
          my $count = 0;
          $kbmb = 1000;
          my $filter = 10000;

          foreach my $rrd_file (@files) {
            $count++;
            my $rrd_file_title = $rrd_file;
            $rrd_file_title =~ s/\.rrm$//;
            $rrd_file_title =~ s/:/\\:/g;
            $rrd_file = "$dir$rrd_file";

            # avoid old files (storages) which do not exist in the period
            my $rrd_upd_time = ( stat("$rrd_file") )[9];

            # print STDERR "2483 \$rrd_upd_time $rrd_upd_time \$start $start\n";
            # next if ( $rrd_upd_time < $start );
            # 2483 $rrd_upd_time 1647264242 $start 13:00 13.7.2022
            # you will need str2time function to convert human date-time to unix time

            $rrd_file =~ s/:/\\:/g;
            chomp $rrd_file;
            my $rrd = $rrd_file;

            # following lines are from detail-graph-cgi.pl for item = csv_lat_
            # @ds = ( "AvgDisksecPerRead", "AvgDisksecPerReadB", "AvgDisksecPerWrite", "AvgDisksecPerWriteB", "Frequency_PerfTime" ) if ( $item =~ 'csv_lat' );

            # $cmd .= " CDEF:pagein_b_tmp=$ids[1],0,EQ,0,$ids[0],$ids[1],/,$ids[4],/,$kbmb,*,IF";
            # $cmd .= " CDEF:pagein_b=pagein_b_tmp,$filter,GT,0,pagein_b_tmp,IF";
            # $cmd .= " CDEF:pagein_b_nf=pagein_b,-1,*";
            # $cmd .= " CDEF:pageout_b_nf_tmp=$ids[3],0,EQ,0,$ids[2],$ids[3],/,$ids[4],/,$kbmb,*,IF";
            # $cmd .= " CDEF:pageout_b_nf=pageout_b_nf_tmp,$filter,GT,0,pageout_b_nf_tmp,IF";

            $cmd_xpo .= " DEF:PerRead${i}=\"$rrd\":AvgDisksecPerRead:AVERAGE";
            $cmd_xpo .= " DEF:PerReadB${i}=\"$rrd\":AvgDisksecPerReadB:AVERAGE";
            $cmd_xpo .= " DEF:PerWrite${i}=\"$rrd\":AvgDisksecPerWrite:AVERAGE";
            $cmd_xpo .= " DEF:PerWriteB${i}=\"$rrd\":AvgDisksecPerWriteB:AVERAGE";
            $cmd_xpo .= " DEF:Frequency${i}=\"$rrd\":Frequency_PerfTime:AVERAGE";
            $cmd_xpo .= " CDEF:read_tmp${i}=PerReadB${i},0,EQ,0,PerRead${i},PerReadB${i},/,Frequency${i},/,$kbmb,*,IF";
            $cmd_xpo .= " CDEF:read${i}=read_tmp${i},$filter,GT,0,read_tmp${i},IF";
            $cmd_xpo .= " CDEF:write_tmp${i}=PerWriteB${i},0,EQ,0,PerWrite${i},PerWriteB${i},/,Frequency${i},/,$kbmb,*,IF";
            $cmd_xpo .= " CDEF:write${i}=write_tmp${i},$filter,GT,0,write_tmp${i},IF";

            $cmd_xpo .= " XPORT:read${i}:\"Latency Read- $rrd_file_title in ms\"";
            $cmd_xpo .= " XPORT:write${i}:\"Latency Write- $rrd_file_title in ms\"";
            $i++;
          }
        }
      }
      RRDp::cmd qq($cmd_xpo);
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
    #
    # end of HyperV section
    #
  }
  else {    #lpars (everything except pool, mem & multiview)

    my $rrd        = "$wrkdir/$managedname/$hmc/$lpar.rr$type";
    my $lpar_slash = $lpar;
    $lpar_slash =~ s/\&\&1/\//g;    # to show slash and not &&1 which is general replacemnt for it
    my $header = "$managedname : $lpar_slash : $human_start - $human_end";

    my $lpar_out = $lpar_slash;
    $lpar_out =~ s/ /\\/g;

    # print STDERR "626 lpar2rrd-rep.pl $lpar,$start,$end,$step,$rrd\n";
    $rrd =~ s/:/\\:/g;
    if ($xport) {
      print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_$lpar_out.csv\"\n\n";

      # export selected data into XML
      RRDp::cmd qq(xport $showtime
      "--start" "$start"
      "--end" "$end"
      "--step" "$step"
      "--maxrows" "128000"
      "DEF:cur=$rrd:curr_proc_units:AVERAGE"
      "DEF:ent=$rrd:entitled_cycles:AVERAGE"
      "DEF:cap=$rrd:capped_cycles:AVERAGE"
      "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
      "CDEF:tot=cap,uncap,+"
      "CDEF:util=tot,ent,/,$cpu_max_filter,GT,UNKN,tot,ent,/,IF"
      "CDEF:utiltot=util,cur,*"
      "CDEF:utiltot_res=utiltot,100,*,0.5,+,FLOOR,100,/"
      "XPORT:cur:Entitled"
      "XPORT:utiltot_res:Utilization in CPU cores"
      );
      my $answer = RRDp::read;
      if ( $$answer =~ "ERROR" ) {
        error("Rrdtool error : $$answer");
      }
      else {
        $$answer =~ s/.*\n.*\n.*\n<\?xml version=/<\?xml version=/g;
        xport_print( $answer, 0 );
      }
    }
    else {
      #LPARs

      # LPM support
      my $lpm_count = 0;
      if ( $lpm == 1 ) {
        my $DEBUG_ORG = $DEBUG;
        $DEBUG = 0;    # debug has to be switched off for this std function
        my $lpm_suff = "rrl";
        if ( $type =~ "d" ) {
          $lpm_suff = "rrk";
        }
        if ( $type =~ "h" ) {
          $lpm_suff = "rri";
        }

        # never use function "grab", grrrr ...
        my $managedname_space = $managedname;
        if ( $managedname =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
          $managedname_space = "\"" . $managedname . "\"";
        }
        my $hmc_space = $hmc;
        if ( $hmc =~ m/ / ) {            # workaround for server name with a space inside, nothing else works, grrr
          $hmc_space = "\"" . $hmc . "\"";
        }
        my $lpar_space = $lpar;
        if ( $lpar =~ m/ / ) {           # workaround for server name with a space inside, nothing else works, grrr
          $lpar_space = "\"" . $lpar . "\"";
        }

        foreach my $trash (<$wrkdir/$managedname_space/$hmc_space/$lpar_space=====*=====*.$lpm_suff>) {
          $lpm_count++;
        }

        # if it is a VIO server then do not go for LPM
        lpm_exclude_vio( $hmc, $managedname, $wrkdir );
        foreach my $lpm_line (@lpm_excl_vio) {
          chomp($lpm_line);
          if ( "$lpm_line" =~ m/$lpar/ && length($lpm_line) == length($lpar) ) {
            print "LPM VIO exclude: $hmc:$managedname:$lpar_slash:$type:$type - $lpm_line\n" if $DEBUG;
            $lpm_count = 0;
            last;
          }
        }

        if ($lpm_count) {

          # LPM is detected
          # it returns 0 if it is excluded
          my $text = "";
          $lpm_count = lpm( "hist", "", $name, $start, $end, $rrdwidth, $rrdheight, $header, $wrkdir, $webdir, $managedname, $hmc, $lpar, $lpar_slash, $text, $type, $type, $step, "", $act_time, $pic_col, $DEBUG, $rrdtool, $lpm_suff, \@color );
        }
        $DEBUG = $DEBUG_ORG;
      }

      # normal non LPM stuff
      if ( $lpm == 0 || $lpm_count == 0 ) {

        #print "creating graph : $hmc:$managedname:$lpar_slash:$type\n" if $DEBUG ;
        RRDp::cmd qq(graph "$name"
        "--title" "$header"
        "--start" "$start"
        "--end" "$end"
        "--imgformat" "PNG"
        "$disable_rrdtool_tag"
        "--slope-mode"
        "--width=$rrdwidth"
        "--height=$rrdheight"
        "--step=$step"
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
        "GPRINT:cur:AVERAGE: %2.1lf"
        "$t2"
        "LINE1:utiltot#FF0000: Utilization in CPU cores"
        "GPRINT:utiltot:AVERAGE: %3.2lf"
        "COMMENT:(Entitled CPU utilization"
        "GPRINT:utilperct:AVERAGE: %2.1lf"
        "COMMENT:\%)"
        "$t2"
        "$t"
        "$last"
        "$t2"
        "HRULE:0#000000"
        "VRULE:0#000000"
        );
        my $answer = RRDp::read;
        if ( $$answer =~ "ERROR" ) {
          error( "CSV multi graph rrdtool error : $$answer " . __FILE__ . ":" . __LINE__ );
          return 1;
        }
      }
    }
  }
  return 0;
}

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

  # print STDERR Dumper ($xml);
  if ( ref $xml->{meta}{legend}{entry} eq "ARRAY" ) {
    foreach my $item ( @{ $xml->{meta}{legend}{entry} } ) {    # in case semicolon in lpar name
      $item = "\"" . $item . "\"";
    }
  }
  else {
    $xml->{meta}{legend}{entry} = "\"" . $xml->{meta}{legend}{entry} . "\"";
  }

  #print STDERR Dumper %($xml);

  if ( ref $xml->{meta}{legend}{entry} eq "ARRAY" ) {
    print join( "$sep", 'Timestamp DD.MM.YYYY HH:MM', @{ $xml->{meta}{legend}{entry} } ), "\n";
  }
  else {
    print "Timestamp DD.MM.YYYY HH:MM$sep", $xml->{meta}{legend}{entry}, "\n";
  }

  foreach my $row ( @{ $xml->{data}{row} } ) {
    my $time = strftime "%d.%m.%y %H:%M:%S", localtime( $row->{t} );
    my $line = "";
    if ( ref $row->{v} eq "ARRAY" ) {

      #print STDERR Dumper (\@{$row->{v}});
      foreach ( @{ $row->{v} } ) {
        $_ = sprintf "%.2f", $_;
        $_ += 0;
      }

      #print STDERR Dumper (\@{$row->{v}});
      $line = join( "$sep", $time, @{ $row->{v} } );

      #print STDERR "$line\n";
    }
    else {
      if ( !isdigit( $row->{v} ) ) {
        $row->{v} = 0;
      }
      $row->{v} = sprintf "%.2f", $row->{v};
      $row->{v} += 0;
      $line = $time . "$sep" . $row->{v};
    }
    $line =~ s/NaNQ|NaN|nan/0/g;

    #print STDERR "$line////\n";
    print "$line\n";
  }
  return 0;
}

sub multiview {
  my $name        = shift;
  my $act_time    = shift;
  my $managedname = shift;
  my $start       = shift;
  my $end         = shift;
  my $header      = shift;
  my $start_unix  = shift;
  my $end_unix    = shift;

  # my $vmware = 0; # is global
  my @files = ();
  if ( -f "$wrkdir/$managedname/$hmc/VM_hosting.vmh" ) {
    my $hosting_file = "$wrkdir/$managedname/$hmc/VM_hosting.vmh";
    open( FHC, "< $hosting_file" ) || error( "cannot open file : $hosting_file " . __FILE__ . ":" . __LINE__ ) && return 0;
    @files = <FHC>;
    close(FHC);
    $vmware = 1;

    # print STDERR "917  $hosting_file \@files @files\n";
  }
  else {
    opendir( DIR, "$wrkdir/$managedname/$hmc" ) || die "$act_time: directory does not exists : $wrkdir/$managedname/$hmc";
    my @files_unsort = grep( /\.rr$type$/, readdir(DIR) );
    @files = sort { lc $a cmp lc $b } @files_unsort;
    closedir(DIR);
  }

  my $file      = "";
  my $i         = 0;
  my $lpar      = "";
  my $cmd       = "";
  my $cmd_xport = "";
  my $j         = 0;

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
  $cmd .= " --vertical-label=\\\"CPU cores\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " COMMENT:\\\"Average utilization in CPU cores\\l\\\"";

  my $gtype = "AREA";
  foreach $file (@files) {

    # print STDERR "963 $file \$vmware ,$vmware,\n";
    chomp($file);
    if ($vmware) {
      $file =~ s/:.*/\.rrm/;
      next if !-f "$wrkdir/vmware_VMs/$file";

      # avoid old lpars which do not exist in the period
      my $rrd_upd_time = ( stat("$wrkdir/vmware_VMs/$file") )[9];
      next if ( $rrd_upd_time < $start_unix );
    }
    else {
      # avoid old lpars which do not exist in the period
      my $rrd_upd_time = ( stat("$wrkdir/$managedname/$hmc/$file") )[9];
      next if ( $rrd_upd_time < $start_unix );
    }

    $lpar = $file;

    # print STDERR "884 $file\n";
    $lpar =~ s/.rrh$//;
    $lpar =~ s/.rrm$//;
    $lpar =~ s/.rrd$//;

    # Exclude pools and memory
    if ( $lpar =~ m/^mem-pool$/ || $lpar =~ m/^pool$/ || $lpar =~ m/^mem$/ || $lpar =~ m/^SharedPool[0-9]$/ || $lpar =~ m/^SharedPool[1-9][0-9]$/ || $lpar =~ m/^cod$/ ) {
      next;
    }

    # print OUT "$wrkdir/$managedname/$hmc/$file $rrd_upd_time $req_time $act_time\n" if ( $DEBUG == 2);

    my $rrd_target = "$wrkdir/$managedname/$hmc/$file";
    $rrd_target = "$wrkdir/vmware_VMs/$file" if ($vmware);

    $rrd_target =~ s/:/\\:/g;

    # $lpar = human_vmware_name($lpar);
    $lpar =~ s/:/\\:/g;
    $lpar =~ s/&&1/\//g;

    my $lpar_space = $lpar;

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    # to keep same count of characters
    $lpar_space =~ s/\\:/:/g;
    $lpar_space = sprintf( "%-25s", $lpar_space );
    $lpar_space =~ s/:/\\:/g;

    # print STDERR "907 $rrd_target\n";

    # bulid RRDTool cmd
    if ($vmware) {
      $cmd       .= " DEF:utiltot${i}=\\\"$rrd_target\\\":CPU_usage:AVERAGE";
      $cmd_xport .= "\\\"DEF:utiltot${i}=$rrd_target:CPU_usage:AVERAGE\\\"\n";
      $cmd_xport .= "\\\"XPORT:utiltot${i}:$rrd_target MHz\\\"\n";
    }
    else {
      $cmd       .= " DEF:cap${i}=\\\"$rrd_target\\\":capped_cycles:AVERAGE";
      $cmd       .= " DEF:uncap${i}=\\\"$rrd_target\\\":uncapped_cycles:AVERAGE";
      $cmd       .= " DEF:ent${i}=\\\"$rrd_target\\\":entitled_cycles:AVERAGE";
      $cmd       .= " DEF:cur${i}=\\\"$rrd_target\\\":curr_proc_units:AVERAGE";
      $cmd       .= " CDEF:tot${i}=cap${i},uncap${i},+";
      $cmd       .= " CDEF:util${i}=tot${i},ent${i},/";
      $cmd       .= " CDEF:utiltotu${i}=util${i},cur${i},*";
      $cmd       .= " CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF";
      $cmd       .= " $gtype:utiltot${i}$color[$i % ($color_max + 1)]:\\\"$lpar_space\\\"";
      $cmd_xport .= "\\\"DEF:cap${i}=$rrd_target:capped_cycles:AVERAGE\\\"\n";
      $cmd_xport .= "\\\"DEF:uncap${i}=$rrd_target:uncapped_cycles:AVERAGE\\\"\n";
      $cmd_xport .= "\\\"DEF:ent${i}=$rrd_target:entitled_cycles:AVERAGE\\\"\n";
      $cmd_xport .= "\\\"DEF:cur${i}=$rrd_target:curr_proc_units:AVERAGE\\\"\n";
      $cmd_xport .= "\\\"CDEF:tot${i}=cap${i},uncap${i},+\\\"\n";
      $cmd_xport .= "\\\"CDEF:util${i}=tot${i},ent${i},/\\\"\n";
      $cmd_xport .= "\\\"CDEF:utiltotu${i}=util${i},cur${i},*\\\"\n";
      $cmd_xport .= "\\\"CDEF:utiltot${i}=utiltotu${i},UN,0,utiltotu${i},IF\\\"\n";
      $cmd_xport .= "\\\"XPORT:utiltot${i}:$lpar\\\"\n";
    }

    $cmd .= " GPRINT:utiltot${i}:AVERAGE:\\\"%3.2lf \\l\\\"";
    $gtype = "STACK";
    $i++;    # color index
  }
  $cmd .= " COMMENT:\\\" \\l\\\"";
  $cmd .= " COMMENT:\\\"\(Note that for CPU dedicated LPARs is always shown their whole entitlement\)\\\"";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000"; --> it is causing sigsegv on linuxes
  $cmd       =~ s/\\"/"/g;
  $cmd_xport =~ s/\\"/"/g;
  if ($xport) {

    # print STDERR "\$cmd_xport $cmd_xport\n";
    print "Content-Disposition: attachment;filename=\"$hmc\_$managedname\_aggregated.csv\"\n\n";
    RRDp::cmd qq(xport $showtime
		"--start" "$start"
		"--end" "$end"
		"--step" "$step"
		"--maxrows" "128000"
		$cmd_xport
);
    my $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "CSV multi graph rrdtool error : $$ret " . __FILE__ . ":" . __LINE__ );
      return 1;
    }

    # print STDERR "---- $ret\n*** $$ret\n+++ $cmd_xport";
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
          if ($vmware) {

            # in '<entry>' lines transform VM UUID to human VM name
            # <entry>/home/lpar2rrd/lpar2rrd/data/vmware_VMs/502adbbe-1399-d4c9-1dd8-a9337db21ded.rrm MHz</entry>
            ( my $uuid, undef ) = split '.rrm MHz', $line;

            # print STDERR "989 \$uuid $uuid \$line $line\n";
            if ( defined $uuid && $uuid ne "" && $uuid ne $line ) {
              my @parts = split '/', $uuid;
              $uuid = $parts[-1];
              if ( $uuid ne "" ) {
                my $human_name = human_vmware_name($uuid);
                $human_name =~ s/\&/\&amp;/g;    # invalid XML chars
                                                 # print STDERR "1005 lpar2rrd-rep.pl \$uuid $uuid \$human_name $human_name \$line $line\n";
                $line = "<entry>$human_name MHz</entry>\n";
              }
            }
          }
          $out_txt .= $line;
        }
      }
    }
    close(FH);
    unlink("$tmp_file");

    # print STDERR "1014 lpar2rrd-rep.pl --xport $out_txt\n";
    # print STDERR "++xport $$ret\n";
    xport_print( $out_txt, 1 );
  }
  else {
    # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
    # do not do it here, it is in detail-graph-cgi.pl
    close(OUT) if ( $DEBUG == 2 );
    return 0;

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

# fill in @lpm_excl_vio for server
sub lpm_exclude_vio {
  my $host        = shift;
  my $managedname = shift;
  my $wrkdir      = shift;
  my $lpm_excl    = "$wrkdir/$managedname/$host/lpm-exclude.txt";

  if ( $lpm == 0 ) {
    return 0;    # LPM is switched off
  }
  open( FH, "< $lpm_excl" ) || return 1;
  @lpm_excl_vio = <FH>;
  close(FH);
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

sub basename {
  return ( split "\/", $_[0] )[-1];
}

sub active_hmc {

  my $managedname   = shift;
  my $lpar          = shift;
  my $lpar_dir_os   = shift;
  my @unsorted_line = "";
  my %hash_timestamp;
  my @lines;
  my @hmc_test = "";
  opendir( DIR, "$wrkdir/$managedname/" ) || error( "can't opendir $wrkdir/$managedname/: $! :" . __FILE__ . ":" . __LINE__ ) && next;
  my @hmcdir_all = grep !/^\.\.?$/, readdir(DIR);
  closedir(DIR);

  foreach my $hmc (@hmcdir_all) {
    my $lpar_os_file = "$wrkdir/$managedname/$hmc/$lpar/$lpar_dir_os";
    if ( -f $lpar_os_file ) {
      my $last_timestamp = ( stat($lpar_os_file) )[9];
      push( @unsorted_line, "$managedname,$lpar,$hmc,$last_timestamp\n" );
    }
  }
  my @sorted_line = sort @unsorted_line;
  foreach my $line (@sorted_line) {
    if ( defined $line && $line ne "" ) {
      chomp $line;
      my ( $server, $lpar, $hmc, $timestamp ) = split( /,/, $line );
      $hash_timestamp{$server}{$lpar}{$hmc} = $timestamp;
    }
  }

  foreach my $server ( keys %hash_timestamp ) {
    foreach my $lpar ( keys %{ $hash_timestamp{$server} } ) {
      my $last_timestamp = 0;
      my $file           = "";
      foreach my $hmc ( keys %{ $hash_timestamp{$server}{$lpar} } ) {
        if ( $hash_timestamp{$server}{$lpar}{$hmc} >= $last_timestamp ) {

          #$file = "$server,$lpar,$hmc";
          $file           = "$hmc";
          $last_timestamp = $hash_timestamp{$server}{$lpar}{$hmc};
        }
      }
      if ( defined $file && $file ne "" ) {
        return "$file";
      }
    }
  }

  #print STDERR"==@lines==\n";
  #foreach my $hmc_active(@lines){
  #  chomp $hmc_active;
  #  my ($a,$b,$hmc_a) = split (/,/,$hmc_active);
  #  print STDERR"??$a??$b?$hmc_a??????\n";
  #  return "$hmc_a";
  #}
}

sub human_vmware_name {
  my $lpar  = shift;
  my $arrow = shift;
  if ( !$vmware ) { return "$lpar" }
  ;    # only for vmware
       # read file and find human lpar name from uuid or
       # if 'neg' then find uuid from name

  # my $trans_file = "$wrkdir/$server/$host/lpar_trans.txt";
  my $trans_file = "$wrkdir/vmware_VMs/vm_uuid_name.txt";
  if ( -f "$trans_file" ) {
    open( FR, "< $trans_file" );
    foreach my $linep (<FR>) {
      chomp($linep);

      #     (my $id, my $name) = split (/,/,$linep);
      ( my $id, my $name, undef ) = split( /,/, $linep );
      if ( defined($arrow) && "$arrow" eq "neg" ) {
        ( $name, $id, undef ) = split( /,/, $linep );
      }
      if ( "$id" eq "$lpar" ) {
        $lpar = "$name";
        last;
      }
    }
    close(FR);
  }
  return "$lpar";    #human name - if found, or original
}

