#!/bin/sh

/etc/init.d/apache2 start
/etc/init.d/redis-server start

tail -F /var/log/apache2/other_vhosts_access.log
