// Per token: whether a machine, a state or a transition starts here, and the
// change of bracket depth. The prefix sums of these rows number the machines,
// states and transitions and give each token's depth.
import gpu_index;
import generated_token_ids;
import machine_common;

struct MarkParams
{
    uint token_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

ConstantBuffer<MarkParams> gMarks;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> records;
RWStructuredBuffer<uint4> marks;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (token >= gMarks.token_count)
        return;
    uint role = records[token * REC_WORDS + REC_ROLE];
    uint kind = tokens_out[token].kind;
    bool opens = kind == TK_LPAREN || kind == TK_CALL_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_LBRACKET ||
                 kind == TK_INDEX_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_LBRACE;
    bool closes = kind == TK_RPAREN || kind == TK_RBRACKET || kind == TK_RBRACE;
    marks[token] = uint4(role == ROLE_MACHINE ? 1u : 0u, role == ROLE_STATE ? 1u : 0u,
                         role == ROLE_TRANSITION ? 1u : 0u, opens ? 1u : (closes ? 0xffffffffu : 0u));
}
