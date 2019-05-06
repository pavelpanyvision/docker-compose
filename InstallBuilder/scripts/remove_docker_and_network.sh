#!/bin/bash

## Remove all docker container that are running
if [[ $(docker ps -aq) ]]; then
  docker rm -f `docker ps -aq`
else
  echo "There are no containers running"
fi
## Remove docker network contines default or prod
if [[ $(docker network ls | grep 'default\|prod') ]]; then
 docker network ls | grep 'default\|prod' | awk '{print $1}' | xargs docker network rm
else
  echo "There are no network called prod or default"
fi
