use strict;
use warnings;
use HostCfg;
use LWP::UserAgent;
use HTTP::Request;

defined $ENV{INPUTDIR} || error( " Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
require "$ENV{INPUTDIR}/bin/xml.pl";

my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };

my @pids;
my $pid;
my $timeout = 900;
my $success = 0;

foreach my $alias ( keys %hosts ) {
  $success++;
}

if ( parameter("api") ) {
  foreach my $alias ( keys %hosts ) {
    if ( $hosts{$alias}{auth_api} && !$hosts{$alias}{proxy} ) {
      my $nok = test_connection( $hosts{$alias}{host}, 12443 );
      if ($nok) {
        print "$hosts{$alias}{hmc2} " if ( defined $hosts{$alias}{hmc2} );
      }
      else {
        print "$hosts{$alias}{host} ";
      }
    }
  }
}
elsif ( parameter("api-proxy") ) {
  foreach my $alias ( keys %hosts ) {
    if ( $hosts{$alias}{auth_api} && $hosts{$alias}{proxy} ) {
      print "$hosts{$alias}{host} ";
    }
  }
}
elsif ( parameter("old") ) {
  foreach my $alias ( keys %hosts ) {
    if ( $hosts{$alias}{auth_ssh} ) {
      my $nok = test_connection( $hosts{$alias}{host}, 22 );
      if ($nok) {
        print "$hosts{$alias}{hmc2} " if ( defined $hosts{$alias}{hmc2} );
      }
      else {
        print "$hosts{$alias}{host} ";
      }
    }
  }
}
elsif ( parameter("all") ) {
  foreach my $alias ( keys %hosts ) {
    if ( $hosts{$alias}{auth_ssh} ) {
      my $nok = test_connection( $hosts{$alias}{host}, 22 );
      if ($nok) {
        print "$hosts{$alias}{hmc2} " if ( defined $hosts{$alias}{hmc2} );
      }
      else {
        print "$hosts{$alias}{host} ";
      }
    }
    else {
      my $nok = test_connection( $hosts{$alias}{host}, 12443 );
      if ($nok) {
        print "$hosts{$alias}{hmc2} " if ( defined $hosts{$alias}{hmc2} );
      }
      else {
        print "$hosts{$alias}{host} ";
      }
    }
  }
}
elsif ( parameter("username") ) {
  foreach my $alias ( keys %hosts ) {
    if ( !defined $ARGV[1] || $ARGV[1] eq "" ) {
      exit;
    }
    my $host = $ARGV[1];
    if ( $host eq "$hosts{$alias}{host}" ) {
      print "$hosts{$alias}{username}";
      exit;
    }
  }
}
elsif ( parameter("ssh") ) {
  foreach my $alias ( keys %hosts ) {
    if ( !defined $ARGV[1] || $ARGV[1] eq "" ) {
      exit;
    }
    my $host = $ARGV[1];
    if ( $host eq "$hosts{$alias}{host}" ) {
      print "$hosts{$alias}{ssh_key_id}";
      exit;
    }
  }
}
elsif ( parameter("proxy") ) {
  my $all_no_proxy = 0;
  foreach my $alias ( keys %hosts ) {
    if ( defined $ARGV[1] ) {
      if ( $hosts{$alias}{host} eq $ARGV[1] ) {
        if ( $hosts{$alias}{proxy} ) {
          print $hosts{$alias}{proxy};
        }
        else {
          print "0";
          exit;
        }
      }
      else {
        next;
      }
    }
    else {
      if ( defined $hosts{$alias}{proxy} && $hosts{$alias}{proxy} ) {
        print "1";
        exit;
      }
      $all_no_proxy = 1;
      next;
    }
  }
  if ($all_no_proxy) {
    print "0";
  }
}
elsif ( $success > 0 ) {
  foreach my $alias ( keys %hosts ) {
    my $nok;
    if ( $hosts{$alias}{auth_ssh} ) {
      $nok = test_connection( $hosts{$alias}{host}, 22 );
    }
    else {
      $nok = test_connection( $hosts{$alias}{host}, 12443 );
    }
    if ($nok) {
      print "$hosts{$alias}{hmc2} " if ( defined $hosts{$alias}{hmc2} );
    }
    else {
      print "$hosts{$alias}{host} ";
    }
  }
}
else {
  print "NO_POWER_HOSTS_FOUND\n";
}

sub parameter {
  my $tested = shift;
  if (@ARGV) {
    foreach my $param (@ARGV) {
      if ( $param eq "--$tested" ) {
        return 1;
      }
    }
  }
  else { return 0; }
}

sub test_connection {
  my $ip   = shift;
  my $port = shift;

  if ( parameter("no-test") ) {
    return 0;
  }

  use IO::Socket::INET;
  my $sock;

  eval {
    local $SIG{ALRM} = sub { die 'Timed Out'; };
    alarm 10;
    $sock = new IO::Socket::INET(
      PeerAddr => $ip,
      PeerPort => $port,
      Proto    => 'tcp',
      Timeout  => 5
    );
    alarm 0;
  };
  alarm 0;    # race condition protection

  if ( defined $sock && $sock ) {
    return 0;
  }
  else {
    return 1;
  }

}

=begin unused
sub getSession {
  my $alias = shift;
  my $host  = shift;

  my $p = Net::Ping->new();
  my $ping_res = $p->test_connection($host);
  $p->close();

  if ($ping_res || $ping_res == 0){
    return 0;
  } else {
    return 1;
  }


  if (parameter("no-test")){
    return 0;
  }
  my $browser = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0, SSL_cipher_list => 'DEFAULT:!DH' },protocols_allowed => ['https', 'http'],keep_alive => 0);
  my $url = "https://$host:12443/rest/api/web/Logon";
  my $login_id = $hosts{$alias}{username};
  my $login_pwd = $hosts{$alias}{password};
  my $token = <<_REQUEST_;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<LogonRequest xmlns="http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/" schemaVersion="V1_0">
  <UserID kb="CUR" kxe="false">$login_id</UserID>
  <Password kb="CUR" kxe="false">$login_pwd</Password>
</LogonRequest>
_REQUEST_
  my $req = HTTP::Request->new( PUT => $url );
  $req->content_type('application/vnd.ibm.powervm.web+xml');
  $req->content_length( length($token) );
  $req->header( 'Accept' => '*/*' );
  $req->content($token);
  my $response = $browser->request($req);
  if ($response->is_success){
    my $ref = XMLin( $response->content );
    my $session = $ref->{'X-API-Session'}{content};
    logoff($session, $host);
    return 0;
  }
  else {
    return 1;
  }
}

sub sshTest {
  if (parameter("no-test")){
    return "ok";
  }
  my $hmc = shift;
  my $nok = `$hmc->{ssh_key_id} $hmc->{username}\@$hmc->{host} date`;
  return $nok;
}
=cut

sub logoff {
  my $session = shift;
  my $host    = shift;
  my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0, SSL_cipher_list => 'DEFAULT:!DH' }, protocols_allowed => [ 'https', 'http' ], keep_alive => 0 );
  my $url     = "https://$host:12443/rest/api/web/Logon";
  my $req     = HTTP::Request->new( DELETE => $url );
  $req->header( 'X-API-Session' => $session );
  my $data = $browser->request($req);
  if ( $data->is_success ) {
    return 0;
  }
  else {
    return 1;
  }
}
