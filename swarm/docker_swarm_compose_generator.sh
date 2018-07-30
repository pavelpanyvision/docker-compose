#!/bin/bash
set -eu


# Requires https://github.com/webcrofting/meta-compose:
# Online install:
# pip install meta-compose
# Offline (air-gapped) install:
# pip install --no-index --find-links="./meta-compose" meta-compose


certdir="tls"


display_usage() {
  echo -e "\nUsage:\n$0 REGISTRY_HOST [:PORT]\n"
  echo -e "Example:\n$0 registry.anyvision.local :5000\n"
  echo -e "Example:\n$0 gcr.io/anyvision-training\n"
}

docker_warning() {
  echo "This script must be run with Docker capable privileges!"
}

# Check params
if [ $# -lt 1 ]; then
  display_usage
  exit 1
fi

# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi


certdir="tls"
REGISTRY_HOST="$1"
set +eu
REGISTRY_PORT="$2"
set -eu

rm -rf sites/
mkdir -p sites/


## Generate unique stack for each site
while IFS='' read -r site || [[ -n "$site" ]]; do
    SITE_NAME="$site"
    echo "Generating Docker stack file for $SITE_NAME"
    export SITE_NAME="$SITE_NAME"
    export REGISTRY_HOST="$REGISTRY_HOST"
    if [ -n "$REGISTRY_PORT" ]; then
      export REGISTRY_PORT="$REGISTRY_PORT"
    fi
    mkdir -p sites/"$SITE_NAME"
    /usr/local/bin/meta-compose -t docker-compose-swarm-gpu.yml.tmpl -o sites/"$SITE_NAME"/docker-compose-"$SITE_NAME".yml
    cp -R ../env ../guacamole sites/"$SITE_NAME"/
    if [ -d "$certdir" ]; then
      cp -R "$certdir" sites/"$SITE_NAME"/
    fi
    rm sites/"$SITE_NAME"/guacamole/user-mapping-local.xml
    sed -i 's/>desktop</>desktop-'"$SITE_NAME"'\.anyvision\.local</g' sites/"$SITE_NAME"/guacamole/user-mapping-cloud.xml
    sed -i 's/>sftp</>sftp-'"$SITE_NAME"'\.anyvision\.local</g' sites/"$SITE_NAME"/guacamole/user-mapping-cloud.xml
done < "sites.txt"

## Generate the management stack
echo "Generating Docker Management stack file"
/usr/local/bin/meta-compose -t docker-compose-swarm-mgmt.yml.tmpl -o docker-compose-swarm-mgmt.yml

## Generate the api-master stack
echo "Generating Docker API-Master stack file"
/usr/local/bin/meta-compose -t docker-compose-apimaster.yml.tmpl -o docker-compose-apimaster.yml

echo "Done!"
exit 0
