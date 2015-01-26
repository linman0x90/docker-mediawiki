#!/bin/bash

set -e

: ${MEDIAWIKI_SITE_NAME:=MediaWiki}

if [ -z "$MEDIAWIKI_DB_HOST" -a -z "$MYSQL_PORT_3306_TCP" ]; then
	echo >&2 'error: missing MYSQL_PORT_3306_TCP environment variable'
	echo >&2 '  Did you forget to --link some_mysql_container:mysql ?'
	exit 1
fi

# if we're linked to MySQL, and we're using the root user, and our linked
# container has a default "root" password set up and passed through... :)
: ${MEDIAWIKI_DB_USER:=root}
if [ "$MEDIAWIKI_DB_USER" = 'root' ]; then
	: ${MEDIAWIKI_DB_PASSWORD:=$MYSQL_ENV_MYSQL_ROOT_PASSWORD}
fi
: ${MEDIAWIKI_DB_NAME:=mediawiki}

if [ -z "$MEDIAWIKI_DB_PASSWORD" ]; then
	echo >&2 'error: missing required MEDIAWIKI_DB_PASSWORD environment variable'
	echo >&2 '  Did you forget to -e MEDIAWIKI_DB_PASSWORD=... ?'
	echo >&2
	echo >&2 '  (Also of interest might be MEDIAWIKI_DB_USER and MEDIAWIKI_DB_NAME.)'
	exit 1
fi

if ! [ -e index.php -a -e includes/DefaultSettings.php ]; then
	echo >&2 "MediaWiki not found in $(pwd) - copying now..."

	if [ "$(ls -A)" ]; then
		echo >&2 "WARNING: $(pwd) is not empty - press Ctrl+C now if this is an error!"
		( set -x; ls -A; sleep 10 )
	fi
	tar cf - --one-file-system -C /usr/src/mediawiki . | tar xf -
	echo >&2 "Complete! MediaWiki has been successfully copied to $(pwd)"

	echo >&2 "Installing Semantic MediaWiki Extensions."
	curl -sS https://getcomposer.org/installer | php
	php composer.phar require mediawiki/semantic-media-wiki "~2.1"
	# To finish enableing Semantic Extensions add "enableSemantics( 'example.org' );" to LocalSettings.php
	echo >&2 "Complete! Semantic MediaWiki Extensions installed."

	echo >&2 "Installing Widget Extension."
	cd extensions
	git clone https://gerrit.wikimedia.org/r/p/mediawiki/extensions/Widgets.git
	cd Widgets
	git submodule init
	git submodule update
	wget http://www.smarty.net/files/Smarty-stable.tar.gz
	tar xzf Smarty-stable.tar.gz
	mv Smarty-*.*.*/libs .
	rm -rf Smarty-*.*.*/
	chown -R www-data:www-data .
	chmod a+rw compiled_templates
	echo >&2 "Complete! Semantic MediaWiki Extensions installed."
	
	echo >&2 "Installing Adsense2 Extensions."
	wget https://extdist.wmflabs.org/dist/extensions/GoogleAdSense-REL1_23-0b0688f.tar.gz
	tar xzf GoogleAdSense-REL1_23-0b0688f.tar.gz -C /var/www/html/extensions
	rm -rf GoogleAdSense-REL1_23-0b0688f.tar.gz
	chown -R www-data:www-data  /var/www/html/extensions
        echo >&2 "Complete! Adsense2 Extensions installed."

	#echo >&2 "Installing VisualEditor Extension."
	#wget https://extdist.wmflabs.org/dist/extensions/VisualEditor-REL1_23-9883566.tar.gz
	#tar -xzf VisualEditor-REL1_23-9883566.tar.gz -C /var/www/html/extensions
	#chown -R www-data:www-data  /var/www/html/extensions
	#rm -rf VisualEditor-REL1_23-9883566.tar.gz
	#echo >&2 "Complete! VisualEditor Extensions installed."
	

	cd /var/www/html/
	php maintenance/update.php
fi

: ${MEDIAWIKI_SHARED:=/var/www-shared/html}
if [ -d "$MEDIAWIKI_SHARED" ]; then
	# If there is no LocalSettings.php but we have one under the shared
	# directory, symlink it
	if [ -e "$MEDIAWIKI_SHARED/LocalSettings.php" -a ! -e LocalSettings.php ]; then
		ln -s "$MEDIAWIKI_SHARED/LocalSettings.php" LocalSettings.php
	fi

	# If the images directory only contains a README, then link it to
	# $MEDIAWIKI_SHARED/images, creating the shared directory if necessary
	if [ "$(ls images)" = "README" -a ! -L images ]; then
		rm -fr images
		mkdir -p "$MEDIAWIKI_SHARED/images"
		ln -s "$MEDIAWIKI_SHARED/images" images
	fi
fi

: ${MEDIAWIKI_DB_HOST:=${MYSQL_PORT_3306_TCP#tcp://}}

TERM=dumb php -- "$MEDIAWIKI_DB_HOST" "$MEDIAWIKI_DB_USER" "$MEDIAWIKI_DB_PASSWORD" "$MEDIAWIKI_DB_NAME" <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

list($host, $port) = explode(':', $argv[1], 2);
$mysql = new mysqli($host, $argv[2], $argv[3], '', (int)$port);

if ($mysql->connect_error) {
	file_put_contents('php://stderr', 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
	exit(1);
}

if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($argv[4]) . '`')) {
	file_put_contents('php://stderr', 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
	$mysql->close();
	exit(1);
}

$mysql->close();
EOPHP

chown -R www-data: .

#Setup Images folder in data volume if it doesn't already exist
if ! [ -e /data/images/.htaccess ]; then
    if ! [ -d /data/images ]; then
        mkdir /data/images
    fi
    chown -R www-data:www-data /data/images
    chmod -R 0755 /data/images
    
    mv /var/www/html/images /tmp/images
    ln -s /data/images /var/www/html/images
    mv /tmp/images/* /data/images/
    rm -rf /tmp/images
    chown -R www-data:www-data /var/www/html/images
    chmod -R 0755 /var/www/html/images
    
fi

#Setup skins folder in data volume if it doesn't already exist
if ! [ -d /data/skins ]; then
    mkdir /data/skins
    chown -R www-data:www-data /data/skins
    chmod -R 0755 /data/skins
    mv /var/www/html/skins /tmp/skins
    ln -s /data/skins /var/www/html/skins
    mv /tmp/skins/* /data/skins/
    rm -rf /tmp/skins
    chown -R www-data:www-data /var/www/html/skins
    chmod -R 0755 /var/www/html/skins
fi


export MEDIAWIKI_SITE_NAME MEDIAWIKI_DB_HOST MEDIAWIKI_DB_USER MEDIAWIKI_DB_PASSWORD MEDIAWIKI_DB_NAME

exec "$@"
