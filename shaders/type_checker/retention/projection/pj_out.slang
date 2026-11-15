// The lowering columns of the current batch (07_rows, 08_side,
// 09_batch_finish), and the batch's map from batch indices to ranks.
// Element layouts are the compact HIR records (hir_records.slang).
__exported import type_checker.retention.projection.pj_common;

public StructuredBuffer<uint4> pj_batches;
public RWStructuredBuffer<uint4> ob_core;
public RWStructuredBuffer<uint4> ob_links;
public RWStructuredBuffer<uint4> ob_payload;
public RWStructuredBuffer<uint> ob_fn_return_type;
public RWStructuredBuffer<uint> ob_const_value;
public RWStructuredBuffer<uint> ob_expr_parent;
public RWStructuredBuffer<uint> ob_expr_root;
public RWStructuredBuffer<uint> ob_nearest_loop;
public RWStructuredBuffer<uint4> ob_call_args;
public RWStructuredBuffer<uint4> ob_fields;
public RWStructuredBuffer<uint4> ob_array_elements;
public RWStructuredBuffer<uint4> ob_params;
public RWStructuredBuffer<uint2> ob_param_ranges;
public RWStructuredBuffer<uint2> ob_generic_param_ranges;
public RWStructuredBuffer<uint> ob_array_element_start;
public RWStructuredBuffer<uint> ob_array_element_count;
public RWStructuredBuffer<uint> ob_value_decl;
public RWStructuredBuffer<uint> ob_value_type;
public RWStructuredBuffer<uint2> ob_value_const;
public RWStructuredBuffer<uint> ob_value_const_present;
public RWStructuredBuffer<uint> ob_argument_mode;
public RWStructuredBuffer<uint> ob_param_ref_tag;
public RWStructuredBuffer<uint> ob_param_ref_payload;
public RWStructuredBuffer<uint> ob_enclosing_fn;
public RWStructuredBuffer<uint> ob_function_return_type;
public RWStructuredBuffer<uint> ob_function_entrypoint;
public RWStructuredBuffer<uint> ob_function_host_service;
public RWStructuredBuffer<uint> ob_function_native_abi;
public RWStructuredBuffer<uint> ob_control_depth;
public RWStructuredBuffer<uint> ob_calls;   // 22 words per row (CheckedCallArtifact)
public RWStructuredBuffer<uint> ob_call_native_abi;
public RWStructuredBuffer<uint> ob_expr_ref_tag;
public RWStructuredBuffer<uint> ob_expr_ref_payload;
public RWStructuredBuffer<uint> ob_aggregate_decl_token;
public RWStructuredBuffer<uint> ob_aggregate_word_count;
public RWStructuredBuffer<uint> ob_array_length;
public RWStructuredBuffer<uint> ob_member_field_ordinal;
public RWStructuredBuffer<uint> ob_member_field_word_offset;
public RWStructuredBuffer<uint> ob_member_field_word_count;
public RWStructuredBuffer<uint> ob_iterable_kind;
public RWStructuredBuffer<uint> ob_function_result_word_count;
public RWStructuredBuffer<uint> ob_expr_scalar_type;
public RWStructuredBuffer<uint> ob_public_decl_index;
public RWStructuredBuffer<uint> ob_struct_init_field_ordinal;
// Lowering counts (GpuSemanticArtifactView::lowering_counts order).
public RWStructuredBuffer<uint> ob_count_rows;
public RWStructuredBuffer<uint> ob_count_call_args;
public RWStructuredBuffer<uint> ob_count_fields;
public RWStructuredBuffer<uint> ob_count_match_arms;
public RWStructuredBuffer<uint> ob_count_match_payloads;
public RWStructuredBuffer<uint> ob_count_array_elements;
public RWStructuredBuffer<uint> ob_count_strings;
public RWStructuredBuffer<uint> ob_count_params;

public static const uint PJ_CALL_WORDS = 22u;

public struct Batch
{
    public uint lo;
    public uint hi;
    public uint rows;
    public uint tokens;
}

public Batch pj_batch()
{
    uint4 w = pj_batches[pj_config[PJ_CFG_BATCH] * PJ_BATCH_WORDS];
    Batch b;
    b.lo = w.x; b.hi = w.y; b.rows = w.z; b.tokens = w.w;
    return b;
}

public uint pj_batch_side(uint k)
{
    uint b = pj_config[PJ_CFG_BATCH] * PJ_BATCH_WORDS;
    uint4 w1 = pj_batches[b + 1u];
    uint4 w2 = pj_batches[b + 2u];
    if (k < 4u) return k == 0u ? w1.x : (k == 1u ? w1.y : (k == 2u ? w1.z : w1.w));
    return k == 4u ? w2.x : (k == 5u ? w2.y : w2.z);
}

// Batch indices of a rank's relative references.
public struct Map
{
    public uint rank;
    public uint row;    // batch row of the rank's function row
    public uint token;  // batch token of the rank's first token
    public uint lo;
}

public Map pj_map(Batch b, uint rank)
{
    Map m;
    m.rank = rank;
    m.lo = b.lo;
    m.row = 1u + pj_base_at(rank, PJ_C_ROWS) - pj_base_at(b.lo, PJ_C_ROWS);
    m.token = pj_base_at(rank, PJ_C_TOKENS) - pj_base_at(b.lo, PJ_C_TOKENS);
    return m;
}

public uint pj_abs_row(Map m, uint rel) { return rel == RT_INVALID ? rel : m.row + rel; }
public uint pj_abs_token(Map m, uint rel) { return rel == RT_INVALID ? rel : m.token + rel; }
public uint pj_abs_side(Map m, uint k, uint rel)
{
    if (rel == RT_INVALID) return rel;
    return pj_base_at(m.rank, PJ_C_SIDE + k) - pj_base_at(m.lo, PJ_C_SIDE + k) + rel;
}
// A global row as a batch row.
public uint pj_batch_row(Batch b, uint g)
{
    return g == RT_INVALID ? g : 1u + g - pj_base_at(b.lo, PJ_C_ROWS);
}
