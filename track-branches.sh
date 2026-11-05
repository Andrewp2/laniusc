#!/bin/bash
# Make a local branch for each active work branch listed in BRANCHES.md.
git fetch origin
for b in lang regen-modules leafB leafB-lv leafC-s5b leafC-s6b leafC-s6c leafA-p3b leafC-same f6v-split cert lv claude-notes; do
  git show-ref -q --verify refs/heads/$b || git branch --track $b origin/$b
done
git branch -vv | grep -E 'lang|regen-modules|leaf|f6v-split|cert|lv|claude-notes'
