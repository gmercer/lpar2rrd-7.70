#!/bin/bash

if [ "$EUID" -ne 0 ]; then
	echo "Please run as root!"
	exit
fi

# timezone setup script to not restricted location
cp /home/lpar2rrd/lpar2rrd/bin/tz.pl /var/www/cgi-bin/
chmod 755 /var/www/cgi-bin/tz.pl
echo "Fixing timezone settings ..."

# change TZ script location
sed --in-place=.old 's/lpar2rrd-cgi/cgi-bin/g' /var/www/html/index.html

# enable perl script execution in /var/www/cgi-bin/
sed --in-place=.old '/<Directory "\/var\/www\/cgi-bin">/a AddHandler cgi-script .pl' /etc/httpd/conf/httpd.conf

# comment out AllowOverride lines
sed --in-place=.old 's/\(AllowOverride.*\)/# \1/g' /etc/httpd/conf.d/lpar2rrd.conf

# enable Authorization and SetEnv via .htaccess
sed --in-place '/<Directory .*>/a AllowOverride AuthConfig FileInfo' /etc/httpd/conf.d/lpar2rrd.conf

echo "Enable Apache Authorization and SetEnv via .htaccess ..."

# copy .htaccess files to www & lpar2rrd-cgi
cp -p /home/lpar2rrd/lpar2rrd/html/.htaccess /home/lpar2rrd/lpar2rrd/www
cp -p /home/lpar2rrd/lpar2rrd/html/.htaccess /home/lpar2rrd/lpar2rrd/lpar2rrd-cgi
echo "Copying .htaccess files to www & lpar2rrd-cgi ..."

# reload Apache service
echo "Reloading Apache web service ..."
systemctl reload httpd.service

echo "Done. Modified files were saved with .old extension"
echo
echo "Now you can login to LPAR2RRD GUI with this new credentials:"
echo "username: admin"
echo "password: admin"

