#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package IO::Socket::IP;

use strict;
use warnings;
use base qw( IO::Socket );

our $VERSION = '0.05';

use Carp;

use Socket::GetAddrInfo qw(
   :newapi getaddrinfo getnameinfo

   NI_NUMERICHOST NI_NUMERICSERV
   NI_DGRAM
);
use Socket qw(
   SOCK_DGRAM
   SOL_SOCKET
   SO_REUSEADDR SO_REUSEPORT SO_BROADCAST
);

my $IPv6_re = do {
   # translation of RFC 3986 3.2.2 ABNF to re
   my $IPv4address = do {
      my $dec_octet = q<(?:[0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])>;
      qq<$dec_octet(?: \\. $dec_octet){3}>;
   };
   my $IPv6address = do {
      my $h16  = qq<[0-9A-Fa-f]{1,4}>;
      my $ls32 = qq<(?: $h16 : $h16 | $IPv4address)>;
      qq<(?:
                                            (?: $h16 : ){6} $ls32
         |                               :: (?: $h16 : ){5} $ls32
         | (?:                   $h16 )? :: (?: $h16 : ){4} $ls32
         | (?: (?: $h16 : ){0,1} $h16 )? :: (?: $h16 : ){3} $ls32
         | (?: (?: $h16 : ){0,2} $h16 )? :: (?: $h16 : ){2} $ls32
         | (?: (?: $h16 : ){0,3} $h16 )? ::     $h16 :      $ls32
         | (?: (?: $h16 : ){0,4} $h16 )? ::                 $ls32
         | (?: (?: $h16 : ){0,5} $h16 )? ::                 $h16
         | (?: (?: $h16 : ){0,6} $h16 )? ::
      )>
   };
   qr<$IPv6address>xo;
};

=head1 NAME

C<IO::Socket::IP> - Use IPv4 and IPv6 sockets in a protocol-independent way

=head1 SYNOPSIS

 use IO::Socket::IP;

 my $sock = IO::Socket::IP->new(
    PeerHost    => "www.google.com",
    PeerService => "www",
 ) or die "Cannot construct socket - $@";

 printf "Now connected to %s:%s\n", $sock->peerhost_service;

 ...

=head1 DESCRIPTION

This module provides a protocol-independent way to use IPv4 and IPv6 sockets.
It allows new connections to be made by specifying the hostname and service
name or port number. It allows for connections to be accepted by sockets
listening on local ports, by service name or port number.

It uses L<Socket::GetAddrInfo>'s C<getaddrinfo> function to convert
hostname/service name pairs into sets of possible addresses to connect to.
This allows it to work for IPv6 where the system supports it, while still
falling back to IPv4-only on systems which don't.

It provides an API which, for most typical cases, should be a drop-in
replacement for L<IO::Socket::INET>; most constructor arguments and methods
are provided in a compatible way.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $sock = IO::Socket::IP->new( %args )

Creates a new C<IO::Socket::IP> object. If any arguments are passed it will be
configured to contain a newly created socket handle, and be configured
according to the argmuents. The recognised arguments are:

=over 8

=item Type => INT

The socket type (e.g. C<SOCK_STREAM>, C<SOCK_DGRAM>). Will be inferred by 
C<getaddrinfo> from the service name if not supplied.

=item Proto => INT

IP protocol for the socket connection. Will be inferred by C<getaddrinfo> from
the service name, or by the kernel from the socket type, if not supplied.

=item PeerHost => STRING

=item PeerService => STRING

Hostname and service name for the peer to C<connect()> to. The service name
may be given as a port number, as a decimal string.

For symmetry with the accessor methods and compatibility with
C<IO::Socket::INET>, C<PeerAddr> and C<PeerPort> are accepted as synonyms
respectively.

=item Listen => INT

Puts the socket into listening mode where new connections can be accepted
using the C<accept> method.

=item LocalHost => STRING

=item LocalService => STRING

Hostname and service name for the local address to C<bind()> to.

For symmetry with the accessor methods and compatibility with
C<IO::Socket::INET>, C<LocalAddr> and C<LocalPort> are accepted as synonyms
respectively.

=item ReuseAddr => BOOL

If true, set the C<SO_REUSEADDR> sockopt

=item ReusePort => BOOL

If true, set the C<SO_REUSEPORT> sockopt (not all OSes implement this sockopt)

=item Broadcast => BOOL

If true, set the C<SO_BROADCAST> sockopt

=back

If the constructor fails, it will set C<$@> to an appropriate error message;
this may be from C<$!> or it may be some other string; not every failure
necessarily has an associated C<errno> value.

If either C<LocalHost> or C<PeerHost> (or their C<...Addr> synonyms) have any
of the following special forms, they are split to imply both the hostname and
service name:

 hostname.example.org:port    # DNS name
 10.0.0.1:port                # IPv4 address
 [fe80::123]:port             # IPv6 address

In each case, C<port> is passed to the C<LocalService> or C<PeerService>
argument.

Either of C<LocalService> or C<PeerService> (or their C<...Port> synonyms) can
be either a service name, a decimal number, or a string containing both a
service name and number, in the form

 name(number)

In this case, the name will be tried first, but if the resolver does not
understand it then the port number will be used instead.

=head1 $sock = IO::Socket::IP->new( $peeraddr )

As a special case, if the constructor is passed a single argument (as
opposed to an even-sized list of key/value pairs), it is taken to be the value
of the C<PeerAddr> parameter. The example in the SYNOPSIS section may also
therefore be written as

 my $sock = IO::Socket::IP->new( "www.google.com:www" )
    or die "Cannot construct socket - $@";

=cut

sub new 
{
   my $class = shift;
   my %arg = (@_ == 1) ? (PeerHost => $_[0]) : @_;

   $arg{PeerHost} = delete $arg{PeerAddr}
      if exists $arg{PeerAddr} && !exists $arg{PeerHost};

   $arg{PeerService} = delete $arg{PeerPort}
      if exists $arg{PeerPort} && !exists $arg{PeerService};

   $arg{LocalHost} = delete $arg{LocalAddr}
      if exists $arg{LocalAddr} && !exists $arg{LocalHost};

   $arg{LocalService} = delete $arg{LocalPort}
      if exists $arg{LocalPort} && !exists $arg{LocalService};

   for my $type (qw(Peer Local)) {
      my $host    = $type . 'Host';
      my $service = $type . 'Service';

      if (exists $arg{$host} && !exists $arg{$service}) {
         local $_ = $arg{$host};
         defined or next;
         if (/\A\[($IPv6_re)\](?::([^\s:]*))?\z/o || /\A([^\s:]*):([^\s:]*)\z/) {
            $arg{$host}    = $1;
            $arg{$service} = $2 if defined $2 && length $2;
         }
      }
   }
   return $class->SUPER::new(%arg);
}

sub configure
{
   my $self = shift;
   my ( $arg ) = @_;

   my %hints;
   my @localinfos;
   my @peerinfos;

   my @sockopts_enabled;

   if( defined $arg->{Type} ) {
      my $type = delete $arg->{Type};
      $hints{socktype} = $type;
   }

   if( defined $arg->{Proto} ) {
      my $proto = delete $arg->{Proto};

      unless( $proto =~ m/^\d+$/ ) {
         my $protonum = getprotobyname( $proto );
         defined $protonum or croak "Unrecognised protocol $proto";
         $proto = $protonum;
      }

      $hints{protocol} = $proto;
   }

   if( defined $arg->{LocalHost} or defined $arg->{LocalService} ) {
      # Either may be undef
      my $host = delete $arg->{LocalHost};
      my $service = delete $arg->{LocalService};

      defined $service and $service =~ s/\((\d+)\)$// and
         my $fallback_port = $1;

      ( my $err, @localinfos ) = getaddrinfo( $host, $service, \%hints );

      if( $err and defined $fallback_port ) {
         ( $err, @localinfos ) = getaddrinfo( $host, $fallback_port, \%hints );
      }

      $err and ( $@ = "$err", return );
   }

   if( defined $arg->{PeerHost} or defined $arg->{PeerService} ) {
      defined( my $host = delete $arg->{PeerHost} ) or
         croak "Expected 'PeerHost'";
      defined( my $service = delete $arg->{PeerService} ) or
         croak "Expected 'PeerService'";

      defined $service and $service =~ s/\((\d+)\)$// and
         my $fallback_port = $1;

      ( my $err, @peerinfos ) = getaddrinfo( $host, $service, \%hints );

      if( $err and defined $fallback_port ) {
         ( $err, @peerinfos ) = getaddrinfo( $host, $fallback_port, \%hints );
      }

      $err and ( $@ = "$err", return );
   }

   push @sockopts_enabled, SO_REUSEADDR if delete $arg->{ReuseAddr};
   push @sockopts_enabled, SO_REUSEPORT if delete $arg->{ReusePort};
   push @sockopts_enabled, SO_BROADCAST if delete $arg->{Broadcast};

   my $listenqueue = delete $arg->{Listen};

   croak "Cannot Listen with a PeerHost" if defined $listenqueue and @peerinfos;

   keys %$arg and croak "Unexpected keys - " . join( ", ", sort keys %$arg );

   my $socketerr;
   my $binderr;
   my $connecterr;

   foreach my $local ( @localinfos ? @localinfos : {} ) {
      foreach my $peer ( @peerinfos ? @peerinfos : {} ) {

         next if defined $local->{family}   and defined $peer->{family}   and
            $local->{family} != $peer->{family};
         next if defined $local->{socktype} and defined $peer->{socktype} and
            $local->{socktype} != $peer->{socktype};
         next if defined $local->{protocol} and defined $peer->{protocol} and
            $local->{protocol} != $peer->{protocol};

         my $family   = $local->{family}   || $peer->{family}   or next;
         my $socktype = $local->{socktype} || $peer->{socktype} or next;
         my $protocol = $local->{protocol} || $peer->{protocol};

         $self->socket( $family, $socktype, $protocol ) or ( $socketerr = $!, next );

         foreach my $sockopt ( @sockopts_enabled ) {
            $self->setsockopt( SOL_SOCKET, $sockopt, pack "i", 1 ) or ( $@ = "$!", return );
         }

         if( defined( my $addr = $local->{addr} ) ) {
            $self->bind( $addr ) or ( $binderr = $!, next );
         }

         if( defined $listenqueue ) {
            $self->listen( $listenqueue ) or ( $@ = "$!", return );
         }

         if( defined( my $addr = $peer->{addr} ) ) {
            $self->connect( $addr ) or ( $connecterr = $!, next );
         }

         return $self;
      }
   }

   # Pick the most appropriate error, stringified
   $@ = ( $connecterr || $binderr || $socketerr ) . '';
   return undef;
}

=head1 METHODS

=cut

sub _get_host_service
{
   my $self = shift;
   my ( $addr, $numeric ) = @_;

   my $flags = 0;

   $flags |= NI_DGRAM if $self->socktype == SOCK_DGRAM;
   $flags |= NI_NUMERICHOST|NI_NUMERICSERV if $numeric;

   my ( $err, $host, $service ) = getnameinfo( $addr, $flags );
   croak "getnameinfo - $err" if $err;

   return ( $host, $service );
}

=head2 ( $host, $service ) = $sock->sockhost_service( $numeric )

Return the hostname and service name for the local endpoint (that is, the
socket address given by the C<sockname> method).

If C<$numeric> is true, these will be given in numeric form rather than being
resolved into names.

This method is used to implement the following for convenience wrappers. If
both host and service names are required, this method is preferrable to the
following wrappers, because it will call C<getnameinfo(3)> only once.

=cut

sub sockhost_service
{
   my $self = shift;
   my ( $numeric ) = @_;

   $self->_get_host_service( $self->sockname, $numeric );
}

=head2 $addr = $sock->sockhost

Return the numeric form of the local address

=head2 $port = $sock->sockport

Return the numeric form of the local port number

=head2 $host = $sock->sockhostname

Return the resolved name of the local address

=head2 $service = $sock->sockservice

Return the resolved name of the local port number

=cut

sub sockhost { ( shift->sockhost_service(1) )[0] }
sub sockport { ( shift->sockhost_service(1) )[1] }

sub sockhostname { ( shift->sockhost_service(0) )[0] }
sub sockservice  { ( shift->sockhost_service(0) )[1] }

=head2 ( $host, $service ) = $sock->peerhost_service( $numeric )

Similar to the C<sockhost_service> method, but instead returns the hostname
and service name for the peer endpoint (that is, the socket address given by
the C<peername> method).

=cut

sub peerhost_service
{
   my $self = shift;
   my ( $numeric ) = @_;

   $self->_get_host_service( $self->peername, $numeric );
}

=head2 $addr = $sock->peerhost

Return the numeric form of the peer address

=head2 $port = $sock->peerport

Return the numeric form of the peer port number

=head2 $host = $sock->peerhostname

Return the resolved name of the peer address

=head2 $service = $sock->peerservice

Return the resolved name of the peer port number

=cut

sub peerhost    { ( shift->peerhost_service(1) )[0] }
sub peerport    { ( shift->peerhost_service(1) )[1] }

sub peerhostname { ( shift->peerhost_service(0) )[0] }
sub peerservice  { ( shift->peerhost_service(0) )[1] }

# This unbelievably dodgy hack works around the bug that IO::Socket doesn't do
# it
#    https://rt.cpan.org/Ticket/Display.html?id=61577
sub accept
{
   my $self = shift;
   my ( $new, $peer ) = $self->SUPER::accept or return;

   ${*$new}{$_} = ${*$self}{$_} for qw( io_socket_domain io_socket_type io_socket_proto );

   return wantarray ? ( $new, $peer )
                    : $new;
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 TODO

=over 8

=item *

Cache the returns from C<sockhost_service> and C<peerhost_service> to avoid
double-lookup overhead in such code as

  printf "Peer is %s:%d\n", $sock->peerhost, $sock->peerport;

=item *

Implement constructor args C<Timeout>, C<Blocking> and maybe C<Domain>. Except
that C<Domain> is harder because L<IO::Socket> wants to dispatch to subclasses
based on it. Maybe C<Family> might be a better name?

=back

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
