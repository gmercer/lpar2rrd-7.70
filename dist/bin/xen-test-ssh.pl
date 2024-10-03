# xen-test-ssh.pl
# test connection to a XenServer host over SSH and test the environment

use 5.008_008;

use strict;
use warnings;
use LWP::UserAgent;
use JSON qw(encode_json);
use Xorux_lib;

# get parameters
if ( scalar(@ARGV) < 4 ) {
  print STDERR "error: expected four parameters <host> <port> <username> <ssh-key> \n";
  exit 2;
}

my ( $host, $port, $username, $sshkey ) = @ARGV;

# if the username contains any backslash, e.g., as domain delimiter in Active Directory
$username =~ s/\\/\\\\/g;

my $ssh_cmd = "ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey";
if ( $port ne '' ) {
  $ssh_cmd .= " -p $port ";
}
if ( $sshkey ne '' ) {
  $ssh_cmd .= " -i $sshkey ";
}
$ssh_cmd .= "-q $username\@$host ";
$ssh_cmd .= "\"xe host-list --minimal\"";

system($ssh_cmd);
if ( $? == 0 ) {
  Xorux_lib::status_json( 1, 'The connection and environment test has been successful.' );
  exit 0;
}
elsif ( $? == -1 ) {
  Xorux_lib::status_json( 0, "Failed to execute: $!" );
}
elsif ( $? & 127 ) {
  Xorux_lib::status_json( 0, 'SSH command died with signal ' . ( $? & 127 ) );
}
else {
  my $exit_code = $? >> 8;

  if ( $exit_code == 1 ) {
    Xorux_lib::status_json( 0, 'The user $username does not have neccessary rights. Check XenServer RBAC.' );
  }
  elsif ( $exit_code == 127 ) {
    Xorux_lib::status_json( 0, "The host $host does not provide the 'xe' command from Xen API." );
  }
  else {
    Xorux_lib::status_json( 0, "SSH command exited with value $exit_code." );
  }
}

exit 1;
