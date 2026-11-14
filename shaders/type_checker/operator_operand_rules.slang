// Operand rules of operators, conditions and indexing, over checked scalar
// type codes. One definition serves the template rows
// (conditions/compact_expr) and each instance of a generic body
// (closure/06c_table_operands), so both report the same LNC0006 for the
// same operand type. TY_UNKNOWN passes every rule: it is an operand whose
// type is not resolved here (a type parameter in a template, or a type
// another pass checks), never a resolved type that is not a scalar. A
// resolved aggregate is one of the OPR_TY_NAMED / OPR_TY_SEQUENCE classes
// (operator_operand_type), which take no arithmetic, negation, condition or
// index role. References keep the classification the scalar cache gives
// them; a reference row without one stays unknown here.
import primitive_types;

public static const uint OPR_TY_UNKNOWN = 0u;
public static const uint OPR_TY_BOOL = 2u;
public static const uint OPR_TY_INT = 3u;
public static const uint OPR_TY_CHAR = 6u;
public static const uint OPR_TY_STRING = 7u;
public static const uint OPR_TY_POINTER = 8u;
public static const uint OPR_TY_ARRAY_BASE = 128u;
public static const uint OPR_TY_STRUCT_BASE = 4096u;
public static const uint OPR_TY_GENERIC_BASE = 8192u;
// Resolved non-scalar operand classes. They are outside every scalar set and
// every legacy code range, and a detail encodes them as 0.
public static const uint OPR_TY_NAMED = 0xfffffff0u;     // struct or enum
public static const uint OPR_TY_SEQUENCE = 0xfffffff1u;  // array or slice

public static const uint OPR_TYPE_REF_SCALAR = 1u;
public static const uint OPR_TYPE_REF_INSTANCE = 3u;
public static const uint OPR_INSTANCE_NAMED = 1u;
public static const uint OPR_INSTANCE_ARRAY = 2u;
public static const uint OPR_INSTANCE_SLICE = 3u;

public static const uint OPR_EXPR_NOT = 6u;
public static const uint OPR_EXPR_NEG = 13u;
public static const uint OPR_EXPR_EQ = 7u;
public static const uint OPR_EXPR_NE = 8u;
public static const uint OPR_EXPR_LT = 9u;
public static const uint OPR_EXPR_GT = 10u;
public static const uint OPR_EXPR_LE = 11u;
public static const uint OPR_EXPR_GE = 12u;
public static const uint OPR_EXPR_ADD = 14u;
public static const uint OPR_EXPR_SUB = 15u;
public static const uint OPR_EXPR_MUL = 16u;
public static const uint OPR_EXPR_AND = 17u;
public static const uint OPR_EXPR_OR = 18u;
public static const uint OPR_EXPR_MOD = 19u;
public static const uint OPR_EXPR_DIV = 20u;
public static const uint OPR_EXPR_BIT_OR = 21u;
public static const uint OPR_EXPR_BIT_XOR = 22u;
public static const uint OPR_EXPR_BIT_AND = 23u;
public static const uint OPR_EXPR_SHL = 24u;
public static const uint OPR_EXPR_SHR = 25u;

// Which operand a binary rule rejects (operator_binary_violation).
public static const uint OPR_OPERAND_NONE = 0u;
public static const uint OPR_OPERAND_LEFT = 1u;
public static const uint OPR_OPERAND_RIGHT = 2u;

public bool operator_is_array_type(uint ty)
{
    return ty == OPR_TY_SEQUENCE || (ty >= OPR_TY_ARRAY_BASE && ty < OPR_TY_STRUCT_BASE) ||
           (ty >= OPR_TY_ARRAY_BASE + OPR_TY_GENERIC_BASE && ty < OPR_TY_NAMED);
}

public bool operator_is_aggregate(uint ty)
{
    return ty == OPR_TY_NAMED || ty == OPR_TY_SEQUENCE;
}

// An operand's type class from its scalar code and its complete checked
// reference: the scalar when it is a known scalar, OPR_TY_NAMED or
// OPR_TY_SEQUENCE for a resolved struct, enum, array or slice instance, and
// OPR_TY_UNKNOWN otherwise (unresolved, a type parameter, a reference).
public uint operator_operand_type(uint scalar, uint tag, uint payload,
    StructuredBuffer<uint> type_instance_kind)
{
    if (scalar_is_known(scalar)) return scalar;
    if (tag == OPR_TYPE_REF_SCALAR && scalar_is_known(payload)) return payload;
    if (tag != OPR_TYPE_REF_INSTANCE) return OPR_TY_UNKNOWN;
    uint rows; uint stride;
    type_instance_kind.GetDimensions(rows, stride);
    if (payload >= rows) return OPR_TY_UNKNOWN;
    uint kind = type_instance_kind[payload];
    if (kind == OPR_INSTANCE_NAMED) return OPR_TY_NAMED;
    if (kind == OPR_INSTANCE_ARRAY || kind == OPR_INSTANCE_SLICE) return OPR_TY_SEQUENCE;
    return OPR_TY_UNKNOWN;
}

// The code of `ty` in an ERR_ASSIGN_MISMATCH detail byte: aggregates have
// no byte code, and the message names no type for them.
public uint operator_detail_code(uint ty)
{
    return ty < 256u ? ty : 0u;
}

public bool operator_assignable_to_int(uint ty)
{
    return ty == OPR_TY_UNKNOWN || scalar_is_integer(ty);
}

// The RHS of p += n or p -= n is an integer offset, not the value stored
// into p. HIR assignment forms 2 and 3 are ADD and SUB (SET is 1).
public bool operator_pointer_offset_assignment(uint assignment, uint target, uint value)
{
    return (assignment == 2u || assignment == 3u) && target == OPR_TY_POINTER && scalar_is_integer(value);
}

public bool operator_numeric_operand_ok(uint ty)
{
    return ty == OPR_TY_UNKNOWN || scalar_is_integer(ty) || scalar_is_float(ty);
}

// Structs and enums compare by value; arrays, slices and strings do not.
public bool operator_equality_operand_ok(uint ty)
{
    return ty == OPR_TY_UNKNOWN || (!operator_is_array_type(ty) && ty != OPR_TY_STRING);
}

// Negation takes an integer or a float.
public bool operator_negation_operand_ok(uint ty)
{
    return operator_numeric_operand_ok(ty);
}

public bool operator_integer_binary(uint form)
{
    return form == OPR_EXPR_MOD || form == OPR_EXPR_BIT_OR ||
           form == OPR_EXPR_BIT_XOR || form == OPR_EXPR_BIT_AND ||
           form == OPR_EXPR_SHL || form == OPR_EXPR_SHR;
}

public bool operator_numeric_binary(uint form)
{
    return form == OPR_EXPR_ADD || form == OPR_EXPR_SUB ||
           form == OPR_EXPR_MUL || form == OPR_EXPR_DIV ||
           form == OPR_EXPR_LT || form == OPR_EXPR_GT ||
           form == OPR_EXPR_LE || form == OPR_EXPR_GE;
}

public bool operator_equality_binary(uint form)
{
    return form == OPR_EXPR_EQ || form == OPR_EXPR_NE;
}

public bool operator_ordering_binary(uint form)
{
    return form == OPR_EXPR_LT || form == OPR_EXPR_GT ||
           form == OPR_EXPR_LE || form == OPR_EXPR_GE;
}

// Whether binary `form` constrains its operands here.
public bool operator_checked_binary(uint form)
{
    return operator_integer_binary(form) || operator_numeric_binary(form) ||
        operator_equality_binary(form);
}

public bool operator_binary_operand_ok(uint form, uint ty)
{
    if (operator_integer_binary(form)) return operator_assignable_to_int(ty);
    // Chars order by code point (unsigned, as the backends compare them);
    // they take no arithmetic.
    if (operator_ordering_binary(form) && ty == OPR_TY_CHAR) return true;
    // Enums order by variant index; the backends compare their tags.
    if (operator_ordering_binary(form) && ty == OPR_TY_NAMED) return true;
    if (operator_numeric_binary(form)) return operator_numeric_operand_ok(ty);
    if (operator_equality_binary(form)) return operator_equality_operand_ok(ty);
    return true;
}

// The operand a binary operator rejects, and the ERR_ASSIGN_MISMATCH detail.
// `left_null` and `right_null` say whether that operand is the literal 0,
// the null pointer constant.
public uint operator_binary_violation(uint form, uint left_ty, uint right_ty,
    bool left_null, bool right_null, out uint detail)
{
    detail = 0u;
    if (!operator_checked_binary(form)) return OPR_OPERAND_NONE;
    // Pointer offset: `p + n`, `p - n`.
    if ((form == OPR_EXPR_ADD || form == OPR_EXPR_SUB) &&
        left_ty == OPR_TY_POINTER && operator_assignable_to_int(right_ty))
        return OPR_OPERAND_NONE;
    if (operator_equality_binary(form) &&
        (left_ty == OPR_TY_POINTER || right_ty == OPR_TY_POINTER))
    {
        if ((left_ty == OPR_TY_POINTER && right_ty == OPR_TY_POINTER) ||
            (left_ty == OPR_TY_POINTER && right_ty == OPR_TY_INT && right_null) ||
            (right_ty == OPR_TY_POINTER && left_ty == OPR_TY_INT && left_null))
            return OPR_OPERAND_NONE;
        bool left_pointer = left_ty == OPR_TY_POINTER;
        detail = OPR_TY_POINTER * 256u + operator_detail_code(left_pointer ? right_ty : left_ty);
        return left_pointer ? OPR_OPERAND_RIGHT : OPR_OPERAND_LEFT;
    }
    // The detail is the rejected operand's type (no expected type).
    if (!operator_binary_operand_ok(form, left_ty))
    {
        detail = operator_detail_code(left_ty);
        return OPR_OPERAND_LEFT;
    }
    if (!operator_binary_operand_ok(form, right_ty))
    {
        detail = operator_detail_code(right_ty);
        return OPR_OPERAND_RIGHT;
    }
    // Integer widths and signedness are checked type identity. Only an
    // unsuffixed literal can take the opposite operand's type via context.
    // Two aggregates of one class (two structs or enums) pass here; their
    // complete types are not compared by these classes.
    bool shift = form == OPR_EXPR_SHL || form == OPR_EXPR_SHR;
    if (!shift && left_ty != OPR_TY_UNKNOWN && right_ty != OPR_TY_UNKNOWN && left_ty != right_ty)
    {
        detail = operator_detail_code(left_ty) * 256u + operator_detail_code(right_ty);
        return OPR_OPERAND_RIGHT;
    }
    return OPR_OPERAND_NONE;
}

// A condition (`if`, `while`) or a logical operand (`!`, `&&`, `||`) must be
// bool. True, with the ERR_ASSIGN_MISMATCH detail, when `ty` is another
// known type.
public bool operator_bool_violation(uint ty, out uint detail)
{
    detail = OPR_TY_BOOL * 256u + operator_detail_code(ty);
    return ty != OPR_TY_UNKNOWN && ty != OPR_TY_BOOL;
}

public bool operator_logical_form(uint form)
{
    return form == OPR_EXPR_NOT || form == OPR_EXPR_AND || form == OPR_EXPR_OR;
}

// A negation's operand must be an integer or a float. True, with the
// ERR_ASSIGN_MISMATCH detail (the operand's type), when `ty` is another known
// type: bool, char, str, ptr or an aggregate.
public bool operator_negation_violation(uint ty, out uint detail)
{
    detail = operator_detail_code(ty);
    return !operator_negation_operand_ok(ty);
}

// An index base must be an array or slice (or a reference to one, which the
// caller resolves); an aggregate or scalar of another kind is rejected.
// An index must be an integer.
public bool operator_index_violation(uint index_ty, out uint detail)
{
    detail = OPR_TY_INT * 256u + operator_detail_code(index_ty);
    return !operator_assignable_to_int(index_ty);
}
