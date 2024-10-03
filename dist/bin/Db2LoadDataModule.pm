package Db2LoadDataModule;

use strict;
use warnings;

use RRDp;
use Xorux_lib;
use Data::Dumper;
use Db2DataWrapper;

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
my %raw_metrics = %{ Db2DataWrapper::get_raw_metrics() };
sub touch {
  my $text       = shift;
  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-db2";
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
  'data' =>[
    'AGENTS_TOP',
    'NUM_POOLED_AGENTS',
    'NUM_ASSOC_AGENTS',
    'NUM_COORD_AGENTS',
    'NUM_LOCKS_HELD',
    'NUM_LOCKS_WAITING',
    'LOCK_ESCALS',
    'LOCK_TIMEOUTS',
    'DEADLOCKS',
    'LOGICAL_READS',
    'PHYSICAL_READS',
    'WRITES',
    'DIRECT_READS',
    'DIRECT_WRITES',
    'DIRECT_READ_TIME',
    'DIRECT_WRITE_TIME',
    'POOL_READ_TIME',
    'POOL_WRITE_TIME',
    'ROWS_MODIFIED',
    'ROWS_RETURNED',
    'ROWS_READ',
    'ROWS_UPDATED',
    'ROWS_DELETED',
    'ROWS_INSERTED',
    'INT_ROWS_DELETED',
    'INT_ROWS_INSERTED',
    'INT_ROWS_UPDATED',
    'FED_ROWS_RETURNED',
    'FED_ROWS_READ',
    'FED_ROWS_UPDATED',
    'FED_ROWS_DELETED',
    'FED_ROWS_INSERTED',
    'TCPIP_SEND_VOLUME',
    'TCPIP_RECV_VOLUME',
    'IPC_SEND_VOLUME',
    'IPC_RECV_VOLUME',
    'FCM_SEND_VOLUME',
    'FCM_RECV_VOLUME',
    'PKG_CACHE_INSERTS',
    'PKG_CACHE_LOOKUPS',
    'TOTAL_APP_COMMITS',
    'TOTAL_APP_ROLLBACKS',
    'LOG_DISK_WAIT_TIME',
    'TCPIP_SEND_WAIT_TIME',
    'TCPIP_RECV_WAIT_TIME',
    'IPC_SEND_WAIT_TIME',
    'IPC_RECV_WAIT_TIME',
    'FCM_SEND_WAIT_TIME',
    'FCM_RECV_WAIT_TIME',
    'CF_WAIT_TIME',
    'CLIENT_IDLE_WAIT_TIME',
    'LOCK_WAIT_TIME',
    'AGENT_WAIT_TIME',
    'WLM_QUEUE_TIME_TOTAL',
    'RATINLOG',
    'RATIOCACHE',
    'RATIOBUFFER',
    'RATIOCPUT',
    'CONNECTIONS_TOP',
    'TOTAL_CONS',
    'TOTAL_SEC_CONS',
    'APPLS_CUR_CONS',
    'AGENTS_REGISTERED',
    'IDLE_AGENTS',
    'AGENTS_STOLEN',
  ]
  );

  return \%metrics;
}
sub get_metrics_rrd {
  my %met_rrd = (
  'data' =>[
    'AGENTSTOP',
    'ASSOCAGNT',
    'POOLEDAGNT',
    'COORDAGNT',
    'LCKSHELD',
    'LCKSWAITING',
    'LCKESCALS',
    'LCKTMOUTS',
    'DEADLOCKS',
    'LOGICALRD',
    'PHYSICALRD',
    'WRITES',
    'DIRECTRDS',
    'DIRECTWRTS',
    'DIRECTRDT',
    'DIRECTWRT',
    'POOLREADT',
    'POOLWRITETM',
    'ROWMODIFIED',
    'ROWRETURNED',
    'ROWREAD',
    'ROWUPDATED',
    'ROWDELETED',
    'ROWINSERTED',
    'INTRDELETED',
    'INTRINSERT',
    'INTRUPDATED',
    'FEDRRETURN',
    'FEDRREAD',
    'FEDRUPDAT',
    'FEDRDELET',
    'FEDRINSERT',
    'TCPIPSENDVL',
    'TCPIPRECVVL',
    'IPCSENDVOL',
    'IPCRECVVOL',
    'FCMSENDVOL',
    'FCMRECVVOL',
    'PKGINSERTS',
    'PKGLOOKUPS',
    'COMMITS',
    'ROLLBACKS',
    'LOGDISKWT',
    'TCPIPSENDWT',
    'TCPIPRECVWT',
    'IPCSENDWT',
    'IPCRECVWT',
    'FCMSENDWT',
    'FCMRECVWT',
    'CFWAITTIME',
    'CLIENTIDLWT',
    'LOCKWT',
    'AGENTWT',
    'WLMQUEUET',
    'RATINLOG',
    'RATIOCACHE',
    'RATIOBUFFER',
    'RATIOCPUT',
    'CONNSTOP',
    'TOTALCONS',
    'TSECCONS',
    'CURCONS',
    'AGENTSREGT',
    'IDLEAGENTS',
    'AGENTSSTLN',
  ]
  );

  return \%met_rrd;
}


1;
