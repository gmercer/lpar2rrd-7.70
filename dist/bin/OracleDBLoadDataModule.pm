package OracleDBLoadDataModule;

use strict;
use warnings;

use RRDp;
use Xorux_lib;
use Data::Dumper;
use OracleDBAlerting;

my $rrdtool = $ENV{RRDTOOL};

my $step    = 60;
my $no_time = $step * 18;

my $one_minute_sample = 86400;
my $five_mins_sample  = 25920;
my $one_hour_sample   = 4320;
my $five_hours_sample = 1734;
my $one_day_sample    = 1080;

my %metrics = (
  'CPU_info' => [ 'CPU Usage Per Sec', 'CPU Usage Per Txn', 'Host CPU Utilization (%)' ],
  'Network'  => ['Network Traffic Volume Per Sec'],
  'Ratio'    => [
    'Database Wait Time Ratio', 'Memory Sorts Ratio', 'PGA Cache Hit %',
    'Database CPU Time Ratio',  'Soft Parse Ratio',   'Buffer Cache Hit Ratio'
  ],
  'SQL_query' => [
    'Executions Per Sec',   'Hard Parse Count Per Sec',   'User Transaction Per Sec',
    'User Commits Per Sec', 'Current Open Cursors Count', 'Open Cursors Per Sec'
  ],
  'Data_rate' => [
    'I/O Megabytes per Second', 'Physical Read Bytes Per Sec',  'Physical Writes Per Sec',
    'I/O Requests per Second',  'Redo Generated Per Sec',       'Logical Reads Per Sec',
    'Physical Reads Per Sec',   'Physical Write Bytes Per Sec', 'DB Block Changes Per Sec'
  ],
  'Session_info' => [
    'Current Logons Count',    'Logons Per Sec', 'Active Serial Sessions',
    'Average Active Sessions', 'Active Parallel Sessions'
  ],
  'RAC' => [
    'Global Cache Blocks Lost',              'Global Cache Average CR Get Time',
    'Global Cache Average Current Get Time', 'GC CR Block Received Per Second',
    'GC Current Block Received Per Second',  'Cell Physical IO Interconnect Bytes',
    'Global Cache Blocks Corrupted',         'GC Avg CR Block receive ms', 'GC Avg CUR Block receive ms',
    'DB files read latency',                 'DB files write latency',
    'LOG files write latency',               'gc cr block 2-way',
    'gc cr block 3-way',                     'gc current block 2-way',
    'gc current block 3-way',                'gc cr block busy',
    'gc cr block congested',                 'gc cr grant 2-way',
    'gc cr grant congested',                 'gc current block busy',
    'gc current block congested',            'gc cr block lost',
    'gc current block lost',                 'gc cr failure',
    'gc current retry',                      'gc current split',
    'gc current multi block request',        'gc current grant busy',
    'gc cr disk read',                       'gc cr multi block request',
    'gc buffer busy acquire',                'gc buffer busy release',
    'gc current grant 2-way',                'gc current grant congested',
    'gc remaster'
  ],
  'Cache' => [
    'Global Cache Blocks Lost',              'Global Cache Average CR Get Time',
    'Global Cache Average Current Get Time', 'GC CR Block Received Per Second',
    'GC Current Block Received Per Second',  'Cell Physical IO Interconnect Bytes',
    'Global Cache Blocks Corrupted',         'GC Avg CR Block receive ms', 'GC Avg CUR Block receive ms',
  ],

  'Disk_latency' => [
    'db file sequential read', 'db file single write',
    'db file parallel write',  'log file sync',
    'log file single write',   'log file parallel write',
    'flashback log file sync', 'db file scattered read',
  ],
  'Wait_class_Main' => [ 'Average wait FG ms', 'Average wait ms' ],

  'IO_Read_Write_per_datafile' => [
    'Physical Writes',  'Physical Reads', 'Avg write read ms',
    'Avg read wait ms', 'Read/Write %'
  ],
  'Services' => [ 'physical reads', 'physical writes' ],
  'Capacity' => [ 'used',           'free', 'log_capacity' ],
  'Cpct'     => [ 'controlfiles',   'tempfiles', 'recoverysize', 'recoveryused' ]
);
my %met_rrd = (
  'CPU_info' => [ 'CPUusgPS', 'CPUusgPT', 'HstCPUutil' ],
  'Network'  => ['NetTrfcVlPS'],
  'Ratio'    => [
    'DbWtTm',  'MmrSrts', 'PGACchHt',
    'DbCPUTm', 'SftPrs',  'BffrCchHt'
  ],
  'SQL_query' => [
    'ExecsPS',    'HrdPrsCntPS', 'UsrTxnPS',
    'UsrComtsPS', 'CntOpnCrs',   'OpnCrsPS'
  ],
  'Data_rate' => [
    'IOMbPS',     'PhysReadBPS',  'PhysWritePS',
    'IORqstPS',   'RdoGenPS',     'LgclReadPS',
    'PhysReadPS', 'PhysWriteBPS', 'DBBlckChngPS'
  ],
  'Session_info' => [
    'CrntLgnsCnt', 'LgnsPS', 'ActSrlSsion',
    'AvgActSsion', 'ActPrllSsion'
  ],
  'RAC' => [
    'GCBlckLst',    'GCAvgCRGtTm',
    'GCAvgCtGtTm',  'GCCRBlckRcPS',
    'GCCtBlckRcPS', 'CPIOIntB',
    'GCBlckCrrptd', 'AvgCRBlkrc', 'AvgCURBlkrc',
    'flsrltnc',     'flswltnc',
    'LGflswltnc',   'crblocktwy',
    'crblckthwy',   'crntblcktwy',
    'crntblckthwy', 'crblckbs',
    'crblckcngstd', 'crgrnttwy',
    'crgrntcngstd', 'crntblckbs',
    'crntblckcngs', 'crblcklst',
    'crntblcklst',  'crflr',
    'crntrtr',      'crntsplt',
    'crntmltrqst',  'crntgrntbs',
    'crdskr',       'crmtblckrqst',
    'bfrbsacqr',    'bfrbsrls',
    'crntgrnttwy',  'crntgrntcstd',
    'gcrmstr'
  ],
  'Cache' => [
    'GCBlckLst',    'GCAvgCRGtTm',
    'GCAvgCtGtTm',  'GCCRBlckRcPS',
    'GCCtBlckRcPS', 'CPIOIntB',
    'GCBlckCrrptd', 'AvgCRBlkrc', 'AvgCURBlkrc',
  ],
  'Disk_latency' => [
    'flsqentlr',   'flsnglw',
    'flprlllw',    'lgflsnc',
    'lgflsnglw',   'lgflprlllw',
    'flshbcklgfl', 'dbflscttrdr'
  ],
  'Wait_class_Main'            => [ 'AvgwtFGms', 'Avgwtms' ],
  'IO_Read_Write_per_datafile' => [
    'physW', 'physR',
    'avgwrms', 'avgrwms', 'rw'
  ],
  'Services' => [ 'physR',        'physW' ],
  'Capacity' => [ 'used',         'free', 'log' ],
  'Cpct'     => [ 'controlfiles', 'tempfiles', 'recoverysize', 'recoveryused' ]
);

################################################################################

sub touch {
  my $text       = shift;
  my $version    = "$ENV{version}";
  my $basedir    = $ENV{INPUTDIR};
  my $new_change = "$basedir/tmp/$version-oracledb";
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
      Xorux_lib::error( "Unable to create $filepath : at " . __FILE__ . ": line " . __LINE__ );
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

    if ( $type eq "Wait_class_Main" or $type eq "IO_Read_Write_per_datafile" ) {
      if ( $hash{$item} ) {
        $hash{$item} =~ s/,/./g;
        if ( $hash{$item} =~ /^\./ ) {
          $hash{$item} = "0" . "$hash{$item}";
        }
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
  if ( $$lastupdate > $act_time ) {
    my $readable_lastupdate = localtime($$lastupdate);
    my $readable_time       = localtime($act_time);
    warn "Cant update rrd. Last data update time $readable_lastupdate ($$lastupdate) for $type is greater than actual time $readable_time ($act_time).  $rrd";
    return 0;
  }

  RRDp::cmd qq(update "$rrd" $update_string);
  eval { my $answer = RRDp::read; };

  if ($@) {
    Xorux_lib::error( "Failed during read last time $rrd: $@ " . __FILE__ . ":" . __LINE__ );
    return 0;
  }
  return 1;
}

1;
