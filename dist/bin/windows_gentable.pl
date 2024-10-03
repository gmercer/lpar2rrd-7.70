#!/usr/bin/perl
#. /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL windows_gentable.pl
use strict;
use warnings;
use Xorux_lib;
use Data::Dumper;

my $inputdir = $ENV{INPUTDIR};
my $perl     = $ENV{PERL} || Xorux_lib::error("PERL not defined") && exit 1;
my $DEBUG    = $ENV{DEBUG};
my $tmpdir   = "$inputdir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $win_check_html = "$tmpdir/win_check.html";
my $tmp_hypdir     = "$tmpdir/HYPERV";
my @tmphypdir_dirs = "";

opendir my $tmphypdirDH, $tmp_hypdir || Xorux_lib::error( "Cannot open $tmp_hypdir " . __FILE__ . ":" . __LINE__ ) && exit 1;
@tmphypdir_dirs = grep { -d "$tmp_hypdir/$_" && !/^..?$/ } readdir($tmphypdirDH);
close $tmphypdirDH;

#print "@tmphypdir_dirs\n";
#print "$tmpdir\n";

open( WCH, "> $win_check_html" ) || Xorux_lib::error( "Cannot open $win_check_html " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $header = "<center><h4>List of Windows agents</h4></center>
<table><tr><td><center><table class =\"tabconfig tablesorter\">
<thead><tr>
<th class = \"sortable\">Instance&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
<th class = \"sortable\">UUID&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
<th class = \"sortable\">Domain&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
<th class = \"sortable\">Agent version&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
<th class = \"sortable\">Last update&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
<th class = \"sortable\">Collects&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
</tr></thead><tbody>";

print WCH "$header\n";

foreach my $hyp_uuid (@tmphypdir_dirs) {
  my @txt_files       = ();
  my $one_txt_file    = "";                        # take only one file for one UUID, if there is more, take the last one
  my $hyp_uuid_dir    = "$tmp_hypdir/$hyp_uuid";
  my $l_counter       = 0;
  my $l_uuid_counter  = 0;
  my $first_ver_line  = 0;
  my $hostname_line_i = 0;
  my $comp_line_i     = 0;

  my %ag_instances;
  my $ag_hostname = "";
  my $ag_domain   = "";
  my $ag_uuid     = "";
  my $ag_version  = "";
  my $last_update = "none";
  my $ag_collect  = "";

  opendir my $hyp_uuidDH, $hyp_uuid_dir || Xorux_lib::error( "Cannot open $hyp_uuid_dir " . __FILE__ . ":" . __LINE__ ) && next;
  @txt_files = grep /\d{10}.txt$/, ( grep !/^\.\.?$/, readdir($hyp_uuidDH) );
  close $hyp_uuidDH;

  @txt_files = sort { $a cmp $b } @txt_files;

  #print "start @txt_files\n";
  if (@txt_files) {
    $one_txt_file = $txt_files[-1];
    $one_txt_file = "$hyp_uuid_dir/$one_txt_file";

    #print "$one_txt_file\n";
    if ( -M $one_txt_file <= 30 ) {

      #print "OK\n";
      #print "$hyp_uuid\n";
      # first while for checking uuid of agent source
      open my $txtFH, '<', $one_txt_file || Xorux_lib::error( "Cannot open file $one_txt_file " . __FILE__ . ":" . __LINE__ );
      while ( my $line = <$txtFH> ) {
        $l_uuid_counter++;
        if ( $line =~ m/$hyp_uuid/ ) {
          my $ag_uuid_l = $line;
          $hostname_line_i = $l_uuid_counter - 6;
          chomp $ag_uuid_l;

          #print "$ag_uuid_l\n";
          ( $ag_uuid, undef ) = split( ',', $ag_uuid_l );
          $ag_uuid =~ s/"//g;

          #print "$ag_uuid\n";
        }
      }
      close $txtFH;
      open $txtFH, '<', $one_txt_file || Xorux_lib::error( "Cannot open file $one_txt_file " . __FILE__ . ":" . __LINE__ );
      while ( my $line = <$txtFH> ) {
        $l_counter++;

        # timestamp of file
        my $file_ts = ( stat("$one_txt_file") )[9];
        my ( $sec_e, $min_e, $hour_e, $day_e, $month_e, $year_e, $wday_e, $yday_e, $isdst_e ) = localtime($file_ts);
        $last_update = sprintf( "%4d-%02d-%02d %02d:%02d", $year_e + 1900, $month_e + 1, $day_e, $hour_e, $min_e );

        if ( ( $line =~ m/version .+ Unix/ ) && !($first_ver_line) ) {
          $first_ver_line = 1;
          my $ver_line = $line;
          ( undef, undef, undef, undef, $ag_version, undef ) = split( / /, $ver_line );

          #print "$ag_version\n";
        }

        # computersystems from agent
        if ( $line =~ m/CLASS: Win32_ComputerSystem$/ ) {
          $comp_line_i = $l_counter + 2;
        }    # end if ( $line =~ m/CLASS: Win32_ComputerSystem$/ )
        if ( $l_counter == $comp_line_i ) {
          my $comp_line = $line;

          #print "$comp_line\n";
          ( my $hostname, undef, undef, undef, undef, my $domain ) = split( ',', $comp_line );    # get name and domain from line
          $hostname =~ s/"//g;
          $domain   =~ s/"//g;
          $ag_instances{$hostname} = $domain;

          #print "$ag_instance,$ag_version\n";
          #print WCH "<tr><td>$ag_info[0]</td><td></td><td></td><td>$ag_version</td><td>$last_update</td></tr>\n";
        }    # end if ( $l_counter = $comp_line_num )
        if ( $l_counter == $hostname_line_i ) {

          #print "$line\n";
          my $hostname_line = $line;
          ( $ag_hostname, undef ) = split( ',', $hostname_line );
          $ag_hostname =~ s/"//g;

          #print "$ag_hostname\n";
        }
      }    # end while (my $line = <$txtFH>)
      close $txtFH;
      if ( exists $ag_instances{$ag_hostname} ) {
        $ag_domain = $ag_instances{$ag_hostname};
      }
      foreach my $key ( keys %ag_instances ) {
        $ag_collect = join( ",", keys %ag_instances );
      }
      print WCH "<tr>
      <td><b>$ag_hostname</b></td>
      <td>$ag_uuid</td>
      <td>$ag_domain</td>
      <td>$ag_version</td>
      <td>$last_update</td>
      <td>$ag_collect</td></tr>\n";
    }    # end if ( -M $one_txt_file <= 30 )
    else {
      #print "File $one_txt_file older than 30 days\n";
    }
  }    # end if ( @txt_files )
  else {
    print "No perfiles\n";
  }
}    # foreach my $hyp_uuid (@tmphypdir_dirs)
print WCH "</tbody></table></center>";
print WCH "Agent data not updated more than 30 days are ignored.<br>\n";
close(WCH);
