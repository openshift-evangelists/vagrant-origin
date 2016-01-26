#!/bin/bash
#
# Run all additional scripts in order
#
#
echo "[INFO] Executing every script with numerical index in order"
for i in `ls [0-9]/* | sort -V`
do
  if [ -x ${i} ]
  then
    echo "[INFO] Executing additional provisioning script $i"
  else
    echo "[WARN] $i is not a script. Not executing it"
  fi
done
