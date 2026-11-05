#!/bin/bash
# bl.sh TARGET: build, print errors briefly
B=/home/andrew-peterson/code/laniusc/target/claude-work
cd /home/andrew-peterson/code/laniusc-wt/leafC/formal
$B/bin/leanslot timeout 290 ~/.elan/bin/lake build "$@" > $B/leafC/b1.log 2>&1
grep "✖\|^error: Lanius\|^error: [a-zA-Z/]*\.lean" $B/leafC/b1.log | head -40
tail -1 $B/leafC/b1.log
awk '/^error: /{p=1; n=0} p{print; n++} /⊢/{p=0} n>14{p=0}' $B/leafC/b1.log | grep -v "^warning" | head -60
