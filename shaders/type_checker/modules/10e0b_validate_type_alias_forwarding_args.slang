// Validate one positional forwarding edge per generic argument in parallel.
// The final count check in root initialization rejects missing/duplicate rows.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirTypeArg { uint owner; uint value; uint ordinal; uint file_id; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> alias_forwarding;
RWStructuredBuffer<uint> alias_forwarding_valid_arg_count;
StructuredBuffer<uint> alias_decl_by_target_hir;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
uint active_type_arg_count() { return min(gParams.n_hir_nodes, compact_type_arg_count[0u]); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_type_arg_count())
        return;
    HirTypeArg arg = compact_type_args[row];
    uint owner = arg.owner;
    uint decl_i = owner < active_hir_count() ? alias_decl_by_target_hir[owner] : INVALID;
    if (decl_i >= gParams.n_hir_nodes || alias_forwarding[decl_i] == 0u)
        return;

    uint token = arg.value < active_hir_count()
        ? compact_hir_core[arg.value].token_start
        : INVALID;
    uint slot = token < gParams.n_tokens ? type_generic_param_slot_by_token[token] : INVALID;
    uint rank = arg.ordinal;
    if (slot == INVALID || slot != rank)
    {
        uint ignored;
        InterlockedAnd(alias_forwarding[decl_i], 0u, ignored);
        return;
    }
    uint ignored;
    InterlockedAdd(alias_forwarding_valid_arg_count[decl_i], 1u, ignored);
}
