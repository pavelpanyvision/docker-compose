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
export REGISTRY_HOST="$REGISTRY_HOST"
if [ -n "$REGISTRY_PORT" ]; then
  export REGISTRY_PORT="$REGISTRY_PORT"
fi

rm -rf stacks/
mkdir -p stacks/


## Generate unique stack for each site
while IFS='' read -r site || [[ -n "$site" ]]; do
    SITE_NAME="$site"
    echo "Generating Docker stack file for $SITE_NAME"
    export SITE_NAME="$SITE_NAME"
    mkdir -p stacks/"$SITE_NAME"
    /usr/local/bin/meta-compose -t templates/node-gpu-stack.yml.tmpl -o stacks/"$SITE_NAME"/docker-stack-"$SITE_NAME".yml
    cp -R ../env ../crontab ../guacamole stacks/"$SITE_NAME"/
    if [ -d "$certdir" ]; then
      cp -R "$certdir" stacks/"$SITE_NAME"/
    fi
    rm stacks/"$SITE_NAME"/guacamole/user-mapping-local.xml
    sed -i 's/>desktop</>desktop-'"$SITE_NAME"'\.anyvision\.local</g' stacks/"$SITE_NAME"/guacamole/user-mapping-cloud.xml
    sed -i 's/>sftp</>sftp-'"$SITE_NAME"'\.anyvision\.local</g' stacks/"$SITE_NAME"/guacamole/user-mapping-cloud.xml
done < "sites.txt"

## Generate the management stack
echo "Generating Docker Management stack file"
mkdir -p stacks/management
cp -R ../crontab stacks/management/
cp -R ./tls stacks/management/
/usr/local/bin/meta-compose -t templates/management-stack.yml.tmpl -o stacks/management/docker-stack-management.yml

## Generate the api-master stack
echo "Generating Docker API-Master stack file"
mkdir -p stacks/api-master
cp -R ../env stacks/api-master/
cp -R ./tls stacks/api-master/
export SITE_NAME="api-master"
/usr/local/bin/meta-compose -t templates/api-master-stack.yml.tmpl -o stacks/"$SITE_NAME"/docker-stack-api-master.yml

echo "Done!"
exit 0
