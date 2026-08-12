// Publish ordinary HIR declarations by their unique source-token anchor.
//
// The following HIR-name passes use this as GPU-resident input for declaration
// table compaction. Both ordinary declarations and match binders write into
// the same token-indexed descriptor table before one token-domain scan. That
// makes the compact declaration table source ordered without sorting by token.

import hir_records;
import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> hir_value_decl_name_present;
RWStructuredBuffer<uint> hir_visible_decl_flag;
RWStructuredBuffer<uint> hir_visible_decl_source_by_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 68u;

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
    if (!valid_decl_name_token(decl_token))
        return;

    // Zero means no declaration. Ordinary HIR rows use row + 1; the high bit
    // is reserved for compact match-payload rows.
    uint encoded = row + 1u;
    uint prior = atomic_u32_compare_exchange(
        hir_visible_decl_source_by_token,
        decl_token,
        0u,
        encoded);
    if (prior == 0u || prior == encoded)
        hir_visible_decl_flag[decl_token] = 1u;
}
