// The calls of the instance table's virtual rows (D3; instance_table.slang):
// one lane per virtual row. A call row of an entry (F, E) names what the call
// reaches under E, as the closure found it:
//
// - a call of a local generic body: its callee's instance, the callee row
//   under the call's environment substituted by E (closure_instance_env, as
//   03_expand inserts it), which is that instance's entry;
// - a bound-member call: the implementation method its receiver E(P)
//   selects (bound_route.slang, as 03c routes it): a generic method's
//   instance entry, or a nongeneric method's row;
// - a generic call into a dependency: marked, for D7, when the checked call
//   record keeps it as a dependency callable (semantic/artifact/00_calls,
//   which runs earlier; host retention reads the same words): an imported
//   enum's constructor, an intrinsic or a host service keeps its callee.
//
// Every other row, and a call of a nongeneric function, keeps the template's
// callee (IT_CALL_NONE). A call the table cannot name is IT_CALL_UNRESOLVED:
// lowering an instance over the table needs every call named.
import hir_records;
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.substitution.call_env;
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;
import type_checker.methods.lookup;
import checked_semantic_artifact;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint CALLABLE_DEPENDENCY = 3u;

#include "closure_calls.slang"
#include "bound_route.slang"

// The entry, as an IT_CALL_ENTRY call, of function row `function` under
// tagged environment `env`; IT_CALL_UNRESOLVED when the table has none.
uint2 entry_call(uint function, uint env)
{
    if (!ct_is_record(env)) return uint2(IT_CALL_UNRESOLVED, 0u);
    uint entry = it_find_entry(function, env, instance_table_counts[IT_COUNT_ENTRIES]);
    return entry == IT_NO_ENTRY ? uint2(IT_CALL_UNRESOLVED, 0u) : uint2(IT_CALL_ENTRY, entry);
}

// The method token of call `call`, as methods/09 reads it: its callee
// member's name, or the leaf of a qualified callee path `P::member`; INVALID
// for any other callee.
uint member_token(uint call)
{
    uint callee = compact_hir_payload[call].a;
    if (!valid_node(callee)) return INVALID;
    if (compact_hir_core[callee].kind == HIR_MEMBER_EXPR) return compact_hir_payload[callee].c;
    uint path = compact_hir_core[callee].kind == HIR_NAME_EXPR
        ? compact_hir_links[callee].first_child : callee;
    if (!valid_node(path) || compact_hir_core[path].kind != HIR_PATH_EXPR) return INVALID;
    HirCore core = compact_hir_core[path];
    return core.token_end <= core.token_start + 1u ? INVALID : core.token_end - 1u;
}

// The call template row `call` makes under the entry's tagged environment
// `caller`.
uint2 row_call(uint call, uint caller)
{
    if (!valid_node(call) || compact_hir_core[call].kind != HIR_CALL_EXPR) return uint2(IT_CALL_NONE, 0u);
    CtSpare subst_spare = ct_spare_none();
    CtSpare env_spare = ct_spare_none();
    uint token;
    uint callee;
    uint2 masks;
    if (closure_call(call, token, callee, masks))
        return entry_call(callee, closure_instance_env(token, callee, masks, caller, subst_spare, env_spare));
    if (closure_bound_call(call, token))
    {
        uint env;
        uint selected = route_bound_call(token, caller, subst_spare, env_spare, env);
        if (selected == INVALID) return uint2(IT_CALL_UNRESOLVED, 0u);
        if (env == CT_NONE) return uint2(IT_CALL_METHOD, selected);
        return entry_call(fn_hir_by_decl_token[compact_method_cores[selected].name_token], env);
    }
    // Any other call on a type parameter (`value.member(...)` or
    // `P::member(...)`) is a bound-member call that a replay routes outside
    // this unit's implementations (an imported trait, or an implementation
    // elsewhere): not named yet.
    uint member = member_token(call);
    if (valid_token(member) && method_call_name_id[member] != INVALID &&
        method_call_receiver_ref_tag[member] == TYPE_REF_GENERIC_PARAM)
        return uint2(IT_CALL_UNRESOLVED, 0u);
    token = call_token(call);
    if (!valid_token(token)) return uint2(IT_CALL_NONE, 0u);
    uint2 counts = required_callable_generic_counts(token);
    if ((counts.x | counts.y) == 0u) return uint2(IT_CALL_NONE, 0u);
    if (call_dependency_library_id[token] == INVALID) return uint2(IT_CALL_UNRESOLVED, 0u);
    CheckedCallArtifact record = semantic_calls_by_hir[call];
    return record.callable_kind == CALLABLE_DEPENDENCY && record.dependency_host_service == INVALID
        ? uint2(IT_CALL_DEPENDENCY, 0u) : uint2(IT_CALL_NONE, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint rows = instance_table_counts[IT_COUNT_FLAGS] != 0u ? 0u
        : min(instance_table_counts[IT_COUNT_ROWS], it_row_capacity());
    if (row >= rows) return;
    uint index = it_entry_of_row(row, instance_table_counts[IT_COUNT_ENTRIES]);
    uint4 entry = instance_table[2u * index];
    uint2 call = uint2(IT_CALL_NONE, 0u);
    // Only this job's own bodies are templates today (IT_SOURCE_LOCAL).
    if (instance_table[2u * index + 1u].z == IT_SOURCE_LOCAL) call = row_call(entry.x + (row - entry.w), entry.z);
    instance_row_calls[row] = call;
}
