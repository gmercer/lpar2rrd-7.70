package Proxmox;

use strict;
use warnings;

use HTTP::Request::Common;
use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;

my $protocol = 'https://';

sub new {
  my ( $self, $protocol, $ip, $port, $backup_host ) = @_;

  my $o = {};
  $o->{protocol} = $protocol;
  $o->{ip}       = $ip;
  $o->{port}     = $port;

  if ( defined $backup_host ) {
    $o->{backup_host} = $backup_host;
  }

  bless $o;

  return $o;
}

sub authCredentials {
  my ( $self, $username, $password, $domain, $alias ) = @_;

  my $url = $self->{ip} . ":" . $self->{port} . "/api2/json/access/ticket?username=" . $username . "@" . $domain . "&password=" . $password;

  my $resp = $self->apiRequest( "POST", $url );

  if ( !defined $resp->{data}{ticket} && defined $self->{backup_host} ) {
    $self->{ip} = $self->{backup_host};

    print "Can't connect to host! Switching to backup host ...\n";
    $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/access/ticket?username=" . $username . "@" . $domain . "&password=" . $password;
    $resp = $self->apiRequest( "POST", $url );

    if ( !defined $resp->{data}{ticket} ) {
      error("Request URL: '$url'");
      error( "Response data: " . Dumper($resp) );
      error_die("Can't connect to host!");
    }
  }
  elsif ( !defined $resp->{data}{ticket} ) {
    error("Request URL: '$url'");
    error( "Response data: " . Dumper($resp) );
    error_die("Can't connect to host!");
  }

  if ( !defined $resp->{data}{clustername} ) {
    $self->{cluster} = $alias;
  }
  else {
    $self->{cluster} = $resp->{data}{clustername};
  }

  $self->{ticket} = $resp->{data}{ticket};
  $self->{csrf}   = $resp->{data}{CSRFPreventionToken};

  #print Dumper($resp);

  return 1;
}

sub authToken {
  my ( $self, $token, $secret ) = @_;

  $self->{token} = $token . "=" . $secret;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/version";
  my $resp = $self->apiRequest( "GET", $url );

  print Dumper($resp);

  #$self->{cluster} = $resp->{data}{clustername};

  return 1;
}

sub getClusterName {
  my ($self) = @_;
  return $self->{cluster};
}

sub getStatus {
  my ($self) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/cluster/status";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getLog {
  my ($self) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/cluster/log";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getNodes {
  my ($self) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/nodes";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getNodeMetrics {
  my ( $self, $node ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/nodes/" . $node . "/rrddata?timeframe=hour";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getNodeDisks {
  my ( $self, $node ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/nodes/" . $node . "/disks/list";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getNodeVMs {
  my ( $self, $node ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/nodes/" . $node . "/qemu";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getVMMetrics {
  my ( $self, $node, $vm ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/nodes/" . $node . "/qemu/" . $vm . "/rrddata?timeframe=hour";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getNodeLXCs {
  my ( $self, $node ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/nodes/" . $node . "/lxc";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getLXCMetrics {
  my ( $self, $node, $vm ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/nodes/" . $node . "/lxc/" . $vm . "/rrddata?timeframe=hour";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getNodeStorages {
  my ( $self, $node ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/nodes/" . $node . "/storage";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

sub getStorageMetrics {
  my ( $self, $node, $storage ) = @_;

  my $url  = $self->{ip} . ":" . $self->{port} . "/api2/json/nodes/" . $node . "/storage/" . $storage . "/rrddata?timeframe=hour";
  my $resp = $self->apiRequest( "GET", $url );

  return $resp;

}

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

  if ( defined $self->{ticket} ) {
    $ua->cookie_jar( {} );
    $ua->cookie_jar->set_cookie( 0, "PVEAuthCookie", $self->{ticket}, "/", $self->{ip}, 8006, 0, 0, 365 * 86400, 0 );

    #print "Cookie jar: ", $ua->cookie_jar->as_string, "\n";
  }
  elsif ( defined $self->{token} ) {
    $ua->default_header( Authorization => 'PVEAPIToken=' . $self->{token} );
  }

  my $resp = $json->decode("{}");

  if ( $type eq "GET" ) {
    eval {
      my $req      = HTTP::Request->new( 'GET', $self->{protocol} . "://" . $url );
      my $response = $ua->request($req);

      if ( $response->{'_rc'} eq "500" ) {
        return ();
      }

      if (length($response->content) >= 2) {
	$resp = $json->decode( $response->content );
      } else {
        error("[$url]: Server returned empty reponse");
	return ();
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
      if ( defined $data ) {
        $req->content( encode_json($data) );
      }
      my $response = $ua->request($req);

      if ( $response->{'_rc'} eq "500" ) {
        return ();
      }

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
