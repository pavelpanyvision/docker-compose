#!/bin/bash
set -eu

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

export TZ=`readlink /etc/localtime | awk -F / '{print $5"/"$6}'`

docker-compose "$@"
