// Publish imported function parameter counts before the shared token scan.
// Type projection happens in the dependency scatter pass so dependency raw
// argument IDs never alias compact local-parameter staging rows.

import gpu_index;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_ordinal;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> dependency_declaration_words;
StructuredBuffer<uint> dependency_type_words;
RWStructuredBuffer<uint> call_param_count;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return gParams.hir_capacity == 0u ? 0u : min(gParams.hir_capacity, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arg_node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (arg_node >= active_hir_count())
        return;
    uint call_node = hir_call_arg_parent_call[arg_node];
    if (call_node >= active_hir_count())
        return;
    uint callee_node = hir_call_callee_node[call_node];
    if (callee_node >= active_hir_count())
        return;
    uint callee_token = hir_token_pos[callee_node];
    if (callee_token >= gParams.visible_capacity)
        return;
    uint declaration_i = call_dependency_decl[callee_token];
    if (declaration_i == INVALID || declaration_i >= gParams.declaration_count)
        return;

    uint signature_i = dependency_declaration_words[declaration_i * DECL_WORDS + 7u];
    uint signature_base = signature_i * TYPE_WORDS;
    if (dependency_type_words[signature_base] != INTERFACE_TYPE_FUNCTION)
        return;
    uint edge_count = dependency_type_words[signature_base + 4u];
    uint ordinal = hir_call_arg_ordinal[arg_node];
    uint param_count = edge_count == 0u ? 0u : edge_count - 1u;
    if (ordinal >= param_count)
        return;

    call_param_count[callee_token] = param_count;
}
