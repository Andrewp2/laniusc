// The scoped type hash and equality walkers with their frames in the thread
// scratch table, for kernels that bind it (program evidence). Callers must
// have bound their slot with thread_scratch_begin. Local-array callers keep
// scoped_type_ref_hash and scoped_type_refs_equal_graphs, which expand the
// same walker bodies.
//
// INTERIM: this is still per-thread DFS state, only moved to global memory.
// The end state (P7) is program evidence on canonical type IDs with level
// rounds, where these walkers are deleted.
import type_checker.concrete_type_equality;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_hash;
import thread_scratch;

// Hash frames, 2 cells per depth: (ref, next), then (count, 0, 0, 0).
#define SCOPED_TYPE_HASH_WALK scoped_type_ref_hash_scratch
#define SCOPED_TYPE_HASH_FRAMES
#define SH_REF(d) scratch_cell(SCRATCH_SCOPED_HASH + (d) * 2u).xyz
#define SH_PUSH(d, r) scratch_set_cell(SCRATCH_SCOPED_HASH + (d) * 2u, uint4(r, INVALID))
#define SH_CLASSIFIED(d, r) scratch_set_cell(SCRATCH_SCOPED_HASH + (d) * 2u, uint4(r, 0u)); \
    scratch_set_cell(SCRATCH_SCOPED_HASH + (d) * 2u + 1u, uint4(0u, 0u, 0u, 0u))
#define SH_NEXT(d) scratch_word(SCRATCH_SCOPED_HASH + (d) * 2u, 3u)
#define SH_SET_NEXT(d, v) scratch_set_word(SCRATCH_SCOPED_HASH + (d) * 2u, 3u, v)
#define SH_COUNT(d) scratch_word(SCRATCH_SCOPED_HASH + (d) * 2u + 1u, 0u)
#define SH_SET_COUNT(d, v) scratch_set_word(SCRATCH_SCOPED_HASH + (d) * 2u + 1u, 0u, v)
#include "scoped_type_hash_walk.slang"
#undef SCOPED_TYPE_HASH_WALK
#undef SCOPED_TYPE_HASH_FRAMES
#undef SH_REF
#undef SH_PUSH
#undef SH_CLASSIFIED
#undef SH_NEXT
#undef SH_SET_NEXT
#undef SH_COUNT
#undef SH_SET_COUNT

[ForceInline]
uint scoped_type_equality_next_increment(uint depth)
{
    uint cell = SCRATCH_SCOPED_EQUALITY + depth * 2u + 1u;
    uint slot = scratch_word(cell, 2u);
    scratch_set_word(cell, 2u, slot + 1u);
    return slot;
}

// Equality frames, 2 cells per depth: the pair, then (context, next, count).
#define SCOPED_TYPE_EQUALITY_WALK scoped_type_refs_equal_graphs_scratch
#define SCOPED_TYPE_EQUALITY_FRAMES
#define SE_PAIR(d) scratch_cell(SCRATCH_SCOPED_EQUALITY + (d) * 2u)
#define SE_CONTEXT(d) scratch_cell(SCRATCH_SCOPED_EQUALITY + (d) * 2u + 1u).xy
#define SE_PUSH(d, p, c) scratch_set_cell(SCRATCH_SCOPED_EQUALITY + (d) * 2u, p); \
    scratch_set_cell(SCRATCH_SCOPED_EQUALITY + (d) * 2u + 1u, uint4(c, INVALID, 0u))
#define SE_CLASSIFIED(d, p, c) scratch_set_cell(SCRATCH_SCOPED_EQUALITY + (d) * 2u, p); \
    scratch_set_cell(SCRATCH_SCOPED_EQUALITY + (d) * 2u + 1u, uint4(c, 0u, 0u))
#define SE_NEXT(d) scratch_word(SCRATCH_SCOPED_EQUALITY + (d) * 2u + 1u, 2u)
#define SE_NEXT_INCREMENT(d) scoped_type_equality_next_increment(d)
#define SE_COUNT(d) scratch_word(SCRATCH_SCOPED_EQUALITY + (d) * 2u + 1u, 3u)
#define SE_SET_COUNT(d, v) scratch_set_word(SCRATCH_SCOPED_EQUALITY + (d) * 2u + 1u, 3u, v)
#include "scoped_type_equality_walk.slang"
#undef SCOPED_TYPE_EQUALITY_WALK
#undef SCOPED_TYPE_EQUALITY_FRAMES
#undef SE_PAIR
#undef SE_CONTEXT
#undef SE_PUSH
#undef SE_CLASSIFIED
#undef SE_NEXT
#undef SE_NEXT_INCREMENT
#undef SE_COUNT
#undef SE_SET_COUNT

// One graph namespace, as scoped_type_refs_equal.
public bool scoped_type_refs_equal_scratch<Graph : IParameterScopedTypeGraph>(
    uint left_tag, uint left_payload, uint left_context,
    uint right_tag, uint right_payload, uint right_context, uint type_capacity,
    uint token_capacity)
{
    return scoped_type_refs_equal_graphs_scratch<Graph, Graph>(
        left_tag, left_payload, left_context, right_tag, right_payload, right_context,
        type_capacity, type_capacity, token_capacity);
}
