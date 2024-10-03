package Cloudstack;

use strict;
use warnings;

use HTTP::Request::Common;
use HTTP::Cookies;
use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;

sub new {
  my ( $self, $cloud, $protocol, $endpoint ) = @_;

  my $o = {};
  $o->{cloud}    = $cloud;
  $o->{endpoint} = $endpoint;
  $o->{protocol} = $protocol;
  bless $o;

  return $o;
}

sub auth {
  my ( $self, $username, $password ) = @_;

  my $url = $self->{endpoint} . "/client/api";

  my %data;
  $data{command}  = 'login';
  $data{username} = $username;
  $data{password} = $password;
  $data{response} = 'json';

  my $resp = $self->apiRequest( "LOGIN", $url, \%data );

  if ( defined $self->{session} ) {

    #print "Token: $self->{session} \n";
  }
  else {
    error_die("Auth error (missing session)");
  }

  return 1;
}

sub getHosts {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/client/api?command=listHosts&response=json";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getHostsMetrics {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/client/api?command=listHostsMetrics&response=json";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getInstances {
  my ( $self, $uuid ) = @_;

  my $url  = $self->{endpoint} . "/client/api?listall=true&command=listVirtualMachines&response=json";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getInstancesMetrics {
  my ( $self, $uuid ) = @_;

  my $url  = $self->{endpoint} . "/client/api?listall=true&command=listVirtualMachinesMetrics&response=json";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getVolumes {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/client/api?listall=true&command=listVolumes&response=json";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getVolumesMetrics {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/client/api?listall=true&command=listVolumesMetrics&response=json";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getInstanceLimits {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/compute/v2.1/limits";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getAlerts {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/client/api/?command=listAlerts&response=json&pagesize=50&page=1";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getEvents {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/client/api/?command=listEvents&response=json&pagesize=50&page=1&level=ERROR";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getPrimaryStorages {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/client/api/?listall=true&page=1&pagesize=10&command=listStoragePoolsMetrics&response=json";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getSecondaryStorages {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/client/api/?listall=true&page=1&pagesize=10&command=listImageStores&response=json";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getSystemVMs {
  my ($self) = @_;

  my $url  = $self->{endpoint} . "/client/api/?listall=true&page=1&pagesize=10&command=listSystemVms&response=json";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub getVolumeLimits {
  my ($self) = @_;

  if ( !defined $self->{project} ) {
    error("Project error: no projects under user ");
    return ();
  }

  my $url  = $self->{endpoint} . "/volume/v3/" . $self->{project} . "/limits";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;
}

sub apiRequest {
  my ( $self, $type, $url ) = @_;

  my $data;
  if ( defined $_[3] ) {
    $data = $_[3];
  }

  my $json = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  #if (defined $self->{session}) {
  #  $ua->cookie_jar({ });
  #  $ua->cookie_jar->set_cookie(0, "JSESSIONID", $self->{session}, "/", $self->{protocol}."://".$self->{endpoint});
  #}

  my $resp = $json->decode("{}");

  if ( $type eq "GET" ) {
    eval {

      if ( defined $self->{session} && defined $self->{cookies} ) {
        my $cookie = "sessionkey=" . $self->{session} . "; " . $self->{cookies};

        my $response = $ua->get( $self->{protocol} . "://" . $url, Cookie => $cookie );

        $resp = $json->decode( $response->content );

      }
      else {
        error_die("Auth error: no auth cookie OR session key");
      }
    };

    if ($@) {
      my $error = $@;
      error_die($error);
    }
  }
  elsif ( $type eq "POST" ) {
    eval {
      my $req = HTTP::Request->new( 'POST', $self->{protocol} . "://" . $url );
      $req->header( 'Content-Type' => 'application/x-www-form-urlencoded;charset=utf-8' );

      $req->content( encode_json($data) );
      my $response = $ua->request($req);
      $resp = $json->decode( $response->content );
    };

    if ($@) {
      my $error = $@;
      error_die($error);
    }
  }
  elsif ( $type eq "LOGIN" ) {
    eval {
      my $response = $ua->post(
        $self->{protocol} . "://" . $url,
        'Content-Type' => 'application/x-www-form-urlencoded',
        Content        => $data
      );

      #cookie
      my $cookies = $response->header('set-cookie');
      $self->{cookies} = $cookies;

      $resp = $json->decode( $response->content );

      #session key
      if ( defined $resp->{loginresponse}{sessionkey} ) {
        $self->{session} = $resp->{loginresponse}{sessionkey};
      }
      elsif ( defined $resp->{loginresponse}{errortext} ) {
        error( $resp->{loginresponse}{errortext} );
      }
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
