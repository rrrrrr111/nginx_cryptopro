#!/bin/sh

set -x

/etc/init.d/cprocsp start
nginx -g 'daemon off;'
