// Publish predicate syntax links from canonical HIR and ordered argument rows.
import hir_records;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;

RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;
RWStructuredBuffer<uint> predicate_trait_impl_trait_type_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH = 11u;
static const uint PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE = 12u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION = 22u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node)) return;
    uint kind = compact_hir_semantic_facts[node].semantic_kind;
    if (kind == HIR_SEMANTIC_IMPL_TRAIT)
    {
        predicate_trait_impl_trait_type_node[node] = compact_hir_payload[node].b;
        return;
    }
    if (kind != HIR_SEMANTIC_BOUND_PATH && kind != HIR_SEMANTIC_BOUND_REFERENCE) return;
    uint total = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    HirRange range = compact_type_arg_ranges[node];
    if (range.start > total || range.count > total - range.start)
    { predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION; return; }
    predicate_bound_arg_count[node] = range.count;
    if (range.count > 32u) predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH;
    // The two token fields are diagnostic anchors, never semantic arguments.
    for (uint ordinal = 0u; ordinal < min(range.count, 2u); ordinal++)
    {
        uint arg = compact_type_args[range.start + ordinal].value;
        uint token = valid_node(arg) ? compact_hir_core[arg].token_start : INVALID;
        if (ordinal == 0u) predicate_bound_first_arg_token[node] = token;
        else predicate_bound_second_arg_token[node] = token;
    }
}
