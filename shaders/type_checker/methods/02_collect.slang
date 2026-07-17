// Collect inherent method declarations from parser-owned HIR method rows.
//
// The parser publishes one method relation row keyed by the HIR function node:
// impl owner, method name token, first parameter token, receiver mode, and
// visibility. This pass only projects those rows into the token-keyed method
// tables used by later typechecking passes. Trait impl methods also publish
// impl-owner rows for predicate validation, but they are not inherent methods and
// must not enter receiver-method lookup. This pass consumes the parser-owned impl
// owner kind to keep those tables separate; it does not walk parse-tree
// ancestors, child lists, token neighborhoods, or source bytes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_method_impl_node;
StructuredBuffer<uint> hir_method_name_token;
StructuredBuffer<uint> hir_method_first_param_token;
StructuredBuffer<uint> hir_method_receiver_mode;
StructuredBuffer<uint> hir_method_visibility;
StructuredBuffer<uint> hir_method_signature_flags;

RWStructuredBuffer<uint> method_decl_impl_node;
RWStructuredBuffer<uint> method_decl_name_token;
RWStructuredBuffer<uint> method_decl_param_offset;
RWStructuredBuffer<uint> method_decl_receiver_mode;
RWStructuredBuffer<uint> method_decl_visibility;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint METHOD_SIGNATURE_INHERENT_IMPL = 4u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || hir_kind[node] != HIR_FN)
        return;

    uint impl_node = hir_method_impl_node[node];
    if (!valid_node(impl_node) ||
        (hir_method_signature_flags[node] & METHOD_SIGNATURE_INHERENT_IMPL) == 0u)
        return;

    // Method metadata shares the canonical declaration-name token domain with
    // compact function HIR, enclosing-function context, call resolution, and
    // backend ABI records. The function span anchor is not an identity.
    uint fn_token = hir_method_name_token[node];
    if (!valid_token(fn_token))
        return;

    method_decl_impl_node[fn_token] = impl_node;
    method_decl_name_token[fn_token] = hir_method_name_token[node];
    method_decl_param_offset[fn_token] = hir_method_first_param_token[node];
    method_decl_receiver_mode[fn_token] = hir_method_receiver_mode[node];
    method_decl_visibility[fn_token] = hir_method_visibility[node];
}
