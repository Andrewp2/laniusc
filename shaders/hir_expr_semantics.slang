// Shared semantic interpretation of parser-owned HIR expression records.
//
// Consumers use these forms instead of reading parser production ids. The
// scalar type codes are the stable language type codes shared by typecheck and
// codegen.

public static const uint HIR_SEM_EXPR_NAME = 2u;
public static const uint HIR_SEM_EXPR_INT = 3u;
public static const uint HIR_SEM_EXPR_TRUE = 4u;
public static const uint HIR_SEM_EXPR_FALSE = 5u;
public static const uint HIR_SEM_EXPR_FLOAT = 27u;
public static const uint HIR_SEM_EXPR_STRING = 28u;
public static const uint HIR_SEM_EXPR_CHAR = 29u;

public static const uint HIR_SEM_TY_UNKNOWN = 0u;
public static const uint HIR_SEM_TY_BOOL = 2u;
public static const uint HIR_SEM_TY_INT = 3u;
public static const uint HIR_SEM_TY_FLOAT = 5u;
public static const uint HIR_SEM_TY_CHAR = 6u;
public static const uint HIR_SEM_TY_STRING = 7u;

public uint hir_scalar_type_for_expr_form(uint form)
{
    if (form == HIR_SEM_EXPR_TRUE || form == HIR_SEM_EXPR_FALSE)
        return HIR_SEM_TY_BOOL;
    if (form == HIR_SEM_EXPR_INT)
        return HIR_SEM_TY_INT;
    if (form == HIR_SEM_EXPR_FLOAT)
        return HIR_SEM_TY_FLOAT;
    if (form == HIR_SEM_EXPR_STRING)
        return HIR_SEM_TY_STRING;
    if (form == HIR_SEM_EXPR_CHAR)
        return HIR_SEM_TY_CHAR;
    return HIR_SEM_TY_UNKNOWN;
}
