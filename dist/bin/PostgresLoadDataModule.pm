package PostgresLoadDataModule;

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
  my $new_change = "$basedir/tmp/$version-postgres";
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
    '_cluster' => [
      'checkpoints_req',
      'buffers_checkpoint',
      'buffers_clean',
      'checkpoints_timed',
      'buffers_backend'
    ],
    '_dbs' => [
      'xact_commit',
      'cursors',
      'xact_rollback',
      'blks_hit',
      'blks_read',
      'locks',
      'deadlocks',
      'tup_deleted',
      'commit_ratio',
      'cache_hit_ratio',
      'current_transactions',
      'tup_updated',
      'tup_returned',
      'tup_inserted',
      'tup_fetched',
      'temp_files',
      'temp_bytes'
    ],
    '_locks' => [
      'hrelation',
      'hextend',
      'hpage',
      'htuple',
      'hobject',
      'huserlock',
      'arelation',
      'aextend',
      'apage',
      'atuple',
      'aobject',
      'auserlock'
    ],
    '_sessions' => [
      'active',
      'idle',
      'idle_in_transaction',
      'idle_in_transaction_aborted',
      'fastpath_function_call',
      'disabled'
    ],
    '_wait_event' => [
      'LWLockNamed',
      'LWLockTranche',
      'Lock',
      'BufferPin'
    ],
    '_event' => [
      'ShmemIndexLock',
      'OidGenLock',
      'XidGenLock',
      'ProcArrayLock',
      'SInvalReadLock',
      'SInvalWriteLock',
      'WALBufMappingLock',
      'WALWriteLock',
      'ControlFileLock',
      'CheckpointLock',
      'CLogControlLock',
      'SubtransControlLock',
      'MultiXactGenLock',
      'MultiXactOffsetControlLock',
      'MultiXactMemberControlLock',
      'RelCacheInitLock',
      'CheckpointerCommLock',
      'TwoPhaseStateLock',
      'TablespaceCreateLock',
      'BtreeVacuumLock',
      'AddinShmemInitLock',
      'AutovacuumLock',
      'AutovacuumScheduleLock',
      'SyncScanLock',
      'RelationMappingLock',
      'AsyncCtlLock',
      'AsyncQueueLock',
      'SerializableXactHashLock',
      'SerializableFinishedListLock',
      'SerializablePredicateLockListLock',
      'OldSerXidLock',
      'SyncRepLock',
      'BackgroundWorkerLock',
      'DynamicSharedMemoryControlLock',
      'AutoFileLock',
      'ReplicationSlotAllocationLock',
      'ReplicationSlotControlLock',
      'CommitTsControlLock',
      'CommitTsLock',
      'ReplicationOriginLock',
      'MultiXactTruncationLock',
      'OldSnapshotTimeMapLock',
      'WrapLimitsVacuumLock',
      'NotifyQueueTailLock',
      'clog',
      'commit_timestamp',
      'subtrans',
      'multixact_offset',
      'multixact_member',
      'async',
      'oldserxid',
      'wal_insert',
      'buffer_content',
      'buffer_io',
      'replication_origin',
      'replication_slot_io',
      'proc',
      'buffer_mapping',
      'lock_manager',
      'predicate_lock_manager',
      'relation',
      'extend',
      'frozenid',
      'page',
      'tuple',
      'transactionid',
      'virtualxid',
      'speculative token',
      'object',
      'userlock',
      'advisory',
      'BufferPin'
    ],
    _vacuum => [
      'initializing',
      'scanning heap',
      'vacuuming indexes',
      'vacuuming heap',
      'cleaning up indexes',
      'runcating heap',
      'performing final cleanup'
    ]

  );
  return \%metrics;
}

sub get_metrics_rrd {
  my %met_rrd = (
    '_cluster' => [
      'chckpntsrq',
      'bfrschckpnt',
      'bfrscln',
      'chckpntstmd',
      'bfrsbcknd'
    ],
    '_dbs' => [
      'xctcmmt',
      'crsrs',
      'xctrlbck',
      'blksht',
      'blksrd',
      'lcks',
      'ddlcks',
      'tpdltd',
      'cmmtrt',
      'cchhtrt',
      'crrnttxn',
      'tpupdtd',
      'tpretrnd',
      'tpinsrtd',
      'tpftchd',
      'tmpfls',
      'tmpbts'
    ],
    '_locks' => [
      "hrltn",
      "hxtnd",
      "hpg",
      "htpl",
      "hbjct",
      "hsrlck",
      "arltn",
      "axtnd",
      "apg",
      "atpl",
      "abjct",
      "asrlck"
    ],
    '_sessions' => [
      'ctv',
      'dl',
      'dltxn',
      'dltxnbrtd',
      'fstpthfncll',
      'dsbld'
    ],
    '_wait_event' => [
      'lwlcknmd',
      'lwlcktrnch',
      'lck',
      'bffrpn'
    ],
    '_event' => [
      'ShmemIndex',
      'OidGen',
      'XidGen',
      'ProcArray',
      'SInvalRead',
      'SInvalWrit',
      'WALBufMapp',
      'WALWrite',
      'ControlFil',
      'Chckpont',
      'CLogContro',
      'SubtransCo',
      'Gen',
      'OffsetCont',
      'MemberCont',
      'RelCacheIn',
      'Checkpoint',
      'TwoPhaseSt',
      'Tablespace',
      'BtreeVacuu',
      'AddinShmem',
      'Autovacm',
      'Autovacuum',
      'SyncScan',
      'RelationMa',
      'AsyncCtl',
      'AsyncQueue',
      'XactHash',
      'FinishedLi',
      'PredicateL',
      'OldSerXid',
      'SyncRep',
      'Background',
      'DynamicSha',
      'AutoFile',
      'SlotAlloca',
      'SlotContro',
      'CommitTsCo',
      'CommitTs',
      'Origin',
      'Truncation',
      'OldSnapsho',
      'WrapLimits',
      'NotifyQueu',
      'clog',
      'committime',
      'subtrans',
      'multixacto',
      'multixactm',
      'async',
      'oldserxid',
      'walinsert',
      'buffercont',
      'bufferio',
      'origin',
      'slotio',
      'proc',
      'buffermapp',
      'lockmanage',
      'predicatel',
      'relation',
      'extend',
      'frozenid',
      'page',
      'tuple',
      'transactio',
      'virtualxid',
      'speculativ',
      'object',
      'userlock',
      'advisory',
      'BufferPinx'
    ],
    _vacuum => [
      'ntlzng',
      'scnhp',
      'vcmgndxs',
      'vcmghp',
      'clnndxs',
      'rnctghp',
      'fnlcln'
    ]

  );
  return \%met_rrd;
}

1;
