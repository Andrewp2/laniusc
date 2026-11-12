// Per tree node: the record of the generator construct the node stands for,
// written at the construct's first token. Each word of a record has one
// writer, so the nodes of one construct fill it without a conflict.
import gpu_index;
import generated_parse_production_ids;
import generated_token_ids;
import generator_common;

struct NodeParams
{
    uint node_capacity;
    uint token_count;
    uint reserved0;
    uint reserved1;
};

ConstantBuffer<NodeParams> gNodes;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> semantic_token_kinds;
RWStructuredBuffer<uint> records;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint node_count()
{
    return min(gNodes.node_capacity, tree_count_status[5u]);
}

bool valid(uint node)
{
    return node != GN_NONE && node < node_count();
}

uint kind_of(uint node)
{
    return valid(node) ? node_kind[node] : GN_NONE;
}

uint up_of(uint node)
{
    return valid(node) ? parent[node] : GN_NONE;
}

uint sibling(uint node)
{
    return valid(node) ? next_sibling[node] : GN_NONE;
}

void store(uint token, uint word, uint value)
{
    if (token < gNodes.token_count)
        records[token * GR_WORDS + word] = value;
}

// A type's token range includes the token after it unless the type ends in
// `>`, `]` or `!`.
uint type_end(uint node)
{
    if (!valid(node))
        return 0u;
    uint end = hir_token_end[node];
    uint last = semantic_token_kinds[end];
    if (last == TK_TYPE_ARG_GT || last == TK_TYPE_ARRAY_RBRACKET || last == TK_RETURN_NEVER)
        return end;
    return end - 1u;
}

void block(uint node, uint kind, uint owner)
{
    uint open = hir_token_pos[node];
    uint end = hir_token_end[node];
    store(open, GR_ROLE, GROLE_BLOCK);
    store(open, GR_END, end);
    store(open, GR_OWNER, owner);
    store(open, GR_KIND, kind);
    store(end - 1u, GR_ROLE, GROLE_CLOSE);
    store(end - 1u, GR_OPEN, open);
}

// The first token of the `if` statement that the arm under `node` belongs
// to. An `else if` is an arm of the first `if` of its chain.
uint chain_head(uint node)
{
    uint at = node;
    for (uint guard = 0u; guard < MAX_LIST; guard += 1u)
    {
        uint kind = kind_of(at);
        if (kind == PROD_IF_STMT)
            return hir_token_pos[at];
        if (kind != PROD_ELSE_IF && kind != PROD_ELSE_STMT && kind != PROD_ELSE_BLOCK)
            return 0u;
        at = parent[at];
    }
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (node >= node_count())
        return;
    uint kind = node_kind[node];
    uint pos = hir_token_pos[node];
    uint up = parent[node];
    uint up_kind = kind_of(up);

    if (kind == PROD_FN && (up_kind == PROD_ITEM_GEN || up_kind == PROD_PUB_GEN))
    {
        uint type_params = first_child[node];
        uint params = sibling(type_params);
        uint output = sibling(params);
        uint where_clause = sibling(output);
        uint contracts = sibling(where_clause);
        uint body = sibling(contracts);
        if (!valid(body))
            return;
        uint flags = up_kind == PROD_PUB_GEN ? GF_PUBLIC : 0u;
        if (kind_of(type_params) != PROD_ENUM_TYPE_PARAMS_NONE)
            flags |= GF_GENERIC;
        if (kind_of(output) != PROD_RET_TYPE)
            flags |= GF_NO_TYPE;
        if (kind_of(where_clause) != PROD_WHERE_NONE || kind_of(contracts) != PROD_CONTRACTS_NONE)
            flags |= GF_WHERE;
        uint gen = hir_token_pos[up];
        store(gen, GR_ROLE, GROLE_GEN);
        store(gen, GR_END, hir_token_end[body]);
        store(gen, GR_OPEN, hir_token_pos[body]);
        store(gen, GR_OWNER, hir_token_end[params] - 1u);
        store(gen, GR_KIND, flags);
        return;
    }
    if (kind == PROD_FN_BLOCK)
    {
        uint item = kind_of(up_of(up));
        if (item == PROD_ITEM_GEN || item == PROD_PUB_GEN)
            block(node, BK_BODY, 0u);
        return;
    }
    if (kind == PROD_BLOCK)
    {
        if (up_kind == PROD_WHILE_STMT)
            block(node, BK_WHILE, hir_token_pos[up]);
        else if (up_kind == PROD_FOR_STMT)
            block(node, BK_FOR, hir_token_pos[up]);
        else if (up_kind == PROD_ELSE_BLOCK)
            block(node, BK_IF, chain_head(up));
        return;
    }
    if (kind == PROD_IF_BLOCK)
    {
        if (up_kind == PROD_IF_STMT || up_kind == PROD_ELSE_IF)
            block(node, BK_IF, chain_head(up));
        return;
    }
    if (kind == PROD_STMTS_MORE)
    {
        uint rest = sibling(first_child[node]);
        if (valid(rest))
            store(pos, GR_NEXT, hir_token_pos[rest]);
        // A statement list ends with an empty production, so its range
        // includes the `}` after it.
        store(pos, GR_CLOSE, hir_token_end[node] - 1u);
        return;
    }
    if (kind == PROD_LET_STMT)
    {
        uint declared = first_child[node];
        store(pos, GR_ROLE, GROLE_LET);
        store(pos, GR_END, kind_of(declared) == PROD_LET_TYPE ? type_end(first_child[declared]) : 0u);
        return;
    }
    if (kind == PROD_PARAM_NAMED)
    {
        store(pos, GR_ROLE, GROLE_PARAM);
        store(pos, GR_END, type_end(first_child[node]));
        return;
    }
    if (kind == PROD_YIELD && up_kind == PROD_EXPR_STMT)
    {
        uint semicolon = hir_token_end[up] - 1u;
        store(pos, GR_ROLE, GROLE_YIELD);
        store(semicolon, GR_ROLE, GROLE_YIELD_END);
        store(semicolon, GR_OPEN, pos);
    }
}
