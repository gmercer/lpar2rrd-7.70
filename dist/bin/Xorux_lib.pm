#! /usr/bin/perl

package Xorux_lib;

use strict;
use warnings;
use JSON;
use RRDp;
use Data::Dumper;
use File::Temp qw(tempfile);
use File::Copy;
use MIME::Base64 qw( decode_base64 encode_base64 );
use Menu;

my $rrdtool  = $ENV{RRDTOOL};
my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data";

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

# format a status/message as JSON
# originally from `host_cfg.pl`
sub status_json {
  my ( $status, $msg, $log ) = @_;
  $log ||= "";

  # $status = ( $status ) ? "true" : "false";
  my %res = ( success => $status, error => $msg, log => $log );
  print encode_json( \%res );
}

sub create_check {

  # This function check if rrdtool create will be successful finished.
  #
  # Usage:
  #
  # - Program, which calls this function must have:
  #     RRDp::start "$rrdtool";
  #     RRDp::cmd qq(create ...
  #
  # - This function is called:
  #     if (! Xorux_lib::create_check ("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
  #       error ("unable to create $rrd : at ".__FILE__.": line ".__LINE__);
  #       RRDp::end;
  #       RRDp::start "$rrdtool";
  #       return 0;
  #     }
  #     return 1;
  #
  # - return 0 if: RRDp::read error (disc space is full)
  #                rrdtool info error (rrd file is not all)
  #                wrong sum rows (rows in create procedure are not equal as rows in rrdtool info)
  # - else return 1
  # - you can set timeout for alarm in eval

  my $data       = shift;
  my $timeout    = "60";                  ##### timeout for alarm
  my $rrdtool    = $ENV{RRDTOOL};
  my @rrd_create = split( ",", $data );
  my $rrd_file   = "";
  my @create_rows;
  my $index = 0;
  foreach my $line (@rrd_create) {
    chomp $line;
    $line =~ s/"//g;
    if ( $line =~ /^file:/ ) {
      $line =~ s/^file: //g;
      $rrd_file = $line;
      next;
    }
    $index++;
    if ( $line =~ /[0-9]+/ ) {
      $line =~ s/\s+//g;
      push( @create_rows, "$index:$line\n" );
    }
  }
  my $answer = "";
### first check
  eval {
    local $SIG{ALRM} = sub { die "rrdtool read died in SIG ALRM: "; };
    alarm($timeout);
    $answer = RRDp::read;
  };
  alarm(0);
  if ($@) {
    unlink("$rrd_file");
    error("RRDp::create read error : $rrd_file : $@") && return 0;
  }
  if ( defined $answer ) {
    my $answer_i = "";
### second check
    eval {
      local $SIG{ALRM} = sub { die "rrdtool info died in SIG ALRM: "; };
      alarm($timeout);
      RRDp::cmd qq(info "$rrd_file");
      $answer_i = RRDp::read;
    };
    alarm(0);
    if ($@) {
      unlink("$rrd_file");
      error("rrdtool info error : $rrd_file : $@") && return 0;
    }
    my $ret       = $$answer_i;
    my @info_rows = split( "\n", $ret );
    my $index_i   = 0;
    foreach my $line (@info_rows) {
      if ( $line !~ /^rra\[[0-9]\]\.rows/ ) { next; }
      $index_i++;
      $line =~ s/^rra\[[0-9]\]\.rows\s=\s//g;
### third check
      if ( grep {/$index_i:$line/} @create_rows ) {
        next;
      }
      else {
        unlink("$rrd_file");
        error("RRDp error : $rrd_file : wrong sum rows : $line") && return 0;
      }
    }
  }
  return 1;
}

sub RRD_new {
  my ( $class, $daemon ) = @_;
  my $this = {};

  $daemon ||= $ENV{RRDCACHED_ADDRESS};
  defined $daemon or return undef;

  my $sock_family = "INET";

  if ( $daemon =~ m{^unix: | ^/ }x ) {
    $sock_family = "UNIX";
    $daemon =~ s/^unix://;
  }

  my $sock = "IO::Socket::$sock_family"->new($daemon) or return "";

  $sock->printflush("BATCH\n");

  my $go = $sock->getline;
  warn "We didn't get go-ahead from rrdcached" unless $go =~ /^0/;

  $sock->autoflush(0);

  bless {
    sock   => $sock,
    daemon => $daemon,
  }, $class;
}

sub RRD_update {
  my $this = shift;
  my $file = shift;
  ## @updates = @_;

  @_ or error( "No update data for $file " . __FILE__ . ":" . __LINE__ ) && return 0;

  ## rrdcached doesn't handle N: timestamps
  #my $now = time();
  #s/^N(?=:)/$now/ for (@_);

  #print "001 $file @_\n";
  $file =~ s/ /\\ /g;
  $file =~ s/:/\\:/g;
  $this->{sock}->print("update $file @_\n") or error( "update problem for: $file : $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  return 1;
}

sub RRD_done {
  my ($this) = @_;

  my $sock = delete $this->{sock};

  $sock->printflush(".\n");
  my $errs = $sock->getline;

  my ($num_err) = $errs =~ /^(\d+)/;
  return unless $num_err;

  $sock->getline for ( 1 .. $num_err );

  $sock->close;
}

sub rrd_last_update {
  my $filepath    = shift;
  my $last_update = -1;

  RRDp::cmd qq(last "$filepath");
  eval { $last_update = RRDp::read; };

  if ($@) {
    warn( localtime() . ": Failed during read last time $filepath: $@ " . __FILE__ . ":" . __LINE__ );
    return 1;
  }

  chomp $last_update;
  return $last_update;
}

sub write_json {
  my $path        = shift;
  my $hash_ref    = shift;
  my $path_suffix = "$path-tmp" . $$;
  my $json        = JSON->new->utf8;

  my ( $fh, $file_name ) = tempfile( UNLINK => 1 );    #use tempfile instead of the $path_suffix (HD)

  if ( ref($hash_ref) ne "HASH" && ref($hash_ref) ne "ARRAY" ) {
    warn( "Hash ref or array ref expected (path:$path), got: \"$hash_ref\" (Ref:" . ref($hash_ref) . ") in " . __FILE__ . ":" . __LINE__ . "\n" );
    return 0;
  }
  if ( $ENV{JSON_PRETTY} ) {
    $json->pretty( [1] );
  }

  #open( my $FILE, '>', $path_suffix ) || error( "Couldn't open file $path_suffix $! " . __FILE__ . ":" . __LINE__ ) && return 0;
  #print $FILE $json->encode( $hash_ref );
  #close $FILE;
  #rename($path_suffix, $path);

  print $fh $json->encode($hash_ref);
  close($fh);

  copy( $file_name, $path );

  return 1;
}

sub read_json {
  my $file = shift;
  my $json = JSON->new->utf8;
  my $string;
  my $output;

  {
    local $/ = undef;
    open( my $FILE, '<', $file ) or error( "Couldn't open file $file $!" . __FILE__ . ':' . __LINE__ ) && return ( 0, undef );
    $string = <$FILE>;
    close $FILE;
  }

  if ($string) {
    eval {
      $output = $json->decode($string);
      1;
    } or do {
      error( "Couldn't parse json file $file $@ " . __FILE__ . ":" . __LINE__ ) && return ( 0, undef );
    };
  }

  return ( 1, $output );
}

sub uuid_big_endian_format {
  my $uuid       = uc shift;
  my $delimiter  = shift;
  my @uuid_parts = ();

  if ($delimiter) {
    if ( $uuid =~ /(.{8})$delimiter(.{4})$delimiter(.{4})$delimiter(.{4})$delimiter(.{12})/ ) {
      @uuid_parts = ( $1, $2, $3, $4, $5 );
    }
  }
  else {
    @uuid_parts = unpack( "a8 a4 a4 a4 a12", $uuid );
  }

  for ( my $i = 0; $i < 3; $i++ ) {
    $uuid_parts[$i] = join( '', reverse( split /(..)/, $uuid_parts[$i] ) );
  }
  return join( '-', @uuid_parts );
}

sub file_time_diff {
  my $file = shift;

  my $act_time  = time();
  my $file_time = $act_time;
  my $time_diff = 0;
  if ( -f $file ) {
    $file_time = ( stat($file) )[9];
    $time_diff = $act_time - $file_time;
  }

  return ($time_diff);
}

sub urlencode {
  my $s = shift;

  # $s =~ s/ /+/g;
  $s =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  # $s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  return $s;
}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;

  # $s =~ s/\+/ /g;
  return $s;
}

sub parse_url_params {
  my ( $buffer, @pairs, $pair, $name, $value, %PAR );
  $buffer = shift;

  # Split information into name/value pairs
  @pairs = split( /&/, $buffer );
  foreach $pair (@pairs) {
    ( $name, $value ) = split( /=/, $pair );
    unless ( defined $name && $name ne '' && defined $value && $value ne '' ) { next; }
    $value =~ tr/+/ /;
    $value =~ s/%(..)/pack("C", hex($1))/eg;

    # replace HTML tag opening and closing (< >) with entities to prevent XSS
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    if ( exists $PAR{$name} ) {
      if ( ref $PAR{$name} eq "ARRAY" ) {
        push @{ $PAR{$name} }, $value;
      }
      else {
        my $firstVal = $PAR{$name};
        $PAR{$name} = [];
        push @{ $PAR{$name} }, $firstVal;
        push @{ $PAR{$name} }, $value;
      }
    }
    else {
      $PAR{$name} = $value;
    }
  }
  return \%PAR;
}

# VMWARE
# 'url' => '%2Flpar2rrd-cgi%2Fdetail.sh%3Fhost%3D10.22.11.10%26server%3D10.22.11.14%26lpar%3Dvm-tomas-lazy-menu%26item%3Dlpar%26entitle%3D0%26none%3Dnone%26d_platform%3DVMware'

sub url_old_to_new {
  my $url = shift;
  my $params;
  my %out;
  $url = Xorux_lib::urldecode($url);
  $url =~ s/===double-col===/:/g;
  $url =~ s/%20/ /g;
  $url =~ s/%3A/:/g;
  $url =~ s/%2F/&&1/g;
  $url =~ s/%23/#/g;
  $url =~ s/%3B/;/g;

  my $qs = $url;
  my $type;
  my $id;

  #print STDERR "QS 0\n";
  #print STDERR Dumper $qs;
  ( undef, $qs ) = split( "\\?", $qs ) if ( $qs =~ m/\?/ );

  #print STDERR "QS1\n";
  # print STDERR Dumper "Xorux_lib.pm 367",$qs;
  $params = Xorux_lib::parse_url_params($qs);
  if ( !defined $params->{host} || $params->{host} eq "Power" ) {
    return {};
  }

  #print STDERR "PARAMS\n";
  #print STDERR Dumper $params;
  my $ltime = localtime();

  # print STDERR Dumper ("372 Xorux_lib.pm $ltime","\$qs $qs",$params);
  if ( ( exists $params->{d_platform} ) && ( $params->{d_platform} eq "VMware" ) ) {
    require VmwareDataWrapper;
    if ( index( "lpar,vmw-proc,vmw-mem,vmw-diskrw,vmw-iops,vmw-netrw,vmw-swap,vmw-comp,vmw-ready,vmw-vmotion,", $params->{item} . "," ) > -1 ) {
      $type = 'vm';

      # $id  = 'eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_vm_500f7363-b0f9-559e-0f1e-3970d5c3bb0d';
      if ( exists $params->{vm_dbi_uuid} ) {
        $id = $params->{vm_dbi_uuid};
      }
      else {
        $id = VmwareDataWrapper::get_item_uid( $type, $qs );
      }
    }
    elsif ( $params->{item} eq "pool" || $params->{item} eq "lparagg" || $params->{item} eq "memalloc" || $params->{item} eq "memaggreg" || $params->{item} eq "vmdiskrw" || $params->{item} eq "vmnetrw" ) {
      $type = 'pool';

      # $id  = 'eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_vm_500f7363-b0f9-559e-0f1e-3970d5c3bb0d';
      # qs:  host=10.22.11.10&server=10.22.11.9&lpar=pool&item=pool&entitle=0&none=none&d_platform=VMware
      $id   = VmwareDataWrapper::get_item_uid( $type, $qs );
      $type = 'esxi-cpu';
    }
    elsif ( $params->{item} eq "datastore" ) {

      # print STDERR "388 Xorux_lib.pm go for datastore\n";
      $type = 'datastore';
      $id   = VmwareDataWrapper::get_item_uid( $type, "$qs&acl=acl" );

      #$type = 'esxi-cpu';
    }
    elsif ( $params->{item} eq "vtop10" ) {
      $type = 'vcenter';
      $id   = VmwareDataWrapper::get_item_uid( $type, $qs );

      #$id  = 'eb6102a7-1fa0-4376-acbb-f67e34a2212c_28';
      $type = 'hmctotals';
    }
    elsif ( index( "clustcpu,clustlpar,clustmem,clustser,clustlpardy,clustlan,trendcluster,", $params->{item} . "," ) > -1 ) {
      if ( exists $params->{acl} ) {

        # 'server' => 'vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28',
        # 'host' => 'cluster_domain-c87',
        my $id = $params->{server};
        $id =~ s/vmware_//;
        $id = "$id" . "_" . $params->{host};
        $qs = "id=$id";
        return $qs;
      }
      else {
        # host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=clustcpu&time=d&type_sam=m&detail=9&entitle=0&d_platform=VMware&none=-1604668003
        $type = 'clustcpu';
        $id   = VmwareDataWrapper::get_item_uid( $type, $qs );
        $type = 'clustcpu';

        # print STDERR "397 Xorux_lib.pm \$type $type \$id $id\n";
      }
    }
    elsif ( $params->{item} =~ /vm_cluster_totals/ ) {
      $id   = VmwareDataWrapper::get_item_uid( "vm_cluster_totals", $qs );
      $type = 'cluster';
    }
    elsif ( $params->{item} =~ /dstrag_/ ) {

    }
    elsif ( $params->{item} =~ /multihmc/ ) {
      if ( exists $params->{acl} ) {
        my $id = $params->{server};
        $id =~ s/vmware_//;
        $qs = "id=$id";
      }
      return $qs;
    }
    elsif ( $params->{item} eq "rpcpu" || $params->{item} eq "rpmem" || $params->{item} eq "rplpar" ) {

      # print STDERR "422 item = rpcpu\n";
      if ( exists $params->{acl} ) {

        #   'lpar' => 'resgroup-138',
        # 'server' => 'vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28',
        #   'host' => 'cluster_domain-c87',
        #   'item' => 'rpcpu',
        my $id = $params->{server};
        $id =~ s/vmware_//;
        $id = "$id" . "_" . $params->{lpar};
        $qs = "id=$id";
        return $qs;
      }
    }
    elsif ( index( "dsmem,dslat,dsrw,ds-vmiops,dsarw,", $params->{item} . "," ) > -1 ) {
      if ( exists $params->{acl} ) {

        #   'lpar' => '8e7080d6-563de438',
        # 'server' => 'vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28',
        #   'host' => 'datastore_datacenter-2',
        #   'item' => 'dsrw',
        my $id = $params->{server};
        $id =~ s/vmware_//;
        $id = "$id" . "_ds_" . $params->{lpar};
        $qs = "id=$id";
        return $qs;
      }
    }
    else {
      my $x_item = $params->{item};

      # print STDERR localtime()." error Xorux_lib.pm unknown VMWARE item ,$x_item, in url $url\n";
    }

    # print STDERR "350 Xorux_lib.pm \$id $id\n";
    my $menu = Menu->new( lc 'Vmware' );
    if ($id) {
      $url = $menu->page_url( $type, $id );

      #print STDERR "458 Xorux_lib.pm \$type $type \$id $id \$url $url\n";
    }
    else {
      $url = $menu->page_url($type);
    }
    return $url;
  }
  elsif ( defined $params->{platform} && $params->{platform} eq "hyperv" ) {
    my $menu = Menu->new( lc 'Windows' );
    if ( $params->{item} eq "host" ) {
      $type = "pool";

      # qs : 'platform=hyperv&item=host&domain=ad.xorux.com&name=HVNODE01'
      $id = $params->{domain} . "_server_" . $params->{name};
      $id =~ s/^domain_//;    # in case backlink from Cluster Node
    }
    elsif ( $params->{item} eq "vm" ) {
      if ( !defined $params->{vm_uuid} ) {
        $params->{vm_uuid} = $params->{id};
      }
      if ( defined $params->{cluster} ) {
        require WindowsDataWrapper;
        $type = "wvm";

        # necessary to find out domain for server from windows/<hyperv_cluster>/node_list.html
        # this section should be in WindowsDataWrapper.pm (if necessary)
        $id = WindowsDataWrapper::get_item_uid( { type => $type, cluster => $params->{cluster}, host => $params->{host}, vm_uuid => $params->{vm_uuid} } );

        # $id = "ad.xorux.com_server_".$params->{host}."_vm_8127B1FB-FFD6-4A9F-82BC-36CF9F18F03D";
      }
      else {    # not cluster
        $type = "wvm";
        $id   = $params->{domain} . "_server_" . $params->{host} . "_vm_" . $params->{vm_uuid};
      }
    }
    elsif ( $params->{item} eq "volume" ) {
      $id   = $params->{id};
      $type = "s2dvolume";
    }
    elsif ( index( "hyp-cpu,hyp-mem,hyp-disk,hyp-net,", $params->{item} . "," ) > -1 ) {

      #    'lpar' => 'CBD9D469-A221-4228-816F-3860110150AD',
      #    'server' => 'windows/domain_ad.xorux.com',
      #    'host' => 'HVNODE01',
      #    'item' => 'hyp-cpu',
      #    'acl' => 'acl',
      $id = $params->{server};
      $id =~ s/windows\/domain_//;
      $id   = "$id" . "_server_" . $params->{host} . "_vm_" . $params->{lpar};
      $type = "wvm";

    }
    elsif ( index( "pool,memalloc,hyppg1,vmnetrw,hdt_data,hdt_io,lparagg,", $params->{item} . "," ) > -1 ) {

      # 'server' => 'windows/domain_ad.xorux.com',
      # 'host' => 'DC',
      $type = "pool";
      $id   = $params->{server} . "_server_" . $params->{host};
      ( undef, $id ) = split "domain_", $id, 2;
    }
    elsif ( index( "lfd_cat_,lfd_dat_,lfd_io_,lfd_lat_,", $params->{item} . "," ) > -1 ) {

      #if (exist $params->{server}
      $type = "pool";
      $id   = $params->{server} . "_server_" . $params->{host};
      ( undef, $id ) = split "domain_", $id, 2;
    }
    elsif ( index( "hyp_clustsercpu,hyp_clustservms,hyp_clustsermem,hyp_clustser,", $params->{item} . "," ) > -1 ) {

      #          'host' => 'cluster_MSNET-HVCL',
      $type = "pool";
      if ( $params->{host} =~ /cluster_/ ) {
        $id = $params->{host};
        $id =~ s/^cluster_//;
      }
    }
    else {
      #print STDERR "432 unknown hyperv item ,".$params->{item}.", in Xorux_lib.pm\n";
      #return
    }
    if ($id) {
      $url = $menu->page_url( $type, $id );

      #print STDERR "437 Xorux_lib.pm \$type $type \$id $id \$url $url\n";
    }
    else {
      $url = $menu->page_url($type);
    }
    return $url;
  }
  elsif ( defined $params->{d_platform} && $params->{d_platform} eq "Linux" ) {
    my $menu = Menu->new( lc 'Linux' );

    # $id = "pahampl";
    $id   = $params->{lpar};
    $type = "linux";
    $url  = $menu->page_url( $type, $id );

    # print STDERR "550 Xorux_lib.pm \$url $url\n";
    return $url;
  }

### Solaris part
  #print STDERR"XoruxLib|Solaris: $params->{platform}?$params->{item}\n";
  #print STDERR Dumper $params;
  if ( defined $params->{platform} && $params->{platform} eq "solaris" ) {
    if ( $params->{item} =~ /solaris_ldom_cpu|solaris_ldom_mem|solaris_ldom_net/ ) {
      $type = "LDOM";
      $id   = "$params->{host}";

      #print STDERR "===================================\n";
      #print STDERR Dumper $params;
      #print STDERR "===================================\n";
    }
    elsif ( $params->{item} =~ /solaris_zone_cpu|solaris_zone_os_cpu|solaris_zone_mem|solaris_zone_net/ ) {
      $type = "ZONE_L";
      $id   = "$params->{host}";

      #print STDERR "===================================\n";
      #print STDERR Dumper $params;
      #print STDERR "===================================\n";
    }
    elsif ( $params->{item} =~ /oscpu|mem|pg1|pg2|san1|san2|san_resp|jobs|solaris_ldom_*|queue_cpu/ ) {
      if ( $params->{item} !~ /solaris_ldom_agg_c|solaris_ldom_agg_m/ ) {
        $type = "STANDALONE_LDOM";
        $id   = SolarisDataWrapper::get_item_uid( { type => $type, label => $params->{lpar} } );
      }
      else {
        $type = "SOLARIS_TOTAL";
        $id   = "total_solaris";
      }
      my $solaris_dir = "";

      #print STDERR "===================================\n";
      #print STDERR Dumper $params;
      #print STDERR "===================================\n";
    }
    elsif ( $params->{item} =~ /solaris_pool/ ) {
      $type = "LDOM";

      #$id    = SolarisDataWrapper::get_item_uid( { type => $type, label => $params->{host} } );
    }
    my $menu = Menu->new( lc 'Solaris' );
    if ($id) {
      $url = $menu->page_url( $type, $id );

      # print STDERR "598 Xorux_lib.pm \$type $type \$id $id \$url $url\n";
    }
    else {
      $url = $menu->page_url($type);

      # print STDERR "602 Xorux_lib.pm \$type $type \$id $id \$url $url\n";
    }
    return $url;

  }

### POWER part

  require PowerDataWrapper;

  if ( $params->{item} eq "lpar" || $params->{item} eq "trend" || $params->{item} eq "sea" || $params->{item} eq "ssea" || $params->{item} eq "oscpu" || $params->{item} eq "queue_cpu" || $params->{item} eq "jobs" || $params->{item} eq "jobs_mem" || $params->{item} eq "mem" || $params->{item} eq "pg1" || $params->{item} eq "pg2" || $params->{item} eq "lan" || $params->{item} eq "slan" || $params->{item} eq "packets_lan" || $params->{item} eq "san" || $params->{item} eq "san1" || $params->{item} eq "ssan1" || $params->{item} eq "san2" || $params->{item} eq "ssan2" || $params->{item} eq "san_resp" || $params->{item} eq "ame" || $params->{item} eq "wlm-cpu" || $params->{item} eq "wlm-mem" || $params->{item} eq "wlm-dkio" || $params->{item} eq "mem_trend" ) {
    $type = 'vm';
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{lpar} } );
  }
  elsif ( $params->{item} eq "pool" && $params->{lpar} eq "pool" || $params->{item} eq "pool-max" && $params->{lpar} eq "pool" || $params->{item} eq "lparagg" && $params->{lpar} eq "pool-multi" ) {
    $type = "pool";
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{server} } );
  }
  elsif ( $params->{item} eq "shpool" || $params->{item} eq "shpool-max" || $params->{item} eq "poolagg" || $params->{item} eq "trendshpool" || $params->{item} eq "trendshpool-max" ) {
    $type = "shpool";
    my $server_id = PowerDataWrapper::get_item_uid( { type => 'SERVER', label => $params->{server} } );
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{lpar}, parent => $server_id } );
  }
  elsif ( $params->{item} eq "pool-total" || $params->{item} eq "pool-total-max" ) {
    $type = "pool";
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{server} } );
  }
  elsif ( $params->{item} eq "memalloc" || $params->{item} eq "trendmemalloc" ) {
    $type = "memory";
    $id   = PowerDataWrapper::get_item_uid( { type => "server", label => $params->{server} } );
  }
  elsif ( defined $params->{mode} && $params->{mode} eq "power" && defined( $params->{host} ) ) {
    $type = "local_historical_reports";
    $id   = "not_supported_anymore";
  }
  elsif ( defined $params->{mode} && $params->{mode} eq "global" ) {
    $type = "historical_reports";
    $id   = "";
  }
  elsif ( $params->{item} eq "topten" && defined( $params->{server} ) ) {
    $type = "topten";
    $id   = PowerDataWrapper::get_item_uid( { type => "server", label => $params->{server} } );
  }
  elsif ( $params->{item} eq "view" && defined( $params->{server} ) ) {
    $type = "view";
    $id   = PowerDataWrapper::get_item_uid( { type => "server", label => $params->{server} } );
  }
  elsif ( $params->{item} =~ "power_" && $params->{lpar} !~ m/totals/ ) {
    $type = $params->{item};
    $type =~ s/power_//g;
    $type =~ s/_.*//g;
    my $label = $params->{lpar};
    $label =~ s/\..*//g;
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_lan" && $params->{lpar} =~ m/totals/ ) {
    $type = "lan-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_san" && $params->{lpar} =~ m/totals/ ) {
    $type = "san-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_sas" && $params->{lpar} =~ m/totals/ ) {
    $type = "sas-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_hea" && $params->{lpar} =~ m/totals/ ) {
    $type = "hea-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_sri" && $params->{lpar} =~ m/totals/ ) {
    $type = "sri-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "lparagg" ) {
    $type = "vm-aggr";
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{server} } );
  }
  elsif ( $params->{item} =~ "hmctotals" ) {
    $type = "hmc-totals";
    $id   = "";
  }
  else {
    #   print STDERR "!!!!!!!!!!!!!!!!!!!!!!!!! not implemented $params->{item} ($params->{lpar}) in power\n";
    return;
  }

  my $menu = Menu->new( lc 'Power' );
  if ($id) {
    $url = $menu->page_url( $type, $id );
  }
  else {
    $url = $menu->page_url($type);
  }

  if ( !defined $url ) {
    $url = "";
  }
  return $url;
}

sub isdigit {
  my $digit = shift;

  if ( !defined($digit) ) {
    return 0;
  }
  if ( $digit eq '' ) {
    return 0;
  }

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/^-//;
  $digit_work =~ s/e//;
  $digit_work =~ s/\+//;
  $digit_work =~ s/\-//;

  if ( length($digit_work) == 0 ) {

    # is a number
    return 1;
  }

  # NOT a number
  return 0;
}

sub calculate_weighted_avg {
  my $data = shift;
  my $deb  = shift;    # is not mandatory

  # data must be in this format (array of hashes):
  #$VAR1 = [
  #          {
  #            'count' => '3.413',
  #            'value' => '3.660'
  #          },
  #          ...
  #          {
  #            'value' => '0.902',
  #            'count' => '663.150'
  #          }
  #        ];

  my $sum         = "";
  my $value_total = "";
  my $value_idx   = 0;

  if ( ref($data) eq "ARRAY" ) {
    foreach ( @{$data} ) {

      #if ( exists $_->{count} && isdigit($_->{count}) && exists $_->{value} && isdigit($_->{value}) ) {
      if ( exists $_->{count} && isdigit( $_->{count} ) && $_->{count} != 0 && exists $_->{value} && isdigit( $_->{value} ) ) {
        if ( isdigit($sum) ) {
          $sum += $_->{count};
        }
        else {
          $sum = $_->{count};
        }

        if ( isdigit($value_total) ) {
          $value_total += $_->{value} * $_->{count};
        }
        else {
          $value_total = $_->{value} * $_->{count};
        }
        $value_idx++;
      }
    }
  }
  if ( $value_idx > 0 ) {
    my $weighted_avg = sprintf( '%.4f', $value_total / $sum );

    # debug
    #$deb = 1;
    if ($deb) {
      print Dumper $data;
      print "$weighted_avg = $value_total / $sum\n";
    }

    return $weighted_avg;
  }
  else {
    return undef;
  }
}

sub human_vmware_name {
  my $lpar  = shift;
  my $arrow = shift;

  $arrow = "" if !defined $arrow;

  my $vms_dir    = "vmware_VMs";
  my $trans_file = "$wrkdir/$vms_dir/vm_uuid_name.txt";

  # print STDERR "13770 $wrkdir/$vms_dir/vm_uuid_name.txt \n";
  if ( -f "$trans_file" ) {
    my $name      = "";
    my $file_time = 0;

    # there can be more UUID for same Vm name when param is 'neg', choose latest one
    open( FR, "< $trans_file" );
    foreach my $linep (<FR>) {
      chomp($linep);

      # print STDERR "12956 $linep\n";
      ( my $id, my $name_tmp, undef ) = split( /,/, $linep );
      if ( "$arrow" eq "neg" ) {
        ( $name_tmp, $id, undef ) = split( /,/, $linep );

        # print STDERR "12960 \$id $id \$lpar $lpar\n";
        if ( "$id" eq "$lpar" ) {
          next if !-f "$wrkdir/$vms_dir/$name_tmp.rrm";
          my $act_file_time = ( stat("$wrkdir/$vms_dir/$name_tmp.rrm") )[9];
          if ( $act_file_time > $file_time ) {
            $file_time = $act_file_time;
            $name      = $name_tmp;

            # print STDERR "11630 \$name $name \$file_time $file_time\n";
          }
        }
      }
      else {
        if ( "$id" eq "$lpar" ) {
          $name = $name_tmp;
          last;
        }
      }
    }
    close(FR);
    $lpar = "$name" if $name ne "";
  }
  return "$lpar";    #human name - if found, or original
}

####################################################################
#   send email using sendmail or via SMTP (if it's configured in Alerting)
#
#   parameters are self explaining...
#   $body can be HTML formatted if $use_html is used and true
#   $mailfrom is optional
#   $attachments [optional] should be an array ref. containing list of filepaths to be attached
#   $filenames [optional] should be an array ref. containing list of strings to rename corresponding $attachments

sub send_email {
  my ( $mailto, $mailfrom, $subject, $body, $attachments, $filenames, $use_html ) = @_;

  use Mime::Lite;
  require Alerting;
  my $errors;
  my $cfg = Alerting::getConfigRef();

  $mailfrom ||= $cfg->{MAILFROM} ? $cfg->{MAILFROM} : "";
  my $body_format = $use_html ? "text/html" : "TEXT";

  my $smtp_options = {
    host     => $cfg->{SMTP_HOST},
    port     => $cfg->{SMTP_PORT},
    from     => $mailfrom,
    to       => $mailto,
    username => $cfg->{SMTP_USER},
    password => $cfg->{SMTP_PASS},
    method   => $cfg->{SMTP_AUTH},
    ssl      => 0,
    tls      => 0,
  };

  my $msg = MIME::Lite->new(
    From    => $mailfrom,
    To      => $mailto,
    Subject => $subject,
    Type    => $body_format,
    Data    => $body,
  );

  if ( defined $attachments && scalar @$attachments ) {
    use File::Basename;
    my $idx = 0;
    foreach my $file_to_attach (@$attachments) {
      if ( -e $file_to_attach && -f _ && -r _ ) {
        my ( $filename, $filepath, $suffix ) = fileparse( $file_to_attach, qr"\..[^.]*$" );
        my $content_type = get_mime_type($suffix);
        if ($content_type) {
          if ( defined $filenames && @{$filenames}[$idx] ) {
            $filename = @{$filenames}[$idx];
          }
          $msg->attach(
            Type     => $content_type,
            Path     => $file_to_attach,
            Filename => $filename
          );
        }
      }
      $idx++;
    }
  }

  if ( $cfg->{SMTP_HOST} ) {    # use Net::SMTP if SMTP_HOST defined
    if ( !$cfg->{SMTP_PORT} ) {
      $smtp_options->{port} = 25;
    }
    if ( !$cfg->{SMTP_AUTH} ) {
      $smtp_options->{method} = 'PLAIN';
    }

    if ( $cfg->{SMTP_ENC} ) {
      if ( $cfg->{SMTP_ENC} eq "ssl" ) {
        $smtp_options->{ssl} = 1;
        if ( !$cfg->{SMTP_PORT} ) {
          $smtp_options->{port} = 465;
        }
      }
      elsif ( $cfg->{SMTP_ENC} eq "tls" ) {
        $smtp_options->{tls} = 1;
      }
    }
    $errors .= $msg->send( 'sub', \&send_net_smtp, $smtp_options );
  }
  else {    # send using sendmail
    $errors .= $msg->send();
  }

  if ( !$errors ) {
    return ( 0, "" );
  }
  else {
    return ( 1, "$errors" );
  }
}

sub send_net_smtp {
  use Net::SMTP;
  my ( $msg, $options ) = @_;

  # warn Dumper $options;
  # warn $msg->as_string;
  close(STDERR);
  my $errlog;
  open( STDERR, ">>", \$errlog ) or do {
    return "failed to open STDERR ($!)\n";
  };

  my $smtp = Net::SMTP->new(
    "$options->{host}:$options->{port}",
    SSL             => $options->{ssl},
    Debug           => 1,
    SSL_verify_mode => 0,
    Timeout         => 20,
  );

  if ( !$smtp ) {
    return "ERROR: could not connect to mail server! ( $! )";
  }

  if ( $options->{tls} ) {
    if ( !$smtp->starttls() ) {
      return "ERROR: could not STARTTLS\n$errlog";
    }
  }

  if ( $options->{username} ) {
    use Authen::SASL;

    my $sasl = Authen::SASL->new(
      mechanism => $options->{method},
      callback  => {
        pass => unobscure_password( $options->{password} ),
        user => $options->{username},
      }
    );

    # warn "Authenticating using $options->{method} method...";
    if ( !$smtp->auth($sasl) ) {
      return "ERROR: authentication failed\n$errlog";
    }
  }

  $smtp->mail( $options->{from} );    # SMTP: MAIL FROM
  $smtp->to( $options->{to} );        # SMTP: RCPT TO
  $smtp->data();                      # SMTP: DATA
  $smtp->datasend( $msg->as_string );
  $smtp->dataend();                   # SMTP: .

  $smtp->quit();                      # SMTP: QUIT

  return;

}

sub get_mime_type {
  my $suffix = shift;
  if ( defined $suffix ) {
    use File::Basename;
    my %mime_types = (
      '.jpg'  => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.png'  => 'image/png',
      '.zip'  => 'application/zip',
      '.pdf'  => 'application/pdf',
      '.csv'  => 'text/csv'
    );
    return $mime_types{$suffix};
  }
  return "";
}

sub unobscure_password {
  my $string    = shift;
  my $unobscure = decode_base64($string);
  $unobscure = unpack( chr( ord("a") + 19 + print "" ), $unobscure );
  return $unobscure;
}

1;
