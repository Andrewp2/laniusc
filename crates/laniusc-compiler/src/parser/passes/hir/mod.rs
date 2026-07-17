/// Array literal record passes.
pub mod array;
/// Binary expression span and result passes.
pub mod binary;
/// Call expression and argument record passes.
pub mod call;
/// Final Pareas-style compact HIR phase boundary.
pub mod canonical;
/// Context relation passes for nearest statement, block, and control owners.
pub mod context;
/// Enum, variant, and match-related HIR passes.
pub mod enums;
/// Expression form and result-root passes.
pub mod expr;
/// Function signature and return-type passes.
pub mod functions;
/// Index-expression span passes.
pub mod index_spans;
/// Item kind, declaration-token, namespace, visibility, and import passes.
pub mod item;
/// Generic list ranking helpers shared by HIR record families.
pub mod list;
/// Literal value extraction passes.
pub mod literal_values;
/// Match expression and arm record passes.
pub mod matches;
/// Member access record passes.
pub mod member;
/// Method declaration and receiver record passes.
pub mod method;
/// Tree-node to HIR-node classification pass.
pub mod nodes;
/// Parameter linking, ranking, id, and field passes.
pub mod param;
/// Canonical path segment ownership and ordinal lowering passes.
pub mod path;
/// Range-expression span passes.
pub mod range_spans;
/// HIR record clearing passes.
pub mod record;
/// Dense semantic-HIR topology and navigation passes.
pub mod semantic;
/// Common source-span propagation passes for HIR nodes.
pub mod spans;
/// Statement kind, scope, and assignment-field passes.
pub mod stmt_fields;
/// Statement scope relation passes.
pub mod stmt_scope;
/// Canonical decoded string literal lowering passes.
pub mod string;
/// Struct declaration, field, literal, and rank passes.
pub mod structs;
/// Type form, type-path, type-argument, and alias passes.
pub mod types;
