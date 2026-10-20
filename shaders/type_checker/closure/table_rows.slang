// Realized expression types of the instance table's virtual rows
// (instance_table.slang). One lane per virtual row: its template row's
// expression reference, substituted under the entry's tagged environment
// and realized as checked rows. A closed reference is kept as it is. A row
// whose realization meets a row another lane is realizing stays pending for
// the next dispatch (06_table_rows); the final dispatch (06a) fails it
// instead. Included by both entry files.
import hir_records;
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.substitution.call_env;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;
import type_checker.methods.lookup;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint HIR_MATCH_EXPR = 34u;
static const uint TYPE_REF_INVALID = 0u;
// Failure codes beside ct_realize's (CT_REALIZE_*).
static const uint ROW_FAILED_REFERENCE = 0x100u;
static const uint ROW_FAILED_SUBSTITUTION = 0x200u;

#include "closure_calls.slang"
#include "bound_route.slang"

// The expression reference of a template row. Every template is a local
// body today (source IT_SOURCE_LOCAL: this job's HIR); a dependency's
// bodies (D_PLAN D7c) will be a second source read here.
//
// A match expression whose result is symbolic keeps no expression type in
// the template (its scalar cache is empty); its checked type is the match
// token's declared type, which 01_expression_refs prefers once concrete. The
// template's symbolic declared type stands for it here.
uint2 template_expr_ref(uint source, uint template_row)
{
    if (source != IT_SOURCE_LOCAL) return uint2(INVALID, 0u);
    uint2 reference = uint2(semantic_expr_ref_tag_by_hir[template_row],
        semantic_expr_ref_payload_by_hir[template_row]);
    if (reference.x != TYPE_REF_INVALID) return reference;
    HirCore core = compact_hir_core[template_row];
    uint tokens; uint stride;
    decl_type_ref_tag.GetDimensions(tokens, stride);
    if (core.kind == HIR_MATCH_EXPR && core.token_start < tokens &&
        decl_type_ref_tag[core.token_start] != TYPE_REF_INVALID)
        return uint2(decl_type_ref_tag[core.token_start], decl_type_ref_payload[core.token_start]);
    return reference;
}

void fail_row(uint row, uint failure)
{
    instance_row_refs[row] = uint2(IT_ROW_FAILED, failure);
    uint ignored;
    InterlockedAdd(instance_table_counts[IT_COUNT_FAILED], 1u, ignored);
}


// A bound-member call keeps no type in the template: its callee is the
// trait's required member. A copy replay routes it to the implementation
// method its concrete receiver selects (methods/09) and types the call with
// that method's return type. The table routes it the same way (bound_route,
// as 03c does) on the receiver substituted under the entry's environment:
// the next term is the selected method's declared return type, under the
// routed environment. False when the route is unknown.
bool route_row(uint token, uint receiver, inout uint reference, inout uint env)
{
    if (!ct_is_resolved(receiver)) return false;
    CtSpare env_spare = ct_spare_none();
    uint routed;
    uint selected = route_bound_receiver(token, receiver, env_spare, routed);
    if (selected == INVALID || (routed != CT_NONE && !ct_is_record(routed))) return false;
    uint candidate = compact_method_cores[selected].name_token;
    if (!valid_token(candidate)) return false;
    uint result = ct_ref(fn_return_ref_tag[candidate], fn_return_ref_payload[candidate]);
    if (!ct_is_resolved(result) || (routed == CT_NONE && !ct_closed(result))) return false;
    reference = result;
    env = routed;
    return true;
}

void realize_row(uint row, bool final_dispatch)
{
    uint rows = instance_table_counts[IT_COUNT_FLAGS] != 0u ? 0u
        : min(instance_table_counts[IT_COUNT_ROWS], it_row_capacity());
    if (row >= rows || instance_row_refs[row].x != 0u) return;
    uint index = it_entry_of_row(row, instance_table_counts[IT_COUNT_ENTRIES]);
    uint4 entry = instance_table[2u * index];
    uint template_row = entry.x + (row - entry.w);
    uint source = instance_table[2u * index + 1u].z;
    uint2 template_ref = template_expr_ref(source, template_row);
    uint tag = template_ref.x;
    uint payload = template_ref.y;
    if (tag == INVALID)
    {
        fail_row(row, ROW_FAILED_REFERENCE);
        return;
    }
    uint reference = ct_ref(tag, payload);
    // An untyped bound-member call substitutes twice: its receiver, then
    // the routed method's return type (one substitution site).
    uint token = INVALID;
    uint steps = tag == TYPE_REF_INVALID && source == IT_SOURCE_LOCAL && valid_node(template_row) &&
        closure_bound_call(template_row, token) ? 2u : 1u;
    if (steps == 2u) reference = bound_call_receiver(token);
    // A row without a type, or with a closed one, reads as the template's.
    else if (reference == CT_UNKNOWN || ct_closed(reference))
    {
        instance_row_refs[row] = uint2(tag + 1u, payload);
        return;
    }
    CtSpare spare = ct_spare_none();
    uint env = entry.z;
    uint bound = CT_UNKNOWN;
    bool routed = true;
    for (uint step = 0u; step < steps; step++)
    {
        if (routed) bound = ct_subst(SourceSlots(), env, reference, true, spare);
        if (routed && step + 1u < steps) routed = route_row(token, bound, reference, env);
    }
    // An unknown route leaves the row as the template's (untyped).
    if (!routed)
    {
        instance_row_refs[row] = uint2(tag + 1u, payload);
        return;
    }
    if (!ct_is_resolved(bound))
    {
        fail_row(row, ROW_FAILED_SUBSTITUTION);
        return;
    }
    uint failure;
    uint2 operand = ct_realize(bound, failure);
    if (failure == CT_REALIZE_BUSY && !final_dispatch) return;
    if (failure != 0u)
    {
        fail_row(row, failure);
        return;
    }
    instance_row_refs[row] = uint2(operand.x + 1u, operand.y);
}
