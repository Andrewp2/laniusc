// Attach imported generic type instances to their canonical external nominal
// identity. Generic arguments remain in the ordinary local instance relation;
// only the declaration identity lives in the external side table.

import gpu_index;

struct Params
{
    uint type_count;
    uint declaration_count;
    uint member_count;
    uint path_capacity;
    uint token_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_dependency_decl;
StructuredBuffer<uint> dependency_declaration_words;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> declaration_generic_arity;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_decl_token;
RWStructuredBuffer<uint> type_instance_external_canonical;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (path_i >= min(path_count_out[0u], gParams.path_capacity) ||
        path_kind[path_i] != PATH_RECORD_KIND_HIR_TYPE_EXPR)
        return;
    uint declaration_i = resolved_dependency_decl[path_i];
    uint segment_count = path_segment_count[path_i];
    if (declaration_i >= gParams.declaration_count || segment_count == 0u)
        return;
    uint leaf_token = path_segment_token[path_segment_base[path_i] + segment_count - 1u];
    uint owner_token = path_owner_token[path_i];
    if (leaf_token >= gParams.token_capacity || owner_token >= gParams.token_capacity ||
        type_instance_kind[leaf_token] != TYPE_INSTANCE_NAMED)
        return;
    if (type_instance_arg_count[leaf_token] != declaration_generic_arity[declaration_i])
    {
        type_instance_state[leaf_token] = TYPE_INSTANCE_UNSUPPORTED;
        return;
    }
    uint signature = dependency_declaration_words[declaration_i * DECL_WORDS + 7u];
    if (signature >= gParams.type_count)
        return;
    uint root = canonical_type_roots[signature];
    if (root >= gParams.type_count)
        return;
    type_instance_decl_token[leaf_token] = INVALID;
    type_instance_external_canonical[leaf_token] = root;
    type_instance_state[leaf_token] = TYPE_INSTANCE_RESOLVED;
    type_expr_ref_tag[owner_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[owner_token] = leaf_token;
    type_expr_ref_tag[leaf_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[leaf_token] = leaf_token;
}
