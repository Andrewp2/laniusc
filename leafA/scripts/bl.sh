#!/bin/bash
# bl.sh TARGETS: build in leafA's worktree (under 5 min), print errors briefly
B=/home/andrew-peterson/code/laniusc/target/claude-work
cd /home/andrew-peterson/code/laniusc-wt/leafA/formal
HEAVY_PRIORITY=1 timeout 298 $B/bin/leanslot timeout 290 ~/.elan/bin/lake build "$@" > $B/leafA/b1.log 2>&1
grep "✖\|^error: Lanius\|^error: [a-zA-Z/]*\.lean" $B/leafA/b1.log | head -30
tail -1 $B/leafA/b1.log
awk '/^error: /{p=1; n=0} p{print; n++} /⊢/{p=0} n>14{p=0}' $B/leafA/b1.log | grep -v "^warning" | head -60
