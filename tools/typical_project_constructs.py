#!/usr/bin/env python3
"""Role-specific semantic workloads for corpus-calibrated typical projects."""

from __future__ import annotations

import json
import re
from functools import cache
from pathlib import Path


VALUE_MASK = 4095
ARCHETYPES = ("policy", "processor", "service", "planner", "tracker", "summary")


# Presence is measured from rendered Lanius source, matching the per-file
# corpus calibration in typical_construct_profile.json. These are language
# syntax probes, not emitter labels: deleting or misspelling a construct in a
# template removes it from the manifest automatically.
LANIUS_CONSTRUCT_PATTERNS: dict[str, tuple[str, ...]] = {
    "module": (r"(?m)^module\s+",),
    "import": (r"(?m)^import\s+",),
    "public_item": (r"(?m)^pub\s+(?:fn|const|type|struct|enum|trait|impl|extern)\b",),
    "public_const": (r"(?m)^pub\s+const\s+",),
    "public_type_alias": (r"(?m)^pub\s+type\s+",),
    "public_struct": (r"(?m)^pub\s+struct\s+",),
    "public_enum": (r"(?m)^pub\s+enum\s+",),
    "public_trait": (r"(?m)^pub\s+trait\s+",),
    "public_impl": (r"(?m)^pub\s+impl\s+",),
    "public_extern": (r'(?m)^pub\s+extern(?:\s+"[^"]+")?\s+fn\s+',),
    "function": (r"\bfn\s+\w+",),
    "parameters": (r"\bfn\s+\w+(?:<[^>]+>)?\([^)]*\w+\s*:\s*[^)]+\)",),
    "return_value": (r"\breturn\s+[^;]+;",),
    "typed_local": (r"\blet\s+\w+\s*:\s*[^=;]+\s*=",),
    "mutable_local": (r"\blet\s+\w+\s*:\s*[^=;]+\s*=",),
    "function_call": (r"\b\w+(?:::\w+)*\s*\(",),
    "if": (r"\bif\s*\(",),
    "else": (r"\belse\s*\{",),
    "integer_literal": (r"\b\d+\b",),
    "arithmetic_operators": (r"\s[+*/%-]\s",),
    "assignment": (r"(?m)^\s*\w+(?:\.\w+)?\s*=\s*",),
    "qualified_path": (r"\b\w+::\w+",),
    "const_item": (r"(?m)^\s*(?:pub\s+)?const\s+",),
    "type_alias": (r"(?m)^\s*(?:pub\s+)?type\s+\w+",),
    "struct": (r"(?m)^\s*(?:pub\s+)?struct\s+\w+",),
    "empty_struct_declaration": (r"\bstruct\s+\w+\s*\{\s*\}",),
    "empty_struct_literal": (r"=\s*\w+\s*\{\s*\}\s*;",),
    "struct_literal": (r"\b\w+\s*\{\s*\w+\s*:",),
    "struct_field": (r"\b\w+\.\w+\b",),
    "aggregate_parameter": (r"\bfn\s+\w+\([^)]*(?:self|:\s*[A-Z]\w*)",),
    "aggregate_return": (r"\)\s*->\s*[A-Z]\w*",),
    "inherent_impl": (r"(?m)^\s*impl(?:<[^>]+>)?\s+[A-Z]\w*\s*\{",),
    "method_call": (r"\.\w+\s*\(",),
    "self_parameter": (r"\(\s*(?:&)?self\b|,\s*(?:&)?self\b",),
    "enum": (r"(?m)^\s*(?:pub\s+)?enum\s+\w+",),
    "enum_payload": (r"(?m)^\s*[A-Z]\w*\([^)]*\)\s*,",),
    "enum_multi_payload": (r"(?m)^\s*[A-Z]\w*\([^,\n]+,[^)\n]+\)\s*,",),
    "enum_empty_tuple_payload": (r"(?m)^\s*[A-Z]\w*\(\s*\)\s*,",),
    "enum_payload_trailing_comma": (
        r"(?m)^\s*[A-Z]\w*\([^)]*\w\s*,\s*\)\s*,",
    ),
    "match": (r"\bmatch\s*\(",),
    "match_payload_pattern": (r"(?m)^\s*[A-Z]\w*\(\w+\)\s*->",),
    "match_multi_payload_pattern": (
        r"(?m)^\s*[A-Z]\w*\(\w+\s*,\s*\w+\)\s*->",
    ),
    "match_unit_pattern": (r"(?m)^\s*[A-Z]\w*\s*->",),
    "match_empty_tuple_pattern": (r"(?m)^\s*[A-Z]\w*\(\s*\)\s*->",),
    "match_pattern_trailing_comma": (
        r"(?m)^\s*[A-Z]\w*\([^)]*\w\s*,\s*\)\s*->",
    ),
    "match_integer_pattern": (r"(?m)^\s*\d+\s*->",),
    "match_boolean_pattern": (r"(?m)^\s*(?:true|false)\s*->",),
    "match_wildcard_pattern": (r"(?m)^\s*_\s*->",),
    "generic_struct": (r"\bstruct\s+\w+<[^>]+>",),
    "generic_function": (r"\bfn\s+\w+<[^>]+>",),
    "generic_type_alias": (r"\btype\s+\w+<[^>]+>\s*=",),
    "generic_type_argument": (r"\b[A-Z]\w*<i32>",),
    "multiple_generic_parameters": (
        r"\b(?:struct|enum|fn|trait|type)\s+\w+<[^>\n]+,[^>\n]+>",
    ),
    "multiple_type_arguments": (r"\b[A-Z]\w*<[^>\n]+,[^>\n]+>",),
    "generic_parameter_trailing_comma": (
        r"\b(?:struct|enum|fn|trait|type)\s+\w+<[^>\n]+,\s*>",
    ),
    "type_argument_trailing_comma": (r"\b[A-Z]\w*<[^>\n]+,\s*>",),
    "fixed_array": (r"\[[^\]]+;\s*\w+\]",),
    "array_literal": (r"=\s*\[[^\]]*,[^\]]*\]",),
    "empty_array_literal": (r"=\s*\[\s*\]",),
    "zero_length_array_type": (r"\[[^\];]+;\s*0\s*\]",),
    "array_index": (r"\b\w+\s*\[[^\]]+\]",),
    "while": (r"\bwhile\s*\(",),
    "for_range": (r"\bfor\s+\w+\s+in\s+[^\n{]+\.\.",),
    "for_iterable_path": (r"\bfor\s+\w+\s+in\s+\w+(?:::\w+)*\s*\{",),
    "range_inclusive": (r"\.\.=",),
    "range_to": (r"\bfor\s+\w+\s+in\s+\.\.(?!=)",),
    "range_to_inclusive": (r"\bfor\s+\w+\s+in\s+\.\.=",),
    "range_from": (r"\bfor\s+\w+\s+in\s+[^\n{]+\.\.\s*\{",),
    "range_full": (r"\bfor\s+\w+\s+in\s+\.\.\s*\{",),
    "nested_loop": (r"\bfor\b[\s\S]{0,180}\bfor\b",),
    "break": (r"\bbreak\s*;",),
    "continue": (r"\bcontinue\s*;",),
    "nested_scope": (r"(?m)^\s{4,}\{\s*$",),
    "shadowing": (r"\blet\s+(\w+)\b[\s\S]{0,800}?\blet\s+\1\b",),
    "early_return": (r"\bif\b[^{}]*\{\s*return\b",),
    "bool": (r"\b(?:true|false|bool)\b",),
    "logical_operators": (r"&&|\|\|",),
    "unary_expression": (r"!\s*(?:false|true|\w+)|-\s*\d+",),
    "bitwise_operators": (r"(?<!&)&(?!&|=)|\^(?!=)|(?<!\|)\|(?!\||=)",),
    "shift_operators": (r"<<|>>",),
    "comparison_operators": (r"==|!=|<=|>=|\s<\s|\s>\s",),
    "compound_assignment": (r"[+\-*/%&|^]=",),
    "trait": (r"(?m)^\s*(?:pub\s+)?trait\s+",),
    "trait_impl": (r"(?m)^\s*(?:pub\s+)?impl(?:<[^>]+>)?\s+[^\n{]+\s+for\s+",),
    "public_trait_method": (r"\btrait\b[\s\S]{0,1200}?\n\s+pub\s+fn\s+\w+",),
    "where_clause": (r"\bwhere\s+\w+\s*:",),
    "generic_bound": (r"\bwhere\s+\w+\s*:\s*\w+",),
    "multiple_where_predicates": (
        r"\bwhere\s+\w+\s*:[^{\n]+,\s*\w+\s*:",
    ),
    "where_predicate_trailing_comma": (r"\bwhere\s+[^{\n]+,\s*\{",),
    "multiple_type_bounds": (r"\bwhere\s+\w+\s*:[^{\n]+\+[^{\n]+",),
    "bound_multiple_type_arguments": (
        r"\bwhere\s+[^{\n]+\b[A-Z]\w*<[^>\n]+,[^>\n]+>",
    ),
    "bound_type_argument_trailing_comma": (
        r"\bwhere\s+[^{\n]+\b[A-Z]\w*<[^>\n]+,\s*>",
    ),
    "const_generic": (r"<\s*const\s+\w+\s*:\s*usize\s*>",),
    "reference_type": (r"&self\b|:\s*&\w+",),
    "fixed_array_parameter": (r"\[[A-Za-z_]\w*(?:::\w+)*;\s*\d+\]",),
    "extern_function": (r"\bextern(?:\s+\"[^\"]+\")?\s+fn\s+",),
    "extern_abi": (r"\bextern\s+\"[^\"]+\"\s+fn\s+",),
    "extern_without_abi": (r"\bextern\s+fn\s+",),
    "void_function": (r"\bfn\s+\w+(?:<[^>]+>)?\([^)]*\)\s*\{",),
    "bare_return": (r"\breturn\s*;",),
    "inferred_local": (r"\blet\s+\w+\s*=",),
    "uninitialized_typed_local": (r"\blet\s+\w+\s*:\s*[^=;]+;",),
    "expression_statement": (r"(?m)^\s*\w+(?:::\w+)*\([^;]*\);\s*$",),
    "public_impl_method": (r"\bimpl\b[\s\S]{0,1200}?\n\s+pub\s+fn\s+\w+",),
    "postfix_call_member": (r"\b\w+\([^;]*\)\.\w+",),
    "if_without_else": (r"\bif\s*\([^)]*\)\s*\{[^{}]*\}(?!\s*else)",),
    "group_expression": (r"=\s*\(\([^;]+\)\)\s*;",),
    "unary_positive": (r"=\s*\+\s*\(",),
    "empty_call": (r"\b\w+(?:::\w+)*\(\)",),
    "param_trailing_comma": (r"\bfn\s+\w+(?:<[^>]+>)?\([^)]*,\s*\)",),
    "call_trailing_comma": (r"\b\w+(?:::\w+)*\([^)]*,\s*\)",),
    "array_trailing_comma": (r"=\s*\[[^\]]+,\s*\]",),
    "struct_literal_trailing_comma": (r"\b\w+\s*\{[^{}]*,\s*\}",),
    "assign_add": (r"\+=",),
    "assign_subtract": (r"-=",),
    "assign_multiply": (r"\*=",),
    "assign_divide": (r"/=",),
    "assign_remainder": (r"%=",),
    "assign_xor": (r"\^=",),
    "assign_shift_left": (r"<<=",),
    "assign_shift_right": (r">>=",),
    "assign_bit_and": (r"&=",),
    "assign_bit_or": (r"\|=",),
    "type_u8": (r"\bu8\b",),
    "type_u32": (r"\bu32\b",),
    "type_usize": (r"\busize\b",),
    "type_i64": (r"\bi64\b",),
    "type_f32": (r"\bf32\b",),
    "type_char": (r"\bchar\b",),
    "type_str": (r"\bstr\b",),
    "type_ptr": (r"\bptr\b",),
    "string_literal": (r'"(?:[^"\\]|\\.)*"',),
    "char_literal": (r"'(?:[^'\\]|\\.)'",),
    "float_literal": (r"\b\d+\.\d+\b",),
    "stdio": (r"\bstd::io::",),
    "filesystem": (r"\bstd::fs::",),
    "environment": (r"\bstd::env::",),
    "process_args": (r"\bstd::process::(?:argc|arg_len|arg_read)\s*\(",),
    "process_exit": (r"\bstd::process::exit\s*\(",),
    "random": (r"\bstd::random::",),
    "time": (r"\bstd::time::",),
    "allocation": (r"\balloc::allocator::(?:alloc|realloc|dealloc)\s*\(",),
}


def lanius_constructs_in_source(source: str) -> frozenset[str]:
    constructs = {
        construct
        for construct, patterns in LANIUS_CONSTRUCT_PATTERNS.items()
        if any(re.search(pattern, source) for pattern in patterns)
    }
    function_names = re.findall(r"\bfn\s+(\w+)", source)
    if any(f"return {name}(" in source for name in function_names):
        constructs.add("recursion")
    return frozenset(constructs)


@cache
def load_construct_profile() -> dict[str, object]:
    path = Path(__file__).with_name("typical_construct_profile.json")
    return json.loads(path.read_text())


@cache
def _archetype_cycle() -> tuple[str, ...]:
    # Keep the first six modules maximally varied, then converge toward the
    # corpus-calibrated weights with a deterministic weighted-fair schedule.
    # This gives small benchmark projects useful breadth without making large
    # projects an unrealistic uniform rotation of compiler features.
    weights = {
        name: int(load_construct_profile()["archetypes"][name]["weight"])
        for name in ARCHETYPES
    }
    if sum(weights.values()) != 100:
        raise ValueError("archetype weights must sum to 100")
    counts = {name: 1 for name in ARCHETYPES}
    cycle = list(ARCHETYPES)
    for _ in range(len(ARCHETYPES), 100):
        remaining = {
            name: weights[name] - counts[name]
            for name in ARCHETYPES
        }
        selected = min(
            (name for name in ARCHETYPES if remaining[name] > 0),
            key=lambda name: (
                counts[name] / weights[name],
                ARCHETYPES.index(name),
            ),
        )
        counts[selected] += 1
        cycle.append(selected)
    return tuple(cycle)


def archetype_for_module(index: int) -> str:
    if index < 0:
        raise ValueError("module index must be non-negative")
    return _archetype_cycle()[index % 100]


def construct_coverage(archetype: str) -> frozenset[str]:
    profile = load_construct_profile()
    common = profile["common_constructs"]
    specific = profile["archetypes"][archetype]["constructs"]
    return frozenset((*common, *specific))


RARE_PATTERN_SLOTS = {
    "contracts": frozenset({6, 20, 34, 48, 62, 76, 90, 98}),
    "const_generic": frozenset({11, 31, 51, 71, 91}),
    "borrowed_views": frozenset({9, 16, 23, 30, 37, 44, 51, 58, 65, 72, 79, 86, 93, 99}),
    "foreign_api": frozenset({42, 92}),
    "literal_data": frozenset({13, 23, 33, 43, 53, 63, 73, 83, 93, 99}),
    "language_forms": frozenset({4, 29, 54, 79}),
    "operator_forms": frozenset({7, 27, 47, 67, 87}),
    "primitive_forms": frozenset({18, 43, 68, 93}),
    "range_forms": frozenset({38, 88}),
    "match_forms": frozenset({17, 57, 97}),
    "enum_tuple_patterns": frozenset({24, 74}),
    "iterable_forms": frozenset({32, 82}),
    "trailing_lists": frozenset({40, 80}),
    "generic_arity": frozenset({25, 75}),
    "pattern_list_forms": frozenset({26, 76}),
    "bound_list_forms": frozenset({28}),
    "statement_postfix_forms": frozenset({39, 89}),
    "public_items": frozenset({49}),
    "empty_aggregates": frozenset({46, 96}),
}

RARE_PATTERN_CONSTRUCTS = {
    "contracts": frozenset({
        "trait", "trait_impl", "where_clause", "generic_bound",
        "public_trait_method",
    }),
    "const_generic": frozenset({"const_generic"}),
    "borrowed_views": frozenset({"reference_type", "fixed_array_parameter"}),
    "foreign_api": frozenset({"extern_function", "extern_abi"}),
    "literal_data": frozenset({"string_literal", "char_literal", "float_literal"}),
    "language_forms": frozenset({
        "extern_without_abi", "void_function", "bare_return", "inferred_local",
        "if_without_else", "group_expression", "unary_positive", "empty_call",
    }),
    "operator_forms": frozenset({
        "assign_add", "assign_subtract", "assign_multiply", "assign_divide",
        "assign_remainder", "assign_xor", "assign_shift_left",
        "assign_shift_right", "assign_bit_and", "assign_bit_or",
    }),
    "primitive_forms": frozenset({
        "type_u8", "type_u32", "type_usize", "type_i64", "type_f32",
        "type_char", "type_str", "type_ptr",
    }),
    "range_forms": frozenset({
        "range_inclusive", "range_to", "range_to_inclusive", "range_from",
        "range_full",
    }),
    "match_forms": frozenset({
        "match_integer_pattern", "match_boolean_pattern", "match_wildcard_pattern",
    }),
    "enum_tuple_patterns": frozenset({
        "enum_multi_payload", "match_multi_payload_pattern", "match_unit_pattern",
    }),
    "iterable_forms": frozenset({"for_iterable_path"}),
    "trailing_lists": frozenset({
        "param_trailing_comma", "call_trailing_comma", "array_trailing_comma",
        "struct_literal_trailing_comma",
    }),
    "generic_arity": frozenset({
        "multiple_generic_parameters", "multiple_type_arguments",
        "generic_parameter_trailing_comma", "type_argument_trailing_comma",
        "generic_type_alias",
    }),
    "pattern_list_forms": frozenset({
        "enum_empty_tuple_payload", "enum_payload_trailing_comma",
        "match_empty_tuple_pattern", "match_pattern_trailing_comma",
    }),
    "bound_list_forms": frozenset({
        "multiple_where_predicates", "where_predicate_trailing_comma",
        "multiple_type_bounds", "bound_multiple_type_arguments",
        "bound_type_argument_trailing_comma",
    }),
    "statement_postfix_forms": frozenset({
        "uninitialized_typed_local", "expression_statement",
        "public_impl_method", "postfix_call_member",
    }),
    "public_items": frozenset({
        "public_const", "public_type_alias", "public_struct", "public_enum",
        "public_trait", "public_impl", "public_extern",
    }),
    "empty_aggregates": frozenset({
        "empty_array_literal", "zero_length_array_type",
        "empty_struct_declaration", "empty_struct_literal",
    }),
}

RARE_SCORE_FUNCTIONS = {
    "literal_data": ("literal_metadata", ""),
    "language_forms": ("language_forms", "seed"),
    "operator_forms": ("operator_forms", "seed"),
    "primitive_forms": ("primitive_forms", ""),
    "range_forms": ("range_forms", "seed"),
    "match_forms": ("match_forms", "seed"),
    "enum_tuple_patterns": ("enum_tuple_patterns", "seed"),
    "iterable_forms": ("iterable_forms", "seed"),
    "trailing_lists": ("trailing_lists", "seed"),
    "generic_arity": ("generic_arity", "seed"),
    "pattern_list_forms": ("pattern_list_forms", "seed"),
    "bound_list_forms": ("bound_list_forms", "seed"),
    "statement_postfix_forms": ("statement_postfix_forms", "seed"),
    "public_items": ("public_items", "seed"),
    "empty_aggregates": ("empty_aggregates", "seed"),
}


def rare_patterns_for_module(index: int) -> tuple[str, ...]:
    slot = index % 100
    return tuple(
        pattern for pattern, slots in RARE_PATTERN_SLOTS.items() if slot in slots
    )


def rare_construct_coverage(index: int) -> frozenset[str]:
    return frozenset(
        construct
        for pattern in rare_patterns_for_module(index)
        for construct in RARE_PATTERN_CONSTRUCTS[pattern]
    )


def evaluate_rare_patterns(seed: int, index: int) -> int:
    """Evaluate the observable contribution made by rare construct use sites."""
    total = 0
    for pattern in rare_patterns_for_module(index):
        if pattern in {
            "contracts", "const_generic", "language_forms", "operator_forms",
            "range_forms", "iterable_forms", "trailing_lists", "generic_arity",
            "pattern_list_forms",
            "bound_list_forms",
            "statement_postfix_forms",
            "public_items",
            "empty_aggregates",
        }:
            total = (total + seed) & VALUE_MASK
        elif pattern == "borrowed_views":
            # Both the borrowed receiver and slice call return the first value.
            total = (total + seed + seed) & VALUE_MASK
        elif pattern == "match_forms":
            scalar = (5, 7, 9)[seed % 3]
            boolean = 3 if seed & 1 == 0 else 4
            total = (total + scalar + boolean) & VALUE_MASK
        elif pattern == "enum_tuple_patterns":
            total = (total + (seed % 7) * 3 + ((seed // 7) % 7) + 1) & VALUE_MASK
        elif pattern in {"foreign_api", "literal_data", "primitive_forms"}:
            # These sites execute, but intentionally do not make expected output
            # depend on process state, platform state, or metadata literals.
            pass
        else:
            raise ValueError(pattern)
    return total


def render_rare_patterns(language: str, module_name: str, index: int) -> str:
    definitions = "".join(
        _render_rare_pattern(language, pattern, module_name, index)
        for pattern in rare_patterns_for_module(index)
    )
    if not definitions:
        return ""
    return definitions + _render_rare_score(language, module_name, index)


def rare_score_call(
    language: str, module_name: str, module_index: int, argument: str
) -> str | None:
    if not rare_patterns_for_module(module_index):
        return None
    if language == "c":
        return f"{module_name}_rare_construct_score({argument})"
    return f"rare_construct_score({argument})"


def _render_rare_score(language: str, module_name: str, index: int) -> str:
    patterns = rare_patterns_for_module(index)
    prefix = f"{module_name}_" if language == "c" else ""
    statements: list[str] = []
    for pattern in patterns:
        if pattern in RARE_SCORE_FUNCTIONS:
            function, arguments = RARE_SCORE_FUNCTIONS[pattern]
            statements.append(
                f"    total = (total + {prefix}{function}({arguments})) & {VALUE_MASK};"
            )
            continue
        if language == "lanius":
            if pattern == "contracts":
                statements.append(
                    f"    total = (total + preserve_scored(seed)) & {VALUE_MASK};"
                )
            elif pattern == "const_generic":
                statements.extend(
                    (
                        f"    let const_values: [i32; 4] = [seed, {index}, 3, 7];",
                        f"    total = (total + first_const_generic(seed, const_values)) & {VALUE_MASK};",
                    )
                )
            elif pattern == "borrowed_views":
                statements.extend(
                    (
                        f"    let borrowed: BorrowedValue = BorrowedValue {{ value: seed }};",
                        f"    total = (total + borrowed.borrowed_marker()) & {VALUE_MASK};",
                        f"    let slice_values: [i32; 4] = [seed, {index}, 3, 7];",
                        f"    total = (total + first_slice(slice_values)) & {VALUE_MASK};",
                    )
                )
            elif pattern == "foreign_api":
                statements.extend(
                    (
                        "    let observed_argc: i32 = argc();",
                        "    if (observed_argc < 0) { return 1; }",
                    )
                )
        elif language == "rust":
            if pattern == "contracts":
                statements.append(
                    f"    total = (total + preserve_scored(seed)) & {VALUE_MASK};"
                )
            elif pattern == "const_generic":
                statements.append(
                    f"    total = (total + first_const_generic(seed, [seed, {index}, 3, 7])) & {VALUE_MASK};"
                )
            elif pattern == "borrowed_views":
                statements.extend(
                    (
                        "    let borrowed = BorrowedValue { value: seed };",
                        f"    total = (total + borrowed.borrowed_marker()) & {VALUE_MASK};",
                        f"    total = (total + first_slice(&[seed, {index}, 3, 7])) & {VALUE_MASK};",
                    )
                )
            elif pattern == "foreign_api":
                statements.extend(
                    (
                        "    let observed_process = unsafe { getpid() };",
                        "    if observed_process < 0 { return 1; }",
                    )
                )
        elif language in {"c", "cpp"}:
            if pattern == "contracts":
                if language == "c":
                    statements.extend(
                        (
                            f"    {prefix}score_policy_contract contract = {{ {prefix}score_policy_i32 }};",
                            f"    total = (total + {prefix}preserve_scored(seed, contract)) & {VALUE_MASK};",
                        )
                    )
                else:
                    statements.append(
                        f"    total = (total + preserve_scored(seed)) & {VALUE_MASK};"
                    )
            elif pattern == "const_generic":
                statements.extend(
                    (
                        f"    int32_t const_values[4] = {{ seed, {index}, 3, 7 }};",
                        f"    total = (total + {prefix}first_const_generic(seed, const_values)) & {VALUE_MASK};",
                    )
                )
            elif pattern == "borrowed_views":
                if language == "c":
                    statements.extend(
                        (
                            f"    {prefix}BorrowedValue borrowed = {{ seed }};",
                            f"    total = (total + {prefix}borrowed_marker(&borrowed)) & {VALUE_MASK};",
                            f"    int32_t slice_values[4] = {{ seed, {index}, 3, 7 }};",
                            f"    total = (total + {prefix}first_slice(slice_values, 4)) & {VALUE_MASK};",
                        )
                    )
                else:
                    statements.extend(
                        (
                            "    BorrowedValue borrowed { seed };",
                            f"    total = (total + borrowed.borrowed_marker()) & {VALUE_MASK};",
                            f"    int32_t slice_values[4] = {{ seed, {index}, 3, 7 }};",
                            f"    total = (total + first_slice(slice_values, 4)) & {VALUE_MASK};",
                        )
                    )
            elif pattern == "foreign_api":
                statements.extend(
                    (
                        "    int32_t observed_process = (int32_t)getpid();",
                        "    if (observed_process < 0) return 1;",
                    )
                )
        elif language == "zig":
            if pattern == "contracts":
                statements.extend(
                    (
                        "    const contract = ScorePolicy { .score_policy = score_policy_i32 };",
                        f"    total = (total + preserve_scored(seed, contract)) & {VALUE_MASK};",
                    )
                )
            elif pattern == "const_generic":
                statements.append(
                    f"    total = (total + first_const_generic(seed, 4, [_]i32{{ seed, {index}, 3, 7 }})) & {VALUE_MASK};"
                )
            elif pattern == "borrowed_views":
                statements.extend(
                    (
                        "    const borrowed = BorrowedValue { .value = seed };",
                        f"    total = (total + borrowed.borrowed_marker()) & {VALUE_MASK};",
                        f"    const slice_values = [_]i32{{ seed, {index}, 3, 7 }};",
                        f"    total = (total + first_slice(&slice_values)) & {VALUE_MASK};",
                    )
                )
            elif pattern == "foreign_api":
                statements.extend(
                    (
                        "    const observed_process: i32 = @intCast(getpid());",
                        "    if (observed_process < 0) return 1;",
                    )
                )
        else:
            raise ValueError(language)

    if language == "rust":
        return (
            "fn rare_construct_score(seed: i32) -> i32 {\n"
            "    let mut total: i32 = 0;\n"
            + "\n".join(statements)
            + "\n    total\n}\n\n"
        )
    if language == "zig":
        seed_discard = "    _ = seed;\n" if not any("seed" in line for line in statements) else ""
        total_binding = (
            "    var total: i32 = 0;\n"
            if any("total =" in line for line in statements)
            else "    const total: i32 = 0;\n"
        )
        return (
            "fn rare_construct_score(seed: i32) i32 {\n"
            + total_binding
            + seed_discard
            + "\n".join(statements)
            + "\n    return total;\n}\n\n"
        )
    if language == "lanius":
        return (
            "fn rare_construct_score(seed: i32) -> i32 {\n"
            "    let total: i32 = 0;\n"
            + "\n".join(statements)
            + "\n    return total;\n}\n\n"
        )
    return (
        f"static int32_t {prefix}rare_construct_score(int32_t seed) {{\n"
        "    int32_t total = 0;\n"
        + "\n".join(statements)
        + "\n    return total;\n}\n\n"
    )


def _render_rare_pattern(
    language: str, pattern: str, module_name: str, index: int
) -> str:
    prefix = f"{module_name}_" if language == "c" else ""
    if language == "lanius":
        if pattern == "contracts":
            return """trait ScorePolicy<T> {
    pub fn score_policy(value: T) -> i32;
}

impl ScorePolicy<i32> for i32 {
    pub fn score_policy(value: i32) -> i32 {
        return value & 4095;
    }
}

fn preserve_scored<T>(value: T) -> T where T: ScorePolicy<T> {
    return value;
}

"""
        if pattern == "const_generic":
            return """fn first_const_generic<const N: usize>(first: i32, values: [i32; N]) -> i32 {
    return first;
}

"""
        if pattern == "borrowed_views":
            return """struct BorrowedValue {
    value: i32,
}

impl BorrowedValue {
    fn borrowed_marker(&self) -> i32 {
        return self.value;
    }
}

fn first_slice(values: [i32; 4]) -> i32 {
    return values[0];
}

"""
        if pattern == "foreign_api":
            return '''extern "lanius_std" fn argc() -> i32;

'''
        if pattern == "literal_data":
            return f'''fn literal_metadata() -> i32 {{
    let label: str = "module-{index}";
    let delimiter: char = ':';
    let ratio: f32 = 1.25;
    return 0;
}}

'''
        if pattern == "language_forms":
            return """extern fn unbound_probe() -> i32;

fn zero_value() -> i32 {
    return 0;
}

fn record_positive(value: i32) {
    if (value > 0) {
        return;
    }
}

fn language_forms(seed: i32) -> i32 {
    let inferred = +(seed);
    let grouped: i32 = ((inferred));
    record_positive(grouped);
    return grouped + zero_value();
}

"""
        if pattern == "operator_forms":
            return f"""fn operator_forms(seed: i32) -> i32 {{
    let value: i32 = seed;
    value += 3;
    value -= 3;
    value *= 2;
    value /= 2;
    value %= {VALUE_MASK + 1};
    value ^= 0;
    value <<= 1;
    value >>= 1;
    value &= {VALUE_MASK};
    value |= 0;
    return value;
}}

"""
        if pattern == "primitive_forms":
            return """fn primitive_forms() -> i32 {
    let tiny: u8 = 1;
    let unsigned: u32 = 2;
    let count: usize = 3;
    let wide: i64 = 4;
    let decimal: f32 = 1.5;
    let truth: bool = true;
    let letter: char = 'x';
    let text: str = "types";
    let address: ptr = 0;
    return 0;
}

"""
        if pattern == "range_forms":
            return f"""fn range_forms(seed: i32) -> i32 {{
    let total: i32 = seed;
    for value in 1 ..= 3 {{
        total = (total + value) & {VALUE_MASK};
    }}
    for value in .. 3 {{
        total = (total + value) & {VALUE_MASK};
    }}
    for value in ..= 2 {{
        total = (total + value) & {VALUE_MASK};
    }}
    for value in 2 .. {{
        total = (total + value) & {VALUE_MASK};
        if (value == 4) {{ break; }}
    }}
    for value in .. {{
        total = (total + value) & {VALUE_MASK};
        if (value == 2) {{ break; }}
    }}
    return (total - 24) & {VALUE_MASK};
}}

"""
        if pattern == "match_forms":
            return """fn integer_pattern_score(value: i32) -> i32 {
    return match (value) {
        0 -> 5,
        1 -> 7,
        _ -> 9,
    };
}

fn boolean_pattern_score(value: bool) -> i32 {
    return match (value) {
        true -> 3,
        false -> 4,
    };
}

fn match_forms(seed: i32) -> i32 {
    return integer_pattern_score(seed % 3) + boolean_pattern_score((seed & 1) == 0);
}

"""
        if pattern == "enum_tuple_patterns":
            return """enum CoordinateEvent {
    Moved(i32, i32),
    Idle,
}

fn coordinate_event_score(event: CoordinateEvent) -> i32 {
    return match (event) {
        Moved(x, y) -> x * 3 + y,
        Idle -> 1,
    };
}

fn enum_tuple_patterns(seed: i32) -> i32 {
    let moved: CoordinateEvent = Moved(seed % 7, (seed / 7) % 7);
    let idle: CoordinateEvent = Idle;
    return coordinate_event_score(moved) + coordinate_event_score(idle);
}

"""
        if pattern == "iterable_forms":
            return f"""fn iterable_forms(seed: i32) -> i32 {{
    let values: [i32; 4] = [seed, 2, 3, 4];
    let total: i32 = 0;
    for value in values {{
        total = (total + value) & {VALUE_MASK};
    }}
    return (total - 9) & {VALUE_MASK};
}}

"""
        if pattern == "trailing_lists":
            return """struct TrailingRecord {
    left: i32,
    right: i32,
}

fn trailing_sum(left: i32, right: i32,) -> i32 {
    let values: [i32; 2] = [left, right,];
    let record: TrailingRecord = TrailingRecord {
        left: values[0],
        right: values[1],
    };
    return record.left + record.right;
}

fn trailing_lists(seed: i32) -> i32 {
    return trailing_sum(seed, 0,);
}

"""
        if pattern == "generic_arity":
            return """struct GenericPair<Left, Right,> {
    left: Left,
    right: Right,
}

type GenericIdentity<Value,> = Value;

fn generic_pair_left(value: GenericPair<i32, bool,>) -> i32 {
    let left: GenericIdentity<i32,> = value.left;
    return left;
}

fn generic_arity(seed: i32) -> i32 {
    let pair: GenericPair<i32, bool,> = GenericPair {
        left: seed,
        right: true,
    };
    return generic_pair_left(pair);
}

"""
        if pattern == "pattern_list_forms":
            return """enum PatternListEvent {
    Empty(),
    Value(i32,),
}

fn pattern_list_score(value: PatternListEvent) -> i32 {
    return match (value) {
        Empty() -> 0,
        Value(inner,) -> inner,
    };
}

fn pattern_list_forms(seed: i32) -> i32 {
    let empty: PatternListEvent = Empty();
    let value: PatternListEvent = Value(seed);
    return pattern_list_score(empty) + pattern_list_score(value);
}

"""
        if pattern == "bound_list_forms":
            return """trait BoundScorePolicy<T> {
    fn bound_score_policy(value: T) -> i32;
}

trait StableBoundPolicy<T> {
    fn stable_bound_policy(value: T) -> i32;
}

trait PairBoundPolicy<Left, Right> {
    fn pair_bound_policy(left: Left, right: Right) -> i32;
}

impl BoundScorePolicy<i32> for i32 {
    fn bound_score_policy(value: i32) -> i32 { return value; }
}

impl StableBoundPolicy<i32> for i32 {
    fn stable_bound_policy(value: i32) -> i32 { return value; }
}

impl BoundScorePolicy<bool> for bool {
    fn bound_score_policy(value: bool) -> i32 {
        if (value) { return 1; }
        return 0;
    }
}

impl PairBoundPolicy<i32, bool> for i32 {
    fn pair_bound_policy(left: i32, right: bool) -> i32 { return left; }
}

fn preserve_bound_pair<Left, Right,>(left: Left, right: Right) -> Left
where Left: BoundScorePolicy<Left,> + StableBoundPolicy<Left,> + PairBoundPolicy<Left, Right,>, Right: BoundScorePolicy<Right,>, {
    return left;
}

fn bound_list_forms(seed: i32) -> i32 {
    return preserve_bound_pair(seed, true);
}

"""
        if pattern == "statement_postfix_forms":
            return """struct StatementRecord {
    value: i32,
}

impl StatementRecord {
    pub fn statement_value(self) -> i32 {
        return self.value;
    }
}

fn observe_statement(value: i32) { return; }

fn make_statement_record(value: i32) -> StatementRecord {
    return StatementRecord { value: value, };
}

fn statement_postfix_forms(seed: i32) -> i32 {
    let deferred: i32;
    observe_statement(0);
    let record: StatementRecord = StatementRecord { value: seed, };
    return record.statement_value() + make_statement_record(0).value;
}

"""
        if pattern == "public_items":
            return """pub const PUBLIC_ZERO: i32 = 0;
pub type PublicScore = i32;

pub struct PublicRecord {
    value: PublicScore,
}

pub enum PublicChoice {
    Selected(i32),
    Empty,
}

pub trait PublicPolicy<T> {
    pub fn public_policy(value: T) -> i32;
}

pub impl PublicRecord {
    pub fn read(self) -> i32 { return self.value; }
}

pub extern "lanius_std" fn argc() -> i32;

fn public_items(seed: i32) -> i32 {
    let record: PublicRecord = PublicRecord { value: seed, };
    let choice: PublicChoice = Selected(0);
    let adjustment: i32 = match (choice) {
        Selected(inner) -> inner,
        Empty -> 0,
    };
    let observed: i32 = argc();
    if (observed < 0) { return 0; }
    return record.read() + adjustment + PUBLIC_ZERO;
}

"""
        if pattern == "empty_aggregates":
            return """struct EmptyRecord {}

fn empty_aggregates(seed: i32) -> i32 {
    let empty_record: EmptyRecord = EmptyRecord {};
    let empty_values: [i32; 0] = [];
    return seed;
}

"""
    if language == "rust":
        if pattern == "contracts":
            return """trait ScorePolicy<T> { fn score_policy(value: T) -> i32; }
impl ScorePolicy<i32> for i32 { fn score_policy(value: i32) -> i32 { value & 4095 } }
fn preserve_scored<T: ScorePolicy<T>>(value: T) -> T { value }

"""
        if pattern == "const_generic":
            return """fn first_const_generic<const N: usize>(first: i32, values: [i32; N]) -> i32 { first }

"""
        if pattern == "borrowed_views":
            return """struct BorrowedValue { value: i32 }
impl BorrowedValue { fn borrowed_marker(&self) -> i32 { self.value } }
fn first_slice(values: &[i32]) -> i32 { values[0] }

"""
        if pattern == "foreign_api":
            return '''unsafe extern "C" { fn getpid() -> i32; }

'''
        if pattern == "literal_data":
            return f'''fn literal_metadata() -> i32 {{
    let _label: &str = "module-{index}";
    let _delimiter: char = ':';
    let _ratio: f32 = 1.25;
    0
}}

'''
        if pattern == "language_forms":
            return """unsafe extern "C" { fn unbound_probe() -> i32; }
fn zero_value() -> i32 { 0 }
fn record_positive(value: i32) { if value > 0 { return; } }
fn language_forms(seed: i32) -> i32 {
    let inferred = seed;
    let grouped = ((inferred));
    record_positive(grouped);
    grouped + zero_value()
}

"""
        if pattern == "operator_forms":
            return f"""fn operator_forms(seed: i32) -> i32 {{
    let mut value = seed;
    value += 3; value -= 3; value *= 2; value /= 2; value %= {VALUE_MASK + 1};
    value ^= 0; value <<= 1; value >>= 1; value &= {VALUE_MASK}; value |= 0;
    value
}}

"""
        if pattern == "primitive_forms":
            return """fn primitive_forms() -> i32 {
    let _tiny: u8 = 1; let _unsigned: u32 = 2; let _count: usize = 3;
    let _wide: i64 = 4; let _decimal: f32 = 1.5; let _truth: bool = true;
    let _letter: char = 'x'; let _text: &str = "types"; let _address: *const u8 = std::ptr::null();
    0
}

"""
        if pattern == "range_forms":
            return f"""fn range_forms(seed: i32) -> i32 {{
    let mut total = seed;
    for value in 1..=3 {{ total = (total + value) & {VALUE_MASK}; }}
    for value in 0..3 {{ total = (total + value) & {VALUE_MASK}; }}
    for value in 0..=2 {{ total = (total + value) & {VALUE_MASK}; }}
    for value in 2.. {{ total = (total + value) & {VALUE_MASK}; if value == 4 {{ break; }} }}
    for value in 0.. {{ total = (total + value) & {VALUE_MASK}; if value == 2 {{ break; }} }}
    (total - 24) & {VALUE_MASK}
}}

"""
        if pattern == "match_forms":
            return """fn integer_pattern_score(value: i32) -> i32 {
    match value { 0 => 5, 1 => 7, _ => 9 }
}
fn boolean_pattern_score(value: bool) -> i32 { match value { true => 3, false => 4 } }
fn match_forms(seed: i32) -> i32 {
    integer_pattern_score(seed % 3) + boolean_pattern_score((seed & 1) == 0)
}

"""
        if pattern == "enum_tuple_patterns":
            return """enum CoordinateEvent {
    Moved(i32, i32),
    Idle,
}
fn coordinate_event_score(event: CoordinateEvent) -> i32 {
    match event { CoordinateEvent::Moved(x, y) => x * 3 + y, CoordinateEvent::Idle => 1 }
}
fn enum_tuple_patterns(seed: i32) -> i32 {
    coordinate_event_score(CoordinateEvent::Moved(seed % 7, (seed / 7) % 7))
        + coordinate_event_score(CoordinateEvent::Idle)
}

"""
        if pattern == "iterable_forms":
            return f"""fn iterable_forms(seed: i32) -> i32 {{
    let values = [seed, 2, 3, 4];
    let mut total = 0;
    for value in values {{ total = (total + value) & {VALUE_MASK}; }}
    (total - 9) & {VALUE_MASK}
}}

"""
        if pattern == "trailing_lists":
            return """struct TrailingRecord { left: i32, right: i32 }
fn trailing_sum(left: i32, right: i32) -> i32 {
    let values = [left, right];
    let record = TrailingRecord { left: values[0], right: values[1] };
    record.left + record.right
}
fn trailing_lists(seed: i32) -> i32 { trailing_sum(seed, 0) }

"""
        if pattern == "generic_arity":
            return """struct GenericPair<Left, Right> { left: Left, right: Right }
type GenericIdentity<Value> = Value;
fn generic_pair_left(value: GenericPair<i32, bool>) -> i32 {
    let left: GenericIdentity<i32> = value.left;
    left
}
fn generic_arity(seed: i32) -> i32 {
    generic_pair_left(GenericPair { left: seed, right: true })
}

"""
        if pattern == "pattern_list_forms":
            return """enum PatternListEvent { Empty, Value(i32) }
fn pattern_list_score(value: PatternListEvent) -> i32 {
    match value { PatternListEvent::Empty => 0, PatternListEvent::Value(inner) => inner }
}
fn pattern_list_forms(seed: i32) -> i32 {
    pattern_list_score(PatternListEvent::Empty) + pattern_list_score(PatternListEvent::Value(seed))
}

"""
        if pattern == "bound_list_forms":
            return """trait BoundScorePolicy<T> { fn bound_score_policy(value: T) -> i32; }
trait StableBoundPolicy<T> { fn stable_bound_policy(value: T) -> i32; }
trait PairBoundPolicy<Left, Right> { fn pair_bound_policy(left: Left, right: Right) -> i32; }
impl BoundScorePolicy<i32> for i32 { fn bound_score_policy(value: i32) -> i32 { value } }
impl StableBoundPolicy<i32> for i32 { fn stable_bound_policy(value: i32) -> i32 { value } }
impl BoundScorePolicy<bool> for bool { fn bound_score_policy(value: bool) -> i32 { value as i32 } }
impl PairBoundPolicy<i32, bool> for i32 {
    fn pair_bound_policy(left: i32, _right: bool) -> i32 { left }
}
fn preserve_bound_pair<Left, Right>(left: Left, _right: Right) -> Left
where Left: BoundScorePolicy<Left> + StableBoundPolicy<Left> + PairBoundPolicy<Left, Right>, Right: BoundScorePolicy<Right> {
    left
}
fn bound_list_forms(seed: i32) -> i32 { preserve_bound_pair(seed, true) }

"""
        if pattern == "statement_postfix_forms":
            return """struct StatementRecord { value: i32 }
impl StatementRecord { pub fn statement_value(self) -> i32 { self.value } }
fn observe_statement(_value: i32) {}
fn make_statement_record(value: i32) -> StatementRecord { StatementRecord { value } }
fn statement_postfix_forms(seed: i32) -> i32 {
    let deferred: i32;
    observe_statement(0);
    let record = StatementRecord { value: seed };
    record.statement_value() + make_statement_record(0).value
}

"""
        if pattern == "public_items":
            return """pub const PUBLIC_ZERO: i32 = 0;
pub type PublicScore = i32;
pub struct PublicRecord { pub value: PublicScore }
pub enum PublicChoice { Selected(i32), Empty }
pub trait PublicPolicy<T> { fn public_policy(value: T) -> i32; }
impl PublicRecord { pub fn read(self) -> i32 { self.value } }
fn public_items(seed: i32) -> i32 {
    let record = PublicRecord { value: seed };
    let choice = PublicChoice::Selected(0);
    let adjustment = match choice { PublicChoice::Selected(inner) => inner, PublicChoice::Empty => 0 };
    record.read() + adjustment + PUBLIC_ZERO
}

"""
        if pattern == "empty_aggregates":
            return """struct EmptyRecord {}
fn empty_aggregates(seed: i32) -> i32 {
    let _empty_record = EmptyRecord {};
    let _empty_values: [i32; 0] = [];
    seed
}

"""
    if language == "cpp":
        if pattern == "contracts":
            return """template<class T> struct ScorePolicy { static std::int32_t score_policy(T value) { return value & 4095; } };
template<class T> requires requires(T value) { ScorePolicy<T>::score_policy(value); }
T preserve_scored(T value) { return value; }

"""
        if pattern == "const_generic":
            return """template<std::size_t N> std::int32_t first_const_generic(std::int32_t first, const std::int32_t (&values)[N]) { return first; }

"""
        if pattern == "borrowed_views":
            return """struct BorrowedValue { std::int32_t value; std::int32_t borrowed_marker() const { return value; } };
std::int32_t first_slice(const std::int32_t* values, std::size_t count) { return count == 0 ? 0 : values[0]; }

"""
        if pattern == "foreign_api":
            return '''extern "C" int getpid(void);

'''
        if pattern == "literal_data":
            return f'''std::int32_t literal_metadata() {{
    const char* label = "module-{index}"; char delimiter = ':'; float ratio = 1.25f;
    (void)label; (void)delimiter; (void)ratio; return 0;
}}

'''
        if pattern == "language_forms":
            return """extern "C" int unbound_probe();
std::int32_t zero_value() { return 0; }
void record_positive(std::int32_t value) { if (value > 0) return; }
std::int32_t language_forms(std::int32_t seed) {
    auto inferred = +seed; auto grouped = ((inferred));
    record_positive(grouped); return grouped + zero_value();
}

"""
        if pattern == "operator_forms":
            return f"""std::int32_t operator_forms(std::int32_t seed) {{
    std::int32_t value = seed;
    value += 3; value -= 3; value *= 2; value /= 2; value %= {VALUE_MASK + 1};
    value ^= 0; value <<= 1; value >>= 1; value &= {VALUE_MASK}; value |= 0;
    return value;
}}

"""
        if pattern == "primitive_forms":
            return """std::int32_t primitive_forms() {
    std::uint8_t tiny = 1; std::uint32_t unsigned_value = 2; std::size_t count = 3;
    std::int64_t wide = 4; float decimal = 1.5f; bool truth = true;
    char letter = 'x'; const char* text = "types"; void* address = nullptr;
    (void)tiny; (void)unsigned_value; (void)count; (void)wide; (void)decimal;
    (void)truth; (void)letter; (void)text; (void)address; return 0;
}

"""
        if pattern == "range_forms":
            return f"""std::int32_t range_forms(std::int32_t seed) {{
    std::int32_t total = seed;
    for (std::int32_t value = 1; value <= 3; ++value) total = (total + value) & {VALUE_MASK};
    for (std::int32_t value = 0; value < 3; ++value) total = (total + value) & {VALUE_MASK};
    for (std::int32_t value = 0; value <= 2; ++value) total = (total + value) & {VALUE_MASK};
    for (std::int32_t value = 2;; ++value) {{ total = (total + value) & {VALUE_MASK}; if (value == 4) break; }}
    for (std::int32_t value = 0;; ++value) {{ total = (total + value) & {VALUE_MASK}; if (value == 2) break; }}
    return (total - 24) & {VALUE_MASK};
}}

"""
        if pattern == "match_forms":
            return """std::int32_t integer_pattern_score(std::int32_t value) {
    switch (value) { case 0: return 5; case 1: return 7; default: return 9; }
}
std::int32_t boolean_pattern_score(bool value) { return value ? 3 : 4; }
std::int32_t match_forms(std::int32_t seed) {
    return integer_pattern_score(seed % 3) + boolean_pattern_score((seed & 1) == 0);
}

"""
        if pattern == "enum_tuple_patterns":
            return """struct CoordinateEvent {
    enum class Kind { Moved, Idle } kind;
    std::int32_t x;
    std::int32_t y;
};
std::int32_t coordinate_event_score(CoordinateEvent event) {
    return event.kind == CoordinateEvent::Kind::Moved ? event.x * 3 + event.y : 1;
}
std::int32_t enum_tuple_patterns(std::int32_t seed) {
    CoordinateEvent moved { CoordinateEvent::Kind::Moved, seed % 7, (seed / 7) % 7 };
    CoordinateEvent idle { CoordinateEvent::Kind::Idle, 0, 0 };
    return coordinate_event_score(moved) + coordinate_event_score(idle);
}

"""
        if pattern == "iterable_forms":
            return f"""std::int32_t iterable_forms(std::int32_t seed) {{
    std::int32_t values[4] = {{ seed, 2, 3, 4 }};
    std::int32_t total = 0;
    for (std::int32_t value : values) total = (total + value) & {VALUE_MASK};
    return (total - 9) & {VALUE_MASK};
}}

"""
        if pattern == "trailing_lists":
            return """struct TrailingRecord { std::int32_t left; std::int32_t right; };
std::int32_t trailing_sum(std::int32_t left, std::int32_t right) {
    std::int32_t values[2] = { left, right };
    TrailingRecord record { values[0], values[1] };
    return record.left + record.right;
}
std::int32_t trailing_lists(std::int32_t seed) { return trailing_sum(seed, 0); }

"""
        if pattern == "generic_arity":
            return """template<class Left, class Right> struct GenericPair { Left left; Right right; };
template<class Value> using GenericIdentity = Value;
std::int32_t generic_pair_left(GenericPair<std::int32_t, bool> value) {
    GenericIdentity<std::int32_t> left = value.left; return left;
}
std::int32_t generic_arity(std::int32_t seed) {
    return generic_pair_left(GenericPair<std::int32_t, bool> { seed, true });
}

"""
        if pattern == "pattern_list_forms":
            return """struct PatternListEvent { bool has_value; std::int32_t value; };
std::int32_t pattern_list_score(PatternListEvent value) { return value.has_value ? value.value : 0; }
std::int32_t pattern_list_forms(std::int32_t seed) {
    return pattern_list_score({ false, 0 }) + pattern_list_score({ true, seed });
}

"""
        if pattern == "bound_list_forms":
            return """template<class Left, class Right> std::int32_t preserve_bound_pair(Left left, Right) {
    return static_cast<std::int32_t>(left);
}
std::int32_t bound_list_forms(std::int32_t seed) { return preserve_bound_pair(seed, true); }

"""
        if pattern == "statement_postfix_forms":
            return """struct StatementRecord {
    std::int32_t value;
    std::int32_t statement_value() const { return value; }
};
void observe_statement(std::int32_t) {}
StatementRecord make_statement_record(std::int32_t value) { return { value }; }
std::int32_t statement_postfix_forms(std::int32_t seed) {
    observe_statement(0);
    StatementRecord record { seed };
    return record.statement_value() + make_statement_record(0).value;
}

"""
        if pattern == "public_items":
            return """inline constexpr std::int32_t PUBLIC_ZERO = 0;
using PublicScore = std::int32_t;
struct PublicRecord { PublicScore value; std::int32_t read() const { return value; } };
struct PublicChoice { bool selected; std::int32_t value; };
template<class T> struct PublicPolicy { static std::int32_t public_policy(T value) { return value; } };
std::int32_t public_items(std::int32_t seed) {
    PublicRecord record { seed }; PublicChoice choice { true, 0 };
    return record.read() + (choice.selected ? choice.value : 0) + PUBLIC_ZERO;
}

"""
        if pattern == "empty_aggregates":
            return """struct EmptyRecord {};
std::int32_t empty_aggregates(std::int32_t seed) {
    EmptyRecord empty_record {}; (void)empty_record; return seed;
}

"""
    if language == "c":
        if pattern == "contracts":
            return f'''typedef struct {{ int32_t (*score_policy)(int32_t); }} {prefix}score_policy_contract;
static int32_t {prefix}score_policy_i32(int32_t value) {{ return value & 4095; }}
static int32_t {prefix}preserve_scored(int32_t value, {prefix}score_policy_contract contract) {{
    (void)contract.score_policy(value); return value;
}}

'''
        if pattern == "const_generic":
            return f'''static int32_t {prefix}first_const_generic(int32_t first, const int32_t values[static 4]) {{ return first; }}

'''
        if pattern == "borrowed_views":
            return f'''typedef struct {{ int32_t value; }} {prefix}BorrowedValue;
static int32_t {prefix}borrowed_marker(const {prefix}BorrowedValue* value) {{ return value->value; }}
static int32_t {prefix}first_slice(const int32_t* values, size_t count) {{ return count == 0 ? 0 : values[0]; }}

'''
        if pattern == "foreign_api":
            return '''extern int getpid(void);

'''
        if pattern == "literal_data":
            return f'''static int32_t {prefix}literal_metadata(void) {{
    const char* label = "module-{index}"; char delimiter = ':'; float ratio = 1.25f;
    (void)label; (void)delimiter; (void)ratio; return 0;
}}

'''
        if pattern == "language_forms":
            return f"""extern int unbound_probe(void);
static int32_t {prefix}zero_value(void) {{ return 0; }}
static void {prefix}record_positive(int32_t value) {{ if (value > 0) return; }}
static int32_t {prefix}language_forms(int32_t seed) {{
    int32_t inferred = +seed; int32_t grouped = ((inferred));
    {prefix}record_positive(grouped); return grouped + {prefix}zero_value();
}}

"""
        if pattern == "operator_forms":
            return f"""static int32_t {prefix}operator_forms(int32_t seed) {{
    int32_t value = seed;
    value += 3; value -= 3; value *= 2; value /= 2; value %= {VALUE_MASK + 1};
    value ^= 0; value <<= 1; value >>= 1; value &= {VALUE_MASK}; value |= 0;
    return value;
}}

"""
        if pattern == "primitive_forms":
            return f"""static int32_t {prefix}primitive_forms(void) {{
    uint8_t tiny = 1; uint32_t unsigned_value = 2; size_t count = 3;
    int64_t wide = 4; float decimal = 1.5f; _Bool truth = 1;
    char letter = 'x'; const char* text = "types"; void* address = NULL;
    (void)tiny; (void)unsigned_value; (void)count; (void)wide; (void)decimal;
    (void)truth; (void)letter; (void)text; (void)address; return 0;
}}

"""
        if pattern == "range_forms":
            return f"""static int32_t {prefix}range_forms(int32_t seed) {{
    int32_t total = seed;
    for (int32_t value = 1; value <= 3; ++value) total = (total + value) & {VALUE_MASK};
    for (int32_t value = 0; value < 3; ++value) total = (total + value) & {VALUE_MASK};
    for (int32_t value = 0; value <= 2; ++value) total = (total + value) & {VALUE_MASK};
    for (int32_t value = 2;; ++value) {{ total = (total + value) & {VALUE_MASK}; if (value == 4) break; }}
    for (int32_t value = 0;; ++value) {{ total = (total + value) & {VALUE_MASK}; if (value == 2) break; }}
    return (total - 24) & {VALUE_MASK};
}}

"""
        if pattern == "match_forms":
            return f"""static int32_t {prefix}integer_pattern_score(int32_t value) {{
    switch (value) {{ case 0: return 5; case 1: return 7; default: return 9; }}
}}
static int32_t {prefix}boolean_pattern_score(_Bool value) {{ return value ? 3 : 4; }}
static int32_t {prefix}match_forms(int32_t seed) {{
    return {prefix}integer_pattern_score(seed % 3) + {prefix}boolean_pattern_score((seed & 1) == 0);
}}

"""
        if pattern == "enum_tuple_patterns":
            return f"""typedef enum {{ {prefix}MOVED, {prefix}IDLE }} {prefix}coordinate_event_kind;
typedef struct {{ {prefix}coordinate_event_kind kind; int32_t x; int32_t y; }} {prefix}coordinate_event;
static int32_t {prefix}coordinate_event_score({prefix}coordinate_event event) {{
    return event.kind == {prefix}MOVED ? event.x * 3 + event.y : 1;
}}
static int32_t {prefix}enum_tuple_patterns(int32_t seed) {{
    {prefix}coordinate_event moved = {{ {prefix}MOVED, seed % 7, (seed / 7) % 7 }};
    {prefix}coordinate_event idle = {{ {prefix}IDLE, 0, 0 }};
    return {prefix}coordinate_event_score(moved) + {prefix}coordinate_event_score(idle);
}}

"""
        if pattern == "iterable_forms":
            return f"""static int32_t {prefix}iterable_forms(int32_t seed) {{
    int32_t values[4] = {{ seed, 2, 3, 4 }};
    int32_t total = 0;
    for (size_t index = 0; index < 4; ++index) total = (total + values[index]) & {VALUE_MASK};
    return (total - 9) & {VALUE_MASK};
}}

"""
        if pattern == "trailing_lists":
            return f"""typedef struct {{ int32_t left; int32_t right; }} {prefix}trailing_record;
static int32_t {prefix}trailing_sum(int32_t left, int32_t right) {{
    int32_t values[2] = {{ left, right }};
    {prefix}trailing_record record = {{ values[0], values[1] }};
    return record.left + record.right;
}}
static int32_t {prefix}trailing_lists(int32_t seed) {{ return {prefix}trailing_sum(seed, 0); }}

"""
        if pattern == "generic_arity":
            return f"""typedef int32_t {prefix}generic_identity_i32;
typedef struct {{ int32_t left; _Bool right; }} {prefix}generic_pair_i32_bool;
static int32_t {prefix}generic_pair_left({prefix}generic_pair_i32_bool value) {{ return value.left; }}
static int32_t {prefix}generic_arity(int32_t seed) {{
    {prefix}generic_pair_i32_bool pair = {{ seed, 1 }};
    return {prefix}generic_pair_left(pair);
}}

"""
        if pattern == "pattern_list_forms":
            return f"""typedef struct {{ _Bool has_value; int32_t value; }} {prefix}pattern_list_event;
static int32_t {prefix}pattern_list_score({prefix}pattern_list_event value) {{
    return value.has_value ? value.value : 0;
}}
static int32_t {prefix}pattern_list_forms(int32_t seed) {{
    {prefix}pattern_list_event empty = {{ 0, 0 }};
    {prefix}pattern_list_event value = {{ 1, seed }};
    return {prefix}pattern_list_score(empty) + {prefix}pattern_list_score(value);
}}

"""
        if pattern == "bound_list_forms":
            return f"""static int32_t {prefix}preserve_bound_pair(int32_t left, _Bool right) {{
    (void)right; return left;
}}
static int32_t {prefix}bound_list_forms(int32_t seed) {{ return {prefix}preserve_bound_pair(seed, 1); }}

"""
        if pattern == "statement_postfix_forms":
            return f"""typedef struct {{ int32_t value; }} {prefix}statement_record;
static int32_t {prefix}statement_value({prefix}statement_record record) {{ return record.value; }}
static void {prefix}observe_statement(int32_t value) {{ (void)value; }}
static {prefix}statement_record {prefix}make_statement_record(int32_t value) {{
    {prefix}statement_record record = {{ value }}; return record;
}}
static int32_t {prefix}statement_postfix_forms(int32_t seed) {{
    {prefix}observe_statement(0);
    {prefix}statement_record record = {{ seed }};
    return {prefix}statement_value(record) + {prefix}make_statement_record(0).value;
}}

"""
        if pattern == "public_items":
            return f"""enum {{ {prefix}PUBLIC_ZERO = 0 }};
typedef int32_t {prefix}public_score;
typedef struct {{ {prefix}public_score value; }} {prefix}public_record;
typedef struct {{ _Bool selected; int32_t value; }} {prefix}public_choice;
static int32_t {prefix}public_items(int32_t seed) {{
    {prefix}public_record record = {{ seed }};
    {prefix}public_choice choice = {{ 1, 0 }};
    return record.value + (choice.selected ? choice.value : 0) + {prefix}PUBLIC_ZERO;
}}

"""
        if pattern == "empty_aggregates":
            return f"""typedef struct {{ unsigned char unused; }} {prefix}empty_record;
static int32_t {prefix}empty_aggregates(int32_t seed) {{
    {prefix}empty_record empty = {{ 0 }}; (void)empty; return seed;
}}

"""
    if language == "zig":
        if pattern == "contracts":
            return """const ScorePolicy = struct { score_policy: *const fn (i32) i32 };
fn score_policy_i32(value: i32) i32 { return value & 4095; }
fn preserve_scored(value: i32, contract: ScorePolicy) i32 { _ = contract.score_policy(value); return value; }

"""
        if pattern == "const_generic":
            return """fn first_const_generic(first: i32, comptime N: usize, values: [N]i32) i32 { _ = values; return first; }

"""
        if pattern == "borrowed_views":
            return """const BorrowedValue = struct {
    value: i32,
    fn borrowed_marker(self: *const BorrowedValue) i32 { return self.value; }
};
fn first_slice(values: []const i32) i32 { return if (values.len == 0) 0 else values[0]; }

"""
        if pattern == "foreign_api":
            return '''extern fn getpid() c_int;

'''
        if pattern == "literal_data":
            return f'''fn literal_metadata() i32 {{
    const label = "module-{index}"; const delimiter: u8 = ':'; const ratio: f32 = 1.25;
    _ = label; _ = delimiter; _ = ratio; return 0;
}}

'''
        if pattern == "language_forms":
            return """extern fn unbound_probe() c_int;
fn zero_value() i32 { return 0; }
fn record_positive(value: i32) void { if (value > 0) return; }
fn language_forms(seed: i32) i32 {
    const inferred = seed; const grouped = ((inferred));
    record_positive(grouped); return grouped + zero_value();
}

"""
        if pattern == "operator_forms":
            return f"""fn operator_forms(seed: i32) i32 {{
    var value = seed;
    value += 3; value -= 3; value *= 2;
    value = @divTrunc(value, 2); value = @mod(value, {VALUE_MASK + 1});
    value ^= 0; value <<= 1; value >>= 1; value &= {VALUE_MASK}; value |= 0;
    return value;
}}

"""
        if pattern == "primitive_forms":
            return """fn primitive_forms() i32 {
    const tiny: u8 = 1; const unsigned_value: u32 = 2; const count: usize = 3;
    const wide: i64 = 4; const decimal: f32 = 1.5; const truth: bool = true;
    const letter: u8 = 'x'; const text: []const u8 = "types"; const address: ?*anyopaque = null;
    _ = tiny; _ = unsigned_value; _ = count; _ = wide; _ = decimal;
    _ = truth; _ = letter; _ = text; _ = address; return 0;
}

"""
        if pattern == "range_forms":
            return f"""fn range_forms(seed: i32) i32 {{
    var total = seed;
    for (1..4) |raw| {{ const value: i32 = @intCast(raw); total = (total + value) & {VALUE_MASK}; }}
    for (0..3) |raw| {{ const value: i32 = @intCast(raw); total = (total + value) & {VALUE_MASK}; }}
    for (0..3) |raw| {{ const value: i32 = @intCast(raw); total = (total + value) & {VALUE_MASK}; }}
    var from_value: i32 = 2;
    while (true) : (from_value += 1) {{ total = (total + from_value) & {VALUE_MASK}; if (from_value == 4) break; }}
    var full_value: i32 = 0;
    while (true) : (full_value += 1) {{ total = (total + full_value) & {VALUE_MASK}; if (full_value == 2) break; }}
    return (total - 24) & {VALUE_MASK};
}}

"""
        if pattern == "match_forms":
            return """fn integer_pattern_score(value: i32) i32 {
    return switch (value) { 0 => 5, 1 => 7, else => 9 };
}
fn boolean_pattern_score(value: bool) i32 { return if (value) 3 else 4; }
fn match_forms(seed: i32) i32 {
    return integer_pattern_score(@mod(seed, 3)) + boolean_pattern_score((seed & 1) == 0);
}

"""
        if pattern == "enum_tuple_patterns":
            return """const CoordinateEvent = union(enum) {
    moved: struct { x: i32, y: i32 },
    idle,
};
fn coordinate_event_score(event: CoordinateEvent) i32 {
    return switch (event) { .moved => |point| point.x * 3 + point.y, .idle => 1 };
}
fn enum_tuple_patterns(seed: i32) i32 {
    const moved = CoordinateEvent { .moved = .{ .x = @mod(seed, 7), .y = @mod(@divTrunc(seed, 7), 7) } };
    return coordinate_event_score(moved) + coordinate_event_score(.idle);
}

"""
        if pattern == "iterable_forms":
            return f"""fn iterable_forms(seed: i32) i32 {{
    const values = [_]i32{{ seed, 2, 3, 4 }};
    var total: i32 = 0;
    for (values) |value| total = (total + value) & {VALUE_MASK};
    return (total - 9) & {VALUE_MASK};
}}

"""
        if pattern == "trailing_lists":
            return """const TrailingRecord = struct { left: i32, right: i32 };
fn trailing_sum(left: i32, right: i32) i32 {
    const values = [_]i32{ left, right };
    const record = TrailingRecord { .left = values[0], .right = values[1] };
    return record.left + record.right;
}
fn trailing_lists(seed: i32) i32 { return trailing_sum(seed, 0); }

"""
        if pattern == "generic_arity":
            return """fn GenericPair(comptime Left: type, comptime Right: type) type {
    return struct { left: Left, right: Right };
}
fn GenericIdentity(comptime Value: type) type { return Value; }
fn generic_pair_left(value: GenericPair(i32, bool)) GenericIdentity(i32) { return value.left; }
fn generic_arity(seed: i32) i32 {
    const pair = GenericPair(i32, bool) { .left = seed, .right = true };
    return generic_pair_left(pair);
}

"""
        if pattern == "pattern_list_forms":
            return """const PatternListEvent = union(enum) { empty, value: i32 };
fn pattern_list_score(value: PatternListEvent) i32 {
    return switch (value) { .empty => 0, .value => |inner| inner };
}
fn pattern_list_forms(seed: i32) i32 {
    return pattern_list_score(.empty) + pattern_list_score(.{ .value = seed });
}

"""
        if pattern == "bound_list_forms":
            return """fn preserve_bound_pair(left: anytype, right: anytype) @TypeOf(left) {
    _ = right; return left;
}
fn bound_list_forms(seed: i32) i32 { return preserve_bound_pair(seed, true); }

"""
        if pattern == "statement_postfix_forms":
            return """const StatementRecord = struct {
    value: i32,
    fn statement_value(self: StatementRecord) i32 { return self.value; }
};
fn observe_statement(value: i32) void { _ = value; }
fn make_statement_record(value: i32) StatementRecord { return .{ .value = value }; }
fn statement_postfix_forms(seed: i32) i32 {
    observe_statement(0);
    const record = StatementRecord { .value = seed };
    return record.statement_value() + make_statement_record(0).value;
}

"""
        if pattern == "public_items":
            return """pub const PUBLIC_ZERO: i32 = 0;
pub const PublicScore = i32;
pub const PublicRecord = struct { value: PublicScore, fn read(self: PublicRecord) i32 { return self.value; } };
pub const PublicChoice = union(enum) { selected: i32, empty };
fn public_items(seed: i32) i32 {
    const record = PublicRecord { .value = seed };
    const choice = PublicChoice { .selected = 0 };
    const adjustment = switch (choice) { .selected => |inner| inner, .empty => 0 };
    return record.read() + adjustment + PUBLIC_ZERO;
}

"""
        if pattern == "empty_aggregates":
            return """const EmptyRecord = struct {};
fn empty_aggregates(seed: i32) i32 {
    const empty_record = EmptyRecord {};
    const empty_values = [_]i32{};
    _ = empty_record; _ = empty_values; return seed;
}

"""
    raise ValueError((language, pattern))


def render_runtime_probe(language: str) -> str:
    if language == "lanius":
        return """fn runtime_probe() -> i32 {
    let capacity: usize = 32;
    let memory: ptr = alloc::allocator::alloc(capacity, 8);
    if (memory == 0) { return 1; }
    let argument_count: i32 = std::process::argc();
    let working_directory_length: i32 = std::env::current_dir_len();
    let seconds: i32 = std::time::unix_seconds();
    let random_value: u32 = std::random::secure_u32();
    let source: i32 = std::fs::open_read_path("lanius/main.lani");
    if (source < 0) {
        alloc::allocator::dealloc(memory, capacity, 8);
        return 2;
    }
    let source_close: i32 = std::fs::close_file(source);
    alloc::allocator::dealloc(memory, capacity, 8);
    if (argument_count < 1) { return 3; }
    if (working_directory_length <= 0) { return 4; }
    if (seconds <= 0) { return 5; }
    if (source_close < 0) { return 6; }
    if (random_value != random_value) { return 7; }
    return 0;
}

"""
    if language in {"c", "cpp"}:
        return """static int32_t runtime_probe(int argc) {
    void* memory = malloc(32);
    if (memory == NULL) return 1;
    char working_directory[4096];
    if (argc < 1 || getcwd(working_directory, sizeof(working_directory)) == NULL) {
        free(memory); return 2;
    }
    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now) != 0) { free(memory); return 3; }
    uint32_t random_value = 0;
    if (getrandom(&random_value, sizeof(random_value), 0) != sizeof(random_value)) {
        free(memory); return 4;
    }
    FILE* source = fopen("lanius/main.lani", "rb");
    if (source == NULL) { free(memory); return 5; }
    if (fclose(source) != 0) { free(memory); return 6; }
    free(memory);
    return random_value != random_value ? 7 : 0;
}

"""
    if language == "rust":
        return """fn runtime_probe() -> i32 {
    let mut memory = vec![0_u8; 32];
    memory[0] = 1;
    if std::env::args_os().count() < 1 { return 1; }
    if std::env::current_dir().is_err() { return 2; }
    if std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).is_err() { return 3; }
    let mut random_file = match std::fs::File::open("/dev/urandom") {
        Ok(file) => file,
        Err(_) => return 4,
    };
    let mut random_bytes = [0_u8; 4];
    if std::io::Read::read_exact(&mut random_file, &mut random_bytes).is_err() { return 5; }
    if std::fs::File::open("lanius/main.lani").is_err() { return 6; }
    drop(memory);
    0
}

"""
    if language == "zig":
        return """fn runtime_probe(argument_count: usize) i32 {
    const memory = c.malloc(32) orelse return 1;
    defer c.free(memory);
    var working_directory: [4096]u8 = undefined;
    if (argument_count < 1 or c.getcwd(&working_directory, working_directory.len) == null) return 2;
    var now: c.struct_timespec = undefined;
    if (c.clock_gettime(c.CLOCK_REALTIME, &now) != 0) return 3;
    var random_value: u32 = 0;
    if (c.getrandom(&random_value, @sizeOf(u32), 0) != @sizeOf(u32)) return 4;
    const source = c.fopen("lanius/main.lani", "rb") orelse return 5;
    if (c.fclose(source) != 0) return 6;
    return if (random_value != random_value) 7 else 0;
}

"""
    raise ValueError(language)


def evaluate_archetype(archetype: str, seed: int, index: int) -> int:
    if archetype == "policy":
        return (seed + ((seed % 7) + 1 if seed & 1 == 0 else -1)) & VALUE_MASK
    if archetype == "processor":
        values = (seed, index & 31, 3, 7, 11, 13)
        total = 0
        cursor = 0
        while cursor < len(values):
            if cursor == 1:
                cursor += 1
                continue
            if cursor == 5:
                break
            total = (total + values[cursor]) & VALUE_MASK
            cursor += 1
        return total
    if archetype == "service":
        left = (seed + index) & VALUE_MASK
        right = (seed * 2 + 3) & VALUE_MASK
        adjustment = index % 7 + 1
        return ((left + adjustment) * 3 + (right - adjustment)) & VALUE_MASK
    if archetype == "planner":
        total = 0
        limit = 3 + index % 4
        for outer in range(limit):
            for inner in range(3):
                if inner == 1 and outer % 2 == 0:
                    continue
                total = (total + seed + outer * 3 + inner) & VALUE_MASK
        first = next(
            (candidate for candidate in range(6) if (seed + candidate) % 4 == 0),
            6,
        )
        return (total + first) & VALUE_MASK
    if archetype == "tracker":

        def decay(value: int, remaining: int) -> int:
            if remaining <= 0:
                return value
            mixed = ((value << 1) ^ (value >> 1) ^ index) & VALUE_MASK
            return decay(mixed, remaining - 1)

        delta = -(index % 5 + 1)
        return (decay(seed, 3) - delta) & VALUE_MASK
    if archetype == "summary":
        return (seed + index) & VALUE_MASK
    raise ValueError(archetype)


def render_archetype(
    language: str, archetype: str, module_name: str, index: int
) -> str:
    renderer = {
        "lanius": render_lanius,
        "rust": render_rust,
        "zig": render_zig,
        "c": render_c,
        "cpp": render_cpp,
    }.get(language)
    if renderer is None:
        raise ValueError(language)
    return renderer(archetype, module_name, index)


def render_lanius(archetype: str, _module_name: str, index: int) -> str:
    if archetype == "policy":
        return f"""enum Adjustment {{
    Add(i32),
    Hold,
}}

fn choose_adjustment(seed: i32) -> Adjustment {{
    if ((seed & 1) == 0) {{
        return Add((seed % 7) + 1);
    }}
    return Hold;
}}

fn workload_score(seed: i32) -> i32 {{
    let adjustment: Adjustment = choose_adjustment(seed);
    return match (adjustment) {{
        Add(amount) -> (seed + amount) & {VALUE_MASK},
        Hold -> (seed - 1) & {VALUE_MASK},
    }};
}}

"""
    if archetype == "processor":
        return f"""fn workload_score(seed: i32) -> i32 {{
    let values: [i32; 6] = [seed, {index & 31}, 3, 7, 11, 13];
    let cursor: i32 = 0;
    let total: i32 = 0;
    while (cursor < 6) {{
        if (cursor == 1) {{
            cursor += 1;
            continue;
        }}
        if (cursor == 5) {{
            break;
        }}
        total += values[cursor];
        total &= {VALUE_MASK};
        cursor += 1;
    }}
    return total;
}}

"""
    if archetype == "service":
        return f"""struct ServiceState {{
    left: i32,
    right: i32,
}}

impl ServiceState {{
    fn from_parts(left: i32, right: i32) -> ServiceState {{
        return ServiceState {{ left: left, right: right }};
    }}

    fn new(seed: i32) -> ServiceState {{
        return ServiceState::from_parts(
            (seed + {index}) & {VALUE_MASK},
            (seed * 2 + 3) & {VALUE_MASK},
        );
    }}

    fn adjusted(self, amount: i32) -> ServiceState {{
        return ServiceState::from_parts(self.left + amount, self.right - amount);
    }}

    fn score(self) -> i32 {{
        return (self.left * 3 + self.right) & {VALUE_MASK};
    }}
}}

fn workload_score(seed: i32) -> i32 {{
    let state: ServiceState = ServiceState::new(seed);
    let adjusted: ServiceState = state.adjusted({index % 7 + 1});
    return adjusted.score();
}}

"""
    if archetype == "planner":
        return f"""fn first_eligible(seed: i32) -> i32 {{
    for candidate in 0 .. 6 {{
        if (((seed + candidate) % 4) == 0) {{
            return candidate;
        }}
    }}
    return 6;
}}

fn workload_score(seed: i32) -> i32 {{
    let total: i32 = 0;
    let limit: i32 = {3 + index % 4};
    for outer in 0 .. limit {{
        for inner in 0 .. 3 {{
            if (inner == 1 && (outer % 2) == 0) {{
                continue;
            }}
            total = (total + seed + outer * 3 + inner) & {VALUE_MASK};
        }}
    }}
    let preview: i32 = total;
    {{
        let preview: i32 = 0;
        if (preview < 0) {{ return 0; }}
    }}
    return (total + first_eligible(seed)) & {VALUE_MASK};
}}

"""
    if archetype == "tracker":
        return f"""fn decay(value: i32, remaining: i32) -> i32 {{
    if (remaining <= 0) {{
        return value;
    }}
    let mixed: i32 = ((value << 1) ^ (value >> 1) ^ {index}) & {VALUE_MASK};
    return decay(mixed, remaining - 1);
}}

fn workload_score(seed: i32) -> i32 {{
    let delta: i32 = -{index % 5 + 1};
    let enabled: bool = !false;
    if (enabled) {{
        return (decay(seed, 3) - delta) & {VALUE_MASK};
    }}
    return 0;
}}

"""
    return f"""type SummaryScore = i32;

const SUMMARY_OFFSET: SummaryScore = {index};

struct Envelope<T> {{
    value: T,
}}

fn unwrap<T>(envelope: Envelope<T>) -> T {{
    return envelope.value;
}}

fn workload_score(seed: i32) -> i32 {{
    let envelope: Envelope<i32> = Envelope {{ value: seed + SUMMARY_OFFSET }};
    return unwrap(envelope) & {VALUE_MASK};
}}

"""


def render_rust(archetype: str, _module_name: str, index: int) -> str:
    if archetype == "policy":
        return f"""enum Adjustment {{
    Add(i32),
    Hold,
}}

fn choose_adjustment(seed: i32) -> Adjustment {{
    if seed & 1 == 0 {{ Adjustment::Add(seed % 7 + 1) }} else {{ Adjustment::Hold }}
}}

fn workload_score(seed: i32) -> i32 {{
    match choose_adjustment(seed) {{
        Adjustment::Add(amount) => (seed + amount) & {VALUE_MASK},
        Adjustment::Hold => (seed - 1) & {VALUE_MASK},
    }}
}}

"""
    if archetype == "processor":
        return f"""fn workload_score(seed: i32) -> i32 {{
    let values: [i32; 6] = [seed, {index & 31}, 3, 7, 11, 13];
    let mut cursor: usize = 0;
    let mut total: i32 = 0;
    while cursor < values.len() {{
        if cursor == 1 {{
            cursor += 1;
            continue;
        }}
        if cursor == 5 {{ break; }}
        total = (total + values[cursor]) & {VALUE_MASK};
        cursor += 1;
    }}
    total
}}

"""
    if archetype == "service":
        return f"""struct ServiceState {{
    left: i32,
    right: i32,
}}

impl ServiceState {{
    fn new(seed: i32) -> Self {{
        Self {{ left: (seed + {index}) & {VALUE_MASK}, right: (seed * 2 + 3) & {VALUE_MASK} }}
    }}

    fn adjusted(self, amount: i32) -> Self {{
        Self {{ left: self.left + amount, right: self.right - amount }}
    }}

    fn score(self) -> i32 {{ (self.left * 3 + self.right) & {VALUE_MASK} }}
}}

fn workload_score(seed: i32) -> i32 {{
    ServiceState::new(seed).adjusted({index % 7 + 1}).score()
}}

"""
    if archetype == "planner":
        return f"""fn first_eligible(seed: i32) -> i32 {{
    for candidate in 0..6 {{
        if (seed + candidate) % 4 == 0 {{ return candidate; }}
    }}
    6
}}

fn workload_score(seed: i32) -> i32 {{
    let mut total: i32 = 0;
    let limit: i32 = {3 + index % 4};
    for outer in 0..limit {{
        for inner in 0..3 {{
            if inner == 1 && outer % 2 == 0 {{ continue; }}
            total = (total + seed + outer * 3 + inner) & {VALUE_MASK};
        }}
    }}
    {{
        let total = total;
        if total < 0 {{ return 0; }}
    }}
    (total + first_eligible(seed)) & {VALUE_MASK}
}}

"""
    if archetype == "tracker":
        return f"""fn decay(value: i32, remaining: i32) -> i32 {{
    if remaining <= 0 {{ return value; }}
    let mixed = ((value << 1) ^ (value >> 1) ^ {index}) & {VALUE_MASK};
    decay(mixed, remaining - 1)
}}

fn workload_score(seed: i32) -> i32 {{
    let delta = -{index % 5 + 1};
    let enabled = !false;
    if enabled {{ (decay(seed, 3) - delta) & {VALUE_MASK} }} else {{ 0 }}
}}

"""
    return f"""type SummaryScore = i32;
const SUMMARY_OFFSET: SummaryScore = {index};

struct Envelope<T> {{ value: T }}

fn unwrap<T>(envelope: Envelope<T>) -> T {{ envelope.value }}

fn workload_score(seed: i32) -> i32 {{
    let envelope: Envelope<i32> = Envelope {{ value: seed + SUMMARY_OFFSET }};
    unwrap(envelope) & {VALUE_MASK}
}}

"""


def render_c(archetype: str, module_name: str, index: int) -> str:
    prefix = f"{module_name}_"
    if archetype == "policy":
        return f"""typedef enum {{ {prefix}ADD, {prefix}HOLD }} {prefix}AdjustmentKind;
typedef struct {{ {prefix}AdjustmentKind kind; int32_t amount; }} {prefix}Adjustment;

static {prefix}Adjustment {prefix}choose_adjustment(int32_t seed) {{
    if ((seed & 1) == 0) return ({prefix}Adjustment) {{ {prefix}ADD, seed % 7 + 1 }};
    return ({prefix}Adjustment) {{ {prefix}HOLD, 0 }};
}}

static int32_t {prefix}workload_score(int32_t seed) {{
    {prefix}Adjustment adjustment = {prefix}choose_adjustment(seed);
    if (adjustment.kind == {prefix}ADD) return (seed + adjustment.amount) & {VALUE_MASK};
    return (seed - 1) & {VALUE_MASK};
}}

"""
    if archetype == "processor":
        return f"""static int32_t {prefix}workload_score(int32_t seed) {{
    int32_t values[6] = {{ seed, {index & 31}, 3, 7, 11, 13 }};
    int32_t cursor = 0;
    int32_t total = 0;
    while (cursor < 6) {{
        if (cursor == 1) {{ cursor += 1; continue; }}
        if (cursor == 5) break;
        total = (total + values[cursor]) & {VALUE_MASK};
        cursor += 1;
    }}
    return total;
}}

"""
    if archetype == "service":
        return f"""typedef struct {{ int32_t left; int32_t right; }} {prefix}ServiceState;

static {prefix}ServiceState {prefix}new_state(int32_t seed) {{
    return ({prefix}ServiceState) {{ (seed + {index}) & {VALUE_MASK}, (seed * 2 + 3) & {VALUE_MASK} }};
}}

static {prefix}ServiceState {prefix}adjusted({prefix}ServiceState self, int32_t amount) {{
    return ({prefix}ServiceState) {{ self.left + amount, self.right - amount }};
}}

static int32_t {prefix}score({prefix}ServiceState self) {{
    return (self.left * 3 + self.right) & {VALUE_MASK};
}}

static int32_t {prefix}workload_score(int32_t seed) {{
    {prefix}ServiceState state = {prefix}new_state(seed);
    return {prefix}score({prefix}adjusted(state, {index % 7 + 1}));
}}

"""
    if archetype == "planner":
        return f"""static int32_t {prefix}first_eligible(int32_t seed) {{
    for (int32_t candidate = 0; candidate < 6; ++candidate)
        if ((seed + candidate) % 4 == 0) return candidate;
    return 6;
}}

static int32_t {prefix}workload_score(int32_t seed) {{
    int32_t total = 0;
    int32_t limit = {3 + index % 4};
    for (int32_t outer = 0; outer < limit; ++outer) {{
        for (int32_t inner = 0; inner < 3; ++inner) {{
            if (inner == 1 && outer % 2 == 0) continue;
            total = (total + seed + outer * 3 + inner) & {VALUE_MASK};
        }}
    }}
    {{ int32_t total = total; if (total < 0) return 0; }}
    return (total + {prefix}first_eligible(seed)) & {VALUE_MASK};
}}

"""
    if archetype == "tracker":
        return f"""static int32_t {prefix}decay(int32_t value, int32_t remaining) {{
    if (remaining <= 0) return value;
    int32_t mixed = ((value << 1) ^ (value >> 1) ^ {index}) & {VALUE_MASK};
    return {prefix}decay(mixed, remaining - 1);
}}

static int32_t {prefix}workload_score(int32_t seed) {{
    int32_t delta = -{index % 5 + 1};
    int enabled = !0;
    return enabled ? ({prefix}decay(seed, 3) - delta) & {VALUE_MASK} : 0;
}}

"""
    return f"""typedef int32_t {prefix}SummaryScore;
static const {prefix}SummaryScore {prefix}SUMMARY_OFFSET = {index};
typedef struct {{ int32_t value; }} {prefix}Envelope;

static int32_t {prefix}unwrap({prefix}Envelope envelope) {{ return envelope.value; }}

static int32_t {prefix}workload_score(int32_t seed) {{
    {prefix}Envelope envelope = {{ seed + {prefix}SUMMARY_OFFSET }};
    return {prefix}unwrap(envelope) & {VALUE_MASK};
}}

"""


def render_cpp(archetype: str, _module_name: str, index: int) -> str:
    if archetype == "policy":
        return f"""enum class AdjustmentKind {{ add, hold }};
struct Adjustment {{ AdjustmentKind kind; std::int32_t amount; }};

static Adjustment choose_adjustment(std::int32_t seed) {{
    if ((seed & 1) == 0) return {{ AdjustmentKind::add, seed % 7 + 1 }};
    return {{ AdjustmentKind::hold, 0 }};
}}

static std::int32_t workload_score(std::int32_t seed) {{
    auto adjustment = choose_adjustment(seed);
    if (adjustment.kind == AdjustmentKind::add) return (seed + adjustment.amount) & {VALUE_MASK};
    return (seed - 1) & {VALUE_MASK};
}}

"""
    if archetype == "processor":
        return f"""static std::int32_t workload_score(std::int32_t seed) {{
    std::int32_t values[6] = {{ seed, {index & 31}, 3, 7, 11, 13 }};
    std::int32_t cursor = 0;
    std::int32_t total = 0;
    while (cursor < 6) {{
        if (cursor == 1) {{ ++cursor; continue; }}
        if (cursor == 5) break;
        total = (total + values[cursor]) & {VALUE_MASK};
        ++cursor;
    }}
    return total;
}}

"""
    if archetype == "service":
        return f"""struct ServiceState {{
    std::int32_t left;
    std::int32_t right;

    static ServiceState create(std::int32_t seed) {{
        return {{ (seed + {index}) & {VALUE_MASK}, (seed * 2 + 3) & {VALUE_MASK} }};
    }}
    ServiceState adjusted(std::int32_t amount) const {{ return {{ left + amount, right - amount }}; }}
    std::int32_t score() const {{ return (left * 3 + right) & {VALUE_MASK}; }}
}};

static std::int32_t workload_score(std::int32_t seed) {{
    return ServiceState::create(seed).adjusted({index % 7 + 1}).score();
}}

"""
    if archetype == "planner":
        return f"""static std::int32_t first_eligible(std::int32_t seed) {{
    for (std::int32_t candidate = 0; candidate < 6; ++candidate)
        if ((seed + candidate) % 4 == 0) return candidate;
    return 6;
}}

static std::int32_t workload_score(std::int32_t seed) {{
    std::int32_t total = 0;
    for (std::int32_t outer = 0; outer < {3 + index % 4}; ++outer)
        for (std::int32_t inner = 0; inner < 3; ++inner) {{
            if (inner == 1 && outer % 2 == 0) continue;
            total = (total + seed + outer * 3 + inner) & {VALUE_MASK};
        }}
    {{ std::int32_t total = total; if (total < 0) return 0; }}
    return (total + first_eligible(seed)) & {VALUE_MASK};
}}

"""
    if archetype == "tracker":
        return f"""static std::int32_t decay(std::int32_t value, std::int32_t remaining) {{
    if (remaining <= 0) return value;
    auto mixed = ((value << 1) ^ (value >> 1) ^ {index}) & {VALUE_MASK};
    return decay(mixed, remaining - 1);
}}

static std::int32_t workload_score(std::int32_t seed) {{
    auto delta = -{index % 5 + 1};
    return !false ? (decay(seed, 3) - delta) & {VALUE_MASK} : 0;
}}

"""
    return f"""using SummaryScore = std::int32_t;
static constexpr SummaryScore summary_offset = {index};
template <typename T> struct Envelope {{ T value; }};
template <typename T> static T unwrap(Envelope<T> envelope) {{ return envelope.value; }}

static std::int32_t workload_score(std::int32_t seed) {{
    Envelope<std::int32_t> envelope {{ seed + summary_offset }};
    return unwrap(envelope) & {VALUE_MASK};
}}

"""


def render_zig(archetype: str, _module_name: str, index: int) -> str:
    if archetype == "policy":
        return f"""const Adjustment = union(enum) {{ add: i32, hold }};

fn chooseAdjustment(seed: i32) Adjustment {{
    if ((seed & 1) == 0) return .{{ .add = @mod(seed, 7) + 1 }};
    return .hold;
}}

fn workloadScore(seed: i32) i32 {{
    return switch (chooseAdjustment(seed)) {{
        .add => |amount| (seed + amount) & {VALUE_MASK},
        .hold => (seed - 1) & {VALUE_MASK},
    }};
}}

"""
    if archetype == "processor":
        return f"""fn workloadScore(seed: i32) i32 {{
    const values = [6]i32{{ seed, {index & 31}, 3, 7, 11, 13 }};
    var cursor: usize = 0;
    var total: i32 = 0;
    while (cursor < values.len) {{
        if (cursor == 1) {{ cursor += 1; continue; }}
        if (cursor == 5) break;
        total = (total + values[cursor]) & {VALUE_MASK};
        cursor += 1;
    }}
    return total;
}}

"""
    if archetype == "service":
        return f"""const ServiceState = struct {{
    left: i32,
    right: i32,

    fn create(seed: i32) ServiceState {{
        return .{{ .left = (seed + {index}) & {VALUE_MASK}, .right = (seed * 2 + 3) & {VALUE_MASK} }};
    }}
    fn adjusted(self: ServiceState, amount: i32) ServiceState {{
        return .{{ .left = self.left + amount, .right = self.right - amount }};
    }}
    fn score(self: ServiceState) i32 {{ return (self.left * 3 + self.right) & {VALUE_MASK}; }}
}};

fn workloadScore(seed: i32) i32 {{ return ServiceState.create(seed).adjusted({index % 7 + 1}).score(); }}

"""
    if archetype == "planner":
        return f"""fn firstEligible(seed: i32) i32 {{
    for (0..6) |raw| {{
        const candidate: i32 = @intCast(raw);
        if (@mod(seed + candidate, 4) == 0) return candidate;
    }}
    return 6;
}}

fn workloadScore(seed: i32) i32 {{
    var total: i32 = 0;
    for (0..{3 + index % 4}) |outer_raw| {{
        const outer: i32 = @intCast(outer_raw);
        for (0..3) |inner_raw| {{
            const inner: i32 = @intCast(inner_raw);
            if (inner == 1 and @mod(outer, 2) == 0) continue;
            total = (total + seed + outer * 3 + inner) & {VALUE_MASK};
        }}
    }}
    {{ const preview = total; if (preview < 0) return 0; }}
    return (total + firstEligible(seed)) & {VALUE_MASK};
}}

"""
    if archetype == "tracker":
        return f"""fn decay(value: i32, remaining: i32) i32 {{
    if (remaining <= 0) return value;
    const mixed = ((value << 1) ^ (value >> 1) ^ {index}) & {VALUE_MASK};
    return decay(mixed, remaining - 1);
}}

fn workloadScore(seed: i32) i32 {{
    const delta: i32 = -{index % 5 + 1};
    return if (!false) (decay(seed, 3) - delta) & {VALUE_MASK} else 0;
}}

"""
    return f"""const SummaryScore = i32;
const summary_offset: SummaryScore = {index};

fn Envelope(comptime T: type) type {{ return struct {{ value: T }}; }}
fn unwrap(envelope: anytype) @TypeOf(envelope.value) {{ return envelope.value; }}

fn workloadScore(seed: i32) i32 {{
    const envelope = Envelope(i32){{ .value = seed + summary_offset }};
    return unwrap(envelope) & {VALUE_MASK};
}}

"""


def workload_call(language: str, module_name: str, argument: str) -> str:
    if language == "c":
        return f"{module_name}_workload_score({argument})"
    if language == "zig":
        return f"workloadScore({argument})"
    return f"workload_score({argument})"
