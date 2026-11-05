#!/bin/bash
# iter.sh TARGETS: build loop; auto-add missing tyRef/xDeref.. arms when those are the only errors; repeat
B=/home/andrew-peterson/code/laniusc/target/claude-work/leafC
cd /home/andrew-peterson/code/laniusc-wt/leafC/formal
for r in 1 2 3 4 5 6; do
  HEAVY_PRIORITY=1 $B/blloop.sh "$@" > $B/s5/loop.log 2>&1
  if grep -q DONE $B/s5/loop.log; then echo DONE; exit 0; fi
  n=$(grep -c "Alternative \`tyRef\` has not been provided" $B/s5/loop.log)
  if [ "$n" = 0 ]; then echo STOP; grep -v "^/home" $B/s5/loop.log | grep -v "✔" | head -60; exit 1; fi
  python3 $B/s5/fixarms.py $B/s5/loop.log tyRef " _" | tee $B/s5/fix.log; grep -q " [1-9][0-9]* inserted" $B/s5/fix.log || { echo STOP; grep "^error" $B/s5/loop.log | sort -u | head -40; exit 1; }
done
