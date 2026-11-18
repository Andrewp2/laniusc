// The symbolic context of an unsuffixed numeric literal in a generic body.
//
// `literal_context_type_by_hir` holds a literal's checked scalar context, or
// 0 for none (the syntax default: i32 or f32). When the literal's only
// context is a value of a type parameter, as in `a + 1` with `a: T` or
// `return 1.5;` in a function returning `T`, it holds that parameter's
// reference instead: LITERAL_CONTEXT_SYMBOLIC | the parameter's declaration
// token, the payload of its TYPE_REF_GENERIC_PARAM reference.
//
// The word is never a scalar identity (scalar_is_integer/float are false
// for it), so readers that need a scalar see no context. The literal's row
// takes the parameter reference (project_checked_operator_references), each instance realizes
// it (instance table), and validate_instance_table_operands checks the literal's kind, range and
// float status against that instance's scalar. The template has no type for
// the literal, so the template checks do not apply one.
import shared.semantics.primitive_types;

public static const uint LITERAL_CONTEXT_SYMBOLIC = 0x80000000u;

public bool literal_context_is_symbolic(uint context)
{
    return (context & LITERAL_CONTEXT_SYMBOLIC) != 0u;
}

// The parameter declaration token of a symbolic context.
public uint literal_context_parameter(uint context)
{
    return context & ~LITERAL_CONTEXT_SYMBOLIC;
}

// The symbolic context of reference (tag, payload), or 0 when it is not a
// type parameter reference (TYPE_REF_GENERIC_PARAM, 2).
public uint literal_symbolic_context_of(uint tag, uint payload, uint tokens)
{
    return tag == 2u && payload < tokens && payload < LITERAL_CONTEXT_SYMBOLIC
        ? LITERAL_CONTEXT_SYMBOLIC | payload : 0u;
}

// The scalar a reader of `literal_context_type_by_hir` sees as the literal's
// effective type: the context when it is a scalar of the literal's kind,
// else the syntax default.
public uint literal_effective_scalar(uint context, bool floating)
{
    if (floating ? scalar_is_float(context) : scalar_is_integer(context)) return context;
    return floating ? SCALAR_F32 : SCALAR_I32;
}
