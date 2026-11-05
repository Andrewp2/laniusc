#!/bin/bash
# fixfailed.sh K: fixalls.py on the modules layerK.log reports failing.
D=/home/andrew-peterson/code/laniusc/target/claude-work/regen
cd /home/andrew-peterson/code/laniusc-wt/regen/formal
fs=$(grep "✖" $D/layer$1.log | grep -o "Building [A-Za-z0-9_.]*" | awk '{print $2}' | sed 's|\.|/|g; s|$|.lean|')
timeout 295 python3 -I $D/fixalls.py $fs 2>&1 | tail -12
