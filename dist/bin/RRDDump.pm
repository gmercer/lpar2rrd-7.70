package RRDDump;

use strict;
use warnings;

use Data::Dumper;
use Xorux_lib;
use RRDp;
use Scalar::Util qw(looks_like_number);

my $rrdtool = $ENV{RRDTOOL}  || Xorux_lib::error( "Not defined RRDTOOL! Cannot continue...: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
my $basedir = $ENV{INPUTDIR} || Xorux_lib::error("INPUTDIR is not defined")                                                   && exit 0;
my $wrkdir  = "$basedir/data";

sub new {
  my ( $self, $rrd ) = @_;

  if ( !-f $rrd ) {
    Xorux_lib::error( "RRD file does not exist! \"$rrd\": $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
  }

  my $o = {};
  $o->{rrd} = $rrd;

  bless $o;
  return $o;
}

sub export_metric {
  my ( $self, $metric ) = @_;

  if ( !defined $metric ) {
    Xorux_lib::error( "Not defined Metric! Cannot continue...: $!" . __FILE__ . ":" . __LINE__ ) && return ();
  }

  $self->{metric} = $metric;

  RRDp::start "$rrdtool";

  my %data;

  my ( $sunix, $eunix ) = $self->set_timerange( $self->{rrd} );
  if ( !defined $sunix || !defined $eunix ) { RRDp::end; return (); }
  my $cmd = $self->set_cmd( $sunix, $eunix, $self->{rrd}, $metric );

  $self->test_metric( $self->{rrd}, $metric );
  $self->xport_metric( $cmd, 1 );

  RRDp::end;

  return @{ $self->{data} };
}

sub get_metric {
  my ( $self, $metric ) = @_;

  if ( !defined $metric ) {
    Xorux_lib::error( "Not defined Metric! Cannot continue...: $!" . __FILE__ . ":" . __LINE__ ) && return ();
  }

  $self->{metric} = $metric;

  RRDp::start "$rrdtool";

  my %data;

  my ( $sunix, $eunix ) = $self->set_timerange( $self->{rrd} );
  if ( !defined $sunix || !defined $eunix ) { RRDp::end; return (); }
  my $cmd = $self->set_cmd( $sunix, $eunix, $self->{rrd}, $metric );
  $self->test_metric( $self->{rrd}, $metric );
  $self->xport_metric($cmd);

  RRDp::end;
  if ( !defined $self->{data} || ref( $self->{data} ) ne "ARRAY" ) {
    return ();
  }

  return @{ $self->{data} };

}

sub get_average_by_interval {
  my ( $self, $metric, $interval ) = @_;

  if ( !defined $metric || !defined $interval ) {
    Xorux_lib::error( "Not defined Metric or Interval! Cannot continue...: $!" . __FILE__ . ":" . __LINE__ ) && return ();
  }

  RRDp::start "$rrdtool";

  my $cmd;
  $cmd .= "graph dummy --start=end-" . $interval . "d --end=now ";
  $cmd .= "DEF:x=" . $self->{rrd} . ":" . $metric . ":AVERAGE ";
  $cmd .= "VDEF:xa=x,AVERAGE PRINT:xa:%lf";

  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error( "sum detail: Multi graph rrdtool error : $$ret  " . __FILE__ . ":" . __LINE__ ) && return 0;
  }

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  RRDp::end;

  return $rrd_result[1];

}

sub xport_metric {
  my ( $self, $cmd, $debug ) = @_;

  #print "xport start: ".localtime()."\n";

  my $last;

  my $timeout = 300;
  my $ret     = "";

  eval {
    local $SIG{ALRM} = sub { die "rrdtool info died in SIG ALRM: "; };
    alarm($timeout);

    $cmd =~ s/\\"/"/g;

    RRDp::cmd qq($cmd);
    $ret = RRDp::read;
    if ( $$ret =~ "ERROR" ) {
      error( "sum detail: Multi graph rrdtool error : $$ret  " . __FILE__ . ":" . __LINE__ ) && return 0;
    }
  };

  #print "xport end: ".localtime()."\n";

  my @rrd_result;
  if ( $ret =~ /0x/ ) {
    @rrd_result = split( '\n', $$ret );
  }
  else {
    @rrd_result = split( '\n', $ret );
  }

  foreach my $row (@rrd_result) {
    chomp $row;
    $row =~ s/^\s+//g;
    $row =~ s/\s+$//g;
    if ( $row =~ "^<row><t>" ) {
      my ( $timestamp, $value ) = split( "</t><v>", $row );
      $timestamp =~ s/<row><t>//g;
      $value     =~ s/<\/v><\/row>//g;

      #if ( $value !~ /nan/i ) {
      #  $value = sprintf '%.9g', $value;
      #  $value = sprintf '%.3f', $value;
      #}
      if ( !looks_like_number($value) || $value eq "NaN" || $value =~ /nan/i ) {
        if ( !defined $last ) {
          next;
        }
        else {
          $value = $last;
        }
      }
      else {
        $value = sprintf '%.9g', $value;
        $value = sprintf '%.3f', $value;
      }
      if ( defined $debug && $debug == 1 ) {
        push( @{ $self->{data} }, "$timestamp => $value" );
      }
      else {
        push( @{ $self->{data} }, $value );
      }
      $last = $value;
    }
  }

  return 1;
}

sub set_cmd {
  my $self   = shift;
  my $sunix  = shift;
  my $eunix  = shift;
  my $rrd    = shift;
  my $metric = shift;

  my $max_rows = 170000;
  my $xport    = "xport";
  my $STEP     = 86400;

  #my $STEP    = 60;
  my $val = 1;    # this can be used to convert values e.g.: from kB to MB -> value/1024

  my $cmd;

  $cmd .= "$xport";

  if ( -f "$wrkdir/../tmp/rrdtool-xport-showtime" ) {

    # RRDTOOL: suported since 1.6, without that does not print timestamp like older 1.4 (1.5 does not support it)
    $cmd .= " --showtime";
  }

  $cmd .= " --start \\\"$sunix\\\"";
  $cmd .= " --end \\\"$eunix\\\"";
  $cmd .= " --step \\\"$STEP\\\"";
  $cmd .= " --maxrows \\\"$max_rows\\\"";
  $cmd .= " DEF:$metric=\\\"$rrd\\\":$metric:AVERAGE";
  $cmd .= " CDEF:result=$metric,$val,/";
  $cmd .= " XPORT:result:$metric";

  #print "$cmd\n";

  return $cmd;
}

sub set_timerange {
  my $self = shift;
  my $rrd  = shift;

  my $act_timestamp = time();

  my $timeout = 300;
  my $ret     = "";

  eval {
    local $SIG{ALRM} = sub { die "rrdtool info died in SIG ALRM: "; };
    alarm($timeout);

    RRDp::cmd qq(last "$rrd");
    $ret = RRDp::read;
    chomp($$ret);

    if ( $$ret =~ "ERROR" ) {
      error( "RRDp ERROR: $$ret  " . __FILE__ . ":" . __LINE__ ) && return;
    }
  };

  my $last_upd = localtime($$ret);

  #print "$last_upd : $$ret\n";

  #if ( $act_timestamp - $$ret > 3600 * 24) {
  #  Xorux_lib::error( "RRD file has not been updated longer than one day! \"$rrd\" last upd time $last_upd: $!" . __FILE__ . ":" . __LINE__ ) && return;
  #}

  my $eunix = $$ret;
  my $sunix = $$ret - 31536000;    # start time is 365 days back
                                   #my $sunix = $$ret - (60*60*24*60); # 60 days

  #print "RRDtool xport start time: ".localtime($sunix)." : $sunix\n";
  #print "RRDtool xport end time  : ".localtime($eunix)." : $eunix\n";

  return ( $sunix, $eunix );
}

sub test_metric {
  my $self   = shift;
  my $rrd    = shift;
  my $metric = shift;

  my $timeout = 300;
  my $ret     = "";

  eval {
    local $SIG{ALRM} = sub { die "rrdtool info died in SIG ALRM: "; };
    alarm($timeout);

    RRDp::cmd qq(info "$rrd");
    $ret = RRDp::read;

    if ( $$ret =~ "ERROR" ) {
      error( "RRDp ERROR: $$ret  " . __FILE__ . ":" . __LINE__ ) && exit 0;
    }
  };

  my @output;
  if ( $ret =~ /0x/ ) {
    @output = split( /\n/, $$ret );
  }
  else {
    @output = split( /\n/, $ret );
  }

  if ( scalar( grep {/ds\[$metric\]/} @output ) == 0 ) {
    Xorux_lib::error( "$metric does not exist in $rrd: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
  }

  return 1;
}

1;
