package SQLServerLoadDataModule;

use strict;
use warnings;

use RRDp;
use Xorux_lib;
use Data::Dumper;

my $rrdtool = $ENV{RRDTOOL};

my $step    = 60;
my $no_time = $step * 18;

my $one_minute_sample = 86400;
my $five_mins_sample  = 25920;
my $one_hour_sample   = 4320;
my $five_hours_sample = 1734;
my $one_day_sample    = 1080;

my %metrics = %{ get_metrics() };
my %met_rrd = %{ get_metrics_rrd() };

sub touch {
  my $text       = shift;
  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-sqlserver";
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
################################################################################

sub create_rrd {
  my $filepath = shift;
  my $time     = ( shift @_ ) - 3600;
  my $type     = shift;
  my $cmd      = qq(create "$filepath" --start "$time" --step "$step"\n);
  my $samples  = "$five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample";

  touch("create_rrd $type $filepath");

  print Dumper \@{ $met_rrd{$type} };
  foreach my $metric ( @{ $met_rrd{$type} } ) {
    $cmd .= qq("DS:$metric:GAUGE:$no_time:0:U"\n);
  }

  print "Creating RRD      : $filepath\n";
  $cmd .= qq(
               "RRA:AVERAGE:0.5:5:$five_mins_sample"
               "RRA:AVERAGE:0.5:60:$one_hour_sample"
               "RRA:AVERAGE:0.5:300:$five_hours_sample"
               "RRA:AVERAGE:0.5:1440:$one_day_sample"
              );

  if ( defined $cmd ) {
    RRDp::cmd $cmd;

    #warn localtime()."$type   $filepath  $time";
    if ( !Xorux_lib::create_check("file: $filepath, $samples") ) {
      warn("Unable to create $filepath : at ");
      RRDp::end;
      RRDp::start "$rrdtool";
      return 0;
    }
  }

  return 1;
}

sub update_rrd {
  my $rrd           = shift;
  my $act_time      = shift;
  my $type          = shift;
  my $hah           = shift;
  my $alias         = shift;
  my %hash          = %{$hah};
  my $last_rec      = '';
  my $update_string = "$act_time:";

  foreach my $item ( @{ $metrics{$type} } ) {
    my $value;

    if ( $hash{$item} ) {
      $hash{$item} =~ s/,/./g;
      if ( $hash{$item} =~ /^\./ ) {
        $hash{$item} = "0" . "$hash{$item}";
      }
    }

    if ( !defined $hash{$item} || $hash{$item} eq '' ) {    #|| ! isdigit( $hash{$item} )
      $value = 'U';
    }
    else {
      $value = $hash{$item};
    }
    $update_string .= "$value:";
  }
  $update_string = substr( $update_string, 0, -1 );
  print "\n$update_string\n";

  my $lastupdate = Xorux_lib::rrd_last_update($rrd);
  if ( $$lastupdate >= $act_time ) {
    my $readable_lastupdate = localtime($$lastupdate);
    my $readable_time       = localtime($act_time);
    warn "Cant update rrd. Last data update time $readable_lastupdate ($$lastupdate) for $type is greater than actual time $readable_time ($act_time).  $rrd";
    return 0;
  }

  RRDp::cmd qq(update "$rrd" $update_string);
  eval { my $answer = RRDp::read; };

  if ($@) {
    warn("Failed during read last time $rrd: $@ ");
    return 0;
  }
  return 1;
}


sub get_metrics {
  my %metrics = (
    'virtual' => [
      "io_rd",
      "io_wr",
      "data_wr",
      "latency_total",
      "latency_wr",
      "data_rd",
      "data_total",
      "latency_rd",
      "io_total"
    ],
    'counters' => [
      'Background writer pages/sec',
      'Checkpoint pages/sec',
      'Page life expectancy',
      'Lazy writes/sec',
      'Page reads/sec',
      'Page writes/sec',
      'Readahead pages/sec',
      'Readahead time/sec',
      'Database pages',
      'Extension allocated pages',
      'Extension free pages',
      'Target pages',
      'User Connections',
      'Connection Reset/sec',
      'Logins/sec',
      'Logouts/sec',
      'Active cursors',
      'Cursor Requests/sec',
      'Cached Cursors Counts',
      'Transactions',
      'Write Transactions/sec',
      'Locks Requests/sec',
      'Locks Waits/sec',
      'Number of Deadlocks/sec',
      'Lock Timeouts/sec',
      'Buffer cache hit ratio',
      "Cache Hit Ratio",
      "Active Transactions",
      "Tracked transactions/sec",
      "Transactions/sec",
      "Log Cache Hit Ratio",
      "Free Memory (KB)",
      "Reserved Server Memory (KB)",
      "Target Server Memory (KB)",
      "Total Server Memory (KB)"
    ],
    'wait_events' => [
      "PAGEIOLATCH_DT",
      "PAGEIOLATCH_EX",
      "PAGEIOLATCH_KP",
      "PAGEIOLATCH_NL",
      "PAGEIOLATCH_SH",
      "PAGEIOLATCH_UP",
      "PAGELATCH_DT",
      "PAGELATCH_EX",
      "PAGELATCH_KP",
      "PAGELATCH_NL",
      "PAGELATCH_SH",
      "PAGELATCH_UP",
      "LATCH_DT",
      "LATCH_EX",
      "LATCH_KP",
      "LATCH_NL",
      "LATCH_SH",
      "LATCH_UP",
      'LCK_M_BU',
      'LCK_M_IS',
      'LCK_M_IU',
      'LCK_M_IX',
      'LCK_M_RIn_NL',
      'LCK_M_RIn_S',
      'LCK_M_RIn_U',
      'LCK_M_RIn_X',
      'LCK_M_RS_S',
      'LCK_M_RS_U',
      'LCK_M_RX_S',
      'LCK_M_RX_U',
      'LCK_M_RX_X',
      'LCK_M_S',
      'LCK_M_SCH_M',
      'LCK_M_SCH_S',
      'LCK_M_SIU',
      'LCK_M_SIX',
      'LCK_M_U',
      'LCK_M_UIX',
      'LCK_M_X',
      'RS_SM_QUERY_CMPL',
      'SOS_SCHEDULER_YIELD',
      'ASYNC_NETWORK_IO',
      'MSQL_XP',
      'EXECSYNC',
      'WRITE_COMPLETION',
      'IO_COMPLETION',
      'CXPACKET',
      'WRITELOG',
      'THREADPOOL'

    ],
    'capacity' => [
      "available",
      "log_space",
      "unused",
      "used",
    ]

  );

  return \%metrics;
}

sub get_metrics_rrd {
  my %met_rrd = (
    'virtual' => [
      "io_rd",
      "io_wr",
      "data_wr",
      "ltnc_t",
      "ltnc_wr",
      "data_rd",
      "data_t",
      "ltnc_rd",
      "io_t"
    ],
    'counters' => [
      'BGdwrpgPS',
      'ChckptpgPS',
      'Pagelexpect',
      'LazywrPS',
      'PagerdPS',
      'PagewrPS',
      'RdahdpagePS',
      'RdahdtimePS',
      'Dbpages',
      'Extnallocpg',
      'Extnfreepg',
      'Targetpages',
      'UsrCons',
      'ConresetsPS',
      'LoginsPS',
      'LogoutsPS',
      'Activecrsrs',
      'CrsrRqstsPS',
      'CchdCrsrCnt',
      'Txns',
      'WTxnsPS',
      'LockRqstsPS',
      'LockWaitsPS',
      'DeadlocksPS',
      'LockTmtsPS',
      'Bfrcachehit',
      "CacheHitRat",
      "ActiveTxn",
      "Trackedtxn",
      "Transaction",
      "LogCacheHit",
      'FreeMemory',
      'ReservedMemory',
      'TargetMemory',
      'TotalMemory'
    ],
    'wait_events' => [
      "pageiodt",
      "pageioex",
      "pageiokp",
      "pageionl",
      "pageiosh",
      "pageioup",
      "pagedt",
      "pageex",
      "pagekp",
      "pagenl",
      "pagesh",
      "pageup",
      "latchdt",
      "latchex",
      "latchkp",
      "latchnl",
      "latchsh",
      "latchup",
      'LCKMBU',
      'LCKMIS',
      'LCKMIU',
      'LCKMIX',
      'LCKMRInNL',
      'LCKMRInS',
      'LCKMRInU',
      'LCKMRInX',
      'LCKMRSS',
      'LCKMRSU',
      'LCKMRXS',
      'LCKMRXU',
      'LCKMRXX',
      'LCKMS',
      'LCKMSCHM',
      'LCKMSCHS',
      'LCKMSIU',
      'LCKMSIX',
      'LCKMU',
      'LCKMUIX',
      'LCKMX',
      'RSSMQUER',
      'SOSSCHED',
      'ASYNCNET',
      'MSQLXP',
      'EXECSYNC',
      'WRITECOM',
      'IOCOMPLE',
      'CXPACKET',
      'WRITELOG',
      'THREADPL'
    ],
    'capacity' => [
      "available",
      "log_space",
      "unused",
      "used",
    ]

  );

  return \%met_rrd;
}



1;
