#!/bin/bash
set -eu


# Source the optparse.bash file ---------------------------------------------------
source optparse.bash
# Define options
optparse.define short=s long=sites desc="Deploy stacks from sites.txt" variable=deploy_sites value=true default=false
optparse.define short=m long=management desc="Deploy management stack" variable=deploy_management value=true default=false
optparse.define short=i long=apimaster desc="Deploy api-master stack" variable=deploy_apimaster value=true default=false
optparse.define short=b long=ab desc="Deploy A/B stacks from sites.txt" variable=deploy_ab value=true default=false
optparse.define short=g long=monitor desc="Deploy monitor stack" variable=deploy_monitor value=true default=false
optparse.define short=a long=all desc="Deploy all stacks" variable=deploy_all value=true default=false
optparse.define short=r long=remove desc="Remove stack before deploy" variable=remove value=true default=false
# Source the output file ----------------------------------------------------------
source $( optparse.build )


docker_warning() {
  echo "This script must be run with Docker capable privileges!"
}


# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi


if [ "$deploy_sites" = "false" ] && [ "$deploy_all" = "false" ] && [ "$deploy_apimaster" = "false" ] && [ "$deploy_management" = "false" ] && [ "$deploy_ab" = "false" ] && [ "$deploy_monitor" = "false" ]; then
  echo "Error: Nothing to deploy, please choose which stacks you wish to deploy."
  exit 1
fi


# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")


## Remove and Deploy stack for each site
if [ "$deploy_sites" = "true" ] || [ "$deploy_all" = "true" ]; then
  while IFS='' read -r site || [[ -n "$site" ]]; do
      SITE_NAME="$site"
      if [ "$remove" = "true" ]; then
        echo "Removing stack \"$SITE_NAME\""
        docker stack rm "$SITE_NAME"
        sleep 15
      fi
      echo "Deploying stack \"$SITE_NAME\" using file stacks/$SITE_NAME/docker-stack-$SITE_NAME.yml"
      docker stack deploy --with-registry-auth --resolve-image always -c "$BASEDIR"/stacks/"$SITE_NAME"/docker-stack-"$SITE_NAME".yml "$SITE_NAME"
  done < "$BASEDIR"/sites.txt
fi


## API Master stack
if [ "$deploy_apimaster" = "true" ] || [ "$deploy_all" = "true" ]; then
  if [ "$remove" = "true" ]; then
    echo "Removing stack \"api-master\""
    docker stack rm api-master
    sleep 15
  fi
  echo "Deploying stack \"api-master\" using file stacks/api-master/docker-stack-api-master.yml"
  docker stack deploy --with-registry-auth --resolve-image always -c "$BASEDIR"/stacks/api-master/docker-stack-api-master.yml api-master
fi

## Site B stack
if [ "$deploy_ab" = "true" ] || [ "$deploy_all" = "true" ]; then
  if [ "$remove" = "true" ]; then
    echo "Removing stack \"B\""
    docker stack rm b
    sleep 15
  fi
  echo "Deploying stack \"B\" using file stacks/b/docker-stack-b.yml"
  docker stack deploy --with-registry-auth --resolve-image always -c "$BASEDIR"/stacks/b/docker-stack-b.yml b
fi

## Monitor stack
if [ "$deploy_monitor" = "true" ] || [ "$deploy_all" = "true" ]; then
  if [ "$remove" = "true" ]; then
    echo "Removing stack \"monitor\""
    docker stack rm monitor
    sleep 15
  fi
  echo "Deploying stack \"monitor\" using file stacks/monitor/docker-stack-monitor.yml"
  docker stack deploy --with-registry-auth --resolve-image always -c "$BASEDIR"/stacks/monitor/docker-stack-monitor.yml monitor
fi


## Management stack
if [ "$deploy_management" = "true" ] || [ "$deploy_all" = "true" ]; then
  if [ "$remove" = "true" ]; then
    echo "Removing stack \"management\""
    docker stack rm management
    sleep 15
  fi
  echo "Deploying stack \"management\" using file stacks/management/docker-stack-management.yml"
  docker stack deploy --with-registry-auth --resolve-image always -c "$BASEDIR"/stacks/management/docker-stack-management.yml management
fi


echo "Done!"
#exit 0
