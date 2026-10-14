# Canonical type IDs (design, 2026-10-13)

## Problem

Checked types are stored as *instance rows*: one row per type-expression
occurrence in source (keyed by token), plus private rows allocated past
source capacity by materialization and body replay. Rows are not
deduplicated, and a row's arguments may be declaration-side parameters that
only mean something under a *context* (an environment instance). So type
identity is decided by walking whole type graphs:

- `scoped_type_refs_equal` / `scoped_type_ref_hash` walk two graphs with
  per-thread stacks of 64 entries (and nested constant walkers);
- `instance_scoped_reference` re-interns a substituted type at every use
  site: hash the whole substituted tree, then run full scoped equality
  against each bucket candidate;
- materialization, expansion (`03e1`), closure checks and native layout
  (`01c`) are further stack walkers that call the ones above.

Measured consequences on the laptop (RTX 3070, NVIDIA 595.99):

- 167 of 850 shaders declare per-thread local arrays, up to ~30 KB per
  thread, which spill;
- the driver inlines everything, so these shaders take minutes to create
  (`03e1` did not finish in 15 min fully inlined; `01c` takes 121 s);
- with helpers kept out of line (`DontInline`), dispatches hang depending on
  which trivial leaf helpers are marked and on the input. There is no
  inlining policy that is both fast to compile and correct.

## Idea: hash-consing

Give every distinct type exactly one **canonical ID** (a `uint`), and store
each canonical type as a flat record whose children are canonical IDs:

```
ct_kind[id]    scalar | param | named | array | slice | ref
ct_head[id]    scalar code | parameter token | declaration token
ct_extern[id]  (library, unit, local) for imported declarations
ct_len[id]     canonical constant ID (arrays only)
ct_arity[id], ct_arg[ct_arg_base[id] + i]   canonical child IDs
ct_height[id]  1 + max child height
```

Because children are already canonical, identity is `==` on IDs, and the
hash of a record is computed from O(arity) words. Nothing walks a tree.
Declaration-side types are canonical too: their parameter leaves are
`param` records keyed by the parameter's declaration token, so `T` in two
different scopes never collides.

Constants (array lengths, constant generic arguments) get canonical IDs the
same way: concrete values by `(scalar, lo, hi)`, bare parameters by token,
projections as records over child constant IDs.

## Interning without locks or spinning

Rows are interned one *height level* at a time, in rounds. A row is
*ready* when all its children have canonical IDs. Each round has four
dispatches, each doing O(arity) work per thread with no local arrays:

1. **propose**: every ready row writes its key (the flat record) to a
   candidate buffer, and computes its hash;
2. **claim**: probe an open-addressing table `ct_slot[]`. An empty slot is
   claimed by CAS-ing in `CANDIDATE | row`. An occupied slot is compared
   by key, either against a published record or against the occupying
   candidate's key, which is visible because it was written in dispatch 1.
   Equal means "map to the occupant"; otherwise probe on;
3. **publish**: each claimant allocates an ID, writes the record, and
   replaces its slot value with the ID;
4. **resolve**: rows that matched another candidate copy its ID.

Nothing ever waits for another invocation, so this is safe without
forward-progress guarantees. ID numbering depends on atomic order;
semantics do not.

The number of rounds is the maximum type height (the existing walkers
already cap depth at 64). Termination uses a changed-count readback, the
same way call inference does today.

## Substitution as a memo table

`subst(env, t)` is the canonical ID of term `t` with the parameters of
environment `env` (a canonical `named` application, or a generic function
instance) replaced by its arguments. It is computed in two sweeps over a
memo table keyed by `(env, t)`:

- **expand** (top-down, by depth): a request for `(env, t)` requests
  `(env, child)` for each child of `t` that contains parameters
  (`ct_closed` tracks this, so closed subterms map to themselves);
- **intern** (bottom-up, by height): build the substituted record from the
  children's results and intern it as above.

Field types of a nominal application are `subst(C, field_decl_type)`.
Monomorphization closure (today's `03e1` expansion) is the fixpoint
"request every field of every new closed nominal ID" until no new IDs
appear.

## Native layout by levels

`words(id)`: scalars are 1 word (`str` is 2), slices are
`NATIVE_SLICE_WORDS`, refs are 1, and arrays are `count * words(elem)`.
Structs are the sum of their substituted fields; enums are the
tag/overhead plus the maximum group sum. Each round, every ID whose
dependencies all have widths computes its own. That replaces `01c`'s walker
with one O(fields) thread per ID per round.

## Migration plan (incremental, measured)

Each phase keeps the generics matrix (`tools/generics_matrix.py`) passing.
Each records local-array bytes (`target/claude-work/local_arrays.py`) and
pipeline creation times.

0. **Canonicalize existing rows.** Add the canonical tables and
   `row_canon[row]` for source, seed and generated rows, plus a debug
   validation pass that checks `row_canon` equality against
   `scoped_type_refs_equal` on the fixture corpus. Rows with unsupported
   shapes get `CANON_UNKNOWN`, and consumers fall back to the old path for
   those.
1. **Layout.** Replace `01c_generic_native_words` with a lookup of
   level-computed widths (needs field substitution, phase 2's machinery,
   restricted to fields).
2. **Substitution and closure.** Replace `03e1` expansion and
   `instance_scoped_reference` with the memo table.
3. **Equality and hash consumers.** Replace `scoped_type_refs_equal` and
   `scoped_type_ref_hash` call sites (38 and 17 shaders) with ID
   comparisons, then delete the walkers and their local arrays.
4. **Constants.** Move constant identity (`inspect_constant_reference`,
   `concrete_value_words` and related) onto canonical constant IDs.

Non-goals for now: replacing body replay, or the type checker's inference
rounds.
