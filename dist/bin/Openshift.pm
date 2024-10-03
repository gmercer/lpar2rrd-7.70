package Openshift;

use strict;
use warnings;

use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;
use Scalar::Util qw(looks_like_number);

sub new {
  my ( $self, $cluster, $endpoint, $token, $protocol, $uuid ) = @_;

  my $o = {};
  $o->{cluster}  = $cluster;
  $o->{endpoint} = $endpoint;
  $o->{token}    = $token;
  $o->{protocol} = $protocol;
  $o->{uuid}     = $uuid;
  bless $o, $self;

  return $o;
}

sub getConfiguration {
  my ($self) = @_;

  my %data;

  #infrastructure
  my $url             = $self->{endpoint} . "/apis/config.openshift.io/v1/infrastructures";
  my $infrastructures = $self->apiRequest($url);

  for ( @{ $infrastructures->{items} } ) {
    my $infrastructure = $_;

    $data{infrastructure}{ $infrastructure->{metadata}->{uid} }{name}        = $infrastructure->{metadata}->{name};
    $data{infrastructure}{ $infrastructure->{metadata}->{uid} }{platform}    = $infrastructure->{status}->{platform};
    $data{infrastructure}{ $infrastructure->{metadata}->{uid} }{internalApi} = $infrastructure->{status}->{apiServerInternalURI};
    $data{infrastructure}{ $infrastructure->{metadata}->{uid} }{api}         = $infrastructure->{status}->{apiServerURL};
    $data{infrastructure}{ $infrastructure->{metadata}->{uid} }{domain}      = $infrastructure->{status}->{etcdDiscoveryDomain};

  }

  #projects
  $url = $self->{endpoint} . "/apis/project.openshift.io/v1/projects";
  my $projects = $self->apiRequest($url);

  for ( @{ $projects->{items} } ) {
    my $project = $_;

    $data{project_name}{ $project->{metadata}->{name} }    = $self->{uuid};
    $data{project}{ $project->{metadata}->{uid} }{name}    = $project->{metadata}->{name};
    $data{project}{ $project->{metadata}->{uid} }{cluster} = $self->{uuid};
  }

  return \%data;

}

sub apiRequest {
  my ( $self, $url ) = @_;

  my $protocol = $self->{protocol} . "://";
  my $json     = JSON->new;

  my $ua = LWP::UserAgent->new(
    timeout  => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  $ua->default_header( Authorization => "Bearer $self->{token}" );

  my $resp = $json->decode("{}");

  eval {
    my $response = $ua->get( $protocol . $url );
    $resp = $json->decode( $response->content );
  };

  if ($@) {
    my $error = $@;
    error($error);

    my $response = $ua->get( $protocol . $url );
    error($response);
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
