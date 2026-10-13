import primitive_types;
import hir_records;
import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

bool valid_instance(uint instance)
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return instance < capacity;
}

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> semantic_function_flag;
StructuredBuffer<uint> semantic_function_prefix;
StructuredBuffer<uint> semantic_param_ref_tag_by_row;
StructuredBuffer<uint> semantic_param_ref_payload_by_row;
StructuredBuffer<uint> semantic_param_prefix;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_native_words;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
// Private layout rows: native value words, then 0 (descriptor/scalar),
// 1 (descending native words), or 2 (ascending packed i32 elements).
RWStructuredBuffer<uint> semantic_param_value_layout;
RWStructuredBuffer<SemanticLirParam> semantic_lir_params;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint source_count = compact_param_count[0u];
    uint count = min(source_count, gParams.param_capacity);
    if (row == 0u)
    {
        if (source_count > gParams.param_capacity)
        {
            InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_SEMANTIC_CAPACITY);
            InterlockedMax(lowering_status[0u].required_capacity, source_count);
            InterlockedMin(lowering_status[0u].available_capacity, gParams.param_capacity);
        }
    }
    if (row >= count) return;

    HirParam source = compact_params[row];
    if (source.owner >= gParams.n_hir_nodes || semantic_function_flag[source.owner] == 0u)
        return;
    SemanticLirParam result;
    result.function_id = source.owner < gParams.n_hir_nodes && semantic_function_flag[source.owner] != 0u
        ? semantic_function_prefix[source.owner] : LIR_INVALID;
    result.declaration_id = source.name_token;
    result.ordinal = source.ordinal;
    // Parameter shape is a checked declaration contract, independent of
    // whether the source wrote a type node (implicit self does not).
    uint tag = semantic_param_ref_tag_by_row[row];
    uint payload = semantic_param_ref_payload_by_row[row];
    result.type_id = 0u;
    bool array_pair = false;
    uint value_words = 0u;
    uint value_storage = 0u;
    if (tag == 1u && scalar_is_known(payload))
        result.type_id = payload;
    else if (tag == 3u && valid_instance(payload))
    {
        uint kind = type_instance_kind[payload];
        if (kind == 4u)
            result.type_id = SEMANTIC_LIR_TY_POINTER;
        else if (kind == 3u)
        {
            result.type_id = 128u;
            array_pair = true;
        }
        else if (kind == 1u || kind == 2u)
        {
            bool packed_i32 = kind == 2u &&
                type_instance_elem_ref_tag[payload] == 1u &&
                type_instance_elem_ref_payload[payload] == 3u;
            result.type_id = kind == 1u ? 4096u : packed_i32 ? 131u : 128u;
            array_pair = kind == 2u;
            value_words = type_instance_native_words[payload];
            value_storage = packed_i32 ? 2u : 1u;
        }
    }
    else if (tag == 1u && payload >= 4096u)
    {
        // Legacy nominal identities carry a declaration token. Check its
        // declaration kind because the struct and enum code ranges overlap.
        uint token = payload - 4096u;
        uint declaration = token < gParams.n_tokens
            ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
        if (declaration >= gParams.n_hir_nodes || compact_hir_core[declaration].kind != 27u)
        {
            token = payload >= 6144u ? payload - 6144u : LIR_INVALID;
            declaration = token < gParams.n_tokens
                ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
            if (declaration >= gParams.n_hir_nodes || compact_hir_core[declaration].kind != 26u)
                declaration = LIR_INVALID;
        }
        if (declaration < gParams.n_hir_nodes)
        {
            result.type_id = payload;
            value_words = semantic_struct_word_count_by_hir[declaration];
            value_storage = 1u;
        }
    }
    result.value_metadata = result.type_id |
        (array_pair ? SEMANTIC_LIR_VALUE_ARRAY_PAIR : 0u);
    uint destination = semantic_param_prefix[row];
    // Replay already bounds native payloads to 65,535 words. Enforce the
    // same explicit value-copy boundary for ordinary aggregate parameters.
    if (result.type_id == 0u || value_words > 0xffffu)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
        InterlockedMin(lowering_status[0u].first_unsupported_hir,
            source.type_node < gParams.n_hir_nodes ? source.type_node : source.owner);
        value_words = 0u;
    }
    semantic_param_value_layout[destination * 2u] = value_words;
    semantic_param_value_layout[destination * 2u + 1u] = value_storage;
    semantic_lir_params[destination] = result;
}
