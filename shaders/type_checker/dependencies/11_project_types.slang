// Project resolved dependency type declarations into the local tagged type-ref
// relation. Scalars use the existing scalar tag. Every other canonical shape
// retains an explicit external graph-node identity and is never encoded as a
// local declaration token.

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
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_dependency_decl;
StructuredBuffer<uint> dependency_declaration_words;
StructuredBuffer<uint> dependency_type_words;
StructuredBuffer<uint> canonical_type_roots;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> module_type_path_type;
RWStructuredBuffer<uint> module_type_path_status;

static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
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
    uint owner_token = path_owner_token[path_i];
    if (declaration_i >= gParams.declaration_count || owner_token >= gParams.token_capacity)
        return;
    uint signature = dependency_declaration_words[declaration_i * DECL_WORDS + 7u];
    if (signature >= gParams.type_count)
        return;
    uint root = canonical_type_roots[signature];
    if (root >= gParams.type_count)
        return;
    uint type_base = root * TYPE_WORDS;
    uint kind = dependency_type_words[type_base];
    uint payload = dependency_type_words[type_base + 1u];
    if (kind == INTERFACE_TYPE_SCALAR)
    {
        type_expr_ref_tag[owner_token] = TYPE_REF_SCALAR;
        type_expr_ref_payload[owner_token] = payload;
        module_type_path_type[owner_token] = payload;
    }
    else
    {
        type_expr_ref_tag[owner_token] = TYPE_REF_EXTERNAL_CANONICAL;
        type_expr_ref_payload[owner_token] = root;
    }
    module_type_path_status[owner_token] = PATH_RESOLVE_STATUS_OK;
}
