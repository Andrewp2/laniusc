# Lexer

The lexer is the first GPU phase in the compiler. It turns one source string or
a source pack concatenated into one byte stream into compact token records,
records the source file that owns each token, and leaves resident GPU buffers
available for parser and backend phases that can avoid host readback.

Use this document when changing token kinds, lexer tables, source-pack lexing,
resident token lifetimes, or the token boundary between lexer and parser.

## Ownership

The lexer owns the byte-to-token contract. Its source is under
`crates/laniusc-compiler/src/lexer`, its shaders are under `shaders/lexer`, and
its generated token-id bridge is `shaders/generated_token_ids.slang`.

The lexer owns:

- loading compact DFA tables from `tables/lexer_tables.bin`
- converting those tables into the packed Rust buffers consumed by Slang
- uploading input bytes and source-pack file metadata
- managing resident lexer buffers and lexer bind-group cache invalidation
- recording the DFA, pair-scan, compaction, and token-build shader passes
- assigning `TokenKind` IDs to final kept tokens
- assigning `token_file_id` for source-pack consumers
- optional token and count readback for tests, demos, and diagnostics paths

The lexer does not own grammar-specific syntax structure. Contextual retags
that require parser context, such as call/group/index delimiters or declaration
roles, live in parser token-front-end passes even though their `TokenKind`
values are declared in the lexer token table. This split is intentional:
`TokenKind` is the shared numeric namespace, not proof that the lexer produced a
kind directly.

The lexer also does not own user-facing syntax diagnostics. It produces offsets,
lengths, token kinds, token counts, and file IDs. Parser and later compiler
layers turn those records into diagnostics.

## Public Entry Points

`GpuLexer::new` creates a lexer on the process-global GPU device.
`GpuLexer::new_with_device` creates one on an existing `GpuDevice`. Both load
the compact DFA table once and create all shader pass objects before any input
is lexed.

`lex(input)` is the simple readback path. It records the full lexer pipeline,
submits GPU work, optionally reads `token_count`, copies exactly the populated
`GpuToken` range back to the host, and decodes the rows into host `Token`
values. If `LANIUS_READBACK=0`, the GPU work still runs but this function
returns an empty vector rather than reading tokens.

`with_resident_tokens(input, consume)` records and submits lexer work, then
calls `consume` with `GpuBuffers` while the lexer's buffer guard is still held.
Use this when downstream work can consume resident GPU buffers directly after
the lexer submission.

`lex_source_pack(sources)` and `with_resident_source_pack_tokens(sources, ...)`
lex multiple source strings by concatenating their bytes into one input buffer.
The source-pack metadata buffers preserve file identity inside that single token
stream.

The `with_recorded_resident_*` entry points record lexer work and caller GPU
work into a shared command stream. Variants without `after_count` do not read
`token_count` before caller recording; downstream code must size from byte
capacity or another conservative bound.

The `after_count` variants intentionally split submission:

1. record and submit lexer work
2. copy and map `token_count`
3. record downstream GPU work using the exact token count

That boundary is a performance cost. Use it only when downstream dispatches or
buffers need the exact token count before recording.

The `releasing_lexer` variants drop the lexer's resident buffer allocation
before later phases allocate their own buffers. They exist for memory pressure,
not for compatibility. A caller that needs lexer buffers after release must use
the parser-input variant, which clones the precise `LaniusBuffer` handles needed
by the parser before clearing the lexer's guard.

## Input Preparation

Single-source lexing goes through `prepare_buffers_for_input`. Source-pack
lexing goes through `prepare_buffers_for_source_pack`. Both paths produce one
current byte stream and one set of resident buffers.

For a single source:

- `in_bytes` receives the source bytes.
- `source_file_count` is `1`.
- `source_file_start[0]` is `0`.
- `source_file_len[0]` is the byte length.

For a source pack:

- host code concatenates the source bytes in source order
- `source_file_start[i]` stores each file's start byte in the concatenated
  buffer
- `source_file_len[i]` stores each file's byte length
- byte length overflow is rejected before GPU work is recorded

Input bytes are padded to a word boundary for upload, but `LexParams.n` remains
the real byte length. Shaders must treat `n` as the semantic end of input.
Padding exists for buffer upload alignment only.

The driver resizes resident buffers when byte capacity, DFA block count, or
source-file capacity changes. Resizing clears the lexer bind-group cache because
cached bind groups reference old `wgpu::Buffer` handles. A change that replaces
or aliases any resident buffer must either preserve this invalidation rule or
prove cached bind groups cannot observe the old handle.

Zero-length input still allocates at least one element of capacity where the GPU
infrastructure requires non-empty buffers. Runtime sizes are still set from the
real byte length.

## Table Model

`tables/lexer_tables.bin` is the runtime table source. `GpuLexer::new_with_device`
embeds it with `include_bytes!`, parses it with
`load_compact_tables_from_bytes`, and stores the parsed table vectors on the
lexer instance.

The compact table format is:

| Field | Meaning |
| --- | --- |
| `LXDFA001` | 8-byte magic header |
| `u32 n_states` | DFA state count |
| `u32 reserved` | currently ignored |
| `u16 next_emit[256 * n_states]` | transition rows with high-bit emit flag |
| `u16 token_map[n_states]` | accepting-state token kind, `0xFFFF` for invalid |

The loader validates that every non-invalid `token_map` entry resolves through
`TokenKind::from_u32`. Invalid table entries fail at initialization rather than
leaking unknown token IDs into shaders.

The table becomes three GPU buffers:

- `next_emit`: two `u16` transition entries packed into each `u32`
- `next_u8`: byte-indexed next-state table, four states packed into each `u32`
- `token_map`: `u32` token kinds or `INVALID_TOKEN`

`next_emit` is used when a shader needs the emit flag and next state.
`next_u8` is used by local DFA summary construction where only next state is
needed and denser packing is faster.

`TokenKind` in `lexer::tables::tokens` is the Rust source of truth for numeric
token IDs. `shaders/generated_token_ids.slang` must match those discriminants.
The broader token, grammar terminal, generated-table, and shader-constant
contract is documented in
[Grammar and generated tables](grammar-and-tables.md).
Tests check:

- `TokenKind::from_u32` covers the contiguous valid range
- grammar terminals resolve through `TokenKind::from_name`
- generated Slang constants match Rust discriminants
- hard-coded shader token constants match generated constants
- compact table token-map entries reject invalid token IDs

The older table-building helpers remain for generation and tests. Runtime GPU
lexing reads only the compact binary.

## Token Record Contract

The final GPU token record is:

```rust
pub struct GpuToken {
    pub kind: u32,
    pub start: u32,
    pub len: u32,
}
```

Host readback decodes this into:

```rust
pub struct Token {
    pub kind: TokenKind,
    pub start: usize,
    pub len: usize,
}
```

`start` and `len` are byte offsets in the concatenated input stream, not UTF-8
scalar indices and not source-file-relative positions. Source-pack consumers map
global byte offsets back to file-relative positions using source-pack metadata
and `token_file_id`.

The final token stream contains kept tokens only. Whitespace, line comments,
block comments, and `u32::MAX` are configured as skip kinds by the driver. The
DFA can still recognize skipped tokens because skipped boundaries are needed to
compute starts for later kept tokens.

`token_count[0]` is the number of kept tokens written to `tokens_out` and
`token_file_id`. It must never exceed the byte length `n`; count-boundary entry
points check this before recording downstream work.

## Pipeline

The pass order is defined by `lexer::passes::record_all_passes`:

1. `source_file_boundaries` writes per-byte start/end flags from source-file
   metadata.
2. `dfa_01_scan_inblock` scans bytes inside 256-byte blocks and writes local
   DFA summary functions.
3. `dfa_02_scan_block_summaries` prefix-scans per-block DFA summary functions.
4. `dfa_03_apply_block_prefix` applies scanned block prefixes, emits boundary
   flags, and writes packed raw token kinds.
5. `pair_01_sum_inblock` counts all and kept token boundaries inside each
   block.
6. `pair_02_scan_block_totals` prefix-scans per-block boundary totals.
7. `pair_03_apply_block_prefix` produces compact ranks for all boundaries and
   kept boundaries.
8. `compact_boundaries_kept` writes kept token end positions, token kinds, all
   boundary indexes, and `token_count`.
9. `compact_boundaries_all` writes all boundary end positions into reused
   scratch space.
10. `tokens_build` writes final `GpuToken` rows and `token_file_id`.

When batching is enabled, no timer/debug/validation scopes are active, and a
bind-group cache is available, the driver records compatible passes into three
compute-pass batches:

- source-file boundaries plus local DFA scan
- DFA prefix application plus local pair count
- pair prefix application, kept compaction, all compaction, and token build

The scanned prefix passes remain separate because they operate over block
summary streams. The driver removes cached bind groups for passes whose bound
buffer roles can change through ping/pong reuse.

Kept compaction runs before all-boundary compaction. That order is part of the
buffer-reuse contract: `tokens_build` needs all-boundary end positions after the
kept stream has already captured kept token kinds and all-boundary indexes.

## Source File Identity

Source packs are lexed as one byte stream, but tokens must still be attributable
to their source file. The lexer maintains this through two mechanisms.

First, `source_file_boundaries` writes `source_file_start_flags[start] = 1` and
`source_file_end_flags[end] = 1` for each file. DFA passes use the start flags
to reset DFA state at file boundaries and use end flags to force an EOF-like
token boundary at the end of each file.

Second, `tokens_build` maps each final token end position back to a source file.
It performs a bounded binary search over `source_file_start`, checks the chosen
file's `[start, end)` byte range, and writes the file index into
`token_file_id[k]`. If the token end does not belong to a file, the shader
returns `INVALID`.

Token starts are clamped to the owning file start before the final record is
written. This prevents a token after a source-pack boundary from inheriting an
end position from the previous file.

The binary search has a fixed 32-iteration guard, which is enough for a `u32`
source-file count. This is not a user-facing language limit in practice; the
host metadata count is `u32`, and each search step halves the range.

## Keyword And Local Retags

The lexer-level `tokens_build` pass performs retags that can be decided from the
token lexeme and adjacent lexer tokens without parser context:

- identifiers that match reserved words become keyword token kinds
- floats ending in `.` can be split so range tokens parse correctly
- adjacent `..` and `..=` forms are corrected from dot/assign tokens

These retags are still lexer-owned because they rely only on bytes, adjacency,
and same-file checks. Parser-front-end retags own grammar-position facts such as
parameter delimiters, argument commas, type-argument delimiters, and declaration
identifier roles.

When adding a retag, place it in the earliest phase that owns all required
information. Do not move parser-context retags into `tokens_build` to save a
later pass; that would make source syntax decisions depend on local byte
heuristics.

## Buffer Groups

`GpuBuffers` is the resident state carrier for the lexer. The fields have stable
roles:

| Group | Buffers |
| --- | --- |
| Runtime sizes | `n`, `nb_dfa`, `nb_sum` |
| Parameters/input | `params`, `in_bytes` |
| DFA tables | `next_emit`, `next_u8`, `token_map` |
| DFA prefix scan | `dfa_02_ping`, `dfa_02_pong`, `dfa_chunk_summaries` |
| Boundary facts | `tok_types`, `flags_packed`, `s_all_final`, `s_keep_final` |
| Kept compaction | `end_positions`, `types_compact`, `all_index_compact`, `token_count` |
| Output | `tokens_out`, `token_file_id` |
| Source files | `source_file_count`, `source_file_start`, `source_file_len`, `source_file_start_flags`, `source_file_end_flags` |

The pair-scan phase deliberately reuses the DFA ping/pong buffers. Treat those
buffers as scratch owned by the current pass sequence, not durable output after
lexing.

The public resident output for parser-like consumers is much smaller than
`GpuBuffers`. `ResidentLexerParserInputs` clones only:

- `source_len`
- `in_bytes`
- `tokens_out`
- `token_count`
- `token_file_id`

That narrow wrapper is the safe handoff when the lexer allocation itself is
released before parser work is recorded.

## Resident Lifetimes

`GpuLexer` keeps its resident buffers in a mutex-protected `Option<GpuBuffers>`.
Normal resident entry points hold the guard while downstream code inspects
buffers. Releasing variants set the option to `None`, drop the guard, clear the
bind-group cache, and then record or consume downstream state through cloned
handles.

The important lifetime rule is: a downstream phase may keep using a buffer only
if it owns a cloned `LaniusBuffer` handle that was captured before the lexer
guard was released. Borrowing `GpuBuffers` and then using it after a releasing
entry point has returned is invalid by construction and should not be worked
around with aliases.

Releasing the lexer buffers is useful when parser, type-checker, or codegen
needs memory proportional to token or source size. It is not a semantic change
to lexing and should not change token IDs, offsets, or file IDs.

## Readback, Timers, And Debug Paths

The hot compiler path should keep tokens resident. Host readback is available
for tests, demos, diagnostics, and explicit command paths.

Readback behavior:

- `lex` obeys `LANIUS_READBACK`; when disabled it returns `Vec::new()` after GPU
  submission.
- `lex_source_pack` reads resident source-pack tokens by first reading
  `token_count`, then copying exactly `token_count * sizeof(GpuToken)` bytes.
- `after_count` APIs always read `token_count` because exact count is their
  purpose.

Timing behavior:

- `LANIUS_GPU_TIMING` enables lexer timing in the direct readback path.
- `LANIUS_GPU_COMPILE_TIMING` enables timing across recorded compile-style
  entry points.
- GPU tracing can also enable timer collection.
- Very small timer deltas are elided from normal print output.

Debug behavior:

- `LANIUS_VALIDATION_SCOPES` disables pass batching through the shared GPU pass
  infrastructure.
- The `gpu-debug` feature can attach lexer debug output to pass recording.
- The `graphics_debugger` feature wraps lexing calls in GPU debugger capture.

Do not add unconditional readback for observability. Prefer generated reference
tables, host-side command labels, validation scopes, timers, or opt-in debug
capture.

## Diagnostics And Failures

Hard lexer failures are currently host errors:

- compact table parse failure
- invalid token-map entry in the compact table
- GPU initialization or shader-pass construction failure
- source-pack file count or byte-length overflow
- buffer sizing or mapping failure
- invalid token bytes during host readback
- `token_count > n` after a count-boundary readback

Lexical invalidity is not currently exposed as a stable public lexer diagnostic
code. Invalid or unexpected token structure is normally surfaced by parser or
later diagnostics.

Even without public lexer diagnostics, the lexer controls the source locations
that later diagnostics rely on. When changing token starts, lengths,
source-pack concatenation, or `token_file_id`, verify that parser diagnostics
still point at the source file and byte span a user would inspect.

## Performance Rules

The lexer is designed to avoid per-token host work on the compile path.

Keep these rules intact:

- Upload source bytes and source-file metadata once per lexing call.
- Reuse resident buffers when capacity still matches.
- Clear cached bind groups only when buffer handles or buffer-role bindings can
  change.
- Keep token readback behind explicit readback entry points.
- Prefer resident continuation over `after_count` when downstream work can use
  byte-capacity bounds.
- Preserve compute-pass batching when debug, timing, and validation scopes are
  off.
- Avoid shader loops proportional to token count inside per-byte work.

Existing bounded shader loops are intentionally small or logarithmic:

- DFA chunk replay is bounded by the 256-byte block and `CHUNK_COUNT`.
- Source-file lookup in `tokens_build` is bounded by 32 binary-search steps.
- Keyword retags compare fixed keyword lengths.

If a future change adds a loop whose bound comes from user source size, document
the bound here and add performance evidence in `testing.md` or the relevant
benchmark notes.

## Changing Token Kinds

When adding or changing a token kind:

1. Update `TokenKind` in `lexer::tables::tokens`.
2. Regenerate `shaders/generated_token_ids.slang`.
3. Update lexer table generation so `tables/lexer_tables.bin` recognizes the
   new byte pattern if the token is lexer-produced.
4. Update parser token-front-end passes if the token is contextual or
   grammar-position dependent.
5. Update Slang token constants only through the generated-token-id path or a
   tested hard-coded mirror.
6. Run token ID tests and a focused lexer comparison.
7. Regenerate `docs/compiler/generated/reference.md` if public items, shader
   load sites, status codes, large structs, or Rustdoc coverage changed.

Adding a `TokenKind` does not by itself make the lexer produce that kind.
Confirm whether the DFA, keyword retag, token-build adjacency logic, or parser
front end is the actual producer.

## Changing Source-Pack Lexing

When changing source-pack behavior:

1. Keep token `start` and `len` as global byte offsets unless all downstream
   source-pack diagnostics are changed together.
2. Preserve DFA reset at source-file starts.
3. Preserve EOF-like boundary emission at source-file ends.
4. Keep `token_file_id` aligned with final kept-token order.
5. Verify tokens do not merge across adjacent files.
6. Verify diagnostics map global byte spans back to the expected source file.

The source-pack path is deliberately not a compatibility alias around
single-file lexing. It is the same lexer pipeline with source metadata uploaded
before recording.

## Changing Pass Order Or Buffers

When changing pass order, buffer reuse, or bind-group behavior:

1. Update `record_all_passes` and the batched and non-batched sequences
   together.
2. Check whether a cached bind group references a buffer whose role changed.
3. Update the buffer-role table in this document.
4. Update `gpu-passes.md` if shader artifact loading, reflection, bind layouts,
   or dispatch behavior changed.
5. Update `data-flow.md` if the resident boundary between compiler phases
   changed.
6. Run focused lexer tests and the generated reference check.

The most common mistake is treating a scratch buffer as phase output. If a
later pass needs a durable value, add a named buffer or prove the scratch buffer
is not reused before that value is consumed.

## Common Mistakes

- Treating `TokenKind` as proof of lexer ownership. Parser retags share the
  enum.
- Treating token offsets as file-relative in source-pack paths. They are global
  byte offsets.
- Adding host token iteration to the compile path. Prefer resident buffers.
- Using `after_count` when byte capacity is enough.
- Forgetting to clear the bind-group cache after resident buffers are replaced.
- Reordering kept and all-boundary compaction without checking
  `all_index_compact`.
- Adding a token kind without regenerating Slang token IDs.
- Updating shader constants by hand without keeping the generated mirror tested.
- Allowing tokens to span source-pack file boundaries.
- Reading padded bytes by using allocation capacity instead of `LexParams.n`.

## Evidence To Update

After lexer changes, update or run the evidence that matches the edit:

| Change | Evidence |
| --- | --- |
| Token IDs or generated constants | token ID tests in `lexer::tables::tokens`; regenerated `shaders/generated_token_ids.slang` |
| Compact table format | `lexer::tables::compact` tests; regenerated `tables/lexer_tables.bin` |
| DFA behavior | focused GPU/CPU lexer comparison |
| Source-pack lexing | source-pack lexer/parser diagnostic tests |
| Resident handoff | parser or compile path that consumes resident lexer buffers |
| Count-boundary APIs | test or benchmark that needs exact token count before recording |
| Buffer fields or large structs | `tools/compiler_inventory.py --check docs/compiler/generated/reference.md` |
| Shader pass order | lexer tests plus `gpu-passes.md` review |
| Performance-sensitive shader loop | focused benchmark or shader-loop audit note |

If a change affects generated-reference inputs, regenerate
`docs/compiler/generated/reference.md` and run the `--check` command before
considering the docs current.
