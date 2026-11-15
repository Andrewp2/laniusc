// Projection step 3: closed-type layouts. One lane per TermId of the
// store's term table; the host records PJ_LAYOUT_ROUNDS rounds after the
// initializing step 3a. A round lays out each closed
// NAMED struct term whose field types all have layouts: a field's declared
// term is closed, or a type-parameter leaf of the struct's own binder,
// which is the term's operand. Each round therefore completes one more
// level of struct nesting. The lowering's type-instance tables, indexed by
// TermId, receive every laid-out term as an imported struct with its
// complete native width.
//
// Unsupported here, and left without a layout (a use is a PJ_E_LAYOUT or
// PJ_E_TYPE error with its location): enums, arrays, slices, references,
// constant operands and a field whose declared type is a compound term over
// the struct's parameters (it would need its own substitution).
import type_checker.retention.projection.pj_types;

static const uint DIR_STRUCT = 5u;

// The closed field type of struct term `t` for a declared field term, or
// RT_INVALID.
uint field_type(uint t, uint binder, uint types, uint declared)
{
    if (rt_term_closed(declared)) return declared;
    if (!rt_is_param_leaf(declared)) return RT_INVALID;
    uint param = rt_leaf_param(declared);
    for (uint j = 0u; j < types; j++)
        if (rt_binders[binder + j] == param) return rt_term_arg(t, j);
    return RT_INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint t = pj_lane(dtid);
    uint terms = min(rt_counts[RT_A_TERMS], rt_capacity(RT_A_TERMS));
    if (t < RT_FIRST_TERM || t >= min(terms, pj_type_rows())) return;
    if (pj_layout[t].x != RT_INVALID) return;
    if (rt_term_kind(t) != RT_KIND_NAMED || !rt_term_closed(t)) return;
    uint3 words = rt_term_words(t);
    if (words.y != 0u) return;
    uint entry = pj_dir_entry(words.x);
    if (entry == RT_INVALID) return;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS + 0u];
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    uint4 d3 = rt_dir[entry * RT_DIR_WORDS + 3u];
    if (d0.y != DIR_STRUCT || d0.w != RT_DIR_COMMITTED || d3.w != 0u) return;
    uint types = d1.y & 0xffffu;
    if ((d1.y >> 16u) != 0u || rt_term_arity(t) != types) return;
    uint fields = 0u;
    uint total = 0u;
    for (uint k = 0u; k < d2.z; k++)
    {
        uint4 record = rt_schema[d2.y + k];
        if ((record.y & 0xffu) != RT_SCHEMA_FIELD) continue;
        uint field = field_type(t, d1.x, types, record.w);
        uint w = pj_words(field);
        if (w == RT_INVALID) return;
        total += w;
        fields++;
    }
    if (fields != d1.w || total == 0u) return;
    pj_layout[t] = uint4(total, 1u, fields, 0u);
    uint4 key = rt_decl_key[words.x];
    ob_ti_kind[t] = 1u;
    ob_ti_native_words[t] = total;
    ob_ti_len_payload[t] = 0u;
    ob_ext_library[t] = key.x;
    ob_ext_unit[t] = key.y;
    ob_ext_local[t] = key.w;
    ob_imported_layout_kind[t] = PJ_IMPORTED_STRUCT | PJ_IMPORTED_COMPLETE;
    InterlockedAdd(pj_status[PJ_S_LAYOUT_CHANGED], 1u);
}
