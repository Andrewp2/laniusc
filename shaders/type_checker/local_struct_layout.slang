import native_value_layout;
// Read the checked, fixed local struct layout at a dependency call boundary.
// An unknown, symbolic, overflowing, or cyclic layout is never a word-count
// estimate. All inputs remain resident; no host type reconstruction is needed.
import hir_records;

// Call checking reads immutable type rows; dependency projection reads the
// same rows from its writable resource. Both provide identical checked data.
public interface ILocalStructTypeRefs
{
    static uint tag(uint token);
    static uint payload(uint token);
}

public uint local_struct_for_scalar(uint scalar, uint hir_count, uint token_capacity,
    StructuredBuffer<uint> declaration_hir, StructuredBuffer<HirCore> cores)
{
    if (scalar < 4096u || scalar - 4096u >= token_capacity) return 0xffffffffu;
    uint root = declaration_hir[scalar - 4096u];
    // Legacy enum and struct scalar codes overlap in large source packs.
    // An ambiguous numeric code cannot establish nominal identity.
    if (scalar >= 6144u && scalar - 6144u < token_capacity)
    {
        uint alternative = declaration_hir[scalar - 6144u];
        if (alternative < hir_count && cores[alternative].kind == 26u)
            return 0xffffffffu;
    }
    return root < hir_count && cores[root].kind == 27u ? root : 0xffffffffu;
}

public uint first_local_struct_field(uint token, uint field_count,
    StructuredBuffer<HirField> fields)
{
    uint lo = 0u;
    uint hi = field_count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (fields[mid].name_token < token) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

public uint fixed_local_struct_words<TypeRefs : ILocalStructTypeRefs>(uint root, uint hir_count, uint token_capacity,
    uint field_count, StructuredBuffer<HirCore> cores,
    StructuredBuffer<HirPayload> payloads, StructuredBuffer<HirField> fields,
    StructuredBuffer<uint> declaration_hir)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    if (root >= hir_count || cores[root].kind != 27u) return INVALID;
    uint declarations[DEPTH_LIMIT];
    uint first[DEPTH_LIMIT];
    uint next[DEPTH_LIMIT];
    uint totals[DEPTH_LIMIT];
    uint depth = 0u;
    declarations[0u] = root;
    first[0u] = first_local_struct_field(cores[root].token_start, field_count, fields);
    next[0u] = first[0u];
    totals[0u] = 0u;
    for (;;)
    {
        uint current = declarations[depth];
        uint row = next[depth];
        if (row >= field_count || fields[row].name_token >= cores[current].token_end)
        {
            uint words = totals[depth];
            if (depth == 0u) return words;
            depth--;
            if (totals[depth] >= INVALID - words) return INVALID;
            totals[depth] += words;
            continue;
        }
        HirField field = fields[row];
        next[depth]++;
        if (field.owner != current || field.ordinal != row - first[depth] ||
            field.value >= hir_count || cores[field.value].kind != 5u)
            return INVALID;
        uint type_node = field.value;
        // Fixed-array fields do not yet have a consistent native inline-copy
        // representation. Reject them rather than publish a plausible width.
        // A slice contains a descriptor and does not copy its elements.
        if (payloads[type_node].a == 2u) return INVALID;
        uint width = INVALID;
        uint child = INVALID;
        if (payloads[type_node].a == 3u) width = NATIVE_SLICE_WORDS;
        else if (payloads[type_node].a == 4u) width = 1u;
        else
        {
            uint token = cores[type_node].token_start;
            if (token >= token_capacity || TypeRefs.tag(token) != 1u) return INVALID;
            uint scalar = TypeRefs.payload(token);
            if (scalar != 0u && scalar < 128u) width = scalar == 7u ? 2u : 1u;
            else child = local_struct_for_scalar(scalar, hir_count, token_capacity,
                declaration_hir, cores);
        }
        if (child == INVALID)
        {
            if (width == INVALID || totals[depth] >= INVALID - width) return INVALID;
            totals[depth] += width;
            continue;
        }
        if (depth + 1u >= DEPTH_LIMIT) return INVALID;
        for (uint ancestor = 0u; ancestor <= depth; ancestor++)
            if (declarations[ancestor] == child) return INVALID;
        depth++;
        declarations[depth] = child;
        first[depth] = first_local_struct_field(cores[child].token_start, field_count, fields);
        next[depth] = first[depth];
        totals[depth] = 0u;
    }
}
