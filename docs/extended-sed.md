# Stream editing (sed)

`ext::sed` runs sed scripts in the manner of GNU sed 4.9: addressed
commands applied to each line of an input stream. Regular expressions are
POSIX basic syntax, or extended syntax with `-E`, translated to
[`ext::regex`](extended-regex.md). The sample
`sample_programs/library/text_sed.lani` is a sed command over it, compared
with `/usr/bin/sed` by a differential oracle.

```lanius
let program: ext::sed::Program = core::result::unwrap(ext::sed::compile(script, false));
let run: ext::sed::Run = core::result::unwrap(program.run());
let output: alloc::vec::Vec<u8> = alloc::vec::new();
let quit: bool = core::result::unwrap(program.execute(run.borrow(), input, false, output.borrow()));
// output holds what the script wrote; run.exit_status() is q's code when quit.
output.destroy(); run.destroy(); program.destroy();
```

## API

| Call | Meaning |
| --- | --- |
| `compile(script: View<u8>, extended: bool) -> Result<Program, Error>` | Parse a UTF-8 script (several `-e` expressions joined by newlines) and compile its regexes; `extended` is `-E`. |
| `Program.quiet()` | The script began with the line `#n`, which acts as `-n`. |
| `Program.run() -> Result<Run, Error>` | Execution state for one stream: line counter, range states, the regex workspace and the pattern-space buffers. |
| `Program.execute(&Run, input: View<u8>, quiet: bool, &Vec<u8>) -> Result<bool, Error>` | Run every line of `input`, appending output. `$` is the last line of `input`. Returns whether `q` or `Q` ended the run. |
| `Program.execute_joined(&Run, input, joins: View<i32>, quiet, &Vec<u8>)` | The same over several files joined into one input. `joins` are the ascending indexes in `input.values` of newlines added after files without a final newline. |
| `Run.restart(&Program)` | A new file of a separate-files run (`-s`, `-i`): line numbers restart and no range stays open. |
| `Run.new_output()` | Output goes to a new destination, so no newline is owed to it. |
| `Run.exit_status()`, `ended()`, `line_number()` | The `q`/`Q` exit code, whether the run ended, lines read. |
| `Run.consumed()`, `looked_past()` | After `execute`: the end of the last line read, and whether the run then asked whether more input followed. See [unreadable files](#files). |
| `destroy()` | Release a `Program` or `Run`. |

`Error` values carry a byte offset in the script: `Syntax`,
`UnknownCommand`, `Unterminated`, `Regex`, `Reference` (a `\n` beyond the
regex's groups), `Unsupported` (a GNU feature outside this subset) and
`InvalidUtf8`. Running can fail with `InvalidUtf8` (a regex met a line that is
not UTF-8), `NoPreviousRegex` (an empty regex before any regex ran),
`WorkLimit`, `Limit` and `AllocationFailed`.

## Script language

| Form | Meaning |
| --- | --- |
| `N` | Line N (from 1; per file with `-s`/`-i`). |
| `$` | The last line of the input (of each file with `-s`/`-i`). |
| `/re/`, `\cREc` | Lines the regex matches; any delimiter `c` with `\c`. |
| `first~step` | Lines first, first+step, ...; `N~0` is line N. |
| `a1,a2` | A range: a1 opens it, a2 closes it (a2 is checked from the next line). A line-number a2 not after the opening line selects one line. |
| `0,/re/` | A range open from the start, so `/re/` may close it on line 1. |
| `a1,+N`, `a1,~N` | Up to N lines after the opening line; up to the next line that is a multiple of N. |
| `addr!` | The lines the address does not select. |
| `s/re/rep/flags` | Replace the leftmost-longest match; flags `g`, `p` and a number N (the Nth match, with `g` the Nth and later). `rep` takes `&`, `\0`-`\9`, `\n`, `\t`, `\&`, `\\` and an escaped delimiter or newline. |
| `y/src/dst/` | Transliterate scalars; both strings must have as many scalars. |
| `p`, `d`, `=` | Print the pattern space; delete it and start the next cycle; print the line number. |
| `n` | Print the pattern space (unless `-n`) and read the next line; at the last line it ends the cycle. |
| `q [code]`, `Q [code]` | Quit after printing the pattern space (`q`) or without printing (`Q`). |
| `{ ... }` | A block under one address. |
| `#` | A comment to the end of the line. |

Commands are separated by `;` or newlines. The other GNU commands (`a`, `i`,
`c`, `h`/`H`/`g`/`G`/`x`, `N`/`D`/`P`, `b`/`t`/`T`/`:`, `l`, `r`/`R`/`w`/`W`,
`e`, `F`, `z`, `v`), the `w` and `e` flags, the `I` and `M` modifiers and the
case conversions `\L`, `\U`, `\E`, `\l`, `\u` are `Unsupported`.

GNU behaviors the oracle pins:

- A file's last line without a newline is written without one. Any later
  output first writes the owed newline, and `q` writes it too.
- A line-number first address that `n` skipped over still opens the range,
  unless a line-number end was passed as well. A range whose first address is
  a line number closes for good.
- After a non-empty match, `s///g` does not take an empty match at its end
  (`s/b*/X/g` on `abc` gives `XaXcX`).
- In a bracket expression the delimiter is literal, `\n` and `\t` are newline
  and tab, and any other `\` is a member.
- An empty regex is the last regex used at run time.

### Regexes

The translator rewrites POSIX basic syntax for ext::regex: `\(`, `\)`, `\{`,
`\}`, `\|`, `\+` and `\?` become operators, the bare `( ) { } | + ?` become
literals, a `*` at the start of an expression or group is literal, and `^`
and `$` anchor only at the start and end of an expression or group. Extended
syntax passes through. In both, `.` matches any scalar including newline,
bracket classes such as `[[:digit:]]` become ASCII ranges, `` \` `` and `\'`
are `\A` and `\z`, and `\w`, `\W`, `\s`, `\S`, `\b`, `\B` keep their meaning.
`\<`, `\>`, back-references in the regex, `[.x.]` and `[=x=]` are
`Unsupported`.

`s///` takes the POSIX leftmost-longest match. The leftmost start is the
start of the first match by any rule. The end is the longest match from that
start. When the regex has a required literal, a line without it is skipped
before any regex work, and before its UTF-8 check. The unanchored lazy DFA gives the
earliest match end, which bounds the leftmost start. One anchored DFA run per
candidate start then finds the start and the longest end. The Pike VM runs
only for `\1`-`\9` captures, with the same longest end. Group spans follow
the VM's priority among equally long matches. For a group inside an
alternation or under a repetition, POSIX can choose a different span.

## Files

text_sed joins its files into one stream, as sed does. A file without a final
newline gets one only when more input follows (`execute_joined`). An
unreadable file is reported only if GNU sed would have opened it: when a
later line was read, or when the run asked whether input followed the
preceding file's last line. Asking means a `$` address, `n`, or starting
another cycle. So `sed q f missing` reports nothing, and `sed '$p' f missing`
reports `missing`.

With `-s` each file is its own stream on standard output. With `-i` each
file's output replaces the file through a new file `NAME.text-sed~` beside
it, renamed over it with the original permission bits. `q` and `Q` end every
file: the current file keeps only what was written before the quit, and later
files are untouched.

```
text-sed [-n|--quiet] [-E|-r|--regexp-extended] [-s|--separate] [-i|--in-place]
         [-e SCRIPT|--expression SCRIPT]... [SCRIPT] [FILE...]
```

Exit status is 0, 1 for a bad script, usage error or no previous regex, 2
when an input could not be read (it wins over a `q` code, as in GNU), 4
for a failure while running or writing, and otherwise the `q`/`Q` code.
`-i` takes no backup suffix, and `-in` means `-i -n`.

## Differences from GNU sed 4.9

- After an empty match GNU sed steps one byte, even inside a multibyte
  character. For example, `s/x*/-/g` on `é` writes `-\xc3-\xa9-`. ext::sed
  steps one scalar, so its output stays UTF-8.
- When GNU sed searches again after an empty match next to the previous
  match, it loses the left context of `\b` and `\B` (`s/.*\B/<&>/g` on `ab`
  gives `<a>b<>`).
- In en_US.UTF-8, glibc orders bracket ranges by collation, so `[a-z]` there
  matches `ß`. ext::regex compares scalar values.
- `\w`, `\b` and the POSIX classes are ASCII; glibc counts `é` as a letter.
- A regex command on a line that is not UTF-8 is an error (status 4). GNU
  matches such lines with invalid bytes as non-characters. Lines that no regex
  reads, or that lack a regex's required literal, pass through unchanged.
- In `y`, a source scalar listed twice maps by its first occurrence.
- Error messages differ. The status is the same.

## Verification

`tests/fixtures/extended/sed_oracle/oracle.py` generates scripts with every
command, address form and option above. It generates BRE and ERE regexes with
classes, intervals, groups, alternation, anchors and escapes, and
replacements with `&`, groups and escapes. Inputs are UTF-8 files with
`é` and `日`, with or without final newlines, plus empty files, standard
input and a missing file. 5% of the scripts carry a deliberate error. Each
case runs under `LC_ALL=en_US.UTF-8` in two copies of the files. The oracle
compares exit status, standard output, every file afterwards and the names
in "can't read" messages.

Repeated substitutions over non-ASCII input use regexes that cannot match
empty, and none uses `\b` or `\B`. Cases where GNU's output is invalid UTF-8
are counted separately. Neither GNU difference above is a disagreement.
Captures are referenced only for groups with a single possible span. ASCII-only
cases add `\w`, `\b` and the letter classes.

```
python3 -I tests/fixtures/extended/sed_oracle/oracle.py text_sed --seed S --count 1000 [--from K]
```

Results, eight seeds of 1,000 cases each: 8,000 of 8,000 agree, including
589 scripts both reject; no case needed the character-split exemption. A
seed takes 3 to 5 s. Log: `target/claude-work/s3/sed/oracle-receipt.log`.

Timings for an 8 MB, 190,990-line UTF-8 file of repository text. User time
is in seconds, with output to a file:

| Script | text_sed | GNU sed |
| --- | ---: | ---: |
| `d` | 0.04 | 0.02 |
| `p` | 0.14 | 0.03 |
| `/the/d` | 0.16 | 0.02 |
| `s/the/THE/g` | 0.41 | 0.02 |
| `s/[a-z]*e /<&>/g` | 0.76 | 0.15 |
| `s/\([a-z]*\)e /<\1>/g` | 1.17 | 0.29 |
| `s/x*/-/g` | 12.0 | 1.5 |
