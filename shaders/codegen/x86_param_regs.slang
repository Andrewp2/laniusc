// x86_64 parameter declaration -> SysV register lookup scatter.
//
// The parser owns hir_param_record rows. This pass scatters those sparse
// parameter rows into declaration-token keyed backend records so function-body
// planning can look up parameter ABI registers without scanning the whole HIR.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_item_decl_token;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint4> hir_param_record;

RWStructuredBuffer<uint4> x86_param_reg_record;
RWStructuredBuffer<uint> x86_param_reg_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_PARAM_REGS_OK = 1u;

static const uint HIR_PARAM_RECORD_FN = 0u;
static const uint HIR_PARAM_RECORD_ORDINAL = 1u;
static const uint HIR_PARAM_RECORD_NAME_TOKEN = 2u;
static const uint HIR_PARAM_RECORD_NODE = 3u;

static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
static const uint PARAM_CACHE_STRIDE = 16u;
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDX = 2u;
static const uint X86_REG_ECX = 1u;
static const uint X86_REG_R8D = 8u;
static const uint X86_REG_R9D = 9u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint sysv_integer_arg_reg(uint ordinal)
{
    if (ordinal == 0u) return X86_REG_EDI;
    if (ordinal == 1u) return X86_REG_ESI;
    if (ordinal == 2u) return X86_REG_EDX;
    if (ordinal == 3u) return X86_REG_ECX;
    if (ordinal == 4u) return X86_REG_R8D;
    if (ordinal == 5u) return X86_REG_R9D;
    return INVALID;
}

void scatter_param_reg(uint param_node)
{
    uint4 record = hir_param_record[param_node];
    uint fn_node = record[HIR_PARAM_RECORD_FN];
    uint ordinal = record[HIR_PARAM_RECORD_ORDINAL];
    uint decl_token = record[HIR_PARAM_RECORD_NAME_TOKEN];
    uint source_param_node = record[HIR_PARAM_RECORD_NODE];
    if (!valid_node(fn_node) || !valid_node(source_param_node) ||
        !valid_token(decl_token) || ordinal >= X86_SYSV_MAX_INTEGER_ARGS)
        return;

    uint fn_decl_token = hir_item_decl_token[fn_node];
    if (!valid_token(fn_decl_token))
        return;

    uint arg_reg = sysv_integer_arg_reg(ordinal);
    if (arg_reg == INVALID)
        return;

    uint param_type = call_param_type[fn_decl_token * PARAM_CACHE_STRIDE + ordinal];
    x86_param_reg_record[decl_token] = uint4(fn_node, ordinal, arg_reg, param_type);
    uint old_count = 0u;
    InterlockedAdd(x86_param_reg_status[3u], 1u, old_count);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i >= active_hir_node_count())
        return;

    scatter_param_reg(node_i);
}
