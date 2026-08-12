// Project imported member calls against the associated-method records in the
// active semantic-interface page.  Associated methods are intentionally not
// ordinary declaration rows: the owner declaration and method name identify a
// member, while its value fields carry the call ABI and stable object symbol.

import dependency_interface;
import byte_packing;
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

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> module_value_path_associated_method_token;
StructuredBuffer<uint> module_value_path_associated_receiver_token;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<NameSpan> name_spans;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
StructuredBuffer<uint> dependency_visible_owner_module;
StructuredBuffer<uint> dependency_visible_decl;
StructuredBuffer<uint> dependency_visible_lookup;
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
static const uint TYPE_NAMESPACE = 3u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_KIND_SCALAR = 1u;
static const uint TYPE_WORDS = 9u;
static const uint MEMBER_WORDS = 10u;
static const uint MEMBER_ASSOCIATED_METHOD = 6u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint mix(uint hash, uint value)
{
    hash ^= value;
    hash *= 16777619u;
    return hash;
}

uint dependency_name_byte(uint byte_i)
{
    uint word = dependency_name_byte_word(byte_i >> 2u);
    return (word >> ((byte_i & 3u) * 8u)) & 0xffu;
}

uint local_name_byte(NameSpan span, uint byte_i)
{
    return span.kind == NAME_KIND_LANGUAGE_SYMBOL
        ? byte_address_load_u8(language_symbol_bytes, span.start + byte_i)
        : byte_address_load_u8_bounded(source_bytes, span.start + byte_i, gParams.source_len);
}

bool exact_type_name(uint name_id, uint owner_module, uint visible_i)
{
    if (visible_i >= gParams.visible_capacity ||
        dependency_visible_owner_module[visible_i] != owner_module)
        return false;
    uint declaration_i = dependency_visible_decl[visible_i];
    if (declaration_i >= dependency_declaration_count()) return false;
    uint base = declaration_i * 14u;
    if (dependency_declaration_word(base + 5u) != TYPE_NAMESPACE ||
        dependency_declaration_word(base + 1u) != name_hash_lo[name_id] ||
        dependency_declaration_word(base + 2u) != name_hash_hi[name_id])
        return false;
    NameSpan span = name_spans[name_id];
    uint start = dependency_declaration_word(base + 3u);
    uint len = dependency_declaration_word(base + 4u);
    if (span.len != len || len > 64u) return false;
    for (uint byte_i = 0u; byte_i < 64u; byte_i += 1u)
    {
        if (byte_i >= len) break;
        if (local_name_byte(span, byte_i) != dependency_name_byte(start + byte_i))
            return false;
    }
    return true;
}

bool module_prefix_equal(uint path_i, uint prefix_count, uint module_i)
{
    uint module_base = module_i * 2u;
    uint dependency_segment = dependency_module_word(module_base);
    if (dependency_module_word(module_base + 1u) != prefix_count || prefix_count > 8u)
        return false;
    uint first = path_segment_base[path_i];
    for (uint segment_i = 0u; segment_i < 8u; segment_i += 1u)
    {
        if (segment_i >= prefix_count) break;
        uint name_id = path_segment_name_id[first + segment_i];
        uint segment_base = (dependency_segment + segment_i) * 4u;
        if (name_hash_lo[name_id] != dependency_module_segment_word(segment_base) ||
            name_hash_hi[name_id] != dependency_module_segment_word(segment_base + 1u))
            return false;
    }
    return true;
}

uint associated_receiver_declaration(uint path_i)
{
    if (path_i >= gParams.path_capacity) return INVALID;
    uint count = path_segment_count[path_i];
    if (count < 2u) return INVALID;
    uint first = path_segment_base[path_i];
    uint name_id = path_segment_name_id[first + count - 2u];
    uint owner_module = path_owner_module_id[path_i];
    if (name_id == INVALID || owner_module == INVALID) return INVALID;
    uint hash = mix(2166136261u, owner_module);
    hash = mix(hash, TYPE_NAMESPACE);
    hash = mix(hash, name_hash_lo[name_id]);
    hash = mix(hash, name_hash_hi[name_id]);
    uint mask = gParams.lookup_capacity - 1u;
    uint slot = hash & mask;
    uint match = INVALID;
    for (uint probe = 0u; probe < gParams.lookup_capacity; probe += 1u)
    {
        uint visible_i = dependency_visible_lookup[slot];
        if (visible_i == INVALID) break;
        if (exact_type_name(name_id, owner_module, visible_i))
        {
            uint declaration_i = dependency_visible_decl[visible_i];
            uint module_i = dependency_declaration_word(declaration_i * 14u);
            if (module_prefix_equal(path_i, count - 2u, module_i))
            {
                if (match != INVALID && match != declaration_i) return INVALID;
                match = declaration_i;
            }
        }
        slot = (slot + 1u) & mask;
    }
    return match;
}

uint active_hir_count()
{
    return min(gParams.hir_capacity, compact_hir_count[0u]);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_count();
}

uint path_node_for_callee(uint callee)
{
    if (!valid_hir(callee)) return INVALID;
    if (compact_hir_core[callee].kind == HIR_PATH_EXPR) return callee;
    if (compact_hir_core[callee].kind != HIR_NAME_EXPR) return INVALID;
    uint child = compact_hir_links[callee].first_child;
    return valid_hir(child) && compact_hir_core[child].kind == HIR_PATH_EXPR
        ? child : INVALID;
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
    // The callable identity and arity do not depend on return-type
    // canonicalization. Publish them first so a malformed return record cannot
    // turn an otherwise resolved dependency method into a local lookup miss.
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

    uint return_type_i = dependency_member_word(member_base + 7u);
    uint type_count = dependency_type_count();
    if (return_type_i >= type_count)
        return;
    uint return_root = canonical_type_roots[return_type_i];
    if (return_root >= type_count)
        return;
    uint return_base = return_root * TYPE_WORDS;
    uint return_kind = dependency_type_word(return_base + 0u);

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

    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee))
        return;

    HirCore callee_core = compact_hir_core[callee];
    HirPayload callee_payload = compact_hir_payload[callee];
    uint method_token = INVALID;
    uint raw_receiver = INVALID;
    uint receiver_declaration = INVALID;
    if (callee_core.kind == HIR_MEMBER_EXPR)
    {
        method_token = callee_payload.c;
        raw_receiver = callee_payload.d;
    }
    else
    {
        uint path_node = path_node_for_callee(callee);
        uint path = valid_hir(path_node) ? path_id_by_owner_hir[path_node] : INVALID;
        uint owner_token = path < gParams.path_capacity
            ? path_owner_token[path] : callee_core.token_start;
        if (valid_token(owner_token))
            method_token = module_value_path_associated_method_token[owner_token];
        if (valid_token(method_token))
            raw_receiver = module_value_path_associated_receiver_token[method_token];
        receiver_declaration = associated_receiver_declaration(path);
    }
    if (!valid_token(method_token))
        return;

    uint owner_declaration = receiver_declaration;
    if (owner_declaration == INVALID)
    {
        uint receiver_tag = method_call_receiver_ref_tag[method_token];
        uint receiver_payload = method_call_receiver_ref_payload[method_token];
        uint identity_token = receiver_identity_token(receiver_tag, receiver_payload, raw_receiver);
        uint library_id;
        uint unit_id;
        uint local_id;
        if (!external_identity(identity_token, library_id, unit_id, local_id))
            return;
        owner_declaration = dependency_find_declaration(library_id, unit_id, local_id);
    }
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
