# xen-json2rrd.pl
# store XenServer data retrieved from XAPI into RRDs

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;

use File::Copy;
use JSON qw(decode_json encode_json);
use RRDp;

use XenServerDataWrapper;
use XenServerLoadDataModule;
use Xorux_lib qw(error write_json);

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

# data file paths
my $inputdir          = $ENV{INPUTDIR};
my $iostats_dir       = "$inputdir/data/XEN_iostats";
my $json_dir          = "$iostats_dir/json";
my $rrd_filepath_host = "$inputdir/data/XEN";
my $rrd_filepath_vm   = "$inputdir/data/XEN_VMs";
my $metadata_dir      = "$iostats_dir/metadata";
my $metadata_file     = "$iostats_dir/conf.json";
my $tmpdir            = "$inputdir/tmp";

my $rrdtool = $ENV{RRDTOOL};

my $rrd_start_time;

################################################################################

RRDp::start "$rrdtool";

my $rrdtool_version = 'Unknown';
$_ = `$rrdtool`;
if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
  $rrdtool_version = $1;
}
print "RRDp    version: $RRDp::VERSION \n";
print "RRDtool version: $rrdtool_version\n";

my @files;
my $data;
my ( $DH, $FH );

opendir $DH, $json_dir || die "Could not open '$json_dir' for reading '$!'\n";
@files = grep /.*.json/, readdir $DH;
foreach my $file ( sort @files ) {
  my $has_failed = 0;

  # read file
  my $json = '';
  if ( open( $FH, '<', "$json_dir/$file" ) ) {
    while ( my $row = <$FH> ) {
      chomp $row;
      $json .= $row;
    }
    close $FH;
  }
  else {
    warn( localtime() . ": Cannot open the file $file ($!)" ) && next;
    next;
  }

  # decode JSON
  $data = decode_json($json);
  if ( ref( $data->{data} ) ne 'ARRAY' ) {
    warn( localtime() . ": Error decoding JSON in file $file: missing data" ) && next;
  }

  # access data
  $rrd_start_time = $data->{meta}[0]->{start}[0];
  my ( $legends, @values );
  if ( ref( $data->{meta} ) eq 'ARRAY'
    && exists $data->{meta}[0]->{legend}
    && ref( $data->{meta}[0]->{legend} ) eq 'ARRAY'
    && exists $data->{meta}[0]->{legend}[0]->{entry} )
  {
    $legends = $data->{meta}[0]->{legend}[0]->{entry};
  }
  else {
    next;
  }
  if ( ref( $data->{data} ) eq 'ARRAY' && exists $data->{data}[0]->{row} ) {
    @values = @{ $data->{data}[0]->{row} };
  }
  else {
    next;
  }

  my ( @vm_uuids, @host_uuids );
  my @header;

  # parse table header
  foreach my $column ( @{$legends} ) {

    # cf:(vm|host):uuid:metric
    my @col = split /:/, $column;
    push @header, [@col];
  }

  # create RRDs if needed
  my %rrd_columns;
  for my $i ( 0 .. $#header ) {
    my ( undef, $entry_type, $uuid, $metric ) = @{ $header[$i] };
    my ( $id, $rrd_filepath );

    # check system/interface/storage metrics and existence of respective RRDs
    if ( $entry_type =~ m/host/ ) {
      unless ( -d $rrd_filepath_host ) {
        mkdir( $rrd_filepath_host, 0755 ) || warn( localtime() . ": Could not mkdir '$rrd_filepath_host': $!" ) && next;
      }

      my $dir_filepath = "$rrd_filepath_host/$uuid";
      unless ( -d $dir_filepath ) {
        mkdir( $dir_filepath, 0755 ) || warn( localtime() . ": Could not mkdir '$dir_filepath': $!" ) && next;
      }

      if ( $metric =~ m/^pif/ && $metric !~ m/^pif_aggr/ ) {
        $id           = ( split( '_', $metric ) )[1];
        $rrd_filepath = XenServerDataWrapper::get_filepath_rrd( { type => 'network', uuid => $uuid, id => $id, skip_acl => 1 } );
        unless ( -f $rrd_filepath ) {
          if ( LoadDataModuleXenServer::create_rrd_host_lan( $rrd_filepath, $rrd_start_time ) ) {
            $has_failed = 1;
          }
        }
      }
      elsif ( $metric =~ m/^(io|write|read)/ ) {
        $id           = ( split( '_', $metric ) )[-1];
        $rrd_filepath = XenServerDataWrapper::get_filepath_rrd( { type => 'storage', uuid => $uuid, id => $id, skip_acl => 1 } );
        unless ( -f $rrd_filepath ) {
          if ( LoadDataModuleXenServer::create_rrd_host_disk( $rrd_filepath, $rrd_start_time ) ) {
            $has_failed = 1;
          }
        }
      }
      else {
        $rrd_filepath = XenServerDataWrapper::get_filepath_rrd( { type => 'host', uuid => $uuid, skip_acl => 1 } );
        unless ( -f $rrd_filepath ) {
          if ( LoadDataModuleXenServer::create_rrd_host( $rrd_filepath, $rrd_start_time ) ) {
            $has_failed = 1;
          }
        }
      }
    }
    elsif ( $entry_type =~ m/vm/ ) {
      unless ( -d $rrd_filepath_vm ) {
        mkdir( $rrd_filepath_vm, 0755 ) || warn( localtime() . ": Could not mkdir '$rrd_filepath_vm': $!" ) && next;
      }

      $rrd_filepath = XenServerDataWrapper::get_filepath_rrd( { type => 'vm', uuid => $uuid, skip_acl => 1 } );
      unless ( -f $rrd_filepath ) {
        if ( LoadDataModuleXenServer::create_rrd_vm( $rrd_filepath, $rrd_start_time ) ) {
          $has_failed = 1;
        }
      }
    }
    else {
      warn( localtime() . ": unknown system type '$entry_type', uuid '$uuid'" );
    }

    # save correspondence between columns and RRD files
    $rrd_columns{$rrd_filepath}{$metric} = $i;
  }

  # store values
  my ( $timestamp, @vals );
  foreach my $point ( sort { $a->{t}[0] <=> $b->{t}[0] } @values ) {
    $timestamp = $point->{t}[0];
    @vals      = @{ $point->{v} };

    warn( localtime() . ": number of values ($#vals) does not match number of columns ($#header)" ) unless ( $#vals == $#header );

    # filter columns to update the right RRDs
    for my $rrd_file ( keys %rrd_columns ) {
      my %updates;
      for my $metric ( keys %{ $rrd_columns{$rrd_file} } ) {
        $updates{$metric} = $vals[ $rrd_columns{$rrd_file}{$metric} ];
      }

      # update the RRD
      if ( $rrd_file =~ m/^$rrd_filepath_vm/ ) {
        if ( LoadDataModuleXenServer::update_rrd_vm( $rrd_file, $timestamp, \%updates ) ) {
          $has_failed = 1;
        }
      }
      elsif ( $rrd_file =~ m/^$rrd_filepath_host/ ) {
        if ( $rrd_file =~ m/\/sys\.rrd$/ ) {
          if ( LoadDataModuleXenServer::update_rrd_host( $rrd_file, $timestamp, \%updates ) ) {
            $has_failed = 1;
          }
        }
        elsif ( $rrd_file =~ m/\/lan-(.*)\.rrd$/ ) {
          if ( LoadDataModuleXenServer::update_rrd_host_lan( $rrd_file, $timestamp, \%updates ) ) {
            $has_failed = 1;
          }
        }
        elsif ( $rrd_file =~ m/\/disk-(.*)\.rrd$/ ) {
          if ( LoadDataModuleXenServer::update_rrd_host_disk( $rrd_file, $timestamp, \%updates ) ) {
            $has_failed = 1;
          }
        }
      }
    }
  }

  unless ($has_failed) {
    backup_perf_file($file);
  }
}
closedir $DH;

################################################################################

# merge metadata files
my (%dictionary);

opendir $DH, $metadata_dir || die "Could not open '$metadata_dir' for reading '$!'\n";
@files = grep /.*.json/, readdir $DH;

foreach my $file ( sort @files ) {

  # read file
  my $json = '';
  if ( open( $FH, '<', "$metadata_dir/$file" ) ) {
    while ( my $row = <$FH> ) {
      chomp $row;
      $json .= $row;
    }
    close $FH;
  }
  else {
    warn( localtime() . ": Cannot open the file $file ($!)" ) && next;
    next;
  }

  # decode JSON
  $data = decode_json($json);

  if ( $file =~ m/xe_(.*).json$/ ) {
    if ( defined $data->{labels} ) {
      while ( my ( $type, $values ) = each %{ $data->{labels} } ) {
        while ( my ( $k, $v ) = each %{$values} ) {
          $dictionary{labels}{$type}{$k} = $v;
        }
      }
    }
    if ( defined $data->{architecture} ) {
      while ( my ( $type, $values ) = each %{ $data->{architecture} } ) {
        while ( my ( $k, $v ) = each %{$values} ) {
          $dictionary{architecture}{$type}{$k} = $v;
        }
      }
    }
    if ( defined $data->{specification} ) {
      while ( my ( $type, $values ) = each %{ $data->{specification} } ) {
        while ( my ( $k, $v ) = each %{$values} ) {
          $dictionary{specification}{$type}{$k} = $v;
        }
      }
    }
  }
}
closedir $DH;

# save metadata in a single file
# but only if there is any metadata and the single file does not exist yet
if ( !-f $metadata_file || %dictionary ) {
  Xorux_lib::write_json( $metadata_file, \%dictionary );

  #  my $json = JSON->new->utf8->pretty;
  #  my $json_data = $json->encode( \%dictionary );

  #  open( JSON_FH, '>', "$metadata_file" ) || die "error: cannot save the metadata JSON\n";
  #  print JSON_FH "$json_data\n";
  #  close(JSON_FH);

  backup_conf_file();
}

################################################################################

sub backup_perf_file {

  # expects file name for the file, that's supposed to be moved from XEN_iostats/
  #     with file name "XEN_alias_hostname_perf_timestamp.json"
  my $src_file = shift;
  my $alias    = ( split( '_', $src_file ) )[1];
  my $source   = "$json_dir/$src_file";
  my $target1  = "$tmpdir/xenserver-$alias-perf-last1.json";
  my $target2  = "$tmpdir/xenserver-$alias-perf-last2.json";

  if ( -f $target1 ) {
    move( $target1, $target2 ) or die "error: cannot replace the old backup data file: $!";
  }
  move( $source, $target1 ) or die "error: cannot backup the data file: $!";
}

sub backup_conf_file {
  my $target = "$tmpdir/xenserver-conf-last.json";
  copy( $metadata_file, $target ) or die "error: cannot backup the metadata file: $!";
}

# close RRDtool session
RRDp::end;
