// Reference classes of a retained body row (docs/compiler-program-retention.md).
//
// The exporter encodes every payload word by its class, and a consumer
// decodes and validates the word by the same class. The classes mirror the
// compact HIR writers (closure/09_exec_rows.slang payload_of): a payload
// word is a body row, a body token, a statement/expression context, an
// index into one of the body's side tables, or a plain value (an item kind,
// an operator form, literal words).
//
// The role says which checked fact a row must carry. A VALUE row produces a
// value and must have a resolved type term. A TYPE row is a written type
// annotation and must have its checked type term. A CALLEE row is callable-
// only syntax (the callee of a call); a STRUCTURAL row produces no value.

public static const uint RT_HIR_FN = 3u;
public static const uint RT_HIR_PARAM = 4u;
public static const uint RT_HIR_TYPE = 5u;
public static const uint RT_HIR_BLOCK = 6u;
public static const uint RT_HIR_STMT = 7u;
public static const uint RT_HIR_LET_STMT = 8u;
public static const uint RT_HIR_RETURN_STMT = 9u;
public static const uint RT_HIR_IF_STMT = 10u;
public static const uint RT_HIR_WHILE_STMT = 11u;
public static const uint RT_HIR_BREAK_STMT = 12u;
public static const uint RT_HIR_CONTINUE_STMT = 13u;
public static const uint RT_HIR_EXPR = 14u;
public static const uint RT_HIR_ASSIGN_EXPR = 15u;
public static const uint RT_HIR_BINARY_EXPR = 16u;
public static const uint RT_HIR_UNARY_EXPR = 17u;
public static const uint RT_HIR_POSTFIX_EXPR = 18u;
public static const uint RT_HIR_CALL_EXPR = 19u;
public static const uint RT_HIR_INDEX_EXPR = 20u;
public static const uint RT_HIR_MEMBER_EXPR = 21u;
public static const uint RT_HIR_NAME_EXPR = 22u;
public static const uint RT_HIR_LITERAL_EXPR = 23u;
public static const uint RT_HIR_ARRAY_EXPR = 24u;
public static const uint RT_HIR_CONST_ITEM = 25u;
public static const uint RT_HIR_STRUCT_LITERAL_EXPR = 28u;
public static const uint RT_HIR_FOR_STMT = 30u;
public static const uint RT_HIR_PATH_EXPR = 33u;
public static const uint RT_HIR_MATCH_EXPR = 34u;
public static const uint RT_HIR_TRY_EXPR = 36u;

static const uint STMT_LET = 1u;
static const uint STMT_RETURN = 2u;
static const uint STMT_IF = 3u;
static const uint STMT_CONST = 4u;
static const uint STMT_ASSIGN = 5u;
static const uint STMT_WHILE = 6u;
static const uint STMT_FOR = 7u;
static const uint EXPR_INT = 3u;
static const uint EXPR_FLOAT = 27u;
static const uint EXPR_STRING = 28u;
static const uint EXPR_CHAR = 29u;

// Word classes, 4 bits per payload word (a in bits 0..3, b 4..7, c 8..11,
// d 12..15). Side table k is RT_CLASS_SIDE + k (side_tables.slang order).
public static const uint RT_CLASS_VALUE = 0u;
public static const uint RT_CLASS_ROW = 1u;
public static const uint RT_CLASS_TOKEN = 2u;
public static const uint RT_CLASS_CONTEXT = 3u;
public static const uint RT_CLASS_SIDE = 4u;

uint classes(uint a, uint b, uint c, uint d) { return a | (b << 4u) | (c << 8u) | (d << 12u); }

public uint rt_word_class(uint classes, uint word) { return (classes >> (4u * word)) & 0xfu; }

public bool rt_stmt_kind(uint kind)
{
    return kind == RT_HIR_STMT || kind == RT_HIR_LET_STMT || kind == RT_HIR_RETURN_STMT ||
        kind == RT_HIR_IF_STMT || kind == RT_HIR_WHILE_STMT || kind == RT_HIR_BREAK_STMT ||
        kind == RT_HIR_CONTINUE_STMT || kind == RT_HIR_FOR_STMT;
}

// The classes of a row's payload words. `function_row` is the body's own
// function row; `form` is payload word a.
public uint rt_payload_classes(uint kind, uint form, bool function_row)
{
    const uint V = RT_CLASS_VALUE;
    const uint R = RT_CLASS_ROW;
    const uint T = RT_CLASS_TOKEN;
    const uint X = RT_CLASS_CONTEXT;
    if (function_row) return classes(V, T, V, V);
    if (kind == RT_HIR_PARAM) return classes(R, V, T, R);
    if (kind == RT_HIR_TYPE) return classes(V, R, T, R);
    if (rt_stmt_kind(kind))
    {
        if (form == STMT_LET || form == STMT_CONST || form == STMT_FOR) return classes(V, T, R, R);
        if (form == STMT_RETURN) return classes(V, R, V, T);
        if (form == STMT_ASSIGN) return classes(V, R, R, V);
        if (form == STMT_IF || form == STMT_WHILE) return classes(V, R, R, R);
        return 0u;
    }
    if (kind == RT_HIR_CALL_EXPR) return classes(R, RT_CLASS_SIDE + 0u, V, X);
    if (kind == RT_HIR_INDEX_EXPR || kind == RT_HIR_TRY_EXPR) return classes(V, R, R, T);
    if (kind == RT_HIR_MEMBER_EXPR) return classes(V, R, T, T);
    if (kind == RT_HIR_ARRAY_EXPR) return classes(V, R, T, X);
    if (kind == RT_HIR_STRUCT_LITERAL_EXPR) return classes(V, RT_CLASS_SIDE + 1u, V, X);
    if (kind == RT_HIR_MATCH_EXPR) return classes(R, RT_CLASS_SIDE + 2u, V, V);
    if (form == 0u || form == EXPR_FLOAT) return 0u;
    if (form == EXPR_INT || form == EXPR_CHAR) return classes(V, V, V, T);
    if (form == EXPR_STRING && kind == RT_HIR_LITERAL_EXPR) return classes(V, RT_CLASS_SIDE + 5u, R, T);
    return classes(V, kind != RT_HIR_NAME_EXPR ? R : V, R, T);
}

// Row roles (rt_seg_rows r3.z).
public static const uint RT_ROLE_STRUCTURAL = 0u;
public static const uint RT_ROLE_VALUE = 1u;
public static const uint RT_ROLE_TYPE = 2u;
public static const uint RT_ROLE_CALLEE = 3u;
// A predicate's bound (a trait reference). It denotes no type: its trait
// and arguments are the owner's predicate record (rt_traits).
public static const uint RT_ROLE_BOUND = 4u;
// A match pattern that names an enum variant (`Ok(_)`, `None`). It matches
// and binds; it produces no value, so it needs no type. Its variant is the
// row's binding (r5), the matched type is the scrutinee's term, and its
// payload binders are value rows with their own types.
public static const uint RT_ROLE_PATTERN = 5u;

public bool rt_value_kind(uint kind)
{
    return kind == RT_HIR_EXPR || kind == RT_HIR_ASSIGN_EXPR || kind == RT_HIR_BINARY_EXPR ||
        kind == RT_HIR_UNARY_EXPR || kind == RT_HIR_POSTFIX_EXPR || kind == RT_HIR_CALL_EXPR ||
        kind == RT_HIR_INDEX_EXPR || kind == RT_HIR_MEMBER_EXPR || kind == RT_HIR_NAME_EXPR ||
        kind == RT_HIR_LITERAL_EXPR || kind == RT_HIR_ARRAY_EXPR || kind == RT_HIR_STRUCT_LITERAL_EXPR ||
        kind == RT_HIR_PATH_EXPR || kind == RT_HIR_MATCH_EXPR || kind == RT_HIR_TRY_EXPR;
}

// Value bindings (rt_seg_rows r5.x): the declaration a name, path or
// binding row refers to.
public static const uint RT_BIND_NONE = 0u;
public static const uint RT_BIND_LOCAL = 1u;    // value: body-relative token of the binding's name
public static const uint RT_BIND_DECL = 2u;     // value: DeclId (function, constant, nominal)
public static const uint RT_BIND_VARIANT = 3u;  // value: enum DeclId, aux: variant ordinal
public static const uint RT_BIND_PARAM = 4u;    // value: generic parameter leaf
public static const uint RT_BIND_FOREIGN = 5u;  // a declaration the job could not identify (incomplete)

// Constant flags (rt_seg_rows r6.y), the artifact projection's presence words.
public static const uint RT_CONST_CONCRETE = 0x80000000u;  // (lo, hi) are the value
public static const uint RT_CONST_VARIANT = 0x40000000u;   // lo is an imported unit variant's ordinal
public static const uint RT_CONST_SYMBOLIC = 0x20000000u;  // lo is a constant parameter leaf
