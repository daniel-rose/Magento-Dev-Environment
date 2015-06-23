#!/usr/bin/env bash

MAGENTO_VERSION="magento-ce-1.9.1.1"
MAGENTO_PARENT_DIRECTORY="/var/www/"
MAGENTO_DIRECTORY="/var/www/html/"

VENDOR_DIRECTORY="/var/www/vendor/"

DB_HOST="localhost"
DB_NAME="magentodb"
TEST_DB_NAME="magentodb_test"
DB_USER="magentouser"
DB_PASSWORD="password"

BASE_URL="http://127.0.0.1:8080/"

TOOLS_DIRECTORY="/opt/tools/"

XDEBUG_CONF=$(cat <<EOF
xdebug.remote_enable = 1
xdebug.remote_connect_back = 1
xdebug.remote_port = 9000
xdebug.scream=0 
xdebug.cli_color=1
xdebug.show_local_vars=1
EOF
)

FASTCGI_CONF=$(cat <<EOF
<IfModule mod_fastcgi.c>
	AddType application/x-httpd-fastphp5 .php
	Action application/x-httpd-fastphp5 /php5-fcgi
	Alias /php5-fcgi /usr/lib/cgi-bin/php5-fcgi
	FastCgiExternalServer /usr/lib/cgi-bin/php5-fcgi -socket /var/run/php5-fpm.sock -pass-header Authorization
	<Directory /usr/lib/cgi-bin>
		Require all granted
	</Directory>
</IfModule>
EOF
)

COMPOSER_JSON=$(cat <<EOF
{
    "minimum-stability":"dev",
    "require":{
        "aoepeople/aoe_profiler":"*",
        "aoepeople/aoe_templatehints":"*",
        "firegento/magesetup":"*",
        "riconeitzel/german-localepack-de-de":"*",
        "ecomdev/ecomdev_phpunit":"*"
    },
    "repositories":[
        {
            "type":"composer",
            "url":"http://packages.firegento.com"
        }
    ],
    "extra":{
        "magento-root-dir":"./html/"
    }
}
EOF
)

function installN98MageRun() {
	echo "Installing n98-magerun"
	
	cd ${TOOLS_DIRECTORY}
	wget https://raw.github.com/netz98/n98-magerun/master/n98-magerun.phar 2> /dev/null
	chmod +x ./n98-magerun.phar
	ln -s ${TOOLS_DIRECTORY}n98-magerun.phar /usr/local/bin/n98-magerun
}

function installModman() {
	echo "Installing Modman"

	cd ${TOOLS_DIRECTORY}
	wget https://raw.githubusercontent.com/colinmollenhour/modman/master/modman 2> /dev/null
	chmod +x modman
	ln -s ${TOOLS_DIRECTORY}modman /usr/local/bin/modman
}

function installPHPUnit() {
	echo "Installing PHP-Unit"

	cd ${TOOLS_DIRECTORY}
	wget https://phar.phpunit.de/phpunit.phar 2> /dev/null
	chmod +x phpunit.phar
	ln -s ${TOOLS_DIRECTORY}phpunit.phar /usr/local/bin/phpunit
}

function installComposer() {
	echo "Installing Composer"
	
	cd ${TOOLS_DIRECTORY}
	curl -sS https://getcomposer.org/installer | php -- --install-dir ${TOOLS_DIRECTORY} 2> /dev/null
	ln -s ${TOOLS_DIRECTORY}composer.phar /usr/local/bin/composer
}

function installMagento() {
	echo "Installing Magento"

	chown www-data:www-data ${MAGENTO_PARENT_DIRECTORY} -R
	chmod g+w ${MAGENTO_PARENT_DIRECTORY} -R

	sudo -u vagrant n98-magerun install --dbHost="${DB_HOST}" --dbUser="${DB_USER}" --dbPass="${DB_PASSWORD}" --dbName="${DB_NAME}" \
	--installSampleData=no --useDefaultConfigParams=yes --magentoVersionByName="${MAGENTO_VERSION}" \
	--installationFolder="${MAGENTO_DIRECTORY}" --baseUrl="${BASE_URL}"

	#chown www-data:www-data ${MAGENTO_DIRECTORY} -R

	cd ${MAGENTO_DIRECTORY}
	
	sudo -u vagrant n98-magerun config:set dev/template/allow_symlink 1
	sudo -u vagrant n98-magerun config:set dev/log/active 1
	sudo -u vagrant n98-magerun config:set web/seo/use_rewrites 0

	cd ../
	sudo -u vagrant echo ${COMPOSER_JSON} > composer.json
	sudo -u vagrant composer install

	cd ${MAGENTO_DIRECTORY}

	sudo -u vagrant n98-magerun db:dump --stdout | mysql -u ${DB_USER} --password=${DB_PASSWORD} ${TEST_DB_NAME}

	sudo -u vagrant n98-magerun cache:clean
	sudo -u vagrant n98-magerun cache:flush

	cd shell
	sudo -u vagrant php ecomdev-phpunit.php -a install
	sudo -u vagrant php ecomdev-phpunit.php -a magento-config --db-name ${TEST_DB_NAME} --base-url ${BASE_URL}
}

echo "Adding user vagrant to group www-data"
usermod -a -G www-data vagrant

echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo "Add multiverse repository"
apt-add-repository multiverse

echo "Updating Ubuntu-Repositories"
apt-get update 2> /dev/null

echo "Installing Git"
apt-get install git -y 2> /dev/null

echo "Installing Apache2"
apt-get install apache2-mpm-worker -y 2> /dev/null

echo "Installing PHP5-FPM & PHP5-CLI"
apt-get install libapache2-mod-fastcgi php5-fpm php5-cli -y 2> /dev/null

echo "Installing PHP extensions"
apt-get install curl php5-xdebug php-apc php5-curl php5-gd php5-mcrypt php5-mysql -y 2> /dev/null

echo "Enable FastCGI-Module"
a2enmod actions fastcgi alias 2> /dev/null

echo "Enable rewrite-Module"
a2enmod rewrite 2> /dev/null

echo "Enable mcrypt-Module"
php5enmod mcrypt 2> /dev/null

echo "${FASTCGI_CONF}" > /etc/apache2/mods-enabled/fastcgi.conf

echo "Set memory limit to 512 MB"
sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php5/fpm/php.ini 2> /dev/null

if ! grep -q 'xdebug.remote_enable = 1' /etc/php5/mods-available/xdebug.ini; then
	echo "${XDEBUG_CONF}" >> /etc/php5/mods-available/xdebug.ini
fi

echo "Restart PHP5-FPM"
service php5-fpm restart 2> /dev/null

echo "Restart Apache2"
service apache2 restart 2> /dev/null

echo "Installing DebConf-Utils"
apt-get install debconf-utils -y 2> /dev/null

debconf-set-selections <<< "mysql-server mysql-server/root_password password password"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password password"

echo "Installing MySQL-Server"
apt-get install mysql-server -y 2> /dev/null

echo "Creating Databases"
mysql -u root --password="password" -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password="password" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}'"
mysql -u root --password="password" -e "FLUSH PRIVILEGES"

mysql -u root --password="password" -e "CREATE DATABASE IF NOT EXISTS ${TEST_DB_NAME}"
mysql -u root --password="password" -e "GRANT ALL PRIVILEGES ON ${TEST_DB_NAME}.* TO '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}'"
mysql -u root --password="password" -e "FLUSH PRIVILEGES"

debconf-set-selections <<< 'phpmyadmin phpmyadmin/dbconfig-install boolean false'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2'
 
debconf-set-selections <<< 'phpmyadmin phpmyadmin/app-password-confirm password password'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/admin-pass password password'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/password-confirm password password'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/setup-password password password'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/database-type select mysql'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/app-pass password password'
 
debconf-set-selections <<< 'dbconfig-common dbconfig-common/mysql/app-pass password password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/mysql/app-pass password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/password-confirm password password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/app-password-confirm password password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/app-password-confirm password password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/password-confirm password password'

echo "Installing PHPMyAdmin"
apt-get install phpmyadmin -y 2> /dev/null

if [[ ! -d ${TOOLS_DIRECTORY} ]]; then
	cd /opt
	mkdir tools
fi

if [[ -f "/var/www/html/index.html" ]]; then
	echo "Removing index.html"
	rm /var/www/html/index.html 2> /dev/null
fi

if [[ ! -f "/usr/local/bin/n98-magerun" ]]; then
	installN98MageRun
fi

if [ ! -f "/usr/local/bin/modman" ]; then
	installModman
fi

if [ ! -f "/usr/local/bin/phpunit" ]; then
	installPHPUnit
fi

if [ ! -f "/usr/local/bin/composer" ]; then
	installComposer
fi

if [ ! -f "${MAGENTO_DIRECTORY}app/etc/local.xml" ]; then
	installMagento
fi