#!/bin/bash

## Allow root to write to the X server
echo 'xhost +SI:localuser:root' > /etc/profile.d/xhost.sh

## Create license directory
mkdir -m 777 -p /home/user/license
