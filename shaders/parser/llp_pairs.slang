struct ActionHeader
{
    uint push_len;
    uint emit_len;
    uint pop_tag;
    uint pop_count;
};

struct Params
{
    uint n_tokens;
    uint n_kinds;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_kinds;
StructuredBuffer<ActionHeader> action_table;
RWStructuredBuffer<ActionHeader> out_headers;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (gParams.n_tokens < 2)
        return;
    uint n_pairs = gParams.n_tokens - 1;
    if (i >= n_pairs)
        return;

    uint prev_kind = token_kinds[i];
    uint this_kind = token_kinds[i + 1];

    if (prev_kind >= gParams.n_kinds || this_kind >= gParams.n_kinds)
    { 
        ActionHeader z = { 0, 0, 0, 0 };
        out_headers[i] = z;
        return;
    }

    uint idx = prev_kind * gParams.n_kinds + this_kind;
    out_headers[i] = action_table[idx];
}
