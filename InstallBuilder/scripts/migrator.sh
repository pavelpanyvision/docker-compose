#!/bin/bash

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "${SCRIPT}")

# Source the optparse.bash file ---------------------------------------------------
source "${BASEDIR}"/optparse.bash
# Define options
optparse.define short=p long=project desc="Compose project prefix" variable=compose_project_name
optparse.define short=v long=version desc="Product version" variable=product_version
# Source the output file ----------------------------------------------------------
source $(optparse.build)

set -euo pipefail

docker_warning() {
  echo "This script must be run with Docker capable privileges!"
}

stop_dockers(){
  RUNNING_CONTAINERS=$(docker ps -q --filter "name=${compose_project_name}")
  if [[ -n "${RUNNING_CONTAINERS}" ]]; then
    ## Stop running dockers
    docker kill $(docker ps -q --filter "name=${compose_project_name}")
    ## Remove docker network
    #docker network rm $(docker network ls -q --filter "name=${compose_project_name}")
  fi
}

volume_migration(){
  if [[ ! -d "/ssd/mongo_db_data" ]] || [[ ! -d "/ssd/backend_data" ]]; then
    ## Create Directories
    mkdir -p /ssd/{mongo_db_data,backend_data}
  fi
  NUM_OF_FILES=$(ls /ssd/mongo_db_data | wc -l)
  ## Check if we are migrating from a previous version to 1.20.0 where the MongoDB and Backend Data were saved in Docker Volumes
  if [[ "$NUM_OF_FILES" -eq "0" ]]; then
    ## Migrate pre-1.20.0 backend_data volume to /ssd/backend_data
    VOLUME_CONTAINER_ID=$(docker ps -q --all --filter "volume=${compose_project_name}_backend_data")
    if [[ -n "${VOLUME_CONTAINER_ID}" ]] && [[ -d "/var/lib/docker/volumes/${compose_project_name}_backend_data/_data" ]]; then
      rsync -a /var/lib/docker/volumes/${compose_project_name}_backend_data/_data/ /ssd/backend_data/
    fi
    ## Migrate pre-1.20.0 mongo_db_data volume to /ssd/mongo_db_data
    VOLUME_CONTAINER_ID=$(docker ps -q --all --filter "volume=${compose_project_name}_mongo_db_data")
    if [[ -n "${VOLUME_CONTAINER_ID}" ]] && [[ -d "/var/lib/docker/volumes/${compose_project_name}_mongo_db_data/_data" ]]; then
      rsync -a /var/lib/docker/volumes/${compose_project_name}_mongo_db_data/_data/ /ssd/mongo_db_data/
    fi
  fi
}

db_migration(){
  ## Bring the Migrator stack up
  docker-compose -f /tmp/migrator/${product_version}/docker-compose.yml -p migrator up -d
  ## Migration status
  migration_manager_id=$(docker ps --all -q --filter "name=migrator_migration_manager")
  sleep 5
  migration_manager_status=$(docker inspect ${migration_manager_id} --format='{{.State.Status}}')
  while [[ "${migration_manager_status}" = "running" ]] ; do
    sleep 5
    migration_manager_status=$(docker inspect ${migration_manager_id} --format='{{.State.Status}}')
  done
  migration_manager_exit_code=$(docker inspect ${migration_manager_id} --format='{{.State.ExitCode}}')
  ## Stop the Migrator stack
  #docker-compose -f /tmp/migrator/${product_version}/docker-compose.yml -p migrator down
  docker kill $(docker ps -q --filter "name=migrator")
  if [[ "${migration_manager_exit_code}" -eq "0" ]]; then
    echo "Migration completed successfuly!"
  else
    echo "Migration failed!"
    exit 1
  fi
}

## Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi

## Execute Migration
stop_dockers
volume_migration
db_migration
