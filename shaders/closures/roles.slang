// Binder roles used by capture discovery. A parameter's nearest enclosing
// bracket must be a parenthesis, not a struct or array literal. Searching
// the existing depth scan's minimum heaps replaces a backward token walk.
import gpu_index;
import generated_token_ids;
import closure_common;
import blocked_search_tree;
import segment_tree;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

struct RoleParams
{
    uint leaf_base;
};

ConstantBuffer<RoleParams> gRoles;
StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint4> depth_scan;
StructuredBuffer<int> depth_local_min;
StructuredBuffer<int> depth_min_tree;
RWStructuredBuffer<uint> roles;

public struct DepthTree : IBlockedSearchTree<int>
{
    public static uint row_count() { return token_count[0]; }
    public static int row_value(uint row) { return row == 0u ? 0 : int(depth_scan[row - 1u].x); }
    public static int local_node(uint block, uint node) { return depth_local_min[block * 256u + node]; }
    public static uint block_leaf_base() { return gRoles.leaf_base; }
    public static int block_node(uint node) { return depth_min_tree[node]; }
}

public struct DepthAtMost : IRangeSearchPredicate<int, int>
{
    public static bool aggregate_may_match(int aggregate, int query) { return aggregate <= query; }
    public static bool leaf_matches(int leaf, int query) { return leaf <= query; }
}

uint kind_in_file(uint i, uint count, uint file)
{
    if (i >= count || token_file_id[i] != file)
        return 0u;
    return tokens_out[i].kind;
}

bool inside_parentheses(uint i, uint file)
{
    // An identifier leaves the depth unchanged. The last earlier row at
    // smaller depth is precisely its nearest unmatched opener. This holds
    // even for malformed nesting, which the frontend diagnoses later.
    uint open = blocked_search_last_before<int, int, DepthTree, DepthAtMost>(i, int(depth_scan[i].x) - 1);
    return open != CL_INVALID && token_file_id[open] == file && tk_paren_open(tokens_out[open].kind);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, 16776960u);
    uint count = token_count[0];
    if (i >= count)
        return;
    uint role = 0u;
    if (tokens_out[i].kind == TK_IDENT)
    {
        uint file = token_file_id[i];
        uint previous = i > 0u ? kind_in_file(i - 1u, count, file) : 0u;
        uint next = kind_in_file(i + 1u, count, file);
        uint after_next = kind_in_file(i + 2u, count, file);
        bool typed = next == TK_COLON && after_next != TK_COLON;
        if (previous == TK_LET)
            role = ROLE_LET | (typed ? ROLE_TYPED : 0u);
        else if (previous == TK_FOR)
            role = ROLE_FOR;
        else if (typed && (tk_paren_open(previous) || tk_comma(previous)) && inside_parentheses(i, file))
            role = ROLE_PARAM | ROLE_TYPED;
    }
    roles[i] = role;
}
