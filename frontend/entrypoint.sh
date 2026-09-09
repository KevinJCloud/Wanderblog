#!/bin/sh
sed -i "s|\$API_URL|/api|g" /usr/share/nginx/html/env-config.js
exec "$@"
