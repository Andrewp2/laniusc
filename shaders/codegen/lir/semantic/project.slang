import hir_records;
import gpu_index;
import codegen.lowering_ir;
import checked_semantic_artifact;

struct Params { uint n_tokens; uint n_hir_nodes; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> semantic_value_decl_by_hir;
StructuredBuffer<uint> semantic_value_type_by_hir;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint> semantic_enclosing_fn_by_hir;
StructuredBuffer<uint> semantic_function_flag;
StructuredBuffer<uint> semantic_function_prefix;
StructuredBuffer<uint> semantic_function_id_by_token;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> semantic_const_function_by_root;
RWStructuredBuffer<uint> semantic_value_id;
RWStructuredBuffer<uint> semantic_value_type;
RWStructuredBuffer<uint> semantic_call_target;
RWStructuredBuffer<uint> semantic_call_kind;
RWStructuredBuffer<uint> semantic_call_result_type;
RWStructuredBuffer<uint> semantic_call_receiver;
RWStructuredBuffer<uint> semantic_call_symbol_library_id;
RWStructuredBuffer<uint> semantic_call_symbol_unit_id;
RWStructuredBuffer<uint> semantic_call_symbol_local_index;
RWStructuredBuffer<uint> semantic_call_arg_count_by_hir;
RWStructuredBuffer<uint> semantic_function_id;

static const uint INVALID = 0xffffffffu;
static const uint SEMANTIC_CALL_NONE = 0u;
static const uint SEMANTIC_CALL_FUNCTION = 1u;
static const uint SEMANTIC_CALL_INTRINSIC = 2u;
static const uint SEMANTIC_CALL_HOST = 3u;
static const uint SEMANTIC_CALL_SYMBOL = 4u;
static const uint SEMANTIC_CALL_ENUM_CONSTRUCTOR = 5u;
static const uint CHECKED_CALLABLE_ENUM_VARIANT = 4u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_EXPR_NAME = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint unit_variant_ordinal(uint declaration_token)
{
    uint count = min(compact_variant_count[0u], gParams.n_hir_nodes);
    for (uint row = 0u; row < count; row += 1u)
    {
        HirVariant variant = compact_variants[row];
        if (variant.name_token == declaration_token &&
            compact_variant_payload_count[row] == 0u)
            return variant.ordinal;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (node >= gParams.n_hir_nodes) return;
    semantic_value_id[node] = semantic_value_decl_by_hir[node];
    semantic_value_type[node] = semantic_value_type_by_hir[node];
    semantic_call_target[node] = INVALID;
    semantic_call_kind[node] = SEMANTIC_CALL_NONE;
    semantic_call_result_type[node] = INVALID;
    semantic_call_receiver[node] = INVALID;
    semantic_call_symbol_library_id[node] = INVALID;
    semantic_call_symbol_unit_id[node] = INVALID;
    semantic_call_symbol_local_index[node] = INVALID;
    semantic_call_arg_count_by_hir[node] = 0u;
    semantic_function_id[node] = INVALID;
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= count) return;

    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    // Type checking uses zero as the interval-scan sentinel and stores dense
    // HIR function identity plus one. Semantic LIR owns decoded identities;
    // top-level executable rows must not form a fake fn 0.
    uint encoded_fn = semantic_enclosing_fn_by_hir[node];
    uint hir_function = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    semantic_function_id[node] = hir_function < gParams.n_hir_nodes &&
        semantic_function_flag[hir_function] != 0u
        ? semantic_function_prefix[hir_function] : INVALID;
    if (semantic_function_flag[node] != 0u && core.kind == HIR_CONST_ITEM)
        semantic_function_id[node] = semantic_function_prefix[node];
    if (semantic_function_id[node] == INVALID)
    {
        uint root = compact_expr_root[node];
        if (root < count) semantic_function_id[node] = semantic_const_function_by_root[root];
    }
    if (core.kind == HIR_CALL_EXPR && valid_token(core.token_start))
    {
        CheckedCallArtifact checked = semantic_calls_by_hir[node];
        if (checked.callable_kind == CHECKED_CALLABLE_ENUM_VARIANT)
        {
            semantic_call_kind[node] = SEMANTIC_CALL_ENUM_CONSTRUCTOR;
            semantic_call_target[node] = checked.callable_ordinal;
            semantic_call_result_type[node] = checked.return_type;
        }
        else if (checked.intrinsic_tag != 0u)
        {
            semantic_call_kind[node] = SEMANTIC_CALL_INTRINSIC;
            semantic_call_target[node] = checked.intrinsic_tag;
        }
        else
        {
            uint target = valid_token(checked.target_token)
                ? semantic_function_id_by_token[checked.target_token] : INVALID;
            if (target != INVALID)
            {
                SemanticLirFunction function = semantic_lir_functions[target];
                uint service = function.host_service;
                semantic_call_kind[node] = service != INVALID
                    ? SEMANTIC_CALL_HOST : SEMANTIC_CALL_FUNCTION;
                semantic_call_target[node] = service != INVALID ? service : target;
                semantic_call_result_type[node] = function.result_type;
                semantic_call_receiver[node] = checked.receiver_hir;
            }
            else
            {
                if (checked.dependency_library_id != INVALID &&
                    checked.dependency_unit_id != INVALID &&
                    checked.dependency_local_index != INVALID)
                {
                    if (checked.dependency_host_service != INVALID)
                    {
                        semantic_call_kind[node] = SEMANTIC_CALL_HOST;
                        semantic_call_target[node] = checked.dependency_host_service;
                    }
                    else
                    {
                        semantic_call_kind[node] = SEMANTIC_CALL_SYMBOL;
                        semantic_call_symbol_library_id[node] = checked.dependency_library_id;
                        semantic_call_symbol_unit_id[node] = checked.dependency_unit_id;
                        semantic_call_symbol_local_index[node] = checked.dependency_local_index;
                    }
                    semantic_call_result_type[node] = checked.return_type;
                    semantic_call_receiver[node] = checked.receiver_hir;
                }
            }
        }
        semantic_call_arg_count_by_hir[node] =
            semantic_call_kind[node] == SEMANTIC_CALL_ENUM_CONSTRUCTOR
                ? 0u
                : checked.arg_count +
                    (semantic_call_receiver[node] != INVALID ? 1u : 0u);
    }
    else if ((core.kind == HIR_NAME_EXPR || payload.a == HIR_EXPR_NAME) &&
             semantic_value_id[node] < gParams.n_tokens)
    {
        uint declaration = semantic_value_id[node];
        uint variant_ordinal = unit_variant_ordinal(declaration);
        if (variant_ordinal != INVALID)
        {
            semantic_call_kind[node] = SEMANTIC_CALL_ENUM_CONSTRUCTOR;
            semantic_call_target[node] = variant_ordinal;
            semantic_call_result_type[node] = semantic_value_type[node];
        }
        else
        {
            uint target = semantic_function_id_by_token[declaration];
            if (target < count)
            {
                uint target_hir = semantic_lir_functions[target].hir_function;
                if (target_hir < count && compact_hir_core[target_hir].kind == HIR_CONST_ITEM)
                {
                    semantic_call_kind[node] = SEMANTIC_CALL_FUNCTION;
                    semantic_call_target[node] = target;
                    semantic_call_result_type[node] = semantic_value_type[node];
                }
            }
        }
    }
}
