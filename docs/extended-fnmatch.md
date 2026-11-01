# POSIX fnmatch

`ext::fnmatch` matches a byte name against a shell wildcard pattern with the
answers of glibc's `fnmatch(3)` in the C locale. It is Lanius, allocates
nothing and needs no compilation step:

```lanius
let found: core::result::Result<bool, ext::fnmatch::Error> =
    ext::fnmatch::matches(pattern, name, ext::fnmatch::PATHNAME | ext::fnmatch::PERIOD);
```

`pattern` and `name` are `core::slice::View<u8>`. A NUL byte ends either one,
as it does for the C function. The result is `Err(Bounds)` for a view with a
negative start or length and `Err(Flags(bits))` for unknown flag bits.
Otherwise it is `Ok(true)` exactly when glibc returns 0.

| Flag | Value | Meaning |
| --- | ---: | --- |
| `PATHNAME` | 1 | `*`, `?` and bracket expressions never match `/`; a `/` in the name is matched only by `/` or `\/` in the pattern. |
| `NOESCAPE` | 2 | `\` is an ordinary byte, inside brackets too. |
| `PERIOD` | 4 | A leading `.` must be matched by a literal `.` (or `\.`): at the start of the name and, with `PATHNAME`, after each `/`. |
| `LEADING_DIR` | 8 | GNU: the pattern may stop at a `/` in the name (`a*` matches `ab/c`). |
| `CASEFOLD` | 16 | GNU: ASCII letters match either case. |

`FNM_EXTMATCH` is not supported.

## Matching rules

`?` matches one byte and `*` any run of bytes. A pattern byte that is not
special matches itself. Without `NOESCAPE`, `\x` matches `x`, and a trailing
`\` matches nothing. Bytes are bytes: `?` matches one byte of a multibyte
UTF-8 scalar, as in glibc's C locale.

A bracket expression `[...]` matches one byte. `!` or `^` right after the `[`
negates it, and a `]` in the first member position is a member. Members can be
bytes, ranges `a-z` (by byte value; a reversed range is empty), escaped bytes,
the classes `[:alnum:]`, `[:alpha:]`, `[:blank:]`, `[:cntrl:]`, `[:digit:]`,
`[:graph:]`, `[:lower:]`, `[:print:]`, `[:punct:]`, `[:space:]`, `[:upper:]`
and `[:xdigit:]` with their ASCII meaning, equivalence classes `[=x=]`, and
collating symbols `[.x.]`, which can also bound a range. With `CASEFOLD`, bytes
and range ends are lowered before they are compared, but classes, `[=x=]` and
a lone `[.x.]` compare the name byte as it is.

Malformed brackets behave as in glibc, which is not always "treat `[` as a
literal":

- An expression that never closes makes the `[` a literal byte, and matching
  goes on after it. This holds even when a member had already matched.
- A name between `[:` and `:]` that is not a class makes the whole pattern
  fail at that position. A would-be class name with a byte outside `a`–`y`
  (glibc compares against `'z'` exclusively) is read as the plain members `[`,
  `:` and so on.
- `[.` without a closing `.]`, a collating symbol of more than one byte, a
  trailing `\` and a range with no end fail.
- After a member matched, glibc skips the rest of the expression and fails
  on a malformed `[=` there. It also reads `[.a.]-]` as the symbol followed by
  a literal `-`, so `[[.a.]-]` does not match `a`.

## Algorithm

The matcher walks the pattern and the name once and remembers only the
innermost `*`. On a mismatch, that star absorbs one more byte and matching
resumes after it. An earlier star never needs to be revisited, because every
other element matches exactly one byte. With `PATHNAME` a star stops at the
next `/`, and `*/` jumps straight to it, as glibc does. The work is at most
the pattern length times the name length. glibc instead recurses at each
star, and its run time grows with the number of stars.

## Verification

`tests/fixtures/extended/fnmatch_oracle/oracle.py` builds cases from bracket,
class, collating, escape, slash and period tokens, with names derived from the
tokens so that a useful share match. It runs them through
`tests/fixtures/extended/fnmatch_oracle/cases.lani` in one batch, and through
glibc 2.39 `fnmatch` via `ctypes` after `setlocale(LC_ALL, "C")`, under random
flag sets. The pinned surface runs 72 malformed and boundary patterns under all
32 flag combinations.

```sh
W=target/claude-work/s3
target/claude-work/bin/lcc --stdlib-root stdlib --source-root extended \
  -o "$W/fnmatch_cases" tests/fixtures/extended/fnmatch_oracle/cases.lani
python3 -I tests/fixtures/extended/fnmatch_oracle/oracle.py "$W/fnmatch_cases" [--seed N] [--count N]
```

Seeds 20261101, 1 and 2 with the default 200,000 generated cases agreed on
every case. Each run had 2,304 pinned cases and about 111,000 bracket cases
(about 7,900 matches). It also had 60,000 path cases (19,400 matches), 30,600
other name cases (15,600 matches, including NUL-cut ones) and 2,000
bad-flag cases. The three linear-time cases (`*a` repeated 40 times against
4,000 bytes, and others) take under 0.01 s. Log:
`target/claude-work/s3/fnmatch-oracle-receipt.log`. Deliberate mutations were
caught. Moving the class-name byte bound gave 282 disagreements in 50,000
generated cases. With `--count 2000` plus the pinned surface, failing an
unterminated expression instead of reading a literal `[` gave 215, and
applying the plain-member range rule after a collating symbol gave 32.
