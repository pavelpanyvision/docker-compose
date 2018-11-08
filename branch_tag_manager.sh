#/bin/bash

# this script clones a repository, including all its remote branches
# Author: igald

GIT=`which git`

if [ "x$1" = "x" -o "x$2" = "x" -o "x$3" = "x" -o "x$4" = "x" ];then
  echo "use: $0 <git_repository_to_clone> <directory> <new_branch> <tag>" 
  exit 1
fi

if [ "x$GIT" = "x" ];then
  echo "No git command found. install it"
fi

function clone {

  $GIT clone -q --single-branch -b development $1 $2
  res=$?

  cd $2
  
  $GIT pull --all
  
  existence_branch=$($GIT branch -r | grep -v \> | grep $3)  
  if [ -z "$existence_branch" ] ; then
     $GIT checkout -b $3 
  else 
     echo "branch $3 already exist"
  fi

}

function find_and_replace {


  echo "replace anyvision-training | anyvision-production  "
  for yaml in $(find . -type f -name "*.y*ml") ; do  
	echo $yaml ; 
	sed -i  's/anyvision-training/anyvision-production/' $yaml 
  done

  echo "replace - ENABLE_CHOWN=true in comment"
  for yaml in $(find . -type f -name "*.y*ml") ; do  
	echo $yaml ; 
	sed -i 's/- ENABLE_CHOWN=true$/- ENABLE_CHOWN=false/' $yaml ; 
  done

  echo "replace - remove NODE_DEBUG_OPTION "
  for yaml in $(find . -type f -name "*.y*ml") ; do  
	echo $yaml ; 
	sed -i '/NODE_DEBUG_OPTION/d' $yaml ; 
  done

  echo "comment all rabbitmq ports"
  for yaml in $(find . -type f -name "*.y*ml") ; do  
	echo $yaml ; 
  done

  echo "update the specific tag on specific image"
  for yaml in $(find . -type f -name "*.y*ml") ; do  
	echo $yaml $4 
	sed -i "s/:development$/:$2/" $yaml ;
  done

}

function push {
   
   $GIT push origin $3

}

echo "cloning repository into ... $2"
clone $1 $2 $3
find_and_replace $2 $4
#rm -rf $2
