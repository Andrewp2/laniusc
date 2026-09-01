import Lanius.Compiler.Tokens
import Lean.Data.Json.FromToJson
import Lean

namespace Lanius.Extraction

abbrev FileId := Nat
abbrev TokenId := Nat
abbrev ParseNodeId := Nat
abbrev SurfaceNodeId := Nat
abbrev CoreNodeId := Nat

def schemaVersion : Nat := 5

/-- Half-open byte span in an extracted source file. -/
structure Span where
  file : FileId
  start : Nat
  finish : Nat
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

structure SourceFile where
  path : String
  bytes : List Nat
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

structure Token where
  kind : Nat
  span : Span
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

inductive ParseChild where
  | token : TokenId → ParseChild
  | node : ParseNodeId → ParseChild
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

structure ParseNode where
  production : Nat
  nonterminal : Nat
  position_start : Nat
  position_end : Nat
  children : List ParseChild
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

/-! ## Structurally typed Surface extraction

The untrusted exporter supplies an ordinary algebraic syntax tree. Every
semantic node identifies the grammar node that allegedly produced it, and
every spelling identifies the original token. These are claims only; the
Surface checker validates them against the already-certified parse tree.
-/

structure SpelledName where
  token : TokenId
  text : String
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

mutual
  structure SurfacePathSegment where
    id : SurfaceNodeId
    parse_node : ParseNodeId
    name : SpelledName
    arguments : List SurfaceTypeExpr

  structure SurfacePathValue where
    segments : List SurfacePathSegment

  structure SurfacePath where
    id : SurfaceNodeId
    parse_node : ParseNodeId
    value : SurfacePathValue

  inductive SurfaceArrayLength where
    | literal (token : TokenId) (text : String)
    | parameter (name : SpelledName)

  inductive SurfaceTypeExprValue where
    | path (path : SurfacePath)
    | array (element : SurfaceTypeExpr) (length : SurfaceArrayLength)
    | slice (element : SurfaceTypeExpr)
    | reference (referent : SurfaceTypeExpr)

  structure SurfaceTypeExpr where
    id : SurfaceNodeId
    parse_node : ParseNodeId
    value : SurfaceTypeExprValue
end

deriving instance BEq for
  SurfacePathSegment, SurfacePathValue, SurfacePath, SurfaceArrayLength,
  SurfaceTypeExprValue, SurfaceTypeExpr
deriving instance Repr for
  SurfacePathSegment, SurfacePathValue, SurfacePath, SurfaceArrayLength,
  SurfaceTypeExprValue, SurfaceTypeExpr
deriving instance Lean.FromJson for
  SurfacePathSegment, SurfacePathValue, SurfacePath, SurfaceArrayLength,
  SurfaceTypeExprValue, SurfaceTypeExpr
deriving instance Lean.ToExpr for
  SurfacePathSegment, SurfacePathValue, SurfacePath, SurfaceArrayLength,
  SurfaceTypeExprValue, SurfaceTypeExpr

inductive SurfaceUnaryOp where
  | positive | negative | logical_not
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive SurfaceBinaryOp where
  | logical_or | logical_and | bit_or | bit_xor | bit_and
  | equal | not_equal | less | greater | less_equal | greater_equal
  | shift_left | shift_right | add | subtract | multiply | divide | remainder
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive SurfaceAssignOp where
  | set | add | subtract | multiply | divide | remainder | bit_xor
  | shift_left | shift_right | bit_and | bit_or
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive SurfaceLiteral where
  | integer (token : TokenId) (text : String)
  | float (token : TokenId) (text : String)
  | string (token : TokenId) (text : String)
  | character (token : TokenId) (text : String)
  | boolean (value : Bool)
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

mutual
  structure SurfaceStructFieldValue where
    id : SurfaceNodeId
    parse_node : ParseNodeId
    name : SpelledName
    value : SurfaceExpr

  inductive SurfaceExprValue where
    | literal (literal : SurfaceLiteral)
    | path (path : SurfacePath)
    | array (elements : List SurfaceExpr)
    | struct_value (path : SurfacePath) (fields : List SurfaceStructFieldValue)
    | unary (operator : SurfaceUnaryOp) (operand : SurfaceExpr)
    | binary (operator : SurfaceBinaryOp) (left right : SurfaceExpr)
    | assign (operator : SurfaceAssignOp) (place value : SurfaceExpr)
    | call (callee : SurfaceExpr) (arguments : List SurfaceExpr)
    | index (base index : SurfaceExpr)
    | member (base : SurfaceExpr) (name : SpelledName)

  structure SurfaceExpr where
    id : SurfaceNodeId
    parse_node : ParseNodeId
    value : SurfaceExprValue
end


deriving instance BEq for SurfaceStructFieldValue, SurfaceExprValue, SurfaceExpr
deriving instance Repr for SurfaceStructFieldValue, SurfaceExprValue, SurfaceExpr
deriving instance Lean.FromJson for SurfaceStructFieldValue, SurfaceExprValue, SurfaceExpr
deriving instance Lean.ToExpr for SurfaceStructFieldValue, SurfaceExprValue, SurfaceExpr

mutual
  inductive SurfaceStmtValue where
    | let_local
        (name : SpelledName)
        (type_annotation : Option SurfaceTypeExpr)
        (initializer : Option SurfaceExpr)
    | return_value (value : Option SurfaceExpr)
    | if_then_else
        (condition : SurfaceExpr)
        (then_body else_body : List SurfaceStmt)
    | while_loop (condition : SurfaceExpr) (body : List SurfaceStmt)
    | block (body : List SurfaceStmt)
    | expression (expression : SurfaceExpr)
    | break_loop
    | continue_loop

  structure SurfaceStmt where
    id : SurfaceNodeId
    parse_node : ParseNodeId
    value : SurfaceStmtValue
end


deriving instance BEq for SurfaceStmtValue, SurfaceStmt
deriving instance Repr for SurfaceStmtValue, SurfaceStmt
deriving instance Lean.FromJson for SurfaceStmtValue, SurfaceStmt
deriving instance Lean.ToExpr for SurfaceStmtValue, SurfaceStmt

structure SurfaceParameter where
  id : SurfaceNodeId
  parse_node : ParseNodeId
  name : SpelledName
  type_expression : SurfaceTypeExpr
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure SurfaceFunction where
  name : SpelledName
  is_public : Bool
  parameters : List SurfaceParameter
  return_type : Option SurfaceTypeExpr
  body : List SurfaceStmt
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure SurfaceStructField where
  id : SurfaceNodeId
  parse_node : ParseNodeId
  name : SpelledName
  type_expression : SurfaceTypeExpr
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure SurfaceStruct where
  name : SpelledName
  is_public : Bool
  fields : List SurfaceStructField
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive SurfaceItemValue where
  | module (path : SurfacePath)
  | import_path (path : SurfacePath)
  | function (function : SurfaceFunction)
  | constant
      (name : SpelledName) (is_public : Bool)
      (type_expression : SurfaceTypeExpr) (value : SurfaceExpr)
  | type_alias
      (name : SpelledName) (is_public : Bool) (target : SurfaceTypeExpr)
  | structure (declaration : SurfaceStruct)
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure SurfaceItem where
  id : SurfaceNodeId
  parse_node : ParseNodeId
  value : SurfaceItemValue
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure SurfaceFileValue where
  items : List SurfaceItem
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure SurfaceFile where
  id : SurfaceNodeId
  parse_node : ParseNodeId
  value : SurfaceFileValue
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

/-! ## Structurally typed Core extraction

Core syntax is located independently of source syntax so lowering evidence can
name both sides of every transformation without resorting to untyped tags or
payload offsets. The checker decodes these wire values into `Lanius.Core` only
after validating resolution, typing, and lowering rules.
-/

inductive CorePointerWidth where
  | bits32 | bits64
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure CoreTarget where
  pointer_width : CorePointerWidth
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreSignedIntTy where
  | i8 | i16 | i32 | i64 | isize
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreUnsignedIntTy where
  | u8 | u16 | u32 | u64 | usize
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreScalarTy where
  | bool
  | signed (ty : CoreSignedIntTy)
  | unsigned (ty : CoreUnsignedIntTy)
  | f32 | f64 | char | string | raw_ptr
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreTy where
  | unit
  | scalar (ty : CoreScalarTy)
  | array (element : CoreTy) (length : Nat)
  | slice (element : CoreTy)
  | reference (referent : CoreTy)
  | structure (id : Nat)
  | enumeration (id : Nat)
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreValueProjection where
  | field (field : Nat)
  | index (index : Nat)
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreValue where
  | unit
  | boolean (value : Bool)
  | signed (ty : CoreSignedIntTy) (value : Int)
  | unsigned (ty : CoreUnsignedIntTy) (value : Nat)
  | f32_bits (bits : Nat)
  | f64_bits (bits : Nat)
  | character (value : Nat)
  | string (value : String)
  | pointer (address : Nat)
  | array (elements : List CoreValue)
  | slice
      (element_type : CoreTy) (cell : Nat)
      (projections : List CoreValueProjection) (start length : Nat)
  | structure (id : Nat) (fields : List CoreValue)
  | enumeration (id variant : Nat) (payload : List CoreValue)
  | reference
      (referent : CoreTy) (cell : Nat)
      (projections : List CoreValueProjection)
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreUnaryOp where
  | positive | logical_not | negate
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreBinaryOp where
  | logical_and | logical_or | equal | not_equal
  | less | less_equal | greater | greater_equal
  | add | subtract | multiply | divide | remainder
  | bit_and | bit_or | bit_xor | shift_left | shift_right
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreAssignOp where
  | set | add | subtract | multiply | divide | remainder
  | bit_xor | shift_left | shift_right | bit_and | bit_or
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreHostService where
  | open_read_path | open_write_path | read_i32
  | write_text | write_i32 | write_byte | write_newline | close_file
  | i32_to_f32 | exit | secure_u32
  | alloc | dealloc | argc | arg_len | arg_read | unix_seconds
  | current_dir_read | var_count | var_key_len | var_key_read | var_len | var_read
  | close | read | write | open_read | open_write | open_append
  | write_stdout | write_stderr | read_stdin | fill_secure_bytes
  | remove_file | create_dir | remove_dir | rename
  | monotonic_read | system_read | sleep_ms_i32 | realloc | alloc_failed
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreCapability where
  | clock | network | thread | gpu | test_harness
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreExternalBehavior where
  | host (service : CoreHostService)
  | unavailable (capability : CoreCapability)
  | panic
  | unreachable
  | opaque (id : Nat)
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive CoreIntrinsic where
  | print_i32 | assert
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

mutual
  structure CorePattern where
    id : CoreNodeId
    value : CorePatternValue

  inductive CorePatternValue where
    | wildcard
    | bind (id : Nat)
    | literal (value : CoreValue)
    | enum_variant (type_id variant : Nat) (payload : List CorePattern)

  structure CoreExpr where
    id : CoreNodeId
    value : CoreExprValue

  inductive CoreExprValue where
    | value (value : CoreValue)
    | local (id : Nat)
    | cast (target : CoreScalarTy) (operand : CoreExpr)
    | unary (op : CoreUnaryOp) (operand : CoreExpr)
    | binary (op : CoreBinaryOp) (left right : CoreExpr)
    | array (element_type : CoreTy) (elements : List CoreExpr)
    | array_to_slice (element_type : CoreTy) (array : CoreExpr)
    | index (base index : CoreExpr)
    | struct_value (id : Nat) (fields : List CoreExpr)
    | field (base : CoreExpr) (field : Nat)
    | enum_value (id variant : Nat) (payload : List CoreExpr)
    | match_value (scrutinee : CoreExpr) (arms : List (CorePattern × CoreExpr))
    | assign (op : CoreAssignOp) (place : CorePlace) (value : CoreExpr)
    | borrow (referent : CoreTy) (place : CorePlace)
    | dereference (reference : CoreExpr)
    | constant (id : Nat)
    | call (function : Nat) (arguments : List CoreExpr)
    | intrinsic (operation : CoreIntrinsic) (argument : CoreExpr)
    | i32_array_data_ptr (array : CoreExpr)
    | alloc (size alignment : CoreExpr)
    | realloc (pointer old_size new_size alignment : CoreExpr)
    | dealloc (pointer size alignment : CoreExpr)
    | load_byte (pointer offset : CoreExpr)
    | store_byte (pointer offset value : CoreExpr)

  structure CorePlace where
    id : CoreNodeId
    value : CorePlaceValue

  inductive CorePlaceValue where
    | local (id : Nat)
    | field (base : CorePlace) (field : Nat)
    | index (base : CorePlace) (index : CoreExpr)
end

deriving instance BEq for
  CorePattern, CorePatternValue, CoreExpr, CoreExprValue, CorePlace, CorePlaceValue
deriving instance Repr for
  CorePattern, CorePatternValue, CoreExpr, CoreExprValue, CorePlace, CorePlaceValue
deriving instance Lean.FromJson for
  CorePattern, CorePatternValue, CoreExpr, CoreExprValue, CorePlace, CorePlaceValue
deriving instance Lean.ToExpr for
  CorePattern, CorePatternValue, CoreExpr, CoreExprValue, CorePlace, CorePlaceValue

mutual
  structure CoreStmt where
    id : CoreNodeId
    value : CoreStmtValue

  inductive CoreStmtValue where
    | skip
    | expression (expression : CoreExpr)
    | sequence (first second : CoreStmt)
    | let_local (id : Nat) (ty : CoreTy) (initializer : CoreExpr) (body : CoreStmt)
    | let_uninitialized (id : Nat) (ty : CoreTy) (body : CoreStmt)
    | if_then_else (condition : CoreExpr) (then_branch else_branch : CoreStmt)
    | while_loop (condition : CoreExpr) (body : CoreStmt)
    | for_values (id : Nat) (iterable : CoreExpr) (body : CoreStmt)
    | for_range
        (id : Nat) (start : CoreExpr) (stop : Option CoreExpr)
        (inclusive : Bool) (body : CoreStmt)
    | return_value (value : Option CoreExpr)
    | break_loop
    | continue_loop
end

deriving instance BEq for CoreStmt, CoreStmtValue
deriving instance Repr for CoreStmt, CoreStmtValue
deriving instance Lean.FromJson for CoreStmt, CoreStmtValue
deriving instance Lean.ToExpr for CoreStmt, CoreStmtValue

structure CoreStructDecl where
  id : Nat
  fields : List CoreTy
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure CoreEnumDecl where
  id : Nat
  variants : List (List CoreTy)
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure CoreFunction where
  id : Nat
  parameters : List (Nat × CoreTy)
  return_type : CoreTy
  body : Option CoreStmt
  external : Option CoreExternalBehavior
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure CoreConstant where
  id : Nat
  ty : CoreTy
  value : CoreValue
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

structure CoreProgram where
  target : CoreTarget
  structures : List CoreStructDecl
  enumerations : List CoreEnumDecl
  constants : List CoreConstant
  functions : List CoreFunction
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive Namespace where
  | value
  | type
  | module
  | field
  | variant
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

/-- The role of a source node as a lexical-scope anchor. The role is part of
    the identity: the then- and else-bodies of one `if` share a Surface node
    but are distinct scopes. -/
inductive LexicalScopeKind where
  | function_body
  | after_local
  | then_body
  | else_body
  | loop_body
  | block_body
deriving BEq, DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

structure LexicalScopeIdentity where
  kind : LexicalScopeKind
  node : SurfaceNodeId
deriving BEq, DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

structure ResolutionEvidence where
  use_node : SurfaceNodeId
  /-- Pack unit whose local Surface identity space contains the declaration. -/
  declaration_unit : Nat
  declaration_node : SurfaceNodeId
  namespace_tag : Namespace
  /-- Lexical scopes examined from the use site toward the function root. -/
  scope_path : List LexicalScopeIdentity
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

inductive TypeRule where
  | literal
  | local
  | constant
  | unary
  | binary
  | assignment
  | call
  | index
  | field
  | struct_value
  | return_rule
  | branch
  | loop
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

structure TypeEvidence where
  surface_node : SurfaceNodeId
  ty : CoreTy
  rule : TypeRule
  premises : List Nat
deriving BEq, Repr, Lean.FromJson, Lean.ToExpr

inductive LoweringRule where
  | declaration
  | literal
  | local
  | unary
  | binary
  | assignment
  | call
  | index
  | field
  | aggregate
  | statement
  | control_flow
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

structure LoweringEvidence where
  surface_node : SurfaceNodeId
  core_node : CoreNodeId
  rule : LoweringRule
  premises : List Nat
deriving DecidableEq, Repr, Lean.FromJson, Lean.ToExpr

/-- Data accepted from the untrusted CPU exporter. This structure has no
    semantic invariants; those enter only through verified checkers. -/
structure Artifact where
  schema_version : Nat
  sources : List SourceFile
  tokens : List Token
  /-- Untrusted complete lexer trace, including trivia.  The token checker
      validates every step before using it to certify the canonical stream. -/
  raw_tokens : Option (List Token) := none
  semantic_token_kinds : List Nat
  parse_nodes : List ParseNode
  /-- Optional bounded chunks for kernel-efficient random access.  Surface
      checking accepts them only when their flattening is exactly
      `parse_nodes`; exporters need not provide this cache. -/
  parse_node_chunks : Option (List (List ParseNode)) := none
  parse_root : Option ParseNodeId
  surface : Option SurfaceFile
  resolutions : List ResolutionEvidence
  types : List TypeEvidence
  core_program : Option CoreProgram
  lowering : List LoweringEvidence
deriving Repr, Lean.FromJson, Lean.ToExpr

/-- A dependency-ready set of source artifacts whose Core identities share one
    global namespace. File-local token, parse, and Surface identities remain
    scoped to their unit. -/
structure ArtifactPack where
  schema_version : Nat
  units : List Artifact
deriving Repr, Lean.FromJson, Lean.ToExpr

def Artifact.empty : Artifact := {
  schema_version := schemaVersion
  sources := []
  tokens := []
  raw_tokens := none
  semantic_token_kinds := []
  parse_nodes := []
  parse_node_chunks := none
  parse_root := none
  surface := none
  resolutions := []
  types := []
  core_program := none
  lowering := []
}

end Lanius.Extraction
