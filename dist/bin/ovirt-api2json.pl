# ovirt-api2json.pl
#   fetch data dump from oVirt REST API, only storage domains and disks for now
#   output: json file for each host in data/oVirt/iostats/restapi

use strict;
use warnings;

use JSON qw(decode_json encode_json);
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use Time::Local;
use POSIX;

use HostCfg;
use OVirtDataWrapper;
use Xorux_lib;

my $inputdir    = $ENV{INPUTDIR};
my $path_prefix = "$inputdir/data/oVirt/iostats/restapi";
require "$inputdir/bin/xml.pl";

unless ( -d $path_prefix ) {
  mkdir( $path_prefix, 0755 ) || warn( 'Cannot mkdir ' . "$path_prefix : $!" . __FILE__ . ':' . __LINE__ );
}

################################################################################

my $touch_file    = "$inputdir/tmp/oVirt_getrestapi.touch";
my $generate_time = localtime();

if ( !-f $touch_file ) {
  `touch $touch_file`;
  print 'ovirt-api2json.pl : first run, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day ) {
    print 'ovirt-api2json.pl : already ran today, skip' . "\n";
    exit 0;    # run just once a day
  }
  else {
    `touch $touch_file`;
    print 'ovirt-api2json.pl : get REST API data, ' . localtime() . "\n";
  }
}

################################################################################

my $url_host = my $url_port = my $login_username = my $login_password = '';

if ( scalar(@ARGV) >= 4 ) {

  # expected four parameters <host> <port> <username> <password>
  ( $url_host, $url_port, $login_username, $login_password ) = @ARGV;
  get_data_from_host( $url_host, $url_port, $login_username, $login_password );
}
else {
  my %hosts = %{ HostCfg::getHostConnections('RHV (oVirt)') };

  foreach my $alias ( keys %hosts ) {
    unless ( defined $hosts{$alias}{auth_api} && $hosts{$alias}{auth_api} ) { next; }

    $url_host       = $hosts{$alias}{api_hostname};
    $url_port       = $hosts{$alias}{api_port2};
    $login_username = $hosts{$alias}{api_username};
    $login_password = HostCfg::unobscure_password( $hosts{$alias}{api_password} );
    get_data_from_host( $url_host, $url_port, $login_username, $login_password );
  }
}

exit 0;

################################################################################

sub get_data_from_host {
  my $host     = shift;
  my $port     = shift;
  my $username = shift;
  my $password = shift;

  # currently, there are queries for
  # - storage domains
  # - virtual disks
  # - virtual disks attached to VMs (one query per VM)

  my $api_path = 'ovirt-engine/api';
  my @queries = ( 'storagedomains', 'disks', 'vms' );
  foreach my $query (@queries) {
    my $api_url   = 'https://' . $host . ':' . $port . '/' . $api_path . '/' . $query;
    my $xml_file  = $path_prefix . '/' . $host . '-' . $query . '-last.xml';
    my $json_file = $path_prefix . '/' . $host . '-' . $query . '-last.json';

    if ( $query eq 'vms' ) {
      my $arch_vm = OVirtDataWrapper::get_conf_section('arch-vm');
      my %data;

      foreach my $vm ( keys %{$arch_vm} ) {
        my $api_url_2 = $api_url . '/' . $vm . '/diskattachments';
        my %item_data = %{ get_data_from_api( $xml_file, $api_url_2, $host, $port, $username, $password ) };

        if ( ref( \%item_data ) ne 'HASH' && ref( \%item_data ) ne 'ARRAY' ) {
          warn( 'Hash ref or array ref expected, got: ' . %item_data . ' (Ref:' . ref(%item_data) . ') in ' . __FILE__ . ':' . __LINE__ . "\n" );
          next;
        }

        foreach my $item ( @{ $item_data{'disk_attachment'} } ) {
          push @{ $data{$vm} }, %item_data;
        }

        unlink $xml_file;
      }

      open my $JSON_FH, '>', "$json_file" || die "error: cannot save the JSON $json_file.\n";
      print $JSON_FH JSON->new->pretty->encode( \%data );
      close $JSON_FH;
    }
    else {
      my %data = %{ get_data_from_api( $xml_file, $api_url, $host, $port, $username, $password ) };

      if ( ref( \%data ) ne 'HASH' && ref( \%data ) ne 'ARRAY' ) {
        warn( 'Hash ref or array ref expected, got: ' . %data . ' (Ref:' . ref(%data) . ') in ' . __FILE__ . ':' . __LINE__ . "\n" );
        next;
      }

      my $query_tag = ( $query eq 'storagedomains' ) ? 'storage_domain' : 'disk';
      foreach my $item ( @{ $data{$query_tag} } ) {
        if ( exists $item->{actions} ) { delete $item->{actions}; }
        if ( exists $item->{link} )    { delete $item->{link}; }
        # workaround for issues with text encoding in description fields
        if ( exists $item->{description} ) { delete $item->{description}; }
      }

      open my $JSON_FH, '>', "$json_file" || die "error: cannot save the JSON $json_file.\n";
      print $JSON_FH JSON->new->pretty->encode( \%data );
      close $JSON_FH;

      unlink $xml_file;
    }
  }

  return;
}

################################################################################

sub get_data_from_api {
  my $xml_file = shift;
  my $url      = shift;
  my $host     = shift;
  my $port     = shift;
  my $username = shift;
  my $password = shift;

  my $ua = LWP::UserAgent->new( ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 } );
  my $req = HTTP::Request->new( GET => $url );
  $req->content_type('application/xml');
  $req->header( 'Accept' => '*/*' );
  $req->authorization_basic( "$username", "$password" );
  my $res = $ua->request($req);
  if ( $res->is_success ) {
    if ( $res->{_content} eq '' ) {
      die "error: empty database dump\n";
    }
    else {
      open my $XML_FH, '>', "$xml_file" || die "error: cannot save the received XML file\n";
      print $XML_FH "$res->{_content}\n";
      close $XML_FH;
    }
  }
  else {
    die 'error: ' . $res->status_line . "\n";
  }

  my $data;
  my $xml_simple = XML::Simple->new( keyattr => [], ForceArray => 1 );

  eval { $data = $xml_simple->XMLin($xml_file); };
  if ($@) {
    message("XML parsing error: $@");
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

  #unlink $xml_file;
  return $data;
}
