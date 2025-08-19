// shaders/lexer/retag_calls_and_arrays.slang
// Retag "(" and "[" into CALL/GROUP and INDEX/ARRAY based only on the
// previous *kept* token kind. Operates on the compacted KEPT kinds buffer.
//
// Dispatch can over-shoot; we early-return when tid.x >= token_count[0].
//
// NOTE: Constants here must match src/lexer/tables/tokens.rs

// ---------- Token kind ids (keep in sync with Rust enum reprs) ----------
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

// NEW retagged kinds
static const uint TK_CALL_LPAREN = 28;
static const uint TK_GROUP_LPAREN = 29;
static const uint TK_INDEX_LBRACKET = 30;
static const uint TK_ARRAY_LBRACKET = 31;
static const uint TK_STRING = 32;
static const uint TK_FLOAT = 33;
static const uint TK_CHAR = 34;

// ---------- Bindings ----------
struct Params
{
    uint n;
    uint m;
    uint start_state;
    uint skip0;
    uint skip1;
    uint skip2;
    uint skip3;
};
ConstantBuffer<Params> gParams;

// Number of *kept* tokens after compaction.
StructuredBuffer<uint> token_count;

// Compacted kinds for KEPT tokens. We rewrite this buffer in place.
RWStructuredBuffer<uint> types_compact;

[shader("compute")]
[numthreads(256, 1, 1)]
void retag_calls_and_arrays(uint3 tid: SV_DispatchThreadID)
{
    uint k = tid.x;
    uint total = token_count[0];
    if (k >= total)
        return;

    uint kind = types_compact[k];
    uint prev = (k == 0) ? 0xFFFFu : types_compact[k - 1];

    // ENDS_PRIMARY := { IDENT, INT, FLOAT, STRING, CHAR, RPAREN, RBRACKET, RBRACE, ANGLE_GENERIC }
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
        types_compact[k] = ends_primary ? TK_CALL_LPAREN : TK_GROUP_LPAREN;
        return;
    }
    if (kind == TK_LBRACKET)
    {
        types_compact[k] = ends_primary ? TK_INDEX_LBRACKET : TK_ARRAY_LBRACKET;
        return;
    }
}
