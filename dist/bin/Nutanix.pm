package Nutanix;

use strict;
use warnings;

use HTTP::Request;
use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;

my $timeout = 120;

sub new {
  my ( $self, $protocol, $ip, $port, $username, $password ) = @_;

  my $o = {};
  $o->{protocol} = $protocol;
  $o->{ip}       = $ip;
  $o->{port}     = $port;
  $o->{username} = $username;
  $o->{password} = $password;
  bless $o;

  return $o;
}

sub getClusters {
  my ( $self, $api ) = @_;
  my ( $data, $url );
  if ( $api eq "v3" ) {
    $data = "{\"kind\":\"cluster\"}";
    $url  = "clusters/list";
    return decode_json_eval( $self->restCallv3( $url, $data ) );
  }
  elsif ( $api eq "v2" ) {
    return decode_json_eval( $self->restCallv2( "clusters/?projection=BASIC_INFO", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "clusters/?projection=BASIC_INFO", " ", "GET" ) );
  }
}

sub getNodes {
  my ( $self, $api ) = @_;
  my ( $data, $url );
  if ( $api eq "v3" ) {
    $data = "{\"kind\":\"host\"}";
    $url  = "hosts/list";
    return decode_json_eval( $self->restCallv3( $url, $data ) );
  }
  elsif ( $api eq "v2" ) {
    return decode_json_eval( $self->restCallv2( "hosts/?projection=BASIC_INFO", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "hosts/?projection=BASIC_INFO", " ", "GET" ) );
  }
}

sub getNodePerf {
  my ( $self, $uuid, $metrics, $start, $end, $interval, $api ) = @_;
  if ( $api eq "v2" || $api eq "v3" ) {
    return decode_json_eval( $self->restCallv2( "hosts/$uuid/stats/?metrics=$metrics&start_time_in_usecs=" . $start . "000000&end_time_in_usecs=" . $end . "000000&interval_in_secs=$interval", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "hosts/$uuid/stats/?metrics=$metrics&startTimeInUsecs=" . $start . "000000&endTimeInUsecs=" . $end . "000000&intervalInSecs=$interval", " ", "GET" ) );
  }
}

sub getVMs {
  my ( $self, $api, $page_max, $page ) = @_;
  my ( $data, $url );
  my $start = ($page - 1) * $page_max;
  if ( $api eq "v3" ) {
    $data = "{\"kind\":\"vm\", \"offset\": $start, \"length\": $page_max}";
    $url  = "vms/list";
    return decode_json_eval( $self->restCallv3( $url, $data ) );
  }
  elsif ( $api eq "v2" ) {
    return decode_json_eval( $self->restCallv2( "vms/?offset=" . $start . "&length=" . $page_max . "&projection=BASIC_INFO", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "vms/?count=" . $page_max . "&page=" . $page . "&projection=BASIC_INFO", " ", "GET" ) );
  }
}

sub getVMPerf {
  my ( $self, $uuid, $metrics, $start, $end, $interval ) = @_;
  return decode_json_eval( $self->restCallv1( "vms/$uuid/stats/?metrics=$metrics&startTimeInUsecs=" . $start . "000000&endTimeInUsecs=" . $end . "000000&intervalInSecs=$interval", " ", "GET" ) );
}

sub getDisks {
  my ( $self, $api, $page_max, $page ) = @_;
  if ( $api eq "v2" || $api eq "v3" ) {
    return decode_json_eval( $self->restCallv2( "disks/?count=" . $page_max . "&page=" . $page . "&?projection=BASIC_INFO", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "disks/?count=" . $page_max . "&page=" . $page . "&?projection=BASIC_INFO", " ", "GET" ) );
  }
}

sub getDiskPerf {
  my ( $self, $uuid, $metrics, $start, $end, $interval, $api ) = @_;
  if ( $api eq "v2" || $api eq "v3" ) {
    return decode_json_eval( $self->restCallv2( "disks/$uuid/stats/?metrics=$metrics&start_time_in_usecs=" . $start . "000000&end_time_in_usecs=" . $end . "000000&interval_in_secs=$interval", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "disks/$uuid/stats/?metrics=$metrics&startTimeInUsecs=" . $start . "000000&endTimeInUsecs=" . $end . "000000&intervalInSecs=$interval", " ", "GET" ) );
  }
}

sub getStorageContainers {
  my ( $self, $api ) = @_;
  my ( $data, $url );
  if ( $api eq "v2" || $api eq "v3" ) {
    return decode_json_eval( $self->restCallv2( "storage_containers/?projection=BASIC_INFO", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "containers/?projection=BASIC_INFO", " ", "GET" ) );
  }
}

sub getStorageContainerPerf {
  my ( $self, $uuid, $metrics, $start, $end, $interval, $api ) = @_;
  if ( $api eq "v2" || $api eq "v3" ) {
    return decode_json_eval( $self->restCallv2( "storage_containers/$uuid/stats/?metrics=$metrics&start_time_in_usecs=" . $start . "000000&end_time_in_usecs=" . $end . "000000&interval_in_secs=$interval", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "containers/$uuid/stats/?metrics=$metrics&startTimeInUsecs=" . $start . "000000&endTimeInUsecs=" . $end . "000000&intervalInSecs=$interval", " ", "GET" ) );
  }
}

sub getStoragePools {
  my ( $self, $api ) = @_;
  my ( $data, $url );
  if ( $api eq "v2" || $api eq "v3" || $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "storage_pools/", " ", "GET" ) );
  }
}

sub getStoragePoolPerf {
  my ( $self, $uuid, $metrics, $start, $end, $interval, $api ) = @_;
  if ( $api eq "v2" || $api eq "v3" || $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "storage_pools/$uuid/stats/?metrics=$metrics&startTimeInUsecs=" . $start . "000000&endTimeInUsecs=" . $end . "000000&intervalInSecs=$interval", " ", "GET" ) );
  }
}

sub getVdisks {
  my ( $self, $api, $page_max, $page ) = @_;
  if ( $api eq "v2" || $api eq "v3" ) {
    return decode_json_eval( $self->restCallv2( "virtual_disks/?count=" . $page_max . "&page=" . $page . "&?projection=BASIC_INFO", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "virtual_disks/?count=" . $page_max . "&page=" . $page . "&?projection=BASIC_INFO", " ", "GET" ) );
  }
}

sub getVdiskPerf {
  my ( $self, $uuid, $metrics, $start, $end, $interval, $api ) = @_;
  if ( $api eq "v2" || $api eq "v3" ) {
    return decode_json_eval( $self->restCallv2( "virtual_disks/$uuid/stats/?metrics=$metrics&start_time_in_usecs=" . $start . "000000&end_time_in_usecs=" . $end . "000000&interval_in_secs=$interval", " ", "GET" ) );
  }
  elsif ( $api eq "v1" ) {
    return decode_json_eval( $self->restCallv1( "virtual_disks/$uuid/stats/?metrics=$metrics&startTimeInUsecs=" . $start . "000000&endTimeInUsecs=" . $end . "000000&intervalInSecs=$interval", " ", "GET" ) );
  }
}

sub getEvents {
  my ( $self, $start ) = @_;
  return decode_json_eval( $self->restCallv2( "events/?start_time_in_usecs=" . $start . "000000", " ", "GET" ) );
}

sub getAlerts {
  my ( $self, $start ) = @_;
  return decode_json_eval( $self->restCallv2( "alerts/?start_time_in_usecs=" . $start . "000000", " ", "GET" ) );
}

sub getItemHealth {
  my ( $self, $item ) = @_;
  return decode_json_eval( $self->restCallv1( "$item?projection=health", " ", "GET" ) );
}

sub getHealthCheck {
  my ( $self, $item ) = @_;
  return decode_json_eval( $self->restCallv2( "health_checks/$item/", " ", "GET" ) );
}

sub getHealthSummary {
  my ($self) = @_;
  return decode_json_eval( $self->restCallv1( "ncc/run_summary/", " ", "GET" ) );
}

sub setTls {
  my ( $self, $tls ) = @_;
  $self->{tls} = $tls;
  return 1;
}

#v3 for Prism Central
sub restCallv3() {
  my ( $self, $url, $data ) = @_;

  my $ua;
  if ( defined $self->{tls} ) {
    $ua = LWP::UserAgent->new(
      timeout  => $timeout,
      ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0, SSL_version => $self->{tls} },
    );
  }
  else {
    $ua = LWP::UserAgent->new(
      timeout  => $timeout,
      ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
    );
  }

  my $header  = [ 'Content-Type' => 'application/json; charset=UTF-8' ];
  my $request = HTTP::Request->new( 'POST', $self->{protocol} . "://" . $self->{ip} . ":" . $self->{port} . "/api/nutanix/v3/$url", $header, $data );

  $request->authorization_basic( $self->{username}, $self->{password} );
  my $response = $ua->request($request);

  if ( $response->is_success ) {
    return $response->content;
  }
  else {
    error( "ERROR: Can't handle request (".$url."): " . Dumper( $response->content ) );
    return ();
  }
}

#v2 for Prism Element
sub restCallv2 {
  my ( $self, $url, $data, $method ) = @_;

  my $ua;
  if ( defined $self->{tls} ) {
    $ua = LWP::UserAgent->new(
      timeout  => $timeout,
      ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0, SSL_version => $self->{tls} },
    );
  }
  else {
    $ua = LWP::UserAgent->new(
      timeout  => $timeout,
      ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
    );
  }

  my $header  = [ 'Content-Type' => 'application/json; charset=UTF-8' ];
  my $request = HTTP::Request->new( $method, $self->{protocol} . "://" . $self->{ip} . ":" . $self->{port} . "/PrismGateway/services/rest/v2.0/$url", $header, $data );

  $request->authorization_basic( $self->{username}, $self->{password} );
  my $response = $ua->request($request);

  if ( $response->is_success ) {
    return $response->content;
  }
  else {
    error( "ERROR: Can't handle request (".$url."): " . Dumper( $response->content ) );
    return ();
  }
}

#v1 for Prism Element
sub restCallv1 {
  my ( $self, $url, $data, $method ) = @_;

  my $ua;
  if ( defined $self->{tls} ) {
    $ua = LWP::UserAgent->new(
      timeout  => $timeout,
      ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0, SSL_version => $self->{tls} },
    );
  }
  else {
    $ua = LWP::UserAgent->new(
      timeout  => $timeout,
      ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
    );
  }

  my $header  = [ 'Content-Type' => 'application/json; charset=UTF-8' ];
  my $request = HTTP::Request->new( $method, $self->{protocol} . "://" . $self->{ip} . ":" . $self->{port} . "/PrismGateway/services/rest/v1/$url", $header, $data );

  $request->authorization_basic( $self->{username}, $self->{password} );
  my $response = $ua->request($request);

  if ( $response->is_success ) {
    return $response->content;
  }
  else {
    error( "ERROR: Can't handle request (".$url."): " . Dumper( $response->content ) );
    return ();
  }
}

sub decode_json_eval {
  my ($json) = @_;
  my $hash = ();
  eval { $hash = decode_json($json); };
  if ($@) {
    my $error = $@;
    #error($error);
    return ();
  }
  else {
    return $hash;
  }
}

sub log {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "[$act_time]: $text \n";
  return 1;
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print STDERR "$act_time: $text : $!\n";
  return 1;
}

sub error_die {
  my $message  = shift;
  my $act_time = localtime();
  print STDERR "$act_time: $message : $!\n";
  exit(1);
}

1;
