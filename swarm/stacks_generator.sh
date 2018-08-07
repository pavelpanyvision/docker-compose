#!/bin/bash
set -eu


# Requires https://github.com/webcrofting/meta-compose:
# Online install:
# pip install meta-compose
# Offline (air-gapped) install:
# pip install --no-index --find-links="./meta-compose" meta-compose


certdir="tls"


display_usage() {
  echo -e "\nUsage:\n$0 REGISTRY_HOST [:PORT] --argument1 --argument2 --argument3 --argumentX\n"
  echo -e "Example:\n$0 registry.anyvision.local :5000 --sites --managemnt --api-master\n"
  echo -e "Example:\n$0 gcr.io/anyvision-training --sites --managemnt --api-master\n"
  echo -e "Example:\n$0 gcr.io/anyvision-production --sites --managemnt --ab \n"
}

docker_warning() {
  echo "This script must be run with Docker capable privileges!"
}

# Check params
if [ $# -lt 4 ]; then
  display_usage
  exit 1
fi

# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi

# get extra arguments
generate_sites='false'
generate_managament='false'
generate_apimaster='false'
generate_ab='false'

for i in $*; do
    if [ "${i}" == '--sites' ] ; then
        echo "detected --sites"
        generate_sites='true'
    elif  [ "${i}" == '--managemnt' ] ; then
        echo "detected --managemnt"
        generate_managament='true'
    elif  [ "${i}" == '--api-master' ] ; then
        echo "detected --api-master"
        generate_apimaster='true'
    elif  [ "${i}" == '--ab' ] ; then
        echo "detected --ab"
        generate_ab='true'
    fi
done

certdir="tls"
REGISTRY_HOST="$1"
set +eu

if [[ "$2" =~ [0-9] ]]; then
    REGISTRY_PORT="$2"
else
    echo "no port specified"
    REGISTRY_PORT=""
fi

set -eu
export REGISTRY_HOST="$REGISTRY_HOST"
if [ -n "$REGISTRY_PORT" ]; then
  export REGISTRY_PORT="$REGISTRY_PORT"
fi

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

rm -rf "$BASEDIR"/stacks/
mkdir -p "$BASEDIR"/stacks/


## Generate unique stack for each site
while IFS='' read -r site || [[ -n "$site" ]]; do
    SITE_NAME="$site"
    echo "Generating Docker stack file for $SITE_NAME"
    export SITE_NAME="$SITE_NAME"
    mkdir -p "$BASEDIR"/stacks/"$SITE_NAME"
    if [ $generate_sites == 'true' ] && [ $generate_ab == 'false' ] ; then
        /usr/local/bin/meta-compose -t templates/node-gpu-stack.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-"$SITE_NAME".yml
    else
        /usr/local/bin/meta-compose -t templates/node-gpu-stack-a.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-"$SITE_NAME".yml
    fi
    cp -R "$BASEDIR"/../{env,crontab,guacamole} --target-directory="$BASEDIR"/stacks/"$SITE_NAME"/
    ln -s "$BASEDIR"/tls "$BASEDIR"/stacks/"$SITE_NAME"/tls
    rm "$BASEDIR"/stacks/"$SITE_NAME"/guacamole/user-mapping-local.xml
    sed -i 's/>desktop</>desktop-'"$SITE_NAME"'\.anyvision\.local</g' "$BASEDIR"/stacks/"$SITE_NAME"/guacamole/user-mapping-cloud.xml
    sed -i 's/>sftp</>sftp-'"$SITE_NAME"'\.anyvision\.local</g' "$BASEDIR"/stacks/"$SITE_NAME"/guacamole/user-mapping-cloud.xml
done < "$BASEDIR"/sites.txt



## Generate the management stack
if [ $generate_managament == 'true' ] ; then
    echo "Generating Docker Management stack file"
    mkdir -p "$BASEDIR"/stacks/management
    cp -R "$BASEDIR"/../crontab --target-directory="$BASEDIR"/stacks/management/
    ln -s "$BASEDIR"/tls "$BASEDIR"/stacks/management/tls
    /usr/local/bin/meta-compose -t templates/management-stack.yml.tmpl -o "$BASEDIR"/stacks/management/docker-stack-management.yml
fi

## Generate the api-master stack
if [ $generate_apimaster == 'true' ] ; then
    echo "Generating Docker API-Master stack file"
    mkdir -p "$BASEDIR"/stacks/api-master
    cp -R "$BASEDIR"/../env --target-directory="$BASEDIR"/stacks/api-master/
    ln -s "$BASEDIR"/tls "$BASEDIR"/stacks/api-master/tls
    export SITE_NAME="api-master"
    /usr/local/bin/meta-compose -t templates/api-master-stack.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-api-master.yml
fi

## Generate the ab stack
if [ $generate_ab == 'true' ] ; then
    echo "Generating Docker b stack file"
    export SITE_NAME="b"
    mkdir -p "$BASEDIR"/stacks/"$SITE_NAME"
    cp -R "$BASEDIR"/../env --target-directory="$BASEDIR"/stacks/"$SITE_NAME"/
    ln -s "$BASEDIR"/tls "$BASEDIR"/stacks/"$SITE_NAME"/tls
    /usr/local/bin/meta-compose -t templates/node-gpu-stack-b.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-"$SITE_NAME".yml
fi

echo "Done!"
exit 0

