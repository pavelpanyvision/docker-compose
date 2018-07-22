#!/bin/bash
#set -e

display_usage() {
  echo -e "\nUsage:\n$0 <source path>\n"
  echo -e "Example:\n$0 /tmp/docker_images\n"
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

source="$1"


for IMAGE in ${source}/*.tar.gz ; do
    echo "load the image $IMAGE"
    docker load -i $IMAGE
done

echo "Done!"
#exit 0
