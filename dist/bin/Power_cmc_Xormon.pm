package Power_cmc_Xormon;

use strict;
use warnings;

use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;
use Scalar::Util qw(looks_like_number);
use File::Temp qw/tempdir/;

my $BACKEND_PORT = defined $ENV{APP_PORT} ? $ENV{APP_PORT} : 3000;
my $METRICS_SERVER_PORT = 3030;

my $protocol_https = 'https://';
my $protocol_http = 'http://';

my $PERF_JSON_API = "/api/metrics/v3/data/store";
my $PERF_CSV_API = "/api/metrics/v2/data/store";

#my $PERF_JSON_API = "/perf/json";
#my $PERF_CSV_API = "/perf/csv";

my $splice_data_by = 100;

my $md5module = 1;
my $password = "";
eval "use Digest::MD5 qw(md5_hex); 1" or $md5module = 0;

if ( !$md5module ) {    # binary MD5 module not found, use bundled pure Perl one
  #use Digest::Perl::MD5 qw(md5_hex);
  require Digest::Perl::MD5;

  # print STDERR "Bundled MD5\n";
}

sub new {
  my($self, $url, $token, $microservice) = @_;

  # if the url contains a port
  my @host = split(/:/, $url);

  my $o = {};
  $o->{url} = $host[0] . ":" . $BACKEND_PORT;
  $o->{'metrics-server'} = $host[0] . ":" . $METRICS_SERVER_PORT;
  $o->{token} = $token;
  $o->{microservice} = $microservice;
  bless $o, $self;

  return $o;
}

sub validateJSON {
  my($self,$data) = @_;

}

sub validateCSV {
  my($self,$data) = @_;

}

sub JSONtoCSV {
  my ($self,$data) = @_;

  my %metrics;

  foreach my $uuid (keys %{$data}) {
    foreach my $time (keys %{$data->{$uuid}}) {
      foreach my $metric (keys %{$data->{$uuid}{$time}}) {
        if (!defined $metrics{$metric}) {
          $metrics{$metric} = 1;
        }
      }
    }
  }
  my $csv = "uuid;timestamp;";
  foreach my $metric (keys %metrics) {
    $csv .= "$metric;";
  }
  foreach my $uuid (keys %{$data}) {
    foreach my $time (keys %{$data->{$uuid}}) {
      $csv .= "\n$uuid;$time;";
      foreach my $metric (keys %metrics) {
        if (defined $data->{$uuid}{$time}{$metric}) {
          $csv .= $data->{$uuid}{$time}{$metric}.";";
        } else {
          $csv .= "U;";
        }
      }
    }
  }

  return $csv;
}

sub CSVtoJSON {
  my ($self,$data) = @_;
  my %data;
  my @rows = split(/\n/, $data);
  my @metrics = split(/;/, $rows[0]);
  my $i = 0;
  foreach my $row (@rows) {
    if ($i eq "0") {
      $i++;
      next;
    }
    my @values = split(/;/, $row);
    my $c = 0;
    foreach my $value (@values) {
      if ($c <= 1 || $values[$c] eq "U") {
        $c++;
        next;
      }
      $data{$values[0]}{$values[1]}{$metrics[$c]} = $values[$c];
      $c++;
    }
  $i++;
  }

  return \%data;
}

sub split_hash {
    my ($hash ) = @_;
    my @keys = keys %$hash;
    my @hashes;

    while ( my @subset = splice( @keys, 0, $splice_data_by ) ) {
        push @hashes, { map { $_ => $hash->{$_} } @subset };
    }
    return \@hashes;
}



sub saveJSON2 {
  my($self,$data) = @_;

  my $resp_all = ();

  for (keys %{$data}){
    my $hw_type = $_;
    for (keys %{$data->{$hw_type}}){
      my $subsystem = $_;
      my $item_id = $_;
      my $hash_to_split = $data->{$hw_type}{$subsystem};
      my $hashes = split_hash($hash_to_split);

      for (@{$hashes}){
        
        my $out->{$hw_type}{$subsystem} = (scalar keys %{$_} > 0) ? $_ : {} ;

        my $json = JSON->new;

        my $req = HTTP::Request->new(POST => $protocol_http.$self->{'metrics-server'}.$PERF_JSON_API);
        $req->content_type('application/json');
        $req->content(to_json($out));
        my $ua = LWP::UserAgent->new(
          timeout => 30,
          ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
        );

        $ua->default_header(Authorization => 'Bearer '.$self->{token});

        my $resp = ();
        eval {
          $resp = $ua->request($req);
        };

        if ($@) {
          my $error = $@;
          print STDERR $error;
        }
       

        $resp_all = $resp->code;

        if ($resp_all != 201){
          
          return $resp_all;
        }
      }
    }
  }
  return $resp_all;
}

sub saveJSON {
  my($self,$data,$hw_type,$subsystem) = @_;

  my $json = JSON->new;

  my $param = '';
  if (defined $hw_type && defined $subsystem) {
    $param = "?hw_type=$hw_type&subsystem=$subsystem";
  }
  my $req = HTTP::Request->new(POST => $protocol_http.$self->{'metrics-server'}."/api/metrics/v1/data/store".$param);
  $req->content_type('application/json');
  $req->content(to_json($data));
  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub saveCSV {
  my($self,$data,$hw_type,$subsystem) = @_;

  my $json = JSON->new;

  my $param = '';
  if (defined $hw_type && defined $subsystem) {
    $param = "?hw_type=$hw_type&subsystem=$subsystem";
  }

  my $req = HTTP::Request->new(POST => $protocol_http.$self->{'metrics-server'}.$PERF_CSV_API.$param);
  $req->content_type('text/plain');
  $req->content($data);

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub saveConfJSON {
  my($self,$data) = @_;

  my $json = JSON->new;

  my $req = HTTP::Request->new(POST => $protocol_http.$self->{'metrics-server'}."/api/configuration/v1/properties");
  $req->content_type('application/json');
  $req->content(to_json($data));

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub deleteArchitecture {
  my($self,$hostcfg_id) = @_;

  my $json = JSON->new;
  my $req = HTTP::Request->new(DELETE => $protocol_http.$self->{'metrics-server'}."/api/configuration/v1/architecture");
  $req->content_type('application/json');

  my %data = (
    "hostcfg_id" => $hostcfg_id
  );

  $req->content(to_json(\%data));

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub saveArchitecture {
  my($self,$data) = @_;

  my $resp_all = ();

  while (my @next_n = splice @{$data}, 0, $splice_data_by) {
    my $json = JSON->new;
    my $req = HTTP::Request->new(POST => $protocol_http.$self->{'metrics-server'}."/api/configuration/v1/architecture");
    $req->content_type('application/json');
    $req->content(to_json(\@next_n));

    my $ua = LWP::UserAgent->new(
      timeout => 30,
      ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
    );

    $ua->default_header(Authorization => 'Bearer '.$self->{token});

    my $resp = ();
    eval {
      $resp = $ua->request($req);
    };

    if ($@) {
      my $error = $@;
      print STDERR $error;
    }

    $resp_all = $resp->code;

    if ($resp_all != 201){
      return $resp_all;      
    }

    #print "save partial architecture: ".$resp->code."\n";
  }

  return $resp_all;
}

sub saveArchitectureAgent {
  my($self,$data) = @_;


  my $json = JSON->new;

  my $req = HTTP::Request->new(POST => $protocol_http.$self->{'metrics-server'}."/api/configuration/v1/architecture?agent=1");
  $req->content_type('application/json');
  $req->content(to_json($data));

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub powerAgentMapping {
  my($self,$serial,$label) = @_;

  my $json = JSON->new;

  my $req = HTTP::Request->new(GET => $protocol_https.$self->{url}."/api/mapping/v1/power/$serial/$label");
  $req->content_type('application/json');

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();
  my $response;

  eval {
    $response = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  eval {
    $resp = $json->decode($response->content);
  };

  if ($@) {
    my $error = $@;
    error("JSON decode response from API Error: $error");
    print Dumper($response->content);
  }

  return $resp->{data};
}

sub saveStatus {
  my($self,$data) = @_;

  my $json = JSON->new;

  my $req = HTTP::Request->new(POST => $protocol_https.$self->{url}."/api/health_status/v1/store");
  $req->content_type('application/json');
  $req->content(to_json($data));

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub getData {
  my($self,$key) = @_;

  my $json = JSON->new;

  my $req = HTTP::Request->new(GET => $protocol_https.$self->{url}."/api/configuration/v1/microservices/data/".$self->{microservice}."?key=".$key);
  $req->content_type('application/json');

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();
  my $response;

  eval {
    $response = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  eval {
    $resp = $json->decode($response->content);
  };

  if ($@) {
    my $error = $@;
    error("JSON decode response from API Error: $error");
    print Dumper($response->content);
  }

  if (defined $resp->{status}) {
    if ($resp->{status} eq "Failure") {
      error("API Request Failure: ".$resp->{message}." (bad token?)");
    }
  }

  return $resp;
}

sub saveData {
  my($self,$key,$value) = @_;

  my $json = JSON->new;

  my @data;
  $data[0]{microservice} = $self->{microservice};
  $data[0]{key} = $key;
  $data[0]{value} = $value;

  my $req = HTTP::Request->new(POST => $protocol_https.$self->{url}."/api/configuration/v1/microservices/data");
  $req->content_type('application/json');
  $req->content(to_json(\@data));

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub startJob {
  my($self,$job,$identification,$pid) = @_;

  my $json = JSON->new;

  my %data;
  $data{microservice} = $self->{microservice};
  $data{job} = $job;
  $data{identification} = $identification;
  $data{start} = time();
  $data{pid} = $pid ? $pid : 0;

  my $req = HTTP::Request->new(POST => $protocol_https.$self->{url}."/api/configuration/v1/microservices/job/status");
  $req->content_type('application/json');
  $req->content(to_json(\%data));

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub endJob {
  my($self,$job,$identification, $status, $pid) = @_;

  my $json = JSON->new;

  my %data;
  $data{microservice} = $self->{microservice};
  $data{job} = $job;
  $data{identification} = $identification;
  $data{end} = time();
  $data{status} = $status;
  $data{pid} = $pid ? $pid : 0;

  my $req = HTTP::Request->new(POST => $protocol_https.$self->{url}."/api/configuration/v1/microservices/job/status");
  $req->content_type('application/json');
  $req->content(to_json(\%data));

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub registerMetrics {
  my($self,$data) = @_;

  my $json = JSON->new;

  my $req = HTTP::Request->new(POST => $protocol_https.$self->{url}."/api/metrics/v1/definitions");
  $req->content_type('application/json');
  $req->content(to_json($data));

  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header(Authorization => 'Bearer '.$self->{token});

  my $resp = ();

  eval {
    $resp = $ua->request($req);
  };

  if ($@) {
    my $error = $@;
    print STDERR $error;
  }

  return $resp->code;
}

sub log {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  $| = 1;
  print STDOUT "$act_time: $text\n";
  return 1;
}

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  $| = 1;
  print STDERR "$act_time: $text\n";
  return 1;
}

sub conn_test {
  my $success = shift;
  my $data = shift;

  my %conn;
  $conn{message} = $data;
  if ($success eq "1") {
    $conn{connected} = \1;
  } else {
    $conn{connected} = \0;
  }

  return encode_json(\%conn);
}

sub unobscure_password {
  my $string    = shift;
  my $unobscure = DecodeBase64($string);
  $unobscure = unpack( chr( ord("a") + 19 + print "" ), $unobscure );
  return $unobscure;
}

sub DecodeBase64 {
  my $d = shift;
  $d =~ tr!A-Za-z0-9+/!!cd;
  $d =~ s/=+$//;
  $d =~ tr!A-Za-z0-9+/! -_!;
  my $r = '';
  while ( $d =~ /(.{1,60})/gs ) {
    my $len = chr( 32 + length($1) * 3 / 4 );
    $r .= unpack( "u", $len . $1 );
  }
  $r;
}

sub isdigit {
  my $digit = shift;

  if ( !defined($digit) ) {
    return 0;
  }
  if ( $digit eq '' ) {
    return 0;
  }

  if ( $digit eq '-' ) {
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
} ## end sub isdigit

sub isAscii {
  my $string = shift;

  if ( ! defined $string || $string eq '' ) {
    return 1;
  }

  if ( $string =~ /[^!-~\s]/g ) {
    return 0; #Non-ASCII character found
  }
  else {
    return 1;
  }
}

sub save_as_json {
  my $path        = shift;
  my $hash_ref    = shift;
  my $path_suffix = "$path-tmp";
  my $json        = JSON->new->utf8;

  if ( ref($hash_ref) ne "HASH" && ref($hash_ref) ne "ARRAY" ) {
    warn( "Hash ref or array ref expected, got: \"$hash_ref\" (Ref:" . ref($hash_ref) . ") in " . __FILE__ . ":" . __LINE__ . "\n" );
    return 0;
  }

  $json->pretty( [1] );
  $json->canonical( [1] );

  open( FILE, ">", "$path_suffix" ) || error( "Couldn't open file $path_suffix $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FILE $json->encode($hash_ref);
  #print to_json($hash_ref, {utf8 => 1, pretty => 1});
  close(FILE);
  rename( $path_suffix, $path );

  return 1;
}

sub read_json {
  my $file = shift;
  my $encode = shift;
  my $json = JSON->new;
  my $string;
  my $output;

  {
    local $/ = undef;
    if (!defined $encode){
      open( FILE, '<', $file ) or error( "Couldn't open file $file $!" . __FILE__ . ":" . __LINE__ ) && return {};
    }
    else{
      open( FILE, '<:encoding(UTF-8)', $file ) or error( "Couldn't open file $file $!" . __FILE__ . ":" . __LINE__ ) && return {};
    }
    $string = <FILE>;
    close FILE;
  }

  if ($string) {
    eval {
      $output = $json->decode($string);
      1;
    } or do {
      error( "Couldn't parse json file $file $@ " . __FILE__ . ":" . __LINE__ ) && return {};
    };
  }

  return $output;
}

sub create_hash_key {
  my $string = shift;
  my $hash   = substr( md5_hex($string), 0, 10 );
  #print "$string : $hash\n";

  return $hash;
}

sub create_hash_key_long {
  my $string = shift;
  my $hash   = md5_hex($string);
  #print "$string : $hash\n";

  return $hash;
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

sub parse_CSV_line_by_header {
  my $separator    = shift;
  my $header_line  = shift;
  my $data_line    = shift;

  my $data_out;

  #parse header
  my @header = split(/$separator/, $header_line);

  # parse data lines
  my @values    = split(/$separator/, $data_line );
  my $value_idx = 0;
  foreach my $value (@values) {
    if ( defined $header[$value_idx] && $header[$value_idx] ne '' ) {
      if ( $header[$value_idx] ne "" && $value ne '' ) {
        $data_out->{ $header[$value_idx] } = $value;
      }
    }
    $value_idx++;
  }

  return $data_out;
}

sub calculate_weighted_avg {
  my $data = shift;
  my $deb  = shift; # is not mandatory

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
    foreach ( @{ $data} ) {
      #if ( exists $_->{count} && isdigit($_->{count}) && exists $_->{value} && isdigit($_->{value}) ) {
      if ( exists $_->{count} && isdigit($_->{count}) && $_->{count} != 0 && exists $_->{value} && isdigit($_->{value}) ) {
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
    if ( $deb ) {
      print Dumper $data;
      print "$weighted_avg = $value_total / $sum\n";
    }

    return $weighted_avg;
  }
  else {
    return undef;
  }
}

sub calculate_avg {
  my $data = shift;
  my $deb  = shift; # is not mandatory

  # data must be an array
  #$VAR1 = [
  #          '30.434',
  #          '1.744',
  #          '0.000'
  #        ];

  my $sum       = "";
  my $value_idx = 0;

  if ( ref($data) eq "ARRAY" ) {
    foreach my $value_act ( @{ $data} ) {
      if ( isdigit($value_act) ) {
        if ( isdigit($sum) ) {
          $sum += $value_act;
        }
        else {
          $sum = $value_act;
        }
        $value_idx++;
      }
    }
  }
  if ( $value_idx > 0 ) {
    my $avg = sprintf( '%.4f', $sum / $value_idx );

    # debug example:
    #$VAR1 = [
    #          '30.434',
    #          '1.744',
    #          '0.000'
    #        ];
    # 10.7260 = 32.178 / 3
    #$deb = 1;
    if ( $deb ) {
      print Dumper $data;
      print "$avg = $sum / $value_idx\n";
    }

    return $avg;
  }
  else {
    return undef;
  }
}

# accepts two arguments, e.g. returnBytes (100, "GiB"), returnBytes (10, "MB"), returnBytes (10, "kB"), returnBytes (10, "KB")
# and returns number of bytes
# 1 KB = 1 KiB = 1024 B #weird but seems valid
# 1 kB = 1000 B
# 1 KiB = 1024 B #weird but seems valid
# 1 kiB (= 1 KiB?) = 1024 B
sub returnBytes {
    my $number = shift;
    my $suffix = shift;

    unless ( defined $number && isdigit($number) && defined $suffix && $suffix ne '' ) { return ""; }

    my $last_char = chop ($suffix);

    my ($power, $base) = get_power_and_base ($suffix);
    if ($power == -1 || $base == -1){
      #warn "Wrong intput number: $number, suffix: $suffix\n";
      return "";
    }
    if ($last_char eq "b") {
        $number /= 8; #bits to bytes
    }
    return $number * ( $base ** $power );
}

#accepts the suffix e.g. "MB", "GiB" etc and returns base and power to calculate the bytes in returnBytes()
sub get_power_and_base {
    my $suffix = shift;
    my @arr1 = ("","k","M","G","T","P","E","Z","Y","R","Q");
    my @arr2 = ("", "ki","Mi","Gi","Ti","Pi","Ei","Zi","Yi","Ri","Qi");
    my @target_arr = ();
    if ( grep( /^$suffix$/, @arr1 ) ) {
        for (0 .. $#arr1){
            return ($_, 1000) if ($suffix eq $arr1[$_]);
        }
    } elsif ( grep( /^$suffix$/, @arr2 ) ){
        for (0 .. $#arr2){
            return ($_, 1024) if ($suffix eq $arr2[$_]);
        }
    } elsif ( $suffix eq "K") {
        return (1, 1024);
    } elsif ( $suffix eq "Ki") {
        return (1, 1024);
    } else {
        #warn "Error, cannot continue with $suffix\n";
        return (-1, -1);
    }
}

sub formatNumberByType {
  my $type  = shift;
  my $value = shift;

  if ( ! defined $value || $value eq '' || ! isdigit($value) || ! defined $type || $type eq '' ) {
    return "";
  }

  if ( $type eq "int" || $type eq "int2" || $type eq "int4" || $type eq "int8" ) {
    return sprintf( '%.0f', $value);
  }
  elsif ( $type eq "float" || $type eq "float4" || $type eq "float8" ) {
    return sprintf( '%.4f', $value);
  }
  else {
    # unsupported types
    return "";
  }
}

sub formatWWN {
  my $wwn = shift;

  unless ( defined $wwn ) { return ""; }

  $wwn =~ s/://g;
  $wwn =~ s/\s//g;
  $wwn = uc($wwn);

  return $wwn;
}

sub openssh_new {
  my ( $host, $port, $user, $timeout, $passwd, $ctl_dir ) = @_;
  my $ssh = "";
  if ( !defined $ctl_dir ) {
    $ctl_dir = "";
  }
  my $error = "";
  require Net::OpenSSH;

  eval {
    #Set alarm
    my $act_time = localtime();
    local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
    alarm($timeout);
    $password = $passwd;
    if ( !defined($ctl_dir) || $ctl_dir eq '' ) {
      $ctl_dir = tempdir( CLEANUP => 1 );    # It must be there because of : too long for Unix domain socket
    }
    $ssh = Net::OpenSSH->new(
      $host, user => $user, strict_mode => 0, ctl_dir => $ctl_dir,
      master_opts => [
        '-q', -o => 'NumberOfPasswordPrompts=1',
        -p => $port,
        -o => 'StrictHostKeyChecking=no',
        -o => 'ConnectTimeout=80',
        -o => 'PreferredAuthentications=keyboard-interactive,password'
      ],
      login_handler => \&mi_login_handler
    );
    if ( $ssh->error ) {

      #print STDERR ("Error: Unable to connect to remote machine. ".$ssh->error."\n");
      #error("Error: Unable to connect to remote machine " . $ssh->error);
      my $error_local = $ssh->error;
      if ( !defined $error_local ) { $error_local = ""; }
      $error = "Error: Unable to connect to remote machine $error_local";
    }
    alarm(0);
    };
  if ($@) {
    if ( $@ =~ /died in SIG ALRM/ ) {
      return "Error command: ssh login timed out after : $timeout seconds";
    }
    return "Error command: ssh login failed $ssh $@";
  }
  if ( defined $error && $error ne "" ) {
    return $error;
  }
  return $ssh;
}

sub mi_login_handler {
  my ( $ssh, $pty, $data ) = @_;

  # print "custom login handler called!";
  my $read = sysread( $pty, $$data, 1024, length $$data );
  if ($read) {

    # print "buffer: >$$data<\n";
    if ( $$data =~ s/.*://s ) {
      print $pty "$password\n";
      return 1;
    }
  }
  return 0;
}


sub openssh_disconnect {
  my ( $ssh, $timeout ) = @_;
  require Net::OpenSSH;

  my $async = 0;
  my $rc    = 0;
  eval {
    #Set alarm
    my $act_time = localtime();
    local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
    alarm($timeout);
    my $pid;
    $ssh->disconnect($async);
    if ( $ssh->error ) {
      if ( $ssh->error =~ /aborted/ ) {    # async==0 -> aborted
                                           #print STDERR ("openssh_disconnect: ".$ssh->error."\n");
        $rc = 1;
      }
      elsif ( $ssh->error =~ /exit/ ) {    # async==0 -> exit
                                           #print STDERR ("openssh_disconnect: ".$ssh->error."\n");
        $rc = 1;
      }
      else {
        #print STDERR ("Error: openssh_disconnect failed. ".$ssh->error."\n");
        $rc = 0;
      }
    }
    alarm(0);
  };
  if ($@) {
    if ( $@ =~ /died in SIG ALRM/ ) {
      my $act_time = localtime();

      #print STDERR "Error: Session clossing on timed out after : $timeout seconds\n";
      return 0;
    }

    #print STDERR "Error: ".$@."\n";
    return 0;
  }
  return $rc;
}

sub openssh_runcmd {
  my ( $ssh, $cmd, $timeout, $type_data, $st_type ) = ( shift, shift, shift, shift, shift );
  require Net::OpenSSH;

  my $data = {};
  my @data = ();
  eval {
    #Set alarm
    my $act_time = localtime();
    local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
    alarm($timeout);
    if ( $cmd =~ /^scp,/ ) {
      my %param;
      my ( undef, $remote_file, $local_file ) = split( ",", $cmd );
      $data = $ssh->scp_get( \%param, $remote_file, $local_file );
    }
    else {
      if ( defined $type_data && $type_data eq "ARRAY" ) {

        #{stderr_discard => 0},
        @data = $ssh->capture( { stderr_discard => 1 }, $cmd );
      }
      else {
        if    ( !defined $st_type )      { $data = $ssh->capture( { stderr_discard => 1 }, $cmd ); }
        elsif ( $st_type eq "MACROSAN" ) { $data = $ssh->capture( { stderr_discard => 1, stdin_data => $cmd } ); }
      }
    }
    alarm(0);
  };
  if ($@) {
    if ( $@ =~ /died in SIG ALRM/ ) {
      my $act_time = localtime();
      if ( defined $type_data && $type_data eq "ARRAY" ) {
        return "(Error command: $cmd timed out after : $timeout seconds)";
      }
      else {
        return "Error command: $cmd timed out after : $timeout seconds";
      }
    }
    if ( defined $type_data && $type_data eq "ARRAY" ) {
      my $scal = join( "", @data );
      return "(Error command: $cmd : $scal\n)";
    }
    else {
      my @output = %{$data};
      my $scal   = join( "", @output );
      return "Error command: $cmd : $scal\n";
    }
  }
  if ( defined $type_data && $type_data eq "ARRAY" ) {
    return @data;
  }
  return $data;
}

sub conntest_tcp{
  my $host = shift;
  my $port = shift;
  my $timeout = shift;
  if (!Xormon::isdigit($timeout)){
    $timeout = 5;
  }
  my $sock;

  use IO::Socket::INET;
  eval{
    local $SIG{ALRM} = sub { die 'Timed Out'; };
    alarm ($timeout + 5);
    $sock = new IO::Socket::INET(
      PeerAddr => $host,
      PeerPort => $port,
      Proto    => 'tcp',
      Timeout  => $timeout
    );
    alarm 0;
  };
  if ( $@ && $@ =~ /Timed Out/ ) {
      return (0, "TCP connection to $host:$port timed out after 10 seconds!")
  }
  elsif ($sock) {
    return( 1, "TCP connection to $host:$port is OK" );
  }
  else{
    return (0,"TCP connection to $host:$port has failed! Open it on the firewall.");
  }

}

sub conntest_udp {
  my $host    = shift;
  my $port    = shift;
  my $timeout = shift;
  if (!Xormon::isdigit($timeout)){
    $timeout = 5;
  }
  my $socket;
  my @sock;

  use IO::Socket::INET;
  use IO::Select;

  my $ret = scanUDP( $host, $port );

  if ( $ret ) {
    return( 1, "UDP connection to $host:$port is OK" );
  }
  else {
    return (0,"UDP connection to $host:$port has failed! Open it on the firewall.");
  }
}

sub scanUDP {
  my $address = shift;
  my $port    = shift;
  my $socket  = new IO::Socket::INET(
    PeerAddr => $address,
    PeerPort => $port,
    Proto    => 'udp',
  ) or return 0;
  $socket->send( 'Hello', 0 );
  my $select = new IO::Select();
  $select->add($socket);
  my @socket = $select->can_read(1);
  if ( @socket == 1 ) {
    $socket->recv( my $temp, 1, 0 ) or return 0;
    return 1;
  }
  return 1;
}

1;
