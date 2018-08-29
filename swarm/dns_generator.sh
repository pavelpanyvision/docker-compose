#!/bin/bash

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

mkdir -p "$BASEDIR"/stacks/management/coredns

j2 "$BASEDIR"/templates/coredns-zonefile.tmpl sites.yml > "$BASEDIR"/stacks/management/coredns/db.zonefile
j2 "$BASEDIR"/templates/coredns-Corefile.tmpl sites.yml > "$BASEDIR"/stacks/management/coredns/Corefile

echo 'Done!'
exit 0
