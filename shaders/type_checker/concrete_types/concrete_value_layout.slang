// Evaluate a concrete value layout from checked payload references. Each
// group is a record's fields or one enum variant. Groups sum their payload
// widths; the value uses the largest group. Descriptors are terminal values.
public interface IConcreteValueLayout
{
    // INVALID means the node needs expansion or has no supported layout.
    // Zero is a complete leaf with no native payload words.
    static uint leaf_words(uint tag, uint payload);
    static uint group_count(uint tag, uint payload);
    static uint overhead(uint tag, uint payload);
    static uint repetitions(uint tag, uint payload);
    // INVALID marks a row belonging to a different declaration.
    static uint payload_count(uint tag, uint payload, uint group);
    static bool payload_ref(uint tag, uint payload, uint group, uint ordinal,
        out uint child_tag, out uint child_payload);
}

// Local frame storage. The scratch expansion is concrete_value_words_scratch.
#define CONCRETE_VALUE_WORDS_WALK concrete_value_words
#define CONCRETE_VALUE_WORDS_FRAMES uint2 refs[DEPTH_LIMIT]; uint group[DEPTH_LIMIT]; \
    uint groups[DEPTH_LIMIT]; uint ordinal[DEPTH_LIMIT]; uint totals[DEPTH_LIMIT]; uint maxima[DEPTH_LIMIT];
#define VL_REF(d) refs[d]
#define VL_GROUPS(d) groups[d]
#define VL_GROUP(d) group[d]
#define VL_ORDINAL(d) ordinal[d]
#define VL_TOTALS(d) totals[d]
#define VL_MAXIMA(d) maxima[d]
#define VL_SET_GROUPS(d, v) groups[d] = v
#define VL_SET_MAXIMA(d, v) maxima[d] = v
#define VL_ADD_TOTALS(d, v) totals[d] += v
#define VL_PUSH(d, r) refs[d] = r; groups[d] = INVALID
#define VL_OPENED(d, o) group[d] = 0u; ordinal[d] = 0u; totals[d] = o; maxima[d] = 0u
#define VL_NEXT_GROUP(d, o) group[d]++; ordinal[d] = 0u; totals[d] = o
#define VL_ORDINAL_INCREMENT(d) ordinal[d]++
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
