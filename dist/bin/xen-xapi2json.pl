# xen-xapi2json.pl
# download XAPI data dump from XenServer hosts

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use HostCfg;
use LWP::UserAgent;
use HTTP::Request;
use JSON qw(decode_json encode_json);
use Xorux_lib qw(write_json);
use POSIX ":sys_wait_h";

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
require "$inputdir/bin/xml.pl";

my $path_prefix   = "$inputdir/data/XEN_iostats";
my $xml_path      = "$path_prefix/xml";
my $json_path     = "$path_prefix/json";
my $metadata_path = "$path_prefix/metadata";

my $SSH = $ENV{SSH} . ' ';

# create directories in data/
unless ( -d $path_prefix ) {
  mkdir( "$path_prefix", 0755 ) || warn( localtime() . ": Cannot mkdir $path_prefix: $!" . __FILE__ . ':' . __LINE__ );
}
unless ( -d $xml_path ) {
  mkdir( "$xml_path", 0755 ) || warn( localtime() . ": Cannot mkdir $xml_path: $!" . __FILE__ . ':' . __LINE__ );
}
unless ( -d $json_path ) {
  mkdir( "$json_path", 0755 ) || warn( localtime() . ": Cannot mkdir $json_path: $!" . __FILE__ . ':' . __LINE__ );
}
unless ( -d $metadata_path ) {
  mkdir( "$metadata_path", 0755 ) || warn( " Cannot mkdir $metadata_path: $!" . __FILE__ . ':' . __LINE__ );
}

my %hosts = %{ HostCfg::getHostConnections('XenServer') };
my @pids;
my $pid;
my $timeout = 1200;

foreach my $host ( keys %hosts ) {

  # fork for each host
  unless ( defined( $pid = fork() ) ) {
    warn( localtime() . ': Error: failed to fork for ' . $host . ".\n" );
    next;
  }
  else {
    if ($pid) {
      push @pids, $pid;
    }
    else {
      eval {
        # Set alarm
        my $act_time = localtime();
        local $SIG{ALRM} = sub { die "$act_time: XenServer XAPI2JSON: $pid died in SIG ALRM"; };
        alarm($timeout);
        collect_data($host);

        #  end of alarm
        alarm(0);
      };
      if ($@) {
        if ( $@ =~ /died in SIG ALRM/ ) {
          warn( localtime() . ': XenServer data collection timed out on ' . $hosts{$host}{host} . ' after ' . $timeout . ' seconds : ' . __FILE__ . ':' . __LINE__ );
        }
        else {
          warn( localtime() . ': error while connecting to ' . $hosts{$host}{host} . ", error: $@ : " . __FILE__ . ':' . __LINE__ );
        }
        exit(0);
      }

      exit;
    }
  }
}

# wait for forked data retrieval
for $pid (@pids) {
  waitpid( $pid, 0 );
}

print 'data collection    : done successfully, ' . localtime() . "\n";
exit 0;

################################################################################

sub collect_data {
  my $host = shift;

  my ( $hostname, $username ) = ( $hosts{$host}{host}, $hosts{$host}{username} );

  if ( $hosts{$host}{auth_api} ) {
    my $password = $hosts{$host}{password};
    my ( $protocol, $port ) = ( $hosts{$host}{proto}, $hosts{$host}{api_port} );
    xapi2json( $hostname, $username, $password, $protocol, $port );
  }

  if ( $hosts{$host}{auth_ssh} ) {
    my $ssh_key = $hosts{$host}{ssh_key_id};
    my $port    = $hosts{$host}{ssh_port};
    ssh2json( $hostname, $username, $ssh_key, $port );
  }

  return 1;
}

# fetch "performance" data

sub xapi2json {
  my ( $host, $username, $password, $protocol, $port ) = @_;

  my $rrdfile    = 'rrd_updates';
  my $start_time = time() - 20 * 60;                                                              # last 20 minutes
  my $db_url     = "$protocol://$host:$port/$rrdfile?start=${start_time}&cf=AVERAGE&host=true";

  my $xml_file  = "$xml_path/$rrdfile\_$host\_$start_time.xml";
  my $json_file = "$json_path/XEN\_$host\_perf_$start_time.json";

  # download dumped RRD as XML
  my $ua  = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 } );
  my $req = HTTP::Request->new( GET => $db_url );
  $req->content_type('application/xml');
  $req->header( 'Accept' => '*/*' );
  $req->authorization_basic( $username, $password );
  my $res = $ua->request($req);
  if ( $res->is_success ) {
    if ( $res->{_content} eq '' ) {
      die "error: empty database dump\n";
    }
    else {
      open my $XML_FH, '>', "$xml_file" || die "error: cannot save the received RRD XML file\n";
      print $XML_FH "$res->{_content}\n";
      close $XML_FH;
    }
  }
  else {
    die 'error: ' . $res->status_line . "\n";
  }

  # parse XML
  my $data;
  my $xml_simple = XML::Simple->new( keyattr => [], ForceArray => 1 );

  eval { $data = $xml_simple->XMLin($xml_file); };
  if ($@) {
    warning("XML parsing error: $@");
    message("XML parsing error. Trying to recover XML with xmllint");

    eval {
      my $linted = `xmllint --recover $xml_file`;
      $data = $xml_simple->XMLin($linted);
    };

    if ($@) {
      warn( localtime() . ': XML parsing error: ' . $@ . __FILE__ . ':' . __LINE__ . ' file: ' . $xml_file );
      message( 'XML parsing error: File: ' . $xml_file );
      die "error: invalid XML\n";
    }
  }

  # save as JSON
  my $code = Xorux_lib::write_json( $json_file, $data );

  # clean up the downloaded data dump
  unlink $xml_file;
}

################################################################################

# fetch "configuration" data

sub ssh2json {
  my ( $host, $username, $ssh_key, $port ) = @_;
  my %dictionary;

  # if the username contains any backslash, e.g., as domain delimiter in Active Directory
  $username =~ s/\\/\\\\/g;

  # wrapper for general commands
  my $get_output = sub {
    my $cmd_api         = shift;
    my $redirect_stderr = shift;
    my $cmd             = "$SSH";
    $cmd .= " -i $ssh_key" if ($ssh_key);
    $cmd .= " -p $port"    if ($port);
    $cmd .= " $username\@$host";
    $cmd .= " \"$cmd_api\"";
    $cmd .= " 2>&1" if ($redirect_stderr);

    my $result = `$cmd`;
    return $result;
  };

  # wrapper for commands with --minimal flag
  my $get_values = sub {
    my $cmd_api         = shift;
    my $redirect_stderr = shift;
    my $cmd             = "$SSH";
    $cmd .= " -i $ssh_key" if ($ssh_key);
    $cmd .= " -p $port"    if ($port);
    $cmd .= " $username\@$host";
    $cmd .= " \"$cmd_api\"";
    $cmd .= " 2>&1" if ($redirect_stderr);

    my @result = split ',', `$cmd`;
    chomp $_ foreach (@result);
    return @result;
  };

  # get labels (human-readable names for UUIDs)
  my @sources = ( 'vm', 'host', 'pool', 'sr', 'vdi' );
  foreach my $source (@sources) {
    my $object_list = $get_output->("xe $source-list params=uuid,name-label");
    my @objects     = split "\n\n\n", $object_list;
    foreach my $object (@objects) {
      my @params = split "\n", $object;
      my %this_object;
      foreach my $line (@params) {
        my ( $key, $val ) = split ":", $line, 2;
        $key =~ s/^\s+|\s+$//g;
        $val =~ s/^\s+|\s+$//g;
        if    ( $key =~ m/uuid/ )       { $this_object{uuid}       = $val; }
        elsif ( $key =~ m/name-label/ ) { $this_object{name_label} = $val; }
      }
      if ( $this_object{name_label} ) {
        $dictionary{labels}{$source}{ $this_object{uuid} } = $this_object{name_label};
      }
      else {
        my $short_uuid = substr( $this_object{uuid}, 0, 8 );
        $dictionary{labels}{$source}{ $this_object{uuid} } = "no label $short_uuid ...";
      }
    }
  }

  # get system specification/configuration
  {
    # hosts
    my $host_list = $get_output->("xe host-list params=uuid,name-label,memory-total,address,cpu_info,software-version");
    my @hosts     = split "\n\n\n", $host_list;
    foreach my $object (@hosts) {
      my @params = split "\n", $object;
      my %this_object;
      foreach my $line (@params) {
        my ( $key, $val ) = split ":", $line, 2;
        $key =~ s/^\s+|\s+$//g;
        $val =~ s/^\s+|\s+$//g;
        if ( $val =~ m/Error: Key name not found in map/ ) { next; }
        if ( $key =~ m/uuid/ ) { $this_object{uuid} = $val; }
        elsif ( $key =~ m/name-label/ ) { $this_object{name_label} = $val; }
        elsif ( $key =~ m/memory-total/ ) {
          $val /= 1024**3;    # convert from bytes to GB
          $val = sprintf "%.2f", $val;
          $this_object{memory} = $val;
        }
        elsif ( $key =~ m/address/ ) { $this_object{address} = $val; }
        elsif ( $key =~ m/cpu_info/ ) {
          my @subvals = split "; ", $val;
          foreach my $subval (@subvals) {
            my ( $key, $val ) = split ": ", $subval, 2;
            if    ( $key =~ m/cpu_count/ )    { $this_object{cpu_count}    = $val; }
            elsif ( $key =~ m/socket_count/ ) { $this_object{socket_count} = $val; }
            elsif ( $key =~ m/modelname/ )    { $this_object{cpu_model}    = $val; }
          }
        }
        elsif ( $key =~ m/software-version/ ) {
          my @subvals = split "; ", $val;
          foreach my $subval (@subvals) {
            my ( $key, $val ) = split ": ", $subval, 2;
            if ( $key =~ m/xen/ ) { $this_object{xen} = $val; }
          }
        }
      }
      foreach my $key ( keys %this_object ) {
        $dictionary{specification}{host}{ $this_object{uuid} }{$key} = $this_object{$key} unless ( $key =~ m/uuid/ );
      }
    }

    # VMs
    my $vm_list = $get_output->("xe vm-list params=uuid,name-label,memory-actual,VCPUs-number,VCPUs-at-startup,VCPUs-max,os-version,resident-on");
    my @vms     = split "\n\n\n", $vm_list;
    foreach my $object (@vms) {
      my @params = split "\n", $object;
      my %this_object;
      foreach my $line (@params) {
        my ( $key, $val ) = split ":", $line, 2;
        $key =~ s/^\s+|\s+$//g;
        $val =~ s/^\s+|\s+$//g;
        if ( $val =~ m/Error: Key name not found in map/ ) { next; }
        if ( $val =~ m/^<not in database>$/ )              { $val = ''; }
        if ( $key =~ m/uuid/ )                             { $this_object{uuid} = $val; }
        elsif ( $key =~ m/name-label/ ) { $this_object{name_label} = $val; }
        elsif ( $key =~ m/memory-actual/ ) {
          $val /= 1024**3;    # convert from bytes to GB
          $val = sprintf "%.2f", $val;
          $this_object{memory} = $val;
        }
        elsif ( $key =~ m/VCPUs-number/ )     { $this_object{cpu_count}       = $val; }
        elsif ( $key =~ m/VCPUs-at-startup/ ) { $this_object{cpu_count_start} = $val; }
        elsif ( $key =~ m/VCPUs-max/ )        { $this_object{cpu_count_max}   = $val; }
        elsif ( $key =~ m/os-version/ ) {
          my @subvals = split "; ", $val;
          foreach my $subval (@subvals) {
            my ( $key, $val ) = split ": ", $subval, 2;
            if ( $key =~ m/name/ ) { $this_object{name} = $val; }
          }
        }
        elsif ( $key =~ m/resident-on/ ) { $this_object{parent_host} = $val; }
      }
      foreach my $key ( keys %this_object ) {
        $dictionary{specification}{vm}{ $this_object{uuid} }{$key} = $this_object{$key} unless ( $key =~ m/uuid/ );
      }
    }

    # ad-hoc parent pool for transition to SQLite backend
    my $cmd_hosts  = "xe host-list params=uuid --minimal";
    my $cmd_vms    = "xe vm-list params=uuid --minimal";
    my @hosts_list = $get_values->($cmd_hosts);
    my @vms_list   = $get_values->($cmd_vms);
    foreach my $host (@hosts_list) {
      my $cmd_pool = "xe pool-list params=uuid --minimal";
      my @pools    = $get_values->($cmd_pool);
      $dictionary{specification}{host}{$host}{parent_pool} = ( scalar @pools > 0 ) ? $pools[0] : '';
    }
    foreach my $vm (@vms_list) {
      my $cmd_pool = "xe pool-list params=uuid --minimal";
      my @pools    = $get_values->($cmd_pool);
      $dictionary{specification}{vm}{$vm}{parent_pool} = ( scalar @pools > 0 ) ? $pools[0] : '';
    }

    # get network interfaces
    my $pif_list = $get_output->("xe pif-list params=uuid,device,host-uuid");
    my @pifs     = split "\n\n\n", $pif_list;
    foreach my $object (@pifs) {
      my @params = split "\n", $object;
      my %this_object;
      foreach my $line (@params) {
        my ( $key, $val ) = split ":", $line, 2;
        $key =~ s/^\s+|\s+$//g;
        $val =~ s/^\s+|\s+$//g;
        if    ( $val =~ m/Error: Key name not found in map/ ) { next; }
        if    ( $val =~ m/^<not in database>$/ )              { $val = ''; }
        if    ( $key =~ m/host-uuid/ )                        { $this_object{parent_host} = $val; }
        elsif ( $key =~ m/device/ )                           { $this_object{device} = $val; }
        elsif ( $key =~ m/uuid/ )                             { $this_object{uuid} = $val; }
      }
      foreach my $key ( keys %this_object ) {
        $dictionary{specification}{pif}{ $this_object{uuid} }{$key} = $this_object{$key} unless ( $key =~ m/uuid/ );
      }
    }

    # add storages
    my $sr_list = $get_output->("xe sr-list params=uuid,name-label,type,virtual-allocation,physical-utilisation,physical-size");
    my @srs     = split "\n\n\n", $sr_list;
    foreach my $object (@srs) {
      my @params = split "\n", $object;
      my %this_object;
      foreach my $line (@params) {
        my ( $key, $val ) = split ":", $line, 2;
        $key =~ s/^\s+|\s+$//g;
        $val =~ s/^\s+|\s+$//g;
        if    ( $val =~ m/Error: Key name not found in map/ ) { next; }
        if    ( $val =~ m/^<not in database>$/ )              { $val = ''; }
        if    ( $key =~ m/uuid/ )                             { $this_object{uuid} = $val; }
        elsif ( $key =~ m/name-label/ )                       { $this_object{label} = $val; }
        elsif ( $key =~ m/type/ )                             { $this_object{type} = $val; }
        else {
          if ( $val == -1 ) { next; }
          $val /= 1000**3;    # convert from bytes to GB
          $val = sprintf "%.2f", $val;
          if    ( $key =~ m/virtual-allocation/ )   { $this_object{virtual_allocation}   = $val; }
          elsif ( $key =~ m/physical-utilisation/ ) { $this_object{physical_utilisation} = $val; }
          elsif ( $key =~ m/physical-size/ )        { $this_object{physical_size}        = $val; }
        }
      }
      foreach my $key ( keys %this_object ) {
        $dictionary{specification}{sr}{ $this_object{uuid} }{$key} = $this_object{$key} unless ( $key =~ m/uuid/ );
      }
    }

    # add virtual disks
    my $vdi_list = $get_output->("xe vdi-list params=uuid,name-label,physical-utilisation,virtual-size");
    my @vdis     = split "\n\n\n", $vdi_list;
    foreach my $object (@vdis) {
      my @params = split "\n", $object;
      my %this_object;
      foreach my $line (@params) {
        my ( $key, $val ) = split ":", $line, 2;
        $key =~ s/^\s+|\s+$//g;
        $val =~ s/^\s+|\s+$//g;
        if    ( $val =~ m/Error: Key name not found in map/ ) { next; }
        if    ( $val =~ m/^<not in database>$/ )              { $val = ''; }
        if    ( $key =~ m/uuid/ )                             { $this_object{uuid} = $val; }
        elsif ( $key =~ m/name-label/ )                       { $this_object{label} = $val; }
        else {
          if ( $val == -1 ) { next; }
          $val /= 1000**3;    # convert from bytes to GB
          $val = sprintf "%.2f", $val;
          if    ( $key =~ m/physical-utilisation/ ) { $this_object{physical_utilisation} = $val; }
          elsif ( $key =~ m/virtual-size/ )         { $this_object{virtual_size}         = $val; }
        }
      }
      foreach my $key ( keys %this_object ) {
        $dictionary{specification}{vdi}{ $this_object{uuid} }{$key} = $this_object{$key} unless ( $key =~ m/uuid/ );
      }
    }
  }

  # get relations between pools, hosts and VMs
  {
    my $cmd_pool  = "xe pool-list params=uuid --minimal";
    my $cmd_hosts = "xe host-list params=uuid --minimal";

    my @pools = $get_values->($cmd_pool);
    my @hosts = $get_values->($cmd_hosts);

    if ( scalar @pools > 0 ) {
      $dictionary{architecture}{pool}{ $pools[0] } = \@hosts;
    }

    foreach my $host (@hosts) {
      my $cmd_vm = "xe vm-list resident-on=$host params=uuid --minimal";
      my @vms    = $get_values->($cmd_vm);
      $dictionary{architecture}{host_vm}{$host} = \@vms;
    }
  }

  # get network relations (currently only host-pif)
  {
    my $cmd_pifs = "xe pif-list params=uuid --minimal";
    my @pifs     = $get_values->($cmd_pifs);
    foreach my $pif (@pifs) {
      my $cmd_host = "xe pif-param-get param-name=host-uuid uuid=$pif";
      my $host     = ( $get_values->( $cmd_host, 1 ) )[0];
      push @{ $dictionary{architecture}{network}{host_pif}{$host} }, $pif;
    }
  }

  # get storage relations: (0) pbd=physical device on host (1) sr=LVM volume group, (2) vdi=LVM logical volume, (3) vbd=VM's virtual disk
  # currently, the idea is to present the structure as follows: | sr (host) | vm (vdi) |
  # save relations: (0) sr-hosts (1) vdi-sr (2) vm-vdi
  # i.e., skip pbd and vbd layers
  {
    # get storages (sr)
    my $cmd_sr  = "xe sr-list params=uuid --minimal";
    my @sr_list = $get_values->($cmd_sr);
    foreach my $sr (@sr_list) {
      my $cmd_host = "xe pbd-list params=host-uuid sr-uuid=$sr --minimal";
      my @sr_host  = $get_values->($cmd_host);
      $dictionary{architecture}{storage}{sr_host}{$sr} = \@sr_host;

      # note that the listing excludes snapshots
      my $cmd_vdi        = "xe vdi-list params=uuid sr-uuid=$sr is-a-snapshot=false --minimal";
      my $vdi_cmd_output = ( $get_values->($cmd_vdi) )[0];
      if ( $vdi_cmd_output eq '' ) { next; }
      my @sr_vdi_tmp = $get_values->($cmd_vdi);
      my @sr_vdi;
      foreach my $vdi (@sr_vdi_tmp) {
        push @sr_vdi, $vdi if ($vdi);
      }
      if (@sr_vdi) {
        $dictionary{architecture}{storage}{sr_vdi}{$sr} = \@sr_vdi;
      }
    }

    # vdi-vm
    my $cmd_vbd_vdi = "xe vbd-list params=vdi-uuid --minimal";
    my @vdi_list    = $get_values->($cmd_vbd_vdi);
    foreach my $vdi (@vdi_list) {
      if ( $vdi eq '<not in database>' ) { next; }
      my $cmd_vm = "xe vbd-list params=vm-uuid vdi-uuid=$vdi --minimal";
      my @vdi_vm = $get_values->($cmd_vm);
      $dictionary{architecture}{storage}{vdi_vm}{$vdi} = \@vdi_vm;
    }
  }

  # save as JSON
  my $labels_file = "$metadata_path/xe\_$host.json";
  my $code        = Xorux_lib::write_json( $labels_file, \%dictionary );
}
