# Regex differential oracle

`tests/fixtures/extended/regex_oracle/oracle.py` compares four real
[`ext::regex`](extended-regex.md) programs with CPython `re`. It generates
patterns and inputs from a seeded grammar instead of using hand-picked
cases. The four programs are:

| Surface | Lanius program | Python side |
| --- | --- | --- |
| `find_iter_captures` | `tests/fixtures/extended_library/regex_input.lani`: `compile`, `find_iter` and every capture span of every match, plus `group_name` for every group | `search` loop and `Match.span(g)` per group, converted to byte offsets; `Pattern.groupindex` for names |
| `replace_template` | `sample_programs/library/regex_replace.lani template` over stdin | the same match loop, with `Match.group(n) or ""` per template reference |
| `grep_filter` | `sample_programs/library/text_grep.lani` with `-v`, `-n`, `-c` and their combinations | per-record `search`, exit status 0 or 1 |
| `lookbehind_find` | `regex_input.lani` again, on patterns that contain `(?<=...)` or `(?<!...)`, nested or inside generated groups | the same `search` loop; a pattern that Python rejects with "look-behind requires fixed-width pattern" must be a Lanius `Syntax` error |
| `dfa_match_find` | `tests/fixtures/extended/regex_oracle/dfa.lani`: `Dfa::is_match`, `Dfa::find_span` and the reusable-scratch forms, next to the VM's `is_match` and `find` on the same case | `search` and `Match.span()`, converted to byte offsets |

Another surface, `linear_time`, runs six inputs on which a backtracking
engine is exponential or quadratic, such as `(?:a?){30}a{30}` on 30 `a`s and
`(a+)+b`, `(a|aa)*c`, `(x+x+)+y` and `(?:(?<=(?:a|a){8})a)+b` on 20,000
scalars. CPython is not run on
these. Their expected results are derived by hand, and the elapsed time is
reported.

Python is only the oracle. Both search and replacement are Lanius code that
the GPU compiler emitted as native x86_64 Linux executables.

## Running it

```sh
W=target/claude-work/s3
for entry in tests/fixtures/extended_library/regex_input.lani \
             tests/fixtures/extended/regex_oracle/dfa.lani \
             sample_programs/library/regex_replace.lani \
             sample_programs/library/text_grep.lani; do
  target/claude-work/bin/lcc --stdlib-root stdlib --source-root extended \
    -o "$W/$(basename "$entry" .lani)" "$entry"
done
python3 -I tests/fixtures/extended/regex_oracle/oracle.py \
  "$W/regex_input" "$W/regex_replace" "$W/text_grep" \
  [--dfa "$W/regex_dfa"] [--seed N] [--patterns N]
```

The default is 3,000 generated patterns. Each pattern gets four inputs for
`find_iter_captures`. A third as many patterns are used for each of the
replacement and grep surfaces. The script prints `surface agree/total` for each
surface, followed by `disagreements N`. It exits 1 if any case disagrees.
`--dfa EXE` adds the `dfa_match_find` surface: one case per pattern. A case
agrees only when the DFA answer, the VM answer and Python all match. Anchors
and word boundaries are DFA state, so every pattern without lookbehind must
get a `Dfa`. A tenth of the patterns contain lookbehind; `dfa()` refuses those
unless the lookbehind compiled away (inside `{0}`), and the VM answers. Inputs
reach 400 scalars, or 20 when the pattern has a quantified group, which keeps
CPython's backtracking short. About one
case in ten gets a work budget of 1, 20 or 200, so the exactness bound fails;
those cases are compared with the VM only, including its `WorkLimit` errors,
and not with Python.
`tests/extended_regex_oracle_execution.rs` compiles the four programs through
the library compiler API, runs the default seed and requires exact agreement.

## Shared subset

The generator emits only syntax whose meaning is the same in both engines:

- literals, including `é`, `🙂`, escaped punctuation, `\xHH`, `\x{H...}`,
  `\t` and `\n`;
- `.`, the shorthands `\d \w \s \D \W \S`, and bracket classes built from
  literals, ranges (including `é-🙂`), shorthands and `^` negation;
- the anchors `^ $ \A \z \b \B`. They are never quantified directly;
- `? * + {n} {n,} {n,m}`, the lazy form of each, alternation (including empty
  branches), numbered captures, named captures `(?P<name>...)` and `(?<name>...)`
  (about 35% of captures), and `(?:...)`. Patterns nest to depth 2, or to
  depth 3 for a quarter of them, with at most eight captures;
- the `multiline` and `dot_matches_newline` options, each enabled in a quarter
  of the find cases.

Python compiles with `re.ASCII`; `(?<name>` maps to `(?P<name>`. Without multiline, `$` and `\z` map to
Python's `\Z`; `\x{H...}` maps to the literal scalar.

Lookbehind bodies come from the same grammar with captures turned off. Four
in five bodies use only exact counts, so most are fixed width; the rest give
Python's width rejection something to reject. Lookbehind nests one level, and
`\b`, `\B` and anchors may appear inside. The `lookbehind_find` stream is
separate, so the other surfaces generate exactly the cases they did before. Three documented
differences are kept outside the subset:

| Difference | How the generator avoids it |
| --- | --- |
| Empty iterations of a repeated body that can match empty: Pike state deduplication versus Python's extra empty pass (see the [dialect](extended-regex.md#dialect)) | Only `?` and `??` apply to a body that can match empty |
| `\B` in empty text matches in `ext::regex` (and RE2, and CPython 3.14), but not in CPython 3.12 | Inputs and grep records are nonempty when the pattern contains `\B` |
| `\s` includes VT in Python, but not in `ext::regex` | Inputs never contain VT |

CPython backtracks exponentially on some quantified groups over long
inputs. Inputs of 400 scalars are therefore used only for patterns with no
quantified group; the others use up to 40.

CPython's own `finditer` and `sub` retry an empty match position for a
nonempty match. Here, the next search starts one scalar after an empty match.
The Python side therefore runs the library's canonical progress loop
explicitly: it searches from the previous end and advances one scalar after an
empty match.

Five reduced cases are pinned and run before the generated ones. They are the
reductions of the defect below.

## Defect found and fixed

Lazy counted repetition with a zero minimum and at least two optional copies
had the wrong priority. The builder linked each optional copy's skip edge to
the *next* optional copy, not to the repeat exit. As a result `x{0,2}?`
behaved like `x??x??`, which tries every single iteration before any second
one. RE2, Go, Rust `regex` and Python nest the copies as `(?:x(?:x)??)??`.

```text
(?:a|aab){0,2}?b   on aabb   before: [0,4)          now and Python: [0,3) [3,4)
(a|1b|a1b){0,2}?\. on a1b.   before: group 1 [0,3)  now and Python: [1,3)
```

Greedy forms and forms with a nonzero minimum produced the same results
before the fix, because their extra paths repeat paths that have already
failed. The fix in `extended/ext/regex.lani` is two edges in `Builder.build`
phase 3: every optional copy now skips to `f.next`. The instruction count does
not change.

An old-versus-new comparison ran 18,000 cases from an unrestricted generator
that also quantifies nullable bodies. It found no other changed result. The 31
cases there that disagree with Python, before and after the fix, all repeat a
nullable body, which is the documented Pike cycle policy.

## Receipts

The receipts are for `extended/ext/regex.lani` SHA256
`baac32079de0d03c0f9f038b735ad9995eda4871b1c0aaa900ee70c48dd9389c`, oracle
SHA256 `a85b3d29888a5ca26e1c335182c8e8ea18a42515e20999a682b84869bd3d0148` and
`dfa.lani` SHA256
`b6112163f8d84bae6d2357e3fd486c1ebdb763f23fc1a22e4831962d1f64b999`, with
CPython 3.12.3, on native Linux x86_64. Executables were built with
`target/claude-work/bin/lcc`. Log:
`target/claude-work/s3/oracle-dfa-assert-receipt.log`. The earlier logs
`oracle-lookbehind-receipt.log` (before assertions in the DFA),
`oracle-dfa-receipt.log` (before lookbehind) and `oracle-receipt.log` (before
named groups and the DFA) are in the same directory.

| Seed | find_iter_captures | replace_template | grep_filter | lookbehind_find | dfa_match_find | linear_time | Wall time |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 20261031 | 12,005/12,005 | 1,000/1,000 | 1,000/1,000 | 2,728/2,728 | 3,000/3,000 | 6/6 | 8.65 s |
| 1 | 12,005/12,005 | 1,000/1,000 | 1,000/1,000 | 2,737/2,737 | 3,000/3,000 | 6/6 | 8.95 s |
| 2 | 12,005/12,005 | 1,000/1,000 | 1,000/1,000 | 2,809/2,809 | 3,000/3,000 | 6/6 | 8.60 s |
| 3 | 12,005/12,005 | 1,000/1,000 | 1,000/1,000 | 2,812/2,812 | 3,000/3,000 | 6/6 | 7.91 s |
| 4 | 12,005/12,005 | 1,000/1,000 | 1,000/1,000 | 2,767/2,767 | 3,000/3,000 | 6/6 | 8.67 s |
| Total | 60,025/60,025 | 5,000/5,000 | 5,000/5,000 | 13,853/13,853 | 15,000/15,000 | 30/30 | |

For the default seed, 6,942 of the find cases have at least one match, 4,890
have several matches, 2,440 report capture groups, 1,883 include an unset
optional group and 1,932 include named groups. Of its 1,000 lookbehind
patterns, Python rejected 424 for width, and Lanius rejected the same 424 with
`Syntax`. The other 576 gave 2,304 find cases, 1,497 of them with a match;
1,530 cases contain a negative lookbehind and 340 contain two or more. Across
the five seeds there are 2,049 width rejections and 11,804 lookbehind find
cases. Of the default seed's 3,000 `dfa_match_find` cases, 2,829 ran through a
`Dfa`, 830 of them with assertions; 171 lookbehind patterns stayed on the VM;
318 had a tiny work budget, where DFA and VM must agree exactly, `WorkLimit`
included. Across the five seeds the DFA path covered 14,155 cases (4,054 with
assertions), the VM path 845 and the tiny budget 1,533. The six pathological inputs
complete in about 0.35 s together; CPython alone takes about 30 s on the
lookbehind one.

A separate deeper sweep generated depth-3 patterns with up to ten captures and
inputs up to 20 scalars, using seeds 10 through 25. It had 192,000 find cases.
Before the fix, three of the first 72,000 disagreed, all from the lazy-counted
defect. After the fix, all 192,000 agree.

These receipts cover only the generated subset, CPython 3.12.3 and native
Linux x86_64. They do not establish agreement for unsupported syntax, Unicode
properties, nullable-repeat captures or other targets, and they make no
throughput claim. The Cargo test file was updated for the fourth surface but was not built
or run for this receipt.
The receipt comes from the same script running against CLI-built executables.
