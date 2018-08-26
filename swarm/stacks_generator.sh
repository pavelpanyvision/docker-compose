#!/bin/bash


# Requires https://github.com/webcrofting/meta-compose:
# Online install:
# pip install meta-compose
# Offline (air-gapped) install:
# pip install --no-index --find-links="./meta-compose" meta-compose


# Source the optparse.bash file ---------------------------------------------------
source optparse.bash
# Define options
optparse.define short=s long=sites desc="Generate stacks from sites.txt" variable=generate_sites value=true default=false
optparse.define short=b long=ab desc="Generate A/B stacks from sites.txt" variable=generate_ab value=true default=false
optparse.define short=m long=management desc="Generate management stack" variable=generate_management value=true default=false
optparse.define short=i long=apimaster desc="Generate api-master stack" variable=generate_apimaster value=true default=false
optparse.define short=g long=monitor desc="Generate monitor stack" variable=generate_monitor value=true default=false
optparse.define short=a long=all desc="Generate all stacks" variable=generate_all value=true default=false
optparse.define short=r long=registry desc="Registry URI, for example: \"gcr.io/anyvision-production\" or \"registry.anyvision.local:5000\"" variable=registry
optparse.define short=d long=domain desc="Domain Name, for example: \"anyvision.local\" or \"tls.ai\"" variable=domain
optparse.define short=o long=overwrite desc="Force overwrite stack files" variable=force_overwrite value=true default=false
# Source the output file ----------------------------------------------------------
source $( optparse.build )

docker_warning() {
  echo "Error: This script must be run with Docker capable privileges."
}


if [ "$generate_sites" = "false" ] && [ "$generate_all" = "false" ] && [ "$generate_apimaster" = "false" ] && [ "$generate_management" = "false" ] && [ "$generate_monitor" = "false" ] ; then
  echo "Error: Nothing to generate, please choose which stacks you wish to generate."
  exit 1
fi


# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi

if [ -n "$registry" ]; then
  export REGISTRY_HOST="$registry"
fi

if [ -n "$domain" ]; then
  export DOMAIN_NAME="$domain"
fi

certdir="tls"

set -eu

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")


## Generate unique stack for each site
if [ "$generate_sites" = "true" ] || [ "$generate_ab" = "true" ] || [ "$generate_all" = "true" ]; then
  while IFS='' read -r site || [[ -n "$site" ]]; do
    SITE_NAME="$site"
    export SITE_NAME="$SITE_NAME"
    if [ "$force_overwrite" = "true" ] ; then
        rm -rf "$BASEDIR"/stacks/"$SITE_NAME"
    fi
    mkdir -p "$BASEDIR"/stacks/"$SITE_NAME"
    if [ "$generate_ab" = "false" ] ; then
      echo "Generating Docker stack file for \"$SITE_NAME\""
      /usr/local/bin/meta-compose -t templates/node-gpu-stack.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-"$SITE_NAME".yml
    else
      echo "Generating Docker stack file for \"$SITE_NAME\" as 'A' site"
      /usr/local/bin/meta-compose -t templates/node-gpu-stack-a.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-"$SITE_NAME".yml
    fi
    cp -R -n "$BASEDIR"/../{env,crontab,guacamole} --target-directory="$BASEDIR"/stacks/"$SITE_NAME"/
    ln -sf "$BASEDIR"/tls "$BASEDIR"/stacks/"$SITE_NAME"/tls
    rm "$BASEDIR"/stacks/"$SITE_NAME"/guacamole/user-mapping-local.xml
    sed -i 's/>desktop</>desktop-'"$SITE_NAME"'\.anyvision\.local</g' "$BASEDIR"/stacks/"$SITE_NAME"/guacamole/user-mapping-cloud.xml
    sed -i 's/>sftp</>sftp-'"$SITE_NAME"'\.anyvision\.local</g' "$BASEDIR"/stacks/"$SITE_NAME"/guacamole/user-mapping-cloud.xml
  done < "$BASEDIR"/sites.txt
fi


## Generate the management stack
if [ "$generate_management" = "true" ] || [ "$generate_all" = "true" ]; then
    echo "Generating Docker Management stack file"
    if [ "$force_overwrite" = "true" ] ; then
        rm -rf "$BASEDIR"/stacks/management
    fi
    mkdir -p "$BASEDIR"/stacks/management
    cp -R -n "$BASEDIR"/../crontab --target-directory="$BASEDIR"/stacks/management/
    ln -sf "$BASEDIR"/tls "$BASEDIR"/stacks/management/tls
    /usr/local/bin/meta-compose -t templates/management-stack.yml.tmpl -o "$BASEDIR"/stacks/management/docker-stack-management.yml
fi

## Generate the api-master stack
if [ "$generate_apimaster" = "true" ] || [ "$generate_all" = "true" ]; then
    echo "Generating Docker API-Master stack file"
    if [ "$force_overwrite" = "true" ] ; then
        rm -rf "$BASEDIR"/stacks/api-master
    fi
    mkdir -p "$BASEDIR"/stacks/api-master
    cp -R -n "$BASEDIR"/../env --target-directory="$BASEDIR"/stacks/api-master/
    ln -sf "$BASEDIR"/tls "$BASEDIR"/stacks/api-master/tls
    export SITE_NAME="api-master"
    /usr/local/bin/meta-compose -t templates/api-master-stack.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-api-master.yml
fi

## Generate the ab stack
if [ "$generate_ab" = "true" ] || [ "$generate_all" = "true" ]; then
    echo "Generating Docker \"B\" stack file"
    export SITE_NAME="b"
    if [ "$force_overwrite" = "true" ] ; then
        rm -rf "$BASEDIR"/stacks/"$SITE_NAME"
    fi
    mkdir -p "$BASEDIR"/stacks/"$SITE_NAME"
    #cp -R "$BASEDIR"/../env --target-directory="$BASEDIR"/stacks/"$SITE_NAME"/
    cp -R -n "$BASEDIR"/../{env,crontab,guacamole} --target-directory="$BASEDIR"/stacks/"$SITE_NAME"/
    ln -sf "$BASEDIR"/tls "$BASEDIR"/stacks/"$SITE_NAME"/tls
    /usr/local/bin/meta-compose -t templates/node-gpu-stack-b.yml.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-"$SITE_NAME".yml
fi

## Generate the monitor stack
if [ "$generate_monitor" = "true" ] || [ "$generate_all" = "true" ]; then
    echo "Generating Docker \"monitor\" stack file"
    export SITE_NAME="monitor"
    if [ "$force_overwrite" = "true" ] ; then
        rm -rf "$BASEDIR"/stacks/"$SITE_NAME"
    fi
    mkdir -p "$BASEDIR"/stacks/"$SITE_NAME"
    #cp -R "$BASEDIR"/../env --target-directory="$BASEDIR"/stacks/"$SITE_NAME"/
    cp -R -n "$BASEDIR"/../{env,crontab,guacamole} --target-directory="$BASEDIR"/stacks/"$SITE_NAME"/
    cp -R -n "$BASEDIR"/../managment/monitor --target-directory="$BASEDIR"/stacks/"$SITE_NAME"/
    ln -sf "$BASEDIR"/tls "$BASEDIR"/stacks/"$SITE_NAME"/tls
    /usr/local/bin/meta-compose -t templates/monitor-stack.tmpl -o "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-monitor.yml
fi

echo "Done!"
exit 0
