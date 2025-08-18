# Details

Date : 2025-08-17 15:20:01

Directory /home/andrew-peterson/code/laniusc

Total : 87 files,  10679 codes, 706 comments, 1593 blanks, all 12978 lines

[Summary](results.md) / Details / [Diff Summary](diff.md) / [Diff Details](diff-details.md)

## Files
| filename | language | code | comment | blank | total |
| :--- | :--- | ---: | ---: | ---: | ---: |
| [.cargo/config.toml](/.cargo/config.toml) | TOML | 7 | 3 | 2 | 12 |
| [.rustfmt.toml](/.rustfmt.toml) | TOML | 4 | 7 | 4 | 15 |
| [Cargo.lock](/Cargo.lock) | TOML | 1,785 | 2 | 217 | 2,004 |
| [Cargo.toml](/Cargo.toml) | TOML | 30 | 0 | 6 | 36 |
| [LEXING.md](/LEXING.md) | Markdown | 69 | 0 | 44 | 113 |
| [LEXING\_ADDITIONAL.md](/LEXING_ADDITIONAL.md) | Markdown | 150 | 0 | 72 | 222 |
| [LLM\_REMINDERS.md](/LLM_REMINDERS.md) | Markdown | 3 | 0 | 0 | 3 |
| [PARSING.md](/PARSING.md) | Markdown | 47 | 0 | 25 | 72 |
| [README.md](/README.md) | Markdown | 26 | 0 | 17 | 43 |
| [build.rs](/build.rs) | Rust | 172 | 8 | 24 | 204 |
| [deny.toml](/deny.toml) | TOML | 55 | 175 | 15 | 245 |
| [lexer\_tests/line\_comment\_eof.tokens.json](/lexer_tests/line_comment_eof.tokens.json) | JSON | 28 | 0 | 0 | 28 |
| [lexer\_tests/operators\_mix.tokens.json](/lexer_tests/operators_mix.tokens.json) | JSON | 100 | 0 | 0 | 100 |
| [lexer\_tests/simple.tokens.json](/lexer_tests/simple.tokens.json) | JSON | 56 | 0 | 0 | 56 |
| [lexer\_tests/tricky\_block\_near\_eof.tokens.json](/lexer_tests/tricky_block_near_eof.tokens.json) | JSON | 24 | 0 | 0 | 24 |
| [shaders/lexer/boundary\_finalize\_and\_seed.slang](/shaders/lexer/boundary_finalize_and_seed.slang) | Slang | 60 | 0 | 18 | 78 |
| [shaders/lexer/compact\_boundaries.slang](/shaders/lexer/compact_boundaries.slang) | Slang | 103 | 17 | 24 | 144 |
| [shaders/lexer/dfa\_01\_scan\_inblock.slang](/shaders/lexer/dfa_01_scan_inblock.slang) | Slang | 122 | 13 | 21 | 156 |
| [shaders/lexer/dfa\_02\_scan\_block\_summaries.slang](/shaders/lexer/dfa_02_scan_block_summaries.slang) | Slang | 54 | 6 | 13 | 73 |
| [shaders/lexer/dfa\_03\_apply\_block\_prefix.slang](/shaders/lexer/dfa_03_apply_block_prefix.slang) | Slang | 119 | 7 | 20 | 146 |
| [shaders/lexer/pair\_01\_sum\_inblock.slang](/shaders/lexer/pair_01_sum_inblock.slang) | Slang | 51 | 8 | 11 | 70 |
| [shaders/lexer/pair\_02\_scan\_block\_totals.slang](/shaders/lexer/pair_02_scan_block_totals.slang) | Slang | 46 | 6 | 8 | 60 |
| [shaders/lexer/pair\_03\_apply\_block\_prefix.slang](/shaders/lexer/pair_03_apply_block_prefix.slang) | Slang | 53 | 5 | 13 | 71 |
| [shaders/lexer/retag\_calls\_and\_arrays.slang](/shaders/lexer/retag_calls_and_arrays.slang) | Slang | 71 | 14 | 12 | 97 |
| [shaders/lexer/tokens\_build.slang](/shaders/lexer/tokens_build.slang) | Slang | 30 | 6 | 8 | 44 |
| [shaders/lexer/utils.slang](/shaders/lexer/utils.slang) | Slang | 63 | 0 | 16 | 79 |
| [shaders/parser/brackets\_match.slang](/shaders/parser/brackets_match.slang) | Slang | 77 | 14 | 16 | 107 |
| [shaders/parser/llp\_pairs.slang](/shaders/parser/llp_pairs.slang) | Slang | 37 | 0 | 7 | 44 |
| [shaders/parser/pack\_varlen.slang](/shaders/parser/pack_varlen.slang) | Slang | 80 | 12 | 18 | 110 |
| [shaders/reminders.md](/shaders/reminders.md) | Markdown | 55 | 0 | 14 | 69 |
| [src/bin/fuzz\_lex.rs](/src/bin/fuzz_lex.rs) | Rust | 497 | 0 | 47 | 544 |
| [src/bin/gen\_lex\_tables.rs](/src/bin/gen_lex_tables.rs) | Rust | 56 | 5 | 11 | 72 |
| [src/bin/gen\_parse\_tables.rs](/src/bin/gen_parse_tables.rs) | Rust | 91 | 25 | 15 | 131 |
| [src/bin/parse\_demo.rs](/src/bin/parse_demo.rs) | Rust | 117 | 3 | 17 | 137 |
| [src/bin/perf\_one.rs](/src/bin/perf_one.rs) | Rust | 184 | 0 | 19 | 203 |
| [src/bin/recount\_compact.rs](/src/bin/recount_compact.rs) | Rust | 20 | 2 | 5 | 27 |
| [src/dev/generator.rs](/src/dev/generator.rs) | Rust | 116 | 18 | 16 | 150 |
| [src/dev/mod.rs](/src/dev/mod.rs) | Rust | 1 | 0 | 1 | 2 |
| [src/gpu/buffers.rs](/src/gpu/buffers.rs) | Rust | 125 | 15 | 13 | 153 |
| [src/gpu/debug.rs](/src/gpu/debug.rs) | Rust | 50 | 8 | 8 | 66 |
| [src/gpu/device.rs](/src/gpu/device.rs) | Rust | 65 | 4 | 14 | 83 |
| [src/gpu/mod.rs](/src/gpu/mod.rs) | Rust | 5 | 1 | 2 | 8 |
| [src/gpu/passes\_core.rs](/src/gpu/passes_core.rs) | Rust | 291 | 4 | 35 | 330 |
| [src/gpu/timer.rs](/src/gpu/timer.rs) | Rust | 101 | 9 | 14 | 124 |
| [src/lexer/cpu.rs](/src/lexer/cpu.rs) | Rust | 120 | 11 | 20 | 151 |
| [src/lexer/gpu/buffers.rs](/src/lexer/gpu/buffers.rs) | Rust | 156 | 0 | 34 | 190 |
| [src/lexer/gpu/debug.rs](/src/lexer/gpu/debug.rs) | Rust | 46 | 5 | 13 | 64 |
| [src/lexer/gpu/debug\_checks.rs](/src/lexer/gpu/debug_checks.rs) | Rust | 870 | 56 | 93 | 1,019 |
| [src/lexer/gpu/debug\_host.rs](/src/lexer/gpu/debug_host.rs) | Rust | 81 | 3 | 20 | 104 |
| [src/lexer/gpu/driver.rs](/src/lexer/gpu/driver.rs) | Rust | 364 | 3 | 47 | 414 |
| [src/lexer/gpu/mod.rs](/src/lexer/gpu/mod.rs) | Rust | 13 | 3 | 4 | 20 |
| [src/lexer/gpu/passes/boundary\_finalize\_and\_seed.rs](/src/lexer/gpu/passes/boundary_finalize_and_seed.rs) | Rust | 92 | 0 | 12 | 104 |
| [src/lexer/gpu/passes/compact\_boundaries\_all.rs](/src/lexer/gpu/passes/compact_boundaries_all.rs) | Rust | 83 | 0 | 8 | 91 |
| [src/lexer/gpu/passes/compact\_boundaries\_kept.rs](/src/lexer/gpu/passes/compact_boundaries_kept.rs) | Rust | 94 | 0 | 8 | 102 |
| [src/lexer/gpu/passes/dfa\_01\_scan\_inblock.rs](/src/lexer/gpu/passes/dfa_01_scan_inblock.rs) | Rust | 66 | 0 | 9 | 75 |
| [src/lexer/gpu/passes/dfa\_02\_scan\_block\_summaries.rs](/src/lexer/gpu/passes/dfa_02_scan_block_summaries.rs) | Rust | 192 | 3 | 28 | 223 |
| [src/lexer/gpu/passes/dfa\_03\_apply\_block\_prefix.rs](/src/lexer/gpu/passes/dfa_03_apply_block_prefix.rs) | Rust | 100 | 0 | 12 | 112 |
| [src/lexer/gpu/passes/mod.rs](/src/lexer/gpu/passes/mod.rs) | Rust | 175 | 0 | 23 | 198 |
| [src/lexer/gpu/passes/pair\_01\_sum\_inblock.rs](/src/lexer/gpu/passes/pair_01_sum_inblock.rs) | Rust | 66 | 0 | 7 | 73 |
| [src/lexer/gpu/passes/pair\_02\_scan\_block\_totals.rs](/src/lexer/gpu/passes/pair_02_scan_block_totals.rs) | Rust | 206 | 1 | 25 | 232 |
| [src/lexer/gpu/passes/pair\_03\_apply\_block\_prefix.rs](/src/lexer/gpu/passes/pair_03_apply_block_prefix.rs) | Rust | 104 | 0 | 13 | 117 |
| [src/lexer/gpu/passes/retag\_calls\_and\_arrays.rs](/src/lexer/gpu/passes/retag_calls_and_arrays.rs) | Rust | 66 | 0 | 8 | 74 |
| [src/lexer/gpu/passes/tokens\_build.rs](/src/lexer/gpu/passes/tokens_build.rs) | Rust | 68 | 0 | 6 | 74 |
| [src/lexer/gpu/types.rs](/src/lexer/gpu/types.rs) | Rust | 25 | 1 | 6 | 32 |
| [src/lexer/gpu/util.rs](/src/lexer/gpu/util.rs) | Rust | 50 | 6 | 12 | 68 |
| [src/lexer/mod.rs](/src/lexer/mod.rs) | Rust | 3 | 1 | 1 | 5 |
| [src/lexer/tables/build.rs](/src/lexer/tables/build.rs) | Rust | 157 | 11 | 25 | 193 |
| [src/lexer/tables/compact.rs](/src/lexer/tables/compact.rs) | Rust | 59 | 10 | 12 | 81 |
| [src/lexer/tables/dfa.rs](/src/lexer/tables/dfa.rs) | Rust | 269 | 19 | 35 | 323 |
| [src/lexer/tables/io.rs](/src/lexer/tables/io.rs) | Rust | 186 | 17 | 27 | 230 |
| [src/lexer/tables/mod.rs](/src/lexer/tables/mod.rs) | Rust | 15 | 4 | 3 | 22 |
| [src/lexer/tables/tokens.rs](/src/lexer/tables/tokens.rs) | Rust | 49 | 10 | 9 | 68 |
| [src/lib.rs](/src/lib.rs) | Rust | 6 | 0 | 1 | 7 |
| [src/main.rs](/src/main.rs) | Rust | 20 | 2 | 4 | 26 |
| [src/parser/gpu/buffers.rs](/src/parser/gpu/buffers.rs) | Rust | 181 | 18 | 32 | 231 |
| [src/parser/gpu/debug.rs](/src/parser/gpu/debug.rs) | Rust | 17 | 6 | 6 | 29 |
| [src/parser/gpu/driver.rs](/src/parser/gpu/driver.rs) | Rust | 296 | 27 | 36 | 359 |
| [src/parser/gpu/mod.rs](/src/parser/gpu/mod.rs) | Rust | 5 | 1 | 2 | 8 |
| [src/parser/gpu/passes/brackets\_match.rs](/src/parser/gpu/passes/brackets_match.rs) | Rust | 88 | 2 | 10 | 100 |
| [src/parser/gpu/passes/llp\_pairs.rs](/src/parser/gpu/passes/llp_pairs.rs) | Rust | 61 | 0 | 10 | 71 |
| [src/parser/gpu/passes/mod.rs](/src/parser/gpu/passes/mod.rs) | Rust | 6 | 2 | 2 | 10 |
| [src/parser/gpu/passes/pack\_varlen.rs](/src/parser/gpu/passes/pack_varlen.rs) | Rust | 97 | 1 | 12 | 110 |
| [src/parser/mod.rs](/src/parser/mod.rs) | Rust | 2 | 0 | 1 | 3 |
| [src/parser/tables.rs](/src/parser/tables.rs) | Rust | 342 | 56 | 47 | 445 |
| [src/reflection.rs](/src/reflection.rs) | Rust | 333 | 19 | 30 | 382 |
| [src/type\_checker/mod.rs](/src/type_checker/mod.rs) | Rust | 0 | 0 | 1 | 1 |
| [tests/size\_sweep.rs](/tests/size_sweep.rs) | Rust | 154 | 11 | 17 | 182 |

[Summary](results.md) / Details / [Diff Summary](diff.md) / [Diff Details](diff-details.md)