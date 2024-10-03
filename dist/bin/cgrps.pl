
use strict;
use warnings;

# use Data::Dumper;
use ACL;

my $acl = ACL->new();

my $useacl  = $acl->useACL();
my $isAdmin = $acl->isAdmin();

# use lib "../bin";    # maybe useless, but didn't work for me without that
# use CustomGroups;             # use module

print "Content-type: text/html\n\n";

if ( $useacl && !$isAdmin ) {
  print "<div>You must be a member of Administrators group to change custom groups!</div>";
  exit;
}

print <<_MARKER_;
	<div style='float: left; margin-right: 10px; outline: none'>
		<fieldset class='estimator cggrpnames'>
			<table id="cgtree" class="cfgtree">
				<colgroup>
				<col width="2px">
				<col width="2px">
				<col width="220px">
				<col width="10em">
				<col width="10px">
				<col width="20px">
				</colgroup>
				<thead>
				<tr><th></th><th></th><th id="addcgrpth">Custom Group <button id="addcgrp">Add New</button></th> <th>Type</th><th>Set of groups&nbsp;</th><th><a href='https://www.lpar2rrd.com/custom_groups.html' target='_blank'><button id="cgcfg-help-button" title="Help on usage">?</button></a></th></tr>
				</thead>
				<tbody>
				</tbody>
			</table>
		</fieldset>
		<div style="text-align: center">
			<input type='submit' style='font-weight: bold; margin-top: .7em' name='savegrp' id='savegrp' value='Save Custom Groups configuration'>
		</div>
	</div>

<div id='cgtest' style="display: none">
</div>
<br style="clear: both">

<pre>
<div id='aclfile' style='text-align: left; margin: auto; background: #fcfcfc; border: 1px solid #c0ccdf; border-radius: 10px; padding: 15px; display: none; overflow: auto'></div>
</pre>
_MARKER_
