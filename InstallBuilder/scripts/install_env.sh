#!/bin/bash

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

# Source the optparse.bash file ---------------------------------------------------
source "$BASEDIR"/optparse.bash
# Define options
optparse.define short=i long=installdir desc="Installation directory prefix" variable=installdir
optparse.define short=u long=user desc="Targer user" variable=user
optparse.define short=c long=component desc="Component to install" variable=component
# Source the output file ----------------------------------------------------------
source $( optparse.build )

set -euo pipefail


## Install Component
if [ -d "$installdir"/"$component" ]; then
  cd "$installdir"/"$component"
  if [ ! -f "/etc/debian_version" ]; then                         ## NOT A DEBIAN BASED DISTRIBUTION (REDHAT, CENTOS)
    rpm --quiet --nosignature --replacepkgs -i *.rpm
    if [ "$component" = "nvidia-driver" ]; then
      chmod +x /opt/NVIDIA-Linux-x86_64-390.87.run
      /opt/NVIDIA-Linux-x86_64-390.87.run --silent --no-questions ## THIS IS THE ONLY METHOD THAT WORKS FOR RHEL
    fi
  else
    dpkg -i *.deb
  fi
else
  echo "Error: directory "$installdir"/"$component" does not exist."
  exit 1
fi


## Add the target user to the docker group (requires re-login)
if [ "$component" = "docker-ce" ]; then
  usermod -aG docker "$user"
  systemctl enable docker
fi


## Update Docker's daemon.json to include nvidia as default runtime
if [ "$component" = "nvidia-docker2" ]; then
  cat > /etc/docker/daemon.json <<'EOF'
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF
  ## Restart Docker daemon
  if pgrep -x "dockerd" > /dev/null; then
    pkill -SIGHUP dockerd
  else
    systemctl start docker
  fi
fi
