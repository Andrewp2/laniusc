// The seven HIR side tables a body owns rows of, in segment order. Each
// table is in key order (its owner HIR row), so a body's block is the range
// of keys inside its subtree (as instance_exec.slang's blocks).
//   0 call arguments  (key: call row)        4 array elements (key: array row)
//   1 fields          (key: owner row)       5 strings        (key: literal row)
//   2 match arms      (key: match row)       6 parameters     (key: function row)
//   3 match payloads  (key: pattern row)
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

public StructuredBuffer<uint> compact_call_arg_count;
public StructuredBuffer<HirCallArg> compact_call_args;
public StructuredBuffer<uint> compact_field_count;
public StructuredBuffer<HirField> compact_fields;
public StructuredBuffer<uint> compact_match_arm_count;
public StructuredBuffer<HirMatchArm> compact_match_arms;
public StructuredBuffer<uint> compact_match_payload_row_count;
public StructuredBuffer<HirMatchPayload> compact_match_payloads;
public StructuredBuffer<uint> compact_match_payload_start;
public StructuredBuffer<uint> compact_match_payload_count;
public StructuredBuffer<uint> compact_array_element_row_count;
public StructuredBuffer<HirArrayElement> compact_array_elements;
public StructuredBuffer<uint> compact_string_count;
public StructuredBuffer<HirString> compact_strings;
public StructuredBuffer<uint> compact_string_data_words;
public StructuredBuffer<uint> compact_param_count;
public StructuredBuffer<HirParam> compact_params;
public StructuredBuffer<HirRange> compact_param_ranges;
public StructuredBuffer<uint> struct_init_field_ordinal_by_row;
// Nominal schemas (not body side tables).
public StructuredBuffer<uint> compact_variant_payload_row_count;
public StructuredBuffer<HirVariantPayload> compact_variant_payloads;

public static const uint RECEIVER_SELF = 1u;
public static const uint RECEIVER_REF_SELF = 2u;
// The side pass claims the trait row for any required &self signature.
// The schema pass reads the resulting term after that dispatch.
public RWStructuredBuffer<uint2> rt_x_ref_self;

public uint required_receiver(uint function, uint ordinal, out uint trait_row, out uint self_leaf)
{
    trait_row = container_of(function);
    self_leaf = RT_UNKNOWN;
    if (ordinal != 0u || !is_trait_row(trait_row)) return 0u;
    uint method = method_row(function);
    if (method == 0xffffffffu) return 0u;
    uint mode = compact_method_signatures[method].receiver_mode;
    if (mode != RECEIVER_SELF && mode != RECEIVER_REF_SELF) return 0u;
    uint token = hir_generic_owner_token(compact_hir_core[trait_row], compact_hir_payload[trait_row], token_capacity());
    uint param = token == 0xffffffffu ? RT_INVALID : param_map_find(token);
    if (param == RT_INVALID) return 0u;
    self_leaf = rt_param_leaf(param);
    return mode;
}

public uint variant_rows()
{
    uint rows; uint stride;
    compact_variants.GetDimensions(rows, stride);
    return min(compact_variant_count[0u], rows);
}

public uint variant_payload_rows()
{
    uint rows; uint stride;
    compact_variant_payloads.GetDimensions(rows, stride);
    return min(compact_variant_payload_row_count[0u], rows);
}

// First variant whose owner row is at least `row`.
public uint variant_lower_bound(uint row)
{
    uint lo = 0u;
    uint hi = variant_rows();
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (compact_variants[mid].owner < row) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

// First variant payload whose variant is at least `variant`.
public uint payload_lower_bound(uint variant)
{
    uint lo = 0u;
    uint hi = variant_payload_rows();
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (compact_variant_payloads[mid].variant < variant) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

public static const uint RT_SIDE_TABLES = 7u;
public static const uint RT_SIDE_CALL_ARGS = 0u;
public static const uint RT_SIDE_FIELDS = 1u;
public static const uint RT_SIDE_MATCH_ARMS = 2u;
public static const uint RT_SIDE_MATCH_PAYLOADS = 3u;
public static const uint RT_SIDE_ARRAY_ELEMENTS = 4u;
public static const uint RT_SIDE_STRINGS = 5u;
public static const uint RT_SIDE_PARAMS = 6u;
// Side records are two uint4: the table's record and RT_SIDE_WORDS - 1
// words of semantic extras (see docs/compiler-program-retention.md).
public static const uint RT_SIDE_WORDS = 2u;

public uint side_key(uint k, uint index)
{
    if (k == RT_SIDE_CALL_ARGS) return compact_call_args[index].call;
    if (k == RT_SIDE_FIELDS) return compact_fields[index].owner;
    if (k == RT_SIDE_MATCH_ARMS) return compact_match_arms[index].owner;
    if (k == RT_SIDE_MATCH_PAYLOADS) return compact_match_payloads[index].pattern;
    if (k == RT_SIDE_ARRAY_ELEMENTS) return compact_array_elements[index].array;
    if (k == RT_SIDE_STRINGS) return compact_strings[index].node;
    return compact_params[index].owner;
}

public uint side_rows(uint k)
{
    uint rows; uint stride;
    if (k == RT_SIDE_CALL_ARGS) { compact_call_args.GetDimensions(rows, stride); return min(compact_call_arg_count[0u], rows); }
    if (k == RT_SIDE_FIELDS) { compact_fields.GetDimensions(rows, stride); return min(compact_field_count[0u], rows); }
    if (k == RT_SIDE_MATCH_ARMS) { compact_match_arms.GetDimensions(rows, stride); return min(compact_match_arm_count[0u], rows); }
    if (k == RT_SIDE_MATCH_PAYLOADS) { compact_match_payloads.GetDimensions(rows, stride); return min(compact_match_payload_row_count[0u], rows); }
    if (k == RT_SIDE_ARRAY_ELEMENTS) { compact_array_elements.GetDimensions(rows, stride); return min(compact_array_element_row_count[0u], rows); }
    if (k == RT_SIDE_STRINGS) { compact_strings.GetDimensions(rows, stride); return min(compact_string_count[0u], rows); }
    compact_params.GetDimensions(rows, stride);
    return min(compact_param_count[0u], rows);
}

// The first index of table k whose key is at least `row`.
public uint side_lower_bound(uint k, uint row)
{
    uint lo = 0u;
    uint hi = side_rows(k);
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (side_key(k, mid) < row) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}
