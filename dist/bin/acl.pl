
use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);

#use Data::Dumper;

print "Content-type: text/html\n\n";

use ACL;    # use module ACL.pm

my $acl = ACL->new;

my $useacl = $acl->useACL;

if ($useacl) {
  my $aclAdmins = $acl->getAdminGroup();

  if ( $acl->isAdmin ) {
    print <<_MARKER_;

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
              <div id='aclgrptree' name='selGroup' class='seltree' style="width: 150px"></div>
            </fieldset>
          </div>
        </td>
        <td>
          <div style='float: left; width: 340px'>
            <fieldset class='estimator'>
              <legend><b>Select objects </b></legend>
              <div id='aclitemstree' name='selPool' class='seltree' style='width: 320px'></div>
            </fieldset>
            <label style='font-size: .8em'><input  style='vertical-align: sub' type="checkbox" id="acl_power_server_ignore">IBM Power Systems: ignore server level for LPARs</label>
          </div>
        </td>
        <!--
        <td>
          <div style='float: left'>
            <fieldset class='estimator'>
              <legend><b>Custom Groups</b></legend>
              <div id='aclcustgrptree' name='selCust' class='seltree' style="width: 150px"></div>
            </fieldset>
          </div>
        </td>
        -->
        <td style="">
          <div style='float: left; padding-left: 20px; min-width: 320px;'>
            <fieldset class="estimator">
              <legend><b>Granted objects overview</b></legend>
              <div id='aclpreview' style='text-align: left; max-height: 34em; overflow: auto'>
                <h4 class="aclh4 acg" style='display: none'>Custom group</h4>
                <div id="acl_cg" class="acd"></div>
                <h4 class="aclh4 apw" style='display: none'>IBM Power: server &rArr; POOL|LPAR</h4>
                <div id="acl_pw" class="acd"></div>
                <h4 class="aclh4 avm" style='display: none'>VMware: cluster &rArr; VM</h4>
                <div id="acl_vm" class="acd"></div>
                <h4 class="aclh4 alinux" style='display: none'>Linux</h4>
                <div id="acl_linux" class="acd"></div>
                <h4 class="aclh4 aun" style='display: none'>Unmanaged: platform &rArr; server</h4>
                <div id="acl_un" class="acd"></div>
                <div id="more_platforms" class="acd" style='display: none'></div>
              </div>
            </fieldset>
          </div>
        </td>
      </div>
      </tr>
      <tr>
        <td colspan='2' align='center'>
        </td>
      </tr>
      </tbody>
    </table>
    </div>
    <p><button style='font-weight: bold' id='saveacl'>Save ACL</button></p>
    <!--<p class="notice">This feature is not supported yet for oVirt/RHV, XenServer, Solaris and MS Windows server/Hyper-V. It will come in future releases.</p>-->
    </div>
  </center>
_MARKER_

  }
  else {
    print <<_MARKER_;
  <div>You are not a member of the ACL Admin Group ($aclAdmins). You cannot change any permissions on LPAR2RRD content.</div>
_MARKER_
  }

}
else {
  print <<_MARKER_;
  <div>Apache authentication is not defined for this tool. Please follow <a href='http://www.lpar2rrd.com/apache_auth.htm' target='_blank'>online instructions</a> to get it work.
  </div>
_MARKER_
}

sub pipes {
  return s/===pipe===/\|/g;
}

sub commaToBR {
  my $str = shift;
  $str =~ s/\,/<br>/g;
  return $str;
}
