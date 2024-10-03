
use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;
use File::Copy;
use JSON;
use Fcntl ':flock';    # import LOCK_* constants

use Xorux_lib;
use Users;
use ACL;

my $cfg_filename = "users.json";
if ( defined $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
  $cfg_filename = "users-xormon.json";
}
my $acl = ACL->new;

my $useacl        = $acl->useACL;
my $aclAdminGroup = $acl->getAdminGroup;

my $json = JSON->new->utf8->pretty;

sub file_write {
  my $file = shift;
  open my $IO, ">", $file or die "Cannot open $file for output: $!\n";
  print $IO @_;
  close $IO;
}

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

sub trim {
  my $s = shift;
  if ($s) {
    $s =~ s/^\s+|\s+$//g;
  }
  return $s;
}

my $buffer;

if ( !defined $ENV{'REQUEST_METHOD'} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";

  exit;
}

if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
  read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
}
else {
  $buffer = $ENV{'QUERY_STRING'};
}

my %PAR = %{ Xorux_lib::parse_url_params($buffer) };

# print STDERR Dumper \%PAR;

if ( !defined $PAR{cmd} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";
  exit;
}

if ( $PAR{cmd} eq "test" ) {    ### Get list of credentials
  print "Content-type: text/html\n\n";
  print "<pre>";

  # print Dumper \%ENV;
  # print Dumper \%PAR;
  my $cfg = Users::getRawConfig();
  print Dumper $cfg;

}
elsif ( $PAR{cmd} eq "json" ) {    ### Get list of credentials
  print "Content-type: application/json\n\n";

  # print Dumper \%ENV;
  # print Dumper \%PAR;
  my $cfg = Users::getRawConfig();
  print $cfg;

}
elsif ( $PAR{cmd} eq "form" ) {    ### Get list of credentials

  my %cfg = Users::getConfig();
  print "Content-type: text/html\n\n";

  if ( $acl->getUser() && $useacl ) {

    # TABs
    print "<div id='tabs' style='text-align: center;'>";
    print "<ul>";
    if ( $useacl eq "2" ) {
      print "<li><a href='#tabs-1'>Users</a></li>";
    }
    print "<li><a href='#tabs-2'>Groups</a></li>";
    print "<li><a href='/lpar2rrd-cgi/acl.sh'>ACL</a></li>";
    print "</ul>";

    if ( $useacl eq "2" ) {
      print <<_MARKER_;
<div id='tabs-1' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <fieldset class='estimator cggrpnames'>
      <table id="usertable" class="cfgtree">
        <thead>
        <tr>
          <th>Login <button id="adduser">New</button></th>
          <th>Full name</th>
          <th>Email</th>
          <th>Password</th>
          <!--
          <th>Created</th>
          <th>Last modified</th>
          -->
          <th>Groups</th>
          <th></th>
          <!--th><button id="cgcfg-help-button" title="Help on usage">?</button></th-->
        </tr>
        </thead>
        <tbody>
        </tbody>
      </table>
    </fieldset>
    <!--
    <div style="text-align: center">
      <input type='submit' style='font-weight: bold; margin-top: .7em' name='saveusrcfg' class='saveusrcfg' value='Save configuration'>
    </div>
    -->
  </div>

  <br style="clear: both">
  <pre>
  <div id='aclfile' style='text-align: left; margin: auto; background: #fcfcfc; border: 1px solid #c0ccdf; border-radius: 10px; padding: 15px; display: none; overflow: auto'></div>
  </pre>
</div>

_MARKER_
    }

    print <<_MARKER_;
<div id='tabs-2' style='display: inline-block'>
  <div style='float: left; margin-right: 10px; outline: none'>
    <fieldset class='estimator cggrpnames'>
      <table id="grptable" class="cfgtree">
        <thead>
        <th><button id="addgrp">New group</button></th>
        <th>Description</th>
        <th></th>
        <!--th><button id="cgcfg-help-button" title="Help on usage">?</button></th-->
        </tr>
        </thead>
        <tbody>
        </tbody>
      </table>
    </fieldset>
  </div>
</div>
<style>
#optform  {
  display: table;
}
#optform div {
  display: table-row;
}
#optform label {
  display: table-cell;
}
#optform input {
  display: table-cell;
}
</style>

</div>
_MARKER_
  }
  else {
    print <<_MARKER_;
<div id='tabs' style='text-align: center;'>
  <ul>
    <li><a href='#tabs-1'>ACL</a></li>
  </ul>

<div id='tabs-1' style='display: inline-block'>
  <div>Apache authentication is not defined for this tool. Please follow <a href='http://www.lpar2rrd.com/apache_auth.htm' target='_blank'>online instructions</a> to get it work.
  </div>
</div>
</div>
_MARKER_
  }

}
elsif ( $PAR{cmd} eq "saveall" ) {    ### Save configuration as is
  my $basedir = $ENV{INPUTDIR};
  $basedir ||= "..";

  my $cfgdir = "$basedir/etc/web_config";

  my $tmpdir = "$basedir/tmp";
  if ( defined $ENV{TMPDIR_LPAR} ) {
    $tmpdir = $ENV{TMPDIR_LPAR};
  }
  print "Content-type: text/html\n\n";
  if ( $PAR{acl} ) {
    my %oldcfg  = Users::getConfig();
    my $cfg     = $PAR{acl};
    my $retstr  = "";
    my $isAdmin = $acl->isAdmin();

    if ( $ENV{DEMO} ) {
      my %res = (
        status => "success",
        msg    => "<div>This demo site does not allow saving any changes you do in the admin GUI panel.<br>You can only see the preview of cfg to be written.</div>",
        cfg    => $cfg
      );
      print encode_json ( \%res );
    }
    elsif ( !$isAdmin ) {
      my %res = (
        status => "fail",
        msg    => "<div>You are not a member of admins group, you can only change your own settings</div>"
      );
      print encode_json ( \%res );
    }

    my $old_json = file_read("$cfgdir/$cfg_filename");

    if ( open( my $CFG, ">", "$cfgdir/$cfg_filename" ) ) {
      flock( $CFG, LOCK_EX );
      print $CFG "$cfg\n";
      close $CFG;
      if ( $cfg_filename eq "users.json" ) {    # generate Apache password file only for LPAR2RRD users
        my $htpasswd = Users::getHTPasswords();
        if ( !-o "$cfgdir/htusers.cfg" ) {
          move( "$cfgdir/htusers.cfg", "$cfgdir/.htusers.cfg" );
          chmod 0664, "$cfgdir/.htusers.cfg";
        }
        file_write( "$cfgdir/htusers.cfg", $htpasswd );
        chmod 0664, "$cfgdir/htusers.cfg";
      }
      my %res = (
        status => "success",
        msg    => "<div>Users configuration file has been successfully saved!<br /><br /></div>",
        cfg    => $cfg
      );
      print encode_json ( \%res );

      require LogCfgChanges;
      my $new_json = file_read("$cfgdir/$cfg_filename");
      LogCfgChanges::save_diff( $old_json, $new_json, $cfg_filename, $acl->getUser() );
    }
    else {
      my %res = (
        status => "fail",
        msg    => "<div>File $cfgdir/$cfg_filename cannot be written by webserver, check apache user permissions: <span style='color: red'>$!</span></div>"
      );
      print encode_json ( \%res );
    }
  }
  else {
    my %res = (
      status => "fail",
      msg    => "<div>No data was written to $cfg_filename</div>"
    );
    print encode_json ( \%res );
  }

}
elsif ( $PAR{cmd} eq "saveuser" ) {    ### Get list of credentials
  my $basedir = $ENV{INPUTDIR};
  my %oldcfg  = Users::getConfig();
  my $isAdmin = $acl->isAdmin();
  $basedir ||= "..";

  my $cfgdir = "$basedir/etc/web_config";

  my $tmpdir = "$basedir/tmp";
  if ( defined $ENV{TMPDIR_LPAR} ) {
    $tmpdir = $ENV{TMPDIR_LPAR};
  }
  print "Content-type: text/html\n\n";
  if ( $PAR{acl} ) {
    my $cfg    = $PAR{acl};
    my $retstr = "";
    if ( $ENV{DEMO} ) {
      my %res = (
        status => "success",
        msg    => "<div>This demo site does not allow saving any changes.</div>",
        cfg    => $cfg
      );
      print encode_json ( \%res );

    }
    elsif ( $acl->getUser() ne $PAR{user} && !$isAdmin ) {
      my %res = (
        status => "fail",
        msg    => "<div>You are not a member of admins group, you can only change your own settings</div>"
      );
      print encode_json ( \%res );
    }

    my $old_json = file_read("$cfgdir/$cfg_filename");

    if ( open( my $CFG, ">", "$cfgdir/$cfg_filename" ) ) {
      flock( $CFG, LOCK_EX );
      my %new_usr_cfg = %{ decode_json($cfg) };
      if ( !$isAdmin ) {
        $new_usr_cfg{groups} = $oldcfg{users}{ $PAR{user} }{groups};    # non admin users cannot change groups!
      }

      # print STDERR Dumper \%new_usr_cfg;
      if ( $PAR{user} ) {
        $oldcfg{users}{ $PAR{user} } = \%new_usr_cfg;
      }
      print $CFG $json->encode( \%oldcfg );
      close $CFG;
      my $htpasswd = Users::getHTPasswords();
      file_write( "$cfgdir/htusers.cfg", $htpasswd );
      my %res = (
        status => "success",
        msg    => "<div>Users configuration file has been successfully saved!<br /><br /></div>",
        cfg    => $cfg
      );
      print encode_json ( \%res );

      require LogCfgChanges;
      my $new_json = file_read("$cfgdir/$cfg_filename");
      LogCfgChanges::save_diff( $old_json, $new_json, $cfg_filename, $acl->getUser() );
    }
    else {
      my %res = (
        status => "fail",
        msg    => "<div>File $cfgdir/$cfg_filename cannot be written by webserver, check apache user permissions: <span style='color: red'>$!</span></div>"
      );
      print encode_json ( \%res );
    }
  }
  else {
    my %res = (
      status => "fail",
      msg    => "<div>No data was written to $cfg_filename</div>"
    );
    print encode_json ( \%res );
  }

}
elsif ( $PAR{cmd} eq "savedashboard" ) {
  my $basedir = $ENV{INPUTDIR};
  my $isAdmin = $acl->isAdmin();
  $basedir ||= "..";

  my $cfgdir = "$basedir/etc/web_config";

  my $tmpdir = "$basedir/tmp";
  if ( defined $ENV{TMPDIR_LPAR} ) {
    $tmpdir = $ENV{TMPDIR_LPAR};
  }
  print "Content-type: text/html\n\n";
  if ( $PAR{acl} ) {
    my $cfg    = $PAR{acl};
    my $retstr = "";
    if ( $ENV{DEMO} ) {
      my %res = (
        status => "success",
        msg    => "<div>This demo site does not allow saving any changes.</div>",
        cfg    => $cfg
      );
      print encode_json ( \%res );

    }
    elsif ( $acl->getUser() && ( $acl->getUser() ne $PAR{user} ) && !$isAdmin ) {
      print "{ \"status\" : \"fail\", \"msg\" : \"<div>You are not a member of admins group, you can only change your own settings</div>\" }";
    }
    elsif ( -e "$cfgdir/dashboards.json" && -f _ && -r _ ) {
      if ( $PAR{user} ) {
        my $new_dashboard = decode_json($cfg);
        Users::storeUserDashboard( $PAR{user}, $new_dashboard );

        # warn "Saved $PAR{user} dashboard!";
      }
      print "{}";
    }
    else {
      my %oldcfg = Users::getConfig();
      if ( open( my $CFG, ">", "$cfgdir/$cfg_filename" ) ) {
        flock( $CFG, LOCK_EX );
        local $/ = undef;    # required for re-read of encode_json pretty output
        my $new_dashboard = decode_json($cfg);

        # print STDERR Dumper \%oldcfg;
        if ( $PAR{user} ) {
          $oldcfg{users}{ $PAR{user} }{dashboard} = $new_dashboard;
        }
        print $CFG $json->encode( \%oldcfg );
        close $CFG;
        my %res = (
          status => "success",
          msg    => "<div>Users configuration file has been successfully saved!<br /><br /></div>",
          cfg    => $cfg
        );
        print encode_json ( \%res );
      }
      else {
        my %res = (
          status => "fail",
          msg    => "<div>File $cfgdir/$cfg_filename cannot be written by webserver, check apache user permissions: <span style='color: red'>$!</span></div>"
        );
        print encode_json ( \%res );
      }
    }
  }
  else {
    my %res = (
      status => "fail",
      msg    => "<div>No data was written to $cfg_filename</div>"
    );
    print encode_json ( \%res );
  }

}
elsif ( $PAR{cmd} eq "loaddashboard" ) {
  print "Content-type: application/json\n\n";
  if ( $PAR{user} ) {
    print encode_json ( Users::loadUserDashboard( $PAR{user} ) );
  }
  else {
    print "{}";
  }
}
elsif ( $PAR{cmd} eq "tree" ) {    ### Get list of credentials
  my %cfg = Users::getConfig();
  print "Content-type: application/json\n\n";
  print "[";
  my $n1 = "";

  # print Dumper \%cfg;
  foreach my $usr ( sort keys %{ $cfg{users} } ) {
    print $n1 . "{\"title\":\"$usr\",\"name\":\"$cfg{users}{$usr}{name}\",\"email\":\"$cfg{users}{$usr}{email}\"}\n";
    $n1 = "\n,";
    my $n2 = "";
    foreach my $grp ( sort keys %{ $cfg{groups} } ) {

      # print Dumper $cfg{users}{$usr};
      if ( grep {/$grp/} @{ $cfg{users}{$usr}{groups} } ) {

        #print $n2 . "{\"title\":\"$grp\",\"folder\":\"true\",\"children\":[\n";
        $n2 = "\n,";
      }
    }

    #print "]}\n";
  }
  print "]\n";

}
elsif ( $PAR{cmd} eq "grptree" ) {    ### Get list of credentials
  my %cfg = Users::getConfig();
  print "Content-type: application/json\n\n";
  print "[";
  my $n1 = "";

  # print Dumper \%cfg;
  foreach my $grp ( sort keys %{ $cfg{groups} } ) {
    if ( $grp eq "$aclAdminGroup" || $grp eq "ReadOnly" ) {
      next;
    }
    print $n1 . "{\"title\":\"$grp\"}\n";
    $n1 = "\n,";
  }
  print "]\n";
}

sub userRows {
  my %cfg = Users::getConfig();

  # print Dumper \%cfg;
  foreach my $usr ( sort keys %{ $cfg{users} } ) {
    print "<tr>";
    print "  <td><a href='#' class='userlink'>$usr</a></td>";
    print "  <td>$cfg{users}{$usr}{name}</td>";
    print "  <td>$cfg{users}{$usr}{email}</td>";
    print "  <td>" . jsonTimeToHuman( $cfg{users}{$usr}{created} ) . "</td>";
    print "  <td>" . jsonTimeToHuman( $cfg{users}{$usr}{last_login} ) . "</td>";
    print "  <td>" . join( ', ', @{ $cfg{users}{$usr}{groups} } ) . "</td>";
    if ( $usr ne "admin" ) {
      print "  <td><button>X</button></td>";
    }
    print "</tr>";
  }
}

sub userEdit {
  my %cfg    = Users::getConfig();
  my $grpsel = "";
  foreach my $grp ( sort keys %{ $cfg{groups} } ) {
    if ( grep {/$grp/} @{ $cfg{users}{groups} } ) {
      $grpsel .= "<option selected>$grp</option>";
    }
    else {
      $grpsel .= "<option>$grp</option>";
    }
  }
  print "<td><select style='width: 20em' class='multisel' multiple>$grpsel</select></td>";
}

sub jsonTimeToHuman {
  my $str = shift;
  $str =~ tr/TZ/ /;
  return $str;
}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  $s =~ s/\+/ /g;
  return $s;
}
