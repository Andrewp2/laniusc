// Project imported member calls against the associated-method records in the
// active semantic-interface page.  Associated methods are intentionally not
// ordinary declaration rows: the owner declaration and method name identify a
// member, while its value fields carry the call ABI and stable object symbol.

import dependency_interface;
import hir_records;
import gpu_index;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;

RWStructuredBuffer<uint> call_dependency_library_id;
RWStructuredBuffer<uint> call_dependency_unit_id;
RWStructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> call_dependency_host_service;
RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_KIND_SCALAR = 1u;
static const uint TYPE_WORDS = 9u;
static const uint MEMBER_WORDS = 10u;
static const uint MEMBER_ASSOCIATED_METHOD = 6u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count()
{
    return min(gParams.hir_capacity, compact_hir_count[0u]);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.visible_capacity;
}

bool external_identity(uint token, out uint library_id, out uint unit_id, out uint local_id)
{
    library_id = INVALID;
    unit_id = INVALID;
    local_id = INVALID;
    if (!valid_token(token))
        return false;
    library_id = external_type_library_id[token];
    unit_id = external_type_unit_id[token];
    local_id = external_type_local_index[token];
    return library_id != INVALID && unit_id != INVALID && local_id != INVALID;
}

uint receiver_identity_token(uint receiver_tag, uint receiver_payload, uint raw_receiver)
{
    // Generic imported instances retain their external identity at the
    // instance token. A canonical external reference retains it at the raw
    // expression token. Prefer the ref payload, then the raw receiver.
    if (receiver_tag == 3u && valid_token(receiver_payload) &&
        external_type_library_id[receiver_payload] != INVALID)
        return receiver_payload;
    if (receiver_tag == TYPE_REF_EXTERNAL_CANONICAL && valid_token(raw_receiver) &&
        external_type_library_id[raw_receiver] != INVALID)
        return raw_receiver;
    return valid_token(raw_receiver) && external_type_library_id[raw_receiver] != INVALID
               ? raw_receiver
               : INVALID;
}

uint associated_method_member(
    uint owner_declaration,
    uint method_name_lo,
    uint method_name_hi)
{
    uint count = dependency_member_count();
    for (uint row = 0u; row < count; row += 1u)
    {
        uint base = row * MEMBER_WORDS;
        if (dependency_member_word(base + 0u) != owner_declaration ||
            dependency_member_word(base + 1u) != MEMBER_ASSOCIATED_METHOD ||
            dependency_member_word(base + 3u) != method_name_lo ||
            dependency_member_word(base + 4u) != method_name_hi)
            continue;
        return row;
    }
    return INVALID;
}

void publish_method_result(uint method_token, uint member_i, uint owner_declaration)
{
    uint member_base = member_i * MEMBER_WORDS;
    uint return_type_i = dependency_member_word(member_base + 7u);
    uint type_count = dependency_type_count();
    if (return_type_i >= type_count)
        return;
    uint return_root = canonical_type_roots[return_type_i];
    if (return_root >= type_count)
        return;
    uint return_base = return_root * TYPE_WORDS;
    uint return_kind = dependency_type_word(return_base + 0u);

    // The member's high value is the stable method symbol local index. The
    // owner supplies the defining library and unit identity.
    uint method_local_index = dependency_member_word(member_base + 9u);
    if (method_local_index == INVALID)
        return;
    call_dependency_library_id[method_token] =
        dependency_declaration_library_id(owner_declaration);
    call_dependency_unit_id[method_token] =
        dependency_declaration_unit_id(owner_declaration);
    call_dependency_local_index[method_token] = method_local_index;
    call_dependency_host_service[method_token] = INVALID;
    call_param_count[method_token] = dependency_member_word(member_base + 8u);

    if (return_kind == TYPE_KIND_SCALAR)
    {
        uint scalar = dependency_type_word(return_base + 1u);
        call_return_type[method_token] = scalar;
        call_return_type_token[method_token] = INVALID;
        decl_type_ref_tag[method_token] = TYPE_REF_SCALAR;
        decl_type_ref_payload[method_token] = scalar;
    }
    else
    {
        call_return_type[method_token] = 0u;
        call_return_type_token[method_token] = method_token;
        decl_type_ref_tag[method_token] = TYPE_REF_EXTERNAL_CANONICAL;
        decl_type_ref_payload[method_token] = return_root;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return;

    uint member = compact_hir_payload[call].a;
    if (!valid_hir(member) || compact_hir_core[member].kind != HIR_MEMBER_EXPR)
        return;

    HirPayload member_payload = compact_hir_payload[member];
    uint method_token = member_payload.c;
    uint raw_receiver = member_payload.d;
    if (!valid_token(method_token))
        return;

    uint receiver_tag = method_call_receiver_ref_tag[method_token];
    uint receiver_payload = method_call_receiver_ref_payload[method_token];
    uint identity_token = receiver_identity_token(receiver_tag, receiver_payload, raw_receiver);
    uint library_id;
    uint unit_id;
    uint local_id;
    if (!external_identity(identity_token, library_id, unit_id, local_id))
        return;

    uint owner_declaration = dependency_find_declaration(library_id, unit_id, local_id);
    if (owner_declaration == INVALID)
        return;
    uint name_id = name_id_by_token[method_token];
    if (name_id == INVALID || name_id >= gParams.visible_capacity)
        return;
    uint member_i = associated_method_member(
        owner_declaration,
        name_hash_lo[name_id],
        name_hash_hi[name_id]);
    if (member_i == INVALID)
        return;
    publish_method_result(method_token, member_i, owner_declaration);
}
