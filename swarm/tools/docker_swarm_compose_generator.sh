#!/bin/bash
set -eu

# Requires https://github.com/webcrofting/meta-compose:
# Online install:
# pip install meta-compose

# Offline (air-gapped) install:
# pip install --no-index --find-links="./meta-compose" meta-compose

mkdir -p sites/

while IFS='' read -r site || [[ -n "$site" ]]; do
    SITE_NAME=$site
    echo "Generating Docker Compose file for $SITE_NAME"
    export SITE_NAME="$SITE_NAME"
    mkdir -p sites/$SITE_NAME
    /usr/local/bin/meta-compose -t docker-compose-swarm-gpu.yml.tmpl -o sites/$SITE_NAME/docker-compose-$SITE_NAME.yml
    cp -R ../../env ../../guacamole sites/$SITE_NAME/
done < "sites.txt"

echo "Done!"
exit 0
