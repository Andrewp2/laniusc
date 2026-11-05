#!/bin/bash
# Re-extract frontend.lani from a clean Frontend Lean tree (the extract exe builds against it).
cd /home/andrew-peterson/code/laniusc-wt/leafC
git checkout -- formal/Lanius/Mini/Frontend.lean formal/Lanius/Mini/Frontend/
git status --short formal/Lanius/Mini/Frontend/ | grep "^??" | awk '{print $2}' | xargs -r rm -f
HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I formal/tools/regen.py --only extract --limit 280 > /home/andrew-peterson/code/laniusc/target/claude-work/leafC/s5/extract.log 2>&1
tail -2 /home/andrew-peterson/code/laniusc/target/claude-work/leafC/s5/extract.log | cut -c1-200
