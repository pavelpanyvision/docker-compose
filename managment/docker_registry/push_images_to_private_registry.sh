#!/bin/bash
set -e

display_usage() {
  echo -e "\nUsage:\n$0 <source path> <private registry hostname or fqdn or ip> <private registry port>\n"
  echo -e "Example:\n$0 /tmp/docker_images 192.168.59.128 5000\n"
}

docker_warning() {
  echo "This script must be run with Docker capable privileges!"
}

# Check params
if [ $# -lt 3 ]; then
  display_usage
  exit 1
fi

# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi

source="${1}"
registry_host="$2"
registry_port="$3"


for IMAGE in ${source}/*.tar.gz ; do
    if [[ $IMAGE != *"registry"* ]] ; then
        echo "load the image $IMAGE"
        docker load -i $IMAGE

        IMAGE_SOURCE_NAME=$(echo $IMAGE | awk -F "/" '{print $NF}'  | sed -e 's/__/\:/g' |  sed -e 's/_/\//g' )
        IMAGE_SOURCE_NAME_NO_TARGZ=${IMAGE_SOURCE_NAME%".tar.gz"}
        IMAGE_WITHOUT_REGISTRY=$(echo $IMAGE_SOURCE_NAME_NO_TARGZ | awk -F "/" '{print $NF}')
        IMAGE_LOCAL_REGISTRY="$registry_host:$registry_port/$IMAGE_WITHOUT_REGISTRY"


        echo "Retagging Docker $IMAGE_SOURCE_NAME_NO_TARGZ to $IMAGE_LOCAL_REGISTRY"
        docker tag $IMAGE_SOURCE_NAME_NO_TARGZ $IMAGE_LOCAL_REGISTRY
        docker rmi $IMAGE_SOURCE_NAME_NO_TARGZ

        echo "Pushing image $IMAGE_LOCAL_REGISTRY"
        docker push $IMAGE_LOCAL_REGISTRY
    fi
done


echo "Done!"
exit 0
