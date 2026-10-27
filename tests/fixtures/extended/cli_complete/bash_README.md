# Bash word and reply codec fixtures

## Current status

The final fragment-metadata pure contracts compiled and executed successfully
against encoder `b6036015`, decoder `2b086426` and contracts `7aabacc1`.
`completion-bash-contracts-final-compile-first.log` records compilation exit 0;
`completion-bash-contracts-final-no-host.trace` contains only launch and raw
exit 0 while all mmap calls were denied. The corresponding native log is
empty. The emitted ELF SHA-256 is
`b28c20b96a2d4a569287c159fe4aa70f4d95cdae78a1b1453b9537f13428b0ef`.
No allocation denial was reached, so this is no-allocation behavior rather
than OOM recovery evidence. This was a direct executable gate, not a Rust
libtest execution.

The final binary model also compiled and passed its direct Python oracle on
the first attempt: `completion-bash-model-compile-first.log` and
`completion-bash-model-native-first.log`, with model `22699893` and oracle
`c7acf4c0` against the same decoder/encoder. It executed 389 commands in one
native process: 270 decoder commands and 119 reply commands, seed
`3125936166`. Evidence is `/tmp/cli-bash-model-htwm6ee3`; the emitted ELF
SHA-256 is
`cb7b25aabd8e10ac19f12bc8f5e347ee1cd200dcc3b965b85e1fd4cc36f27ffe`.
This is a direct model receipt, not a second Rust libtest pass. The registered
Rust driver has separate combined `--no-run` build admission in 3.56s in
`target/stdlib-work/completion-bash-app-drivers-build-first.log`, alongside the
shell and query-resource drivers. That build did not execute their native Rust
tests and is not added to these direct program receipts.

The Python oracle separately passed 14 CPU controls over this command set.
These controls validate the oracle and its transport; they do not execute
Lanius and are not added to the native command count.

The earlier encoder `91a431cd` and contracts `e21f7acf` compiled and ran with no
host effects in `completion-bash-contracts-compile-first.log` and
`completion-bash-contracts-no-host.log`. That receipt covers the earlier frame
without quote, continuation and trim records. It does not establish runtime
acceptance of the current frame. The adapter's actual Readline fragment
behavior required the new records; there is no old-frame compatibility path.

## Public APIs and exact frame

The tests use the actual `ext::bash_words` decoder and `ext::cli_bash` encoder.
The encoder accepts borrowed data:

```lani
Reply {
    mode:Mode, append_space:bool,
    quote:ext::bash_words::Quote, continuation:ext::bash_words::Quote,
    trim:View<u8>, stem:View<u8>, prefix:View<u8>,
    candidates:View<View<u8>>
}
measure(Reply) -> Result<u64,Error>
encode_into(Reply,View<u8>) -> Result<i32,Error>
```

Every record below ends in NUL, including the final `end` record:

1. `lanius-completion-1`
2. `candidates`, `files` or `none`
3. `space` or `nospace`
4. fragment-start quote: `unquoted`, `single` or `double`
5. old-cursor continuation quote: the same three spellings
6. trim
7. stem
8. prefix
9. canonical decimal candidate count
10. each candidate, in order
11. `end`

Candidates requires empty stem and prefix. Files requires no candidates. None
requires no candidates and empty trim, stem and prefix. Spacing and both quote
states are permitted in every mode. Trim is opaque non-NUL data to this codec;
the bridge checks and removes it when inserting a replacement. Candidates
remain whole-prefix replacement words. Empty candidate words are valid.

All outer and nested logical ranges are checked before mode constraints, then
NUL checks run in trim/stem/prefix/candidate order. Checked size precedes output
range and capacity checks. Every error preserves the entire output. Success
writes exactly the measured bytes and preserves unused output bytes. Errors
are Bounds, InvalidReply, NulTrim(index), NulStem(index), NulPrefix(index),
NulCandidate(candidate,index), OutputTooSmall(required) and SizeOverflow.

## Executable test design

`bash_contracts.lani` performs no I/O or allocation. It checks literal frame
records, decimal counts 0/3/12, all modes, quote/continuation metadata, opaque
trim, empty candidates, arbitrary non-NUL bytes, bounds/error precedence,
exact capacity and one-byte-short atomic refusal. It uses native descending
stack slices and packed ascending backing with nonzero logical offsets and
canaries. Decoder goldens cover literal concatenation, quoting, pending prefix
escapes, double-quote retained backslashes, unsafe syntax and error offsets.

`bash_model.lani` is only a binary transport around the real public functions.
`bash_model.py` supplies independent literal expected words and NUL frames.
Generated decoder inputs are safe single-quoted spellings of independently
chosen bytes, including every non-NUL byte and apostrophe concatenation. The
oracle does not implement a second decoder or invoke shell evaluation.

The 389 commands run in one model process. They cover Complete and Prefix
decoder modes, all four input/output stride-sign combinations, all unsafe
classes, leading versus literal `#`, CR/VT/FF, NUL and syntax/output precedence,
negative/overflowed logical ranges, exact and short capacities, all reply
mode/spacing/quote/continuation combinations, counts 0/1/9/10/32 and raw bytes.
The fixed generation seed is `3125936166` (`0xBA520026`). The model checks exact
metadata and bytes, canaries, and rejection of truncated or extra output. Its
native runner preserves request, command, stdout and stderr files on failure
and has a 30-second subprocess deadline.

The test transport starts with a little-endian u64 command count. Each command
has a 128-byte header, raw stem/input, prefix, trim, then length-prefixed
candidates. Each response is a 96-byte header followed by the success payload.
This format is fixture-only; production uses the NUL frame above.

## Commands and scope

The parent serializes compiler and native execution. The two registered Rust
filters are:

```text
bash_word_and_reply_atomic_stride_contracts_execute
bash_words_and_reply_frames_match_literal_binary_models
```

CPU oracle controls were run with:

```sh
timeout --kill-after=2s 100s python3 -B tests/fixtures/extended/cli_complete/bash_model.py controls
```

Current output: `cli-bash CPU controls=14 cases=389 seed=3125936166`.

After compiling `bash_model.lani`, its direct oracle command is:

```sh
python3 -B tests/fixtures/extended/cli_complete/bash_model.py MODEL_ELF
```

Logical bounds checks cannot establish physical backing or lifetime. All
borrowed inputs must remain immutable and live, and output must be disjoint
from them. SizeOverflow is guarded in production but is not forced using fake
huge backing. These pure codecs allocate no memory, so an allocation-failure
campaign would add no useful case. The binary model's stream I/O belongs to
the fixture, not the codecs.

Native acceptance is finite Linux x86_64 CPU execution of output produced by
the GPU compiler. It is separate from actual Bash adapter,
PTY insertion, filename generation and shell-version acceptance. There is no
claim of support for all shell syntax or other shells.
