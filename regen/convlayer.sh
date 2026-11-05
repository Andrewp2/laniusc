#!/bin/bash
# convlayer.sh K [conv|build]: conv = modconv layer K's files (layers.txt); build = one lake build pass of them.
cd /home/andrew-peterson/code/laniusc-wt/regen/formal
D=/home/andrew-peterson/code/laniusc/target/claude-work/regen
mods=$(awk -v k=$1 '$1==k {for(i=3;i<=NF;i++) print $i}' $D/layers.txt)
case $2 in
  conv) python3 $D/modconv.py $(for m in $mods; do echo ${m//.//}.lean; done); echo converted $(echo $mods | wc -w) ;;
  build) HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 288 ~/.elan/bin/lake build $mods > $D/layer$1.log 2>&1; rc=$?
     echo "rc=$rc built=$(grep -c Built $D/layer$1.log) $(grep -o '\[[0-9]*/[0-9]*\]' $D/layer$1.log | tail -1)"
     grep -E "error: .*lean:" $D/layer$1.log | cut -c1-250 | head -12 ;;
esac
