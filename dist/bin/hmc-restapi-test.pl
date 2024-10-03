use strict;
use warnings;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use JSON qw(decode_json encode_json);
use Math::BigInt;
use HostCfg;
use POSIX;
my $basedir = $ENV{INPUTDIR};
require "$basedir/bin/xml.pl";
my ( $host, @others ) = @ARGV;
my ( $port, $proto, $login_id, $login_pwd );
my $args_defined = 0;
my $args_cycle   = 0;

my %credentials  = %{ HostCfg::getHostConnections("IBM Power Systems") };
my @host_aliases = keys %credentials;
if ( !defined( keys %credentials ) || !defined $host_aliases[0] ) {
  print "No IBM Power Systems host found. Please save Host Confiugration in GUI first<br>\n";
}

my $LWPtest = $LWP::VERSION;
if ( !defined $others[0] ) {

  #print "LWP Version: $LWPtest\n";
}
my $aix       = `uname -a|grep AIX|wc -l`;
my $perl_path = `echo \$PERL`;
chomp($aix);
chomp($perl_path);
my $hmc_found = 0;
my $hmc_alias = "";

print STDERR "DEBUG 0 : $host\n";
print STDERR Dumper \@others;

foreach my $alias ( keys %credentials ) {
  my $hmc = $credentials{$alias};
  if ( $host ne $hmc->{host} ) { next; }
  $proto     = $hmc->{proto};
  $port      = $hmc->{api_port};
  $login_id  = $hmc->{username};
  $login_pwd = $hmc->{password};
  $hmc_alias = $alias;
  $hmc_found = 1;
}

print STDERR "DEBUG 1 : host:$host proto:$proto port:$port login:$login_id alias:$hmc_alias\n";

if ( defined $others[0] && $others[0] eq "DEBUG_BAD_HMC" ) {
  my $APISession = getSession( $proto, $host, $port, $login_id, $login_pwd );
  print "API Session $host : " . substr( $APISession, 0, 80 ) . "\n";

  print "ManagedSystems $host : \n";
  my $mc1 = callAPI( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/uom/ManagementConsole" );
  print Dumper $mc1;

  print "Preferences $host : \n";
  my $pre = callAPI( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/pcm/preferences" );
  print Dumper $pre;

  my $logoff = logoff($APISession);
  if   ($logoff) { print "Logoff from $host  was successful $logoff\n"; }
  else           { print "Logoff from $host was not successful $logoff\n"; }
  exit;
}

elsif ( defined $others[0] && $others[0] eq "REST_API_CMD" && defined $others[1] && $others[1] ne "" ) {
  my $APISession = getSession( $proto, $host, $port, $login_id, $login_pwd );
  print "API Session $host : " . substr( $APISession, 0, 80 ) . "\n";

  my $pre;
  if ( $others[1] =~ /json/ ) {
    my $rand_json = callAPIjson( $proto, $host, $port, $login_id, $login_pwd, $APISession, $others[1] );
    $pre = decode_json($rand_json);
  }
  else {
    $pre = callAPI( $proto, $host, $port, $login_id, $login_pwd, $APISession, $others[1] );
  }
  print "Rest API response ($host) : \n";
  print Dumper $pre;
  my $logoff = logoff($APISession);
  if   ($logoff) { print "Logoff from $host  was successful $logoff\n"; }
  else           { print "Logoff from $host was not successful $logoff\n"; }
  exit;
}

if ( $hmc_found == 0 ) {
  print "No $host found in Host Configuration. Add your hosts to Web -> Settings -> IBM Power Systems\n";
  print STDERR "No $host found in Host Configuration. Add your hosts to Web -> Settings -> IBM Power Systems\n";
  exit(1);
}

#  my $hmc = $credentials{$hmc_alias};
#  $host=$hmc->{host};
#  $proto=$hmc->{proto};
#  $port=$hmc->{api_port};
#  $login_id=$hmc->{username};
#  $login_pwd=$hmc->{password};
my $time = time;

#print "HMC Connection Test:$alias($host)\t$time\n";
#print "--------------------------------------------\n";
my $APISession;

#  my $sessionFile = "$basedir/tmp/restapi/session_$host\_0_$time.tmp";
#  if (-e $sessionFile && (open (my $fh, "<", $sessionFile))){
#    $APISession = readline($fh);
#    close($fh);
#  }
#  else{
#    my $x = $!;
#    if (!($x =~ m/[Pp]ermission.*denied/ || $x =~ m/[Nn]o such file/)){
#      print STDERR "$x Cannot open file $sessionFile File:". __FILE__.":".__LINE__ . "\n";
#    }
#  }
#  if (!(-e $sessionFile )){
$APISession = getSession( $proto, $host, $port, $login_id, $login_pwd );

#    if (open (my $fh, ">", $sessionFile)){
#      print $fh $APISession;
#      close($fh);
#    }
#    else{
#      my $x = $!;
#      if (!($x =~ m/[Pp]ermission.*denied/)){
#        print STDERR "$x Cannot open file $sessionFile File:". __FILE__.":".__LINE__ . "\n";
#      }
#    }
#   }
#print "\nOK $host\n";
if ($APISession) {
  print STDERR "OK  Rest API connection\n";
}
else {
  print "$host : Cannot get session\n";
}
my @all_servers;
my $mc       = callAPI( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/uom/ManagementConsole" );
my $hmc_time = $mc->{updated};
print STDERR "HMC Time : $hmc_time @ $host\n";
if ( ref($mc) eq "HASH" && defined $mc->{error}{content}{_content} && ( $mc->{error}{content}{_msg} =~ /negotiation failed/ || $mc->{error}{content}{_rc} == 500 ) ) {
  print "Crypt-SSLeay, perl-Net_SSLeay.pm are required on AIX\n";
  my @modules = `rpm -q perl-Crypt-SSLeay perl-Net_SSLeay.pm`;
  foreach my $m (@modules) {
    chomp($m);
    print "$m";
  }
  print "\n";

  #print "NOK $host - $response->{_msg} <a href=\"http://lpar2rrd.com/https.htm\">lpar2rrd.com/https.htm</a><br>";
  print "AIX HTTPS visit http://lpar2rrd.com/https.htm for resolving this AIX specific problem\n";
  logoff($APISession);
  exit;
}
if ( ref($mc) eq "HASH" && defined $mc->{error}{content}{_content} ) {
  print "API Error : $mc->{error}{content}{_msg} $mc->{error}{content}{_rc} $mc->{error}{content}{_request}{_uri}\n";
  print STDERR "NOK API Error : $mc->{error}{content}{_msg} $mc->{error}{content}{_rc} $mc->{error}{content}{_request}{_uri}\n";
  print STDERR "NOK API Error : Session from previous forced closed connection expired or is corrupted.\n";

  #print "NOK $host IMPORTANT SETTINGS: Allow remote access via the web : GUI --> Manage User Profiles and Access --> select lpar2rrd --> modify --> user properties --> Allow remote access via the web\n";
  #next;
}
my $version = $mc->{'entry'}{'content'}{'ManagementConsole:ManagementConsole'}{'VersionInfo'}{'Version'}{'content'};

#  print "<p style='color:green'>OK  Managment Console - Version:$version\n";

my $pref = callAPI( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/pcm/preferences" );
print STDERR "HMC preferences @ $host\n";
print STDERR Dumper $pref;
my $mspp    = $pref->{'entry'}{'content'}{'ManagementConsolePcmPreference:ManagementConsolePcmPreference'}{'ManagedSystemPcmPreference'};
my $servers = getServerIDs( $proto, $host, $port, $login_id, $login_pwd, $APISession );
if ( !defined $servers || ( ref($servers) ne "HASH" && ref($servers) ne "ARRAY" ) ) {
  print "$host : No Servers Found. Check HMC username and password. HMC also might have been restarted right now - wait a while and try again.\n";
  print STDERR "$host : No Servers Found. Check HMC username and password. HMC also might have been restarted right now - wait a while and try again.\n";
  logoff($APISession);
  exit;
}
my $server_found = 0;
if ( ref($mspp) eq "HASH" ) {
  if ( $mspp->{'SystemName'}{'content'} eq $others[0] ) {
    $server_found = 1;
    push( @all_servers, $mspp->{'SystemName'}{'content'} );
    my $agg_on = $mspp->{'AggregationEnabled'}{'content'};
    my $ltm_on = $mspp->{'LongTermMonitorEnabled'}{'content'};
    my $stm_on = $mspp->{'ShortTermMonitorEnabled'}{'content'};
    my $cle_on = $mspp->{'ComputeLTMEnabled'}{'content'};
    my $eme_on = $mspp->{'EnergyMonitorEnabled'}{'content'};
    if ( $agg_on eq "false" ) {

      #      print "<p style='color:green'>OK* $host $mspp->{'SystemName'}{'content'} AggregationEnabled=$agg_on\n";
      print "Troubleshooting: <a href=\"www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm\">www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm</a><br><br>$mspp->{'SystemName'}{'content'}<br>AggregationEnabled=$agg_on<br>Turn on AggragationEnabled on each server:<br>Server -> Performance -> Top Right Corner - Data Collection -> ON<br>";

      #print "$host $mspp->{'SystemName'}{'content'} : AggregationEnabled=$agg_on - This usually turns on LTM which is a must. Turn on AggragationEnabled on each server -> Server -> Performance -> Top Right Corner - Data Collection -> ON\n";
    }
    else {
      #      print "<p style='color:green'>OK  $mspp->{'SystemName'}{'content'} AggregationEnabled\n";
    }
    if ( $ltm_on eq "false" ) {
      print "$host $mspp->{'SystemName'}{'content'} : LongTermMonitor is $ltm_on. Turn on data aggregation\n";
      print STDERR "NOK $host $mspp->{'SystemName'}{'content'} LongTermMonitorEnabled=$ltm_on\n";
      print STDERR "The LongTermMonitorEnabled must be on. Turn on AggregationEnabled (or just LongTermMonitor if you can)";
    }
    else {
      #      print "<p style='color:green'>OK  $mspp->{'SystemName'}{'content'} LongTermMonitorEnabled\n";
    }
    if ( $stm_on eq "false" ) {

      #print "NOK $host $mspp->{'SystemName'}{'content'} ShortTermMonitorEnabled=$stm_on\n";
    }
    else {
      #print "<p style='color:green'>OK  $mspp->{'SystemName'}{'content'} ShortTermMonitorEnabled\n";
    }
    if ( $cle_on eq "false" ) {

      #print "NOK $host $mspp->{'SystemName'}{'content'} ComputeLTMEnabled=$cle_on\n";
    }
    else {
      #print "<p style='color:green'>OK  $mspp->{'SystemName'}{'content'} ComputeLTMEnabled\n";
    }
    if ( $eme_on eq "false" ) {

      #print "NOK $host $mspp->{'SystemName'}{'content'} EnergyMonitorEnabled=$eme_on\n";
    }
    else {
      #print "<p style='color:green'>OK  $mspp->{'SystemName'}{'content'} EnergyMonitorEnabled\n";
    }

    #  print "LongTermMonitorEnabled\t$ltm_on\n";
    #  print "ShortTermMonitorEnabled\t$stm_on\n";
    #  print "ComputeLTMEnabled\t$cle_on\n";
    #  print "EnergyMonitorEnabled\t$eme_on\n";
  }
}
elsif ( ref($mspp) eq "ARRAY" && defined $others[0] ) {
  foreach my $m_server ( @{$mspp} ) {
    if ( $m_server->{'SystemName'}{'content'} !~ $others[0] ) { next; }
    $server_found = 1;
    push( @all_servers, $m_server->{'SystemName'}{'content'} );
    my $agg_on = $m_server->{'AggregationEnabled'}{'content'};
    my $ltm_on = $m_server->{'LongTermMonitorEnabled'}{'content'};
    my $stm_on = $m_server->{'ShortTermMonitorEnabled'}{'content'};
    my $cle_on = $m_server->{'ComputeLTMEnabled'}{'content'};
    my $eme_on = $m_server->{'EnergyMonitorEnabled'}{'content'};

    if ( $agg_on eq "false" ) {

      #        print "<p style='color:green'>OK* $host $m_server->{'SystemName'}{'content'} AggregationEnabled=$agg_on\n";
      print "Troubleshooting: <a href=\"www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm\">www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm</a><br><br>$m_server->{'SystemName'}{'content'}<br>AggregationEnabled=$agg_on<br>Turn on AggragationEnabled on each server:<br>Server -> Performance -> Top Right Corner - Data Collection -> ON<br>";
      print STDERR "Troubleshooting: <a href=\"www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm\">www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm</a><br><br>$m_server->{'SystemName'}{'content'}<br>AggregationEnabled=$agg_on<br>Turn on AggragationEnabled on each server:<br>Server -> Performance -> Top Right Corner - Data Collection -> ON<br>";
    }
    else {
      #        print "<p style='color:green'>OK  $m_server->{'SystemName'}{'content'} AggregationEnabled\n";
    }
    if ( $ltm_on eq "false" ) {

      #print "LongTermMonitor is off for $host $m_server->{'SystemName'}{'content'}. Turn on data aggregation\n";
      print "The LongTermMonitorEnabled must be on. Turn on AggregationEnabled (or just LongTermMonitor)<br><br>";
    }
    else {
      #        print "<p style='color:green'>OK  $m_server->{'SystemName'}{'content'} LongTermMonitorEnabled\n";
    }
    if ( $stm_on eq "false" ) {

      #print "NOK $host $m_server->{'SystemName'}{'content'} ShortTermMonitorEnabled=$stm_on\n";
    }
    else {
      #print "<p style='color:green'>OK  $m_server->{'SystemName'}{'content'} ShortTermMonitorEnabled\n";
    }
    if ( $cle_on eq "false" ) {

      #print "NOK $host $m_server->{'SystemName'}{'content'} ComputeLTMEnabled=$cle_on\n";
    }
    else {
      #print "<p style='color:green'>OK  $m_server->{'SystemName'}{'content'} ComputeLTMEnabled\n";
    }
    if ( $eme_on eq "false" ) {

      #print "NOK $host $m_server->{'SystemName'}{'content'} EnergyMonitorEnabled=$eme_on\n";
    }
    else {
      #print "<p style='color:green'> $m_server->{'SystemName'}{'content'} EnergyMonitorEnabled\n";
    }
    foreach my $no ( keys %{$servers} ) {
      my $server      = $servers->{$no};
      my $server_id   = $server->{id};
      my $server_name = $server->{name};
      if ( $server_name ne $m_server->{'SystemName'}{'content'} ) { next; }
      my $t = callAPI( $proto, $host, $port, $login_id, $login_pwd, $APISession, "rest/api/pcm/ManagedSystem/$server_id/RawMetrics/LongTermMonitor" );
      if ( $t eq "-1" ) { next; }
      foreach my $hash_id ( keys %{ $t->{entry} } ) {

        #         print Dumper $t->{entry}{$hash_id};
      }
      my $rand_id = ( keys %{ $t->{entry} } )[0];

      my $rand_json_href = $t->{entry}{$rand_id}{link}{href};
      my $rand_json      = callAPIjson( $proto, $host, $port, $login_id, $login_pwd, $APISession, $rand_json_href );
      my $hash_from_json = decode_json($rand_json);

      my $lparsUtil = $hash_from_json->{systemUtil}{utilSample};
      if ( defined $lparsUtil && $lparsUtil ne "" ) {

        #          print "<p style='color:green'>OK  $server_name Perf Data\n";
      }
      else {
        print "$host $server_name : Perf Data\n";
        print STDERR "NOK $host $server_name Perf Data\n";
      }
    }
  }
}
my $local_time = strftime( "%F %X", localtime );
$hmc_time =~ s/T/ /;
( $hmc_time, undef ) = split( '\.', $hmc_time );
if ( !defined $others[0] ) {
  my @srvnames;
  my $num_servers = keys %{$servers};
  if ( $num_servers != 0 ) {
    foreach my $no ( sort keys %{$servers} ) {
      push @srvnames, $servers->{$no}{name};
    }
    print encode_json( \@srvnames );
  }
  else {
    print "Cannot find any server on $host\n";

    #    print STDERR "NOK $host Servers - cannot find any server\n";
  }
}
else {
  if ( $server_found == 0 ) {
    print "No server $others[0] found on $host.\n";
  }
}

if ( logoff($APISession) ) {

  #unlink($sessionFile);
}

#logoff($APISession);
exit;

sub getSession {
  my $proto     = shift;
  my $host      = shift;
  my $port      = shift;
  my $login_id  = shift;
  my $login_pwd = shift;
  my $session;
  my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => "SSL_VERIFY_NONE", SSL_cipher_list => 'DEFAULT:!DH' }, protocols_allowed => [ 'https', 'http' ], keep_alive => 0 );
  $browser->timeout(10);
  my $error;
  my $Url   = $proto . '://' . $host . ':' . $port . '/rest/api/web/Logon';
  my $token = <<_REQUEST_;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<LogonRequest xmlns="http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/" schemaVersion="V1_0">
  <UserID kb="CUR" kxe="false">$login_id</UserID>
  <Password kb="CUR" kxe="false">$login_pwd</Password>
</LogonRequest>
_REQUEST_
  my $req = HTTP::Request->new( PUT => $Url );
  $req->content_type('application/vnd.ibm.powervm.web+xml');
  $req->content_length( length($token) );
  $req->header( 'Accept' => '*/*' );
  $req->content($token);
  my $response = $browser->request($req);

  if ( defined $others[0] && $others[0] eq "DEBUG_BAD_HMC" ) {
    print "Get Session Response $host : \n";
    print Dumper $response;
  }
  if ( $response->is_success ) {
    my $ref = XMLin( $response->content );
    $session = $ref->{'X-API-Session'}{content};
    if ( $session eq "" ) {
      print "Invalid session. Unknown error.\n";
    }
  }
  else {
    if ( defined $response->{_msg} &&  $response->{_msg} =~ /negotiation failed/ ) {
      print "Crypt-SSLeay, Net_SSLeay are required on AIX\n";
      my @modules = `rpm -qa | egrep -i 'Crypt-SSLeay|Net_SSLeay'`;
      print "Found:\n";
      foreach my $m (@modules) {
        chomp($m);
        print "$m\n";
      }

      #print "NOK $host - $response->{_msg} <a href=\"http://lpar2rrd.com/https.htm\">lpar2rrd.com/https.htm</a><br>";
      print "AIX HTTPS Help: <a target='blank' href='http://lpar2rrd.com/https.htm'>lpar2rrd.com/https.htm<\/a><br>\n";
      print "AIX HTTPS visit http://lpar2rrd.com/https.htm for resolving this AIX specific problem<\/a>\n";
      logoff($APISession);
      exit;
    } elsif ( defined $response->{_msg} && $response->{_msg} ne "" ){
      print "Session error: $response->{_msg}<br>\n";
    }
    return 812;
  }
  return $session;
}

sub getServerIDs {
  my $proto      = shift;
  my $host       = shift;
  my $port       = shift;
  my $login_id   = shift;
  my $login_pwd  = shift;
  my $APISession = shift;
  my $ids;
  my $url     = 'rest/api/pcm/preferences';
  my $servers = callAPI( $proto, $host, $port, $login_id, $login_pwd, $APISession, $url );

  if ( defined $servers->{error} ) {
    print "Preferences data from hmc: $proto" . "://" . $host . ':' . $port . "/" . $url . "\n";
    print STDERR "NOK preferences data from hmc: $proto" . "://" . $host . "/" . $url . "\n";

    #print Dumper $servers->{error};
    return 813;
  }
  my $out;
  my $i = 0;
  my $name;
  if ( !defined $servers->{entry} ) {
    print "NOK Server list not found on $url\n";
    print STDERR "NOK Server list not found on $url\n";
    return -1;
  }
  $servers = $servers->{entry}{content}{'ManagementConsolePcmPreference:ManagementConsolePcmPreference'}{ManagedSystemPcmPreference};
  if ( ref($servers) eq "HASH" ) {
    print STDERR "SERVER in HASH  : $servers->{Metadata}{Atom}{AtomID}:$servers->{SystemName}{content}\n";
    $out->{$i}{id}   = $servers->{Metadata}{Atom}{AtomID};
    $out->{$i}{name} = $servers->{SystemName}{content};
  }
  elsif ( ref($servers) eq "ARRAY" ) {
    foreach my $hash ( @{$servers} ) {
      print STDERR "SERVER in ARRAY : $hash->{Metadata}{Atom}{AtomID}:$hash->{SystemName}{content}\n";
      $out->{$i}{id}   = $hash->{Metadata}{Atom}{AtomID};
      $out->{$i}{name} = $hash->{SystemName}{content};
      $i++;
    }
  }
  return $out;
}

sub callAPI {
  my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => "SSL_VERIFY_NONE", SSL_cipher_list => 'DEFAULT:!DH' }, protocols_allowed => [ 'https', 'http' ], keep_alive => 0 );
  $browser->timeout(10);
  my $proto      = shift;
  my $host       = shift;
  my $port       = shift;
  my $login_id   = shift;
  my $login_pwd  = shift;
  my $APISession = shift;
  my $url        = shift;
  my $error;

  if    ( $url =~ /^rest/ )   { $url = "$proto://$host:$port/$url"; }
  elsif ( $url =~ /^\/rest/ ) { $url = "$proto://$host:$port" . $url; }
  else                        { $url = $url; }
  if ( $url eq "" ) {
    $error->{error}{url}     = $url;
    $error->{error}{content} = "Not valid rest api command. Is the url correct? Check config";
    return $error;
  }
  my $req = HTTP::Request->new( GET => $url );
  $req->content_type('application/xml');
  $req->header( 'Accept'        => '*/*' );
  $req->header( 'X-API-Session' => $APISession );

  my $data = $browser->request($req);

  if ($data->{_rc} < 200 && $data->{_rc} >= 300){
    print "NOK: $data->{_rc} $data->{_msg}<br>\n";
    return;
  }
  elsif ( $data->{_content} =~ m/SRVE0190E/) {
    print "NOK: $data->{_rc} $data->{_msg}<br>\n";
    return;
  }

  if ( $data->is_success) {

    #print "$data->{_content}\n";
    if ( $data->{_content} eq "" ) {

      #print Dumper $data;
      #print "$url request\n";
      #print STDERR "NOK $url request\n";
      if ( $url =~ m/LongTermMonitor/ ) {
        print "LongTermMonitor is off. This happens a few minutes after data aggregation is enabled. Wait a few minutes and try again.<br><br>\n";
      }
      return -1;
    }
    else {
      my $out;
      eval {
        $out = XMLin( $data->{_content} );

        # print Dumper $out;
      };
      if ($@) {
        print "Corrupted XML content:\n";
        print Dumper $data->content;
        return { "corrupted_xml" => $data->content };
      }
      return $out;
    }
  }
  else {
    #print Dumper $data;
    print "NOK $data->{_rc} : $data->{_msg}<br>\n";
    if ( $data->{_content} =~ m/user does not have the role authority to perform the request/) {

      #print "NOK IMPORTANT SETTINGS: Allow remote access via the web : GUI --> Manage User Profiles and Access --> select lpar2rrd --> modify --> user properties --> Allow remote access via the web\n";
      #print STDERR "NOK IMPORTANT SETTINGS: Allow remote access via the web : GUI --> Manage User Profiles and Access --> select lpar2rrd --> modify --> user properties --> Allow remote access via the web\n";
      return $data;
    }
    $error->{error}{content} = $data;
    return $error;
  }
}

sub callAPIjson {
  my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => "SSL_VERIFY_NONE", SSL_cipher_list => 'DEFAULT:!DH' }, protocols_allowed => [ 'https', 'http' ], keep_alive => 0 );
  $browser->timeout(10);
  my $proto      = shift;
  my $host       = shift;
  my $port       = shift;
  my $login_id   = shift;
  my $login_pwd  = shift;
  my $APISession = shift;
  my $url        = shift;
  my $error;

  if ( $url =~ /^rest/ ) {
    $url = "$proto://$host:$port/$url";
  }
  elsif ( $url =~ /^\/rest/ ) {
    $url = "$proto://$host:$port" . $url;
  }
  else {
    my $new_url = $url;
    $new_url =~ s/^.*\/rest/rest/g;
    $url = "$proto://$host:$port/$new_url";
  }
  my $req = HTTP::Request->new( GET => $url );
  $req->content_type('application/json');
  $req->header( 'Accept'        => '*/*' );
  $req->header( 'X-API-Session' => $APISession );
  my $data = $browser->request($req);
  if ( $data->is_success ) {
    my $out = $data->{_content};
    return $out;
  }
  else {
    #print "NOK - This happens only if aggregation was just turned on. Wait a few minutes and try again.\n";
  }
}

sub logoff {
  my $session = shift;
  my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0, SSL_cipher_list => 'DEFAULT:!DH' }, keep_alive => 0 );
  $browser->timeout(10);
  my $url = $proto . '://' . $host . ':' . $port . '/rest/api/web/Logon';

  #print "URL: $url\n";
  my $req = HTTP::Request->new( DELETE => $url );
  $req->header( 'X-API-Session' => $session );
  my $data = $browser->request($req);
  if ( $data->is_success ) {

    #    print "<p style='color:green'>OK  logoff\n";
    return 1;
  }
  else {
    if ( $data->{_rc} == 401 ) {
      print STDERR $data->{_msg};
      return 0;
    }
    else {
      print "logoff wasn't sucessfull $data->{_rc}\n";
    }
  }
}
