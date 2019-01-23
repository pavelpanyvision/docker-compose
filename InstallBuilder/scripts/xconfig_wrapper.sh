#!/bin/bash

BusID=$(lspci | grep NVIDIA | head -1 | cut -d ' ' -f 1 | sed -e 's/^0//g' | sed -e 's/00/0/g' | sed -e 's/\./:/g')
nvidia-xconfig --virtual=1920x1080 --mode-list=1920x1080 --metamodes="1920x1080 +0+0" --allow-empty-initial-configuration --busid=`echo $BusID` -o /etc/X11/xorg.conf
