#!/bin/bash

## Remove all docker container that are running
docker rm -f `docker ps -aq`
## Remove docker network contines default or prod
docker network ls | grep 'default\|prod' | awk '{print $1}' | xargs docker network rm
