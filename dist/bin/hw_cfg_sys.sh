# It is called by lpar2rrd.pl 
# lpar2rrd sends it to hmc to get HW and logical configuration of managed systems
# You can edit it to customize information you want to see in lpar2rrd front-end
# Note that the output of that script is formated :
#  - commas are replaced by spaces
#  - commands which fails or which finish with \"No results found\" or any other error are filtred
#  - and many more

# do not change LANG
export LANG=en_US 

echo \"</PRE><HR><CENTER><B>System overview:</B><font size=\"-1\">(it is generated once a day, last run : \"`date \"+%d.%m.%Y\"`\")</font></CENTER><HR><PRE>\"
lssyscfg -m \"$managedname\" -r sys 2>&1
echo \"</PRE><B>CPU totally:</B><PRE>\"
lshwres -m \"$managedname\" -r proc --level sys 2>&1
echo \"</PRE><A NAME=\"CPU_pool\"></A><B>CPU pool:</B><PRE>\"
lshwres -m \"$managedname\" -r proc --level pool 2>&1
echo \"</PRE><A NAME=\"CPU_pools\"></A><B>CPU pools:</B><PRE>\"
lshwres -m \"$managedname\" -r procpool 2>&1
echo \"</PRE><A NAME=\"Memory\"></A><B>Memory:</B><PRE>\"
lshwres -m \"$managedname\" -r mem --level sys 2>&1
echo \"</PRE><A NAME=\"Memory_AMS\"></A><B>Memory - AMS:</B><PRE>\"
lshwres -m \"$managedname\" -r mempool 2>&1
echo \"</PRE><A NAME=\"Memory_AMS_paging\"></A><B>Memory - AMS - paging:</B><PRE>\"
lshwres -m \"$managedname\" -r mempool --rsubtype pgdev 2>&1
# read only user cannot run "lslic"  
#echo \"</PRE><A NAME=\"Firmware\"></A><B>Firmware:</B><PRE>\"
#lslic -t syspower -m \"$managedname\" 2>&1
echo \"</PRE><B>Physical IO per bus:</B><PRE>\"
lshwres -m \"$managedname\" -r io --rsubtype bus 2>&1|sort -f
echo \"</PRE><B>Physical IO per slot:</B><PRE>\"
lshwres -m \"$managedname\" -r io --rsubtype slot -F drc_name,lpar_name,feature_codes,description 2>&1|sort -f
echo \"</PRE><B>Physical IO per io pool level sys:</B><PRE>\"
lshwres -m \"$managedname\" -r io --rsubtype iopool --level sys 2>&1
echo \"</PRE><B>Physical IO per io pool level pool:</B><PRE>\"
lshwres -m \"$managedname\" -r io --rsubtype iopool --level pool 2>&1
echo \"</PRE><B>Physical IO per slot children:</B><PRE>\"
lshwres -m \"$managedname\" -r io --rsubtype slotchildren 2>&1|sort -f
echo \"</PRE><B>Physical IO per taggedio:</B><PRE>\"
lshwres -m \"$managedname\" -r io --rsubtype taggedio 2>&1
echo \"</PRE><B>Ethernet:</B><PRE>\"
lshwres -m \"$managedname\" -r virtualio --rsubtype eth --level sys  2>&1|sort -f
echo \"</PRE><B>HEA physical per system:</B><PRE>\"
lshwres -m \"$managedname\" -r hea --rsubtype phys --level sys   2>&1|sort -f
echo \"</PRE><B>HEA physical per port:</B><PRE>\"
lshwres -m \"$managedname\" -r hea --rsubtype phys --level port 2>&1|sort -f
echo \"</PRE><B>HEA physical per port group:</B><PRE>\"
lshwres -m \"$managedname\" -r hea --rsubtype phys --level port_group 2>&1|sort -f
echo \"</PRE><B>HEA logical:</B><PRE>\"
lshwres -m \"$managedname\" -r hea --rsubtype logical --level sys 2>&1|sort -f
echo \"</PRE><B>HEA logical per port:</B><PRE>\"
lshwres -m \"$managedname\" -r hea --rsubtype logical --level port 2>&1
echo \"</PRE><B>HCA adapters:</B><PRE>\"
lshwres -m \"$managedname\" -r hca --level sys 2>&1
echo \"</PRE><B>Virtual OptiConnec:</B><PRE>\"
lshwres -m \"$managedname\" -r virtualio --rsubtype virtualopti 2>&1
echo \"</PRE><B>SNI adapters:</B><PRE>\"
lshwres -m \"$managedname\" -r sni 2>&1
echo \"</PRE><B>SR-IOV adapters:</B><PRE>\"
lshwres -m \"$managedname\" -r sriov --rsubtype adapter         2>&1
echo \"</PRE><B>SR-IOV ethernet logical ports:</B><PRE>\"
lshwres -m \"$managedname\" -r sriov --rsubtype logport --level eth        2>&1
echo \"</PRE><B>SR-IOV ethernet physical ports:</B><PRE>\"
lshwres -m \"$managedname\" -r sriov --rsubtype physport --level eth        2>&1
echo \"</PRE><B>SR-IOV converged ethernet physical ports:</B><PRE>\"
lshwres -m \"$managedname\" -r sriov --rsubtype physport --level ethc         2>&1
echo \"</PRE><B>SR-IOV unconfigured logical ports:</B><PRE>\"
lshwres -m \"$managedname\" -r sriov --rsubtype logport         2>&1
echo \"</PRE><B>SR-IOV recoverable logical ports:</B><PRE>\"
lshwres -m \"$managedname\" -r sriov --rsubtype logport -R         2>&1
#echo \"</PRE><B>Capabilities:</B><PRE>\"
#lssyscfg -m \"$managedname\" -r sys -F capabilities         2>&1
echo ""
echo ""
