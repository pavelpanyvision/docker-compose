#!/bin/bash
set -eu

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

TZ=`readlink /etc/localtime | awk -F / '{print $5"/"$6}'`
PULSE_DIR=`find /run/user/ -name pulse 2>/dev/null | head -n1`

FILES="$BASEDIR/docker-compose*.yml"
for f in $FILES
do
  echo "Processing $f ..."
  # take action on each file. $f store current file name
  sed -i -e 's@/run/user/1000/pulse@'$PULSE_DIR'@' "$f"
  sed -i.bak -e 's@\${TZ:-UTC}@'$TZ'@' "$f"
done

echo "Done!"
exit 0
