// Mark interned names and compact-table flags for HIR value declarations.
//
// The following HIR-name passes use this as GPU-resident input for declaration
// table compaction. This stage consumes only compact HIR payloads and interned
// name ids; compact match payload binders are appended by a dedicated
// family-row pass after this scan. It does not inspect source text or token
// spelling.

import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> hir_value_decl_name_present;
RWStructuredBuffer<uint> hir_visible_decl_flag;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 63u;

static const uint HIR_STMT = 7u;
static const uint HIR_PARAM = 4u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_FOR_STMT = 30u;

static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_dense(uint dense)
{
    return dense != INVALID && dense < active_compact_hir_count();
}

bool valid_decl_name_token(uint token)
{
    if (!valid_token(token))
        return false;

    uint name_id = name_id_by_token[token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return false;

    atomic_u32_or(hir_value_decl_name_present, name_id, 1u);
    return true;
}

uint decl_token_for_hir_node(uint node)
{
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind == HIR_PARAM)
    {
        if (valid_dense(payload.a) && compact_hir_core[payload.a].kind == 3u)
            return payload.c;
    }

    uint stmt_kind = payload.a;
    if ((core.kind == HIR_STMT ||
         core.kind == HIR_LET_STMT ||
         core.kind == HIR_FOR_STMT) &&
        (stmt_kind == STMT_RECORD_KIND_LET ||
         stmt_kind == STMT_RECORD_KIND_CONST ||
         stmt_kind == STMT_RECORD_KIND_FOR))
        return payload.b;

    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (!valid_dense(row))
        return;

    uint decl_token = decl_token_for_hir_node(row);
    hir_visible_decl_flag[row] = valid_decl_name_token(decl_token) ? 1u : 0u;
}
