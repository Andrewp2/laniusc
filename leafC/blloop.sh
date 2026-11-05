#!/bin/bash
# blloop.sh TARGETS: rerun bl.sh until the build completes or fails (each run under 5 min)
B=/home/andrew-peterson/code/laniusc/target/claude-work/leafC
for i in $(seq 1 12); do
  out=$($B/bl.sh "$@" 2>&1)
  if grep -q "^error" $B/b1.log; then echo "$out" | grep -v "^ \|Hint\|Note\|^$\|\[apply\]\|⚠" | tail -40; echo FAILED; exit 1; fi
  if grep -q "Build completed successfully" $B/b1.log; then echo DONE; exit 0; fi
  tail -1 $B/b1.log
done
echo GAVEUP
