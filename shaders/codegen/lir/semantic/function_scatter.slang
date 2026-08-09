import hir_records;
import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_start;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> semantic_function_flag;
StructuredBuffer<uint> semantic_function_prefix;
StructuredBuffer<uint> semantic_local_prefix;
StructuredBuffer<uint> semantic_local_total;
StructuredBuffer<uint> semantic_function_return_type_by_hir;
StructuredBuffer<uint> semantic_function_result_word_count_by_hir;
StructuredBuffer<uint> semantic_function_entrypoint_by_hir;
StructuredBuffer<uint> semantic_function_host_service_by_hir;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> semantic_value_type_by_hir;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> semantic_aggregate_decl_token_by_hir;
StructuredBuffer<uint> semantic_aggregate_word_count_by_hir;
StructuredBuffer<uint> semantic_array_length_by_hir;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<uint> semantic_function_id_by_token;
RWStructuredBuffer<uint> semantic_const_function_by_root;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;

bool valid_token(uint token) { return token != LIR_INVALID && token < gParams.n_tokens; }

uint local_payload_word_count(uint type_node, uint hir_count, out bool supported)
{
    supported = type_node < hir_count;
    if (!supported) return 0u;
    uint words = semantic_aggregate_word_count_by_hir[type_node];
    if (words != 0u) return words;
    uint array_length = semantic_array_length_by_hir[type_node];
    if (array_length != LIR_INVALID) return array_length;

    uint decl_token = semantic_aggregate_decl_token_by_hir[type_node];
    if (!valid_token(decl_token) && semantic_expr_ref_tag_by_hir[type_node] == 1u)
    {
        uint type_id = semantic_expr_ref_payload_by_hir[type_node];
        if (type_id >= TY_STRUCT_BASE && type_id < TY_ENUM_BASE)
            decl_token = type_id - TY_STRUCT_BASE;
        else if (type_id >= TY_ENUM_BASE)
            decl_token = type_id - TY_ENUM_BASE;
    }
    if (!valid_token(decl_token)) return 1u;
    uint declaration = semantic_aggregate_hir_by_name_token[decl_token];
    if (declaration >= hir_count)
    {
        supported = false;
        return 0u;
    }
    if (compact_hir_core[declaration].kind == HIR_STRUCT_ITEM)
    {
        words = semantic_struct_word_count_by_hir[declaration];
        supported = words != 0u;
        return words;
    }
    // Nested enum payload layouts need the enum-layout fixed point rather
    // than silently treating an aggregate as one scalar word.
    if (compact_hir_core[declaration].kind == HIR_ENUM_ITEM)
    {
        supported = false;
        return 0u;
    }
    return 1u;
}

uint local_enum_word_count(uint enum_hir, uint hir_count)
{
    uint variant_total = min(compact_variant_count[0u], hir_count);
    uint lo = 0u;
    uint hi = variant_total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_variants[mid].owner < enum_hir) lo = mid + 1u;
        else hi = mid;
    }
    uint payload_total = min(compact_variant_payload_row_count[0u], hir_count);
    uint maximum_payload_words = 0u;
    for (uint variant_row = lo;
         variant_row < variant_total && compact_variants[variant_row].owner == enum_hir;
         variant_row += 1u)
    {
        uint start = compact_variant_payload_start[variant_row];
        uint count = compact_variant_payload_count[variant_row];
        if (count != 0u && (start >= payload_total || count > payload_total - start))
            return 0u;
        uint variant_words = 0u;
        for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
        {
            HirVariantPayload payload = compact_variant_payloads[start + ordinal];
            if (payload.variant != variant_row || payload.ordinal != ordinal)
                return 0u;
            bool supported;
            uint payload_words = local_payload_word_count(
                payload.type_node, hir_count, supported);
            if (!supported) return 0u;
            variant_words += payload_words;
        }
        maximum_payload_words = max(maximum_payload_words, variant_words);
    }
    return 1u + maximum_payload_words;
}

uint public_impl_method_symbol(uint hir, uint hir_count)
{
    uint method_count = min(compact_method_count[0u], hir_count);
    for (uint row = 0u; row < method_count; row += 1u)
    {
        HirMethodCore method = compact_method_cores[row];
        HirMethodSignature signature = compact_method_signatures[row];
        // Method symbols share the object identity namespace with public
        // declarations, using a disjoint high-bit namespace.  Trait contracts
        // have no implementation node and therefore produce no definition.
        if (method.node == hir && method.impl_node != LIR_INVALID &&
            (signature.metadata & 0xffffu) == 1u)
            return 0x80000000u | hir;
    }
    return LIR_INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (hir >= hir_count || semantic_function_flag[hir] == 0u) return;

    uint function_id = semantic_function_prefix[hir];
    HirCore core = compact_hir_core[hir];
    HirPayload payload = compact_hir_payload[hir];
    bool constant = core.kind == HIR_CONST_ITEM;
    HirRange range = compact_param_ranges[hir];
    SemanticLirFunction result;
    result.hir_function = hir;
    result.name_token = payload.b;
    result.param_start = range.count == 0u ? LIR_INVALID : range.start;
    result.param_count = range.count;
    result.result_type = constant ? semantic_value_type_by_hir[hir]
        : semantic_function_return_type_by_hir[hir];
    uint return_type_node = compact_fn_return_type[hir];
    uint result_decl_token = LIR_INVALID;
    uint result_decl_hir = LIR_INVALID;
    if (!constant && return_type_node < hir_count)
    {
        uint ref_tag = semantic_expr_ref_tag_by_hir[return_type_node];
        uint ref_payload = semantic_expr_ref_payload_by_hir[return_type_node];
        result_decl_token = semantic_aggregate_decl_token_by_hir[return_type_node];
        if (!valid_token(result_decl_token))
        {
            uint source_token = compact_hir_core[return_type_node].token_start;
            if (valid_token(source_token) &&
                semantic_aggregate_hir_by_name_token[source_token] < hir_count)
                result_decl_token = source_token;
        }
        if (!valid_token(result_decl_token))
        {
            uint value_node = compact_hir_payload[return_type_node].b;
            if (value_node < hir_count)
            {
                result_decl_token = semantic_aggregate_decl_token_by_hir[value_node];
                if (!valid_token(result_decl_token))
                    result_decl_token = compact_hir_core[value_node].token_start;
            }
        }
        result_decl_hir = valid_token(result_decl_token)
            ? semantic_aggregate_hir_by_name_token[result_decl_token] : LIR_INVALID;
        if (result_decl_hir < hir_count)
        {
            uint kind = compact_hir_core[result_decl_hir].kind;
            if (kind == HIR_STRUCT_ITEM)
                result.result_type = TY_STRUCT_BASE + result_decl_token;
            else if (kind == HIR_ENUM_ITEM)
                result.result_type = TY_ENUM_BASE + result_decl_token;
        }
        else if (ref_tag == 1u && ref_payload >= TY_STRUCT_BASE)
            result.result_type = ref_payload;
    }
    result.result_word_count = semantic_function_result_word_count_by_hir[hir];
    if (result.result_word_count == 0u && result_decl_hir < hir_count &&
        compact_hir_core[result_decl_hir].kind == HIR_STRUCT_ITEM)
        result.result_word_count = semantic_struct_word_count_by_hir[result_decl_hir];
    if (result.result_word_count == 0u && result_decl_hir < hir_count &&
        compact_hir_core[result_decl_hir].kind == HIR_ENUM_ITEM)
        result.result_word_count = local_enum_word_count(result_decl_hir, hir_count);
    if (result.result_word_count == 0u && result_decl_hir >= hir_count &&
        result.result_type >= TY_STRUCT_BASE && result.result_type < TY_ENUM_BASE)
    {
        uint name_token = result.result_type - TY_STRUCT_BASE;
        uint struct_hir = valid_token(name_token)
            ? semantic_aggregate_hir_by_name_token[name_token] : LIR_INVALID;
        if (struct_hir < hir_count)
            result.result_word_count = semantic_struct_word_count_by_hir[struct_hir];
    }
    if (result.result_word_count == 0u && result_decl_hir >= hir_count &&
        result.result_type >= TY_ENUM_BASE)
    {
        uint name_token = result.result_type - TY_ENUM_BASE;
        uint enum_hir = valid_token(name_token)
            ? semantic_aggregate_hir_by_name_token[name_token] : LIR_INVALID;
        if (enum_hir < hir_count && compact_hir_core[enum_hir].kind == HIR_ENUM_ITEM)
            result.result_word_count = local_enum_word_count(enum_hir, hir_count);
    }
    result.flags = !constant && semantic_function_entrypoint_by_hir[hir] != 0u
        ? SEMANTIC_FUNCTION_FLAG_ENTRYPOINT : 0u;
    result.file_id = compact_hir_links[hir].file_id;
    uint local_start = semantic_local_prefix[hir];
    uint local_end = compact_hir_links[hir].subtree_end < hir_count
        ? semantic_local_prefix[compact_hir_links[hir].subtree_end]
        : semantic_local_total[0u];
    result.local_start = local_start;
    result.local_count = local_end - local_start;
    uint symbol_local_index = constant ? LIR_INVALID : public_decl_index_by_hir[hir];
    if (!constant && symbol_local_index == LIR_INVALID)
        symbol_local_index = public_impl_method_symbol(hir, hir_count);
    result.symbol_local_index = symbol_local_index;
    result.symbol_flags = 0u;
    result.host_service = semantic_function_host_service_by_hir[hir];
    semantic_lir_functions[function_id] = result;

    // Type checking deliberately exposes backend call targets in the
    // function-start-token domain. Translate that boundary once, here, so all
    // downstream LIR uses compact function IDs.
    if (valid_token(core.token_start)) semantic_function_id_by_token[core.token_start] = function_id;
    if (valid_token(payload.b)) semantic_function_id_by_token[payload.b] = function_id;
    if (constant && compact_const_value[hir] < hir_count)
        semantic_const_function_by_root[compact_const_value[hir]] = function_id;
}
