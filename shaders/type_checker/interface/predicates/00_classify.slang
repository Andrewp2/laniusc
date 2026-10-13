// Select accepted predicates owned by exported callables. Source-order scans
// assign durable rows; names and GPU-local ids never cross the artifact boundary.
import hir_records;
import atomics;
import type_checker.interface.method_parameters;
import type_checker.type.instances.generic_param_lookup;

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<HirPredicate> compact_predicates;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> interface_implementation_index_by_hir;
StructuredBuffer<uint> interface_implementation_total;
StructuredBuffer<uint> interface_type_seed_owner;
StructuredBuffer<uint> predicate_owner_node;
StructuredBuffer<uint> predicate_subject_token;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> predicate_bound_arg_count;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_lookup_state;
RWStructuredBuffer<uint> interface_predicate_flag;
RWStructuredBuffer<uint> interface_predicate_argument_count;
RWStructuredBuffer<uint> interface_predicate_owner;
RWStructuredBuffer<uint> interface_predicate_scope;
RWStructuredBuffer<uint> interface_predicate_subject_row;
RWStructuredBuffer<uint> interface_status;
#define LEXICAL_HIR_CAPACITY gParams.hir_capacity
#define LEXICAL_TOKEN_CAPACITY gParams.token_capacity
#include "../../type/instances/lexical_parameter_lookup.slang"
static const uint INVALID = 0xffffffffu;
void fail(uint row, uint detail)
{
    atomic_u32_or(interface_status, 0u, 65536u);
    atomic_u32_min(interface_status, 1u, row);
    atomic_u32_min(interface_status, 2u, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    uint rows; uint stride;
    interface_predicate_flag.GetDimensions(rows, stride);
    uint count = compact_predicate_count[0u];
    if (count > active || count > rows)
    { if (row == 0u) fail(row, 15u); return; }
    if (row >= count) return;
    interface_predicate_flag[row] = 0u;
    interface_predicate_argument_count[row] = 0u;
    interface_predicate_owner[row] = INVALID;
    interface_predicate_scope[row] = 0u;
    interface_predicate_subject_row[row] = INVALID;
    HirPredicate predicate = compact_predicates[row];
    if ((predicate.metadata & 255u) != 1u) return;
    uint owner = predicate.owner;
    if (owner >= active) { fail(row, 1u); return; }
    uint exported = public_decl_index_by_hir[owner];
    uint scope = 0u;
    if (exported == INVALID)
    {
        uint implementation = INVALID;
        uint map_rows; uint stride;
        interface_implementation_index_by_hir.GetDimensions(map_rows, stride);
        if (compact_hir_core[owner].kind == 35u)
        {
            implementation = owner;
            scope = 0xc0000000u | owner;
        }
        else
        {
            uint method = interface_method_for_function(owner,
                min(compact_method_count[0u], active), compact_method_cores);
            if (method == INVALID) return;
            HirMethodCore core = compact_method_cores[method];
            HirMethodSignature signature = compact_method_signatures[method];
            exported = interface_trait_method_owner(core, active, compact_hir_core,
                compact_hir_payload, public_decl_index_by_hir);
            if (exported == INVALID)
            {
                if (!interface_public_inherent_method(signature)) return;
                implementation = core.impl_node;
            }
            scope = 0x80000000u | owner;
        }
        if (implementation != INVALID)
        {
            uint link = implementation < min(active, map_rows)
                ? interface_implementation_index_by_hir[implementation] : 0u;
            if (link == 0u) return;
            if (link > interface_implementation_total[0u]) { fail(row, 2u); return; }
            exported = 0x80000000u | (link - 1u);
        }
        if (exported == INVALID) return;
    }
    if (predicate.bound >= active || ((exported & 0x80000000u) == 0u && exported >= gParams.decl_capacity))
    { fail(row, 2u); return; }
    uint bound = predicate.bound;
    if (predicate_owner_node[bound] != owner || predicate_status[bound] != 0u ||
        predicate_bound_reference[bound] == INVALID || predicate_bound_arg_count[bound] > 32u)
    { fail(row, 3u); return; }
    uint subject = predicate_subject_token[bound];
    if (subject != predicate.subject || subject >= gParams.token_capacity)
    { fail(row, 4u); return; }
    uint parameter = lexical_parameter_row(bound, subject, 1u);
    if (parameter >= min(generic_param_count_out[0u], gParams.token_capacity))
    { fail(row, 5u); return; }
    interface_predicate_owner[row] = exported;
    interface_predicate_scope[row] = scope;
    interface_predicate_subject_row[row] = parameter;
    interface_predicate_argument_count[row] = predicate_bound_arg_count[bound];
    interface_predicate_flag[row] = 1u;
}
