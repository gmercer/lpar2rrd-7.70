package PDF;

use strict;
use warnings;

use Data::Dumper;
use POSIX qw (strftime);

use Xorux_lib;

my $inputdir = $ENV{INPUTDIR} ||= Xorux_lib::error( "Not defined INPUTDIR! $!" . __FILE__ . ":" . __LINE__ ) && return 0;
my $perl     = $ENV{PERL}     ||= Xorux_lib::error( "Not defined PERL! $!" . __FILE__ . ":" . __LINE__ )     && return 0;
my $wrkdir   = "$inputdir/data";

#
# test if required modules are installed
#
my @required_modules = ( "PDF::API2", "PDF::Table" );
foreach my $module (@required_modules) {
  my $module_ok = 1;
  eval "use $module; 1" or $module_ok = 0;

  if ( !$module_ok ) {    # module not found
    Xorux_lib::error( "ERROR: Perl module has not been found: \'$module\' : " . __FILE__ . ":" . __LINE__ );
    Xorux_lib::error("       Check its existence via: $perl -e \'use $module\'") && return 0;
  }
}

######################
# NOTES (not done yet)
#
# 1.  PAGE settings:
#         PageSize - '4A', '2A', 'A0', 'A1', 'A2',
#                    'A3', 'A4', 'A5', 'A6', '4B',
#                    '2B', 'B0', 'B1', 'B2', 'B3',
#                    'B4', 'B5', 'B6', 'LETTER',
#                    'BROADSHEET', 'LEDGER', 'TABLOID',
#                    'LEGAL', 'EXECUTIVE', '36X36'
#         PageOrientation - 'Portrait', 'Landscape'
#
#
# XY. TABLE settings:
#
#     Mandatory global settings:
#
#         %settings = ( 'x' => 30, 'y' => 795, 'w' => 535, 'h' => 380 );
#         x - distance from the left edge of the page
#             X coordinate of upper left corner of the table.
#             0 <= X < PageWidth
#         y - distance from the bottom of the page
#             e.g.: y => 795 a PageHeight => 800 -> table starts from the 5. point from the top and from the 795 point from the bottom
#             Y coordinate of upper left corner of the table on the initial page.
#             0 < y < PageHeight
#         w - width of the table starting from x.
#             0 < w < PageWidth - x
#         h - Height of the table on the initial (current) page.
#             0 < h < PageHeight - Current Y position
#
#     Optional global settings:
#
#         next_h - Height of the table on any additional page.
#                  0 < next_h < PageHeight - y
#         next_y - Y coordinate of upper left corner of the table at any additional page.
#                  0 < next_y < PageHeight
#
######################
# How to create PDF
#
# It's necessary to prepare hash with the PDF content
#
# Here is an example:
#
#{
#  'PageOrientation' => 'Portrait',   # -> not used yet
#  'PageTemplate' => 'default',       # -> not used yet
#  'PageSize' => 'A4',
#  'info' => {
#    'Subject' => 'FUJITSU-ETERNUS overview Mon Feb  1 09:20:20 2021 - Mon Feb  8 09:20:20 2021',
#    'Creator' => '/home/stor2rrd/stor2rrd/bin/overview.pl',
#    'Keywords' => 'XoruX LPAR2RRD STOR2RRD XorMon',
#    'Title' => 'FUJITSU-ETERNUS overview',
#    'Author' => 'XoruX'
#  },
#  'content' => [
#    ######################### -> add text as a table (this is page/PDF header in a border with some background color)
#    {
#      'text_settings' => {
#       'padding_y' => 3
#     },
#     'table_settings' => {
#       'justify' => 'center',
#       'fg_color' => 'white',
#       'padding' => 10,
#       'font_size' => 16,
#       'bg_color' => '#0B2F3A',
#       'font' => 'Helvetica',
#       'border_w' => 0
#     },
#     'data' => [
#       [
#         'FUJITSU-ETERNUS overview'
#       ]
#     ],
#     'type' => 'TABLE-TEXTONLY'
#   },
#    ######################### -> add text as a table
#   {
#     'text_settings' => {
#       'padding_y' => 3
#     },
#     'table_settings' => {
#       'justify' => 'center',
#       'fg_color' => 'black',
#       'padding' => 0,
#       'font_size' => 14,
#       'font' => 'Helvetica',
#       'border_w' => 0
#     },
#     'data' => [
#       [
#         'Device configuration'
#       ]
#     ],
#     'type' => 'TABLE-TEXTONLY'
#   },
#    ######################### -> add a table
#   {
#     'table_settings' => {
#       'font_size' => 10,
#       'header_props' => {
#         'bg_color' => '#f6f8f9',
#         'font' => 'Helvetica-Bold'
#       },
#       'font' => 'Helvetica',
#       'fg_color' => 'black',
#       'padding_right' => 5,
#       'cell_props' => [
#         [],
#         [
#           {},
#           {},
#           {},
#           {},
#           {},
#           {}
#         ]
#       ],
#       'border_c' => '#ccc',
#       'padding_left' => 5
#     },
#     'data' => [
#       [
#         'Alias Name',
#         'Node Name',
#         'IP',
#         'Model',
#         'Serial',
#         'Version'
#       ],
#       [
#         'FUJITSU-ETERNUS',
#         '',
#         '',
#         'ET251CU',
#         '4601629360',
#         'V10L70-5000'
#       ]
#     ],
#     'type' => 'TABLE'
#   },
#    ######################### -> add a graph
#   {
#     'file' => '/tmp/FUJITSU-ETERNUS-POOL-io_rate.png',
#     'type' => 'IMG',
#     'img_settings' => {
#       'metric_type' => 'IO',
#       'metric' => 'io_rate',
#       'subsys' => 'POOL',
#       'device' => 'FUJITSU-ETERNUS'
#     }
#   }
# ]
#};

use constant mm   => 25.4 / 72;    # 25.4 mm in an inch, 72 points in an inch
use constant in   => 1 / 72;       # 72 points in an inch
use constant pt   => 1;            # 1 point
use constant A4_x => 210 / mm;     # x points in an A4 page ( 595.2755 )
use constant A4_y => 297 / mm;     # y points in an A4 page ( 841.8897 )

use constant US_x => 216 / mm;     # x points in an US letter page ( 612.2834 )
use constant US_y => 279 / mm;     # y points in an US letter page ( 790.8661 )

my $pdf;
my $page;
my $pdf_table;
my $app_lc = $ENV{APPNAME} ||= "lpar2rrd";
my $app_uc = uc $app_lc;

# default page layout
my $PageSize        = "A4";
my $PageWidth       = A4_x;
my $PageHeight      = A4_y;
my $PageOrientation = "Portrait";
my $PageTemplate    = "default";

# default page padding
my $PagePadding_x = 30;    # x-axis (from the left and from the right)
my $PagePadding_y = 30;    # y-axis (from the top and from the bottom)

sub createPDF {
  my $pdf_file = shift;
  my $pdf_data = shift;

  # set different page layout
  if ( exists $pdf_data->{PageSize} ) { $PageSize = $pdf_data->{PageSize}; }

  #if ( exists $pdf_data->{PageOrientation} ) { $PageOrientation = $pdf_data->{PageOrientation}; } # not supported yet
  #if ( exists $pdf_data->{PageTemplate} )    { $PageTemplate    = $pdf_data->{PageTemplate}; }    # not supported yet

  # create a blank PDF file
  $pdf = PDF::API2->new();

  # add info
  $pdf = add_info( $pdf, $pdf_data->{info} );

  # create a new page
  $page = add_new_page();

  # usable vertical distance from the bottom of the page
  my $y = $PageHeight - $PagePadding_y;

  #warn Dumper $pdf_data;

  # add content to the page (TABLE, IMG)
  if ( exists $pdf_data->{content} && ref( $pdf_data->{content} ) eq "ARRAY" ) {
    foreach my $content ( @{ $pdf_data->{content} } ) {

      #warn Dumper $content;

      if ( exists $content->{type} ) {

        # add TABLE
        if ( $content->{type} eq "TABLE" ) {
          ( $pdf, $page, $y ) = add_table( $pdf, $page, $y, $content );
        }

        # add TABLE TEXT ONLY
        if ( $content->{type} eq "TABLE-TEXTONLY" ) {
          ( $pdf, $page, $y ) = add_table_text_only( $pdf, $page, $y, $content );
        }

        # add IMG
        if ( $content->{type} eq "IMG" ) {
          ( $pdf, $page, $y ) = add_img( $pdf, $page, $y, $content );
        }
      }
    }
  }

  # save the PDF
  $pdf->saveas("$pdf_file");

  return 1;
}

sub add_info {
  my $pdf       = shift;
  my $info_data = shift;    # use configured info

  # add CreationDate and ModDate
  my $tz = strftime( "%z", localtime() );
  $tz =~ s/(\d{2})$/':$1'/;
  my ( $m_sec, $m_min, $m_hour, $m_day, $m_month, $m_year ) = ( localtime() )[ 0, 1, 2, 3, 4, 5 ];
  $m_month += 1;
  $m_year  += 1900;
  my $m_timestamp = sprintf( "D:%4d%02d%02d%02d%02d%02d", $m_year, $m_month, $m_day, $m_hour, $m_min, $m_sec );
  $m_timestamp .= $tz;

  my %info;
  $info{CreationDate} = $m_timestamp;
  $info{ModDate}      = $m_timestamp;

  if ( defined $info_data && ref($info_data) eq "HASH" ) {
    while ( my ( $key, $val ) = each( %{$info_data} ) ) {
      if ( defined $key && defined $val ) {
        $info{$key} = $val;
      }
    }
  }

  $pdf->info(%info);

  return $pdf;
}

sub add_img {
  my $pdf     = shift;
  my $page    = shift;
  my $y       = shift;
  my $content = shift;

  unless ( exists $content->{file} && -f $content->{file} ) { return ( $pdf, $page, $y ); }

  my $page_content = $page->gfx();
  my $dpng         = $pdf->image_png( $content->{file} );
  my $rwidth       = $dpng->width();
  my $rheight      = $dpng->height();

  my $zoomfactor = ( $PageWidth - ( 2 * $PagePadding_x ) ) / $rwidth;

  my $height_png = $rheight * $zoomfactor;
  my $width_png  = $rwidth * $zoomfactor;

  #if ( $height_png > ( $y - $PagePadding_y ) ) {
  #  $zoomfactor = ( $y - $PagePadding_y ) / $rheight;
  #  $height_png = $rheight * $zoomfactor;
  #  $width_png  = $rwidth * $zoomfactor;
  #}

  if ( $height_png > ( $y - $PagePadding_y ) ) {
    $page         = add_new_page();
    $y            = $PageHeight - $PagePadding_y;    # usable vertical distance from the bottom of the page
    $page_content = $page->gfx();
  }

  $page_content->image( $dpng, $PagePadding_y, $y - $height_png, $zoomfactor );

  $y -= $height_png;
  $y -= $PagePadding_y;

  return ( $pdf, $page, $y );
}

sub add_table {
  my $pdf     = shift;
  my $page    = shift;
  my $y       = shift;
  my $content = shift;

  if ( exists $content->{data} && ref( $content->{data} ) eq "ARRAY" ) {
    $pdf_table = PDF::Table->new();

    my $x      = $PagePadding_x;
    my $w      = $PageWidth - ( 2 * $PagePadding_x );
    my $h      = $PageHeight - ( $PageHeight - $y ) - $PagePadding_y;
    my $next_h = $PageHeight - ( 2 * $PagePadding_y );
    my $next_y = $PageHeight - $PagePadding_y;

    # mandatory and some basic table settings
    my $settings = {
      'x'             => $x,
      'y'             => $y,
      'w'             => $w,
      'h'             => $h,
      'next_y'        => $next_y,
      'next_h'        => $next_h,
      'new_page_func' => \&add_new_page,
    };

    # additional table settings
    if ( exists $content->{table_settings} ) {
      while ( my ( $key, $val ) = each( %{ $content->{table_settings} } ) ) {
        if ( defined $key && defined $val ) {
          $settings->{$key} = $val;
        }
      }
    }
    ( $pdf, $settings ) = check_fonts( $pdf, $settings );

    my ( $p_last, undef, $y_bot ) = $pdf_table->table( $pdf, $page, $content->{data}, %{$settings} );

    $page = $p_last;    # use page with its content

    $y = $y_bot - $PagePadding_y;    # vertical distance between tables
    if ( $y < $PagePadding_y ) {     # page wrap
                                     #($page, $PageWidth, $PageHeight) = add_new_page($pdf);
      $page = add_new_page();
      $y    = $PageHeight - $PagePadding_y;    # usable vertical distance from the bottom of the page
    }
  }

  return ( $pdf, $page, $y );
}

sub add_table_text_only {
  my $pdf     = shift;
  my $page    = shift;
  my $y       = shift;
  my $content = shift;

  if ( exists $content->{data} && ref( $content->{data} ) eq "ARRAY" ) {
    $pdf_table = PDF::Table->new();

    my $x      = $PagePadding_x;
    my $w      = $PageWidth - ( 2 * $PagePadding_x );
    my $h      = $PageHeight - ( $PageHeight - $y ) - $PagePadding_y;
    my $next_h = $PageHeight - ( 2 * $PagePadding_y );
    my $next_y = $PageHeight - $PagePadding_y;

    # mandatory and some basic table settings
    my $settings = {
      'x'             => $x,
      'y'             => $y,
      'w'             => $w,
      'h'             => $h,
      'next_y'        => $next_y,
      'next_h'        => $next_h,
      'new_page_func' => \&add_new_page,
    };

    # additional table settings
    if ( exists $content->{table_settings} ) {
      while ( my ( $key, $val ) = each( %{ $content->{table_settings} } ) ) {
        if ( defined $key && defined $val ) {
          $settings->{$key} = $val;
        }
      }
    }
    ( $pdf, $settings ) = check_fonts( $pdf, $settings );

    my ( $p_last, undef, $y_bot ) = $pdf_table->table( $pdf, $page, $content->{data}, %{$settings} );

    $page = $p_last;    # use page with its content

    if ( exists $content->{text_settings}->{padding_y} && Xorux_lib::isdigit( $content->{text_settings}->{padding_y} ) ) {
      $y = $y_bot - $content->{text_settings}->{padding_y};    # vertical distance between tables
      if ( $y < $PagePadding_y ) {                             # page wrap
        $page = add_new_page();
        $y    = $PageHeight - $content->{text_settings}->{padding_y};    # usable vertical distance from the bottom of the page
      }
    }
    else {
      $y = $y_bot - $PagePadding_y;                                      # vertical distance between tables
      if ( $y < $PagePadding_y ) {                                       # page wrap
        $page = add_new_page();
        $y    = $PageHeight - $PagePadding_y;                            # usable vertical distance from the bottom of the page
      }
    }
  }

  return ( $pdf, $page, $y );
}

sub check_fonts {
  my $pdf      = shift;
  my $settings = shift;

  # search all possible places, where param font can be used

  if ( exists $settings->{font} ) {
    $settings->{font} = $pdf->corefont( "$settings->{font}", -encode => "utf8" );
  }
  if ( exists $settings->{header_props} ) {
    if ( exists $settings->{header_props}->{font} ) {
      $settings->{header_props}->{font} = $pdf->corefont( "$settings->{header_props}->{font}", -encode => "utf8" );
    }
  }
  if ( exists $settings->{cell_props} ) {
    foreach my $row ( @{ $settings->{cell_props} } ) {
      foreach ( @{$row} ) {
        if ( exists $_->{font} ) {
          $_->{font} = $pdf->corefont( "$_->{font}", -encode => "utf8" );
        }
      }
    }
  }
  if ( exists $settings->{row_props} ) {
    foreach ( @{ $settings->{row_props} } ) {
      if ( exists $_->{font} ) {
        $_->{font} = $pdf->corefont( "$_->{font}", -encode => "utf8" );
      }
    }
  }

  return ( $pdf, $settings );
}

sub add_new_page {

  my $page = $pdf->page();

  # pageSize: '4A0', '2A0', 'A0', 'A1', 'A2', 'A3', 'A4', 'A5', 'A6', '4B0', '2B0', 'B0', 'B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'LETTER', 'BROADSHEET', 'LEDGER', 'TABLOID', 'LEGAL', 'EXECUTIVE', and '36X36'.
  $page->mediabox($PageSize);

  # PageOrientation -> NOT SUPPORTED YET
  ## pageOrientation Portrait/Landscape
  #if ( $PageOrientation eq "Landscape" ) {
  #  $page->rotate(90);
  #}

  # PageTemplate
  if ( $PageTemplate eq "default" ) {
    my $font = $pdf->corefont( 'Helvetica', -encode => "utf8" );

    # add logo to this page
    if ( -e "$inputdir/html/css/images/logo-$app_lc.png" ) {
      my $logo     = $pdf->image_png("$inputdir/html/css/images/logo-$app_lc.png");
      my $logo_box = $page->gfx();
      $logo_box->image( $logo, 12, 12, 0.35 );

      my $prod_link = $page->annotation();
      my $prod_url  = "http://www.$app_lc.com";
      my %options   = (
        -border => [ 0,  0,  0 ],
        -rect   => [ 12, 12, 80, 30 ]
      );
      $prod_link->url( $prod_url, %options );
    }

    # add page number at the bottom of this page
    my $page_number = $pdf->pages();
    my $footer      = $page->text;
    $footer->textstart;
    $footer->lead(7);
    $footer->font( $font, 7 );
    $footer->fillcolor('navy');
    $footer->translate( 560, 14 );
    $footer->section( $page_number, 400, 16, -align => "right" );
  }

  return $page;
}

1;
