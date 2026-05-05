import retag_closes_common;

StructuredBuffer<uint> token_count;
RWStructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> hist_push;
StructuredBuffer<uint> hist_pop;
StructuredBuffer<uint> off_push;
StructuredBuffer<uint> off_pop;
StructuredBuffer<uint> pushes_by_layer;
StructuredBuffer<uint> pops_by_layer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint l = tid.x;
    uint total = token_count[0];
    if (l >= total + 2u)
        return;

    uint npairs = min(hist_push[l], hist_pop[l]);
    uint p0 = off_push[l];
    uint q0 = off_pop[l];

    for (uint r = 0u; r < npairs; r++)
    {
        uint open_i = pushes_by_layer[p0 + r];
        uint close_i = pops_by_layer[q0 + r];
        TokenOut close = tokens_out[close_i];
        uint open_kind = tokens_out[open_i].kind;

        if (close.kind == TK_RPAREN || close.kind == TK_GROUP_RPAREN || close.kind == TK_CALL_RPAREN)
        {
            if (open_kind == TK_GROUP_LPAREN)
                close.kind = TK_GROUP_RPAREN;
            else if (open_kind == TK_CALL_LPAREN)
                close.kind = TK_CALL_RPAREN;
        }
        else if (close.kind == TK_RBRACKET ||
                 close.kind == TK_ARRAY_RBRACKET ||
                 close.kind == TK_INDEX_RBRACKET)
        {
            if (open_kind == TK_ARRAY_LBRACKET)
                close.kind = TK_ARRAY_RBRACKET;
            else if (open_kind == TK_INDEX_LBRACKET)
                close.kind = TK_INDEX_RBRACKET;
        }

        tokens_out[close_i] = close;
    }
}
