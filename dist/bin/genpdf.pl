##!/usr/bin/perl
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=perl

use strict;
use warnings;
use utf8;

use CGI::Carp qw(fatalsToBrowser);

use Data::Dumper;
use File::Temp qw/ tempfile/;
use Xorux_lib;

use constant mm   => 25.4 / 72;    # 25.4 mm in an inch, 72 points in an inch
use constant in   => 1 / 72;       # 72 points in an inch
use constant pt   => 1;            # 1 point
use constant A4_x => 210 / mm;     # x points in an A4 page ( 595.2755 )
use constant A4_y => 297 / mm;     # y points in an A4 page ( 841.8897 )

use constant US_x => 216 / mm;     # x points in an US letter page ( 612.2834 )
use constant US_y => 279 / mm;     # y points in an US letter page ( 790.8661 )

# my $app_lc = $ENV{APPNAME};
my $app_lc = "lpar2rrd";
my $app_uc = uc($app_lc);

my $inputdir = $ENV{INPUTDIR}      ||= "";
my $format   = $ENV{PDF_PAGE_SIZE} ||= "A4";
my $perl     = $ENV{PERL};
my @pages    = ();
my $nextpage = 0;

my ( $pagetop, $pagey, $pagex );

if ( $format eq "A4" ) {
  $pagetop = 796;
  $pagey   = A4_y;
  $pagex   = A4_x;
}
else {
  $pagetop = 740;
  $pagey   = US_y;
  $pagex   = US_x;
}
my $now;
my ( $font, $fontb, $logo, $stopped );

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

# print $call , "\n";

# print STDERR Dumper \%PAR;

if ( !defined $PAR{cmd} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";
  exit;
}

if ( $PAR{cmd} eq "list" ) {    ### Get list of credentials
  print "Content-type: text/html\n\n";
  print "<pre>";
  print Dumper \%ENV;
  print Dumper \%PAR;

}
elsif ( $PAR{cmd} eq "test" ) {    ### Get list of credentials
  print "Content-type: application/json\n\n";
  my $errors  = "";
  my @reqmods = qw(PDF::API2 Compress::Zlib Compress::Raw::Zlib);

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
    result( 0, "PDF export", $errors );
  }
  else {
    result( 1, "PDF export" );

    #my $err = eval "&testPDF(); 1;";
    #if (!defined $err) {
    #result(0, "PDF export", "$@");
    #} else {
    #result(1, "PDF export");
    #}
  }

}
elsif ( $PAR{cmd} eq "stop" ) {    ### Get list of credentials
  if ( open( STOP, ">", "/tmp/pdfgen.$PAR{id}.stop" ) ) {
    close STOP;
    print "Content-type: application/json\n\n";
    print "{ \"status\": \"terminated\", \"id\": \"$PAR{id}\"}";
  }
}
elsif ( $PAR{cmd} eq "status" ) {    ### Get list of credentials
  print "Content-type: application/json\n\n";

  if ( -e "/tmp/pdfgen.$PAR{id}.done" ) {
    print "{ \"status\": \"done\", \"id\": \"$PAR{id}\"}";

  }
  elsif ( -e "/tmp/pdfgen.$PAR{id}.stopped" ) {
    print "{ \"status\": \"terminated\", \"id\": \"$PAR{id}\"}";
    unlink "/tmp/pdfgen.$PAR{id}.pdf";
    unlink "/tmp/pdfgen.$PAR{id}.stopped";
    unlink "/tmp/pdfgen.$PAR{id}.done";
    unlink "/tmp/pdfgen.$PAR{id}";

  }
  elsif ( open( my $sf, "<", "/tmp/pdfgen.$PAR{id}" ) ) {
    my $stat = <$sf>;
    chomp $stat;
    my ( $c, $t ) = split ":", $stat;
    close $sf;
    print "{ \"status\": \"pending\", \"id\": \"$PAR{id}\", \"done\": $c, \"total\": $t}";

  }
  else {

    # print STDERR "$inputdir/tmp/pdfgen.$PAR{id} $!\n";
    print "{ \"status\": \"unknown\", \"id\": \"$PAR{id}\"}";
  }

}
elsif ( $PAR{cmd} eq "get" ) {    ### Get generated PDF
  print "Content-type: text/html\n";

  if ( open( PDF, "<", "/tmp/pdfgen.$PAR{id}.pdf" ) ) {
    print "Content-Disposition:attachment;filename=$app_uc-report-" . epoch2iso($now) . ".pdf\n\n";
    binmode PDF;
    while (<PDF>) {
      print $_;
    }
    close PDF;
  }
  else {
    print "\n";
  }
  unlink "/tmp/pdfgen.$PAR{id}.pdf";
  unlink "/tmp/pdfgen.$PAR{id}.stop";
  unlink "/tmp/pdfgen.$PAR{id}.done";
  unlink "/tmp/pdfgen.$PAR{id}";

}
elsif ( $PAR{cmd} eq "gen" ) {    ### Get list of credentials
  print "Content-type: application/json\n\n";
  print "{ \"status\": \"pending\", \"id\": \"$PAR{id}\"}";
  $now = time();

  # print "Content-type: application/pdf\n";
  #&result(0, "Hello", Dumper $PAR{graphs});
  # print STDERR "$PAR{id}\n";

  # use lib "../bin/lib";

  require PDF::API2;

  # use PDF::Table;

  use POSIX qw (strftime);
  my $tz = strftime( "%z", localtime() );
  $tz =~ s/(\d{2})$/':$1'/;
  my ( $m_sec, $m_min, $m_hour, $m_day, $m_month, $m_year ) = ( localtime() )[ 0, 1, 2, 3, 4, 5 ];
  $m_year += 1900;
  my $m_timestamp = sprintf( "D:%4d%02d%02d%02d%02d%02d", $m_year, $m_month, $m_day, $m_hour, $m_min, $m_sec );
  $m_timestamp .= $tz;

  # Create a blank PDF file
  my $pdf = PDF::API2->new();
  $pdf->info(
    'Author'       => "XoruX",
    'CreationDate' => $m_timestamp,
    'ModDate'      => $m_timestamp,
    'Creator'      => "genpdf.pl",
    'Title'        => "$app_uc history report ",
    'Subject'      => "",
    'Keywords'     => "XoruX LPAR2RRD STOR2RRD"
  );
  $pdf->preferences( -outlines => 1 );

  # $pdf->pageLabel(0, { -style => 'decimal', });

  $logo = $pdf->image_png("$inputdir/html/css/images/logo-$app_lc.png");

  $font  = $pdf->corefont( 'Helvetica',      -encode => "utf8" );
  $fontb = $pdf->corefont( 'Helvetica-Bold', -encode => "utf8" );

  # Add an external TTF font to the PDF
  # $font = $pdf->ttfont('/usr/share/fonts/dejavu/DejaVuSans.ttf');

  my @grarr    = ();
  my @sections = ();
  if ( ref( $PAR{graphs} ) eq "ARRAY" ) {
    @grarr = @{ $PAR{graphs} };
  }
  else {
    push @grarr, $PAR{graphs};
  }
  my $grcnt = scalar @grarr;
  my $sunix = ( $grarr[0] =~ /sunix=([^&]*)/ )[0];
  my $eunix = ( $grarr[0] =~ /eunix=([^&]*)/ )[0];

  if ( $PAR{sections} ) {
    if ( ref( $PAR{sections} ) eq "ARRAY" ) {
      @sections = @{ $PAR{sections} };
    }
    else {
      push @sections, $PAR{sections};
    }
  }
  else {
    push @sections, "CPU:" . $grcnt;
  }

  my $gridx = 0;
  my $otls  = $pdf->outlines;

SECTIONS: foreach my $section (@sections) {
    my ( $name, $count ) = split( ":", $section );
    my $headtitle = "History of $name               " . epoch2human($sunix) . " - " . epoch2human($eunix);
    my $page      = add_new_page( $pdf, $headtitle );
    my $content   = $page->gfx();
    my $cntr      = $pagetop;
    my $otl       = $otls->outline;
    $otl->title($name);
    $otl->dest($page);

    for my $secgr ( 1 .. $count ) {
      if ( -e "/tmp/pdfgen.$PAR{id}.stop" ) {
        rename "/tmp/pdfgen.$PAR{id}.stop", "/tmp/pdfgen.$PAR{id}.stopped";
        $stopped = 1;
        last SECTIONS;
      }

      # Outline
      my $graph = $grarr[$gridx];
      $gridx++;
      if ( open( STATFILE, ">", "/tmp/pdfgen.$PAR{id}" ) ) {
        print STATFILE "$gridx:$grcnt";
        close STATFILE;
      }
      my ( $script, $qs ) = ( split "\\?", $graph, 2 );

      # print STDERR "$script\n";
      # print STDERR "$qs\n";
      # $qs =~ s/detail=[0-9]/detail=1/g;
      $ENV{QUERY_STRING}   = $qs;
      $ENV{REQUEST_METHOD} = "GET";
      $ENV{PICTURE_COLOR}  = "FFF";
      if ( $script =~ /detail-graph/ ) {
        $script = "detail-graph-cgi.pl";
      }
      elsif ( $script =~ /$app_lc-rep/ ) {
        $script = "$app_lc-rep.pl";
      }
      else {
        $script = "lpar-list-rep.pl";
      }
      my $png = `$perl $ENV{INPUTDIR}/bin/$script`;

      # print STDERR "$png\n";
      my ( $header, $justpng ) = ( split "\n\n", $png, 2 );

      # print STDERR "$header\n";
      if ($justpng) {
        $png = $justpng;
      }
      my ( $ft, $filename ) = tempfile( UNLINK => 1 );
      binmode $ft;
      print $ft $png;
      close $ft;
      my $dpng    = $pdf->image_png($filename);
      my $rwidth  = $dpng->width();
      my $rheight = $dpng->height();

      if ( !$rheight ) {
        next;
      }

      my $zoomfactor = ( 595 - 60 ) / $rwidth;

      # $zoomfactor = 0.500;
      my $height = $rheight * $zoomfactor;
      my $width  = $rwidth * $zoomfactor;

      if ( $height > $pagetop ) {
        $zoomfactor = ( $pagetop - 30 ) / $rheight;
        $height     = $rheight * $zoomfactor;
        $width      = $rwidth * $zoomfactor;

        # print STDERR "PDF generator: image was too big to fit in the page, shrinking...\n";
        # next;
      }

      # print STDERR "W: $rwidth   H: $rheight  Z: $zoomfactor\n";

      if ( ( $cntr - $height ) < 24 ) {
        $page    = add_new_page( $pdf, $headtitle );
        $content = $page->gfx();
        $cntr    = $pagetop;
      }

      # print STDERR "W: $width, H: $height\n";
      #my $dpng = $pdf->image_png("d.png");
      $content->image( $dpng, 30, $cntr - $height, $zoomfactor );

      # close $fh;
      $cntr -= $height;

      # last;
    }

    # unlink "$inputdir/tmp/pdfgen.$PAR{id}";
  }
  if ($stopped) {
    print "Content-type: application/json\n\n";
    print "{ \"status\": \"terminated\", \"id\": \"$PAR{id}\"}";
    sleep(2);    # wait for GUI
    unlink "/tmp/pdfgen.$PAR{id}.stop";

  }
  else {

    # Save the PDF
    $pdf->saveas("/tmp/pdfgen.$PAR{id}.pdf");
    if ( open( FILE, ">", "/tmp/pdfgen.$PAR{id}.done" ) ) {
      close FILE;
    }

    #print "Content-type: text/html\n";
    #print "Content-Disposition:attachment;filename=$PAR{title}-" . epoch2iso($now). ".pdf\n\n";
    #binmode STDOUT;
    #print $pdf->stringify();
  }
}

sub add_new_page {
  my $pdf   = shift();
  my $title = shift();

  my $page = $pdf->page();

  $page->mediabox($format);

  # $page->mediabox(A4_x, A4_y);
  # Your code to display the page template here.
  #
  # Note: You can use a different template for additional pages by
  # looking at e.g. $pdf->pages(), which returns the page count.
  #
  # If you need to include a "Page 1 of 2", you can pass the total
  # number of pages in as an argument:
  # int(scalar @items / $max_items_per_page) + 1

  my $count    = $pdf->pages();
  my $grey_box = $page->gfx(1);
  $grey_box->fillcolor('#555');
  $grey_box->strokecolor('#222');
  $grey_box->rect(
    80 * mm,    # left
    $pagey - ( 130 * mm ),    # bottom
    $pagex - ( 140 * mm ),    # width
    70 * mm                   # height
  );

  $grey_box->fill;

  my $logo_box = $page->gfx();
  $logo_box->image( $logo, 12, 12, 0.35 );

  my $prod_link = $page->annotation();
  my $prod_url  = "http://www.$app_lc.com";
  my %options   = (
    -border => [ 0,  0,  0 ],
    -rect   => [ 12, 12, 80, 30 ]
  );
  $prod_link->url( $prod_url, %options );

  # Add some text to the page
  my $text = $page->text();
  $text->font( $fontb, 15 );
  $text->fillcolor("white");
  $text->translate( 40, $pagey - 38 );
  $text->text($title);

  my $paragraph = "Generated from $app_uc version $ENV{version} by XoruX      " . epoch2human( $now, 1 ) . "                                                         Page $count";
  my $footer    = $page->text;
  $footer->textstart;
  $footer->lead(7);
  $footer->font( $font, 7 );
  $footer->fillcolor('navy');
  $footer->translate( 560, 14 );
  $footer->section( "$paragraph", 400, 16, -align => "right" );

  if ( $PAR{free} ) {
    my $link      = $page->annotation();
    my $url       = "http://www.$app_lc.com/support.htm#benefits";
    my $link_text = "You can only see one graph per section in the Free Edition of $app_uc, please consider the Enterprise Edition.";
    my $txt       = $page->text;
    $txt->font( $font, 9 );
    $txt->fillcolor('red');
    $txt->translate( 70, 34 );
    $txt->text($link_text);

    my %option = (
      -border => [ 0,  0,  0 ],
      -rect   => [ 70, 34, 70 + $font->width($link_text) * 9, 42 ]
    );
    $link->url( $url, %option );
  }

  return $page;
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

sub epoch2human {
  my ( $tm, $secs ) = @_;    # epoch, show seconds
  if ( !$tm ) {
    $tm = time();
  }
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($tm);
  my $y   = $year + 1900;
  my $m   = $mon + 1;
  my $mcs = 0;
  my $str = sprintf( "%4d/%02d/%02d %2d:%02d", $y, $m, $mday, $hour, $min );
  if ($secs) {
    $str = sprintf( "%4d/%02d/%02d %2d:%02d:%02d", $y, $m, $mday, $hour, $min, $sec );
  }
  return ($str);
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

sub testPDF {

  # no warnings "all";
  eval 'use PDF::API2; 1';

  my $pdf  = PDF::API2->new();
  my $font = $pdf->corefont('Helvetica');

  # Add a blank page
  my $page    = $pdf->page();
  my $content = $page->gfx();

  # Add some text to the page
  my $text = $page->text();
  $text->font( $font, 20 );
  $text->translate( 40, 780 );
  $text->text('Test PDF - generated with Perl PDF::API2');

  my $mpng = $pdf->image_png("m.png");
  $content->image( $mpng, 30, 500, 0.55 );

  # Save the PDF
  my $result = $pdf->stringify();

  # print $result;
}
