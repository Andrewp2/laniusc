# Command-line parsing

`std::cli` parses command-line arguments from a declared set of options, operands and subcommands, using GNU `getopt_long` rules. It also generates `--help` text and prints GNU-style error messages that name the bad argument.

The parser itself is pure: it reads a borrowed `View<View<u8>>`, such as `std::args::Arguments.as_view()`, and allocates only its result. Only `print_help` and `print_error` touch the host, writing to standard output and standard error.

The `ext::cli` family is the allocation-free alternative:
- [`ext::cli`](extended-cli.md) is an event tokenizer;
- [`ext::cli_commands`](extended-cli-commands.md) and `ext::cli_help` add command trees and help rendered into caller storage;
- completion and response files are separate modules.

That family takes exact long names only, with no abbreviations, and reports typed locations rather than messages. `std::cli` is a single declarative builder that follows `getopt_long` instead: unique prefixes, glibc's message texts, and help text in GNU layout. Programs that need allocation-free parsing or completion should keep using `ext::cli`.

## API

```text
std::cli::command(name: View<u8>, about: View<u8>) -> Command
Command.flag(id, short: u8, long: View<u8>, help: View<u8>)
Command.option(id, short, long, value_name: View<u8>, help)      // required value
Command.optional(id, short, long, value_name, help)              // attached value only
Command.help(id)                                                  // -h, --help
Command.operands(name: View<u8>, minimum: i32, maximum: i32)      // maximum -1: unbounded
Command.subcommand(id, name: View<u8>, help: View<u8>)            // later calls apply to it
Command.stop_at_operand()                                         // no permutation
Command.parse(args: View<View<u8>>) -> Result<Matches, Error>
Command.write_help(sub: i32, out: &Vec<u8>) -> bool               // sub -1: the root
Command.write_error(error: Error, args, out: &Vec<u8>) -> bool
Command.print_help(sub) -> bool, Command.print_error(error, args) -> bool
Command.destroy()
std::cli::kind_name(kind: ErrorKind) -> View<u8>

Matches.command() -> i32                    // subcommand id, or -1
Matches.count(id), present(id)
Matches.value(id) -> Option<View<u8>>       // last occurrence
Matches.value_at(id, n) -> Option<View<u8>> // n-th occurrence
Matches.occurrences(), occurrence_id(i), occurrence_value(i)
Matches.operand_count(), operand(i)
Matches.destroy()
```

- **Definitions:**
  - `short` is 0 for no short name, and `long` is empty for no long name; at least one must be given.
  - Short names are ASCII letters or digits. Long names are letters, digits and inner `-`, or start with one `-` before a letter or digit for hidden options spelled with three dashes, such as GNU tail's `---presume-input-pipe`.
  - A duplicate name in the same scope, a bad name or a bad operand count marks the command invalid, and `parse` then returns `InvalidSpec`.
  - Ids are the caller's. Every occurrence is recorded in argument order, so repeated options, counters (`-vvv`) and last-one-wins policies all read from `Matches`.
- **Borrowing:** names, help texts and parsed values borrow the caller's storage. `Matches` views borrow the arguments.

## Parsing rules

These follow glibc `getopt_long`:

- **Short options:** `-a`, and clusters `-abc`. A value-taking option takes the rest of its argument (`-fFILE`, `-abfFILE`). If nothing follows, a required option takes the next argument, even if that argument starts with `-` or is `--`. An optional short value must be attached (`-z3`).
- **Long options:** `--name`, `--name=value` and `--name value` (required values only). An unambiguous prefix selects an option (`--hist` for `--histogram`), and an exact name always wins over longer names it prefixes (`--all` versus `--almost-all`). An optional long value must use `=`.
- **Operands:** `-` alone is an operand. `--` ends options; later arguments, including another `--`, are operands.
- **Order:** by default options and operands may be interleaved, as GNU permutes. With `stop_at_operand()` the first operand ends options (`POSIXLY_CORRECT` or a leading `+`).
- **Subcommands:** with subcommands, root options come before the command name, and the first operand must name a subcommand. The rest is then parsed with that subcommand's options and operand count, using the same order rule. Root options are not accepted after the command name.
- **Help:** when a registered help flag occurs, `parse` skips the command and operand-count checks so the caller can print help. Option errors earlier in the arguments still win, as with `getopt`.

## Errors

`Error` is `{ kind, argument, offset, spec, scope }`:
- `argument` is the index of the offending argument;
- `offset` is the byte of the option character for short options;
- `spec` is the matched option where there is one;
- `scope` is -1 for the root, otherwise the subcommand index.

`write_error` prints `NAME: message` followed by `Try 'NAME --help' for more information.` when help is registered. The getopt messages are glibc's, checked against GNU coreutils 9.4 `ls`, `sort` and `head` on this machine:

| Kind | Message |
| --- | --- |
| `UnknownOption` | `unrecognized option '--colr=x'` (the whole argument) |
| `InvalidOption` | `invalid option -- 'j'` |
| `AmbiguousOption` | `option '--co' is ambiguous; possibilities: '--color' '--context'` (in definition order) |
| `UnexpectedValue` | `option '--all' doesn't allow an argument` (the full name, even when abbreviated) |
| `MissingValue` | `option '--file' requires an argument`, or `option requires an argument -- 'f'` |
| `MissingOperand` | `missing operand` (coreutils) |
| `ExtraOperand` | `extra operand 'x'` (coreutils) |
| `MissingCommand` | `missing command` |
| `UnknownCommand` | `unknown command 'x'` |
| `InvalidSpec`, `AllocationFailed` | `invalid option definitions`, `out of memory` (no Try line) |

## Help text

```text
Usage: tool [OPTION]... [FILE]...
List things.

Options:
  -a, --all           do not ignore entries starting with .
  -f, --file=ARCHIVE  use archive file ARCHIVE
      --color[=WHEN]  colorize the output;
                      WHEN is always, never or auto
  -C DIR              change to DIR first
  -h, --help          display this help and exit
```

- **Usage line:** it shows `[OPTION]...` when the scope has options, and `COMMAND [ARG]...` when there are subcommands. The operand name is wrapped in `[...]` when the minimum is 0, and followed by `...` when the maximum is unbounded.
- **Descriptions:** they start two spaces after the widest label, at column 30 at most. A longer label puts its description on the next line, and multi-line help text is indented to the same column.
- **Commands:** a `Commands:` list follows the options.
- **Subcommand help:** `write_help(id)` prints `Usage: NAME SUB ...` with that subcommand's options.

## Execution evidence

[`tests/fixtures/stdlib_cli/oracle.py`](../tests/fixtures/stdlib_cli/oracle.py) checks [`batch.lani`](../tests/fixtures/stdlib_cli/batch.lani), compiled with `lcc`, against a Python model of `getopt_long`. The model is itself checked against Python's `getopt` module.

**Checks:**
- For every case without optional values, `getopt.gnu_getopt`, or `getopt.getopt` for stop-at-operand and subcommand roots, must produce the model's occurrences, values and operands. On errors it must produce the same error and option name.
- `std::cli` must then match the model exactly: occurrences, values, operands, command, error kind, argument index, offset and message bytes.

**Generated cases:**
- One to six options per scope, drawn from long names that prefix each other (`all`/`almost-all`/`author`, `file`/`files`/`filter`, `version`/`verbose`, `out`/`output`, `c`), with any mix of short and long spellings and arities.
- Optional values in half the cases, operand bounds, stop-at-operand, and subcommands in a quarter.
- Arguments mix exact and abbreviated long options, `=value` forms, unknown names, clusters with unknown characters and attached values, `-`, `--`, and values such as `-x`, `--` and empty strings.

| Group | Cases | Agree |
| --- | --- | --- |
| Model against Python `getopt` | 4,051 | 4,051 |
| `std::cli` against the model, including 26 fixed cases taken from `ls`, `sort` and `head` | 6,026 | 6,026 |
| Hand-written `--help` texts | 7 | 7 |

- The default seed's outcomes are 1,748 successful parses plus every error kind except `InvalidSpec` and `AllocationFailed`.
- Seeds 1 and 2 with `--cases 30000` also agree.

```text
lcc -o batch tests/fixtures/stdlib_cli/batch.lani --stdlib-root stdlib --source-root extended
python3 -I tests/fixtures/stdlib_cli/oracle.py ./batch [--seed N] [--cases N]
```

## Samples

- **[`tgz`](../sample_programs/library/tgz.lani):** moved from `ext::cli`. It gains long-option abbreviations, a generated `--help`, and GNU messages such as `tgz: option requires an argument -- 'f'`. Mode and compression conflicts are still checked by the tool, in argument order. The tgz oracle (`--quick`, 1,332 cases) still agrees.
- **[`seq-diff`](../sample_programs/library/seq_diff.lani):** moved from a hand-written argument loop. It now accepts `-U3`, `--unified=3`, `--word-diff[=plain]`, `--word-diff-regex=.` and `--stat[=W[,N[,C]]]` through the parser, plus prefixes such as `--hist`. The seq-diff and seq-patch oracle, the word-diff oracle (400 pairs) and the `git diff` oracle (1,200 pairs) still agree with 0 failures.
