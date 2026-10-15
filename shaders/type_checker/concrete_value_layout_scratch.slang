// The concrete value layout walker with its frames in the thread scratch
// table, for kernels that bind it (program evidence native layout). Callers
// must have bound their slot with thread_scratch_begin. Local-array callers
// keep concrete_value_words, which expands the same walker body.
//
// INTERIM: this is still per-thread DFS state, only moved to global memory.
// The end state (P7) is program evidence on canonical type IDs with level
// rounds, where this walker is deleted.
import type_checker.concrete_value_layout;
import thread_scratch;

[ForceInline]
uint concrete_value_words_cell(uint depth)
{ return SCRATCH_VALUE_LAYOUT + depth * 2u; }

[ForceInline]
uint concrete_value_words_next_ordinal(uint depth)
{
    uint cell = concrete_value_words_cell(depth) + 1u;
    uint ordinal = scratch_word(cell, 0u);
    scratch_set_word(cell, 0u, ordinal + 1u);
    return ordinal;
}

[ForceInline]
void concrete_value_words_next_group(uint depth, uint overhead)
{
    uint cell = concrete_value_words_cell(depth);
    scratch_set_word(cell, 3u, scratch_word(cell, 3u) + 1u);
    scratch_set_word(cell + 1u, 0u, 0u);
    scratch_set_word(cell + 1u, 1u, overhead);
}

// Frames, 2 cells per depth: (ref, groups, group), then
// (ordinal, totals, maxima, 0).
#define CONCRETE_VALUE_WORDS_WALK concrete_value_words_scratch
#define CONCRETE_VALUE_WORDS_FRAMES
#define VL_REF(d) scratch_cell(concrete_value_words_cell(d)).xy
#define VL_GROUPS(d) scratch_word(concrete_value_words_cell(d), 2u)
#define VL_GROUP(d) scratch_word(concrete_value_words_cell(d), 3u)
#define VL_ORDINAL(d) scratch_word(concrete_value_words_cell(d) + 1u, 0u)
#define VL_TOTALS(d) scratch_word(concrete_value_words_cell(d) + 1u, 1u)
#define VL_MAXIMA(d) scratch_word(concrete_value_words_cell(d) + 1u, 2u)
#define VL_SET_GROUPS(d, v) scratch_set_word(concrete_value_words_cell(d), 2u, v)
#define VL_SET_MAXIMA(d, v) scratch_set_word(concrete_value_words_cell(d) + 1u, 2u, v)
#define VL_ADD_TOTALS(d, v) scratch_set_word(concrete_value_words_cell(d) + 1u, 1u, VL_TOTALS(d) + (v))
#define VL_PUSH(d, r) scratch_set_cell(concrete_value_words_cell(d), uint4(r, INVALID, 0u))
#define VL_OPENED(d, o) scratch_set_word(concrete_value_words_cell(d), 3u, 0u); \
    scratch_set_cell(concrete_value_words_cell(d) + 1u, uint4(0u, o, 0u, 0u))
#define VL_NEXT_GROUP(d, o) concrete_value_words_next_group(d, o)
#define VL_ORDINAL_INCREMENT(d) concrete_value_words_next_ordinal(d)
#include "concrete_value_layout_walk.slang"
#undef CONCRETE_VALUE_WORDS_WALK
#undef CONCRETE_VALUE_WORDS_FRAMES
#undef VL_REF
#undef VL_GROUPS
#undef VL_GROUP
#undef VL_ORDINAL
#undef VL_TOTALS
#undef VL_MAXIMA
#undef VL_SET_GROUPS
#undef VL_SET_MAXIMA
#undef VL_ADD_TOTALS
#undef VL_PUSH
#undef VL_OPENED
#undef VL_NEXT_GROUP
#undef VL_ORDINAL_INCREMENT
