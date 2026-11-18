import codegen.lowering_ir;
import codegen.optimization_ir;
import shared.syntax.hir_records;

static const uint X86_C_ENTRY_BYTES = 63u;
// lea(7), skip jump(2), then the stub's inner call displacement at +44.
static const uint X86_C_ENTRY_REL32_OFFSET = 53u;
static const uint X86_C_ENTRY_PREFIX_BYTES = 9u;

// Function names and paths lower to CALL-shaped rows, but materialize a C
// entry address rather than executing the callee. Counting and scattering
// must agree: applying ordinary-call inlining only during counting invents
// extra producer rows that have no allocated result location.
bool x86_c_entry_call(OptIrNodeCore source, uint source_hir, uint function,
    uint function_count, StructuredBuffer<HirCore> hir,
    StructuredBuffer<SemanticLirFunction> functions)
{
    if (source_hir == 0xffffffffu) return false;
    uint kind = hir[source_hir].kind;
    if (kind != 22u && kind != 33u) return false;
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_CALL_SYMBOL) return true;
    if (opt_ir_op(source) != SEMANTIC_LIR_OP_CALL || function >= function_count) return false;
    uint callee = functions[function].hir_function;
    return callee != 0xffffffffu && hir[callee].kind == 3u;
}
