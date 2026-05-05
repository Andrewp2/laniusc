struct LexParams
{
    uint n;
    uint m;
    uint start_state;
    uint skip0;
    uint skip1;
    uint skip2;
    uint skip3;
};

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

static const uint TK_RPAREN = 5;
static const uint TK_RBRACKET = 21;

static const uint TK_CALL_LPAREN = 28;
static const uint TK_GROUP_LPAREN = 29;
static const uint TK_INDEX_LBRACKET = 30;
static const uint TK_ARRAY_LBRACKET = 31;

static const uint TK_GROUP_RPAREN = 62;
static const uint TK_CALL_RPAREN = 63;
static const uint TK_ARRAY_RBRACKET = 64;
static const uint TK_INDEX_RBRACKET = 65;

inline bool is_open(uint kind)
{
    return kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET;
}

inline bool is_close(uint kind)
{
    return kind == TK_RPAREN || kind == TK_RBRACKET ||
           kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET;
}

inline int delimiter_delta(uint kind)
{
    if (is_open(kind))
        return 1;
    if (is_close(kind))
        return -1;
    return 0;
}
