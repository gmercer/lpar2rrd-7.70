#
# used only for DHL accounting purposes
# etc/.magic : KEEP_VIRTUAL=1 --> it has to be setup after initial installation!!!
#

use strict;
use Env qw(QUERY_STRING);
use Date::Parse;
use POSIX qw(strftime);
use RRDp;

my $inputdir       = $ENV{INPUTDIR};
my $webdir         = $ENV{WEBDIR};
my $rrdtool        = $ENV{RRDTOOL};
my $pic_col        = $ENV{PICTURE_COLOR};
my $wrkdir         = "$inputdir/data";
my $STEP           = $ENV{SAMPLE_RATE};
my $DEBUG          = $ENV{DEBUG};
my $errlog         = $ENV{ERRLOG};
my $height         = $ENV{RRDHEIGHT};
my $width          = $ENV{RRDWIDTH};
my $bindir         = $ENV{BINDIR};
my $xport_delta    = "120";                 # default time to go back in XPORT for 1h, for 1d must be -1d
my $cpu_max_filter = 100;                   # my $cpu_max_filter = 100;  # max 10k peak in % is allowed (in fact it cannot by higher than 1k now when 1 logical CPU == 0.1 entitlement)

$DEBUG = 1;

open( OUT, ">> $errlog" ) if $DEBUG == 2;

print OUT "$QUERY_STRING\n" if $DEBUG == 2;

#`echo "00 $QUERY_STRING" >> /tmp/xx66`;

( my $util, my $inp_data, my $week, my $month, my $year, my $result_file, my $week_no, my $print_it, my $xport, my $smonth, my $emonth, my $hmc, my $server_list ) = split( /&/, $QUERY_STRING );

$hmc         =~ s/hmc=//;
$util        =~ s/util=//;
$inp_data    =~ s/input=//;                                           # step in fact
$smonth      =~ s/smonth=//;
$emonth      =~ s/emonth=//;
$month       =~ s/month=//;
$year        =~ s/year=//;
$week_no     =~ s/weekno=//;
$week        =~ s/week=//;
$print_it    =~ s/print=//;
$xport       =~ s/xport=//;
$week        =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
$week        =~ s/\+/ /g;
$result_file =~ s/result=//;                                          # file to keep results which is counted in virtual-cpu-acc-cgi.pl
$result_file =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
$result_file =~ s/\+/ /g;
my $result_file_full = "/var/tmp/" . $result_file;
my $detail           = 0;

if ( isdigit($inp_data) && $inp_data > 0 && $inp_data < 86401 ) {
  $STEP = $inp_data;
}

# check whether SDMC or HMC --> on the HMC it uses daily graphs as this filters outages
# no no --> olways rrd/rrm (daily data)
my $type_sam = "m";

# XPORT is export to XML and then to CVS
if ($xport) {

  # It should be here to do not influence normal report when XML is not in Perl
  require "$bindir/xml.pl";

  # use XML::Simple; --> it has to be in separete file
  print "Content-type: application/octet-stream\n";

  # for normal content type is printed just before picture print to be able print
  # text/html error if appears
}
else {
  print "Content-type: image/png\n\n";
}

# it must go into a temp file as direct stdout from RRDTOOL somehow does not work for me
my $name     = "/var/tmp/lpar2rrd-virtual$$.png";
my $act_time = localtime();

if ( !-d "$webdir" ) {
  die "$act_time: Pls set correct path to Web server pages, it does not exist here: $webdir\n";
}

# start RRD via a pipe
if ( !-f "$rrdtool" ) {
  die "$act_time: Set correct path to rrdtool binarry, it does not exist here: $rrdtool\n";
}
RRDp::start "$rrdtool";

graph_multi( $STEP, $util, $week, $month, $year, "w", $name, $type_sam, $detail, $week_no, $smonth, $emonth, $hmc, $server_list );

# close RRD pipe
RRDp::end;

# exclude Export here
if ( !$xport ) {
  if ( $print_it > 0 ) {
    print_png();
  }
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

sub err_html {
  my $text = shift;
  my $name = "$inputdir/tmp/general_error.png";

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

sub xport_print {
  my $xml_org  = shift;
  my $multi    = shift;
  my $step_new = shift;
  my $xml      = "";

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

  if ( $step_new > 300 ) {
    print join( ";", 'Day.Month.Year Hour', @{ $xml->{meta}{legend}{entry} } ), "\n";
  }
  else {
    print join( ";", 'Day.Month.Year Hour:Minute', @{ $xml->{meta}{legend}{entry} } ), "\n";
  }

  my $first = 0;
  my $time  = 0;
  foreach my $row ( @{ $xml->{data}{row} } ) {
    if ( $first == 0 ) {

      #print "$line\n";
      $first = 1;
      next;
    }
    if ( $step_new > 300 ) {
      $time = strftime "%d.%m.%y %H", localtime( $row->{t} );
    }
    else {
      $time = strftime "%d.%m.%y %H:%M", localtime( $row->{t} );
    }
    my $line = join( ";", $time, @{ $row->{v} } );
    $line =~ s/NaNQ/0/g;
    $line =~ s/NaN/0/g;
    $line =~ s/nan/0/g;    # rrdto0ol v 1.2.27
    my @line_parse = split( /;/, $line );

    # formate numbers to one decimal
    my $first_item = 0;
    foreach my $item (@line_parse) {
      if ( $first_item == 0 ) {
        print "$item";
        $first_item = 1;
        next;
      }
      else {
        my $out = sprintf( "%.2f", $item );
        $out =~ s/\./,/g;    # use "," as a decimal separator
        print ";$out";
      }
    }
    print "\n";
  }
  return 0;
}

sub graph_multi {
  my ( $step_new, $util, $week, $month, $year, $type, $name_out, $type_sam, $detail, $week_no, $smonth, $emonth, $hmc, $server_list ) = @_;

  #my @server_list = @{$server_list_tmp};
  my $text       = "";
  my $xgrid      = "";
  my $t          = "COMMENT: ";
  my $t2         = "COMMENT:\\n";
  my $last       = "COMMENT: ";
  my $act_time   = localtime();
  my $act_time_u = time();
  my $req_time   = 0;
  my $font_def   = "--font=DEFAULT:8:";
  my $font_tit   = "--font=TITLE:9:";
  my $line_items = 0;                     # how many items in the legend per a line (default 2, when detail then 3)
  my $stime      = 0;
  my $etime      = 0;

  if ( $smonth > 0 && $emonth > 0 ) {

    # monthly summary only for xport XLS
    $stime = $smonth;
    $etime = $emonth;
  }
  else {
    ( $stime, $etime ) = split( / /, $week );
  }

  # 48 colors like for HMC bellow + 216 basic HTML colors x 6 == 1296 + 48
  my @color = ( "#FF0000", "#0000FF", "#00FF00", "#FFFF00", "#FF3399", "#00FFFF", "#999933", "#0099CC", "#3300CC", "#FF8080", "#FFFF80", "#80FF80", "#00FF80", "#80FFFF", "#0080FF", "#FF80C0", "#FF80FF", "#FF0000", "#FFFF00", "#80FF00", "#00FF40", "#00FFFF", "#0080C0", "#8080C0", "#FF00FF", "#804040", "#FF8040", "#00FF00", "#008080", "#004080", "#8080FF", "#800040", "#FF0080", "#800000", "#FF8000", "#008000", "#008040", "#0000FF", "#0000A0", "#800080", "#8000FF", "#400000", "#804000", "#004000", "#004040", "#000080", "#000040", "#400040", "#400080", "#000000", "#808000", "#808040", "#808080", "#408080", "#C0C0C0", "#400040", "#AAAAAA", "#CC0000", "#FF0000", "#CC00CC", "#FF00CC", "#0000CC", "#0000FF", "#00CCCC", "#00FFFF", "#00CC00", "#00FF00", "#CCCC00", "#000000", "#FFFF00", "#333300", "#FFFFFF", "#330000", "#999990", "#336600", "#FFCC00", "#339900", "#FF9900", "#33CC00", "#FF6600", "#33FF00", "#FF3300", "#66FF00", "#660000", "#663300", "#66CC00", "#669900", "#666600", "#330033", "#FFFF33", "#333333", "#FF0033", "#336633", "#FFCC33", "#339933", "#FF9933", "#33CC33", "#FF6633", "#33FF33", "#FF3333", "#66FF33", "#660033", "#663333", "#66CC33", "#669933", "#666633", "#330066", "#FFFF66", "#333366", "#FF0066", "#336666", "#FFCC66", "#339966", "#FF9966", "#33CC66", "#FF6666", "#33FF66", "#FF3366", "#66FF66", "#660066", "#663366", "#66CC66", "#669966", "#666666", "#330099", "#FFFF99", "#333399", "#FF0099", "#336699", "#FFCC99", "#339999", "#FF9999", "#33CC99", "#FF6699", "#33FF99", "#FF3399", "#66FF99", "#660099", "#663399", "#66CC99", "#669999", "#666699", "#3300CC", "#FFFFCC", "#3333CC", "#3366CC", "#FFCCCC", "#3399CC", "#FF99CC", "#33CCCC", "#FF66CC", "#33FFCC", "#FF33CC", "#66FFCC", "#6600CC", "#6633CC", "#66CCCC", "#6699CC", "#6666CC", "#3300FF", "#FFFFFF", "#3333FF", "#FF00FF", "#3366FF", "#FFCCFF", "#3399FF", "#FF99FF", "#33CCFF", "#FF66FF", "#33FFFF", "#FF33FF", "#66FFFF", "#6600FF", "#6633FF", "#66CCFF", "#6699FF", "#6666FF", "#CCFFFF", "#0033FF", "#CC00FF", "#0066FF", "#CCCCFF", "#0099FF", "#CC99FF", "#00CCFF", "#CC66FF", "#CC33FF", "#99FFFF", "#9900FF", "#9933FF", "#99CCFF", "#9999FF", "#9966FF", "#CCFFCC", "#0033CC", "#0066CC", "#CCCCCC", "#0099CC", "#CC99CC", "#CC66CC", "#00FFCC", "#CC33CC", "#99FFCC", "#9900CC", "#9933CC", "#99CCCC", "#9999CC", "#9966CC", "#000099", "#CCFF99", "#003399", "#CC0099", "#006699", "#CCCC99", "#009999", "#CC9999", "#00CC99", "#CC6699", "#00FF99", "#CC3399", "#99FF99", "#990099", "#993399", "#99CC99", "#999999", "#996699", "#000066", "#CCFF66", "#003366", "#CC0066", "#006666", "#CCCC66", "#009966", "#CC9966", "#00CC66", "#CC6666", "#00FF66", "#CC3366", "#99FF66", "#990066", "#993366", "#99CC66", "#999966", "#996666", "#000033", "#CCFF33", "#003333", "#CC0033", "#006633", "#CCCC33", "#009933", "#CC9933", "#00CC33", "#CC6633", "#00FF33", "#CC3333", "#99FF33", "#990033", "#993333", "#99CC33", "#999933", "#996633", "#CCFF00", "#003300", "#006600", "#009900", "#CC9900", "#CC6600", "#CC3300", "#99FF00", "#990000", "#993300", "#99CC00", "#999900", "#996600", "#CC0000", "#FF0000", "#CC00CC", "#FF00CC", "#0000CC", "#0000FF", "#00CCCC", "#00FFFF", "#00CC00", "#00FF00", "#CCCC00", "#FFFF00", "#000000", "#999999", "#FFFFFF", "#330000", "#333300", "#336600", "#FFCC00", "#339900", "#FF9900", "#33CC00", "#FF6600", "#33FF00", "#FF3300", "#66FF00", "#660000", "#663300", "#66CC00", "#669900", "#666600", "#330033", "#FFFF33", "#333333", "#FF0033", "#336633", "#FFCC33", "#339933", "#FF9933", "#33CC33", "#FF6633", "#33FF33", "#FF3333", "#66FF33", "#660033", "#663333", "#66CC33", "#669933", "#666633", "#330066", "#FFFF66", "#333366", "#FF0066", "#336666", "#FFCC66", "#339966", "#FF9966", "#33CC66", "#FF6666", "#33FF66", "#FF3366", "#66FF66", "#660066", "#663366", "#66CC66", "#669966", "#666666", "#330099", "#FFFF99", "#333399", "#FF0099", "#336699", "#FFCC99", "#339999", "#FF9999", "#33CC99", "#FF6699", "#33FF99", "#FF3399", "#66FF99", "#660099", "#663399", "#66CC99", "#669999", "#666699", "#3300CC", "#FFFFCC", "#3333CC", "#3366CC", "#FFCCCC", "#3399CC", "#FF99CC", "#33CCCC", "#FF66CC", "#33FFCC", "#FF33CC", "#66FFCC", "#6600CC", "#6633CC", "#66CCCC", "#6699CC", "#6666CC", "#3300FF", "#FFFFFF", "#3333FF", "#FF00FF", "#3366FF", "#FFCCFF", "#3399FF", "#FF99FF", "#33CCFF", "#FF66FF", "#33FFFF", "#FF33FF", "#66FFFF", "#6600FF", "#6633FF", "#66CCFF", "#6699FF", "#6666FF", "#CCFFFF", "#0033FF", "#CC00FF", "#0066FF", "#CCCCFF", "#0099FF", "#CC99FF", "#00CCFF", "#CC66FF", "#CC33FF", "#99FFFF", "#9900FF", "#9933FF", "#99CCFF", "#9999FF", "#9966FF", "#CCFFCC", "#0033CC", "#0066CC", "#CCCCCC", "#0099CC", "#CC99CC", "#CC66CC", "#00FFCC", "#CC33CC", "#99FFCC", "#9900CC", "#9933CC", "#99CCCC", "#9999CC", "#9966CC", "#000099", "#CCFF99", "#003399", "#CC0099", "#006699", "#CCCC99", "#009999", "#CC9999", "#00CC99", "#CC6699", "#00FF99", "#CC3399", "#99FF99", "#990099", "#993399", "#99CC99", "#999999", "#996699", "#000066", "#CCFF66", "#003366", "#CC0066", "#006666", "#CCCC66", "#009966", "#CC9966", "#00CC66", "#CC6666", "#00FF66", "#CC3366", "#99FF66", "#990066", "#993366", "#99CC66", "#999966", "#996666", "#000033", "#CCFF33", "#003333", "#CC0033", "#006633", "#CCCC33", "#009933", "#CC9933", "#00CC33", "#CC6633", "#00FF33", "#CC3333", "#99FF33", "#990033", "#993333", "#99CC33", "#999933", "#996633", "#CCFF00", "#003300", "#006600", "#009900", "#CC9900", "#CC6600", "#CC3300", "#99FF00", "#990000", "#993300", "#99CC00", "#999900", "#996600", "#CC0000", "#FF0000", "#CC00CC", "#FF00CC", "#0000CC", "#0000FF", "#00CCCC", "#00FFFF", "#00CC00", "#00FF00", "#CCCC00", "#FFFF00", "#000000", "#999999", "#FFFFFF", "#330000", "#333300", "#336600", "#FFCC00", "#339900", "#FF9900", "#33CC00", "#FF6600", "#33FF00", "#FF3300", "#66FF00", "#660000", "#663300", "#66CC00", "#669900", "#666600", "#330033", "#FFFF33", "#333333", "#FF0033", "#336633", "#FFCC33", "#339933", "#FF9933", "#33CC33", "#FF6633", "#33FF33", "#FF3333", "#66FF33", "#660033", "#663333", "#66CC33", "#669933", "#666633", "#330066", "#FFFF66", "#333366", "#FF0066", "#336666", "#FFCC66", "#339966", "#FF9966", "#33CC66", "#FF6666", "#33FF66", "#FF3366", "#66FF66", "#660066", "#663366", "#66CC66", "#669966", "#666666", "#330099", "#FFFF99", "#333399", "#FF0099", "#336699", "#FFCC99", "#339999", "#FF9999", "#33CC99", "#FF6699", "#33FF99", "#FF3399", "#66FF99", "#660099", "#663399", "#66CC99", "#669999", "#666699", "#3300CC", "#FFFFCC", "#3333CC", "#3366CC", "#FFCCCC", "#3399CC", "#FF99CC", "#33CCCC", "#FF66CC", "#33FFCC", "#FF33CC", "#66FFCC", "#6600CC", "#6633CC", "#66CCCC", "#6699CC", "#6666CC", "#3300FF", "#FFFFFF", "#3333FF", "#FF00FF", "#3366FF", "#FFCCFF", "#3399FF", "#FF99FF", "#33CCFF", "#FF66FF", "#33FFFF", "#FF33FF", "#66FFFF", "#6600FF", "#6633FF", "#66CCFF", "#6699FF", "#6666FF", "#CCFFFF", "#0033FF", "#CC00FF", "#0066FF", "#CCCCFF", "#0099FF", "#CC99FF", "#00CCFF", "#CC66FF", "#CC33FF", "#99FFFF", "#9900FF", "#9933FF", "#99CCFF", "#9999FF", "#9966FF", "#CCFFCC", "#0033CC", "#0066CC", "#CCCCCC", "#0099CC", "#CC99CC", "#CC66CC", "#00FFCC", "#CC33CC", "#99FFCC", "#9900CC", "#9933CC", "#99CCCC", "#9999CC", "#9966CC", "#000099", "#CCFF99", "#003399", "#CC0099", "#006699", "#CCCC99", "#009999", "#CC9999", "#00CC99", "#CC6699", "#00FF99", "#CC3399", "#99FF99", "#990099", "#993399", "#99CC99", "#999999", "#996699", "#000066", "#CCFF66", "#003366", "#CC0066", "#006666", "#CCCC66", "#009966", "#CC9966", "#00CC66", "#CC6666", "#00FF66", "#CC3366", "#99FF66", "#990066", "#993366", "#99CC66", "#999966", "#996666", "#000033", "#CCFF33", "#003333", "#CC0033", "#006633", "#CCCC33", "#009933", "#CC9933", "#00CC33", "#CC6633", "#00FF33", "#CC3333", "#99FF33", "#990033", "#993333", "#99CC33", "#999933", "#996633", "#CCFF00", "#003300", "#006600", "#009900", "#CC9900", "#CC6600", "#CC3300", "#99FF00", "#990000", "#993300", "#99CC00", "#999900", "#996600", "#CC0000", "#FF0000", "#CC00CC", "#FF00CC", "#0000CC", "#0000FF", "#00CCCC", "#00FFFF", "#00CC00", "#00FF00", "#CCCC00", "#FFFF00", "#000000", "#999999", "#FFFFFF", "#330000", "#333300", "#336600", "#FFCC00", "#339900", "#FF9900", "#33CC00", "#FF6600", "#33FF00", "#FF3300", "#66FF00", "#660000", "#663300", "#66CC00", "#669900", "#666600", "#330033", "#FFFF33", "#333333", "#FF0033", "#336633", "#FFCC33", "#339933", "#FF9933", "#33CC33", "#FF6633", "#33FF33", "#FF3333", "#66FF33", "#660033", "#663333", "#66CC33", "#669933", "#666633", "#330066", "#FFFF66", "#333366", "#FF0066", "#336666", "#FFCC66", "#339966", "#FF9966", "#33CC66", "#FF6666", "#33FF66", "#FF3366", "#66FF66", "#660066", "#663366", "#66CC66", "#669966", "#666666", "#330099", "#FFFF99", "#333399", "#FF0099", "#336699", "#FFCC99", "#339999", "#FF9999", "#33CC99", "#FF6699", "#33FF99", "#FF3399", "#66FF99", "#660099", "#663399", "#66CC99", "#669999", "#666699", "#3300CC", "#FFFFCC", "#3333CC", "#3366CC", "#FFCCCC", "#3399CC", "#FF99CC", "#33CCCC", "#FF66CC", "#33FFCC", "#FF33CC", "#66FFCC", "#6600CC", "#6633CC", "#66CCCC", "#6699CC", "#6666CC", "#3300FF", "#FFFFFF", "#3333FF", "#FF00FF", "#3366FF", "#FFCCFF", "#3399FF", "#FF99FF", "#33CCFF", "#FF66FF", "#33FFFF", "#FF33FF", "#66FFFF", "#6600FF", "#6633FF", "#66CCFF", "#6699FF", "#6666FF", "#CCFFFF", "#0033FF", "#CC00FF", "#0066FF", "#CCCCFF", "#0099FF", "#CC99FF", "#00CCFF", "#CC66FF", "#CC33FF", "#99FFFF", "#9900FF", "#9933FF", "#99CCFF", "#9999FF", "#9966FF", "#CCFFCC", "#0033CC", "#0066CC", "#CCCCCC", "#0099CC", "#CC99CC", "#CC66CC", "#00FFCC", "#CC33CC", "#99FFCC", "#9900CC", "#9933CC", "#99CCCC", "#9999CC", "#9966CC", "#000099", "#CCFF99", "#003399", "#CC0099", "#006699", "#CCCC99", "#009999", "#CC9999", "#00CC99", "#CC6699", "#00FF99", "#CC3399", "#99FF99", "#990099", "#993399", "#99CC99", "#999999", "#996699", "#000066", "#CCFF66", "#003366", "#CC0066", "#006666", "#CCCC66", "#009966", "#CC9966", "#00CC66", "#CC6666", "#00FF66", "#CC3366", "#99FF66", "#990066", "#993366", "#99CC66", "#999966", "#996666", "#000033", "#CCFF33", "#003333", "#CC0033", "#006633", "#CCCC33", "#009933", "#CC9933", "#00CC33", "#CC6633", "#00FF33", "#CC3333", "#99FF33", "#990033", "#993333", "#99CC33", "#999933", "#996633", "#CCFF00", "#003300", "#006600", "#009900", "#CC9900", "#CC6600", "#CC3300", "#99FF00", "#990000", "#993300", "#99CC00", "#999900", "#996600", "#CC0000", "#FF0000", "#CC00CC", "#FF00CC", "#0000CC", "#0000FF", "#00CCCC", "#00FFFF", "#00CC00", "#00FF00", "#CCCC00", "#FFFF00", "#000000", "#999999", "#FFFFFF", "#330000", "#333300", "#336600", "#FFCC00", "#339900", "#FF9900", "#33CC00", "#FF6600", "#33FF00", "#FF3300", "#66FF00", "#660000", "#663300", "#66CC00", "#669900", "#666600", "#330033", "#FFFF33", "#333333", "#FF0033", "#336633", "#FFCC33", "#339933", "#FF9933", "#33CC33", "#FF6633", "#33FF33", "#FF3333", "#66FF33", "#660033", "#663333", "#66CC33", "#669933", "#666633", "#330066", "#FFFF66", "#333366", "#FF0066", "#336666", "#FFCC66", "#339966", "#FF9966", "#33CC66", "#FF6666", "#33FF66", "#FF3366", "#66FF66", "#660066", "#663366", "#66CC66", "#669966", "#666666", "#330099", "#FFFF99", "#333399", "#FF0099", "#336699", "#FFCC99", "#339999", "#FF9999", "#33CC99", "#FF6699", "#33FF99", "#FF3399", "#66FF99", "#660099", "#663399", "#66CC99", "#669999", "#666699", "#3300CC", "#FFFFCC", "#3333CC", "#3366CC", "#FFCCCC", "#3399CC", "#FF99CC", "#33CCCC", "#FF66CC", "#33FFCC", "#FF33CC", "#66FFCC", "#6600CC", "#6633CC", "#66CCCC", "#6699CC", "#6666CC", "#3300FF", "#FFFFFF", "#3333FF", "#FF00FF", "#3366FF", "#FFCCFF", "#3399FF", "#FF99FF", "#33CCFF", "#FF66FF", "#33FFFF", "#FF33FF", "#66FFFF", "#6600FF", "#6633FF", "#66CCFF", "#6699FF", "#6666FF", "#CCFFFF", "#0033FF", "#CC00FF", "#0066FF", "#CCCCFF", "#0099FF", "#CC99FF", "#00CCFF", "#CC66FF", "#CC33FF", "#99FFFF", "#9900FF", "#9933FF", "#99CCFF", "#9999FF", "#9966FF", "#CCFFCC", "#0033CC", "#0066CC", "#CCCCCC", "#0099CC", "#CC99CC", "#CC66CC", "#00FFCC", "#CC33CC", "#99FFCC", "#9900CC", "#9933CC", "#99CCCC", "#9999CC", "#9966CC", "#000099", "#CCFF99", "#003399", "#CC0099", "#006699", "#CCCC99", "#009999", "#CC9999", "#00CC99", "#CC6699", "#00FF99", "#CC3399", "#99FF99", "#990099", "#993399", "#99CC99", "#999999", "#996699", "#000066", "#CCFF66", "#003366", "#CC0066", "#006666", "#CCCC66", "#009966", "#CC9966", "#00CC66", "#CC6666", "#00FF66", "#CC3366", "#99FF66", "#990066", "#993366", "#99CC66", "#999966", "#996666", "#000033", "#CCFF33", "#003333", "#CC0033", "#006633", "#CCCC33", "#009933", "#CC9933", "#00CC33", "#CC6633", "#00FF33", "#CC3333", "#99FF33", "#990033", "#993333", "#99CC33", "#999933", "#996633", "#CCFF00", "#003300", "#006600", "#009900", "#CC9900", "#CC6600", "#CC3300", "#99FF00", "#990000", "#993300", "#99CC00", "#999900", "#996600", "#CC0000", "#FF0000", "#CC00CC", "#FF00CC", "#0000CC", "#0000FF", "#00CCCC", "#00FFFF", "#00CC00", "#00FF00", "#CCCC00", "#FFFF00", "#000000", "#999999", "#FFFFFF", "#330000", "#333300", "#336600", "#FFCC00", "#339900", "#FF9900", "#33CC00", "#FF6600", "#33FF00", "#FF3300", "#66FF00", "#660000", "#663300", "#66CC00", "#669900", "#666600", "#330033", "#FFFF33", "#333333", "#FF0033", "#336633", "#FFCC33", "#339933", "#FF9933", "#33CC33", "#FF6633", "#33FF33", "#FF3333", "#66FF33", "#660033", "#663333", "#66CC33", "#669933", "#666633", "#330066", "#FFFF66", "#333366", "#FF0066", "#336666", "#FFCC66", "#339966", "#FF9966", "#33CC66", "#FF6666", "#33FF66", "#FF3366", "#66FF66", "#660066", "#663366", "#66CC66", "#669966", "#666666", "#330099", "#FFFF99", "#333399", "#FF0099", "#336699", "#FFCC99", "#339999", "#FF9999", "#33CC99", "#FF6699", "#33FF99", "#FF3399", "#66FF99", "#660099", "#663399", "#66CC99", "#669999", "#666699", "#3300CC", "#FFFFCC", "#3333CC", "#3366CC", "#FFCCCC", "#3399CC", "#FF99CC", "#33CCCC", "#FF66CC", "#33FFCC", "#FF33CC", "#66FFCC", "#6600CC", "#6633CC", "#66CCCC", "#6699CC", "#6666CC", "#3300FF", "#FFFFFF", "#3333FF", "#FF00FF", "#3366FF", "#FFCCFF", "#3399FF", "#FF99FF", "#33CCFF", "#FF66FF", "#33FFFF", "#FF33FF", "#66FFFF", "#6600FF", "#6633FF", "#66CCFF", "#6699FF", "#6666FF", "#CCFFFF", "#0033FF", "#CC00FF", "#0066FF", "#CCCCFF", "#0099FF", "#CC99FF", "#00CCFF", "#CC66FF", "#CC33FF", "#99FFFF", "#9900FF", "#9933FF", "#99CCFF", "#9999FF", "#9966FF", "#CCFFCC", "#0033CC", "#0066CC", "#CCCCCC", "#0099CC", "#CC99CC", "#CC66CC", "#00FFCC", "#CC33CC", "#99FFCC", "#9900CC", "#9933CC", "#99CCCC", "#9999CC", "#9966CC", "#000099", "#CCFF99", "#003399", "#CC0099", "#006699", "#CCCC99", "#009999", "#CC9999", "#00CC99", "#CC6699", "#00FF99", "#CC3399", "#99FF99", "#990099", "#993399", "#99CC99", "#999999", "#996699", "#000066", "#CCFF66", "#003366", "#CC0066", "#006666", "#CCCC66", "#009966", "#CC9966", "#00CC66", "#CC6666", "#00FF66", "#CC3366", "#99FF66", "#990066", "#993366", "#99CC66", "#999966", "#996666", "#000033", "#CCFF33", "#003333", "#CC0033", "#006633", "#CCCC33", "#009933", "#CC9933", "#00CC33", "#CC6633", "#00FF33", "#CC3333", "#99FF33", "#990033", "#993333", "#99CC33", "#999933", "#996633", "#CCFF00", "#003300", "#006600", "#009900", "#CC9900", "#CC6600", "#CC3300", "#99FF00", "#990000", "#993300", "#99CC00", "#999900", "#996600" );

  if ( $detail == 1 ) {
    $font_def   = "--font=DEFAULT:10:";
    $font_tit   = "--font=TITLE:13:";
    $line_items = 2;
  }

  my $stime_text = localtime($stime);
  my $etime_text = localtime($etime);

  if ( $type =~ m/d/ ) {
    $text = "day";
    if ( $detail == 0 ) {
      $xgrid = "MINUTE:60:HOUR:2:HOUR:4:0:%H";
    }
    else {
      $xgrid = "MINUTE:60:HOUR:1:HOUR:1:0:%H";
    }
  }
  if ( $type =~ m/w/ ) {
    $text = "$stime_text - $etime_text";
    if ( $detail == 0 ) {

      #$xgrid="HOUR:8:DAY:1:DAY:1:0:%a";
      #$xgrid="\"HOUR:24:HOUR:6:HOUR:24:0:%a %H\"";
      $xgrid = "HOUR:12:DAY:1:DAY:1:0:%d";
    }
    else {
      $xgrid = "\"HOUR:12:HOUR:6:HOUR:12:0:%a %H\"";
    }
  }
  if ( $type =~ m/m/ ) {
    $text = "month";
    if ( $detail == 0 ) {
      $xgrid = "DAY:1:DAY:2:DAY:7:0:%U";
    }
    else {
      $xgrid = "HOUR:12:DAY:1:DAY:1:0:%d";
    }
  }
  if ( $type =~ m/y/ ) {
    $text = "year";
    if ( $detail == 0 ) {
      $xgrid = "MONTH:1:MONTH:1:MONTH:1:0:%b";
    }
    else {
      $xgrid = "MONTH:1:MONTH:1:MONTH:1:0:%b";
    }
  }

  my $header = "$text";
  $header =~ s/00:00:00 //g;

  # Create list of servers
  my @files      = "";
  my $files_indx = 0;
  my @server     = "";
  ( my @server_rows ) = split( /SERVERS=/, $server_list );
  print OUT "001 $week_no : $server_list\n" if $DEBUG == 2;
  foreach my $line (@server_rows) {
    chomp($line);
    $line =~ s/\%20$//g;
    $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $line =~ s/ Report=Generate\+Report//g;
    $line =~ s/\+/ /g;
    $line =~ s/^SERVERS=//g;
    if ( $line eq '' ) {
      next;    # trash
    }
    my $managedname = $line;

    # get first available HMC
    if ( $hmc =~ m/^auto$/ ) {
      my @hmcs     = <$wrkdir/$managedname/*>;
      my $upd_time = 0;                          # find out the HMC with the latest timestamp
      foreach my $line (@hmcs) {
        chomp($line);
        print OUT "088 $line\n" if $DEBUG == 2;
        if ( !-d $line ) {
          next;
        }
        my $pool         = "$line/pool.rrm";
        my $rrd_upd_time = ( stat("$pool") )[9];
        if ( $rrd_upd_time > $upd_time ) {
          $line =~ s/$wrkdir\/$managedname\///;
          $hmc      = $line;
          $upd_time = $rrd_upd_time;
        }
        print OUT "088 $line\n" if $DEBUG == 2;
      }
    }

    #`echo "09 $hmc" >> /tmp/xx66`;

    $files[$files_indx]  = $wrkdir . "/" . $managedname . "/" . $hmc . "/pool.rr$type_sam";
    $server[$files_indx] = $managedname;
    print OUT "002 $week_no : $line : $files_indx : $server_list : $files[$files_indx]\n" if $DEBUG == 2;
    $files_indx++;
  }
  if ( $files_indx == 0 ) {
    error("No server has been selected");
    err_html();
  }

  my $file      = "";
  my $i         = 0;
  my $lpar      = "";
  my $cmd       = "";
  my $j         = 0;
  my $cmd_xport = "";

  $cmd .= "graph \\\"$name_out\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start $stime-120";
  $cmd .= " --end $etime-120";
  $cmd .= " --imgformat PNG";
  $cmd .= " --slope-mode";
  $cmd .= " --width=$width";
  $cmd .= " --height=$height";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";

  if ( $util == 0 ) {
    $cmd .= " --vertical-label=\\\"Virtual CPUs\\\"";
  }
  else {
    $cmd .= " --vertical-label=\\\"Utilization in CPU cores\\\"";
  }
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " $font_def";
  $cmd .= " $font_tit";
  if ( $detail == 1 ) {
    if ( $util == 0 ) {
      $cmd .= " COMMENT:\\\"Virtual CPUs assigned\\:    average                               average                               average\\l\\\"";
    }
    else {
      $cmd .= " COMMENT:\\\"CPU utilization      \\:    average                               average                               average\\l\\\"";
    }
  }
  else {
    if ( $util == 0 ) {
      $cmd .= " COMMENT:\\\"Virtual CPUs assigned\\:                        average\\l\\\"";
    }
    else {
      $cmd .= " COMMENT:\\\"CPU utilization      \\:                        average\\l\\\"";
    }
    $cmd .= " COMMENT:\\\"  LPAR                Server\\l\\\"";
  }

  my $cmd_sum = $cmd;    # store a linne for finding out Total value

  my $gtype       = "AREA";
  my $col_indx    = 0;
  my $line_indx   = 0;        # place enter evry 3rd line
  my $server_indx = 0;
  my $prev        = -1;
  my $last_vol    = -1;

  foreach my $server_pool (@files) {

    # go through all servers
    chomp($server_pool);
    print OUT "003 $week_no : $server_pool\n" if $DEBUG == 2;

    $server_pool =~ s/pool\.rr$type_sam$//;
    opendir( LDIR, "$server_pool" ) || die "$act_time: directory does not exists : $server_pool";
    my @lpar_list = grep( /\.rr$type_sam$/, readdir(LDIR) );

    #@lpar_list = sort { lc $a cmp lc $b } @lpar_list;
    closedir(LDIR);

    # go through all LPARS
    foreach $file (@lpar_list) {
      chomp($file);

      $lpar = $file;
      $lpar =~ s/.rrm//;
      $lpar =~ s/.rrd//;
      $lpar =~ s/\&\&1/\//g;

      # Exclude pools and memory
      if ( $lpar =~ m/^pool$/ || $lpar =~ m/^mem$/ || $lpar =~ /^SharedPool[0-9]$/ || $lpar =~ m/^SharedPool[1-9][0-9]$/ || $lpar =~ m/^mem-pool$/ || $lpar =~ m/^cod$/ ) {
        next;
      }

      if ( !-f "$server_pool/$file" ) {
        next;
      }

      my $file_time = ( stat("$server_pool/$file") )[9];
      if ( $file_time < $stime ) {

        #print STDERR "033 $file_time < $stime : $server_pool/$file\n";
        next;    # old lpars, not having data in the period
      }

      RRDp::cmd qq(last "$server_pool/$file" );
      my $last_rec_rrd = RRDp::read;
      chomp($$last_rec_rrd);
      my $last_rec = $$last_rec_rrd;

      if ( $last_rec < $stime ) {

        #print STDERR "033 $last_rec  < $stime : $server_pool/$file : last_rec\n";
        next;    # old lpars, not having data in the period
      }

      if ( has_data_in_period( "$server_pool/$file", $stime, $etime, $width, $height, $step_new ) == 0 ) {

        #print STDERR "033 $last_rec  < $stime : $server_pool/$file : last_rec\n";
        next;    # old lpars, not having data in the period
                 # it must be checked here to aviod switched off lpars
      }

      # find out server name
      #my $legend = sprintf ("%-20s","$server[$server_indx]").sprintf ("%-20s","$lpar");
      my $legend = sprintf( "%-20s", "$lpar" ) . sprintf( "%-20s", "$server[$server_indx]" );
      print OUT "004 $week_no : $server[$server_indx] : $lpar : $legend \n" if $DEBUG == 2;

      $legend =~ s/:/\\:/g;    # anti ':'
      my $server_pool_file = "$server_pool/$file";
      $server_pool_file =~ s/:/\\:/g;

      # bulid RRDTool cmd
      $cmd .= " DEF:ent${i}=\\\"$server_pool_file\\\":entitled_cycles:AVERAGE";
      $cmd .= " DEF:cap${i}=\\\"$server_pool_file\\\":capped_cycles:AVERAGE";
      $cmd .= " DEF:uncap${i}=\\\"$server_pool_file\\\":uncapped_cycles:AVERAGE";
      $cmd .= " CDEF:tot${i}=cap${i},uncap${i},+";

      #$cmd .= " CDEF:util${i}=tot${i},ent${i},/";
      $cmd .= " CDEF:util${i}=tot${i},ent${i},/,$cpu_max_filter,GT,UNKN,tot${i},ent${i},/,IF";    # filter peeks

      $cmd_xport .= "\\\"DEF:ent${i}=$server_pool_file:entitled_cycles:AVERAGE\\\"\n";
      $cmd_xport .= "\\\"DEF:cap${i}=$server_pool_file:capped_cycles:AVERAGE\\\"\n";
      $cmd_xport .= "\\\"DEF:uncap${i}=$server_pool_file:uncapped_cycles:AVERAGE\\\"\n";
      $cmd_xport .= "\\\"CDEF:tot${i}=cap${i},uncap${i},+\\\"\n";

      #$cmd_xport .= "\\\"CDEF:util${i}=tot${i},ent${i},/\\\"\n";
      $cmd_xport .= "\\\"CDEF:util${i}=tot${i},ent${i},/,$cpu_max_filter,GT,UNKN,tot${i},ent${i},/,IF\\\"\n";    # filter peeks

      $cmd_sum .= " DEF:ent${i}=\\\"$server_pool_file\\\":entitled_cycles:AVERAGE";
      $cmd_sum .= " DEF:cap${i}=\\\"$server_pool_file\\\":capped_cycles:AVERAGE";
      $cmd_sum .= " DEF:uncap${i}=\\\"$server_pool_file\\\":uncapped_cycles:AVERAGE";
      $cmd_sum .= " CDEF:tot${i}=cap${i},uncap${i},+";

      #$cmd_sum .= " CDEF:util${i}=tot${i},ent${i},/";
      $cmd_sum .= " CDEF:util${i}=tot${i},ent${i},/,$cpu_max_filter,GT,UNKN,tot${i},ent${i},/,IF";               # filter peeks

      if ( $util == 0 ) {

        # CPU allocation
        $cmd .= " DEF:virt-s${i}=\\\"$server_pool_file\\\":virtual_procs:AVERAGE";
        $cmd .= " CDEF:virt${i}=tot${i},0,EQ,0,virt-s${i},IF";

        # --> pokud se lpar vypne tak virtual_procs i curr_proc_units zustava assigned stale!!!
        # takze pokud je cap + uncap + ent == 0 --> virt = 0

        $cmd_xport .= "\\\"DEF:virt-s${i}=$server_pool_file:virtual_procs:AVERAGE\\\"\n";
        $cmd_xport .= "\\\"CDEF:virt${i}=tot${i},0,EQ,0,virt-s${i},IF\\\"\n";

        $cmd_sum .= " DEF:virt-s${i}=\\\"$server_pool_file\\\":virtual_procs:AVERAGE";
        $cmd_sum .= " CDEF:virt${i}=tot${i},0,EQ,0,virt-s${i},IF";
      }
      else {
        # CPU utilization
        $cmd .= " DEF:cur${i}=\\\"$server_pool_file\\\":curr_proc_units:AVERAGE";
        $cmd .= " CDEF:virt${i}=util${i},cur${i},*";                                # normally it is called "utiltot"

        $cmd_xport .= "\\\"DEF:cur${i}=$server_pool_file:curr_proc_units:AVERAGE\\\"\n";
        $cmd_xport .= "\\\"CDEF:virt${i}=util${i},cur${i},*\\\"\n";                        # normally it is called "utiltot"

        $cmd_sum .= " DEF:cur${i}=\\\"$server_pool_file\\\":curr_proc_units:AVERAGE";
        $cmd_sum .= " CDEF:virt${i}=util${i},cur${i},*";                                   # normally it is called "utiltot"
      }

      # No, definitly do not do it as it would have an efect on average value
      #$cmd .= " CDEF:virt${i}=virtnull${i},UN,0,virtnull${i},IF"; # it must be here!!!
      #$cmd_xport .= "\\\"CDEF:virt${i}=virtnull${i},UN,0,virtnull${i},IF\\\"\n"; # it must be here!!!
      #$cmd_sum .= " CDEF:virt${i}=virtnull${i},UN,0,virtnull${i},IF"; # it must be here!!!

      $cmd       .= " $gtype:virt${i}$color[$col_indx]:\\\"$legend\\\"";
      $cmd_xport .= "\\\"XPORT:virt${i}:$legend\\\"\n";

      #$cmd_sum .= " PRINT:virt${i}:AVERAGE:\\\"%5.3lf \\\"";  # MUST be X.3 othervise does not work total ... ???
      # --> print all values and sum them out from rrdtool output
      # No No, on purpose not as lpar can disappear, appear atc, it is a difference to stor2rrd accounting
      #   --> use summ line instead and relay on that data do not containg gaps

      $col_indx++;

      $cmd .= " GPRINT:virt${i}:AVERAGE:\\\"%5.3lf \\\"";

      # get only the summ line for total average
      # there must be NaN == 0 othervise it does not work when an lpar is switched off in the midle of the graph!!!
      if ( $prev == -1 ) {
        $cmd_sum .= " CDEF:virt_sum${i}=virt${i},UN,0,virt${i},IF";

        #$cmd_sum .= " CDEF:virt_sum${i}=virt${i}";
        $prev++;
      }
      else {
        $cmd_sum .= " CDEF:virt_null${i}=virt${i},UN,0,virt${i},IF";
        $cmd_sum .= " CDEF:virt_sum${i}=virt_sum${last_vol},virt_null${i},+";

        #$cmd_sum .= " CDEF:virt_sum${i}=virt_sum${last_vol},virt${i},+";
      }
      $last_vol++;

      $gtype = "STACK";
      $i++;
      if ( $line_indx == $line_items ) {

        # put carriage return after each second lpar in the legend
        $cmd .= " COMMENT:\\\"\\l\\\"";
        $line_indx = 0;
      }
      else {
        $line_indx++;
      }
    }
    $server_indx++;
  }

  $cmd_sum .= " PRINT:virt_sum${last_vol}:AVERAGE:\\\"%8.3lf \\\"";    # MUST be X.3 othervise does not work total ... ???
  $cmd_sum =~ s/\\"/"/g;

  my $tmp_file_sum = "/var/tmp/lpar2rrd-virt-sum.tmp-$$";

  # Find out total value
  open( FH, "> $tmp_file_sum" ) || die "$act_time: Can't open $tmp_file_sum : $!";
  print FH "$cmd_sum\n";
  close(FH);
  print OUT "006 $week_no : $cmd_sum\n" if $DEBUG == 2;

  my $ret = `$rrdtool - < "$tmp_file_sum" 2>&1`;
  print OUT "007 $week_no : $ret\n" if $DEBUG == 2;

  my $total_tmp = 0;
  foreach my $ret_line ( split( /\n/, $ret ) ) {
    chomp($ret_line);

    #print "110 $ret_line\n";
    if ( $ret_line =~ m/:/ || $ret_line =~ m/x/ ) {
      next;
    }
    $ret_line =~ s/0x0//g;
    $ret_line =~ s/ //g;
    $ret_line =~ s/OK.*$//g;
    chomp($ret_line);    # must be here as well !!
    if ( $ret_line eq '' ) {
      next;
    }
    my $ret_digit = isdigit($ret_line);

    #print "111 $ret_line - ret_digit = $ret_digit\n";
    if ( $ret_digit == 0 ) {
      next;
    }
    $total_tmp = $total_tmp + $ret_line;

    #print "112 $ret_line : $total \n";
  }
  close(FH);
  unlink($tmp_file_sum);
  my $total       = sprintf( "%.1f", $total_tmp );    # rounding week total to 1 decimal as was agreed
  my $total_print = sprintf( "%.3f", $total_tmp );    # rounding week total to 3 decimal to have it in the chart only
  $cmd .= " LINE2:$total_print#000000:\\\"Total                                     $total_print\\\"";

  print OUT "008 $week_no : $total : $total_tmp \n" if $DEBUG == 2;

  # write down the result into result file
  my $number_active_days = active_days( $stime, $etime, $month, $year );
  open( FHR, ">> $result_file_full" ) || die "$act_time: Can't open $result_file_full : $!";
  print FHR "$week_no:$number_active_days:$total\n";
  close(FHR);

  #$cmd .= " COMMENT:\\\"  Total                                        $total\\l\\\"";
  $cmd .= " HRULE:0#000000";

  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my $FH;
  my $tmp_file = "/var/tmp/lpar2rrd-virt.tmp-$$";
  open( FH, "> $tmp_file" ) || die "$act_time: Can't open $tmp_file : $!";
  print FH "$cmd\n";
  close(FH);

  if ($xport) {
    $cmd_xport =~ s/\\"/"/g;
    print "Content-Disposition: attachment;filename=$year\_$month\_$week_no.csv\n\n";

    # keep there "-120 secs, otherwise start and enad times are wrong
    RRDp::cmd qq(xport
         "--start" "$stime-$xport_delta"
         "--end" "$etime-$xport_delta";
         "--step" "$step_new"
         "--maxrows" "65000"
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
    xport_print( $out_txt, 1, $step_new );
  }
  else {

    # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
    my $ret = `$rrdtool - < "$tmp_file" 2>&1`;
    if ( $ret =~ "ERROR" ) {
      error("virtual-cpu-acc-work.pl: Multi graph rrdtool error : $ret");
      if ( $ret =~ "is not an RRD file" ) {
        ( my $err, my $file, my $txt ) = split( /'/, $ret );
        error("Removing as it seems to be corrupted: $file");
        unlink("$file") || die "Cannot rm $file : $!";
      }
      else {
        error("virtual-cpu-acc-work.pl: $cmd : Multi graph rrdtool error : $ret");
      }
      err_html();
    }
    unlink("$tmp_file");
  }

  return $total;
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

# it returns number of active days in actual week
sub active_days {
  my $stime      = shift;
  my $etime      = shift;
  my $month      = shift;
  my $year       = shift;
  my $month_next = $month;
  my $year_next  = $year;

  my $stime_month = str2time("$month/1/$year");

  if ( $month < 12 ) {
    $month_next++;
  }
  else {
    $month_next = 1;
    $year_next++;
  }
  my $etime_month = str2time("$month_next/1/$year_next");

  while ( $stime < $stime_month ) {
    $stime = $stime + 86400;
  }

  while ( $etime > $etime_month ) {
    $etime = $etime - 86400;
  }

  my $number_of_days = 0;
  while ( $stime < $etime ) {
    $stime = $stime + 86400;
    $number_of_days++;
  }

  return $number_of_days;

}

# it does not work ideally, if no data in the period then it stil has set curr_proc_units
# rest is 0, it works probably because 0/0 == NaN
sub has_data_in_period {
  my $rrd    = shift;
  my $stime  = shift;
  my $etime  = shift;
  my $width  = shift;
  my $height = shift;
  my $step   = shift;

  $rrd =~ s/:/\\:/g;
  RRDp::cmd qq(graph "$inputdir/tmp/name.png"
      "--start" "$stime"
      "--end" "$etime"
      "--slope-mode"
      "--width=$width"
      "--height=$height"
      "--step=$step"
      "--lower-limit=0.00"
      "--alt-autoscale-max"
      "--interlaced"
      "--upper-limit=0.1"
      "DEF:cur=$rrd:curr_proc_units:AVERAGE"
      "DEF:ent=$rrd:entitled_cycles:AVERAGE"
      "DEF:cap=$rrd:capped_cycles:AVERAGE"
      "DEF:uncap=$rrd:uncapped_cycles:AVERAGE"
      "CDEF:tot=cap,uncap,+"
      "CDEF:util=tot,ent,/"
      "CDEF:utiltot=util,cur,*"
      "PRINT:utiltot:AVERAGE: %5.1lf"
  );
  my $answer = RRDp::read;
  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {

    #print STDERR "NOK $rrd $stime:$etime- $$answer";
    return 0;
  }

  #print STDERR "OK  $rrd $stime:$etime- $$answer";
  return 1;

}

