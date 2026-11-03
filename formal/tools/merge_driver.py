#!/usr/bin/env python3
"""Git merge drivers for formal/ (formal/.gitattributes, formal/tools/README.md).

    merge_driver.py generated BASE OURS THEIRS MARKER PATH
    merge_driver.py lean BASE OURS THEIRS MARKER PATH

`generated` (merge=lanius-generated: the files regen.py writes) keeps ours
and exits 0, so a generated file never conflicts: its text is whatever
regen.py makes of the merged sources, so neither side's is the answer. The
path is listed in GIT_DIR/lanius-regen-stale for regen.py, which reports the
list and removes it once every stage has run.

`lean` (merge=lanius-lean: every other Lean file) is git's own 3-way merge
(`git merge-file`), but a conflict between import lines at the top of a
file (every line of both sides an `import`, and nothing above it but
`module`, blank, comment and import lines) takes the lines of both sides,
ours first, each once. Those lines name extracted parts (`import all
Lanius.Mini.Compiler.P.x`), which both sides add as their proofs need them;
regen.py then drops each import of an extracted part that no longer exists
in the files listed (as `imports PATH`). Any other conflict is left as git
leaves it, with its markers, and the driver exits 1.

Git runs a driver from the top of the worktree with BASE, OURS and THEIRS as
temporary files; the result goes in OURS. The drivers are defined in the
repository's config (shared by every worktree), by the commands in
formal/tools/README.md.
"""

import os
import re
import subprocess
import sys

IMPORT = re.compile(r'(public |private )?import (all )?\S+\s*$')


def stale(kind, path):
    gd = subprocess.run(['git', 'rev-parse', '--git-dir'], capture_output=True, text=True).stdout.strip() or '.git'
    with open(os.path.join(gd, 'lanius-regen-stale'), 'a') as f:
        f.write(f'{kind} {path}\n')


def header_line(line):
    s = line.strip()
    return s == '' or s == 'module' or s.startswith('--') or bool(IMPORT.match(s))


def settle(text, marker):
    """Resolve the import conflicts of a merged text: (text, conflicts left, settled)."""
    lines = text.split('\n')
    out, left, settled = [], 0, 0
    top = True  # nothing but header lines so far
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.startswith('<' * marker) or line[marker:marker + 1] not in ('', ' '):
            top = top and header_line(line)
            out.append(line)
            i += 1
            continue
        # a conflict: <<<<<<< ours | ||||||| base | ======= theirs >>>>>>>
        ours, base, theirs, part, j = [], [], [], 'ours', i + 1
        while j < len(lines) and not (lines[j].startswith('>' * marker) and lines[j][marker:marker + 1] in ('', ' ')):
            ln = lines[j]
            if ln.startswith('|' * marker) and ln[marker:marker + 1] in ('', ' '):
                part = 'base'
            elif ln == '=' * marker:
                part = 'theirs'
            else:
                {'ours': ours, 'base': base, 'theirs': theirs}[part].append(ln)
            j += 1
        if j == len(lines):  # unterminated: leave it
            out += lines[i:]
            left += 1
            break
        if top and all(IMPORT.match(x.strip()) or not x.strip() for x in ours + theirs):
            seen = set()
            for x in ours + theirs:
                if x.strip() and x in seen:
                    continue
                seen.add(x)
                out.append(x)
            settled += 1
        else:
            out += lines[i:j + 1]
            left += 1
            top = top and all(header_line(x) for x in ours)
        i = j + 1
    return '\n'.join(out), left, settled


def main(argv):
    kind, base, ours, theirs, marker, path = argv
    marker = int(marker)
    if kind == 'generated':
        stale('generated', path)
        return 0
    if kind != 'lean':
        raise SystemExit(__doc__)
    style = subprocess.run(['git', 'config', 'merge.conflictStyle'], capture_output=True, text=True).stdout.strip()
    flags = {'diff3': ['--diff3'], 'zdiff3': ['--zdiff3']}.get(style, [])
    r = subprocess.run(['git', 'merge-file', f'--marker-size={marker}'] + flags
                       + ['-L', 'ours', '-L', 'base', '-L', 'theirs', ours, base, theirs])
    if r.returncode < 0 or r.returncode > 127:
        return 2
    if r.returncode == 0:
        return 0
    with open(ours, encoding='utf-8', newline='') as f:
        text = f.read()
    new, left, settled = settle(text, marker)
    if settled:
        with open(ours, 'w', encoding='utf-8', newline='') as f:
            f.write(new)
        stale('imports', path)
    return 1 if left else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
