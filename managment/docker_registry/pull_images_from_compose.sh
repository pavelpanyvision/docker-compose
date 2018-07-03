#!/bin/bash
set -e

display_usage() {
  echo -e "\nUsage:\n$0 <docker compose file> <destination path>\n"
  echo -e "Example:\n$0 docker-compose.yml /tmp/docker_images\n"
}

docker_warning() {
  echo "This script must be run with Docker capable privileges!"
}

# Check params
if [ $# -lt 2 ]; then
  display_usage
  exit 1
fi

# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi

compose_file="$1"
destination="$2"
compose_file_dir=$(dirname "$compose_file")

# Create destination dir
mkdir -p "$destination"

# Clear images.txt
rm -f "$destination/images.txt"

# Pull the Docker Registry Image
docker pull registry:latest
# Save the Docker Registry Image
docker save docker.io/registry:latest | gzip -c > "$destination/docker-io.registry.tar.gz"
#echo "docker-io.registry.tar.gz" > images.txt

for IMAGE in $(docker-compose -f $compose_file config | awk '{if ($1 == "image:") print $2;}'); do
  echo "Pulling image $IMAGE"
  docker pull $IMAGE
  sanitized_img=$(echo $IMAGE | sed -e 's/\//_/g' | sed -e 's/\:/__/g')
  echo "Saving $IMAGE to $destination/$sanitized_img.tar.gz"
  docker save $IMAGE | gzip -c > "$destination/$sanitized_img.tar.gz"
  echo "$sanitized_img.tar.gz" >> "$destination/images.txt"
done

# Copy the offline scripts,compose file and .env files to the destination dir
cp ./*.sh $compose_file $compose_file_dir/* $destination

echo -e "\n\nDone!\n"
exit 0
