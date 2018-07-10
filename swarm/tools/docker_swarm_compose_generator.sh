#!/bin/bash
set -eu

# Requirements:
# pip install meta-compose

# From https://github.com/webcrofting/meta-compose

mkdir -p sites/

while IFS='' read -r site || [[ -n "$site" ]]; do
    SITE_NAME=$site
    echo "Generating Docker Compose file for $SITE_NAME"
    export SITE_NAME="$SITE_NAME"
    meta-compose -t docker-compose-swarm-gpu.yml.tmpl -o sites/docker-compose-$SITE_NAME.yml
done < "sites.txt"

echo "Done!"
exit 0
