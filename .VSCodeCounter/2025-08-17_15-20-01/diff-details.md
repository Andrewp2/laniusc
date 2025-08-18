# Diff Details

Date : 2025-08-17 15:20:01

Directory /home/andrew-peterson/code/laniusc

Total : 88 files,  3589 codes, 403 comments, 548 blanks, all 4540 lines

[Summary](results.md) / [Details](details.md) / [Diff Summary](diff.md) / Diff Details

## Files
| filename | language | code | comment | blank | total |
| :--- | :--- | ---: | ---: | ---: | ---: |
| [Cargo.lock](/Cargo.lock) | TOML | 195 | 0 | 23 | 218 |
| [Cargo.toml](/Cargo.toml) | TOML | 3 | 0 | 0 | 3 |
| [LEXING\_ADDITIONAL.md](/LEXING_ADDITIONAL.md) | Markdown | 150 | 0 | 72 | 222 |
| [LLM\_REMINDERS.md](/LLM_REMINDERS.md) | Markdown | 3 | 0 | 0 | 3 |
| [PARSING.md](/PARSING.md) | Markdown | 47 | 0 | 25 | 72 |
| [PARSING\_PLAN.md](/PARSING_PLAN.md) | Markdown | -150 | 0 | -72 | -222 |
| [build.rs](/build.rs) | Rust | 4 | 0 | 0 | 4 |
| [deny.toml](/deny.toml) | TOML | 55 | 175 | 15 | 245 |
| [shaders/lexer/apply\_block\_prefix\_downsweep.slang](/shaders/lexer/apply_block_prefix_downsweep.slang) | Slang | -83 | -6 | -11 | -100 |
| [shaders/lexer/boundary\_finalize\_and\_seed.slang](/shaders/lexer/boundary_finalize_and_seed.slang) | Slang | 60 | 0 | 18 | 78 |
| [shaders/lexer/build\_tokens.slang](/shaders/lexer/build_tokens.slang) | Slang | -30 | -6 | -8 | -44 |
| [shaders/lexer/compact\_boundaries.slang](/shaders/lexer/compact_boundaries.slang) | Slang | 18 | 9 | 3 | 30 |
| [shaders/lexer/dfa\_01\_scan\_inblock.slang](/shaders/lexer/dfa_01_scan_inblock.slang) | Slang | 122 | 13 | 21 | 156 |
| [shaders/lexer/dfa\_02\_scan\_block\_summaries.slang](/shaders/lexer/dfa_02_scan_block_summaries.slang) | Slang | 54 | 6 | 13 | 73 |
| [shaders/lexer/dfa\_03\_apply\_block\_prefix.slang](/shaders/lexer/dfa_03_apply_block_prefix.slang) | Slang | 119 | 7 | 20 | 146 |
| [shaders/lexer/finalize\_boundaries\_and\_seed.slang](/shaders/lexer/finalize_boundaries_and_seed.slang) | Slang | -57 | -13 | -19 | -89 |
| [shaders/lexer/pair\_01\_sum\_inblock.slang](/shaders/lexer/pair_01_sum_inblock.slang) | Slang | 51 | 8 | 11 | 70 |
| [shaders/lexer/pair\_02\_scan\_block\_totals.slang](/shaders/lexer/pair_02_scan_block_totals.slang) | Slang | 46 | 6 | 8 | 60 |
| [shaders/lexer/pair\_03\_apply\_block\_prefix.slang](/shaders/lexer/pair_03_apply_block_prefix.slang) | Slang | 53 | 5 | 13 | 71 |
| [shaders/lexer/scan\_block\_summaries\_inclusive.slang](/shaders/lexer/scan_block_summaries_inclusive.slang) | Slang | -55 | -3 | -8 | -66 |
| [shaders/lexer/scan\_inblock\_inclusive.slang](/shaders/lexer/scan_inblock_inclusive.slang) | Slang | -81 | -6 | -10 | -97 |
| [shaders/lexer/sum\_apply\_block\_prefix\_downsweep\_pairs.slang](/shaders/lexer/sum_apply_block_prefix_downsweep_pairs.slang) | Slang | -53 | -5 | -13 | -71 |
| [shaders/lexer/sum\_inblock\_pairs.slang](/shaders/lexer/sum_inblock_pairs.slang) | Slang | -51 | -8 | -11 | -70 |
| [shaders/lexer/sum\_scan\_block\_totals\_inclusive.slang](/shaders/lexer/sum_scan_block_totals_inclusive.slang) | Slang | -40 | -3 | -6 | -49 |
| [shaders/lexer/tokens\_build.slang](/shaders/lexer/tokens_build.slang) | Slang | 30 | 6 | 8 | 44 |
| [shaders/lexer/utils.slang](/shaders/lexer/utils.slang) | Slang | 16 | -12 | 4 | 8 |
| [shaders/parser/brackets\_match.slang](/shaders/parser/brackets_match.slang) | Slang | 77 | 14 | 16 | 107 |
| [shaders/parser/llp\_pairs.slang](/shaders/parser/llp_pairs.slang) | Slang | 37 | 0 | 7 | 44 |
| [shaders/parser/pack\_varlen.slang](/shaders/parser/pack_varlen.slang) | Slang | 80 | 12 | 18 | 110 |
| [shaders/reminders.md](/shaders/reminders.md) | Markdown | -23 | 0 | 0 | -23 |
| [src/bin/fuzz\_lex.rs](/src/bin/fuzz_lex.rs) | Rust | -92 | -3 | -12 | -107 |
| [src/bin/gen\_lex\_tables.rs](/src/bin/gen_lex_tables.rs) | Rust | 56 | 5 | 11 | 72 |
| [src/bin/gen\_parse\_tables.rs](/src/bin/gen_parse_tables.rs) | Rust | 91 | 25 | 15 | 131 |
| [src/bin/gen\_tables.rs](/src/bin/gen_tables.rs) | Rust | -56 | -5 | -11 | -72 |
| [src/bin/parse\_demo.rs](/src/bin/parse_demo.rs) | Rust | 117 | 3 | 17 | 137 |
| [src/bin/perf\_one.rs](/src/bin/perf_one.rs) | Rust | -46 | -10 | -11 | -67 |
| [src/bin/recount\_compact.rs](/src/bin/recount_compact.rs) | Rust | 20 | 2 | 5 | 27 |
| [src/dev/generator.rs](/src/dev/generator.rs) | Rust | 116 | 18 | 16 | 150 |
| [src/dev/mod.rs](/src/dev/mod.rs) | Rust | 1 | 0 | 1 | 2 |
| [src/gpu/buffers.rs](/src/gpu/buffers.rs) | Rust | 125 | 15 | 13 | 153 |
| [src/gpu/debug.rs](/src/gpu/debug.rs) | Rust | 50 | 8 | 8 | 66 |
| [src/gpu/device.rs](/src/gpu/device.rs) | Rust | 65 | 4 | 14 | 83 |
| [src/gpu/mod.rs](/src/gpu/mod.rs) | Rust | 5 | 1 | 2 | 8 |
| [src/gpu/passes\_core.rs](/src/gpu/passes_core.rs) | Rust | 291 | 4 | 35 | 330 |
| [src/gpu/timer.rs](/src/gpu/timer.rs) | Rust | 101 | 9 | 14 | 124 |
| [src/lexer/gpu/buffers.rs](/src/lexer/gpu/buffers.rs) | Rust | -70 | -11 | -4 | -85 |
| [src/lexer/gpu/debug.rs](/src/lexer/gpu/debug.rs) | Rust | -16 | 3 | 0 | -13 |
| [src/lexer/gpu/debug\_checks.rs](/src/lexer/gpu/debug_checks.rs) | Rust | 870 | 56 | 93 | 1,019 |
| [src/lexer/gpu/debug\_host.rs](/src/lexer/gpu/debug_host.rs) | Rust | 81 | 3 | 20 | 104 |
| [src/lexer/gpu/driver.rs](/src/lexer/gpu/driver.rs) | Rust | 364 | 3 | 47 | 414 |
| [src/lexer/gpu/mod.rs](/src/lexer/gpu/mod.rs) | Rust | -381 | -24 | -51 | -456 |
| [src/lexer/gpu/passes/apply\_block\_prefix\_downsweep.rs](/src/lexer/gpu/passes/apply_block_prefix_downsweep.rs) | Rust | -64 | 0 | -7 | -71 |
| [src/lexer/gpu/passes/boundary\_finalize\_and\_seed.rs](/src/lexer/gpu/passes/boundary_finalize_and_seed.rs) | Rust | 92 | 0 | 12 | 104 |
| [src/lexer/gpu/passes/build\_tokens.rs](/src/lexer/gpu/passes/build_tokens.rs) | Rust | -64 | 0 | -6 | -70 |
| [src/lexer/gpu/passes/compact\_boundaries\_all.rs](/src/lexer/gpu/passes/compact_boundaries_all.rs) | Rust | 4 | -3 | -1 | 0 |
| [src/lexer/gpu/passes/compact\_boundaries\_kept.rs](/src/lexer/gpu/passes/compact_boundaries_kept.rs) | Rust | 4 | -2 | -1 | 1 |
| [src/lexer/gpu/passes/dfa\_01\_scan\_inblock.rs](/src/lexer/gpu/passes/dfa_01_scan_inblock.rs) | Rust | 66 | 0 | 9 | 75 |
| [src/lexer/gpu/passes/dfa\_02\_scan\_block\_summaries.rs](/src/lexer/gpu/passes/dfa_02_scan_block_summaries.rs) | Rust | 192 | 3 | 28 | 223 |
| [src/lexer/gpu/passes/dfa\_03\_apply\_block\_prefix.rs](/src/lexer/gpu/passes/dfa_03_apply_block_prefix.rs) | Rust | 100 | 0 | 12 | 112 |
| [src/lexer/gpu/passes/finalize\_boundaries\_and\_seed.rs](/src/lexer/gpu/passes/finalize_boundaries_and_seed.rs) | Rust | -120 | 0 | -17 | -137 |
| [src/lexer/gpu/passes/mod.rs](/src/lexer/gpu/passes/mod.rs) | Rust | -123 | -17 | -12 | -152 |
| [src/lexer/gpu/passes/pair\_01\_sum\_inblock.rs](/src/lexer/gpu/passes/pair_01_sum_inblock.rs) | Rust | 66 | 0 | 7 | 73 |
| [src/lexer/gpu/passes/pair\_02\_scan\_block\_totals.rs](/src/lexer/gpu/passes/pair_02_scan_block_totals.rs) | Rust | 206 | 1 | 25 | 232 |
| [src/lexer/gpu/passes/pair\_03\_apply\_block\_prefix.rs](/src/lexer/gpu/passes/pair_03_apply_block_prefix.rs) | Rust | 104 | 0 | 13 | 117 |
| [src/lexer/gpu/passes/retag\_calls\_and\_arrays.rs](/src/lexer/gpu/passes/retag_calls_and_arrays.rs) | Rust | 4 | -6 | 0 | -2 |
| [src/lexer/gpu/passes/scan\_block\_summaries\_inclusive.rs](/src/lexer/gpu/passes/scan_block_summaries_inclusive.rs) | Rust | -154 | -3 | -20 | -177 |
| [src/lexer/gpu/passes/scan\_inblock\_inclusive\_pass.rs](/src/lexer/gpu/passes/scan_inblock_inclusive_pass.rs) | Rust | -69 | 0 | -8 | -77 |
| [src/lexer/gpu/passes/sum\_apply\_block\_prefix\_downsweep\_pairs.rs](/src/lexer/gpu/passes/sum_apply_block_prefix_downsweep_pairs.rs) | Rust | -52 | 0 | -7 | -59 |
| [src/lexer/gpu/passes/sum\_inblock\_pairs.rs](/src/lexer/gpu/passes/sum_inblock_pairs.rs) | Rust | -47 | -1 | -7 | -55 |
| [src/lexer/gpu/passes/sum\_scan\_block\_totals\_inclusive.rs](/src/lexer/gpu/passes/sum_scan_block_totals_inclusive.rs) | Rust | -145 | -2 | -19 | -166 |
| [src/lexer/gpu/passes/tokens\_build.rs](/src/lexer/gpu/passes/tokens_build.rs) | Rust | 68 | 0 | 6 | 74 |
| [src/lexer/gpu/timer.rs](/src/lexer/gpu/timer.rs) | Rust | -97 | -3 | -12 | -112 |
| [src/lexer/gpu/types.rs](/src/lexer/gpu/types.rs) | Rust | 25 | 1 | 6 | 32 |
| [src/lexer/gpu/util.rs](/src/lexer/gpu/util.rs) | Rust | 50 | 6 | 12 | 68 |
| [src/lexer/tables/tokens.rs](/src/lexer/tables/tokens.rs) | Rust | 1 | 0 | 0 | 1 |
| [src/lib.rs](/src/lib.rs) | Rust | 4 | 0 | 0 | 4 |
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
| [src/type\_checker/mod.rs](/src/type_checker/mod.rs) | Rust | 0 | 0 | 1 | 1 |
| [tests/size\_sweep.rs](/tests/size_sweep.rs) | Rust | 154 | 11 | 17 | 182 |

[Summary](results.md) / [Details](details.md) / [Diff Summary](diff.md) / Diff Details