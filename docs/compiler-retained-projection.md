# Retained instance projection

Retained projection turns closed instances of retained generic templates
([program retention](compiler-program-retention.md)) into native x86 object
code. It substitutes each instance's row, signature and use terms with the
[retained substitution](compiler-retained-substitution.md) engine, realizes
layouts on the GPU, projects the rows into the existing lowering inputs and
runs the existing lowering pipeline. It never runs a frontend, never lexes or
parses instance text and never calls source replay. General compilation does
not use it yet.

This document is the boundary contract. Implementation status and test
receipts are at the end.

## Producer contract

Discovery (or a test producer) writes three GPU buffers and owns them. The
host never writes a row of them.

### Instance records, `pj_instances`

Two uint4 per instance, indexed by **rank**. Ranks are dense, `0..count`,
and are the final deterministic order (declaration keys, then structural
environment order). Rank is the native instance symbol:
`(NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, rank)`
(`codegen/x86/finalize.rs`).

| Word | Contents |
| --- | --- |
| q0 | `(callable DeclId, closed ENV TermId, generation, flags)` |
| q1 | `(first route row, route count, 0, 0)` |

- The instance identity is `(DeclId, ENV)`. The ENV is a stored, closed,
  normalized `ENV` term whose owner word is the DeclId, the form the
  substitution engine accepts and publishes. Two ranks with one identity are
  rejected (`DUPLICATE`).
- `generation` is the store build generation (`rt_counts[78]`).
- `flags`: bit 0 `ENTRY` marks the program entry instance. This exists for
  tests whose program root is an instance. Production roots are original
  objects whose provisional use symbols the GPU finalizer rewrites.
- The callable must be a committed, complete `FREE_FN` with a body segment.

### Routes, `pj_routes`

One uint4 per `(instance, use)`, at `q1.x + use ordinal`. The use ordinal is
the use's index in the callee's use block (`rt_dir` d2.w .. + d3.x), which is
also the body row's `r3.y`. `q1.y` must equal the block's use count.

`(library, namespace or unit, local, generation)`, the finalizer's route-row
format:

- an instance: `(NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, rank, gen)`;
- an ordinary `DeclNative` callee: `(library, unit, local symbol, gen)`,
  which must equal the callee's declaration key words `(x, y, w)`;
- a use that is not a call (record literal, constructor):
  `(0xffffffff, 0, 0, gen)`.

Projection validates every route of a call before publishing: generation,
range, and identity. An instance route must name a rank whose DeclId is the
use's callee and whose ENV equals the use's ENV substituted under the
caller's ENV (exact TermId). Each argument's substituted type must equal the
target's substituted parameter type, and the call row's type must equal the
target's result type. Exact closed types imply equal argument and result
ABI. Projection never chooses a target or a fallback. Bound-member uses need
a route from the trait solver's evidence; projection checks the route the
same way and does not select an implementation.

### Readiness, `pj_readiness`

One uint4 `(generation, flags, instance count, route count)`. Flags bit 0
routes published, bit 1 ABI certified by the producer. Projection requires
bit 0, checks the generation and the counts against the buffers, and
performs its own signature check (above) regardless of bit 1.

## Stages

All semantic work is GPU lane work. The host allocates, records, submits and
reads status words and the finished objects.

| Step | Lanes | Work |
| --- | --- | --- |
| 00 plan | one per instance | validate the record, read the body sizes, count requests |
| 01 scan | uint scans | instance bases of rows, tokens, side tables and requests |
| 02 requests | one per request | substitution requests: result, parameters, body rows, then use environment, result, matched receiver and receiver parameter |
| substitution | engine | closed, normalized terms; request capacity is the producer rerun |
| 03 layout | one per store term, per height | native words and field offsets of closed types |
| 04 batch plan | 1 | batch totals and capacity demand |
| 05 rows | one per batch row | HIR rows and semantic columns |
| 06 side | one per batch side row | call arguments, fields, parameters, array elements |
| 07 tree | one per batch row | expression parent and root, nearest loop, control depth |
| 08 check | one per batch row | literal, operator and destination rules; routes and signatures |
| 09 finish | 1 | lowering counts and the batch status |
| lowering | existing pipeline | semantic LIR, optimization, x86 object |

A lowering batch is a range of ranks. Instances keep their rows contiguous
in rank order behind one root row. Every call, also inside one batch, is a
native symbol call to the route's identity, so a call names the same symbol
in every batch.
