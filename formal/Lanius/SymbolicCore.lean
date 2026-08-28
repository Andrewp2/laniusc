import Lanius.Core
import Lanius.ScopeGraph

namespace Lanius.SymbolicCore

open Lanius
open Lanius.Core

/-!
`Core` is the executable semantic language.  This module adds a proof-facing
view over it; it deliberately does not introduce a second dynamic semantics.

Local identities come from source declarations and remain meaningful when the
numeric allocation chosen by lowering changes.  The access analysis below is
structural and binder-aware, so loop and call proofs can derive their live
caller frame instead of spelling ranges such as `id <= 30`.
-/

/-- Stable identity of one source local. `declaration` identifies the source
    parameter or `let`; the structured path distinguishes sibling scopes even
    when Core safely reuses their numeric local IDs. -/
structure LocalIdentity where
  functionDeclaration : ScopeGraph.DeclarationId
  declaration : ScopeGraph.DeclarationId
  /-- Canonical checked lexical path in root-to-use order. -/
  scope : List ScopeGraph.ScopeId
  name : String
deriving BEq, DecidableEq, Repr

inductive BindingKind where
  | parameter
  | local
  | pattern
  | iterator
deriving BEq, DecidableEq, Repr

/-- The only place where a stable source identity is associated with the
    numeric local selected by Core lowering. -/
structure LocalBinding where
  identity : LocalIdentity
  coreId : VarId
  type : Ty
  kind : BindingKind
deriving BEq, DecidableEq, Repr

structure LocalLayout where
  bindings : List LocalBinding
deriving BEq, Repr

/-- A finite set of source declarations whose Core storage must be retained.
    The declaration identity remains available even when proofs ultimately
    query the numeric Core local used by the evaluator. -/
abbrev LocalBindingFrame := List LocalBinding

namespace LocalBindingFrame

def coreIds (frame : LocalBindingFrame) : List VarId :=
  frame.map (·.coreId)

def ContainsCoreId (frame : LocalBindingFrame) (id : VarId) : Prop :=
  id ∈ frame.coreIds

def union (left right : LocalBindingFrame) : LocalBindingFrame :=
  left ++ right

end LocalBindingFrame

def LocalLayout.bindingsForId (layout : LocalLayout)
    (id : VarId) : List LocalBinding :=
  layout.bindings.filter (fun binding => binding.coreId == id)

def LocalLayout.bindingForIdentity? (layout : LocalLayout)
    (identity : LocalIdentity) : Option LocalBinding :=
  layout.bindings.find? (fun binding => binding.identity == identity)

def LocalLayout.bindingsNamed (layout : LocalLayout)
    (name : String) : List LocalBinding :=
  layout.bindings.filter (fun binding => binding.identity.name == name)

def scopePrefix : List ScopeGraph.ScopeId → List ScopeGraph.ScopeId → Bool
  | [], _ => true
  | _ :: _, [] => false
  | expected :: expectedTail, actual :: actualTail =>
      expected == actual && scopePrefix expectedTail actualTail

/-- Resolve a reused Core local at one lexical program point.  The longest
    enclosing scope wins, which is ordinary lexical shadowing. -/
def LocalLayout.bindingForIdAt? (layout : LocalLayout)
    (scope : List ScopeGraph.ScopeId) (id : VarId) : Option LocalBinding :=
  layout.bindings.foldl (fun selected binding =>
    if binding.coreId == id && scopePrefix binding.identity.scope scope then
      match selected with
      | none => some binding
      | some previous =>
          if previous.identity.scope.length ≤ binding.identity.scope.length
          then some binding else selected
    else selected) none

/-- A symbolic reference is membership in a checked layout, not a naked
    numeric identifier. -/
structure LocalRef (layout : LocalLayout) where
  binding : LocalBinding
  member : binding ∈ layout.bindings

/-- Resolve a spelling only when it identifies exactly one checked binding in
    the function layout.  This is appropriate for reusable proof resources
    that are not attached to a single lexical program point. -/
def LocalLayout.uniqueReferenceNamed? (layout : LocalLayout)
    (name : String) : Option (LocalRef layout) :=
  match named : layout.bindingsNamed name with
  | [binding] => some {
      binding
      member := by
        have inNamed : binding ∈ layout.bindingsNamed name := by
          rw [named]
          simp
        exact (List.mem_filter.mp inNamed).1
    }
  | _ => none

def LocalLayout.referenceForDeclaration? (layout : LocalLayout)
    (declaration : ScopeGraph.DeclarationId) : Option (LocalRef layout) :=
  match found : layout.bindings.find? (fun binding =>
      binding.identity.declaration == declaration) with
  | none => none
  | some binding => some {
      binding
      member := List.mem_of_find?_eq_some found
    }

/-- Resolve a source spelling at a lexical program point and retain the
    membership proof needed by separation assertions.  Reverse traversal
    chooses the nearest declaration in source order after scope filtering. -/
def LocalLayout.referenceNamedAt? (layout : LocalLayout)
    (scope : List ScopeGraph.ScopeId) (name : String) : Option (LocalRef layout) :=
  let reversed := layout.bindings.reverse
  match found : reversed.find? (fun binding =>
      binding.identity.name == name &&
        scopePrefix binding.identity.scope scope) with
  | none => none
  | some binding =>
      some {
        binding
        member := by
          have reversedMember : binding ∈ reversed :=
            List.mem_of_find?_eq_some found
          simpa [reversed] using reversedMember
      }

def LocalRef.identity (reference : LocalRef layout) : LocalIdentity :=
  reference.binding.identity

def LocalRef.coreId (reference : LocalRef layout) : VarId :=
  reference.binding.coreId

def LocalRef.expr (reference : LocalRef layout) : Core.Expr :=
  .local reference.coreId

def LocalRef.place (reference : LocalRef layout) : Core.Place :=
  .local reference.coreId

inductive AccessMode where
  | read
  | write
  | readWrite
deriving BEq, DecidableEq, Repr

/-- A checked declaration frame paired with the strongest access performed on
    each declaration.  Naming this representation keeps proof APIs from
    exposing an incidental list-of-pairs encoding. -/
abbrev LocalAccessFrame := List (LocalBinding × AccessMode)

namespace LocalAccessFrame

def bindings (frame : LocalAccessFrame) : LocalBindingFrame :=
  frame.map (·.1)

def ids (frame : LocalAccessFrame) : List VarId :=
  frame.bindings.coreIds

def excludingName (frame : LocalAccessFrame) (name : String) :
    LocalAccessFrame :=
  frame.filter (fun access => access.1.identity.name != name)

def withMode (frame : LocalAccessFrame) (mode : AccessMode) :
    LocalAccessFrame :=
  frame.filter (fun access => access.2 == mode)

end LocalAccessFrame

/-- Combine repeated accesses to the same source local.  A write following a
    read (or conversely) makes that local read/write; `readWrite` is absorbing.
    This is the lattice used by structural liveness and frame derivation. -/
def AccessMode.join : AccessMode → AccessMode → AccessMode
  | .read, .read => .read
  | .write, .write => .write
  | _, _ => .readWrite

structure LocalAccess where
  id : VarId
  mode : AccessMode
deriving BEq, DecidableEq, Repr

namespace LocalAccess

def read (id : VarId) : LocalAccess := ⟨id, .read⟩
def write (id : VarId) : LocalAccess := ⟨id, .write⟩
def readWrite (id : VarId) : LocalAccess := ⟨id, .readWrite⟩

def remove (id : VarId) (accesses : List LocalAccess) : List LocalAccess :=
  accesses.filter (fun access => access.id != id)

def ids (accesses : List LocalAccess) : List VarId :=
  accesses.map (·.id)

end LocalAccess

mutual
  def _root_.Lanius.Core.Pattern.boundLocals : Pattern → List VarId
    | .wildcard | .literal _ => []
    | .bind id => [id]
    | .enumVariant _ _ payload => listBoundLocals payload

  def _root_.Lanius.Core.Pattern.listBoundLocals : List Pattern → List VarId
    | [] => []
    | head :: tail =>
        boundLocals head ++ listBoundLocals tail
end

mutual
  def _root_.Lanius.Core.Expr.accesses : Expr → List LocalAccess
    | .value _ | .constant _ => []
    | .local id => [LocalAccess.read id]
    | .cast _ operand | .unary _ operand | .arrayToSlice _ operand |
        .field operand _ | .dereference operand | .intrinsic _ operand |
        .i32ArrayDataPtr operand => accesses operand
    | .binary _ left right | .index left right | .alloc left right |
        .loadByte left right => accesses left ++ accesses right
    | .array _ elements | .structValue _ elements |
        .enumValue _ _ elements | .call _ elements =>
        listAccesses elements
    | .matchValue scrutinee arms =>
        accesses scrutinee ++ matchArmAccesses arms
    | .assign operation place value =>
        assignmentAccesses operation place ++ accesses value
    | .borrow _ place => readAccesses place
    | .realloc pointer oldSize newSize alignment =>
        accesses pointer ++ accesses oldSize ++ accesses newSize ++
          accesses alignment
    | .dealloc pointer size alignment =>
        accesses pointer ++ accesses size ++ accesses alignment
    | .storeByte pointer offset value =>
        accesses pointer ++ accesses offset ++ accesses value

  def _root_.Lanius.Core.Expr.listAccesses : List Expr → List LocalAccess
    | [] => []
    | head :: tail => accesses head ++ listAccesses tail

  def _root_.Lanius.Core.Expr.matchArmAccesses :
      List (Pattern × Expr) → List LocalAccess
    | [] => []
    | (pattern, expression) :: tail =>
        (Pattern.boundLocals pattern).foldr LocalAccess.remove
            (accesses expression) ++
          matchArmAccesses tail

  def _root_.Lanius.Core.Place.readAccesses : Place → List LocalAccess
    | .local id => [LocalAccess.read id]
    | .field base _ => readAccesses base
    | .index base index =>
        readAccesses base ++ accesses index

  def _root_.Lanius.Core.Place.writeAccesses : Place → List LocalAccess
    | .local id => [LocalAccess.write id]
    | .field base _ => readWriteAccesses base
    | .index base index =>
        readWriteAccesses base ++ accesses index

  def _root_.Lanius.Core.Place.readWriteAccesses : Place → List LocalAccess
    | .local id => [LocalAccess.readWrite id]
    | .field base _ => readWriteAccesses base
    | .index base index =>
        readWriteAccesses base ++ accesses index

  def _root_.Lanius.Core.Place.assignmentAccesses (operation : AssignOp)
      (place : Place) : List LocalAccess :=
    match operation with
    | .set => writeAccesses place
    | _ => readWriteAccesses place
end

mutual
  /-- Accesses to locals inherited from the enclosing scope.  Accesses to a
      binder introduced by this statement are removed at that binder. -/
  def _root_.Lanius.Core.Stmt.freeAccesses : Stmt → List LocalAccess
    | .skip | .breakLoop | .continueLoop => []
    | .expression expression => Expr.accesses expression
    | .sequence first second =>
        freeAccesses first ++ freeAccesses second
    | .letLocal id _ initializer body =>
        Expr.accesses initializer ++
          LocalAccess.remove id (freeAccesses body)
    | .letUninitialized id _ body =>
        LocalAccess.remove id (freeAccesses body)
    | .ifThenElse condition thenBranch elseBranch =>
        Expr.accesses condition ++ freeAccesses thenBranch ++
          freeAccesses elseBranch
    | .whileLoop condition body =>
        Expr.accesses condition ++ freeAccesses body
    | .forValues id iterable body =>
        Expr.accesses iterable ++ LocalAccess.remove id (freeAccesses body)
    | .forRange id start stop _ body =>
        Expr.accesses start ++ optionalAccesses stop ++
          LocalAccess.remove id (freeAccesses body)
    | .returnValue value => optionalAccesses value

  def _root_.Lanius.Core.Expr.optionalAccesses :
      Option Expr → List LocalAccess
    | none => []
    | some expression => Expr.accesses expression
end

def _root_.Lanius.Core.Stmt.freeLocalIds (statement : Stmt) : List VarId :=
  LocalAccess.ids (Stmt.freeAccesses statement)

def _root_.Lanius.Core.Stmt.requires (statement : Stmt)
    (reference : LocalRef layout) : Prop :=
  reference.coreId ∈ Stmt.freeLocalIds statement

def LocalLayout.resolveAccessesAt
    (layout : LocalLayout) (scope : List ScopeGraph.ScopeId)
    (accesses : List LocalAccess) :
    List (LocalBinding × AccessMode) :=
  accesses.filterMap fun access =>
    (layout.bindingForIdAt? scope access.id).map fun binding =>
      (binding, access.mode)

def mergeResolvedAccess
    (access : LocalBinding × AccessMode) :
    List (LocalBinding × AccessMode) → List (LocalBinding × AccessMode)
  | [] => [access]
  | head :: tail =>
      if head.1 == access.1 then
        (head.1, AccessMode.join head.2 access.2) :: tail
      else
        head :: mergeResolvedAccess access tail

/-- Deduplicate a stream of resolved accesses while preserving first-use
    order and joining their access modes. -/
def mergeResolvedAccesses
    (accesses : List (LocalBinding × AccessMode)) :
    List (LocalBinding × AccessMode) :=
  accesses.foldl (fun merged access => mergeResolvedAccess access merged) []

def LocalLayout.freeBindingsAt
    (layout : LocalLayout) (scope : List ScopeGraph.ScopeId)
    (statement : Stmt) : List (LocalBinding × AccessMode) :=
  mergeResolvedAccesses
    (layout.resolveAccessesAt scope (Stmt.freeAccesses statement))

mutual
  def exprWellScoped (available : List VarId) : Expr → Bool
    | .value _ | .constant _ => true
    | .local id => id ∈ available
    | .cast _ operand | .unary _ operand | .arrayToSlice _ operand |
        .field operand _ | .dereference operand | .intrinsic _ operand |
        .i32ArrayDataPtr operand => exprWellScoped available operand
    | .binary _ left right | .index left right | .alloc left right |
        .loadByte left right =>
        exprWellScoped available left && exprWellScoped available right
    | .array _ elements | .structValue _ elements |
        .enumValue _ _ elements | .call _ elements =>
        exprListWellScoped available elements
    | .matchValue scrutinee arms =>
        exprWellScoped available scrutinee &&
          matchArmsWellScoped available arms
    | .assign _ place value =>
        placeWellScoped available place && exprWellScoped available value
    | .borrow _ place => placeWellScoped available place
    | .realloc pointer oldSize newSize alignment =>
        exprWellScoped available pointer && exprWellScoped available oldSize &&
          exprWellScoped available newSize &&
            exprWellScoped available alignment
    | .dealloc pointer size alignment =>
        exprWellScoped available pointer && exprWellScoped available size &&
          exprWellScoped available alignment
    | .storeByte pointer offset value =>
        exprWellScoped available pointer && exprWellScoped available offset &&
          exprWellScoped available value

  def exprListWellScoped (available : List VarId) : List Expr → Bool
    | [] => true
    | head :: tail =>
        exprWellScoped available head && exprListWellScoped available tail

  def matchArmsWellScoped (available : List VarId) :
      List (Pattern × Expr) → Bool
    | [] => true
    | (pattern, expression) :: tail =>
        exprWellScoped (Pattern.boundLocals pattern ++ available) expression &&
          matchArmsWellScoped available tail

  def placeWellScoped (available : List VarId) : Place → Bool
    | .local id => id ∈ available
    | .field base _ => placeWellScoped available base
    | .index base index =>
        placeWellScoped available base && exprWellScoped available index
end

def _root_.Lanius.Core.Expr.wellScoped := exprWellScoped
def _root_.Lanius.Core.Place.wellScoped := placeWellScoped

mutual
  def stmtWellScoped (available : List VarId) : Stmt → Bool
    | .skip | .breakLoop | .continueLoop => true
    | .expression expression => exprWellScoped available expression
    | .sequence first second =>
        stmtWellScoped available first && stmtWellScoped available second
    | .letLocal id _ initializer body =>
        exprWellScoped available initializer &&
          stmtWellScoped (id :: available) body
    | .letUninitialized id _ body => stmtWellScoped (id :: available) body
    | .ifThenElse condition thenBranch elseBranch =>
        exprWellScoped available condition &&
          stmtWellScoped available thenBranch &&
            stmtWellScoped available elseBranch
    | .whileLoop condition body =>
        exprWellScoped available condition && stmtWellScoped available body
    | .forValues id iterable body =>
        exprWellScoped available iterable &&
          stmtWellScoped (id :: available) body
    | .forRange id start stop _ body =>
        exprWellScoped available start &&
          exprOptionalWellScoped available stop &&
            stmtWellScoped (id :: available) body
    | .returnValue value => exprOptionalWellScoped available value

  def exprOptionalWellScoped (available : List VarId) : Option Expr → Bool
    | none => true
    | some expression => exprWellScoped available expression
end

def _root_.Lanius.Core.Stmt.wellScoped := stmtWellScoped
def _root_.Lanius.Core.Expr.optionalWellScoped := exprOptionalWellScoped

mutual
  def patternDeclaredLocals : Pattern → List VarId
    | .wildcard | .literal _ => []
    | .bind id => [id]
    | .enumVariant _ _ payload => patternListDeclaredLocals payload

  def patternListDeclaredLocals : List Pattern → List VarId
    | [] => []
    | head :: tail =>
        patternDeclaredLocals head ++ patternListDeclaredLocals tail
end

mutual
  def exprDeclaredLocals : Expr → List VarId
    | .value _ | .local _ | .constant _ => []
    | .cast _ operand | .unary _ operand | .arrayToSlice _ operand |
        .field operand _ | .dereference operand | .intrinsic _ operand |
        .i32ArrayDataPtr operand => exprDeclaredLocals operand
    | .binary _ left right | .index left right | .alloc left right |
        .loadByte left right =>
        exprDeclaredLocals left ++ exprDeclaredLocals right
    | .array _ elements | .structValue _ elements |
        .enumValue _ _ elements | .call _ elements =>
        exprListDeclaredLocals elements
    | .matchValue scrutinee arms =>
        exprDeclaredLocals scrutinee ++ matchArmDeclaredLocals arms
    | .assign _ place value =>
        placeDeclaredLocals place ++ exprDeclaredLocals value
    | .borrow _ place => placeDeclaredLocals place
    | .realloc pointer oldSize newSize alignment =>
        exprDeclaredLocals pointer ++ exprDeclaredLocals oldSize ++
          exprDeclaredLocals newSize ++ exprDeclaredLocals alignment
    | .dealloc pointer size alignment =>
        exprDeclaredLocals pointer ++ exprDeclaredLocals size ++
          exprDeclaredLocals alignment
    | .storeByte pointer offset value =>
        exprDeclaredLocals pointer ++ exprDeclaredLocals offset ++
          exprDeclaredLocals value

  def exprListDeclaredLocals : List Expr → List VarId
    | [] => []
    | head :: tail =>
        exprDeclaredLocals head ++ exprListDeclaredLocals tail

  def matchArmDeclaredLocals : List (Pattern × Expr) → List VarId
    | [] => []
    | (pattern, expression) :: tail =>
        patternDeclaredLocals pattern ++ exprDeclaredLocals expression ++
          matchArmDeclaredLocals tail

  def placeDeclaredLocals : Place → List VarId
    | .local _ => []
    | .field base _ => placeDeclaredLocals base
    | .index base index =>
        placeDeclaredLocals base ++ exprDeclaredLocals index
end

def _root_.Lanius.Core.Pattern.declaredLocals := patternDeclaredLocals
def _root_.Lanius.Core.Expr.declaredLocals := exprDeclaredLocals
def _root_.Lanius.Core.Place.declaredLocals := placeDeclaredLocals

mutual
  def stmtDeclaredLocals : Stmt → List VarId
    | .skip | .breakLoop | .continueLoop => []
    | .expression expression => exprDeclaredLocals expression
    | .sequence first second =>
        stmtDeclaredLocals first ++ stmtDeclaredLocals second
    | .letLocal id _ initializer body =>
        exprDeclaredLocals initializer ++ id :: stmtDeclaredLocals body
    | .letUninitialized id _ body => id :: stmtDeclaredLocals body
    | .ifThenElse condition thenBranch elseBranch =>
        exprDeclaredLocals condition ++ stmtDeclaredLocals thenBranch ++
          stmtDeclaredLocals elseBranch
    | .whileLoop condition body =>
        exprDeclaredLocals condition ++ stmtDeclaredLocals body
    | .forValues id iterable body =>
        exprDeclaredLocals iterable ++ id :: stmtDeclaredLocals body
    | .forRange id start stop _ body =>
        exprDeclaredLocals start ++ exprOptionalDeclaredLocals stop ++
          id :: stmtDeclaredLocals body
    | .returnValue value => exprOptionalDeclaredLocals value

  def exprOptionalDeclaredLocals : Option Expr → List VarId
    | none => []
    | some expression => exprDeclaredLocals expression
end

def _root_.Lanius.Core.Stmt.declaredLocals := stmtDeclaredLocals
def _root_.Lanius.Core.Expr.optionalDeclaredLocals :=
  exprOptionalDeclaredLocals

def _root_.Lanius.Core.Function.declaredLocals
    (function : Function) : List VarId :=
  function.parameters.map (·.1) ++
    (function.body.map Stmt.declaredLocals).getD []

def _root_.Lanius.Core.Function.wellScoped (function : Function) : Bool :=
  match function.body with
  | none => true
  | some body => Stmt.wellScoped (function.parameters.map (·.1)) body

def LocalLayout.coreIds (layout : LocalLayout) : List VarId :=
  layout.bindings.map (·.coreId)

def LocalLayout.identities (layout : LocalLayout) : List LocalIdentity :=
  layout.bindings.map (·.identity)

def LocalLayout.addresses (layout : LocalLayout) :
    List (List ScopeGraph.ScopeId × VarId) :=
  layout.bindings.map fun binding => (binding.identity.scope, binding.coreId)

def LocalLayout.wellFormed (layout : LocalLayout) : Bool :=
  decide layout.identities.Nodup && decide layout.addresses.Nodup

def LocalLayout.covers (layout : LocalLayout) (function : Function) : Bool :=
  layout.coreIds == function.declaredLocals

/-- A checked symbolic view shares the exact Core function.  `erase` is
    therefore definitionally the identity: there is no second semantics and
    no semantic-lowering trust gap. -/
structure FunctionView where
  core : Function
  locals : LocalLayout
  layoutWellFormed : locals.wellFormed = true
  layoutCoversCore : locals.covers core = true
  coreWellScoped : core.wellScoped = true

def FunctionView.erase (view : FunctionView) : Function := view.core

theorem FunctionView.erase_eq (view : FunctionView) :
    view.erase = view.core := rfl

end Lanius.SymbolicCore
