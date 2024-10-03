#!/usr/bin/perl
#. /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL s2d.pl
use strict;
use warnings;
use Date::Parse;
use Data::Dumper;
use LoadDataModuleHyperV;
use RRDp;

my $inputdir = $ENV{INPUTDIR};
my $perl     = $ENV{PERL} || error("PERL not defined") && exit 1;
my $rrdtool  = $ENV{RRDTOOL};
my $DEBUG    = $ENV{DEBUG};
my $wrkdir   = "$inputdir/data";
my $tmpdir   = "$inputdir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $tmp_hypdir     = "$tmpdir/HYPERV";
my $perf_path      = "";
my $wrkdir_windows = "";
my $entity_type    = "";
my $time           = time;
my @dummy;

if ( $wrkdir !~ /windows$/ ) {
  $wrkdir = "$wrkdir/windows";
}
$wrkdir_windows = $wrkdir;

my @tmphypdir_folders = "";
opendir my $tmphypdirFH, $tmp_hypdir || error("Cannot open $tmp_hypdir") && exit 1;
@tmphypdir_folders = grep { -d "$tmp_hypdir/$_" && !/^..?$/ } readdir($tmphypdirFH);

#print "@tmphypdir_folders\n";
close $tmphypdirFH;

#############################################################

RRDp::start "$rrdtool";

foreach my $hyp_uuid (@tmphypdir_folders) {
  my $cluster_dir = "";
  my $vol_dir     = "";
  my $pdisk_dir   = "";
  $perf_path = "$tmp_hypdir/$hyp_uuid";

  print "$perf_path\n" if $DEBUG == "2";

  # read and sort perfiles
  opendir my $perfdir, $perf_path || error("Cannot open $perf_path") && next;
  my @dir_files = readdir $perfdir;
  close $perfdir;
  @dir_files = sort { $a cmp $b } @dir_files;

  my @pd_perfiles  = grep {/^pd_.*\.csv$/} @dir_files;
  my @vol_perfiles = grep {/^vol_.*\.csv$/} @dir_files;
  my @clu_perfiles = grep {/^clu_.*\.csv$/} @dir_files;
  my @conf_files   = grep {/^config_.*\.csv$/} @dir_files;

  if ( !@conf_files ) {
    error( "No s2d config files for $hyp_uuid, skipping.. " . __FILE__ . ":" . __LINE__ ) if $DEBUG == "2";
    next;
  }
  elsif ( !@pd_perfiles && !@vol_perfiles && !@clu_perfiles ) {
    error( "No perfiles for $hyp_uuid, skipping.. " . __FILE__ . ":" . __LINE__ ) if $DEBUG == "2";
    next;
  }

  # config part

  foreach my $conf_file (@conf_files) {
    $conf_file = "$perf_path/$conf_file";

    open( my $FH, "<$conf_file" ) || error( "Cannot open file $conf_file $!" . __FILE__ . ":" . __LINE__ ) && next;
    my @lines = <$FH>;
    close($FH);

    my @pool_list;
    my @vdisk_list;
    my @volume_list;
    my @pdisk_list;

    my $section  = "";
    my $line_idx = 0;
    my $header   = 0;

    foreach my $a_line (@lines) {
      my $line = $a_line;
      $line_idx++;

      $line =~ s/"//g;
      $line =~ s/^\s+//g;
      $line =~ s/\s+$//g;

      if ( $header == 1 ) {
        $header = 0;
        next;
      }

      if ( $line =~ m/###CLUSTER###/ ) { $section = "CLUSTER"; $header = 1; next; }
      if ( $line =~ m/###POOL###/ )    { $section = "POOL";    $header = 1; next; }
      if ( $line =~ m/###VDISKS###/ )  { $section = "VDISKS";  $header = 1; next; }
      if ( $line =~ m/###VOLUMES###/ ) { $section = "VOLUMES"; $header = 1; next; }
      if ( $line =~ m/###PDISKS###/ )  { $section = "PDISKS";  $header = 1; next; }

      if ( $section eq "CLUSTER" ) {
        my ( $clu_name, $UUID ) = split /[;]/, $line;
        if ( $UUID eq $hyp_uuid ) {
          $cluster_dir = "$wrkdir_windows/cluster_$clu_name";
          if ( !-d "$cluster_dir" ) {
            print "mkdir          : $cluster_dir\n";
            mkdir( "$cluster_dir", 0755 ) || error( " Cannot mkdir $cluster_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
          }
        }
      }
      elsif ( $section eq "POOL" ) {
        my ( $friendly_name, $op_status, $health_status, $size, $alloc_size ) = split /[;]/, $line;
        my $meter          = ( $alloc_size / $size ) * 100;
        my $pool_list_line = $friendly_name . "," . $health_status . "," . $op_status . "," . $size . "," . $alloc_size . "," . $meter . "\n";
        push @pool_list, $pool_list_line;
      }
      elsif ( $section eq "VDISKS" ) {
        my ( $friendly_name, $columns_number, $resiliency, $copies_number, $health_status, $size, $alloc_size, $footprint ) = split /[;]/, $line;
        my $vdisk_list_line = $friendly_name . "," . $columns_number . "," . $resiliency . "," . $copies_number . "," . $health_status . "," . $size . "," . $alloc_size . "," . $footprint . "\n";
        push @vdisk_list, $vdisk_list_line;
      }
      elsif ( $section eq "VOLUMES" ) {
        $vol_dir = "$cluster_dir/volumes";
        my ( $label, $filesystem, $drive_type, $health_status, $op_status, $size, $size_free ) = split /[;]/, $line;
        my $alloc_size    = $size - $size_free;
        my $meter         = ( $alloc_size / $size ) * 100;
        my $vol_list_line = $label . "," . $filesystem . "," . $drive_type . "," . $health_status . "," . $op_status . "," . $size . "," . $alloc_size . "," . $size_free . "," . $meter . "\n";
        push @volume_list, $vol_list_line;
        if ( !-d "$vol_dir" ) {
          print "mkdir          : $vol_dir\n";
          mkdir( "$vol_dir", 0755 ) || error( " Cannot mkdir $vol_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
        }
      }
      elsif ( $section eq "PDISKS" ) {
        $pdisk_dir = "$cluster_dir/pdisks";
        my ( $friendly_name, $media_type, $device_id, $serial, $op_status, $health_status, $usage, $size, $alloc_size, $footprint ) = split /[;]/, $line;
        my $pd_list_line = $friendly_name . "," . $media_type . "," . $device_id . "," . $serial . "," . $health_status . "," . $op_status . "," . $usage . "," . $size . "," . $alloc_size . "\n";
        push @pdisk_list, $pd_list_line;
        if ( !-d "$pdisk_dir" ) {
          print "mkdir          : $pdisk_dir\n";
          mkdir( "$pdisk_dir", 0755 ) || error( " Cannot mkdir $pdisk_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
        }
      }
    }
    open my $FH_s2d, '>:encoding(UTF-8)', "$cluster_dir/s2d_list.html" || error( "can't open $cluster_dir/s2d_list.html: $!" . __FILE__ . ":" . __LINE__ ) && exit 1;
    binmode( $FH_s2d, ":utf8" );

    #pool table
    print $FH_s2d "<CENTER><H3>POOL</H3><TABLE class='tabconfig tablesorter tablehs' data-sortby='-2'>";
    print $FH_s2d "<thead><TR> <TH class='sortable' valign='center'>FriendlyName&nbsp;&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;HealthStatus&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;OperationalStatus&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Size[TiB]&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;AllocatedSize[TiB]&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Used&nbsp;&nbsp;&nbsp;</TH>
    </TR></thead><tbody>\n";
    my $pool_ret = FormatResults( @pool_list, "POOL" );
    print $FH_s2d "$pool_ret";
    print $FH_s2d "</tbody></TABLE></CENTER>\n";

    #vdisk table
    #print $FH_s2d "<BR><CENTER><TABLE class='tabconfig tablesorter tablehs' data-sortby='-2'>";
    #print $FH_s2d "<thead><TR> <TH class='sortable' valign='center'>FriendlyName&nbsp;&nbsp;&nbsp;&nbsp;</TH>
    #<TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Columns&nbsp;&nbsp;&nbsp;</TH>
    #<TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Resiliency&nbsp;&nbsp;&nbsp;</TH>
    #<TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;NumberOfCopies&nbsp;&nbsp;&nbsp;</TH>
    #<TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;HealthStatus&nbsp;&nbsp;&nbsp;</TH>
    #<TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Size&nbsp;&nbsp;&nbsp;</TH>
    #<TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;AllocatedSize&nbsp;&nbsp;&nbsp;</TH>
    #<TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Footprint&nbsp;&nbsp;&nbsp;</TH>
    #</TR></thead><tbody>\n";
    #my $vdisk_ret = FormatResults( @vdisk_list, "VDISKS" );
    #print $FH_s2d "$vdisk_ret";
    #print $FH_s2d "</tbody></TABLE></CENTER>\n";

    #volume table
    print $FH_s2d "<BR><CENTER><H3>VOLUME</H3><TABLE class='tabconfig tablesorter tablehs' data-sortby='-4'>";
    print $FH_s2d "<thead><TR> <TH class='sortable' valign='center'>Label&nbsp;&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;FileSystem&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;DriveType&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;HealthStatus&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;OperationalStatus&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Size[TiB]&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;AllocatedSize[TiB]&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;SizeFree[TiB]&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Used&nbsp;&nbsp;&nbsp;</TH>
    </TR></thead><tbody>\n";
    my $vol_ret = FormatResults( @volume_list, "VOLUMES" );
    print $FH_s2d "$vol_ret";
    print $FH_s2d "</tbody></TABLE></CENTER>\n";

    # pdisk table
    print $FH_s2d "<BR><CENTER><H3>DRIVE</H3><TABLE class='tabconfig tablesorter tablehs' data-sortby='-5'>";
    print $FH_s2d "<thead><TR> <TH class='sortable' valign='center'>FriendlyName&nbsp;&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;MediaType&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;DeviceID&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Serial&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;HealthStatus&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;OperationalStatus&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Usage&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Size[TiB]&nbsp;&nbsp;&nbsp;</TH>
    <TH align='center' class='sortable' valign='center'>&nbsp;&nbsp;&nbsp;Allocated[TiB]&nbsp;&nbsp;&nbsp;</TH>
    </TR></thead><tbody>\n";
    my $pdisk_ret = FormatResults( @pdisk_list, "PDISKS" );
    print $FH_s2d "$pdisk_ret";
    print $FH_s2d "</tbody></TABLE></CENTER>\n";
    close $FH_s2d;
    unlink "$conf_file";
  }    ## foreach my $conf_file (@conf_files)

  # perfiles to rrd

  # cluster
  foreach my $clu_perfile (@clu_perfiles) {

    my $clu_name = $clu_perfile;
    $clu_name =~ s/clu_\d{10}_//g;
    $clu_name =~ s/.csv//g;
    my @clu_rows      = "";
    my $clufile       = "$perf_path/$clu_perfile";
    my $last_time     = "0";
    my $last_file     = "clu_$clu_name.last";
    my $last_file_pth = "$cluster_dir/$last_file";

    #print "$last_file_pth\n";
    my $entity_type = "s2dCluster";
    my %hash;
    my $rrd_full;

    if ( -f $last_file_pth ) {
      open my $lastFH, "<", $last_file_pth;
      $last_time = <$lastFH>;
      close $lastFH;
      $last_time = str2time($last_time);
      chomp $last_time;
    }

    # read each file and save rows
    open( my $clufh, '<', $clufile ) || error("Cannot open $clufile") && next;
    @clu_rows = <$clufh>;
    close $clufh;
    chomp @clu_rows;
    $clu_rows[-1] =~ s/\r//g;
    my $header = shift @clu_rows;    # get rid of csv header

    foreach my $a_row (@clu_rows) {
      my $row = $a_row;

      # example rows
      # "Latency Write";"1620038440";"0.000440328311965812"
      # "Throughput Read";"1620038440";"0"

      # split row to variables and remove double quotes
      $row =~ s/"//g;
      my ( $metric, $utimestamp, $value ) = split /;/, $row;
      $utimestamp = int( $utimestamp / 300 ) * 300;
      if ( $utimestamp > $last_time ) {
        $hash{$utimestamp}{$metric} = $value;
      }    ## if ( $utimestamp > $last_time)
    }    ## foreach my $row (@vol_rows)

    # sort by timestamp
    foreach my $key ( sort { $a <=> $b } keys %hash ) {
      if ( $key > $last_time ) {
        print "$key,$last_time\n" if $DEBUG == "2";
        $last_time = $key;

        my $ts_ref  = $hash{$key};
        my @metrics = ( "Volume.IOPS.Read", "Volume.IOPS.Write", "Volume.Latency.Read", "Volume.Latency.Write", "Volume.Throughput.Read", "Volume.Throughput.Write", "Volume.Size.Available", "Volume.Size.Total" );
        my $rrd_string;

        # add U for empty values
        my $idx = 0;
        foreach my $metric (@metrics) {
          if ( not exists $ts_ref->{$metric} ) {
            $idx++;
            $ts_ref->{$metric} = 'U';
          }
        }
        if ( $idx > 0 && scalar(@metrics) / $idx <= 2 ) { next; }

        # output file
        $rrd_string = $key . "," . $ts_ref->{"Volume.IOPS.Read"} . "," . $ts_ref->{"Volume.IOPS.Write"} . "," . $ts_ref->{"Volume.Latency.Read"} . "," . $ts_ref->{"Volume.Latency.Write"} . "," . $ts_ref->{"Volume.Throughput.Read"} . "," . $ts_ref->{"Volume.Throughput.Write"} . "," . $ts_ref->{"Volume.Size.Available"} . "," . $ts_ref->{"Volume.Size.Total"};
        print "$rrd_string\n" if $DEBUG == "2";
        $rrd_full .= "$rrd_string" . " ";
      }    ## if ($key > $last_time)
    }    ## foreach my $key (sort { $a <=> $b } keys %hash)

    if ($rrd_full) {

      #1620903825:0:0.452967279579637:0:0.000593345152985601:0:8444.48998841285 1620904125:0:0.256575735910001:0:0.000563157857142857:0:4533.22753852845
      my $res_update = LoadDataModuleHyperV::load_data( "", "", "$cluster_dir", \$rrd_full, "m", "$time", "", "", "", "300", "$DEBUG", \@dummy, "$last_file", "1080", "", "", "clu_$clu_name", "$entity_type", "" );
    }
    unlink "$perf_path/$clu_perfile";

  }    ## foreach my $clu_perfile (@clu_perfiles)

  # volumes
  foreach my $vol_perfile (@vol_perfiles) {

    # example file
    # vol_1620645015_volume01.csv
    my $vol_name = $vol_perfile;
    $vol_name =~ s/vol_\d{10}_//g;
    $vol_name =~ s/.csv//g;
    my @vol_rows      = "";
    my $volfile       = "$perf_path/$vol_perfile";
    my $last_time     = "0";
    my $last_file     = "vol_$vol_name.last";
    my $last_file_pth = "$vol_dir/$last_file";

    #print "$last_file_pth\n";
    my $entity_type = "s2dVolume";
    my %hash;
    my $rrd_full;

    if ( -f $last_file_pth ) {
      open my $lastFH, "<", $last_file_pth;
      $last_time = <$lastFH>;
      close $lastFH;
      $last_time = str2time($last_time);
      chomp $last_time;
    }

    # read each file and save rows
    open( my $volfh, '<', $volfile ) || error("Cannot open $volfile") && next;
    @vol_rows = <$volfh>;
    close $volfh;
    chomp @vol_rows;
    $vol_rows[-1] =~ s/\r//g;
    my $header = shift @vol_rows;    # get rid of csv header

    foreach my $a_row (@vol_rows) {
      my $row = $a_row;

      # example rows
      # "Latency Write";"1620038440";"0.000440328311965812"
      # "Throughput Read";"1620038440";"0"

      # split row to variables and remove double quotes
      $row =~ s/"//g;
      my ( $metric, $utimestamp, $value ) = split /;/, $row;
      $utimestamp = int( $utimestamp / 300 ) * 300;
      if ( $utimestamp > $last_time ) {
        $hash{$utimestamp}{$metric} = $value;
      }    ## if ( $utimestamp > $last_time)
    }    ## foreach my $row (@vol_rows)

    # sort by timestamp
    foreach my $key ( sort { $a <=> $b } keys %hash ) {
      if ( $key > $last_time ) {
        print "$key,$last_time\n" if $DEBUG == "2";
        $last_time = $key;
        my $ts_ref     = $hash{$key};
        my @metrics    = ( "Size Available", "Size Total", "IOPS Read", "IOPS Write", "Latency Read", "Latency Write", "Throughput Read", "Throughput Write" );
        my $rrd_string = $key . ",";
        my @vals       = ();
        my $idx        = 0;
        foreach my $metric (@metrics) {
          if ( exists $ts_ref->{$metric} ) {
            push( @vals, $ts_ref->{$metric} );
          }
          else {
            $idx++;
            push( @vals, "U" );
          }
        }
        $rrd_string .= join( ",", @vals );
        if ( $idx > 0 ) {
          error( "Update line: $rrd_string has empty values, skip " . __FILE__ . ":" . __LINE__ ) if $DEBUG == "2";
          next;
        }
        $rrd_full .= "$rrd_string" . " ";
      }    ## if ($key > $last_time)
    }    ## foreach my $key (sort { $a <=> $b } keys %hash)

    if ($rrd_full) {

      #1620903825:0:0.452967279579637:0:0.000593345152985601:0:8444.48998841285 1620904125:0:0.256575735910001:0:0.000563157857142857:0:4533.22753852845
      my $res_update = LoadDataModuleHyperV::load_data( "", "", "$vol_dir", \$rrd_full, "m", "$time", "", "", "", "300", "$DEBUG", \@dummy, "$last_file", "1080", "", "", "vol_$vol_name", "$entity_type", "" );
    }
    unlink "$perf_path/$vol_perfile";
  }    ## foreach my $vol_perfile (@vol_perfiles)

  # pdisks
  foreach my $pd_perfile (@pd_perfiles) {

    # example
    # pd_1620038445_6000c299aa64d51fb858da1991b2bf7e.csv
    my ( undef, $pd_filetime, $pd_id, undef ) = split /[_.]/, $pd_perfile;
    my @pd_rows       = "";
    my $pdfile        = "$perf_path/$pd_perfile";
    my $last_time     = "0";
    my $last_file     = "pd_$pd_id.last";
    my $last_file_pth = "$pdisk_dir/$last_file";
    my $entity_type   = "s2dPhysicalDisk";
    my %hash;
    my $rrd_full;

    if ( -f $last_file_pth ) {
      open my $lastFH, "<", $last_file_pth;
      $last_time = <$lastFH>;
      close $lastFH;
      $last_time = str2time($last_time);
    }

    # read each file and save rows
    open( my $pdfh, '<', $pdfile ) || error("Cannot open $pdfile") && next;
    @pd_rows = <$pdfh>;
    close $pdfh;
    chomp @pd_rows;
    $pd_rows[-1] =~ s/\r//g;
    my $header = shift @pd_rows;    # get rid of csv header

    foreach my $a_row (@pd_rows) {
      my $row = $a_row;

      # example rows
      # "Latency Write";"1620038440";"0.000440328311965812"
      # "Throughput Read";"1620038440";"0"
      #
      # split row to variables and remove double quotes
      $row =~ s/"//g;
      my ( $metric, $utimestamp, $value ) = split /;/, $row;
      $utimestamp = int( $utimestamp / 300 ) * 300;
      if ( $utimestamp > $last_time ) {

        #print localtime().": \$utimestamp > \$last_time : $utimestamp > $last_time\n";
        #print "$metric, $utimestamp, $value\n";
        $hash{$utimestamp}{$metric} = $value;
      }    ## if ( $utimestamp > $last_time)
    }    ## foreach my $row (@pd_rows)

    # sort by timestamp
    foreach my $key ( sort { $a <=> $b } keys %hash ) {
      if ( $key > $last_time ) {
        print "$key,$last_time\n" if $DEBUG == "2";
        $last_time = $key;
        my $ts_ref     = $hash{$key};
        my @metrics    = ( "IOPS Read", "IOPS Write", "Latency Read", "Latency Write", "Throughput Read", "Throughput Write" );
        my $rrd_string = $key . ",";
        my @vals       = ();
        my $idx        = 0;
        foreach my $metric (@metrics) {
          if ( exists $ts_ref->{$metric} ) {
            push( @vals, $ts_ref->{$metric} );
          }
          else {
            $idx++;
            push( @vals, "U" );
          }
        }
        $rrd_string .= join( ",", @vals );
        if ( $idx > 3 ) {
          error( "Update line: $rrd_string has too many empty values, skip " . __FILE__ . ":" . __LINE__ ) if $DEBUG == "2";
          next;
        }
        $rrd_full .= "$rrd_string" . " ";

      }    ## if ($key > $last_time)
           #print "$rrd_full\n";
    }    ## foreach my $key (sort { $a <=> $b } keys %hash)

    #print Dumper \%hash;
    #print "$rrd_full\n";

    if ($rrd_full) {

      #1620903825:0:0.452967279579637:0:0.000593345152985601:0:8444.48998841285 1620904125:0:0.256575735910001:0:0.000563157857142857:0:4533.22753852845
      my $res_update = LoadDataModuleHyperV::load_data( "", "", "$pdisk_dir", \$rrd_full, "m", "$time", "", "", "", "300", "$DEBUG", \@dummy, "$last_file", "1080", "", "", "pd_$pd_id", "$entity_type", "" );
    }    ## if ($rrd_full)
    unlink "$perf_path/$pd_perfile";
  }    ## foreach my $pd_perfile (@pd_perfiles)
}    ## foreach my $hyp_uuid (@tmphypdir_folders)

####################################################################################################

RRDp::end;

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);
  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";
  return 1;
}

sub FormatResults {
  my @results_unsort = @_;
  my $section        = pop @results_unsort;
  my $line           = "";
  my $formated       = "";
  my @items1         = "";
  my $item           = "";
  my $edit_item      = "";
  my $TB_divider     = 1024 * 1024 * 1024 * 1024;    # bytes to TiB

  # if any param except 1st starts "comment_" it is comment in HTML
  my @results = sort { lc $a cmp lc $b } @results_unsort;
  foreach $line (@results) {
    chomp $line;
    @items1   = split /,/, $line;
    $formated = $formated . "<TR>";
    my $col = 0;
    foreach $item (@items1) {
      if ( $col == 0 ) {
        $formated .= "<TD><B>$item</B></TD>";
      }
      elsif ( $section eq "PDISKS" and $col == 3 ) {
        $formated .= "<TD>$item</TD>";
      }
      elsif ( ( $section eq "POOL" and $col == 5 ) || ( $section eq "VOLUMES" and $col == 8 ) ) {
        $formated .= "<TD><meter value='$item' min='0' max='100' optimum='0' low='80' high='95' title='$item% of capacity allocated'>$item</meter></TD>";
      }
      elsif ( ( $section eq "PDISKS" and $col == 4 ) || ( $section eq "VOLUMES" and $col == 3 ) || ( $section eq "POOL" and $col == 1 ) ) {
        if ( $item =~ s/^Healthy$// ) {
          $formated .= "<TD class='hsok' data-sortvalue='3' align='center'></TD>";
        }
        elsif ( $item =~ s/^Unknown$// ) {
          $formated .= "<TD class='hsna' data-sortvalue='2' align='center'></TD>";
        }
        elsif ( $item =~ /^Unhealthy$/ || $item =~ /^Warning$/ ) {
          $formated .= "<TD class='hsnok' data-sortvalue='1' align='center'></TD>";
        }
      }
      elsif ( ( $col == 6 ) && ( $section eq "PDISKS" ) ) {
        if ( $item =~ s/^Journal$// ) {
          $item = "Cache";
        }
        elsif ( $item =~ s/^Auto-Select$// ) {
          $item = "Capacity";
        }
        $formated .= "<TD align='center'>$item</TD>";
      }
      elsif ( ( $col == 9 || $col == 8 || $col == 7 ) && ( $section eq "PDISKS" ) ) {
        $edit_item = sprintf( "%6.2f", $item / $TB_divider );
        $formated .= "<TD data-sortvalue='$item' align='center'>" . $edit_item . "</TD>\n";
      }
      elsif ( ( $col == 5 || $col == 6 || $col == 7 ) && ( $section eq "VOLUMES" ) ) {
        $edit_item = sprintf( "%6.2f", $item / $TB_divider );
        $formated .= "<TD data-sortvalue='$item' align='center'>" . $edit_item . "</TD>";
      }
      elsif ( ( $col == 3 || $col == 4 ) && ( $section eq "POOL" ) ) {
        $edit_item = sprintf( "%6.2f", $item / $TB_divider );
        $formated .= "<TD data-sortvalue='$item' align='center'>" . $edit_item . "</TD>";
      }
      else {
        $formated = sprintf( "%s <TD align='center'>%s</TD>", $formated, $item );
      }
      $col++;
    }
    $formated = $formated . "</TR>\n";
  }
  return $formated;
}
