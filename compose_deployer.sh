#!/bin/bash


# Source the optparse.bash file ---------------------------------------------------
source optparse.bash
# Define options
optparse.define short=g long=gpu desc="Deploy compose GPU" variable=deploy_gpu value=true default=false
optparse.define short=c long=cpu desc="Deploy compose CPU" variable=deploy_cpu value=true default=false
optparse.define short=f long=facekey desc="Deploy compose FaceKey" variable=deploy_facekey value=true default=false
optparse.define short=l long=liveness desc="Deploy compose Liveness" variable=deploy_liveness value=true default=false
optparse.define short=t long=ift3 desc="Deploy compose IFT3" variable=deploy_ift3 value=true default=false
#optparse.define short=b long=ab desc="Deploy A/B stacks from sites.txt" variable=deploy_ab value=true default=false
optparse.define short=d long=dbmigration desc="Deploy db-migration stack" variable=deploy_dbmigration value=true default=false
optparse.define short=r long=remove desc="Remove compose before deploy" variable=remove value=true default=false
# Source the output file ----------------------------------------------------------
source $( optparse.build )

set -eu

docker_warning() {
  echo "This script must be run with Docker capable privileges!"
}

migration(){
  echo "Start db migration "
  remove 
  ## Bring the Migrator stack up
  docker-compose -f ${BASEDIR}/docker-compose-migration-db.yml -p migrator up -d
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
    #docker-compose -f "$BASEDIR"/docker-compose-migration-db.yml -p migrator down
    exit 1
  fi

}

remove() {

   if [ -f $HOME/.compose_deployer.desc ] ; then
      current_compose=$(cat $HOME/.compose_deployer.desc)
      echo echo -e "\e[31Current Compose running $current_compose"
      docker-compose $current_compose ps
      read -r -p "continue upgrade? [Y/n] : " answer
      case $answer in 
         [yY]) docker-compose -p anyvision $current_compose down ;
              ;;
         [nN]) echo "Keeping current state"
                exit 0
                ;;
           *) echo "Wrong option"
              exit 0
              ;;
      esac
   else
       echo "No existing compose"
   fi
   rm -f $HOME/.compose_deployer.desc
}

compose() {
   start_desc=$(echo $1 | sed 's/-f/ /g')
   if [ -f $HOME/.compose_deployer.desc ] ; then
      current_compose=$(cat $HOME/.compose_deployer.desc)
      echo echo -e "\e[31Current Compose running $current_compose"
      docker-compose $current_compose ps
      read -r -p "continue upgrade? [Y/n] : " answer
      case $answer in 
         [yY]) docker-compose -p anyvision $current_compose down ;
              ;;
         [nN]) echo "Keeping current state"
                exit 0
                ;;
           *) echo "Wrong option"
              exit 0
              ;;
      esac
   fi
   echo -e "\e[93mStart Composes: $start_desc\e[0m"
   docker-compose -p anyvision $1 up -d
   echo $1 > $HOME/.compose_deployer.desc
}

[ $# -lt 1 ] && $0 -h

# Check Docker command executable exit code
docker images > /dev/null 2>&1; rc=$?;
if [[ $rc != 0 ]]; then
  docker_warning
  exit 1
fi

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

## remove compose
## deploy cloud gpu
if [ "$remove" == "true" ] ; then 
   remove
fi
compose_string=""
if [ "$deploy_gpu" = "true" ] ; then
   compose_string+=" -f $BASEDIR/docker-compose-local-gpu.yml "
   if [ "$deploy_liveness" = "true" ] ; then
      compose_string+=" -f $BASEDIR/docker-compose-liveness-gpu.yml "
   fi
elif [ "$deploy_cpu" = "true" ] ; then
   compose_string+=" -f $BASEDIR/docker-compose-local-cpu.yml "
   if [ "$deploy_liveness" = "true" ] ; then
      compose_string+=" -f $BASEDIR/docker-compose-liveness-cpu.yml "
   fi
fi

if [ "$deploy_ift3" = "true" ] ; then
   compose_string+=" -f $BASEDIR/docker-compose-ift3.yml "
fi

if [ "$deploy_facekey" = "true" ] ; then
   compose_string+=" -f $BASEDIR/docker-compose-facekey.yml "
fi

if [ "$deploy_dbmigration" = "true" ] ; then
   migration   
   exit
fi

if [ ! -z "$compose_string" ] ; then 
   compose "$compose_string"
fi

echo "Done!"
exit 0
