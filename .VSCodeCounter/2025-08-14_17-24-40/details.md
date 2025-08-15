# Details

Date : 2025-08-14 17:24:40

Directory /home/andrew-peterson/code/laniusc

Total : 54 files,  7090 codes, 303 comments, 1045 blanks, all 8438 lines

[Summary](results.md) / Details / [Diff Summary](diff.md) / [Diff Details](diff-details.md)

## Files
| filename | language | code | comment | blank | total |
| :--- | :--- | ---: | ---: | ---: | ---: |
| [.cargo/config.toml](/.cargo/config.toml) | TOML | 7 | 3 | 2 | 12 |
| [.rustfmt.toml](/.rustfmt.toml) | TOML | 4 | 7 | 4 | 15 |
| [Cargo.lock](/Cargo.lock) | TOML | 1,590 | 2 | 194 | 1,786 |
| [Cargo.toml](/Cargo.toml) | TOML | 27 | 0 | 6 | 33 |
| [LEXING.md](/LEXING.md) | Markdown | 69 | 0 | 44 | 113 |
| [PARSING\_PLAN.md](/PARSING_PLAN.md) | Markdown | 150 | 0 | 72 | 222 |
| [README.md](/README.md) | Markdown | 26 | 0 | 17 | 43 |
| [build.rs](/build.rs) | Rust | 168 | 8 | 24 | 200 |
| [lexer\_tests/line\_comment\_eof.tokens.json](/lexer_tests/line_comment_eof.tokens.json) | JSON | 28 | 0 | 0 | 28 |
| [lexer\_tests/operators\_mix.tokens.json](/lexer_tests/operators_mix.tokens.json) | JSON | 100 | 0 | 0 | 100 |
| [lexer\_tests/simple.tokens.json](/lexer_tests/simple.tokens.json) | JSON | 56 | 0 | 0 | 56 |
| [lexer\_tests/tricky\_block\_near\_eof.tokens.json](/lexer_tests/tricky_block_near_eof.tokens.json) | JSON | 24 | 0 | 0 | 24 |
| [shaders/lexer/apply\_block\_prefix\_downsweep.slang](/shaders/lexer/apply_block_prefix_downsweep.slang) | Slang | 83 | 6 | 11 | 100 |
| [shaders/lexer/build\_tokens.slang](/shaders/lexer/build_tokens.slang) | Slang | 30 | 6 | 8 | 44 |
| [shaders/lexer/compact\_boundaries.slang](/shaders/lexer/compact_boundaries.slang) | Slang | 85 | 8 | 21 | 114 |
| [shaders/lexer/finalize\_boundaries\_and\_seed.slang](/shaders/lexer/finalize_boundaries_and_seed.slang) | Slang | 57 | 13 | 19 | 89 |
| [shaders/lexer/retag\_calls\_and\_arrays.slang](/shaders/lexer/retag_calls_and_arrays.slang) | Slang | 71 | 14 | 12 | 97 |
| [shaders/lexer/scan\_block\_summaries\_inclusive.slang](/shaders/lexer/scan_block_summaries_inclusive.slang) | Slang | 55 | 3 | 8 | 66 |
| [shaders/lexer/scan\_inblock\_inclusive.slang](/shaders/lexer/scan_inblock_inclusive.slang) | Slang | 81 | 6 | 10 | 97 |
| [shaders/lexer/sum\_apply\_block\_prefix\_downsweep\_pairs.slang](/shaders/lexer/sum_apply_block_prefix_downsweep_pairs.slang) | Slang | 53 | 5 | 13 | 71 |
| [shaders/lexer/sum\_inblock\_pairs.slang](/shaders/lexer/sum_inblock_pairs.slang) | Slang | 51 | 8 | 11 | 70 |
| [shaders/lexer/sum\_scan\_block\_totals\_inclusive.slang](/shaders/lexer/sum_scan_block_totals_inclusive.slang) | Slang | 40 | 3 | 6 | 49 |
| [shaders/lexer/utils.slang](/shaders/lexer/utils.slang) | Slang | 47 | 12 | 12 | 71 |
| [shaders/reminders.md](/shaders/reminders.md) | Markdown | 78 | 0 | 14 | 92 |
| [src/bin/fuzz\_lex.rs](/src/bin/fuzz_lex.rs) | Rust | 589 | 3 | 59 | 651 |
| [src/bin/gen\_tables.rs](/src/bin/gen_tables.rs) | Rust | 56 | 5 | 11 | 72 |
| [src/bin/perf\_one.rs](/src/bin/perf_one.rs) | Rust | 230 | 10 | 30 | 270 |
| [src/lexer/cpu.rs](/src/lexer/cpu.rs) | Rust | 120 | 11 | 20 | 151 |
| [src/lexer/gpu/buffers.rs](/src/lexer/gpu/buffers.rs) | Rust | 226 | 11 | 38 | 275 |
| [src/lexer/gpu/debug.rs](/src/lexer/gpu/debug.rs) | Rust | 62 | 2 | 13 | 77 |
| [src/lexer/gpu/mod.rs](/src/lexer/gpu/mod.rs) | Rust | 394 | 27 | 55 | 476 |
| [src/lexer/gpu/passes/apply\_block\_prefix\_downsweep.rs](/src/lexer/gpu/passes/apply_block_prefix_downsweep.rs) | Rust | 64 | 0 | 7 | 71 |
| [src/lexer/gpu/passes/build\_tokens.rs](/src/lexer/gpu/passes/build_tokens.rs) | Rust | 64 | 0 | 6 | 70 |
| [src/lexer/gpu/passes/compact\_boundaries\_all.rs](/src/lexer/gpu/passes/compact_boundaries_all.rs) | Rust | 79 | 3 | 9 | 91 |
| [src/lexer/gpu/passes/compact\_boundaries\_kept.rs](/src/lexer/gpu/passes/compact_boundaries_kept.rs) | Rust | 90 | 2 | 9 | 101 |
| [src/lexer/gpu/passes/finalize\_boundaries\_and\_seed.rs](/src/lexer/gpu/passes/finalize_boundaries_and_seed.rs) | Rust | 120 | 0 | 17 | 137 |
| [src/lexer/gpu/passes/mod.rs](/src/lexer/gpu/passes/mod.rs) | Rust | 298 | 17 | 35 | 350 |
| [src/lexer/gpu/passes/retag\_calls\_and\_arrays.rs](/src/lexer/gpu/passes/retag_calls_and_arrays.rs) | Rust | 62 | 6 | 8 | 76 |
| [src/lexer/gpu/passes/scan\_block\_summaries\_inclusive.rs](/src/lexer/gpu/passes/scan_block_summaries_inclusive.rs) | Rust | 154 | 3 | 20 | 177 |
| [src/lexer/gpu/passes/scan\_inblock\_inclusive\_pass.rs](/src/lexer/gpu/passes/scan_inblock_inclusive_pass.rs) | Rust | 69 | 0 | 8 | 77 |
| [src/lexer/gpu/passes/sum\_apply\_block\_prefix\_downsweep\_pairs.rs](/src/lexer/gpu/passes/sum_apply_block_prefix_downsweep_pairs.rs) | Rust | 52 | 0 | 7 | 59 |
| [src/lexer/gpu/passes/sum\_inblock\_pairs.rs](/src/lexer/gpu/passes/sum_inblock_pairs.rs) | Rust | 47 | 1 | 7 | 55 |
| [src/lexer/gpu/passes/sum\_scan\_block\_totals\_inclusive.rs](/src/lexer/gpu/passes/sum_scan_block_totals_inclusive.rs) | Rust | 145 | 2 | 19 | 166 |
| [src/lexer/gpu/timer.rs](/src/lexer/gpu/timer.rs) | Rust | 97 | 3 | 12 | 112 |
| [src/lexer/mod.rs](/src/lexer/mod.rs) | Rust | 3 | 1 | 1 | 5 |
| [src/lexer/tables/build.rs](/src/lexer/tables/build.rs) | Rust | 157 | 11 | 25 | 193 |
| [src/lexer/tables/compact.rs](/src/lexer/tables/compact.rs) | Rust | 59 | 10 | 12 | 81 |
| [src/lexer/tables/dfa.rs](/src/lexer/tables/dfa.rs) | Rust | 269 | 19 | 35 | 323 |
| [src/lexer/tables/io.rs](/src/lexer/tables/io.rs) | Rust | 186 | 17 | 27 | 230 |
| [src/lexer/tables/mod.rs](/src/lexer/tables/mod.rs) | Rust | 15 | 4 | 3 | 22 |
| [src/lexer/tables/tokens.rs](/src/lexer/tables/tokens.rs) | Rust | 48 | 10 | 9 | 67 |
| [src/lib.rs](/src/lib.rs) | Rust | 2 | 0 | 1 | 3 |
| [src/main.rs](/src/main.rs) | Rust | 20 | 2 | 4 | 26 |
| [src/reflection.rs](/src/reflection.rs) | Rust | 333 | 19 | 30 | 382 |

[Summary](results.md) / Details / [Diff Summary](diff.md) / [Diff Details](diff-details.md)