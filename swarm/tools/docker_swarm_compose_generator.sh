#!/bin/bash
set -eu

# Requires https://github.com/webcrofting/meta-compose:
# Online install:
# pip install meta-compose

# Offline (air-gapped) install:
# pip install --no-index --find-links="./meta-compose" meta-compose

rm -rf sites/
mkdir -p sites/

while IFS='' read -r site || [[ -n "$site" ]]; do
    SITE_NAME=$site
    echo "Generating Docker Stack file for $SITE_NAME"
    export SITE_NAME="$SITE_NAME"
    mkdir -p sites/$SITE_NAME
    #/usr/local/bin/meta-compose -t docker-compose-swarm-gpu-standalone.yml.tmpl -o sites/$SITE_NAME/docker-compose-$SITE_NAME.yml
    /usr/local/bin/meta-compose -t docker-compose-swarm-gpu.yml.tmpl -o sites/$SITE_NAME/docker-compose-$SITE_NAME.yml
    cp -R ../../env ../../guacamole sites/$SITE_NAME/
    rm sites/$SITE_NAME/guacamole/user-mapping-local.xml
    sed -i 's/>desktop</>desktop-'$SITE_NAME'\.anyvision\.local</g' sites/$SITE_NAME/guacamole/user-mapping-cloud.xml
    sed -i 's/>sftp</>sftp-'$SITE_NAME'\.anyvision\.local</g' sites/$SITE_NAME/guacamole/user-mapping-cloud.xml
done < "sites.txt"

echo "Done!"
exit 0
