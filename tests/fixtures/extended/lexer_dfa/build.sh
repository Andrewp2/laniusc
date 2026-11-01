#!/bin/bash
# Copy extended/ext plus the frozen VM lexer into one source root and compile the comparator.
cd "$(dirname "$0")/../../../.." || exit 1
W=${W:-$PWD/target/claude-work/s3}
rm -rf $W/combined; mkdir -p $W/combined/ext
cp extended/ext/*.lani tests/fixtures/extended/lexer_dfa/root/ext/lexer_vm.lani $W/combined/ext/
timeout 200 target/claude-work/bin/lcc --stdlib-root stdlib --source-root $W/combined -o $W/lexer_compare tests/fixtures/extended/lexer_dfa/compare.lani 2>&1 | python3 -c "
import sys,json
for l in sys.stdin:
  try: d=json.loads(l); p=d.get('primary_label') or {}; print(d.get('message'), (p.get('path') or '')[-40:], p.get('line'), (p.get('source_line') or '')[:160], d.get('notes'))
  except Exception: print(l[:300])
" | head -${1:-20}
