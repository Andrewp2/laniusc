// Per tree node: the record of the machine construct the node stands for,
// written at the construct's first token. Each word of a record has one
// writer, so the nodes of one construct fill it without a conflict.
import gpu_index;
import generated_parse_production_ids;
import generated_token_ids;
import machine_common;

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
    return node != MC_NONE && node < node_count();
}

uint kind_of(uint node)
{
    return valid(node) ? node_kind[node] : MC_NONE;
}

uint sibling(uint node)
{
    return valid(node) ? next_sibling[node] : MC_NONE;
}

void store(uint token, uint word, uint value)
{
    if (token < gNodes.token_count)
        records[token * REC_WORDS + word] = value;
}

// A node's token range includes the token after it when the node's last
// production is empty. An expression always ends that way.
uint expression_end(uint node)
{
    return hir_token_end[node] - 1u;
}

// A type ends in a token of its own only after `>`, `]` or `!`.
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

    if (kind == PROD_MACHINE)
    {
        uint event = first_child[node];
        uint output = sibling(event);
        uint fields = sibling(output);
        uint states = sibling(fields);
        uint flags = kind_of(up) == PROD_PUB_MACHINE ? FLAG_PUBLIC : 0u;
        uint output_end = 0u;
        if (kind_of(output) == PROD_MACHINE_OUTPUT_SOME)
        {
            uint output_type = first_child[output];
            output_end = type_end(output_type);
            flags |= FLAG_OUTPUT;
            if (kind_of(sibling(output_type)) == PROD_MACHINE_OUTPUT_SOME)
                flags |= FLAG_SECOND_OUTPUT;
        }
        store(pos, REC_ROLE, ROLE_MACHINE);
        store(pos, REC_END, hir_token_end[node]);
        store(pos, REC_EVENT_END, type_end(event));
        store(pos, REC_OUTPUT_END, output_end);
        store(pos, REC_START, valid(states) ? hir_token_pos[states] - 2u : 0u);
        store(pos, REC_FLAGS, flags);
        return;
    }
    if (kind == PROD_MACHINE_STATE)
    {
        uint data = first_child[node];
        uint flags = kind_of(up) == PROD_MACHINE_STATE_FINAL ? FLAG_FINAL : 0u;
        uint block = pos + 2u;
        if (kind_of(data) == PROD_MACHINE_STATE_DATA_SOME)
        {
            flags |= FLAG_DATA;
            block = hir_token_end[data];
        }
        store(pos, REC_ROLE, ROLE_STATE);
        store(pos, REC_END, hir_token_end[node]);
        store(pos, REC_BLOCK, block);
        store(pos, REC_FLAGS, flags);
        return;
    }
    if (kind == PROD_STRUCT_FIELD || kind == PROD_PARAM_NAMED)
    {
        store(pos, REC_ROLE, kind == PROD_STRUCT_FIELD ? ROLE_FIELD : ROLE_DATA);
        store(pos, REC_END, type_end(first_child[node]));
        return;
    }
    if (kind == PROD_MATCH_ARM)
    {
        uint body = sibling(first_child[node]);
        store(pos, REC_ROLE, ROLE_ARM);
        store(pos, REC_END, expression_end(node));
        store(pos, REC_ARROW, valid(body) ? hir_token_pos[body] - 1u : 0u);
        return;
    }
    if (kind == PROD_GOTO || kind == PROD_STAY)
    {
        store(pos, REC_ROLE, ROLE_TRANSITION);
        store(pos, REC_END, expression_end(node));
        return;
    }
    if (kind == PROD_GOTO_ARGS_SOME && kind_of(up) == PROD_GOTO)
    {
        store(hir_token_pos[up], REC_ARGS_CLOSE, hir_token_end[node] - 1u);
        return;
    }
    if (kind == PROD_TRANSITION_OUTPUT_SOME && (kind_of(up) == PROD_GOTO || kind_of(up) == PROD_STAY))
    {
        store(hir_token_pos[up], REC_WITH, pos);
        return;
    }
    uint up_kind = kind_of(up);
    if (up_kind == PROD_ARGS_SOME || up_kind == PROD_ARGS_AFTER_COMMA_MORE)
    {
        // The expression of one call argument.
        if (first_child[up] == node)
        {
            store(pos, REC_ROLE, ROLE_ARGUMENT);
            store(pos, REC_END, expression_end(node));
        }
    }
}
