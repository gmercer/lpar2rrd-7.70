package LogCfgChanges;

use strict;
use warnings;

use Data::Dumper;
use File::Temp;
use JSON;
use POSIX;
use utf8;

my $basedir = $ENV{INPUTDIR};
my $cfg_dir = "$basedir/etc/web_config";

sub file_write_append {
  my $file = shift;
  my $IO;
  if ( -f $file ) {
    open $IO, ">>", $file or die "Cannot open $file for output: $!\n";
  }
  else {
    open $IO, ">", $file or die "Cannot open $file for output: $!\n";
  }
  print $IO @_;
  close $IO;
}

sub file_read {
  my $file = shift;
  open my $IO, $file or die "Cannot open $file for input: $!\n";
  my @data = <$IO>;
  close $IO;
  wantarray ? @data : join( '' => @data );
}

sub save_diff {
  my ( $old_json, $new_json, $cfg_file, $user, $options ) = @_;
  $user ||= "admin";

  local $Data::Dumper::Sortkeys = 1;
  local $Data::Dumper::Indent   = 1;
  local $Data::Dumper::Deepcopy = 1;
  local $Data::Dumper::Useperl  = 1;

  {
    no warnings 'redefine';

    sub Data::Dumper::qquote {
      my $s = shift;
      return "'$s'";
    }
  }

  local $JSON::PP::true  = 'true';
  local $JSON::PP::false = 'false';

  my $before = decode_json($old_json);
  my $after  = decode_json($new_json);

  my $bh = File::Temp->new;
  binmode( $bh, "encoding(UTF-8)" );
  print $bh Dumper($before);
  close $bh;

  my $ah = File::Temp->new;
  binmode( $ah, "encoding(UTF-8)" );
  print $ah Dumper($after);
  close $ah;

  my $before_dump = $bh->filename;
  my $after_dump  = $ah->filename;

  $options ||= ( $^O eq 'aix' ) ? '-C 10' : '-a -C 10 -d --label BEFORE --label AFTER';
  my @diff = `diff $options $before_dump $after_dump`;

  if (@diff) {

    foreach my $line (@diff) {
      if ( $line =~ m/.*(password|ssh-key-id|snmp-auth-pass|snmp-priv-pass)\' =>/ ) {
        $line =~ s/=> \'[^\']*\'/=> \'xxxxxxxxxx\'/;
      }
    }

    my @alog;
    my $datetime = strftime "%Y-%m-%d %H:%M:%S", localtime time;
    push @alog, "############################## $datetime ### changes on $cfg_file by $user";
    push @alog, "\n";
    push @alog, @diff;
    push @alog, "\n";
    push @alog, "\n";
    file_write_append( "$cfg_dir/audit.log", @alog );
  }
}

1;
