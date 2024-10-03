package FusionCompute;

use strict;
use warnings;

use HTTP::Request::Common;
use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;

my $version = "v8.0";

sub new {
  my ( $self, $protocol, $ip, $port, $f_version ) = @_;

  $version = defined $f_version ? $f_version : $version;

  my $o = {};
  $o->{protocol} = $protocol;
  $o->{ip}       = $ip;
  $o->{port}     = $port;
  bless $o;

  return $o;
}

sub auth {
  my ( $self, $username, $password, $usertype, $encrypted ) = @_;

  $encrypted = ( defined $encrypted ) ? $encrypted : 1;

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header( 'Accept'          => "application/json;version=" . $version );
  $ua->default_header( 'Content-type'    => "application/json" );
  $ua->default_header( 'Accept-Language' => "en_US" );
  $ua->default_header( 'X-Auth-User'     => $username );
  $ua->default_header( 'X-Auth-Key'      => $password );
  $ua->default_header( 'X-Auth-UserType' => "$usertype" );
  $ua->default_header( 'X-Auth-AuthType' => "0" );

  if ( $encrypted eq "0" ) {
    $ua->default_header( 'X-ENCRIPT-ALGORITHM' => "1" );
  }

  my $url = $self->{ip} . ":" . $self->{port} . "/service/session";

  my $req      = HTTP::Request->new( 'POST', $self->{protocol} . "://" . $url );
  my $response = $ua->request($req);
  my $hash     = toHash( $response->content );

  if ( defined $hash ) {
    $self->{token} = $response->header('X-Auth-Token');
  }
  else {
    return 0;
  }

}

# Sites

sub listSites {
  my ($self) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

# Clusters

sub listClusters {
  my ( $self, $site_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/clusters";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getCluster {
  my ( $self, $site_id, $cluster_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/clusters/" . $cluster_id;
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getClusterResources {
  my ( $self, $site_id, $cluster_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/clusters/" . $cluster_id . "/computeresource";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getClusterVmResources {
  my ( $self, $site_id, $cluster_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/clusters/" . $cluster_id . "/allvmcomputeresource";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

# Hosts

sub listHosts {
  my ( $self, $site_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/hosts";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getHost {
  my ( $self, $site_id, $host_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/hosts/" . $host_id;
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getHostResources {
  my ( $self, $site_id, $host_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/hosts/" . $host_id . "/computeResourceStatics";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getHostsStatistics {
  my ( $self, $site_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/hosts/statistics";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

# VM --! add limit & offset parameter

sub listVMs {
  my ( $self, $site_id, $limit, $offset ) = @_;

  if ( !defined $limit ) {
    $limit = 100;
  }

  if ( !defined $offset ) {
    $offset = 0;
  }

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/vms?limit=" . $limit . "&offset=" . $offset;
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getVMsStatistics {
  my ( $self, $site_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/vms/statistics";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getVM {
  my ( $self, $site_id, $vm_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/vms/" . $vm_id;
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

# Datastore

sub listDatastores {
  my ( $self, $site_id ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/datastores";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

# Alarms

sub getActiveAlarms {
  my ( $self, $site_id ) = @_;

  my %data;
  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/alarms/activeAlarms";
  my $resp = $self->apiRequest( "POST", $url, \%data );

  return $resp;
}

# Monitoring

sub getMetrics {
  my ( $self, $site_id, $item_id, $metrics, $start, $end, $interval ) = @_;

  my @data_array;
  for my $item ( @{$metrics} ) {
    my %data = (
      "urn"       => $item_id,
      "metricId"  => $item,
      "startTime" => $start,
      "endTime"   => $end,
      "interval"  => $interval
    );
    push( @data_array, \%data );
  }

  my $url  = $self->{ip} . ":" . $self->{port} . "/service/sites/" . $site_id . "/monitors/objectmetric-curvedata";
  my $resp = $self->apiRequest( "POST", $url, \@data_array );

  return $resp;
}

# Other methods

sub apiRequest {
  my ( $self, $type, $url ) = @_;

  my $data = ();
  if ( defined $_[3] ) {
    $data = $_[3];
  }

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header( 'Accept'          => "application/json;version=" . $version );
  $ua->default_header( 'Content-type'    => "application/json" );
  $ua->default_header( 'Accept-Language' => "en_US" );
  $ua->default_header( 'X-Auth-Token'    => $self->{token} );

  my $resp = $json->decode("{}");

  if ( $type eq "GET" ) {
    eval {
      my $req      = HTTP::Request->new( 'GET', $self->{protocol} . "://" . $url );
      my $response = $ua->request($req);
      $resp = $json->decode( $response->content );
    };

    if ($@) {
      my $error = $@;
      error_die($error);
    }
  }
  elsif ( $type eq "POST" ) {
    eval {
      my $req = HTTP::Request->new( 'POST', $self->{protocol} . "://" . $url );
      if ( defined $data ) {
        $req->content( encode_json($data) );
      }
      my $response = $ua->request($req);
      $resp = $json->decode( $response->content );
    };

    if ($@) {
      my $error = $@;
      error_die($error);
    }
  }
  else {
    return ();
  }

  return $resp;

}

sub is_error {
  my $code  = shift;
  my $first = substr( $code, 0, 1 );
  if ( $first eq "4" || $first eq "5" ) {
    return 1;
  }
  else {
    return 0;
  }
}

sub error_code {
  my $code        = shift;
  my %error_codes = (
    "400" => "Bad Request - The request could not be understood by the server due to malformed syntax.",
    "401" => "Unauthorized - The request requires user authentication.",
    "403" => "Forbidden - The server understood the request, but is refusing to fulfill it.",
    "404" => "Not Found - The server has not found anything matching the Request-URI.",
    "405" => "Method Not Allowed - The HTTP verb specified in the request is not supported for this request URI.",
    "409" => "Conflict - A creation or update request could not be completed, because it would cause a conflict in the current state of the resources supported by the platform.",
    "500" => "Internal Host Error - The server encountered an unexpected condition which prevented it from fulfilling the request.",
    "501" => "Not Impelmented - The server does not support the functionality required to fulfill the request.",
    "503" => "Service Unavailable - The server is currently unable to handle the request due to temporary overloading or maintenance of the server."
  );
  if ( defined $error_codes{$code} ) {
    return $error_codes{$code};
  }
  else {
    return ();
  }
}

sub toHash {
  my $originalJson = shift;

  my $json = JSON->new;
  my $hash = ();

  eval { $hash = $json->decode($originalJson); };

  if ($@) {
    my $error = $@;
    error($error);
    error("Failed body: $originalJson");
    return ();
  }
  else {
    return $hash;
  }

}

sub urnToId {
  my $urn   = shift;
  my $index = shift;
  my @parts = split( ':', $urn );
  if ( defined $parts[$index] ) {
    return $parts[$index];
  }
  else {
    error_die("Can not split urn $urn on index $index");
  }
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

sub log {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "[$act_time]: $text \n";
  return 1;
}

sub decode_json_eval {
  my ($json) = @_;
  my $hash = ();
  eval { $hash = decode_json($json); };
  if ($@) {
    my $error = $@;
    error($error);
    return ();
  }
  else {
    return $hash;
  }
}

1;
