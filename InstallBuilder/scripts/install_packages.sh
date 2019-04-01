#!/bin/bash

# Arguments:
debs_packages_dir=$1
rpms_packages_dir=$2


##Install Packages
if [ -d "$debs_packages_dir" ] && [ -d "$rpms_packages_dir" ]; then
  cd "$rpms_packages_dir" && rpm -ivh *.rpm
  cd "$debs_packages_dir" && dpkg -i *.deb
else
  echo "Error: directory "$package_dir" does not exist."
  exit 1
fi
