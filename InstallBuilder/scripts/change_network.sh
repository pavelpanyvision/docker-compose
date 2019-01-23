#!/bin/bash

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

# Source the optparse.bash file ---------------------------------------------------
source "$BASEDIR"/optparse.bash
# Define options
optparse.define short=n long=network-name desc="change the network to this name" variable=network_name
optparse.define short=c long=compose-name desc="change the network in this compose file" variable=compose_name
# Source the output file ----------------------------------------------------------
source $( optparse.build )

NETWORK="name:"

## Change Network Name
if [ ! -z ${network_name} ] && [ ! -z ${compose_name} ]; then 
  if [ -f ${compose_name} ]; then
    if grep -q "${NETWORK}" ${compose_name}; then    
        ## change the netwrok name, remove dots and add "_prod" as suffix
        sed -i "s/name:.*/name: $(echo "${network_name//./}")_prod/g" ${compose_name} 
    else
        echo "Error: there is no network name pre-configured, please configure network first."
        exit 3
    fi
  else
    echo "Error: there is no such file ${compose_name}, please enter full path to the compose file."
    exit 2
  fi
else
  echo "Error: missed parameters, netwrok name: ${network_name} ; compose file name: ${compose_name}."
  exit 1
fi

echo "DONE"
exit 0