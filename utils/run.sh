#!/bin/bash
#
# Run all additional scripts in order
#
#

for i in `ls | grep -v "run.sh" | sort -V`
do
  if [ -x ${i} ]
  then
    echo "[INFO] Executing additional provisioning script $i"
  else
    echo "[WARN] $i is not a script. Not executing it"
  fi
done
