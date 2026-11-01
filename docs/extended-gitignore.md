# .gitignore rules

`ext::gitignore` reads the lines of `.gitignore` files and decides whether a
path is ignored, with git's rules and precedence. It does not walk
directories itself. The caller adds a directory's rules when it enters the
directory and drops them when it leaves, as text_grep's
[recursive mode](extended-text-grep.md#files-and-recursive-search) does.

```lanius
let rules: ext::gitignore::Rules = ext::gitignore::rules();
core::result::unwrap(rules.add(root_contents, 0));          // ./.gitignore
let before: i32 = rules.len();
core::result::unwrap(rules.add(src_contents, 4));           // src/.gitignore, paths "src/..."
let verdict: i32 = rules.check(path, false);                 // path such as "src/main.c"
rules.truncate(before);                                      // leaving src/
rules.destroy();
```

`add(contents, base)` appends the rules of one file. `base` is the index in
the paths later given to `check` where paths relative to that file's
directory begin: 0 for the root, `len("src/")` for `src/.gitignore`. It
returns the number of rules added, `Err(Bounds)` for a bad view or a
negative base, or `Err(AllocationFailed)`. `check(path, directory)` returns
`IGNORED` (1), `INCLUDED` (-1, a `!` rule decided) or `UNDECIDED` (0). Paths
use `/` and have no leading `./`. `truncate(count)` drops the rules added
after the first `count`, and `destroy` releases both buffers.

## Pattern lines

| Line | Meaning |
| --- | --- |
| empty, or starting with `#` | nothing; `\#` starts a pattern with `#` |
| trailing spaces | removed, unless the last one is escaped as `\ ` |
| `!pattern` | a match re-includes the path |
| `pattern/` | matches directories only |
| `/pattern`, `a/b` | anchored: a `/` at the start or inside matches from the rule's directory |
| `name` | no `/`: matches the last component at any depth below the rule's directory |
| `**` component | leading or inner: zero or more components; trailing: one or more |

Components are matched with [`ext::fnmatch`](extended-fnmatch.md) and flags
0, so `*`, `?`, brackets, classes and `\` escapes follow glibc. Each
component of an anchored pattern matches one component of the path, so `*`
never crosses a `/`. A `**` inside a component, as in `a**b`, is an ordinary
pair of stars.

The last rule that matches decides, so a deeper `.gitignore` overrides a
shallower one and a later line an earlier one. A directory that is ignored
is not entered, so a `!` rule cannot bring back a file below it, which is
also git's rule. Recursion over `**` components is bounded at 64 levels; a
pattern with more fails to match.

Not handled: `.git/info/exclude`, `core.excludesFile`, `.gitignore` files
above the starting directory, and tracked files (git never ignores a file it
tracks; this module knows nothing of the index).

## Verification

`tests/fixtures/extended/text_grep_recursive/compare.py generated` builds
random trees with `.gitignore` files at several depths, drawn from 22 lines
that cover every form above (negation, directory-only, anchors, `**` in all
three positions, escaped `#` and space, brackets, `?`). In 70 % of the cases
the root `.gitignore` gets two to six more lines. Each case runs
`git init` in an isolated environment (no system or global config) and
lists the files git does not ignore with `git ls-files -o --exclude-standard`.
GNU grep over exactly those files must give the same sorted lines and status
as `text_grep -r --gitignore`. Seeds 20261101, 1 and 2 with 400 trees each
agreed in all 231, 253 and 246 gitignore cases; git ignored at least one file
in 148, 165 and 157 of them. Log:
`target/claude-work/s3/text-grep-recursive-receipt.log`.
