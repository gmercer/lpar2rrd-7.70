package PostgresDataWrapper;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json);
use Digest::MD5 qw(md5 md5_hex md5_base64);

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $home_dir = "$inputdir/data/PostgreSQL";
my $tmpdir   = "$inputdir/tmp";

my %pages = (
  "_dbs" => {
    "blocks" => {
      "blks_read" => "blksrd",
    },
    "tuples" => {
      "tup_deleted" => "tpdltd",
    },
    "temp" => {
      "temp_bytes" => "lcks",    #
    },
    "user" => {
      "current_transactions" => "crrnttxn",
    },
    "cursors" => {
      "current_cursors" => "lcks",
    },    #x
    "cache" => {
      "cache_hit_ratio" => "cchhtrt",
    },
    "deadlocks" => {
      "deadlocks" => "ddlcks",
    },
    "commit" => {
      "commit_ratio" => "cmmtrt",
    },
    "size" => {
      "commit_ratio" => "cmmtrt",
    },
  },
  "_cluster" => {
    "buffers" => {
      "buffers_backend" => "bfrsbcknd",
    },
    "checkpoints" => {
      "checkpoints_timed" => "chckpntstmd",
    },
    "autovacuum" => { "autovacuum" => "atvcm", },
  },
  "_locks" => {
    "held"    => { userlock => "hsrlck" },
    "awaited" => {
      relation => "arltn",
    }
  },
  "_sessions" => {
    "sessions" => {
      idle => "dl",
    }
  },
  "_wait_event" => {
    "we_type" => {
      idle => "dl",
    }
  },
  "_event" => {
    "LWLockNamed"   => { ads => "asd", },
    "LWLockTranche" => { ads => "asd", },
    "Lock"          => { ads => "asd", },
    "BufferPin"     => { ads => "asd", }
  },
  "_vacuum" => {
    "phase" => {
      idle => "dl",
    }
  }
);


sub get_pages {
  my %pages = (
    "Throughput" => {
      "blocks" => {
        "read" => "blksrd",
        "hit," => "blksht",
      },
      "tuples" => {
        "updated"  => "tpupdtd",
        "inserted" => "tpinsrtd",
        "deleted"  => "tpdltd",
        "returned" => "tpretrnd",
        "fetched"  => "tpftchd",
      },
      "temp" => {
        "temp_files" => "tmpfls",
        "temp_bytes" => "tmpbts",
      },
    },
    "Buffers" => {
      "buffers" => {
        "backend"    => "bfrsbcknd",
        "clean"      => "bfrscln",
        "checkpoint" => "bfrschckpnt",
      },
      "checkpoints" => {
        "requested" => "chckpntsrq",
        "scheduled" => "chckpntstmd",
      },
    },
    "Locks" => {
      "held" => {
        relation => "hrltn",
        extend   => "hxtnd",
        page     => "hpg",
        tuple    => "htpl",
        object   => "hbjct",
        userlock => "hsrlck"
      },
      "awaited" => {
        relation => "arltn",
        extend   => "axtnd",
        page     => "apg",
        tuple    => "atpl",
        object   => "abjct",
        userlock => "asrlck"
      },
      "deadlocks" => {
        "deadlocks" => "ddlcks",
      },
    },
    "configuration" => {
      "size" => { "size" => "lcks" },
    },
    "SQL_query" => {
      "user" => {
        "commits"   => "xctcmmt",
        "rollbacks" => "xctrlbck"
      },
      "cursors" => { "current_cursors" => "lcks" },    #x
    },
    "Ratio" => {
      "cache"  => { "cache_hit_ratio" => "cchhtrt" },
      "commit" => { "commit_ratio"    => "cmmtrt" },
    },
    "Sessions" => {
      "sessions" => {
        "active"                 => "ctv",
        "idle"                   => "dl",
        "idle in txn"            => "dltxn",
        "idle in txn aborted"    => "dltxnbrtd",
        "fastpath function call" => "fstpthfncll",
        "disabled"               => "dsbld"
      },
    },
    "Wait_event" => {
      we_type => {
        'LWLockNamed'   => 'lwlcknmd',
        'LWLockTranche' => 'lwlcktrnch',
        'Lock'          => 'lck',
        'BufferPin'     => 'bffrpn'
      },
      LWLockNamed => {
        ShmemIndexLock                    => 'ShmemIndex',
        OidGenLock                        => 'OidGen',
        XidGenLock                        => 'XidGen',
        ProcArrayLock                     => 'ProcArray',
        SInvalReadLock                    => 'SInvalRead',
        SInvalWriteLock                   => 'SInvalWrit',
        WALBufMappingLock                 => 'WALBufMapp',
        WALWriteLock                      => 'WALWrite',
        ControlFileLock                   => 'ControlFil',
        CheckpointLock                    => 'Chckpont',
        CLogControlLock                   => 'CLogContro',
        SubtransControlLock               => 'SubtransCo',
        MultiXactGenLock                  => 'Gen',
        MultiXactOffsetControlLock        => 'OffsetCont',
        MultiXactMemberControlLock        => 'MemberCont',
        RelCacheInitLock                  => 'RelCacheIn',
        CheckpointerCommLock              => 'Checkpoint',
        TwoPhaseStateLock                 => 'TwoPhaseSt',
        TablespaceCreateLock              => 'Tablespace',
        BtreeVacuumLock                   => 'BtreeVacuu',
        AddinShmemInitLock                => 'AddinShmem',
        AutovacuumLock                    => 'Autovacm',
        AutovacuumScheduleLock            => 'Autovacuum',
        SyncScanLock                      => 'SyncScan',
        RelationMappingLock               => 'RelationMa',
        AsyncCtlLock                      => 'AsyncCtl',
        AsyncQueueLock                    => 'AsyncQueue',
        SerializableXactHashLock          => 'XactHash',
        SerializableFinishedListLock      => 'FinishedLi',
        SerializablePredicateLockListLock => 'PredicateL',
        OldSerXidLock                     => 'OldSerXid',
        SyncRepLock                       => 'SyncRep',
        BackgroundWorkerLock              => 'Background',
        DynamicSharedMemoryControlLock    => 'DynamicSha',
        AutoFileLock                      => 'AutoFile',
        ReplicationSlotAllocationLock     => 'SlotAlloca',
        ReplicationSlotControlLock        => 'SlotContro',
        CommitTsControlLock               => 'CommitTsCo',
        CommitTsLock                      => 'CommitTs',
        ReplicationOriginLock             => 'Origin',
        MultiXactTruncationLock           => 'Truncation',
        OldSnapshotTimeMapLock            => 'OldSnapsho',
        WrapLimitsVacuumLock              => 'WrapLimits',
        NotifyQueueTailLock               => 'NotifyQueu',
      },
      LWLockTranche => {
        clog                   => 'clog',
        commit_timestamp       => 'committime',
        subtrans               => 'subtrans',
        multixact_offset       => 'multixacto',
        multixact_member       => 'multixactm',
        async                  => 'async',
        oldserxid              => 'oldserxid',
        wal_insert             => 'walinsert',
        buffer_content         => 'buffercont',
        buffer_io              => 'bufferio',
        replication_origin     => 'origin',
        replication_slot_io    => 'slotio',
        proc                   => 'proc',
        buffer_mapping         => 'buffermapp',
        lock_manager           => 'lockmanage',
        predicate_lock_manager => 'predicatel',

      },
      Lock => {
        relation            => 'relation',
        extend              => 'extend',
        frozenid            => 'frozenid',
        page                => 'page',
        tuple               => 'tuple',
        transactionid       => 'transactio',
        virtualxid          => 'virtualxid',
        "speculative token" => 'speculativ',
        object              => 'object',
        userlock            => 'userlock',
        advisory            => 'advisory',

      },
      BufferPin => {
        BufferPin => 'BufferPinx'

      }
    },
    Vacuum => {
      phase => {
        'initializing'             => 'ntlzng',
        'scanning heap'            => 'scnhp',
        'vacuuming indexes'        => 'vcmgndxs',
        'vacuuming heap'           => 'vcmghp',
        'cleaning up indexes'      => 'clnndxs',
        'runcating heap'           => 'rnctghp',
        'performing final cleanup' => 'fnlcln'
      },
    }
  );
  return \%pages;
}

sub get_non_counters {
  my %non_counters = (
    'cursors'         => 1,
    'commit_ratio'    => 1,
    'cache_hit_ratio' => 1,
    'locks'           => 1,
  );
  return \%non_counters;
}

sub get_filepath_rrd {
  my $params = shift;

  my $type      = $params->{type};
  my $server    = $params->{uuid};
  my $host      = $params->{id};
  my $skip_acl  = $params->{skip_acl};
  my $acl_check = $params->{acl_check};
  my $filepath  = "";

  if    ( $type eq '_dbs' )        { $filepath = "$home_dir/$server/$host/Stat/stat.rrd"; }
  elsif ( $type eq '_cluster' )    { $filepath = "$home_dir/$server/Cluster/bgw.rrd"; }
  elsif ( $type eq '_locks' )      { $filepath = "$home_dir/$server/$host/Locks/locks.rrd"; }
  elsif ( $type eq '_sessions' )   { $filepath = "$home_dir/$server/$host/Sessions/sessions.rrd"; }
  elsif ( $type eq '_wait_event' ) { $filepath = "$home_dir/$server/$host/Wait_event/wait_event.rrd"; }
  elsif ( $type eq '_event' )      { $filepath = "$home_dir/$server/$host/Event/event.rrd"; }
  elsif ( $type eq '_vacuum' )     { $filepath = "$home_dir/$server/$host/Vacuum/vacuum.rrd"; }
  else {
    warn "Unknown rrd type $type";
    $filepath = "";
  }

  # ACL check
  if ( $acl_check && !$skip_acl ) {
    my $uuid = get_uuid( $server, $host );

    if ( !isGranted($uuid) ) {
      return;
    }
  }

  if ( defined $filepath ) {
    return $filepath;
  }
  else {
    return;
  }
}

sub get_filepath_rrd_bpage {
  my $page   = shift;
  my $server = shift;
  my $host   = shift;
  my $type   = get_type_from_page($page);
  get_filepath_rrd( { type => $type, uuid => $server, id => $host } );
}

sub get_type_from_page {
  my $_page = shift;

  #  my %pages = %{get_pages()};

  for my $type ( keys %pages ) {
    if ( $pages{$type}{$_page} ) {
      return $type;
    }
  }
  return "nope";
}

sub isGranted {
  my $uuid = shift;

  require ACLx;
  my $acl = ACLx->new();

  return $acl->isGranted( { hw_type => 'POSTGRES', item_id => $uuid, match => 'granted' } );
}

sub isdigit {
  my $digit = shift;

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;

  #$digit_work =~ s/\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  return 0;
}

sub basename {
  my $full      = shift;
  my $separator = shift;
  my $out       = "";

  #my $length = length($full);
  if ( defined $separator and defined $full and index( $full, $separator ) != -1 ) {
    $out = substr( $full, length($full) - index( reverse($full), $separator ), length($full) );
    return $out;
  }
  return $full;
}

sub md5_string {
  my $data = shift;
  my $out  = md5_hex($data);

  return $out;
}

sub get_arc {
  if ( -e "$home_dir/_Totals/Configuration/arc_total.json" ) {
    my ( $can_read, $ref ) = Xorux_lib::read_json("$home_dir/_Totals/Configuration/arc_total.json");
    if ($can_read) {
      return $ref;
    }
    else {
      return "0";
    }
  }
  return "0";
}

sub conf_files {
  my $wrkdir   = shift;
  my $type     = shift;
  my $alias    = shift;
  my $host_url = shift;

  #$type = remove_subs($type);

  my @conf_files;

  if ( $type =~ /configuration_Cluster/ ) {
    @conf_files = ( get_dir( "_main", $alias ) );
  }
  elsif ( $type =~ m/configuration/ ) {
    @conf_files = ( " ", get_dir( "_relations", $alias, $host_url ) );
  }
  return \@conf_files;
}

sub get_dir {
  my $type  = shift;
  my $alias = shift;
  my $uuid  = shift;

  my $conf_dir = "$home_dir/$alias/Configuration";

  if ( $type eq "_main" ) {
    return "$conf_dir/main.html";
  }
  elsif ( $type eq "_relations" ) {
    return "$conf_dir/$uuid-relations.html";
  }
  else {
    return "err";
  }
}

sub get_alias {
  my $db = shift;
  my ( $can_read, $ref ) = Xorux_lib::read_json("$home_dir/_Totals/Configuration/arc_total.json");
  if ($can_read) {
    if ( $ref->{hostnames}->{$db} ) {
      return $ref->{hostnames}->{$db}->{alias};
    }
    for my $hostname ( keys %{ $ref->{hostnames} } ) {
      if ( $ref->{hostnames}->{$hostname}->{_dbs}->{$db} ) {
        return $ref->{hostnames}->{$hostname}->{alias};
      }
    }
  }
  else {
    warn "Couldn't open $home_dir/_Totals/Configuration/arc_total.json";
    return "";
  }
}

sub get_dbname {
  my $dbid = shift;
  my ( $can_read, $ref ) = Xorux_lib::read_json("$home_dir/_Totals/Configuration/arc_total.json");
  if ($can_read) {
    for my $hostname ( keys %{ $ref->{hostnames} } ) {
      if ( $ref->{hostnames}->{$hostname}->{_dbs}->{$dbid} ) {
        return $ref->{hostnames}->{$hostname}->{_dbs}->{$dbid}->{filename};
      }
    }
  }
  else {
    warn "Couldn't open $home_dir/_Totals/Configuration/arc_total.json";
    return "";
  }
}

sub get_uuid {
  my $host   = shift;
  my $server = shift;
  my $name   = shift;
  $name = defined $name ? $name : "filename";
  my ( $can_read, $ref ) = Xorux_lib::read_json("$home_dir/_Totals/Configuration/arc_total.json");
  if ($can_read) {
    for my $hostname ( keys %{ $ref->{hostnames} } ) {
      next if ( $ref->{hostnames}->{$hostname}->{alias} ne $host );
      if ( $name eq "cluster" and $ref->{hostnames}->{$hostname}->{alias} eq $host ) {
        return $hostname;
      }
      for my $db ( keys %{ $ref->{hostnames}->{$hostname}->{_dbs} } ) {
        if ( $ref->{hostnames}->{$hostname}->{_dbs}->{$db}->{$name} eq "$server" ) {
          return $db;
        }
      }
    }
  }
  else {
    warn "Couldn't open $home_dir/_Totals/Configuration/arc_total.json";
    return "";
  }
}

sub get_items {
  my %params = %{ shift() };
  my @result;

  my $arc = get_arc();
  if ( defined $params{item_type} or $arc == 0 or !defined $arc->{ $params{item_type} } ) {
    my @empty = [];
    return \@empty;
  }

  my %arc = %{$arc};
  if ( $params{item_type} eq "hostnames" ) {
    @result = keys %{ $arc{ $params{item_type} } };
  }
  elsif ( $params{item_type} eq "dbs" ) {
    for my $hostname ( keys %{ $arc{hostnames} } ) {
      push( @result, keys %{ $arc{hostnames}{$hostname}{"_$params{item_type}"} } );
    }
  }

  return \@result;
}

sub graph_legend {
  my $page = shift;

  #  $page =~ s/_/ /g;
  my %legend = (
    'default' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Memory Sorts',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "blocks" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Blocks',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"blks_read" => "blksrd",
        #"blks_hit," => "blksht",
    },
    "tuples" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Tuples',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"tup_returned" => "tprtrnd",
        #"tup_fetched"  => "tpftchd",
        #"tup_inserted" => "tpnsrtd",
        #"tup_updated"  => "tppdtd",
        #"tup_deleted"  => "tpdltd",
    },
    "temp" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Temp',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"temp_files" => "tmpfls",
        #"temp_bytes" => "tmpbts",
    },
    "sessions" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Sessions',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"current_sessions" => "crrntssns",
    },    #x
    "user" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'User',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'AREA',
      'v_label'    => '',
      'decimals'   => '0'


        #"current_transactions" => "crrnttxn",
    },
    "cursors" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Cursors',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"current_cursors" => "crrnttxn",
    },    #x
    "cache" => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Cache',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"cache_hit_ratio" => "cchhtrt",
    },
    "held" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Held locks',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"locks" => "lcks",
    },
    "awaited" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Awaited locks',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"locks" => "lcks",
    },
    "deadlocks" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Deadlocks',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"locks" => "lcks",
    },
    "commit" => {
      'denom'      => '1',
      'brackets'   => '[%]',
      'header'     => 'Commit',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'


        #"commit_ratio" => "cmmtrt",
    },
    "buffers" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Buffers',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => 'Buffers written',
      'decimals'   => '1'


        #"buffers_backend"     => "bfrsbcknd",
        #"buffers_clean"       => "bfrscln",
        #"buffers_checkpoint"  => "bfrschckpnt",
    },
    "checkpoints" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Chechpoints',
      'value'      => 'Total',
      'rrd_vname'  => 'blksrd',
      'graph_type' => 'LINE1',
      'v_label'    => 'Number of checkpoints',
      'decimals'   => '1'


        #"checkpoints_req"     => "chckpntsrq",
        #"checkpoints_timed"   => "chckpntstmd",
    },
    "we_type" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Type',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "LWLockNamed" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'LWLockNamed',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "LWLockTranche" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'LWLockTranche',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "Lock" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Lock',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "BufferPin" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'BufferPin',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "phase" => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Current phase',
      'value'      => 'Total',
      'graph_type' => 'LINE1',
      'v_label'    => '',
      'decimals'   => '0'

    },
    "size" => {
      'denom'      => '1',
      'brackets'   => '[GiB]',
      'header'     => 'Size',
      'value'      => 'GB',
      'graph_type' => 'AREA',
      'v_label'    => 'GiB',
      'decimals'   => '1'

    }

  );

  if ( $legend{$page} ) {
    return $legend{$page};
  }
  else {
    return $legend{default};
  }
}
1;
