#!/bin/bash


# Requires https://github.com/webcrofting/meta-compose:
# Online install:
# pip install meta-compose
# Offline (air-gapped) install:
# pip install --no-index --find-links="./meta-compose" meta-compose


# Source the optparse.bash file ---------------------------------------------------
source optparse.bash
# Define options
optparse.define short=s long=sites desc="Generate stacks from sites.txt" variable=generate_sites value=true default=true
optparse.define short=b long=ab desc="Generate A/B stacks from sites.txt" variable=generate_ab value=true default=false
optparse.define short=m long=management desc="Generate management stack" variable=generate_management value=true default=true
optparse.define short=a long=apimaster desc="Generate api-master stack" variable=generate_apimaster value=true default=true
optparse.define short=r long=registry desc="Registry URI, for example: \"gcr.io/anyvision-training\" [required]" variable=registry
optparse.define short=p long=port desc="Registry Port, for example: \":5000\" [optional]" variable=port default=""
# Source the output file ----------------------------------------------------------
source $( optparse.build )


docker_warning() {
  echo "Error: This script must be run with Docker capable privileges."
}


# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi


if [ -z "$registry" ]; then
  echo "Error: Registry URI must be provided."
  exit 1
fi

certdir="tls"

export REGISTRY_HOST="$registry"
if [ -n "$port" ]; then
  export REGISTRY_PORT="$port"
fi

set -eu

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
    if [ "$generate_sites" = "true" ] && [ "$generate_ab" = "false" ] ; then
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
if [ "$generate_management" = "true" ] ; then
    echo "Generating Docker Management stack file"
    mkdir -p "$BASEDIR"/stacks/management
    cp -R "$BASEDIR"/../crontab --target-directory="$BASEDIR"/stacks/management/
    ln -s "$BASEDIR"/tls "$BASEDIR"/stacks/management/tls
    /usr/local/bin/meta-compose -t templates/management-stack.yml.tmpl -o "$BASEDIR"/stacks/management/docker-stack-management.yml
fi

## Generate the api-master stack
if [ "$generate_apimaster" = "true" ] ; then
    echo "Generating Docker API-Master stack file"
    mkdir -p "$BASEDIR"/stacks/api-master
    cp -R "$BASEDIR"/../env --target-directory="$BASEDIR"/stacks/api-master/
    ln -s "$BASEDIR"/tls "$BASEDIR"/stacks/api-master/tls
    export SITE_NAME="api-master"
    /usr/local/bin/meta-compose -t templates/api-master-stack.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-api-master.yml
fi

## Generate the ab stack
if [ "$generate_ab" = "true" ] ; then
    echo "Generating Docker \"B\" stack file"
    export SITE_NAME="b"
    mkdir -p "$BASEDIR"/stacks/"$SITE_NAME"
    cp -R "$BASEDIR"/../env --target-directory="$BASEDIR"/stacks/"$SITE_NAME"/
    ln -s "$BASEDIR"/tls "$BASEDIR"/stacks/"$SITE_NAME"/tls
    /usr/local/bin/meta-compose -t templates/node-gpu-stack-b.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-"$SITE_NAME".yml
fi

echo "Done!"
exit 0

