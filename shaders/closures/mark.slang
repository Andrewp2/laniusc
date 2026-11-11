// Per token: the nesting depth change, whether a closure starts here, and
// the binder role of an identifier.
import gpu_index;
import generated_token_ids;
import closure_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
RWStructuredBuffer<uint4> marks;
RWStructuredBuffer<uint> roles;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint kind_in_file(uint i, uint count, uint file)
{
    if (i >= count || token_file_id[i] != file)
        return 0u;
    return tokens_out[i].kind;
}

// A closure starts at `|` or `||` where a binary operator cannot stand.
bool prefix_position(uint previous)
{
    return tk_paren_open(previous) || tk_comma(previous) || tk_assign(previous) || previous == TK_RETURN ||
           previous == TK_COLON || previous == TK_ARROW;
}

// Whether the innermost bracket open before token `i` is a parenthesis.
bool inside_parentheses(uint i, uint file)
{
    uint closed = 0u;
    uint j = i;
    while (j > 0u)
    {
        j -= 1u;
        if (token_file_id[j] != file)
            return false;
        uint k = tokens_out[j].kind;
        if (tk_close(k))
        {
            closed += 1u;
        }
        else if (tk_open(k))
        {
            if (closed == 0u)
                return tk_paren_open(k);
            closed -= 1u;
        }
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    uint count = token_count[0];
    if (i >= count)
        return;

    uint file = token_file_id[i];
    uint kind = tokens_out[i].kind;
    uint previous = i > 0u ? kind_in_file(i - 1u, count, file) : 0u;
    uint next = kind_in_file(i + 1u, count, file);
    uint after_next = kind_in_file(i + 2u, count, file);

    uint start = (kind == TK_PIPE || kind == TK_OROR) && prefix_position(previous) ? 1u : 0u;
    marks[i] = uint4(tk_depth_delta(kind), start, 0u, 0u);

    uint role = 0u;
    if (kind == TK_IDENT)
    {
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
