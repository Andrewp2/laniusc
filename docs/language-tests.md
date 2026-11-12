# Language tests: `laniusc test`

`laniusc test` compiles and runs test programs written in Lanius. One process
starts the compiler once, compiles every test in turn and runs the programs on
worker threads. The x86_64 backend is the only target.

```
laniusc test [--stdlib-root dir] [--filter text] [--jobs n] [--run-timeout-ms n] [--verbose] <path>...
```

Each path is a `.lani` file or a directory that is searched for `.lani` files.
`--stdlib-root` defaults to `./stdlib`. `--filter` keeps the tests whose path
contains the text. `--jobs` is the number of programs that run at once.
`--run-timeout-ms` ends a program that runs longer (default 10000).
`--verbose` prints one line per passing test with its compile time.

The 116 tests in `tests/fixtures/language/` run in about 12 s:

```
laniusc test --stdlib-root stdlib tests/fixtures/language
```

## Directives

A test is a `.lani` file whose leading `//` comment lines hold at least one
`//@` directive. A file without a directive is a module that tests import.

| Directive | Meaning |
| --- | --- |
| `//@ exit N` | The program exits with status `N`. Without it the expected status is 0. |
| `//@ signal N` | Signal `N` ends the program. |
| `//@ stdout TEXT` | One line of expected standard output. Repeat it for more lines. |
| `//@ stderr TEXT` | One line of expected standard error. Repeat it for more lines. |
| `//@ error TEXT` | The compile fails and the diagnostic contains `TEXT`. Repeat it to require several texts. |
| `//@ source-root DIR` | A source root, relative to the directory of the file. Repeat it for more roots. |

```lanius
//@ exit 7
//@ stdout seven

import std::io;

fn main() -> i32 {
    std::io::println("seven");
    return 7;
}
```

A diagnostic text can name a position, such as `main.lani:12:5`. The
directive lines count as lines of the file.

## Output

A failing test prints `FAIL path` and the reason. The last line is the result:

```
test result: ok. 116 passed; 0 failed; 12.1 s (compiler start 0.9 s, compiles 10.0 s)
```

The command exits with a nonzero status when a test fails.

## The Rust harness

`tests/language_ergonomics_execution.rs` runs the command over
`tests/fixtures/language/` in one Rust test,
`every_language_program_test_passes`. The same file keeps the two Wasm tests
and the scope-tree layout test, which the directives cannot express yet.
