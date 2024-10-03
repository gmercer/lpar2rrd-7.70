use strict;
use warnings;
use Env qw(QUERY_STRING);
use Data::Dumper;
use Xorux_lib;

print "Content-type: text/html\n\n";

my $inputdir = $ENV{INPUTDIR};
my $webdir   = $ENV{WEBDIR};
my %params;
my %inventory_data;
my %header;
my $height       = 150;
my $width        = 600;
my $xormon       = $ENV{HTTP_XORUX_APP};
my $time_heatmap = localtime();

if ( !defined $xormon ) {
  $xormon = 0;
}
else {
  $xormon = 1;
}

my $style_html = "td.clr0 {background-color:#737a75;} td.clr1 {background-color:#008000;} td.clr2 {background-color:#29f929;} td.clr3 {background-color:#81fa51;} td.clr4 {background-color:#c9f433;} td.clr5 {background-color:#FFFF66;} td.clr6 {background-color:#ffff00;} td.clr7 {background-color:#FFCC00;} td.clr8 {background-color:#ffa500;} td.clr9 {background-color:#fa610e;} td.clr10 {background-color:#ff0000;}  table.center {margin-left:auto; margin-right:auto;} table {border-spacing: 1px;} .content_legend { height:" . "15" . "px" . "; width:" . "15" . "px" . ";}";

my $LPAR_HEATMAP_UTIL_TIME = $ENV{LPAR_HEATMAP_UTIL_TIME};
if ( !defined $LPAR_HEATMAP_UTIL_TIME ) {
  $LPAR_HEATMAP_UTIL_TIME = 1;
}
my $HEATMAP_MEM_PAGING_MAX;
if ( defined $ENV{HEATMAP_MEM_PAGING_MAX} ) {
  $HEATMAP_MEM_PAGING_MAX = $ENV{HEATMAP_MEM_PAGING_MAX};
}
else {
  $HEATMAP_MEM_PAGING_MAX = 50;
}

my $buffer;
if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
  read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
}
else {
  $buffer = $ENV{'QUERY_STRING'};
}

%params = %{ Xorux_lib::parse_url_params($buffer) };

my $platform = $params{platform};
my $type     = $params{type};
my $tabs     = $params{tabs};
my @types    = ();

if ( !defined $inputdir || $inputdir eq "" ) { error_die("Inputdir is not defined"); }
if ( !defined $platform || $platform eq "" ) { error_die("Platform is not defined"); }
if ( !defined $webdir   || $webdir eq "" )   { error_die("Webdir is not defined"); }
$platform = lc($platform);
if ( $platform eq "xenserver" ) {
  $platform = "xen";
}
if ( $platform eq "hyperv" ) {
  $platform = "windows";
}

### lpar2rrrd
#if ($xormon == 0){
#  my $file = "$webdir/heatmap-$platform.html";
#  if (-f $file){
#    my @data = get_array_data($file);
#    print @data;
#    exit;
#  }
#  else{
#    print "File $file is not exist";
#    exit;
#  }
#}

if ( Xorux_lib::isdigit($tabs) && $tabs == 1 ) {
  gen_tabs($platform);
  exit;
}
else {

  parse_heatmap( $platform, $type );

  #print STDERR Dumper \%inventory_data;
  acl( $platform, $type );

  if ( $type eq "vm" || $type eq "server" || $type eq "lpar" || $type eq "pool" ) {
    gen_html_table_circle( $platform, $type );
  }
  else {
    gen_html_table( $platform, $type );
  }

}

#print STDERR Dumper \%inventory_data;

sub gen_html_table {
  my $platform = shift;
  my $type     = shift;

  my $table = get_table( $platform, $type );
  print "$table";

}

sub get_table {
  my $platform = shift;
  my $type     = shift;
  my ( undef, $item, undef ) = split( "-", $type );

  my $table_header = get_table_header($item);
  my $table_body   = get_table_body( $platform, $type, $item );

  my $style        = get_style( $platform, $type, $item );
  my $sort_item    = get_sort_item($item);
  my $table        = "<table class =\"lparsearch tablesorter\" data-sortby=\"$sort_item\">$table_header $table_body</table>\n";
  my $style_global = "<style>" . "$style" . "$style_html" . "</style>";
  my $html         = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body><center>$table</center></body></html>";
  return $html;

}

sub get_sort_item {
  my $item  = shift;
  my $index = 0;

  if ( !defined $header{$item} || ref( $header{$item} ne "ARRAY" ) ) {
    return "";
  }
  foreach my $htb ( @{ $header{$item} } ) {
    $index++;
    if ( $htb eq "Utilization %" ) {
      return $index;
    }
  }
  return $index;
}

sub get_style {
  my $platform = shift;
  my $type     = shift;
  my $item     = shift;
  use POSIX qw(ceil);

  my $count = get_count_element( $platform, $type, $item );
  if ( $count == 0 ) {
    return "";
  }

  my $cell_size    = ( $height * $width ) / $count;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;
  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }
  $td_height = $td_height - 2;
  my $class = "content_" . "$platform" . "_" . "$type";
  my $style = " .$class { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  return $style;
}

sub get_table_body {

  my $platform = shift;
  my $type     = shift;
  my $item     = shift;
  my $tbody    = "<tbody>";

  if ( $type =~ m/^server/ ) {
    $type = "server";
  }
  if ( $type =~ m/^vm/ ) {
    $type = "vm";
  }
  if ( $type =~ m/^lpar/ ) {
    $type = "lpar";
  }
  if ( $type =~ m/^pool/ ) {
    $type = "pool";
  }

  if ( !defined $header{$item} || ref( $header{$item} ne "ARRAY" ) ) {
    return "";
  }
  foreach my $id ( sort { $a <=> $b } keys %{ $inventory_data{$platform}{$type} } ) {
    my $item_type = $inventory_data{$platform}{$type}{$id}{TYPE};
    if ( !defined $item_type || $item_type ne $item ) { next; }
    my $row = "<tr>";
    foreach my $htb ( @{ $header{$item} } ) {
      if ( defined $inventory_data{$platform}{$type}{$id}{$htb} ) {
        $row = $row . "<td>$inventory_data{$platform}{$type}{$id}{$htb}</td>\n";
      }
    }
    $tbody = $tbody . "$row";
  }
  $tbody = $tbody . "</tbody>";
  return $tbody;
}

sub get_table_header {
  my $item   = shift;
  my $htable = "<thead><tr>";

  if ( !defined $header{$item} || ref( $header{$item} ne "ARRAY" ) ) {
    return "";
  }

  foreach my $htb ( @{ $header{$item} } ) {
    if ( $htb eq "Color" ) {
      $htable = $htable . "<th title=\"Color\" nowrap=\"\"><center>Color</center></th></tr>\n";
      last;
    }
    $htable = $htable . "<th class = \"sortable\" title=\"$htb\" nowrap=\"\">$htb</th>\n";
  }
  $htable = $htable . "</tr></thead>\n";

  return $htable;

}

sub gen_html_table_circle {
  my $platform = shift;
  my $type     = shift;

  my $memory = "Memory";

  my ( $table_cpu, $style_cpu ) = get_table_circle( $platform, $type, "cpu" );
  my ( $table_mem, undef ) = get_table_circle( $platform, $type, "mem" );

  my $style = "<style>" . "$style_cpu" . "$style_html" . "</style>";
  if ( $table_mem eq "" ) {
    $memory = "";
  }
  my $html;
  if ( $platform eq "vmware" ) {
    $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody><tr><td><h3>CPU</h3></td></tr>\n<tr>\n<td>" . $table_cpu . "</td></tr>\n<tr>\n<td>&nbsp;</td>\n</tr><tr><td><h3>$memory</h3></td></tr>\n<tr><td>" . $table_mem . "</td></tr><tr><td>" . get_report() . "\n</td></tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend("cpu_ready") . "</td></tr>\n</tbody>\n</table>\n</body></html>";
  }
  elsif ( $platform eq "power" ) {
    $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody>\n<tr><td><h3>CPU</h3></td></tr><tr>\n<td>" . "$table_cpu" . "</td></tr>\n<tr><td><h3>$memory</h3></td></tr><tr>\n<td>" . "$table_mem" . "</td></tr><tr><td>" . get_report() . "</td>\n</tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend($memory) . "</td></tr>\n</tbody>\n</table>\n</body></html>";
  }
  else {
    $html = "<!DOCTYPE html>\n<html>\n<head>" . $style . "</head><body>\n<table class=" . '"' . "center" . '"' . ">\n<tbody>\n<tr><td><h3>CPU</h3></td></tr><tr>\n<td>" . "$table_cpu" . "</td></tr>\n<tr><td><h3>$memory</h3></td></tr><tr>\n<td>" . "$table_mem" . "</td></tr><tr><td>" . get_report() . "</td>\n</tr><tr><td>&nbsp;</td></tr><tr><td><b>LEGEND</b>:<tr><td>" . get_legend() . "</td></tr>\n</tbody>\n</table>\n</body></html>";
  }
  print $html;
}

sub get_report {
  my $time  = localtime;
  my $table = "<table>\n<tbody>\n<tr>\n<td>Heat map has been created at: " . "$time_heatmap" . "</td>\n</tr>\n<tr>\n<td>Heat map shows average utilization from last $LPAR_HEATMAP_UTIL_TIME hour.</td>\n</tr>\n</tbody>\n</table>";
  return $table;

}

sub get_legend {
  my $memory = shift;
  my $table  = "<table>\n<tbody><tr>";
  my $i      = 0;
  my $from   = 0;
  my $to     = 10;
  my $title  = "";
  my $paging = "";
  while ( $i < 11 ) {
    if ( $i == 0 ) {
      $title = "nan";
    }
    if ( defined $memory && $memory eq "Memory" && $i == 10 ) {
      $title = $title . " and paging in > $HEATMAP_MEM_PAGING_MAX kB/s or paging out > $HEATMAP_MEM_PAGING_MAX kB/s";
    }
    if ( defined $memory && $memory eq "cpu_ready" && $i == 10 ) {
      $title = $title . " or CPU ready > 5%";
    }
    $table = $table . "\n<td title=" . '"' . "$title" . '"' . "class=" . '"' . "clr$i" . '"' . "><div class =" . '"' . "content_legend" . '"' . "></div></td>";
    $i++;
    $title = "$from-$to " . "%";
    $from  = $to + 1;
    $to    = $to + 10;
  }
  $table = $table . "</tr>\n</tbody>\n</table>";
  return $table;
}

sub get_count_element {

  my $platform = shift;
  my $type     = shift;
  my $item     = shift;

  my $count = 0;
  foreach my $id ( keys %{ $inventory_data{$platform}{$type} } ) {
    my $item_type = $inventory_data{$platform}{$type}{$id}{TYPE};
    if ( !defined $item_type || $item_type ne $item ) { next; }
    $count++;
  }
  return $count;

}

sub get_table_circle {

  my $platform = shift;
  my $type     = shift;
  my $item     = shift;
  use POSIX qw(ceil);

  #print STDERR Dumper \%inventory_data;

  my $table = "";

  ### 1. count element (size heatmap)
  my $count = get_count_element( $platform, $type, $item );
  if ( $count == 0 ) {
    return ( $table, "" );
  }

  my $cell_size    = ( $height * $width ) / $count;
  my $td_width     = ceil( sqrt($cell_size) );
  my $td_height    = $td_width;
  my $new_row      = 0;
  my $count_column = 1;
  if ( $td_width < 10 ) {
    $td_width  = 10;
    $td_height = 10;
  }
  if ( $td_width > 42 ) {
    $td_width  = 42;
    $td_height = 42;
  }
  $td_height = $td_height - 2;

  my $class = "content_" . "$platform" . "_" . "$type";
  my $style = " .$class { height:" . "$td_height" . "px" . "; width:" . "$td_height" . "px" . ";} h3 {text-align:center;}";
  #
  #print Dumper \%header;
  $table = "<table>\n<tbody>\n<tr>\n";
  foreach my $id ( sort { $a <=> $b } keys %{ $inventory_data{$platform}{$type} } ) {
    my $item_type = $inventory_data{$platform}{$type}{$id}{TYPE};
    if ( !defined $item_type || $item_type ne $item ) { next; }
    if ( ( $new_row + $td_width ) > $width ) {
      $table   = $table . "</tr>\n<tr>\n";
      $new_row = 0;
    }
    if ( $platform eq "vmware" ) {

      #print STDERR Dumper %inventory_data;
      my $server       = $inventory_data{$platform}{$type}{$id}{Server};
      my $url          = $inventory_data{$platform}{$type}{$id}{VM};
      my $name         = $inventory_data{$platform}{$type}{$id}{NAME};
      my $percent_util = $inventory_data{$platform}{$type}{$id}{"Utilization %"};
      if ( Xorux_lib::isdigit($percent_util) ) {
        $percent_util = $percent_util . "%";
      }
      my $cpu_ready = $inventory_data{$platform}{$type}{$id}{"CPU ready"};
      my $color     = $inventory_data{$platform}{$type}{$id}{"COLOR"};

      if ( defined $url ) {

        #my $original_name = $name;
        #$original_name =~ s/\[/\\[/g;
        #$original_name =~ s/\]/\\]/g;
        #$original_name =~ s/\(/\\(/g;
        #$original_name =~ s/\)/\\)/g;
        #$url=~ s/$original_name<\/a>//g;
        $url =~ s/>.+/>/;
        if ( $item eq "cpu" ) {
          $table = $table . "<td style=\"background-color:$color\">\n$url<div title =" . '"' . "$server : $name" . " : " . $percent_util . " : CPU ready $cpu_ready" . '"' . " class=" . '"' . $class . '"' . "></div>\n</a>\n</td>\n";
        }
        else {
          $table = $table . "<td style=\"background-color:$color\">\n$url<div title =" . '"' . "$server : $name" . " : " . $percent_util . '"' . " class=" . '"' . $class . '"' . "></div>\n</a>\n</td>\n";
        }
      }
      else {
        $url = $inventory_data{$platform}{$type}{$id}{Pool};
        $url =~ s/$name<\/a>//g;
        $table = $table . "<td style=\"background-color:$color\">\n$url<div title =" . '"' . "$server : $name" . " : " . $percent_util . '"' . " class=" . '"' . $class . '"' . "></div>\n</a>\n</td>\n";

      }
    }
    elsif ( $platform eq "power" ) {
      my $server       = $inventory_data{$platform}{$type}{$id}{Server};
      my $url          = $inventory_data{$platform}{$type}{$id}{Lpar};
      my $name         = $inventory_data{$platform}{$type}{$id}{NAME};
      my $percent_util = $inventory_data{$platform}{$type}{$id}{"Utilization %"};
      my $paging_in    = $inventory_data{$platform}{$type}{$id}{'Paging IN kb/s'};
      my $paging_out   = $inventory_data{$platform}{$type}{$id}{'Paging OUT kb/s'};
      my $paging_title = "";
      if ( !defined $paging_in ) {
        $paging_in = "";
      }
      if ( !defined $paging_out ) {
        $paging_out = "";
      }
      if ( $item eq "mem" && $paging_in ne "" && $paging_out ne "" ) {
        $paging_title = " : paging in $paging_in" . "kb/s " . " : paging out $paging_out" . "kb/s";
      }
      if ( Xorux_lib::isdigit($percent_util) ) {
        $percent_util = $percent_util . "%";
      }
      my $color = $inventory_data{$platform}{$type}{$id}{"COLOR"};

      if ( defined $url ) {
        my $original_name = $name;
        $original_name =~ s/\[/\\[/g;
        $original_name =~ s/\]/\\]/g;
        $url           =~ s/$original_name<\/a>//g;
        $table = $table . "<td style=\"background-color:$color\">\n$url<div title =" . '"' . "$server : $name" . " : " . $percent_util . $paging_title . '"' . " class=" . '"' . $class . '"' . "></div>\n</a>\n</td>\n";
      }
      else {
        $url = $inventory_data{$platform}{$type}{$id}{Pool};
        my $name_regex = $name;
        $name_regex =~ s/\+/\\+/g;
        $url        =~ s/$name_regex<\/a>//g;
        $table = $table . "<td style=\"background-color:$color\">\n$url<div title =" . '"' . "$server : $name" . " : " . $percent_util . $paging_title . '"' . " class=" . '"' . $class . '"' . "></div>\n</a>\n</td>\n";

      }
    }
    elsif ( $platform eq "ovirt" ) {
      my $server       = $inventory_data{$platform}{$type}{$id}{Datacenter};
      my $cluster      = $inventory_data{$platform}{$type}{$id}{Cluster};
      my $url          = $inventory_data{$platform}{$type}{$id}{VM};
      my $name         = $inventory_data{$platform}{$type}{$id}{NAME};
      my $percent_util = $inventory_data{$platform}{$type}{$id}{"Utilization %"};
      if ( Xorux_lib::isdigit($percent_util) ) {
        $percent_util = $percent_util . "%";
      }
      my $color = $inventory_data{$platform}{$type}{$id}{"COLOR"};

      if ( defined $url ) {
        my $original_name = $name;
        $original_name =~ s/\[/\\[/g;
        $original_name =~ s/\]/\\]/g;
        $url           =~ s/$original_name<\/a>//g;
        $table = $table . "<td style=\"background-color:$color\">\n$url<div title =" . '"' . "$server : $cluster : $name" . " : " . $percent_util . '"' . " class=" . '"' . $class . '"' . "></div>\n</a>\n</td>\n";
      }
      else {
        $url = $inventory_data{$platform}{$type}{$id}{Server};
        my $original_name = $name;
        $original_name =~ s/\[/\\[/g;
        $original_name =~ s/\]/\\]/g;
        $url           =~ s/$original_name<\/a>//g;
        $table = $table . "<td style=\"background-color:$color\">\n$url<div title =" . '"' . "$server : $cluster : $name" . " : " . $percent_util . '"' . " class=" . '"' . $class . '"' . "></div>\n</a>\n</td>\n";

      }
    }
    else {
      my $server = $inventory_data{$platform}{$type}{$id}{Pool};
      if ( $platform eq "oraclevm" ) {
        $server = $inventory_data{$platform}{$type}{$id}{Cluster};
      }
      if ( $platform eq "windows" ) {
        $server = $inventory_data{$platform}{$type}{$id}{Server};
      }
      my $url          = $inventory_data{$platform}{$type}{$id}{VM};
      my $name         = $inventory_data{$platform}{$type}{$id}{NAME};
      my $percent_util = $inventory_data{$platform}{$type}{$id}{"Utilization %"};
      if ( Xorux_lib::isdigit($percent_util) ) {
        $percent_util = $percent_util . "%";
      }
      my $color = $inventory_data{$platform}{$type}{$id}{"COLOR"};

      if ( defined $url ) {
        my $original_name = $name;
        $original_name =~ s/\[/\\[/g;
        $original_name =~ s/\]/\\]/g;
        $url           =~ s/$original_name<\/a>//g;
        $table = $table . "<td style=\"background-color:$color\">\n$url<div title =" . '"' . "$server : $name" . " : " . $percent_util . '"' . " class=" . '"' . $class . '"' . "></div>\n</a>\n</td>\n";
      }
      else {
        if ( $platform eq "windows" ) {
          $url = $inventory_data{$platform}{$type}{$id}{Pool};
        }
        else {
          $url = $inventory_data{$platform}{$type}{$id}{Server};
        }
        my $original_name = $name;
        $original_name =~ s/\[/\\[/g;
        $original_name =~ s/\]/\\]/g;
        $url           =~ s/$original_name<\/a>//g;
        $table = $table . "<td style=\"background-color:$color\">\n$url<div title =" . '"' . "$server : $name" . " : " . $percent_util . '"' . " class=" . '"' . $class . '"' . "></div>\n</a>\n</td>\n";

      }
    }
    $new_row = $td_width + $new_row;

    #$table = $table . "<td class=\"$class\">\n<a href=" . '"' . "$url" . '"' . "><div title =" . '"' . "$server : $name" . " : " . $percent_util . " : CPU ready $cpu_ready" . '"' . "class=" . '"' . "content_vm" . '"' . "></div>\n</a>\n</td>\n";
  }
  $table = $table . "</tr>\n</tbody>\n</table><br>\n";
  return ( $table, $style );
}

sub acl {
  my $platform = shift;
  my $type     = shift;

  if ($xormon) {

    require ACLx;

    #require PowerDataWrapper;
    #require SolarisDataWrapper;

    my $acl = ACLx->new();

    if ( $type =~ m/^server/ ) {
      $type = "server";
    }
    if ( $type =~ m/^vm/ ) {
      $type = "vm";
    }
    if ( $type =~ m/^lpar/ ) {
      $type = "lpar";
    }
    if ( $type =~ m/^pool/ ) {
      $type = "pool";
    }

    foreach my $id ( keys %{ $inventory_data{$platform}{$type} } ) {
      my $aclitem = $inventory_data{$platform}{$type}{$id}{ACL};
      if ( !defined $aclitem ) { next; }
      if ( !$acl->isGranted($aclitem) ) {

        #print STDERR "$platform $id neni v db\n";
        delete $inventory_data{$platform}{$type}{$id};
        next;
      }
    }
  }
  else {
    use ACL;    # use module ACL.pm
    my $acl    = ACL->new;
    my $useacl = $acl->useACL();
    if ( $type =~ m/^server/ ) {
      $type = "server";
    }
    if ( $type =~ m/^vm/ ) {
      $type = "vm";
    }
    if ( $type =~ m/^lpar/ ) {
      $type = "lpar";
    }
    if ( $type =~ m/^pool/ ) {
      $type = "pool";
    }

    #if( $platform eq "vmware" && $type eq "server"){return 1;}

    #print STDERR Dumper \$inventory_data{$platform}{$type};
    foreach my $id ( keys %{ $inventory_data{$platform}{$type} } ) {
      my $acl_platform = $inventory_data{$platform}{$type}{$id}{ACL}{hw_type};
      my $acl_source   = $inventory_data{$platform}{$type}{$id}{Server};
      my $acl_item     = $inventory_data{$platform}{$type}{$id}{NAME};
      if ( defined $inventory_data{$platform}{$type}{$id}{URL_NAME} ) {
        $acl_item = $inventory_data{$platform}{$type}{$id}{URL_NAME};
      }

      my $acl_subsys;
      if ( defined $acl_platform && defined $acl_source && defined $acl_item ) {
        if ( $acl_platform eq "VMWARE" ) {
          $acl_subsys = "VM";
          if ( defined $inventory_data{$platform}{$type}{$id}{server_name} ) {
            $acl_source = urldecode( $inventory_data{$platform}{$type}{$id}{server_name} );
            if ( $type eq "server" ) {
              $acl_subsys = "SERVER";
              $acl_item   = "";
            }
          }
        }
        elsif ( $acl_platform eq "OVIRT" ) {
          $acl_subsys = "OVIRTVM";
        }
        elsif ( $acl_platform eq "XENSERVER" ) {
          $acl_subsys = "XENVM";
        }
        elsif ( $acl_platform eq "NUTANIX" ) {
          $acl_subsys = "NUTANIXVM";
        }
        elsif ( $acl_platform eq "PROXMOX" ) {
          $acl_subsys = "PROXMOXVM";
        }
        elsif ( $acl_platform eq "FUSIONCOMPUTE" ) {
          $acl_subsys = "FUSIONCOMPUTEVM";
        }

        #elsif ( $server eq "Linux--unknown" ) {
        #  $acl_source   = "Linux";
        #  $acl_platform = "LINUX";
        #  $acl_subsys   = "SERVER";
        #}
        #elsif ( $hyperv ) {
        #  $acl_platform = "HYPERV";
        #}
        #elsif ( $oraclevm ) {
        #  $acl_platform = "ORACLEVM";
        #}
        #elsif ( $item =~ /^oracledb_/ ) {
        #  $acl_platform = "ORACLEDB";
        #}
        #elsif ( $solaris ) {
        #  $acl_platform = "SOLARIS";
        #}
        #elsif ( $server =~ /--unknown$/ || $host eq "no_hmc" ) {
        #  $acl_source   =~ s/--unknown//;
        #  $acl_platform = "UNMANAGED";
        #  $acl_subsys   = "SERVER";
        #}
        else {
          $acl_subsys = "LPAR";
          if ( $type eq "pool" ) {
            $acl_subsys = "POOL";
          }
        }

        #print STDERR "$acl_platform, $acl_subsys, $acl_source, $acl_item  22\n";
        #print STDERR $acl->canShow( $acl_platform, $acl_subsys, $acl_source, $acl_item ) . "tohle vracime\n";
        if ( !$acl->isAdmin() ) {
          if ( !$acl->canShow( $acl_platform, $acl_subsys, $acl_source, $acl_item ) ) {    #  ACL::canShow vrací 0 jestliže nevyhovuje ani jedna z ACL definicí
                                                                                           #print STDERR "$acl_platform, $acl_subsys, $acl_source, $acl_item  $type $id smazano\n";
            delete $inventory_data{$platform}{$type}{$id};
            next;
          }
        }
      }
    }
  }
}

sub parse_heatmap {

  require PowerDataWrapper;
  require SolarisDataWrapper;

  my $platform = shift;
  my $type     = shift;
  my $i        = 0;

  my $type_orig = $type;

  # for vmware is: vm, server, vm-cpu-values, vm-mem-values, server-cpu-values, server-mem-values
  # print STDERR "645 \$platform $platform \$type $type\n";
  if ( $type =~ m/^server/ ) {
    $type = "server";
  }
  if ( $type =~ m/^vm/ ) {
    $type = "vm";
  }
  if ( $type =~ m/^lpar/ ) {
    $type = "lpar";
  }
  if ( $type =~ m/^pool/ ) {
    $type = "pool";
  }

  ### cpu type
  my @files = ( "$webdir/heatmap-$platform-cpu-$type-values.html", "$webdir/heatmap-$platform-mem-$type-values.html" );
  if ( $platform eq "xen" || $platform eq "ovirt" || $platform eq "nutanix" || $platform eq "oraclevm" || $platform eq "proxmox" || $platform eq "fusioncompute" ) {
    @files = ( "$webdir/heatmap-$platform-$type-cpu-values.html", "$webdir/heatmap-$platform-$type-mem-values.html" );
  }
  foreach my $file (@files) {
    if ( !-f $file ) { next; }
    my $mtime = ( stat("$file") )[9];
    $time_heatmap = localtime($mtime);
    my @header = ();
    my @data   = get_array_data($file);

    # line example POWER
    # <tr><td>Power770</td><td><a href="/lpar2rrd-cgi/detail.sh?host=hmc&server=Power770&lpar=SharedPool1&item=shpool&entitle=&gui=1&none=none">AIX2+3</a></td><td>2</td><td><div style="height:15px;width:15px;background-color:#008000; margin: auto;"></div></td></tr>
    #
    # line examples VMWARE
    # with column CPU
    # <tr><td>10.22.11.74</td><td><a href="/lpar2rrd-cgi/detail.sh?host=10.22.11.72&server=10.22.11.74&lpar=pool&item=pool&entitle=0&gui=1&none=none&moref=host-1028&d_platform=VMware&id=8df25c4a-9e09-444a-999b-ead34a7d7e49_17_cluster_domain-c1024_esxi_10.22.11.74">CPU</a></td><td>11</td><td><div style="height:15px;width:15px;background-color:#29f929; margin: auto;"></div></td></tr>
    # or since 7.60 without column CPU
    # <tr><td><a href="/lpar2rrd-cgi/detail.sh?host=10.22.11.72&server=10.22.11.74&lpar=pool&item=pool&entitle=0&gui=1&none=none&moref=host-1028&d_platform=VMware&id=8df25c4a-9e09-444a-999b-ead34a7d7e49_17_cluster_domain-c1024_esxi_10.22.11.74">$server</td><td>11</td><td><div style="height:15px;width:15px;background-color:#29f929; margin: auto;"></div></td></tr>
    # with column MEM
    # <tr><td>10.22.11.74</td><td><a href="/lpar2rrd-cgi/detail.sh?host=10.22.11.72&server=10.22.11.74&lpar=cod&item=pool&entitle=0&gui=1&none=none&moref=host-1028&d_platform=VMware&id=8df25c4a-9e09-444a-999b-ead34a7d7e49_17_cluster_domain-c1024_esxi_10.22.11.74">MEM</a></td><td>40</td><td><div style="height:15px;width:15px;background-color:#c9f433; margin: auto;"></div></td></tr>
    # or since 7.60 without column MEM
    # <tr><td><a href="/lpar2rrd-cgi/detail.sh?host=10.22.11.72&server=10.22.11.74&lpar=cod&item=pool&entitle=0&gui=1&none=none&moref=host-1028&d_platform=VMware&id=8df25c4a-9e09-444a-999b-ead34a7d7e49_17_cluster_domain-c1024_esxi_10.22.11.74">10.22.11.74</a></td><td>40</td><td><div style="height:15px;width:15px;background-color:#c9f433; margin: auto;"></div></td></tr>

    foreach my $line (@data) {
      my @values = ();
      chomp $line;
      if ( $line =~ m/<\/th>/ ) {
        $line =~ s/.*title="//g;
        $line =~ s/".*//g;
        push( @header, $line );
      }
      if ( $line =~ m/<tr>/ ) {
        $line =~ s/<tr>//g;
        $line =~ s/<\/tr>//g;
        $line =~ s/<\/td>//g;
        @values = split( "<td>", $line );
      }
      if ( @values && @header ) {
        my $index = 0;
        $i++;
        foreach my $header (@header) {
          $index++;
          if ( defined $values[$index] ) {
            $inventory_data{$platform}{$type}{$i}{$header} = $values[$index];
          }
        }
        if ( !defined $inventory_data{$platform}{$type}{$i}{TYPE} ) {
          if ( $file =~ m/$platform-cpu-$type-values|$platform-$type-cpu-values/ ) {
            $inventory_data{$platform}{$type}{$i}{TYPE} = "cpu";
            $header{cpu} = \@header;
          }
          else {
            $inventory_data{$platform}{$type}{$i}{TYPE} = "mem";
            $header{mem} = \@header;
          }
        }
      }
    }
  }
  ### add uid and color
  foreach my $id ( keys %{ $inventory_data{$platform}{$type} } ) {
    foreach my $item ( keys %{ $inventory_data{$platform}{$type}{$id} } ) {
      if ( $inventory_data{$platform}{$type}{$id}{$item} =~ m/<a href/ && $inventory_data{$platform}{$type}{$id}{$item} =~ m/uid=|id=/ ) {
        my $uid = $inventory_data{$platform}{$type}{$id}{$item};
        $uid =~ s/.*uid=//g;
        $uid =~ s/.*id=//g;
        if ( $uid =~ m/&/ ) {
          $uid =~ s/&.*//g;
        }
        else {
          $uid =~ s/".*//g;
        }
        if ( defined $uid ) {
          $inventory_data{$platform}{$type}{$id}{uid} = $uid;
        }
      }
      ### server name for vmware because acl
      if ( $inventory_data{$platform}{$type}{$id}{$item} =~ m/<a href/ && $inventory_data{$platform}{$type}{$id}{$item} =~ m/server=/ ) {
        my $server = $inventory_data{$platform}{$type}{$id}{$item};
        $server =~ s/.*server=//g;
        if ( $server =~ m/&/ ) {
          $server =~ s/&.*//g;
        }
        else {
          $server =~ s/".*//g;
        }
        if ( defined $server ) {
          $inventory_data{$platform}{$type}{$id}{server_name} = $server;
        }
      }
      ### name element
      if ( $inventory_data{$platform}{$type}{$id}{$item} =~ m/<a href/ ) {
        my $element  = $inventory_data{$platform}{$type}{$id}{$item};
        my $url_name = $element;
        $url_name =~ s/.*lpar=//g;
        $url_name =~ s/&.*//g;
        $element  =~ s/.*">//g;
        $element  =~ s/<\/a>//g;
        if ( defined $url_name ) {
          $url_name = urldecode($url_name);
          $inventory_data{$platform}{$type}{$id}{URL_NAME} = $url_name;
        }
        if ( defined $element ) {
          $inventory_data{$platform}{$type}{$id}{NAME} = urldecode($element);
          if ( $platform eq "vmware" ) {    # since 7.60 heatmap SERVER CPU/MEM TABLE has only 3 columns
                                            # find server name
            my $server = $inventory_data{$platform}{$type}{$id}{$item};
            my $item   = $server;

            # <a href="/lpar2rrd-cgi/detail.sh?host=10.22.11.72&server=10.22.11.74&lpar=pool
            $server =~ s/.*server=//g;
            $server =~ s/&.*//g;
            if ( $type_orig eq "server" ) {
              my $atxt = $inventory_data{$platform}{$type}{$id}{Server};

              # replace >10.22.11.75</a> at the end
              $atxt =~ s/>.*<\/a/>MEM<\/a/;
              $inventory_data{$platform}{$type}{$id}{Pool}   = $atxt;
              $inventory_data{$platform}{$type}{$id}{Server} = $server;    #"10.11.12.13";
              if ( $item =~ m/lpar=cod/ ) {
                $inventory_data{$platform}{$type}{$id}{NAME} = "MEM";

                # replace >10.22.11.75</a> at the end
                $atxt =~ s/>.*<\/a/>MEM<\/a/;
                $inventory_data{$platform}{$type}{$id}{Pool} = $atxt;
              }
              else {
                $inventory_data{$platform}{$type}{$id}{NAME} = "CPU";

                # replace >10.22.11.75</a> at the end
                $atxt =~ s/>.*<\/a/>CPU<\/a/;
                $inventory_data{$platform}{$type}{$id}{Pool} = $atxt;
              }
            }

            #            }
          }
          if ( $platform eq "power" ) {
            if ( $type eq "lpar" ) {
              $inventory_data{$platform}{$type}{$id}{uid} = PowerDataWrapper::get_item_uid( { type => "VM", label => $url_name } );
            }
          }
        }
      }
      #### server uid power
      if ( $inventory_data{$platform}{$type}{$id}{$item} =~ m/<a href/ && $type eq "pool" && $platform eq "power" ) {
        my $server  = $inventory_data{$platform}{$type}{$id}{Server};
        my $element = $inventory_data{$platform}{$type}{$id}{$item};
        $element =~ s/.*lpar=//g;
        $element =~ s/&.*//g;
        $element = urldecode($element);
        $inventory_data{$platform}{$type}{$id}{URL_NAME} = $element;
        my $server_uid = PowerDataWrapper::get_item_uid( { type => "SERVER", label => $server } );
        $inventory_data{$platform}{$type}{$id}{uid} = PowerDataWrapper::get_item_uid( { type => "SHPOOL", label => $element, parent => $server_uid } );
      }
      if ( $inventory_data{$platform}{$type}{$id}{$item} =~ m/background-color/ ) {
        my $color = $inventory_data{$platform}{$type}{$id}{$item};
        $color =~ s/.*background-color://g;
        $color =~ s/;.*//g;
        if ( defined $color ) {
          $inventory_data{$platform}{$type}{$id}{COLOR} = $color;
        }
      }
      #### platform acl
      if ( $inventory_data{$platform}{$type}{$id}{$item} =~ m/<a href/ && $inventory_data{$platform}{$type}{$id}{$item} =~ m/platform/ ) {
        my $element = $inventory_data{$platform}{$type}{$id}{$item};
        $element =~ s/.*platform=//g;
        $element =~ s/&.*//g;
        $inventory_data{$platform}{$type}{$id}{ACL}{hw_type} = uc($element);
      }
    }

    #acl hash
    if ( !defined $inventory_data{$platform}{$type}{$id}{ACL}{hw_type} ) {
      $inventory_data{$platform}{$type}{$id}{ACL}{hw_type} = uc($platform);
    }

    if ( defined $inventory_data{$platform}{$type}{$id}{uid} ) {
      $inventory_data{$platform}{$type}{$id}{ACL}{item_id} = $inventory_data{$platform}{$type}{$id}{uid};
    }
    $inventory_data{$platform}{$type}{$id}{ACL}{match} = "granted";
  }

  #print STDERR Dumper \%inventory_data;
}

sub get_array_data {
  my $file = shift;
  my $test = test_file_exist($file);
  if ($test) {
    open( FH, "< $file" ) || error_die( "Cannot read $file: $!" . __FILE__ . ":" . __LINE__ );
    my @file_all = <FH>;
    close(FH);
    return @file_all;
  }
  else {
    error( "File not exist $file: $!" . __FILE__ . ":" . __LINE__ );
    my @file_empty = "";
    return @file_empty;
  }
}

sub test_file_exist {
  my $file = shift;
  if ( !-e $file || -z $file ) {
    return 0;
  }
  else {
    return 1;
  }
}

sub gen_tabs {
  my $platform = shift;

  my @types = ( "VM", "Server" );
  if ( $platform eq "power" ) {
    @types = ( "LPAR", "Pool" );
  }
  my @header = ();
  if ( $platform eq "power" ) {
    push( @header, { "LPAR"             => "lpar" } );
    push( @header, { "Server"           => "pool" } );
    push( @header, { "LPAR CPU Table"   => "lpar" } );
    push( @header, { "LPAR MEM Table"   => "lpar" } );
    push( @header, { "Server CPU Table" => "pool" } );
  }
  else {
    push( @header, { "VM"               => "vm" } );
    push( @header, { "Server"           => "server" } );
    push( @header, { "VM CPU Table"     => "vm" } );
    push( @header, { "VM MEM Table"     => "vm" } );
    push( @header, { "Server CPU Table" => "server" } );
    push( @header, { "Server MEM Table" => "server" } );
  }
  print "<div id=\"tabs\">\n";
  print "<ul>\n";
  my $index = 0;
  foreach my $t (@header) {
    my %tabs = %{$t};
    foreach my $tab ( keys %tabs ) {
      $index++;
      if ( -f "$webdir/heatmap-$platform-cpu-$tabs{$tab}-values.html" || -f "$webdir/heatmap-$platform-mem-$tabs{$tab}-values.html" || -f "$webdir/heatmap-$platform-$tabs{$tab}-cpu-values.html" || -f "$webdir/heatmap-$platform-$tabs{$tab}-mem-values.html" ) {
        if ( $index == 1 || $index == 2 ) {
          print "<li><a href=\"/lpar2rrd-cgi/heatmap-xormon.sh?platform=$platform&type=$tabs{$tab}\">$tab</a></li>\n";
          next;
        }
        if ( $index == 3 || $index == 5 ) {
          if ( -f "$webdir/heatmap-$platform-cpu-$tabs{$tab}-values.html" || -f "$webdir/heatmap-$platform-$tabs{$tab}-cpu-values.html" ) {
            print "<li><a href=\"/lpar2rrd-cgi/heatmap-xormon.sh?platform=$platform&type=$tabs{$tab}-cpu-values\">$tab</a></li>\n";
            next;
          }
        }
        if ( $index == 4 || $index == 6 ) {
          if ( -f "$webdir/heatmap-$platform-mem-$tabs{$tab}-values.html" || -f "$webdir/heatmap-$platform-$tabs{$tab}-mem-values.html" ) {
            my $file = "$webdir/heatmap-$platform-mem-$tabs{$tab}-values.html";
            if ( !-f $file && -f "$webdir/heatmap-$platform-$tabs{$tab}-mem-values.html" ) {
              $file = "$webdir/heatmap-$platform-$tabs{$tab}-mem-values.html";
            }
            my $size = ( stat($file) )[7];
            if ( $size > 700 ) {
              print "<li><a href=\"/lpar2rrd-cgi/heatmap-xormon.sh?platform=$platform&type=$tabs{$tab}-mem-values\">$tab</a></li>\n";
            }
            next;
          }
        }
      }
    }
  }
  print "</ul>\n</div>\n";
}

sub error_die {
  my $message = shift;
  print STDERR "$message\n";
  exit(1);
}

sub error {
  my $message = shift;
  print STDERR "$message\n";
}

sub urldecode {
  my $s = shift;
  if ( !defined $s ) {
    return undef;
  }
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;

  #$s =~ s/\+/ /g;
  return $s;
}

sub urlencode {
  my $s = shift;
  if ( !defined $s ) {
    return undef;
  }
  $s =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  #$s =~ s/ /+/g;
  #$s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  return $s;
}

