// Persisted and paged GPU semantic-interface member record layout.
// Word 11 retains source order in the declaration's own generic header.
public static const uint SEMANTIC_INTERFACE_MEMBER_WORDS = 12u;

// Callable predicate records reference ordered canonical operand roots.
public static const uint SEMANTIC_INTERFACE_PREDICATE_WORDS = 8u;

// Implementations own tagged member segments and ordered canonical roots.
public static const uint SEMANTIC_INTERFACE_IMPLEMENTATION_WORDS = 15u;
public static const uint SEMANTIC_INTERFACE_IMPLEMENTATION_METHOD_BINDING_WORDS = 6u;
public static const uint SEMANTIC_INTERFACE_IMPLEMENTATION_INHERENT = 1u;
public static const uint SEMANTIC_INTERFACE_IMPLEMENTATION_TRAIT = 2u;
public static const uint SEMANTIC_INTERFACE_IMPLEMENTATION_OWNER = 0x80000000u;
