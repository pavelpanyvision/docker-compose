#!/bin/bash

display_usage() {
        echo "This script must be run with the script name."
        echo -e "\nUsage:\n ./checkmongo.sh script] \n"
        }
# If less than one arguments supplied, display usage
        if [  $# -le 0 ]
        then
                display_usage
                exit 1
        fi

#Params
#SCRIPT_DIR="Dash-API/scripts"
SCRIPT=$1
#SCRIPT_NAME=$(echo $SCRIPT_DIR| awk -F/ '{print $NF}')
#MONGO_IMAGE="gcr.io/anyvision-training/mongo:3.6-jessie"
#HOSTNAME=127.0.0.1
HOSTNAME=mongo
PORT=27017
echo "Starting the Mongo Container Image and change its name to Mongo"
#docker run -d -v /var/lib/docker/volumes/anyvision_backend_data --name=mongo $MONGO_IMAGE

#echo "Copy $SCRIPT_DIR/$SCRIPT into /tmp/ inside the container"
echo "Copy $SCRIPT_DIR into /tmp/ inside the container as $SCRIPT_DIR"
#if [[ ! -f $SCRIPT_DIR/$SCRIPT ]]
if [[ ! -f $SCRIPT_DIR ]]
then
        echo "$SCRIPT_DIR not found!"
else
        #docker cp $SCRIPT_DIR docker-compose_mongodb_1:/tmp/$SCRIPT_NAME
        echo "Executing Mongo anyVision2 $SCRIPT_NAME"
        #docker exec docker-compose_mongodb_1 bash -c "mongo localhost:27017/anyVision2 /tmp/$SCRIPT_NAME"
        mongo $HOSTNAME:$PORT/anyVision2 $SCRIPT_DIR
        #docker exec mongo bash -c "mongo localhost:27017/anyVision2 /tmp/$SCRIPT_NAME"
fi
# Start job every 1 minute
* * * * * /root/migration/mongo_migration_1.19.2.sh
#echo "Stopping and Removing Mongo container for reuse"
#docker rm -f mongo
