#!/bin/bash
set -e

display_usage() {
  echo -e "\nUsage:\n$0 [OPTIONAL: private registry hostname] [OPTIONAL: private registry port]\n"
  echo -e "Example:\n$0 localhost 5000\n"
}

docker_warning() {
  echo "This script must be run with Docker capable privileges!"
}

# Check params
if [ $# -gt 2 ]; then
  display_usage
  exit 1
fi

# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi

registry_host="$1"
registry_port="$2"

while IFS='' read -r img || [[ -n "$img" ]]; do
    IMAGE=$img
    echo "Loading image $IMAGE"
    docker load -i $IMAGE
    # Retag image if registry hostname/port given
    if [ ! -z "$registry_host" ]; then
      if [ ! -z "$registry_port" ]; then
        IMAGE="$registry_host:$registry_port/$IMAGE"
      else
        IMAGE="$registry_host/$IMAGE"
      fi
      echo "Retagging $img to $IMAGE"
    	docker tag $img $IMAGE
      docker rmi $img
    fi
    echo "Pushing image $IMAGE"
    docker push $IMAGE
done < "images.txt"

echo "Done!"
exit 0
