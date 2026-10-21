import verified_compiler.tests.direct_surface_binary_dispatch
import verified_compiler.tests.direct_surface_unary_dispatch
import verified_compiler.tests.direct_surface_local

namespace SurfaceExpressionTreeProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceOperationsProof SurfaceBinaryProof SurfaceBinaryDispatchProof
open SurfaceUnaryProof SurfaceUnaryDispatchProof IRBuilderNavigationProof
open SurfaceLocalProof SourceIdentifierProof

/-- A specification of supported expressions, not a second emitted IR. -/
inductive Expression where
  | literal (value : Bool)
  | integer (value : Int)
  | localName (token : Nat) (spelling : List UInt8)
  | unary (operation : Unary) (child : Expression)
  | binary (operation : Binary) (left right : Expression)

def Expression.output : Expression → List UInt8
  | .literal value => bytes value
  | .integer value => OutputSignedProof.bytes value
  | .localName _ spelling => World.utf8Bytes "«" ++ spelling ++ World.utf8Bytes "»"
  | .unary operation child => operation.wrap child.output
  | .binary operation leftChild rightChild => binaryBytes operation leftChild.output rightChild.output

/-- Relate the specification to the existing builder tree and native leaf
    annotations. Child positions come from that tree's endpoints. -/
def Represents (tree : Ready region { heap := reference }) (expression : Expression) (index : Nat)
    (scope : Scope := .unrestricted) : Prop :=
  index < region.count ∧ match expression with
    | .literal value => region.events index = booleanEvent value ∧ region.hasResultTypes = true ∧
        readRawSliceIndex extractedProgram { heap := reference } referenceType
          region.resultAddress region.resultLength index = .ok (IRTypeRefProof.referenceValue .Bool)
    | .integer value => region.events index = SurfaceIntegerProof.integerEvent value ∧
        (-2147483648 ≤ value ∧ value < 2147483648) ∧ (0 ≤ value ∨ value = -2147483648)
    | .localName token spelling => region.events index = localEvent token ∧
        ∃ name : Name reference, ∃ metadata : Metadata, scope = .fixed metadata ∧
          metadata.names = name.catalog.value ∧ metadata.unit = name.unitIndex ∧
          name.tokenIndex = token ∧ name.bytes = spelling
    | .unary operation child => region.events index = operation.event ∧ Represents tree child (index + 1) scope
    | .binary operation leftChild rightChild => region.events index = operation.event ∧ NonPointerInput operation tree index ∧
        Represents tree leftChild (index + 1) scope ∧ Represents tree rightChild (tree.ends (index + 1)).toNat scope

theorem Represents.inside {tree : Ready region { heap := reference }} {expression : Expression}
    (represented : Represents tree expression index scope) : index < region.count := by
  cases expression <;> exact represented.1

/-- Closed printing for finite scalar/local trees using all unary/binary operators.
    Recursion and the pointer guard are proved, not assumed.
    This formatting contract does not re-prove operand typing or evaluation. -/
theorem actualTreeWriter (tree : Ready region { heap := reference }) (expression : Expression)
    {scope : Scope} (represented : Represents tree expression index scope) :
    Writer Context.expressionCall reference tree.value index expression.output scope := by
  induction expression generalizing index with
  | literal value =>
      obtain ⟨inside, event, annotations, annotation⟩ := represented
      intro current context input representation nameContext room environment
      let retained := (tree.reheap (after := { current with heap := reference }) rfl).ofReads input.memory.reads
      have read : readRawSliceIndex extractedProgram { current with heap := reference } referenceType
          region.resultAddress region.resultLength index = .ok (IRTypeRefProof.referenceValue .Bool) := annotation
      exact actualBooleanExpression context retained value representation inside event annotations
        (input.memory.reads.rawSlice read) room environment
  | integer value =>
      obtain ⟨inside, event, canonical, allowed⟩ := represented
      intro current context input representation nameContext room environment
      exact actualIntegerExpression context (tree.ofReads input.memory.reads) value representation inside event
        canonical allowed room environment
  | localName token spelling =>
      obtain ⟨inside, event, name, metadata, rfl, catalog, unit, rfl, rfl⟩ := represented
      intro current context input representation nameContext room environment
      exact SurfaceLocalProof.actualExpression context input (tree.ofReads input.memory.reads) name
        representation inside event ((congrArg Metadata.names nameContext).trans catalog)
        ((congrArg Metadata.unit nameContext).trans unit) room environment
  | unary operation child recurse =>
      obtain ⟨inside, parent, childInput⟩ := represented
      have helper : Writer Context.unaryCall reference tree.value index (operation.wrap child.output) scope := by
        intro current context input representation nameContext room environment
        exact actualUnaryStep operation context input (tree.reheap (after := { current with heap := reference }) rfl)
          representation childInput.inside parent (recurse childInput) nameContext room environment
      intro current context input representation nameContext room environment
      exact actualUnaryDispatch operation context input (tree.reheap (after := { current with heap := reference }) rfl)
        representation inside parent helper nameContext room environment
  | binary operation leftChild rightChild recurseLeft recurseRight =>
      obtain ⟨inside, parent, scalar, leftInput, rightInput⟩ := represented
      have helper : Writer Context.binaryCall reference tree.value index (binaryBytes operation leftChild.output rightChild.output) scope := by
        intro current context input representation nameContext room environment
        exact actualBinaryStep operation context input (tree.reheap (after := { current with heap := reference }) rfl)
          representation inside scalar parent (recurseLeft leftInput) (recurseRight rightInput) nameContext room environment
      intro current context input representation nameContext room environment
      exact actualBinaryDispatch operation context input (tree.reheap (after := { current with heap := reference }) rfl)
        representation inside parent helper nameContext room environment

#print axioms actualTreeWriter

/-- The earlier Boolean-child route is a specialization of the closed result,
    not another copy of the native helper and dispatcher proof. -/
example (tree : Ready region { heap := reference }) (value : Bool)
    (represented : Represents tree (.unary .not (.literal value)) index) :
    Writer Context.expressionCall reference tree.value index (Unary.not.wrap (bytes value)) :=
  actualTreeWriter tree (.unary .not (.literal value)) represented

end SurfaceExpressionTreeProof
