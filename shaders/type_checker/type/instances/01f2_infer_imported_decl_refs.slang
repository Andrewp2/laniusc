// Preserve the nominal result of an imported value in an unannotated let.
// Dependency canonical rows are page-local, so copy their stable declaration
// identity as well as the tagged reference before later pages are loaded.

import hir_records;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<uint> decl_imported_type_token;
RWStructuredBuffer<uint> external_type_library_id;
RWStructuredBuffer<uint> external_type_unit_id;
RWStructuredBuffer<uint> external_type_local_index;

static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[ForceInline]
uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

bool imported_nominal_token(uint token)
{
    return valid_token(token) &&
        decl_type_ref_tag[token] == TYPE_REF_EXTERNAL_CANONICAL &&
        decl_type_ref_payload[token] != INVALID &&
        external_type_library_id[token] != INVALID &&
        external_type_unit_id[token] != INVALID &&
        external_type_local_index[token] != INVALID;
}

uint first_imported_token(uint node)
{
    if (!valid_hir(node)) return INVALID;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (imported_nominal_token(core.token_start)) return core.token_start;
    if (imported_nominal_token(payload.d)) return payload.d;
    if (core.kind == HIR_NAME_EXPR && valid_hir(payload.b))
    {
        HirCore child = compact_hir_core[payload.b];
        HirPayload child_payload = compact_hir_payload[payload.b];
        if (child.kind == HIR_PATH_EXPR)
        {
            if (imported_nominal_token(child.token_start)) return child.token_start;
            if (imported_nominal_token(child_payload.d)) return child_payload.d;
        }
    }
    return INVALID;
}

uint initializer_token(uint node)
{
    if (!valid_hir(node)) return INVALID;
    HirCore core = compact_hir_core[node];
    if (core.kind == HIR_PATH_EXPR || core.kind == HIR_NAME_EXPR)
        return first_imported_token(node);
    if (core.kind != HIR_CALL_EXPR) return INVALID;
    uint callee = compact_hir_payload[node].a;
    return first_imported_token(callee);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (!valid_hir(node)) return;
    HirCore core = compact_hir_core[node];
    if (core.kind != HIR_STMT && core.kind != HIR_LET_STMT) return;
    HirPayload stmt = compact_hir_payload[node];
    if (stmt.a != STMT_RECORD_KIND_LET || !valid_token(stmt.b) ||
        decl_type_ref_tag[stmt.b] != TYPE_REF_INVALID)
        return;
    // An explicit annotation is authoritative, including one that failed to
    // resolve. Inference only owns a genuinely unannotated binding.
    if (valid_hir(stmt.d)) return;
    uint source = initializer_token(stmt.c);
    if (!imported_nominal_token(source)) return;
    decl_type_ref_tag[stmt.b] = TYPE_REF_EXTERNAL_CANONICAL;
    decl_type_ref_payload[stmt.b] = decl_type_ref_payload[source];
    decl_imported_type_token[stmt.b] = source;
    external_type_library_id[stmt.b] = external_type_library_id[source];
    external_type_unit_id[stmt.b] = external_type_unit_id[source];
    external_type_local_index[stmt.b] = external_type_local_index[source];
}
