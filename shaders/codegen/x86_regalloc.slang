struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> reg_map;
RWStructuredBuffer<uint> reg_status;

static const uint PHYS_RAX = 0u;
static const uint PHYS_RCX = 1u;
static const uint PHYS_RDX = 2u;
static const uint PHYS_RBX = 3u;
static const uint PHYS_RSI = 6u;
static const uint PHYS_RDI = 7u;

static const uint VREG_ACC = 0u;
static const uint VREG_SCRATCH = 1u;
static const uint VREG_COUNT = 2u;
static const uint VREG_ARG0 = 3u;
static const uint VREG_ARG1 = 4u;
static const uint VREG_REMAINDER = 5u;
static const uint VREG_COUNT_TOTAL = 6u;

uint active_token_count()
{
    return min(token_count[0u], gParams.n_tokens);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i == 0u)
    {
        reg_map[VREG_ACC] = PHYS_RAX;
        reg_map[VREG_SCRATCH] = PHYS_RBX;
        reg_map[VREG_COUNT] = PHYS_RCX;
        reg_map[VREG_ARG0] = PHYS_RDI;
        reg_map[VREG_ARG1] = PHYS_RSI;
        reg_map[VREG_REMAINDER] = PHYS_RDX;
        reg_status[0u] = VREG_COUNT_TOTAL;
        reg_status[1u] = 1u;
    }

    uint n = active_token_count();
    if (i < n)
    {
        uint decl = visible_decl[i];
        uint pool[6] = { PHYS_RAX, PHYS_RBX, PHYS_RCX, PHYS_RDX, PHYS_RDI, PHYS_RSI };
        uint phys = pool[i % 6u];
        reg_map[VREG_COUNT_TOTAL + i] = decl == 0xffffffffu ? phys : pool[decl % 6u];
    }
}
