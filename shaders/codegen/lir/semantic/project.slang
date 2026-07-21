import gpu_index;
import codegen.lowering_ir;

struct Params { uint n_tokens; uint n_hir_nodes; uint reserved0; uint reserved1; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> backend_call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> semantic_function_flag;
StructuredBuffer<uint> semantic_function_prefix;
StructuredBuffer<uint> semantic_function_id_by_token;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<uint> semantic_value_id;
RWStructuredBuffer<uint> semantic_value_type;
RWStructuredBuffer<uint> semantic_call_target;
RWStructuredBuffer<uint> semantic_call_kind;
RWStructuredBuffer<uint> semantic_call_result_type;
RWStructuredBuffer<uint> semantic_function_id;

static const uint INVALID = 0xffffffffu;
static const uint SEMANTIC_CALL_NONE = 0u;
static const uint SEMANTIC_CALL_FUNCTION = 1u;
static const uint SEMANTIC_CALL_INTRINSIC = 2u;
static const uint SEMANTIC_CALL_HOST = 3u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_CONST = 4u;
static const uint HIR_EXPR_NAME = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint host_service_for_name_token(uint token)
{
    if (!valid_token(token)) return INVALID;
    uint name_id = name_id_by_token[token];
    // Slot 52 is compiler-only array data projection. Numeric conversion at
    // slot 28 intentionally crosses this ABI classifier, then target lowering
    // selects a native instruction instead of an imported/runtime call.
    for (uint symbol = 20u; symbol < 63u; ++symbol)
    {
        if (symbol == 52u) continue;
        if (language_name_id[symbol] == name_id) return symbol;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (node >= gParams.n_hir_nodes) return;
    semantic_value_id[node] = INVALID;
    semantic_value_type[node] = 0u;
    semantic_call_target[node] = INVALID;
    semantic_call_kind[node] = SEMANTIC_CALL_NONE;
    semantic_call_result_type[node] = INVALID;
    semantic_function_id[node] = INVALID;
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= count) return;

    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (valid_token(core.token_start))
    {
        // Type checking uses zero as the interval-scan sentinel and stores
        // dense HIR function identity plus one. Semantic LIR owns decoded
        // identities; top-level executable rows must not form a fake fn 0.
        uint encoded_fn = enclosing_fn[core.token_start];
        uint hir_function = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
        semantic_function_id[node] = hir_function < gParams.n_hir_nodes &&
            semantic_function_flag[hir_function] != 0u
            ? semantic_function_prefix[hir_function] : INVALID;
    }
    if ((core.kind == HIR_NAME_EXPR || payload.a == HIR_EXPR_NAME) &&
        valid_token(payload.d))
    {
        semantic_value_id[node] = visible_decl[payload.d];
        semantic_value_type[node] = visible_type[payload.d];
    }
    else if ((core.kind == HIR_LET_STMT ||
              (core.kind == HIR_STMT &&
               (payload.a == HIR_STMT_LET || payload.a == HIR_STMT_CONST))) &&
             valid_token(payload.b))
    {
        semantic_value_id[node] = payload.b;
        semantic_value_type[node] = visible_type[payload.b];
    }

    if (core.kind == HIR_CALL_EXPR && valid_token(core.token_start))
    {
        uint callee = payload.a;
        uint callee_token = callee < count ? compact_hir_core[callee].token_start : INVALID;
        uint intrinsic = valid_token(callee_token) ? call_intrinsic_tag[callee_token] : 0u;
        if (intrinsic != 0u)
        {
            semantic_call_kind[node] = SEMANTIC_CALL_INTRINSIC;
            semantic_call_target[node] = intrinsic;
        }
        else
        {
            uint target_token = backend_call_fn_index[core.token_start];
            uint target = valid_token(target_token)
                ? semantic_function_id_by_token[target_token] : INVALID;
            if (target != INVALID)
            {
                SemanticLirFunction function = semantic_lir_functions[target];
                uint target_hir = function.hir_function;
                bool external = target_hir < count &&
                    compact_hir_payload[target_hir].a == 5u;
                uint service = external
                    ? host_service_for_name_token(function.name_token) : INVALID;
                semantic_call_kind[node] = service != INVALID
                    ? SEMANTIC_CALL_HOST : SEMANTIC_CALL_FUNCTION;
                semantic_call_target[node] = service != INVALID ? service : target;
                semantic_call_result_type[node] = function.result_type;
            }
        }
    }
}
