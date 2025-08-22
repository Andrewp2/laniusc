StructuredBuffer<uint> token_count;
StructuredBuffer<uint> end_positions;
StructuredBuffer<uint> types_compact;
StructuredBuffer<uint> all_index_compact;
StructuredBuffer<uint> end_positions_all;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};
RWStructuredBuffer<TokenOut> tokens_out;

static const uint TK_IDENT = 1;
static const uint TK_INT = 2;
static const uint TK_WHITE = 3;

static const uint TK_LPAREN = 4;
static const uint TK_RPAREN = 5;
static const uint TK_PLUS = 6;
static const uint TK_STAR = 7;
static const uint TK_ASSIGN = 8;
static const uint TK_SLASH = 9;
static const uint TK_LINE_COMMENT = 10;
static const uint TK_BLOCK_COMMENT = 11;

static const uint TK_LT = 12;
static const uint TK_GT = 13;
static const uint TK_LE = 14;
static const uint TK_GE = 15;
static const uint TK_EQEQ = 16;
static const uint TK_ANDAND = 17;
static const uint TK_OROR = 18;
static const uint TK_NOT = 19;
static const uint TK_LBRACKET = 20;
static const uint TK_RBRACKET = 21;
static const uint TK_LBRACE = 22;
static const uint TK_RBRACE = 23;
static const uint TK_ANGLE_GENERIC = 24;
static const uint TK_AMPERSAND = 25;
static const uint TK_PIPE = 26;
static const uint TK_MINUS = 27;

static const uint TK_CALL_LPAREN = 28;
static const uint TK_GROUP_LPAREN = 29;
static const uint TK_INDEX_LBRACKET = 30;
static const uint TK_ARRAY_LBRACKET = 31;
static const uint TK_STRING = 32;
static const uint TK_FLOAT = 33;
static const uint TK_CHAR = 34;

[shader("compute")]
[numthreads(256, 1, 1)]
void tokens_build(uint3 tid: SV_DispatchThreadID)
{
    uint k = tid.x;
    uint total = token_count[0];
    if (k >= total)
        return;

    uint end_excl = end_positions[k];

    uint all_idx = all_index_compact[k];
    uint all_zero = (all_idx == 0u) ? 0u : (all_idx - 1u);

    uint start = (all_zero == 0u) ? 0u : end_positions_all[all_zero - 1u];

    uint kind = types_compact[k];
    uint prev = (k == 0u) ? 0xFFFFu : types_compact[k - 1];

    bool ends_primary =
        (prev == TK_IDENT) ||
        (prev == TK_INT) ||
        (prev == TK_FLOAT) ||
        (prev == TK_RPAREN) ||
        (prev == TK_RBRACKET) ||
        (prev == TK_RBRACE) ||
        (prev == TK_ANGLE_GENERIC) ||
        (prev == TK_STRING) ||
        (prev == TK_CHAR);

    if (kind == TK_LPAREN)
    {
        kind = ends_primary ? TK_CALL_LPAREN : TK_GROUP_LPAREN;
    }
    else if (kind == TK_LBRACKET)
    {
        kind = ends_primary ? TK_INDEX_LBRACKET : TK_ARRAY_LBRACKET;
    }

    // 🤖 Write final token
    TokenOut t;
    t.kind = kind;
    t.start = start;
    t.len = end_excl - start;
    tokens_out[k] = t;
}
