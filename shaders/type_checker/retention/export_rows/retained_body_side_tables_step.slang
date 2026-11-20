// Export step 12: one lane per side-table index, for each of the seven body
// tables. A row keyed inside a retained body is written to that segment's
// side block (table k's block follows tables 0..k-1). The first uint4 is
// the table record with rows, tokens and side indices relative to the body;
// the second holds semantic extras:
//   call args    (call, value, ordinal, file)          extras 0
//   fields       (owner, name token, value, ordinal)    (struct-init ordinal, 0, 0, 0)
//   match arms   (owner, pattern, result, ordinal)      (payload start, payload count, 0, 0)
//   payloads     (arm index, pattern, ordinal, parent)  0
//   elements     (array, value, ordinal, file)          0
//   strings      (node, byte word base, length, file)   0; bytes in rt_seg_bytes
//   params       (owner, name token, type row, ordinal) (declared term, 0, 0, 0)
import type_checker.retention.export_types.retained_export_type_rows;
import shared.syntax.hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export_rows.retained_body_side_tables;
import type_checker.retention.export_rows.retained_body_export;


struct ReceiverArg : IRtArgs
{
    uint leaf;
    uint arg(uint index) { return leaf; }
}

void prepare_ref_self(uint index)
{
    if (index >= side_rows(RT_SIDE_PARAMS)) return;
    uint function = compact_params[index].owner;
    if (!valid_row(function) || compact_hir_core[function].kind != HIR_FN) return;
    uint entry = rt_x_row[function].y;
    if (entry == RT_INVALID) return;
    uint ordinal = index - side_lower_bound(RT_SIDE_PARAMS, function);
    uint2 sig = rt_dir[entry * RT_DIR_WORDS + 1u].zw;
    if (ordinal != 0u || sig.x == RT_INVALID || sig.y == 0u) return;
    uint trait_row, leaf;
    if (required_receiver(function, ordinal, trait_row, leaf) != RECEIVER_REF_SELF) return;
    uint term = translate_checked(semantic_param_ref_tag_by_row[index], semantic_param_ref_payload_by_row[index]);
    if (term != RT_NONE && term != RT_UNKNOWN) return;
    uint claimed;
    InterlockedCompareExchange(rt_x_ref_self[trait_row].x, 0u, 1u, claimed);
    if (claimed != 0u) return;
    RtTermKey key = rt_key_begin(RT_KIND_REF, 1u, 0u, uint3(0u, 0u, 0u));
    rt_key_fold(key, leaf);
    ReceiverArg args;
    args.leaf = leaf;
    rt_x_ref_self[trait_row].y = rt_intern_term(key, args);
}

uint string_byte(uint offset)
{
    uint words; uint stride;
    compact_string_data_words.GetDimensions(words, stride);
    uint word = offset >> 2u;
    return word < words ? (compact_string_data_words[word] >> ((offset & 3u) * 8u)) & 0xffu : 0u;
}

uint side_len(uint4 s1, uint4 s2, uint k)
{
    if (k < 4u) return k == 0u ? s1.x : (k == 1u ? s1.y : (k == 2u ? s1.z : s1.w));
    return k == 4u ? s2.x : (k == 5u ? s2.y : s2.z);
}

void export_slot(uint k, uint index)
{
    if (index >= side_rows(k)) return;
    uint function = body_function(side_key(k, index));
    if (function == 0xffffffffu || rt_x_flags[function].w == 0u) return;
    SegmentContext c = segment_context(function);
    if (c.segment == RT_INVALID) return;
    uint4 s0 = rt_segments[c.segment * RT_SEG_WORDS + 0u];
    uint4 s1 = rt_segments[c.segment * RT_SEG_WORDS + 1u];
    uint4 s2 = rt_segments[c.segment * RT_SEG_WORDS + 2u];
    if (s0.w == RT_INVALID) return;
    uint offset = 0u;
    for (uint j = 0u; j < k; j++) offset += side_len(s1, s2, j);
    uint local = index - side_lower_bound(k, function);
    if (local >= side_len(s1, s2, k))
    {
        rt_invariant(RT_INV_SEGMENT);
        return;
    }

    uint f = 0u;
    uint untranslated = 0u;
    uint unowned = 0u;
    BodySpan s = c.span;
    uint4 record = uint4(0u, 0u, 0u, 0u);
    uint4 extra = uint4(0u, 0u, 0u, 0u);
    if (k == RT_SIDE_CALL_ARGS)
    {
        HirCallArg v = compact_call_args[index];
        record = uint4(rel_row(s, v.call, f), rel_row(s, v.value, f), v.ordinal, v.file_id);
    }
    else if (k == RT_SIDE_FIELDS)
    {
        HirField v = compact_fields[index];
        record = uint4(rel_row(s, v.owner, f), rel_token(s, v.name_token, f), rel_row(s, v.value, f), v.ordinal);
        extra.x = struct_init_field_ordinal_by_row[index];
    }
    else if (k == RT_SIDE_MATCH_ARMS)
    {
        HirMatchArm v = compact_match_arms[index];
        record = uint4(rel_row(s, v.owner, f), rel_row(s, v.pattern, f), rel_row(s, v.result, f), v.ordinal);
        uint payloads = compact_match_payload_count[index];
        extra.x = payloads != 0u ? rel_side(c, RT_SIDE_MATCH_PAYLOADS, compact_match_payload_start[index], f) : 0xffffffffu;
        extra.y = payloads;
    }
    else if (k == RT_SIDE_MATCH_PAYLOADS)
    {
        HirMatchPayload v = compact_match_payloads[index];
        record = uint4(rel_side(c, RT_SIDE_MATCH_ARMS, v.arm, f), rel_row(s, v.pattern, f), v.ordinal,
            rel_row(s, v.parent_pattern, f));
    }
    else if (k == RT_SIDE_ARRAY_ELEMENTS)
    {
        HirArrayElement v = compact_array_elements[index];
        record = uint4(rel_row(s, v.array, f), rel_row(s, v.value, f), v.ordinal, v.file_id);
    }
    else if (k == RT_SIDE_STRINGS)
    {
        HirString v = compact_strings[index];
        uint words = (v.decoded_len + 4u) >> 2u; // bytes and the terminating zero
        uint base = rt_alloc(RT_A_SEG_BYTES, words);
        if (base != RT_INVALID)
        {
            for (uint w = 0u; w < words; w++)
            {
                uint packed = 0u;
                for (uint b = 0u; b < 4u; b++)
                {
                    uint at = w * 4u + b;
                    if (at < v.decoded_len) packed |= string_byte(v.data_offset + at) << (b * 8u);
                }
                rt_seg_bytes[base + w] = packed;
            }
        }
        record = uint4(rel_row(s, v.node, f), base, v.decoded_len, v.file_id);
    }
    else
    {
        HirParam v = compact_params[index];
        record = uint4(rel_row(s, v.owner, f), rel_token(s, v.name_token, f), rel_row(s, v.type_node, f), v.ordinal);
        extra.x = body_term(c, semantic_param_ref_tag_by_row[index], semantic_param_ref_payload_by_row[index],
            untranslated, unowned);
    }
    uint at = s0.w + RT_SIDE_WORDS * (offset + local);
    rt_seg_side[at] = record;
    rt_seg_side[at + 1u] = extra;
    stat_add_at(function, side_key(k, index), RT_STAT_FOREIGN, f);
    stat_add_at(function, side_key(k, index), RT_STAT_UNTRANSLATED, untranslated);
    stat_add_at(function, side_key(k, index), RT_STAT_OWNERSHIP, unowned);
    if (unowned != 0u) rt_invariant(RT_INV_OWNERSHIP);
}

public void write_retained_body_side_tables(uint lane)
{
    prepare_ref_self(lane);
    for (uint k = 0u; k < RT_SIDE_TABLES; k++) export_slot(k, lane);
}
