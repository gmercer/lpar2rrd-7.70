
use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);
use JSON;
use Fcntl ':flock';    # import LOCK_* constants
use Xorux_lib;

#use Data::Dumper;

use ACLx;              # use module ACL.pm
my $json = JSON->new->utf8->pretty;

my $useacl = 1;

# get URL parameters (could be GET or POST) and put them into hash %PAR
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

if ( $PAR{cmd} eq "form" ) {    ### Get raw cfg file
  print "Content-type: text/html\n\n";

  #my $aclAdmins = ACL::getAdminGroup();

  #if (ACL::isAdmin) {
  print <<_MARKER_;

  <div style='text-align: center;'>
    <div style='display: inline-block'>
    <div style='float: left; margin-right: 10px; outline: none'>
      <table border='0' cellspacing='5' style="float: left">
      <tbody>
      <tr valign='top'>
        <div>
        <td>
          <div style='float: left'>
            <fieldset class='estimator'>
              <legend><b>ACL group</b></legend>
              <div id='aclxgrptree' name='selGroup' class='seltree' style="width: 150px; max-height: 31em; overflow: auto;"></div>
            </fieldset>
          </div>
        </td>
        <td>
          <div style='float: left; width: 340px'>
            <fieldset class='estimator'>
              <legend><b>Select objects </b><!--label><input type='checkbox' class="showitems" name='showitems' value='true'>Show Items</label--></legend>
              <input type="text" id="aclfilter" placeholder="Filter..." style="text-align: left">
              <div id='acltree' class='seltree' style='width: 320px; overflow: auto;'></div>
            </fieldset>
          </div>
        </td>
        <td style="">
          <div style='float: left; padding-left: 20px; min-width: 320px;'>
            <fieldset class="estimator">
            <legend><b>Granted objects overview</b></legend>
            <div id='aclpreview' style='text-align: left; max-height: 31em; overflow: auto'>
              <h4 class="aclh4 ast" style='display: none'>Storage</h4>
              <div id="acl_st" class="acd"></div>
              <h4 class="aclh4 asan" style='display: none'>SAN</h4>
              <div id="acl_san" class="acd"></div>
              <h4 class="aclh4 alan" style='display: none'>LAN</h4>
              <div id="acl_lan" class="acd"></div>
              <h4 class="aclh4 acg" style='display: none'>Custom group</h4>
              <div id="acl_cg" class="acd"></div>
              </div>
            </fieldset>
          </div>
        </td>
      </div>
      </tr>
      <tr>
        <td colspan='2' align='center'>
          <button style='font-weight: bold' id='saveaclx'>Save ACL</button>
        </td>
      </tr>
      </tbody>
    </table>
    </div>
    </div>
    </div>
  </center>
_MARKER_
}
elsif ( $PAR{cmd} eq "saveacl" ) {    ### Save configuration as is
  my $basedir = $ENV{INPUTDIR};
  $basedir ||= "..";

  my $cfgdir = "$basedir/etc/web_config";

  my $tmpdir = "$basedir/tmp";
  if ( defined $ENV{TMPDIR_LPAR} ) {
    $tmpdir = $ENV{TMPDIR_LPAR};
  }

  # print "Content-type: application/json\n\n";
  print "Content-type: text/html\n\n";
  if ( $PAR{acl} ) {
    my $retstr = "";

    if ( $ENV{'DEMO'} ) {
      $retstr = "\"msg\" : \"<div>This demo site does not allow saving any changes you do in the admin GUI panel.</div>\"";
      $retstr .= ", \"cfg\" : \"\"";
      print "{ \"status\" : \"fail\", $retstr }";
      exit;
    }

    # disable for now...
    if ( open( CFG, ">$cfgdir/acl.json" ) ) {
      flock( CFG, LOCK_EX );
      my $cfg     = $PAR{acl};
      my %new_cfg = %{ decode_json($cfg) };

      # print STDERR Dumper \%new_usr_cfg;
      #if ( $PAR{user} && $new_usr_cfg{users}{$PAR{user}} ) {
      #  $oldcfg{users}{ $PAR{user} } = $new_usr_cfg{users}{$PAR{user}};
      #}
      # print CFG $json->encode( \%new_cfg );
      print CFG encode_json( \%new_cfg );
      close CFG;
      $cfg =~ s/\n/\\n/g;
      $cfg =~ s/\\:/\\\\:/g;
      $cfg =~ s/"/\\"/g;
      $retstr = "\"msg\" : \"<div>ACL configuration has been successfully saved!<br /><br /></div>\", \"cfg\" : \"";
      print "{ \"status\" : \"success\", $retstr" . "$cfg\" }";
    }
    else {
      print "{ \"status\" : \"fail\", \"msg\" : \"<div>File $cfgdir/acl.json cannot be written by webserver, check apache user permissions: <span style='color: red'>$!</span></div>\" }";
    }
  }
  else {
    print "{ \"status\" : \"fail\", \"msg\" : \"<div>No data was written to acl.json</div>\" }";
  }
}
elsif ( $PAR{cmd} eq "json" ) {    ### Get list of credentials
  print "Content-type: application/json\n\n";

  # print Dumper \%ENV;
  # print Dumper \%PAR;
  my $acl = ACLx->new;
  my $cfg = $acl->getRawConfig();
  print $cfg;

}
