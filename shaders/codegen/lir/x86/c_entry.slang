import codegen.lowering_ir;
import codegen.optimization_ir;
import hir_records;

// Function names and paths lower to CALL-shaped rows, but materialize a C
// entry address rather than executing the callee. Counting and scattering
// must agree: applying ordinary-call inlining only during counting invents
// extra producer rows that have no allocated result location.
bool x86_c_entry_call(OptIrNodeCore source, uint source_hir, uint function,
    uint function_count, StructuredBuffer<HirCore> hir,
    StructuredBuffer<SemanticLirFunction> functions)
{
    if (opt_ir_op(source) != SEMANTIC_LIR_OP_CALL || function >= function_count ||
        source_hir == 0xffffffffu) return false;
    uint kind = hir[source_hir].kind;
    uint callee = functions[function].hir_function;
    return (kind == 22u || kind == 33u) && callee != 0xffffffffu &&
        hir[callee].kind == 3u;
}
