#!/bin/bash
set -eu


# Source the optparse.bash file ---------------------------------------------------
source optparse.bash
# Define options
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


# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")


## Remove and Deploy stack for each site
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


## API Master stack
if [ "$remove" = "true" ]; then
  echo "Removing stack \"api-master\""
  docker stack rm api-master
  sleep 15
fi
echo "Deploying stack \"api-master\" using file stacks/api-master/docker-stack-api-master.yml"
docker stack deploy --with-registry-auth --resolve-image always -c "$BASEDIR"/stacks/api-master/docker-stack-api-master.yml api-master


## Management stack
if [ "$remove" = "true" ]; then
  echo "Removing stack \"management\""
  docker stack rm management
  sleep 15
fi
echo "Deploying stack \"management\" using file stacks/management/docker-stack-management.yml"
docker stack deploy --with-registry-auth --resolve-image always -c "$BASEDIR"/stacks/management/docker-stack-management.yml management


echo "Done!"
exit 0
