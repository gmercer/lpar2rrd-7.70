package Docker;

use strict;
use warnings;

use JSON;
use DockerDataWrapper;
use DockerLoadDataModule;
use Digest::MD5 qw(md5 md5_hex);

# data file paths
my $inputdir      = $ENV{INPUTDIR};
my $data_dir      = "$inputdir/data/Docker";
my $container_dir = "$data_dir/Container";
my $volume_dir    = "$data_dir/Volume";
my $check_dir     = "$data_dir/check";
my $labels_file   = "$data_dir/labels.json";
my $arch_file     = "$data_dir/architecture.json";
my $tmpdir        = "$inputdir/tmp";

my @dir = ( $data_dir, $container_dir, $volume_dir, $check_dir );

for my $path (@dir) {
  unless ( -d $path ) {
    mkdir( "$path", 0755 ) || warn( localtime() . ": Cannot mkdir $path: $!" . __FILE__ . ':' . __LINE__ );
  }
}

# 'Docker-container:timescaledb:31b2d59a02ce77fcff92b2c29c03428fbaed0d3bd794ed9523cd680e299280a4:1645609823:|{"children":["69e89d2c984f0eaa3befce8dd5db6a22166875d524d12952705496f1e4de7708"],"metrics":{"size_root_fs":250253923,"size_rw":28877,"cpu_number":4,"write_bytes":0,"memory_usage":23,"memory_available":3136020480,"memory_used":695762944,"memory_free":2440257536,"rx_bytes":279,"write_io":0,"cpu_usage":0,"read_io":0,"read_bytes":0,"tx_bytes":250},"hostname":{"uuid":"c96a3596eeadc01cdcfb00cddf02cb35","label":"Others"}}';

sub save {
  my ( $type, $label, $uuid, $time, $data, $adress ) = @_;

  my $has_failed = 0;
  my $rrd_filepath;

  #my $rrdtool   = $ENV{RRDTOOL};
  my $timestamp = my $rrd_start_time = time() - 4200;

  #RRDp::start "$rrdtool";

  if ( $type eq "Docker-container" ) {
    $type = 'container';
  }
  elsif ( $type eq "Docker-volume" ) {
    $type = 'volume';
  }
  else {
    return ();
  }

  my $json = decode_json($data);
  $rrd_filepath = DockerDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid } );
  my $host_label;
  my $host_uuid;
  if ( !defined $json->{hostname}{label} || $json->{hostname}{label} eq "Others" ) {
    $host_label = $adress;
    $host_uuid  = md5_hex( 'docker-' . $adress );
  }
  else {
    $host_label = $json->{hostname}{label};
    $host_uuid  = $json->{hostname}{uuid};
  }
  unless ( -f $rrd_filepath ) {
    &saveLabel( 'host', $host_uuid, $host_label );
    if ( $type eq "container" ) {
      &saveLabel( 'container', $uuid, $label );
      &saveArchitecture( 'container', $uuid, $host_uuid );
      if ( DockerLoadDataModule::create_rrd_container( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
    elsif ( $type eq "volume" ) {
      &saveLabel( 'volume', $uuid, $label );
      &saveArchitecture( 'volume', $uuid, $host_uuid );
      if ( DockerLoadDataModule::create_rrd_volume( $rrd_filepath, $rrd_start_time ) ) {
        $has_failed = 1;
      }
    }
  }

  if ( $has_failed != 1 ) {
    my %updates;
    if ( $type eq "container" ) {
      %updates = (
        'cpu_number'       => $json->{metrics}{cpu_number},
        'cpu_usage'        => $json->{metrics}{cpu_usage},
        'memory_used'      => $json->{metrics}{memory_used},
        'memory_available' => $json->{metrics}{memory_available},
        'memory_free'      => $json->{metrics}{memory_free},
        'memory_usage'     => $json->{metrics}{memory_usage},
        'read_bytes'       => $json->{metrics}{read_bytes},
        'write_bytes'      => $json->{metrics}{write_bytes},
        'read_io'          => $json->{metrics}{read_io},
        'write_io'         => $json->{metrics}{write_io},
        'rx_bytes'         => $json->{metrics}{rx_bytes},
        'tx_bytes'         => $json->{metrics}{tx_bytes},
        'size_rw'          => $json->{metrics}{size_rw},
        'size_root_fs'     => $json->{metrics}{size_root_fs},
      );
      if ( DockerLoadDataModule::update_rrd_container( $rrd_filepath, $time, \%updates ) ) {
        return ();
      }
    }
    elsif ( $type eq "volume" ) {
      %updates = (
        'size' => $json->{metrics}{size},
      );
      if ( DockerLoadDataModule::update_rrd_volume( $rrd_filepath, $time, \%updates ) ) {
        return ();
      }
    }
    `touch $data_dir/check/$host_uuid`;
  }
  else {
    return ();
  }

  return $time;
}

sub saveLabel {
  my ( $type, $uuid, $label ) = @_;

  # read file
  my $data;
  my $json;
  if ( -e $labels_file ) {
    $json = '';
    if ( open( my $fh, '<', "$labels_file" ) ) {
      while ( my $row = <$fh> ) {
        chomp $row;
        $json .= $row;
      }
      close($fh);
    }
    else {
      warn( localtime() . ": Cannot open the file $labels_file ($!)" ) && next;
      next;
    }
  }
  else {
    $json = '{}';
  }

  # decode JSON
  eval { $data = decode_json($json); };
  if ($@) {
    my $error = $@;
    error("corrupted labels file");
    unlink "$labels_file";
    next;
  }
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file $labels_file: missing data" ) && next;
  }

  $data->{$type}{$uuid} = $label;

  open my $fh, ">", "$labels_file";
  print $fh JSON->new->pretty->encode($data);
  close $fh;
}

sub deleteLabel {
  my ( $type, $uuid ) = @_;

  # read file
  my $data;
  my $json;
  if ( -e $labels_file ) {
    $json = '';
    if ( open( my $fh, '<', "$labels_file" ) ) {
      while ( my $row = <$fh> ) {
        chomp $row;
        $json .= $row;
      }
      close($fh);
    }
    else {
      warn( localtime() . ": Cannot open the file $labels_file ($!)" ) && next;
      next;
    }
  }
  else {
    $json = '{}';
  }

  # decode JSON
  eval { $data = decode_json($json); };
  if ($@) {
    my $error = $@;
    error("corrupted labels file");
    unlink "$labels_file";
    next;
  }
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file $labels_file: missing data" ) && next;
  }

  if ( defined $data->{$type}{$uuid} ) {
    delete $data->{$type}{$uuid};
  }

  open my $fh, ">", "$labels_file";
  print $fh JSON->new->pretty->encode($data);
  close $fh;
}

sub saveArchitecture {
  my ( $type, $uuid, $parent ) = @_;

  # read file
  my $data;
  my $json;
  if ( -e $arch_file ) {
    $json = '';
    if ( open( my $fh, '<', "$arch_file" ) ) {
      while ( my $row = <$fh> ) {
        chomp $row;
        $json .= $row;
      }
      close($fh);
    }
    else {
      warn( localtime() . ": Cannot open the file $arch_file ($!)" ) && next;
      next;
    }
  }
  else {
    $json = '{}';
  }

  # decode JSON
  eval { $data = decode_json($json); };
  if ($@) {
    my $error = $@;
    error("corrupted architecture file");
    unlink "$arch_file";
    next;
  }
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file $arch_file: missing data" ) && next;
  }

  if ( defined $data->{ 'host_' . $type }{$parent} ) {
    if ( !grep( /^$uuid$/, @{ $data->{ 'host_' . $type }{$parent} } ) ) {
      push( @{ $data->{ 'host_' . $type }{$parent} }, $uuid );
    }
  }
  else {
    $data->{ 'host_' . $type }{$parent}[0] = $uuid;
  }

  open my $fh, ">", "$arch_file";
  print $fh JSON->new->pretty->encode($data);
  close $fh;
}

sub deleteArchitecture {
  my ( $type, $uuid ) = @_;

  # read file
  my $data;
  my $json;
  if ( -e $arch_file ) {
    $json = '';
    if ( open( my $fh, '<', "$arch_file" ) ) {
      while ( my $row = <$fh> ) {
        chomp $row;
        $json .= $row;
      }
      close($fh);
    }
    else {
      warn( localtime() . ": Cannot open the file $arch_file ($!)" ) && next;
      next;
    }
  }
  else {
    $json = '{}';
  }

  # decode JSON
  eval { $data = decode_json($json); };
  if ($@) {
    my $error = $@;
    error("corrupted architecture file");
    unlink "$arch_file";
    next;
  }
  if ( ref($data) ne "HASH" ) {
    warn( localtime() . ": Error decoding JSON in file $arch_file: missing data" ) && next;
  }

  if ( defined $data->{ 'host_' . $type } ) {
    foreach my $host ( keys %{ $data->{ 'host_' . $type } } ) {
      my $max_i = scalar @{ $data->{ 'host_' . $type }{$host} };
      for my $index ( 0 .. $max_i - 1 ) {
        if ( $data->{ 'host_' . $type }{$host}[$index] eq $uuid ) {
          splice @{ $data->{ 'host_' . $type }{$host} }, $index, 1;
        }
      }
    }
  }

  open my $fh, ">", "$arch_file";
  print $fh JSON->new->pretty->encode($data);
  close $fh;
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print STDERR "$act_time: $text : $!\n";
  return 1;
}

1;
