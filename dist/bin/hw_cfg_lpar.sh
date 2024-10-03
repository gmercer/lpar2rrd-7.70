# It is called by lpar2rrd.pl 
# lpar2rrd sends it to hmc to get HW and logical configuration of lpars
# You can edit it to customize information you want to see in lpar2rrd front-end
# Note that the output of that script is formated :
#  - commas are replaced by spaces
#  - commands which fails or which finish with \"No results found\" or any other error are filtred
#  - and many more


# do not change LANG
export LANG=en_US 

echo \"</PRE><A NAME=\"$lpar_space\"></A><HR><CENTER><B> LPAR : \"$lpar\" </B></CENTER><HR><PRE>\"
echo \"</PRE><B>LPAR config:</B><PRE>\"
lssyscfg -m \"$managedname\" -r lpar --filter lpar_names=\"$lpar\" 2>&1
echo \"</PRE><B>LPAR profiles:</B><PRE>\"
lssyscfg -m \"$managedname\" -r prof --filter lpar_names=\"$lpar\" 2>&1
echo \"</PRE><B>CPU resources:</B><PRE>\"
lshwres -m \"$managedname\" -r proc --level lpar --filter lpar_names=\"$lpar\" 2>&1
echo \"</PRE><B>Memory resources [MB]:</B><PRE>\"
lshwres -m \"$managedname\" -r mem --level lpar --filter lpar_names=\"$lpar\" 2>&1
echo \"</PRE><B>Physical adapters:</B><PRE>\"
lshwres -m \"$managedname\" -r io --rsubtype slot --filter lpar_names=\"$lpar\" 2>&1|sort
echo \"</PRE><B>Logical HEA: </B><PRE>\"
lshwres -m \"$managedname\" -r hea --rsubtype logical --level port --filter lpar_names=\"$lpar\" 2>&1|sort
echo \"</PRE><B>Logical HEA per system:</B><PRE>\"
lshwres -m \"$managedname\" -r hea --rsubtype logical --level sys --filter lpar_names=\"$lpar\" 2>&1|sort
echo \"</PRE><B>Virtual slots:</B><PRE>\"
lshwres -m \"$managedname\" -r virtualio --rsubtype slot --level slot --filter lpar_names=\"$lpar\" 2>&1|sort -nk 2 -t=
echo \"</PRE><B>Virtual serial:</B><PRE>\"
lshwres -m \"$managedname\" -r virtualio --rsubtype serial --level lpar --filter lpar_names=\"$lpar\" 2>&1|sort -nk 2 -t=
echo \"</PRE><B>Virtual VASI:</B><PRE>\"
lshwres -m \"$managedname\" -r virtualio --rsubtype vasi --level lpar --filter lpar_names=\"$lpar\" 2>&1|sort -nk 2 -t=
echo \"</PRE><B>Virtual Ethernet:</B><PRE>\"
lshwres -m \"$managedname\" -r virtualio --rsubtype eth --level lpar --filter lpar_names=\"$lpar\" 2>&1|sort -nk 2 -t=
echo \"</PRE><B>Virtual SCSI:</B><PRE>\"
lshwres -m \"$managedname\" -r virtualio --rsubtype scsi --level lpar --filter lpar_names=\"$lpar\" 2>&1|sort -nk 2 -t=
echo \"</PRE><B>Virtual slots per lpar:</B><PRE>\"
lshwres -m \"$managedname\" -r virtualio --rsubtype slot --level lpar --filter lpar_names=\"$lpar\" 2>&1
echo \"</PRE><B>Virtual OptiConnec:</B><PRE>\"
lshwres -m \"$managedname\" -r virtualio --rsubtype virtualopti --level lpar --filter lpar_names=\"$lpar\" 2>&1|sort
echo \"</PRE><B>HCA adapters:</B><PRE>\"
lshwres -m \"$managedname\" -r hca --level lpar --filter lpar_names=\"$lpar\" 2>&1|sort

