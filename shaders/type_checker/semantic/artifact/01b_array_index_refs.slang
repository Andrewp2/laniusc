// Project checked array/slice references into dense semantic HIR.
//
// The earlier index-result pass establishes that the index expression has a
// valid array/slice declaration and publishes its scalar cache. This final
// projection is entirely dense-HIR keyed: no raw parser row survives into the
// checked semantic artifact boundary.

import hir_records;
import gpu_index;
import dependency_interface;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
RWStructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
RWStructuredBuffer<uint> semantic_array_length_by_hir;
RWStructuredBuffer<uint> semantic_iterable_kind_by_hir;
RWStructuredBuffer<uint> semantic_function_result_word_count_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_STMT = 7u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_STMT_FOR = 7u;
static const uint HIR_FN = 3u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_I32 = 3u;
static const uint ITERABLE_EXCLUSIVE_RANGE = 1u;
static const uint ITERABLE_INCLUSIVE_RANGE = 2u;
static const uint ITERABLE_FIXED_ARRAY = 3u;
static const uint LANGUAGE_SYMBOL_CORE = 63u;
static const uint LANGUAGE_SYMBOL_RANGE_MODULE = 64u;
static const uint LANGUAGE_SYMBOL_RANGE_TYPE = 65u;
static const uint LANGUAGE_SYMBOL_RANGE_INCLUSIVE_TYPE = 66u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint name_token(uint node)
{
    if (!valid_hir(node) ||
        (compact_hir_core[node].kind != HIR_NAME_EXPR &&
         compact_hir_core[node].kind != HIR_PATH_EXPR))
        return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : INVALID;
}

void publish_ref(uint node, uint tag, uint payload)
{
    if (!valid_hir(node)) return;
    semantic_expr_ref_tag_by_hir[node] = tag;
    semantic_expr_ref_payload_by_hir[node] = payload;
}

void publish_array_length(uint node, uint instance)
{
    if (!valid_hir(node) || type_instance_len_kind[instance] != TYPE_LEN_LITERAL)
        return;
    semantic_array_length_by_hir[node] = type_instance_len_payload[instance];
}

uint named_iterable_kind(uint instance)
{
    if (!valid_token(instance) || type_instance_kind[instance] != TYPE_INSTANCE_NAMED)
        return 0u;
    if (type_instance_arg_count[instance] != 1u)
        return 0u;
    uint tag = 0u;
    uint payload = INVALID;
    uint row = type_instance_arg_row_start[instance];
    if (row != INVALID && row < type_instance_arg_row_count_out[0u])
    {
        tag = type_instance_arg_row_ref_tag[row];
        payload = type_instance_arg_row_ref_payload[row];
    }
    if (tag == 0u)
    {
        row = type_instance_arg_start[instance];
        if (row == INVALID || row >= gParams.n_tokens) return 0u;
        tag = type_instance_arg_ref_tag[row];
        payload = type_instance_arg_ref_payload[row];
    }
    if (tag != TYPE_REF_SCALAR || payload != TYPE_I32) return 0u;

    uint library_id = external_type_library_id[instance];
    uint unit_id = external_type_unit_id[instance];
    uint local_id = external_type_local_index[instance];
    if (library_id != INVALID && unit_id != INVALID && local_id != INVALID)
    {
        uint dependency_decl = dependency_find_declaration(library_id, unit_id, local_id);
        if (dependency_decl == INVALID) return 0u;
        uint decl_base = dependency_decl * 14u;
        uint module = dependency_declaration_word(decl_base + 0u);
        if (module >= dependency_module_count()) return 0u;
        uint module_base = module * 2u;
        uint segment_base = dependency_module_word(module_base + 0u);
        uint segment_count = dependency_module_word(module_base + 1u);
        if (segment_count != 2u) return 0u;
        uint segment_words = segment_base * 4u;
        uint core_id = language_name_id[LANGUAGE_SYMBOL_CORE];
        uint range_module_id = language_name_id[LANGUAGE_SYMBOL_RANGE_MODULE];
        if (dependency_module_segment_word(segment_words + 0u) != name_hash_lo[core_id] ||
            dependency_module_segment_word(segment_words + 1u) != name_hash_hi[core_id] ||
            dependency_module_segment_word(segment_words + 4u) != name_hash_lo[range_module_id] ||
            dependency_module_segment_word(segment_words + 5u) != name_hash_hi[range_module_id])
            return 0u;
        uint name_lo = dependency_declaration_word(decl_base + 1u);
        uint name_hi = dependency_declaration_word(decl_base + 2u);
        uint range_id = language_name_id[LANGUAGE_SYMBOL_RANGE_TYPE];
        if (name_lo == name_hash_lo[range_id] && name_hi == name_hash_hi[range_id])
            return ITERABLE_EXCLUSIVE_RANGE;
        uint inclusive_id = language_name_id[LANGUAGE_SYMBOL_RANGE_INCLUSIVE_TYPE];
        if (name_lo == name_hash_lo[inclusive_id] && name_hi == name_hash_hi[inclusive_id])
            return ITERABLE_INCLUSIVE_RANGE;
        return 0u;
    }

    uint decl_token = type_instance_decl_token[instance];
    if (!valid_token(decl_token)) return 0u;
    uint decl = decl_id_by_name_token[decl_token];
    if (decl == INVALID || decl >= gParams.n_hir_nodes) return 0u;
    uint module_id = decl_module_id[decl];
    if (module_id >= gParams.n_hir_nodes || module_key_segment_count[module_id] != 2u)
        return 0u;
    uint base = module_key_segment_base[module_id];
    if (base == INVALID || base + 1u >= gParams.n_tokens) return 0u;
    if (module_key_segment_name_id[base] != language_name_id[LANGUAGE_SYMBOL_CORE] ||
        module_key_segment_name_id[base + 1u] != language_name_id[LANGUAGE_SYMBOL_RANGE_MODULE])
        return 0u;
    uint name = decl_name_id[decl];
    if (name == language_name_id[LANGUAGE_SYMBOL_RANGE_TYPE])
        return ITERABLE_EXCLUSIVE_RANGE;
    if (name == language_name_id[LANGUAGE_SYMBOL_RANGE_INCLUSIVE_TYPE])
        return ITERABLE_INCLUSIVE_RANGE;
    return 0u;
}

uint aggregate_word_count(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload)) return 0u;
    uint kind = type_instance_kind[payload];
    if (kind == TYPE_INSTANCE_ARRAY && type_instance_len_kind[payload] == TYPE_LEN_LITERAL)
        return type_instance_len_payload[payload];
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind == HIR_FN && valid_token(payload.b))
        semantic_function_result_word_count_by_hir[node] = aggregate_word_count(
            fn_return_ref_tag[payload.b], fn_return_ref_payload[payload.b]);
    uint index_node = core.kind == HIR_INDEX_EXPR ? node : INVALID;
    bool for_node = core.kind == HIR_FOR_STMT ||
        (core.kind == HIR_STMT && payload.a == HIR_STMT_FOR);
    uint base_node = index_node != INVALID
        ? payload.b
        : for_node ? payload.c : node;
    uint token = name_token(base_node);
    uint decl = valid_token(token) ? visible_decl[token] : INVALID;
    if (!valid_token(decl) || decl_type_ref_tag[decl] != TYPE_REF_INSTANCE) return;

    uint instance = decl_type_ref_payload[decl];
    if (!valid_token(instance)) return;
    uint kind = type_instance_kind[instance];
    if (for_node)
    {
        uint iterable_kind = kind == TYPE_INSTANCE_ARRAY
            ? ITERABLE_FIXED_ARRAY : named_iterable_kind(instance);
        semantic_iterable_kind_by_hir[node] = iterable_kind;
        if (iterable_kind == ITERABLE_EXCLUSIVE_RANGE ||
            iterable_kind == ITERABLE_INCLUSIVE_RANGE)
        {
            publish_ref(node, type_instance_elem_ref_tag[instance],
                type_instance_elem_ref_payload[instance]);
            return;
        }
    }
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE) return;

    uint elem_tag = type_instance_elem_ref_tag[instance];
    uint elem_payload = type_instance_elem_ref_payload[instance];
    if (elem_tag == TYPE_REF_INVALID || elem_payload == INVALID) return;

    publish_ref(base_node, TYPE_REF_INSTANCE, instance);
    if (kind == TYPE_INSTANCE_ARRAY)
    {
        publish_array_length(base_node, instance);
    }
    if (for_node)
    {
        publish_ref(node, elem_tag, elem_payload);
        if (kind == TYPE_INSTANCE_ARRAY) publish_array_length(node, instance);
    }
    if (index_node == INVALID) return;
    publish_ref(index_node, elem_tag, elem_payload);
}
