use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);
use File::Copy;
use File::Temp qw/ tempfile/;

use HostCfg;
use OracleDBDataWrapper;

my $basedir    = $ENV{INPUTDIR} ||= "/home/lpar2rrd/lpar2rrd";
my $perl       = $ENV{PERL};
my $cfgdir     = "$basedir/etc/web_config";
my $realcfgdir = "$basedir/etc";
my $tmpdir     = "$basedir/tmp";
my $cfgbname   = "hosts";
my $cfgfile    = "$cfgdir/$cfgbname.json";
my $json       = JSON->new->utf8->pretty;
my %hosts;

my %oldd = HostCfg::getConfig();
my $oldcfg = \%oldd;

my $added_DBs   = "";
my $updated_DBs = "";
my $failed_DBs  = "";
my $errors      = "";

#my $csv = get_csv();

# get URL parameters (could be GET or POST) and put them into hash %PAR
my ( $buffer, @pairs, $pair, $name, $value, %PAR );

if ( defined $ENV{'CONTENT_TYPE'} && $ENV{'CONTENT_TYPE'} =~ "multipart/form-data" ) {
  print "Content-type: application/json\n\n";
  require CGI;
  my $cgi = new CGI;

  #warn Dumper $cgi;
  my $file = $cgi->param('csvfile');
  my $fh   = $cgi->upload('csvfile');
  if ($fh) {

    #    my $tmpfilename = $cgi->tmpFileName($file);
    #    warn "3 $tmpfilename";
    #    move("$tmpfilename", "$tmpdir/$file");
    #    #chmod 0664, "$tmpdir/$file";

    my $ret_checker   = 0;
    my $empty_checker = 1;
    foreach my $line (<$fh>) {
      my $ret = 0;

      if ( $line =~ m/^\s*$/ ) {
        next;
      }
      else {
        $ret = csvline2json($line);
      }
      if ( $ret ne "1" ) {
        $ret_checker ||= 1;
      }
      elsif ( $ret eq "1" ) {
        $empty_checker = 0;
      }
    }
    close($fh);
    if ( $ret_checker == 1 ) {
      &result( 0, $errors );
    }
    elsif ( $ret_checker == 30 ) {
      &result( 0, $errors );
    }
    elsif ( $empty_checker == 1 ) {
      &result( 0, "File is empty." );
    }
    else {
      json2hosts( \%hosts );
    }
  }
  else {
    warn "Couldn't open file: $file" && &result( 0, "Couldn't open file" );
  }
  exit;
}

if ( !defined $ENV{'REQUEST_METHOD'} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";
  exit;
}

if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
  read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
}
else {
  $buffer = $ENV{'QUERY_STRING'};
}

sub csvline2json {

  my $csv_line = shift;

  if ( $csv_line eq "" ) {
    warn "FILE IS EMPTY";
    return "EMPTY";
  }

  #my @csv_lines = split("\n", $csv);

  #print Dumper \@csv_lines;

  #  for my $i (0 .. 0){#$#csv_lines){
  #print "$csv_lines[$i]\n";
  #lpar2rrd alias;Service;Menu Group;subgroup;DB type;username;password;port;hosts(separated by",");pdb services(separated by",")
  my @sections = split( ';', $csv_line );
  if ( !$sections[0] or !$sections[1] ) {
    warn "This format is not supported: $csv_line\n";
    $errors .= "This format is not supported: $csv_line\n";
    return 0;
  }

  #warn Dumper(\@sections);

  my $alias = $sections[0];
  $alias =~ s/ /_/g;
  $alias =~ s/\\//g;
  $alias =~ s/\\//g;
  $alias =~ s/\///g;
  $alias =~ s/\://g;
  $alias =~ s/\$//g;

  if ( $alias and $alias ne "" ) {
    $hosts{$alias}{"instance"}      = $sections[1];
    $hosts{$alias}{"menu_group"}    = $sections[2];
    $hosts{$alias}{"menu_subgroup"} = $sections[3];
    $hosts{$alias}{"type"}          = $sections[4];
    $hosts{$alias}{"username"}      = $sections[5];
    $hosts{$alias}{"password"}      = HostCfg::obscure_password( $sections[6] );
    $hosts{$alias}{"port"}          = $sections[7];
    $hosts{$alias}{"uuid"}          = create_v4_uuid();
    $hosts{$alias}{"created"}       = timestamp( time, 1 );
    $hosts{$alias}{"updated"}       = timestamp(time);

    if ( $hosts{$alias}{"type"} and ( $hosts{$alias}{"type"} eq "Multitenant" or $hosts{$alias}{"type"} eq "RAC_Multitenant" ) ) {
      if ( $sections[9] ) {
        my @srvcs = split( ',', $sections[9] );
        push( @{ $hosts{$alias}{"services"} }, @srvcs );
      }
    }

    $sections[8] =~ s/ //g;
    my @hsts = split( ',', $sections[8] );
    $hosts{$alias}{"hosts"} = \@hsts;
    $hosts{$alias}{"host"}  = $hsts[0];

    #warn Dumper \@hsts;

    for my $key ( keys %{ $hosts{$alias} } ) {
      next if ( $key eq "menu_group" or $key eq "menu_subgroup" or $key eq "services" );
      if ( !$hosts{$alias}{$key} or $hosts{$alias}{$key} eq "" ) {
        delete( $hosts{$alias} );
        $failed_DBs = "  $alias\n";
        last;
      }
    }
  }

  #warn Dumper \$hosts{$alias};
  return 1;

  #  }
}

sub json2hosts {
  my $_hosts = shift;

  my $cfg_changed = 0;    # flag for missing added DBs

  if ( $oldcfg->{platforms}->{OracleDB}->{aliases} ) {
    for my $alias ( keys %{$_hosts} ) {

      if ( $oldcfg->{platforms}->{OracleDB}->{aliases}->{$alias} ) {
        $updated_DBs .= "  $alias\n";
      }
      else {
        $added_DBs .= "  $alias\n";
      }
      $oldcfg->{platforms}->{OracleDB}->{aliases}->{$alias} = $_hosts->{$alias};

      #}
      $cfg_changed ||= 1;
    }
  }

  if ($cfg_changed) {
    my ( $newcfg, $newcfgfilename ) = tempfile( UNLINK => 0 );
    my $pretty_json = $json->encode($oldcfg);
    $pretty_json =~ s/,\n\s*\}/\}/g;
    $pretty_json =~ s/,\n\s*\]/\]/g;
    print $newcfg $pretty_json;
    close $newcfg;
    my $json_c = eval { $json->decode($pretty_json) };
    if ($@){
      &result( 0, "Created file is corrupted, won't continue" );
    }else{
      copy( $cfgfile, "$realcfgdir/.web_config/$cfgbname.json.multiple_dbs.bak" );
      warn "Created backup of $cfgbname.json: '$basedir/etc/.web_config/$cfgbname.json-multiple_dbs.bak'";
      unlink $cfgfile;
      move( $newcfgfilename, $cfgfile );
      chmod 0644, $cfgfile;
      warn "Added multiple Oracle DBs, writing new $cfgbname file...";
      &result( 1, "Added DBs:\n$added_DBs \nUpdated DBs: \n$updated_DBs \nFailed DBs: \n$failed_DBs\n" );
    }
  }
}

sub timestamp {
  my $time = shift;
  my $prec = shift;
  my ( $sec, $min, $hour, $mday, $mon, $year ) = ( gmtime($time) );
  return gmtime2utc( $sec, $min, $hour, $mday, $mon, $year, $prec );
}

# transforms given gmtime to UTC #
sub gmtime2utc {
  my ( $sec, $min, $hour, $mday, $mon, $year, $precision ) = @_;
  $year += 1900;
  $mon  += 1;
  $mon  = sprintf( "%02d", $mon );
  $mday = sprintf( "%02d", $mday );
  $hour = sprintf( "%02d", $hour );
  $min  = sprintf( "%02d", $min );
  if ( defined $precision and $precision == 1 ) {
    return "$year-$mon-$mday" . "T" . "$hour:$min:$sec" . ".000Z";
  }
  else {
    return "$year-$mon-$mday" . "T" . "$hour:$min:$sec" . "Z";
  }
}

sub rand_32bit {
  my $v1 = int( rand(65536) ) % 65536;
  my $v2 = int( rand(65536) ) % 65536;
  return ( $v1 << 16 ) | $v2;
}

sub create_v4_uuid {
  my $uuid = '';
  for ( 1 .. 4 ) {
    $uuid .= pack 'I', rand_32bit();
  }
  substr $uuid, 6, 1, chr( ord( substr( $uuid, 6, 1 ) ) & 0x0f | 0x40 );
  return join '-',
    map { unpack 'H*', $_ }
    map { substr $uuid, 0, $_, '' } ( 4, 2, 2, 2, 6 );
}

sub result {
  my ( $status, $msg, $log ) = @_;
  $log ||= "";
  $msg =~ s/\n/\\n/g;
  $msg =~ s/\\:/\\\\:/g;
  $log =~ s/\n/\\n/g;
  $log =~ s/\\:/\\\\:/g;
  $status = ($status) ? "true" : "false";
  print "{ \"success\": $status, \"message\" : \"$msg\", \"log\": \"$log\"}";
}

