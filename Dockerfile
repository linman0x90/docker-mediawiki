FROM php:5.6-apache
MAINTAINER Synctree App Force <appforce+docker@synctree.com>

ENV MEDIAWIKI_VERSION 1.23
ENV MEDIAWIKI_FULL_VERSION 1.23.8

RUN apt-get update && \
    apt-get install -y g++ libicu52 libicu-dev && \
    pecl install intl && \
    echo extension=intl.so >> /usr/local/etc/php/conf.d/ext-intl.ini && \
    apt-get remove -y g++ libicu-dev 

RUN docker-php-ext-install mysqli opcache

RUN apt-get install -y imagemagick

RUN apt-get install -y php-pear && \
    rm -rf /var/lib/apt/lists/* && \
    pear install mail && \
    pear install Net_SMTP
    
RUN a2enmod rewrite

RUN mkdir -p /usr/src/mediawiki && \
    curl -sSL https://releases.wikimedia.org/mediawiki/$MEDIAWIKI_VERSION/mediawiki-$MEDIAWIKI_FULL_VERSION.tar.gz | \
    tar --strip-components=1 -xzC /usr/src/mediawiki

COPY apache/mediawiki.conf /etc/apache2/
RUN echo Include /etc/apache2/mediawiki.conf >> /etc/apache2/apache2.conf

COPY docker-entrypoint.sh /entrypoint.sh

RUN mkdir /data
RUN ln -s /data/LocalSettings.php /var/www/html/LocalSettings.php
RUN ln -s /data/images /var/www/html/images

VOLUME ["/data"]   

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
