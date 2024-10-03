use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);
use MIME::Base64 qw(encode_base64 decode_base64);
use Env qw(QUERY_STRING);
use Data::Dumper;
use File::Copy;
use File::Temp qw/ tempfile/;
use File::Path 'rmtree';
use JSON;
use File::Basename;
use Xorux_lib qw(read_json write_json uuid_big_endian_format parse_url_params);

my $basedir  = $ENV{INPUTDIR};
my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$basedir/data";
my $menu_txt = "$inputdir/tmp/menu.txt";
my @menu;
my $csv = 0;

( my $pattern, undef, undef, undef, my $item ) = split( /&/, $QUERY_STRING );
if ( defined $item && $item eq "item=all_multipath" ) {
  $csv = 1;
  $pattern =~ s/LPAR=//g;
  $item =~ s/item=//g;

  #my $server_url_csv = urlencode("$pattern");
  #print_topten_to_csv( $sort_order, $item, $item_a, $period, $server_url_csv );
}

if ( -f $menu_txt ) {
  open( FC, "< $menu_txt" ) || error( "Cannot read $menu_txt: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  @menu = <FC>;
  close(FC);
}

my @list_of_lpars     = grep {/^L:.*:.*:.*:.*:.*:.*:P:.*$/} @menu;        # "P" -> only POWER section
my @list_of_linuxes   = grep {/^L:.*:Linux:.*:.*:.*:.*:.*:.*$/} @menu;    # "P" -> only POWER section
my @list_of_solarises = grep {/Solaris/} @menu;                           # "P" -> only POWER section

#########################
######## AIX
#########################
my @aix_lines;
foreach my $line (@list_of_lpars) {
  my ( undef, $hmc, $server, $lpar, undef, $url, undef, undef, undef, $lpar_type ) = split( /:/, $line );
  my $file_multipath = "$wrkdir/$server/$hmc/$lpar/aix_multipathing.txt";

  #print STDERR"$file_multipath\n";
  if ( -f "$file_multipath" ) {
    open( FH, "< $file_multipath" ) || error( "Cannot open $file_multipath: $!" . __FILE__ . ":" . __LINE__ );
    my @lsdisk_arr = <FH>;
    close(FH);
    my @list_of_disk;
    foreach my $line (@lsdisk_arr) {
      ( my $namedisk ) = split( /:/, $line );
      push @list_of_disk, $namedisk;
    }
    foreach my $line (@lsdisk_arr) {
      chomp($line);
      ( my $namedisk, my $path_id, my $connection, my $parent, my $path_status, my $status, my $disk_size ) = split( /:/, $line );

      #print "$path_id, my $connection, my $parent, my $path_status, my $status\n";
      my $line_to_push = "$lpar:$namedisk:$parent,$connection:$path_status:$status:$disk_size\n";
      push @aix_lines, $line_to_push;

      #print STDERR"$namedisk,$path_id,$connection,$parent,$path_status,$status???\n";
    }
  }
}

#########################
######## LINUX
#########################
my @linux_lines;
foreach my $line (@list_of_linuxes) {
  my ( undef, undef, undef, $lpar, undef, $url, undef, undef, undef, $lpar_type ) = split( /:/, $line );
  my $file_multipath = "$wrkdir/Linux--unknown/no_hmc/$lpar/linux_multipathing.txt";

  #print STDERR"$file_multipath\n";
  if ( -f "$file_multipath" ) {
    open( FH, "< $file_multipath" ) || error( "Cannot open $file_multipath: $!" . __FILE__ . ":" . __LINE__ );
    my @lsdisk_arr = <FH>;
    close(FH);
    my @list_of_disk;
    if ( -f "$file_multipath" ) {
      open( FH, "< $file_multipath" ) || error( "Cannot open $file_multipath: $!" . __FILE__ . ":" . __LINE__ );
      my @multi_lin_arr = <FH>;
      close(FH);
      foreach my $line (@multi_lin_arr) {
        chomp($line);
        my ( $string1, $string2, $string3, $string4 ) = split( /:/, $line );
        my $line_to_push = "$lpar,$string1,$string2,$string3,$string4\n";
        push @linux_lines, $line_to_push;

        #print STDERR"$string1,$string2,$string3,$string4\n";
      }
    }
  }
}

#########################
######## LINUX under LPARs
#########################
foreach my $line (@list_of_lpars) {
  my ( undef, $hmc, $server, $lpar, undef, $url, undef, undef, undef, $lpar_type ) = split( /:/, $line );
  my $file_multipath = "$wrkdir/$server/$hmc/$lpar/linux_multipathing.txt";

  #print STDERR"$file_multipath\n";
  if ( -f "$file_multipath" ) {
    open( FH, "< $file_multipath" ) || error( "Cannot open $file_multipath: $!" . __FILE__ . ":" . __LINE__ );
    my @lsdisk_arr = <FH>;
    close(FH);
    my @list_of_disk;
    if ( -f "$file_multipath" ) {
      open( FH, "< $file_multipath" ) || error( "Cannot open $file_multipath: $!" . __FILE__ . ":" . __LINE__ );
      my @multi_lin_arr = <FH>;
      close(FH);
      foreach my $line (@multi_lin_arr) {
        chomp($line);
        my ( $string1, $string2, $string3, $string4 ) = split( /:/, $line );
        my $line_to_push = "$lpar,$string1,$string2,$string3,$string4\n";
        push @linux_lines, $line_to_push;

        #print STDERR"$string1,$string2,$string3,$string4\n";
      }
    }
  }
}

#########################
######## SOLARIS
#########################
my @solaris_lines;
foreach my $line (@list_of_solarises) {
  my ( undef, undef, undef, $lpar, undef, $url, undef, undef, undef, $lpar_type ) = split( /:/, $line );
  $lpar =~ s/===double-col===/:/g;
  my $file_multipath = "$wrkdir/Solaris/$lpar/solaris_multipathing.txt";

  #print STDERR"$file_multipath\n";
  if ( -f "$file_multipath" ) {
    open( FH, "< $file_multipath" ) || error( "Cannot open $file_multipath: $!" . __FILE__ . ":" . __LINE__ );
    my @lsdisk_arr = <FH>;
    close(FH);
    my @list_of_disk;
    if ( -f "$file_multipath" ) {
      open( FH, "< $file_multipath" ) || error( "Cannot open $file_multipath: $!" . __FILE__ . ":" . __LINE__ );
      my @multi_lin_arr = <FH>;
      close(FH);
      foreach my $line (@multi_lin_arr) {
        chomp($line);
        my ( $string1, $string2, $string3, $string4, $string5, $string6, $string7 ) = split( /:/, $line );
        my $line_to_push = "$lpar,$string1,$string2,$string3,$string4,$string5,$string6,$string7\n";
        push @solaris_lines, $line_to_push;

        #print STDERR"$string1,$string2,$string3,$string4\n";
      }
    }
  }
}

#######################
# set unbuffered stdout
$| = 1;

# CGI-BIN HTML header
if ( !$csv ) {
  print "Content-type: text/html\n\n";
}
my @sorted_aix_lines   = sort @aix_lines;
my @sorted_linux_lines = sort @linux_lines;

my %hash_aix      = ();
my %hash_aix_size = ();
foreach my $line_to_hash (@sorted_aix_lines) {
  chomp($line_to_hash);
  my ( $lpar, $namedisk, $parent, $path_status, $status, $disk_size ) = split( /:/, $line_to_hash );

  #print "$lpar,$namedisk,$parent,$path_status,$status\n";
  $parent =~ s/=====double-colon=====/:/g;
  my $values = "$path_status:$status";
  push @{ $hash_aix{$lpar}{$namedisk}{$parent} }, $values;
  if ( Xorux_lib::isdigit($disk_size) ) {
    $hash_aix_size{$namedisk}{disk_size} = $disk_size;
  }

}

# create CSV with all multipaths
if ($csv) {
  my $csv_file = "multipath_report.csv";
  my $sep      = ";";
  print "Content-Disposition: attachment;filename=\"$csv_file\"\n\n";
  my $csv_header = "System" . "$sep" . "Disk name" . "$sep" . "Disk size [MB]" . "$sep" . "Disk ID" . "$sep" . "Path properties" . "$sep" . "Path info" . "$sep" . "Path status" . "$sep" . "Status\n";
  print "$csv_header";
  foreach my $line_to_hash (@sorted_aix_lines) {
    chomp($line_to_hash);
    my ( $lpar, $namedisk, $parent, $path_status, $status ) = split( /:/, $line_to_hash );
    my $disk_size = "-";
    if ( defined $hash_aix_size{$namedisk}{disk_size} ) {
      $disk_size = $hash_aix_size{$namedisk}{disk_size};
    }
    $parent =~ s/,/ | /g;
    my $final_status = "OK";
    if ( $path_status !~ /Available/ ) {
      $final_status = "Critical";
    }
    print "$lpar" . "$sep" . "$namedisk" . "$sep" . "$disk_size" . "$sep" . "-" . "$sep" . "$parent" . "$sep" . "$path_status" . "$sep" . "$status" . "$sep" . "$final_status\n";
  }
  foreach my $line (@sorted_linux_lines) {
    chomp($line);
    my ( $linux_name, $string1, $string2, $string3, $string4 ) = split( /,/, $line );
    $string1 =~ s/\\//g;
    $string3 =~ s/\//|/g;
    $string4 =~ s/\//|/g;
    $string4 =~ s/=====double-colon=====/:/g;
    my $final_status = "OK";
    if ( $string4 !~ /ready|ghost/ ) {
      $final_status = "Critical";
    }
    print "$linux_name" . "$sep" . "$string1" . "$sep" . "-" . "$sep" . "$string2" . "$sep" . "$string3" . "$sep" . "$string4" . "$sep" . "-" . "$sep" . "$final_status\n";
  }
  foreach my $line (@solaris_lines) {
    chomp($line);
    my ( $solaris_name, $info_about, $string1, $string2, $string3, $string4 ) = split( /,/, $line );
    my ( $disk_id, $disk_alias, $vendor, $product, $revision, $name_type, $asymmetric, $curr_load_balance ) = split( /\//, $info_about );
    $string1 =~ s/\//|/g;
    $string2 =~ s/\//|/g;
    $string3 =~ s/\//|/g;
    $string4 =~ s/\//|/g;
    my @relative_id   = split( /\|/, $string1 );
    my @disabled_info = split( /\|/, $string2 );
    my @path_states   = split( /\|/, $string3 );
    my @access_states = split( /\|/, $string4 );
    my $final_status  = "OK";

    if ( $string3 !~ /OK/ ) {
      $final_status = "Critical";
    }
    print "$solaris_name" . "$sep" . "$disk_alias" . "$sep" . "-" . "$sep" . "$disk_id" . "$sep" . "$vendor | $product | $revision | $name_type" . "$sep" . "ID: $string1 | Disabled: $string2 | Path: $string3 | Access: $string4" . "$sep" . "-" . "$sep" . "$final_status\n";
  }
  exit 0;
}

#<a class=\"csvfloat\" href=\"/lpar2rrd-cgi/multi_csv.sh?SERVER=\$server&HMC=\$host&LPAR=\$lpar&host=CSV_multi&item=all_multipath\" style=\"display: block; margin-left: auto; margin-right: 0px; max-width: fit-content;title=\"MULTIPATH CSV\"><img src=\"css/images/csv.png\"></a>

if ( !$csv ) {
  if ( scalar @solaris_lines > 0 && @solaris_lines ne '' || scalar @aix_lines > 0 && @aix_lines ne '' || scalar @linux_lines > 0 && @linux_lines ne '' ) {
    print "<div id =\"tabs-4\">
    <a class=\"csvfloat\" href=\"/lpar2rrd-cgi/multi_csv.sh?SERVER=\$server&HMC=\$host&LPAR=\$lpar&host=CSV_multi&item=all_multipath\" style=\"display: block; margin-left: auto; margin-right: 0px; max-width: fit-content;title=\"MULTIPATH CSV\"><img src=\"css/images/csv.png\"></a>
    <div id='hiw'><a href='http://www.lpar2rrd.com/multipath.php' target='_blank'><img src='css/images/help-browser.gif' alt='Reporter help page' title='Reporter help page'></a></div>
    <center>
    <table id='table-multipath' data-sortby='5'>
    <thead>
    <tr>
    <th class='group-text'>System</th>
    <th class='group-false'>Disk name</th>
    <th class='group-false'>Disk size [MB]</th>
    <th class='group-false'>Disk ID</th>
    <th class='group-false'>Path properties</th>
    <th class='group-false'>Path info</th>
    <th class='group-false'>Path status</th>
    <th class='group-text'>Status</th>
    </tr>
    </thead>";
  }
  else {
    print "<div id =\"tabs-4\">
    <div id='hiw'><a href='http://www.lpar2rrd.com/multipath.php' target='_blank'><img src='css/images/help-browser.gif' alt='Reporter help page' title='Reporter help page'></a></div>";
    my $status_multi = "No multipath info found, do you have any OS agents installed?";
    print "<td>$status_multi</p></td>";
  }
}

#  print "$load_cpu" . "$sep" . "$load_peak" . "$sep" . "$vm_name" . "$sep" . "$server_pool_name" . "$sep" . "$manager_name";

foreach my $lpar ( keys %hash_aix ) {
  my $color_ok       = "#d3f9d3";                    ##### GREEN
  my $color_crit     = "#ffb8b8";                    ##### RED
  my $color_warn     = "#ffe6b8";                    ##### ORANGE
  my $color_ok_text  = "";
  my $status_text_ok = "OK";
  my $count_lpar     = keys %{ $hash_aix{$lpar} };
  foreach my $namedisk ( sort keys %{ $hash_aix{$lpar} } ) {
    my $count     = keys %{ $hash_aix{$lpar}{$namedisk} };
    my $disk_size = "-";
    if ( defined $hash_aix_size{$namedisk}{disk_size} ) {
      $disk_size = $hash_aix_size{$namedisk}{disk_size};
    }
    print "<td>$lpar</td>";
    print "<td>$namedisk</td>";
    print "<td>$disk_size</td>";
    print "<td></td>";
    if ( $count > 1 ) {
      print "<td>";
    }
    my @string_test1;
    my @string_test2;
    foreach my $parent ( sort keys %{ $hash_aix{$lpar}{$namedisk} } ) {
      my ( $path_status, $status ) = split( /:/, $hash_aix{$lpar}{$namedisk}{$parent}[0] );
      push @string_test1, $path_status . "\n";    ### last value status to array, because <td> problem / print at the end foreach
      push @string_test2, $status . "\n";         ### last value status to array, because <td> problem / print at the end foreach
      if ( $count > 1 ) {
        print "$parent<br>";
      }
      else {
        my $id_status;
        if ( $status !~ /Available|Enabled/ ) {
          $color_ok       = "hs_error";
          $id_status      = 3;
          $status_text_ok = "Critical";
          $color_ok_text  = "#ED3027";            ##### RED
        }
        else {
          $color_ok       = "hs_good";            ##### GREEN
          $status_text_ok = "OK";
          $id_status      = 1;
          $color_ok_text  = "#36B236";            ##### GREEN
        }
        print "<td>$parent</td>";
        print "<td style='color:$color_ok_text;'>$status</td>";
        print "<td>$path_status</td>";
        print "<td class='$color_ok' data-text='$id_status'>$status_text_ok</td>";
      }
    }
    if ( $count > 1 ) {
      print "</td>";
      print "<td>";
      my $status_text = "";
      my $grep_ok     = grep {/^Available$/} @string_test1;
      my $grep_nok    = grep {/^Defined$|^Missing$/} @string_test1;
      foreach my $status_a (@string_test1) {
        if ( $status_a !~ /Available/ ) {
          $color_ok = "#ED3027";
        }
        else {
          $color_ok = "#36B236";
        }
        print "<font color=$color_ok>$status_a</font><br>";
      }
      print "</td>";
      print "<td>";
      foreach my $status_b (@string_test2) {
        print "$status_b<br>";
      }
      print "</td>";
      if ( $grep_ok >= 1 && $grep_nok == 0 ) {    ##### OK
        $status_text = "OK";
        print "<td class=\"hs_good\" data-text='1'>$status_text</p></td>";
      }
      elsif ( $grep_ok >= 1 && $grep_nok >= 1 ) {    ##### WARNING
        $status_text = "Warning";
        print "<td class=\"hs_warning\" data-text='2'>$status_text</p></td>";
      }
      elsif ( $grep_ok == 0 && $grep_nok >= 1 ) {    ##### CRITICAL
        $status_text = "Critical";
        print "<td class=\"hs_error\" data-text='3'>$status_text</p></td>";
      }
    }
    print "</tr>";
  }
}
print "</tr>";

foreach my $line (@sorted_linux_lines) {
  chomp($line);
  my ( $linux_name, $string1, $string2, $string3, $string4 ) = split( /,/, $line );
  $string1 =~ s/\\//g;
  $string3 =~ s/\//|/g;
  $string4 =~ s/\//|/g;
  $string4 =~ s/=====double-colon=====/:/g;
  my $color_ok    = "#d3f9d3";    ##### GREEN
  my $color_crit  = "#f7f7f7";
  my $color_warn  = "#E4D41D";
  my $status_text = "OK";
  my ( $alias, $wwid, $split1 ) = "";

  if ( $string1 =~ /\(/ ) {
    ( $alias, $split1 ) = split( /\(/, $string1 );
    $split1 =~ s/\)//g;
    ($wwid) = split( / /, $split1 );
  }
  my @path_groups = split( /\|/, $string3 );
  my @paths       = split( /\|/, $string4 );
  my $rowspan_line = scalar @path_groups;
  print "<tr>";
  print "<td>$linux_name</td>";
  print "<td>$alias</td>";
  print "<td>-</td>";
  print "<td>$wwid</td>";
  print "<td>$string2</td>";
  my $i = 0;
  print "<td>";
  my @ok_lines;

  foreach (@path_groups) {
    if ( $path_groups[$i] ) {

      # 4:0:0:0 sde 8:64 active ready running
      my $color_text = "";
      my ( undef, undef, $status ) = split( /(\d+\:\d+\:\d+\:\d+)/, $paths[$i] );
      $status =~ s/^\s+//g;
      $status =~ s/\D+\d+\:\d+//g;
      push @ok_lines, $status . "\n";
      my $path = "$paths[$i]";
      $path =~ s/(active \S+ \S+)|(failed \S+ \S+)|(faulty \S+ \S+)//g;

      if ( $status =~ /ghost|ready/ ) {
        $color_text = "#36B236";
      }
      else {
        $color_text = "#ED3027";    ##### RED
      }
      print "$path_groups[$i]<br>$path<font color=$color_text>$status</font><br>";
      $i++;
    }
  }
  my $grep_ok  = grep {/ghost|ready/} @ok_lines;
  my $grep_nok = grep {/faulty/} @ok_lines;
  print "</td>";
  print "<td></td>";
  if ( $grep_ok >= 1 && $grep_nok == 0 ) {    ##### OK
    $status_text = "OK";
    print "<td class=\"hs_good\" data-text='1'>$status_text</p></td>";
  }
  elsif ( $grep_ok >= 1 && $grep_nok >= 1 ) {    ##### WARNING
    $status_text = "Warning";
    print "<td class=\"hs_warning\" data-text='2'>$status_text</p></td>";
  }
  elsif ( $grep_ok == 0 && $grep_nok >= 1 ) {    ##### CRITICAL
    $status_text = "Critical";
    print "<td class=\"hs_error\" data-text='3'>$status_text</p></td>";
  }
  print "</tr>";
}

foreach my $line (@solaris_lines) {
  chomp($line);
  my ( $solaris_name, $info_about, $string1, $string2, $string3, $string4 ) = split( /,/, $line );
  my ( $disk_id, $disk_alias, $vendor, $product, $revision, $name_type, $asymmetric, $curr_load_balance ) = split( /\//, $info_about );
  $string1 =~ s/\//|/g;
  $string2 =~ s/\//|/g;
  $string3 =~ s/\//|/g;
  $string4 =~ s/\//|/g;
  my $color_ok      = "#d3f9d3";                 ##### GREEN
  my $status_text   = "OK";
  my @relative_id   = split( /\|/, $string1 );
  my @disabled_info = split( /\|/, $string2 );
  my @path_states   = split( /\|/, $string3 );
  my @access_states = split( /\|/, $string4 );

  #print STDERR "$solaris_name,$disk_alias,$vendor,$product,$revision,$name_type,$asymmetric,$curr_load_balance---$relative_id[0]\n";
  print "<tr>";
  print "<td>$solaris_name</td>";
  print "<td>$disk_alias</td>";
  print "<td>-</td>";
  print "<td>$disk_id</td>";
  print "<td>$vendor,$product,$revision,$name_type";
  print "<br>Asymmetric: $asymmetric,Load Balance: $curr_load_balance</br>";
  print "</td>";
  my $j = 0;
  print "<td>";
  my @ok_lines;

  foreach (@relative_id) {
    my $path_ok = "";

    #my $grep_ok = grep {/OK/} @path_states;
    #print STDERR"$grep_ok\n";
    push @ok_lines, $path_states[$j] . "\n";
    if ( $path_states[$j] eq "OK" ) {
      $path_ok = "#36B236";    ##### GREEN
    }
    else {
      $path_ok  = "#ED3027";
      $color_ok = "#ffe6b8";
    }
    if ( $access_states[$j] ) {
      print "ID:$relative_id[$j],Disabled:$disabled_info[$j],Path:<font color=$path_ok>$path_states[$j]</font>,Access:$access_states[$j]</br>";
    }
    else {
      print "ID:$relative_id[$j],Disabled:$disabled_info[$j],Path:<font color=$path_ok>$path_states[$j]</font></br>";
    }
    $j++;
  }
  print "</td>";
  print "<td></td>";
  my $grep_ok  = grep {/^OK$/} @ok_lines;
  my $grep_nok = grep {/^NOK$/} @ok_lines;
  if ( $grep_ok >= 1 && $grep_nok == 0 ) {    ##### OK
    $status_text = "OK";
    print "<td class=\"hs_good\" data-text='1'>$status_text</p></td>";
  }
  elsif ( $grep_ok >= 1 && $grep_nok >= 1 ) {    ##### WARNING
    $status_text = "Warning";
    print "<td class=\"hs_warning\" data-text='2'>$status_text</p></td>";
  }
  elsif ( $grep_ok == 0 && $grep_nok >= 1 ) {    ##### CRITICAL
    $status_text = "Critical";
    print "<td class=\"hs_error\" data-text='3'>$status_text</p></td>";
  }
}

print "</table>
</center>
</div>\n";

