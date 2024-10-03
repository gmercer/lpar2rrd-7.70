# sshtest.pl
# test connection & authentization over SSH

use 5.008_008;

use strict;
use warnings;
use Xorux_lib;

# get parameters
if ( scalar(@ARGV) < 3 ) {
  print STDERR "error: expected at least three parameters <host> <port> <username> and optional <ssh-key>";
  exit 2;
}

my ( $host, $port, $username, $sshkey ) = @ARGV;

# if the username contains any backslash, e.g., as domain delimiter in Active Directory
$username =~ s/\\/\\\\/g;

if ( !defined $sshkey ) {
  $sshkey = "";
}
my $ssh_cmd = "ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey";
if ( $port ne "" ) {
  $ssh_cmd .= " -p $port ";
}
if ( $sshkey ne "" ) {
  $ssh_cmd .= " -i $sshkey ";
}
$ssh_cmd .= " $username\@$host exit";    # do not use -q, it suppress error outpt !!!

system($ssh_cmd);
if ( $? == 0 ) {
  Xorux_lib::status_json( 1, "User $username\@$host has successfully authenticated." );
  exit 0;
}
elsif ( $? == -1 ) {
  Xorux_lib::status_json( 0, "Failed to execute: $!" );
}
elsif ( $? & 127 ) {
  Xorux_lib::status_json( 0, "SSH command died with signal " . ( $? & 127 ) );
}
else {
  Xorux_lib::status_json( 0, "SSH command exited with value " . ( $? >> 8 ) );
}

exit 1;
