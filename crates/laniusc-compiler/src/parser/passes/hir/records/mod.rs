/// Tree-node to HIR-node classification pass.
pub mod classify_hir_nodes;
/// Call-specific HIR record clearing pass.
pub mod clear_call_and_member_records;
/// Base HIR record clearing pass.
pub mod clear_hir_records;
/// Exact floating candidate extraction using bounded storage workers.
pub mod convert_float_literals;
/// Call callee and context field pass.
pub mod extract_call_records;
/// Expression field extraction pass.
pub mod extract_expr_records;
/// Literal value extraction passes.
pub mod extract_literal_values;
/// Member/index postfix metadata materialization pass.
pub mod extract_postfix_records;
/// Statement kind, scope, and assignment-field passes.
pub mod extract_stmt_records;
/// Type form and type field extraction pass.
pub mod extract_type_records;
/// Expression result-root propagation pass.
pub mod walk_expr_result_roots;
