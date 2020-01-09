#!/bin/sh -x

# Enable the service
sysrc apache24_enable="YES"
sysrc mysql_enable="YES"

MYSQL_ROOT_PASS=$(openssl rand -base64 20 | md5 | head -c20)

DRUPAL_DB_USER="drupaluser"
DRUPAL_DB_USER_PASS=$(openssl rand -base64 20 | md5 | head -c20)
DRUPAL_DB="drupaldb"

DRUPAL_VER="drupal8"

MY_SERVER_NAME=$(hostname)
MY_SERVER_NAME_ESC=$(hostname | sed 's/\./\\./g')

IP_ADDRESS=$(ifconfig | grep -E 'inet.[0-9]' | grep -v '127.0.0.1' | awk '{ print $2}')

IP_ESC=$(echo $IP_ADDRESS | sed 's/\./\\./g')

# mysql config
 
service mysql-server start
  
mysql_secure_installation <<EOF

y
$MYSQL_ROOT_PASS
$MYSQL_ROOT_PASS
y
y
y
y
EOF
  
echo 'innodb_large_prefix=true' >> /usr/local/my.cnf
echo 'innodb_file_format=barracuda' >> /usr/local/my.cnf
echo 'innodb_file_per_table=true' >> /usr/local/my.cnf 
  
mysql -uroot -p$MYSQL_ROOT_PASS <<EOF
create database ${DRUPAL_DB};
create user ${DRUPAL_DB_USER}@localhost identified by '${DRUPAL_DB_USER_PASS}';
grant all privileges on ${DRUPAL_DB}.* to ${DRUPAL_DB_USER}@localhost identified by '${DRUPAL_DB_USER_PASS}';
flush privileges;
\q
EOF
      
service mysql-server restart

# drupal config

mkdir -p /usr/local/www/$DRUPAL_VER/sites/default/files/private

echo "Drupal Config Starting...."
DRUPAL_ADMIN=$(drush -y site-install standard -r /usr/local/www/${DRUPAL_VER} \
  --db-url="mysql://${DRUPAL_DB_USER}:${DRUPAL_DB_USER_PASS}@localhost/${DRUPAL_DB}" \
  --site-name=${MY_SERVER_NAME} 2>&1 | grep password)
echo "Drupal Config Ending....."
echo $DRUPAL_ADMIN
DRUPAL_ADMIN=$(echo $DRUPAL_ADMIN | awk '{ print $8}')
  
cat >> /usr/local/www/drupal8/sites/default/settings.php << EOF
\$settings['trusted_host_patterns'] = [
  '^$MY_SERVER_NAME_ESC$',
  '^localhost$',
  '^$IP_ESC$',
  '^127\.0\.0\.1$',
];
EOF

chown -R www:www /usr/local/www/$DRUPAL_VER/
  
cat > /usr/local/etc/apache24/Includes/drupal.conf <<EOF
<VirtualHost *:80>
  ServerName $MY_SERVER_NAME
  
  DocumentRoot /usr/local/www/$DRUPAL_VER
  <Directory "/usr/local/www/$DRUPAL_VER">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
<VirtualHost *:443>
  ServerName $MY_SERVER_NAME
  
  SSLEngine on
  SSLCertificateFile "/usr/local/etc/apache24/ssl/certificate.crt"

  SSLCertificateKeyFile "/usr/local/etc/apache24/ssl/private.key"

  DocumentRoot /usr/local/www/$DRUPAL_VER
  <Directory "/usr/local/www/$DRUPAL_VER">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
EOF

# apache config
sed -i.bak '/^#LoadModule ssl_module libexec\/apache24\/mod_ssl.so/s/^#//g' /usr/local/etc/apache24/httpd.conf
  
mkdir -p /usr/local/etc/apache24/ssl
cd /usr/local/etc/apache24/ssl
openssl genrsa -rand -genkey -out private.key 2048
  
openssl req -new -x509 -days 365 -key private.key -out certificate.crt -sha256 -subj "/C=CA/ST=ONTARIO/L=TORONTO/O=Global Security/OU=IT Department/CN=${MY_SERVER_NAME}"
  
cat > /usr/local/etc/apache24/modules.d/020_mod_ssl.conf <<EOF
Listen 443

SSLProtocol ALL -SSLv2 -SSLv3

SSLCipherSuite HIGH:MEDIUM:!aNULL:!MD5

SSLPassPhraseDialog builtin

SSLSessionCacheTimeout 300
EOF
  
sed -i.bak '/^#LoadModule rewrite_module libexec\/apache24\/mod_rewrite.so/s/^#//g' /usr/local/etc/apache24/httpd.conf
  
sed -i.bak '/^#LoadModule mime_magic_module libexec\/apache24\/mod_mime_magic.so/s/^#//g' /usr/local/etc/apache24/httpd.conf
    
sed -i.bak '/AddType application\/x-httpd-php .php/d' /usr/local/etc/apache24/httpd.conf
sed -i.bak '/\<IfModule mime_module\>/a\
AddType application/x-httpd-php .php
' /usr/local/etc/apache24/httpd.conf

# Start the service
service apache24 restart 2>/dev/null
service mysql-server restart 2>/dev/null

echo "drupal8 now installed.\n" > /root/PLUGIN_INFO
echo "\nYour MySQL Root password is \"${MYSQL_ROOT_PASS}\".\n" > /root/PLUGIN_INFO
echo "\nYour Drupal Database password is \"${DRUPAL_DB_USER_PASS}\".\n" > /root/PLUGIN_INFO
echo "\nDrupal Admin user Password is \"${DRUPAL_ADMIN}\".\n" > /root/PLUGIN_INFO
