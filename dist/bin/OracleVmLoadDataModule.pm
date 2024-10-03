# OracleVmLoadDataModule.pm
# create/update RRDs with OracleVm

package OracleVmLoadDataModule;

use strict;

use Date::Parse;
use RRDp;
use File::Copy;
use Xorux_lib;
use Math::BigInt;
use Data::Dumper;
use File::Copy qw(copy);

my $rrdtool = $ENV{RRDTOOL};

my $step            = 60;
my $no_time         = $step * 7;
my $no_time_storage = $step * 180;

my $one_minute_sample = 86400;
my $five_mins_sample  = 25920;
my $one_hour_sample   = 4320;
my $five_hours_sample = 1734;
my $one_day_sample    = 1080;

my %metrics = (
  server      => [ 'CPU_UTILIZATION', 'CPU_COUNT', 'CORES_COUNT', 'MEMORY_USED', 'MEMORY_UTILIZATION', 'FREE_MEMORY', 'FREE_SWAP' ],
  server_net  => [ 'NETWORK_SENT',    'NETWORK_RECEIVED' ],
  server_disk => [ 'DISK_READ',       'DISK_WRITE' ],
  vm          => [ 'CPU_UTILIZATION', 'CPU_COUNT', 'MEMORY_USED' ],
  vm_disk     => [ 'DISK_READ',       'DISK_WRITE' ],
  vm_net      => [ 'NETWORK_SENT',    'NETWORK_RECEIVED' ],
);

################################################################################

sub rrd_last_update {
  my $filepath    = shift;
  my $last_update = -1;

  #RRDp::start "$rrdtool";
  RRDp::cmd qq(last "$filepath");
  eval { $last_update = RRDp::read; };

  #RRDp::end;

  if ($@) {
    Xorux_lib::error( "Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
  }
  my $last_update_rrd = $$last_update;
  return $last_update_rrd;
}

sub touch {
  my $text       = shift;
  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-oraclevm";
  my $DEBUG      = $ENV{DEBUG};

  if ( !-f $new_change ) {
    `touch $new_change`;    # tell install_html.sh that there has been a change
    if ( $text eq '' ) {
      print "touch             : $new_change\n" if $DEBUG;
    }
    else {
      print "touch             : $new_change : $text\n" if $DEBUG;
    }
  }

  return 0;
}

sub isdigit {
  my $digit      = shift;
  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  return 0;
}

##############################################################################

sub create_rrd {
  my $filepath = shift;
  my $time     = ( shift @_ ) - 3600;
  my $type     = shift;
  my $cmd      = qq(create "$filepath" --start "$time" --step "$step"\n);
  my $samples  = "$one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample";

  #print "|$filepath|$time|$type|\n";
  if ( $filepath eq "" ) { next; }
  touch("create_rrd $type $filepath");
  foreach my $metric ( @{ $metrics{$type} } ) {
    if ( $type eq 'server' ) {
      $cmd .= qq("DS:$metric:GAUGE:$no_time:0:U"\n);
    }
    elsif ( $type eq 'server_net' ) {
      $cmd .= qq("DS:$metric:GAUGE:$no_time:0:U"\n);
    }
    else {
      $cmd .= qq("DS:$metric:GAUGE:$no_time:0:U"\n);
    }
  }

  print "Creating RRD      : $filepath\n";

  if ( $type eq 'server' or $type eq 'server_net' ) {

    # storage domains have only hourly data
    $cmd .= qq(
               "RRA:AVERAGE:0.5:1:$one_minute_sample"
               "RRA:AVERAGE:0.5:5:$five_mins_sample"
               "RRA:AVERAGE:0.5:60:$one_hour_sample"
               "RRA:AVERAGE:0.5:300:$five_hours_sample"
               "RRA:AVERAGE:0.5:1440:$one_day_sample"
              );
  }
  else {
    $cmd .= qq(
               "RRA:AVERAGE:0.5:1:$one_minute_sample"
               "RRA:AVERAGE:0.5:5:$five_mins_sample"
               "RRA:AVERAGE:0.5:60:$one_hour_sample"
               "RRA:AVERAGE:0.5:300:$five_hours_sample"
               "RRA:AVERAGE:0.5:1440:$one_day_sample"
              );
  }

  if ( defined $cmd ) {

    #RRDp::start "$rrdtool";
    RRDp::cmd $cmd;
    if ( !Xorux_lib::create_check("file: $filepath, $samples") ) {
      Xorux_lib::error( "Unable to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
      RRDp::end;
      RRDp::start "$rrdtool";
      return 0;
    }
        #RRDp::end;
  }

  return 1;
}

sub update_rrd_vm {
  my $filepath = shift;
  my $data     = shift;
  my $conf     = shift;
  my $last_upd = 0;

  my $number_of_cores;
  my $memory_size;

  #my $memory_size = $conf->{memory_size_mb};

  #  print Dumper $conf;

  #if ( defined $conf->{number_of_sockets} && defined $conf->{cpu_per_socket} ) {
  #  $number_of_cores = $conf->{number_of_sockets} * $conf->{cpu_per_socket};
  #}

  print "Updating vm RRD      : $filepath\n";
  foreach my $row_ref ( keys %{$data} ) {
    my $timestamp = 0;
    my $timetest  = 0;
    my ( $cpu_in_perc, $cpu_count, $memory_used, $disk_read, $disk_write, $net_sent, $net_rec );
    foreach my $time ( sort keys %{ $data->{$row_ref} } ) {
      my @row = $data->{$row_ref}{$time};
      $timestamp = $time;
      $timestamp = $timestamp / 1000;
      $timestamp = sprintf( "%.0f", $timestamp );
      foreach my $item ( keys %{ $data->{$row_ref}{$time} } ) {
        if ( $item eq "CPU_UTILIZATION" ) {
          $cpu_in_perc = $data->{$row_ref}{$time}{$item};
        }
        if ( $item eq "CPU_COUNT" ) {
          $cpu_count = $data->{$row_ref}{$time}{$item};
        }
        if ( $item eq "MEMORY_USED" ) {
          $memory_used = $data->{$row_ref}{$time}{$item};
        }
      }
      if ( defined $timestamp && $last_upd < $timestamp ) {
        update_rrd( $filepath, $timestamp, $cpu_in_perc, $cpu_count, $memory_used );
        $last_upd = $timestamp;
      }
    }
    return 1;
  }

}    ## sub update_rrd_vm

sub update_rrd_vm_disk {
  my $filepath = shift;
  my $data     = shift;
  my $conf     = shift;
  my $last_upd = 0;

  #print Dumper $data;
  #print Dumper $conf;
  print "Updating vm disk RRD      : $filepath\n";
  my ( $disk_sent, $disk_rec );
  my $timestamp = 0;
  my $timetest  = 0;
  my $first_run = 0;
  my $last_value_sent;
  my $last_value_rec;

  foreach my $time ( sort keys %{ $data->{$conf} } ) {

    #if ($net_name ne $conf) {next;}
    my @values = @{ $data->{$conf}{$time} };
    $timestamp = $time;
    $timestamp = $timestamp / 1000;
    $timestamp = sprintf( "%.0f", $timestamp );
    $disk_sent = $values[0];
    $disk_rec  = $values[1];
    if ( $first_run == 0 ) {

      #print "FIRST_RUN: $filepath($time) = $conf,$first_run,$net_sent,$net_rec\n\n";
      $last_value_sent = $disk_sent;
      $last_value_rec  = $disk_rec;
      $first_run++;
      next;
    }
    else {
      #print "NEXT_RUN: $filepath($time) = $conf,$net_sent-$last_value_sent\n\n";
      $disk_sent = $disk_sent - $last_value_sent;
      $disk_rec  = $disk_rec - $last_value_rec;
    }

    #print "$filepath($time) = $conf,$first_run,$net_sent,$net_rec\n";
    if ( defined $timestamp && $last_upd < $timestamp ) {
      update_rrd( $filepath, $timestamp, $disk_sent, $disk_rec );
      $last_upd        = $timestamp;
      $last_value_sent = $values[0];
      $last_value_rec  = $values[1];
      $first_run++;
    }
  }
  return 1;
}

sub update_rrd_vm_net {
  my $filepath = shift;
  my $data     = shift;
  my $conf     = shift;
  my $last_upd = 0;

  print "Updating vm net RRD      : $filepath\n";
  my ( $net_sent, $net_rec );
  my $timestamp = 0;
  my $timetest  = 0;
  my $first_run = 0;
  my $last_value_sent;
  my $last_value_rec;
  $conf =~ s/===double-col===/:/g;

  foreach my $time ( sort keys %{ $data->{$conf} } ) {

    #if ($net_name ne $conf) {next;}
    my @values = @{ $data->{$conf}{$time} };
    $timestamp = $time;
    $timestamp = $timestamp / 1000;
    $timestamp = sprintf( "%.0f", $timestamp );
    $net_sent  = $values[0];
    $net_rec   = $values[1];
    if ( $first_run == 0 ) {

      #print "FIRST_RUN: $filepath($time) = $conf,$first_run,$net_sent,$net_rec\n\n";
      $last_value_sent = $net_sent;
      $last_value_rec  = $net_rec;
      $first_run++;
      next;
    }
    else {
      #print "NEXT_RUN: $filepath($time) = $conf,$net_sent-$last_value_sent\n\n";
      $net_sent = $net_sent - $last_value_sent;
      $net_rec  = $net_rec - $last_value_rec;
    }

    #print "$filepath($timestamp) = $conf,$first_run,$net_sent,$net_rec\n";
    if ( defined $timestamp && $last_upd < $timestamp ) {
      update_rrd( $filepath, $timestamp, $net_sent, $net_rec );
      $last_upd        = $timestamp;
      $last_value_sent = $values[0];
      $last_value_rec  = $values[1];
      $first_run++;
    }
  }
  return 1;

}

sub update_rrd_server {
  my $filepath = shift;
  my $data     = shift;
  my $conf     = shift;
  my $last_upd = 0;

  print "Updating server RRD      : $filepath\n";
  foreach my $row_ref ( keys %{$data} ) {

    #server => [ 'CPU_UTILIZATION','PER_CPU_UTILIZATION','MEMORY_USED','MEMORY_UTILIZATION','FREE_MEMORY','FREE_SWAP','DISK_READ','DISK_WRITE' ],
    my ( $cpu_util, $cores_count, $cpu_count, $mem_used, $mem_util, $mem_free, $free_swap );
    foreach my $time ( sort keys %{ $data->{$row_ref} } ) {
      my $timestamp = $time;
      $timestamp = $timestamp / 1000;
      $timestamp = sprintf( "%.0f", $timestamp );
      foreach my $item ( keys %{ $data->{$row_ref}{$time} } ) {

        #my $timestamp       = $time ;
        #$timestamp          = $timestamp / 1000;
        #$timestamp = sprintf( "%.0f", $timestamp );
        if ( $item eq "CPU_UTILIZATION" ) {
          $cpu_util = $data->{$row_ref}{$time}{$item};
        }
        if ( $item eq "COUNT_CORES" ) {    ### number of cores
          $cores_count = $data->{$row_ref}{$time}{$item};
        }
        if ( $item eq "COUNT_PROC" ) {     ### number of processor
          $cpu_count = $data->{$row_ref}{$time}{$item};
        }
        if ( $item eq "MEMORY_USED" ) {
          $mem_used = $data->{$row_ref}{$time}{$item};
        }
        if ( $item eq "MEMORY_UTILIZATION" ) {
          $mem_util = $data->{$row_ref}{$time}{$item};
        }
        if ( $item eq "FREE_MEMORY" ) {
          $mem_free = $data->{$row_ref}{$time}{$item};
        }
        if ( $item eq "FREE_SWAP" ) {
          $free_swap = $data->{$row_ref}{$time}{$item};
        }
      }

      #print "1)UPDATE:$filepath--$timestamp--$cpu_util,$cpu_count,$cores_count,$mem_used,$mem_util,$mem_free,$free_swap||||last-upd=$last_upd\n";
      if ( defined $timestamp && $last_upd < $timestamp ) {

        #print "2)UPDATE:$filepath--$timestamp--$cpu_util,$cpu_count,$cores_count,$mem_used,$mem_util,$mem_free,$free_swap|||||last-upd=$last_upd\n";
        update_rrd( $filepath, $timestamp, $cpu_util, $cpu_count, $cores_count, $mem_used, $mem_util, $mem_free, $free_swap );
        $last_upd = $timestamp;
      }
    }
  }
  return 1;
}

sub update_rrd_server_net {
  my $filepath = shift;
  my $data     = shift;
  my $conf     = shift;
  my $last_upd = 0;

  print "Updating server net RRD      : $filepath\n";
  my ( $net_sent, $net_rec );
  my $timestamp = 0;
  my $timetest  = 0;
  my $first_run = 0;
  my $last_value_sent;
  my $last_value_rec;
  foreach my $time ( sort keys %{ $data->{$conf} } ) {

    #if ($net_name ne $conf) {next;}
    my @values = @{ $data->{$conf}{$time} };
    $timestamp = $time;
    $timestamp = $timestamp / 1000;
    $timestamp = sprintf( "%.0f", $timestamp );
    $net_sent  = $values[0];
    $net_rec   = $values[1];
    if ( $first_run == 0 ) {

      #print "FIRST_RUN: $filepath($time) = $conf,$first_run,$net_sent,$net_rec\n\n";
      $last_value_sent = $net_sent;
      $last_value_rec  = $net_rec;
      $first_run++;
      next;
    }
    else {
      #print "NEXT_RUN: $filepath($time) = $conf,$net_sent-$last_value_sent\n\n";
      $net_sent = $net_sent - $last_value_sent;
      $net_rec  = $net_rec - $last_value_rec;
    }

    #print "$filepath($time) = $conf,$first_run,$net_sent,$net_rec\n";
    if ( defined $timestamp && $last_upd < $timestamp ) {
      update_rrd( $filepath, $timestamp, $net_sent, $net_rec );
      $last_upd        = $timestamp;
      $last_value_sent = $values[0];
      $last_value_rec  = $values[1];
      $first_run++;
    }
  }
  return 1;
}

sub update_rrd_server_disk {
  my $filepath = shift;
  my $data     = shift;
  my $conf     = shift;
  my $last_upd = 0;

  print "Updating server RRD      : $filepath\n";
  my ( $net_sent, $net_rec );
  my $timestamp = 0;
  my $timetest  = 0;
  my $first_run = 0;
  my $last_value_sent;
  my $last_value_rec;
  foreach my $time ( sort keys %{ $data->{$conf} } ) {

    #if ($net_name ne $conf) {next;}
    my @values = @{ $data->{$conf}{$time} };
    $timestamp = $time;
    $timestamp = $timestamp / 1000;
    $timestamp = sprintf( "%.0f", $timestamp );
    $net_sent  = $values[0];
    $net_rec   = $values[1];
    if ( $first_run == 0 ) {

      #print "FIRST_RUN: $filepath($time) = $conf,$first_run,$net_sent,$net_rec\n\n";
      $last_value_sent = $net_sent;
      $last_value_rec  = $net_rec;
      $first_run++;
      next;
    }
    else {
      #print "NEXT_RUN: $filepath($time) = $conf,$net_sent-$last_value_sent\n\n";
      $net_sent = $net_sent - $last_value_sent;
      $net_rec  = $net_rec - $last_value_rec;
    }

    #print "$filepath($time) = $conf,$first_run,$net_sent,$net_rec\n";
    if ( defined $timestamp && $last_upd < $timestamp ) {
      update_rrd( $filepath, $timestamp, $net_sent, $net_rec );
      $last_upd        = $timestamp;
      $last_value_sent = $values[0];
      $last_value_rec  = $values[1];
      $first_run++;
    }
  }
  return 1;
}
###############################################x

sub update_rrd {
  my $rrd           = shift;
  my @values        = @_;
  my $act_time      = $values[0];
  my $update_string = '';
  my $last_rec      = '';

  foreach my $value (@values) {
    if ( !defined $value || !isdigit($value) || $value eq '' ) {
      $value = 'U';
    }
  }

  $update_string = join ':', @values;
  my $last_update_file = rrd_last_update($rrd);
  chomp $last_update_file;
  if ( $last_update_file >= $act_time ) {
    return 0;
  }

  RRDp::cmd qq(update "$rrd" $update_string);

  eval { my $answer = RRDp::read; };

  if ($@) {
    Xorux_lib::error( "Failed during read last time $rrd: $@ " . __FILE__ . ":" . __LINE__ );
    return 0;
  }

  return 1;
}    ## update_rrd

1;
