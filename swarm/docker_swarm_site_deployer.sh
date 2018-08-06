#!/bin/bash
set -eu


docker_warning() {
  echo "This script must be run with Docker capable privileges!"
}


# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi


## Remove and Deploy stack for each site
while IFS='' read -r site || [[ -n "$site" ]]; do
    SITE_NAME="$site"
    echo "Removing stack \"$SITE_NAME\""
    docker stack rm "$SITE_NAME"
    echo "Deploying stack \"$SITE_NAME\" using file sites/$SITE_NAME/docker-compose-$SITE_NAME.yml"
    docker stack deploy --with-registry-auth -c sites/"$SITE_NAME"/docker-compose-"$SITE_NAME".yml "$SITE_NAME"
done < "sites.txt"

echo "Deploy Management stack"
docker stack deploy --with-registry-auth -c management/"$SITE_NAME"/docker-compose-"$SITE_NAME".yml "$SITE_NAME"

echo "Deploy API Master stack"
SITE_NAME="api-master"
docker stack deploy --with-registry-auth -c sites/"$SITE_NAME"/docker-compose-apimaster.yml "$SITE_NAME"

echo "Done!"
exit 0
