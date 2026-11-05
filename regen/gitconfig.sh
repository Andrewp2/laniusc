git config merge.lanius-generated.name 'generated Lean file: keep ours, formal/tools/regen.py rewrites it'
git config merge.lanius-generated.driver 'f=formal/tools/merge_driver.py; if [ -f "$f" ]; then python3 -I "$f" generated %O %A %B %L %P; else git merge-file -L ours -L base -L theirs %A %O %B; fi'
git config merge.lanius-lean.name 'Lean file: conflicting top-of-file imports take both sides'
git config merge.lanius-lean.driver 'f=formal/tools/merge_driver.py; if [ -f "$f" ]; then python3 -I "$f" lean %O %A %B %L %P; else git merge-file -L ours -L base -L theirs %A %O %B; fi'
