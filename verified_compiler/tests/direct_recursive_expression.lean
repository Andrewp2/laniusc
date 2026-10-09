import verified_compiler.tests.direct_constructor_payload
import verified_compiler.tests.direct_surface_expression_tree
import verified_compiler.tests.direct_surface_match

namespace RecursiveExpressionProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceExpressionTreeProof SurfaceOperationsProof
open SurfaceUnaryProof SurfaceUnaryDispatchProof SurfaceBinaryProof SurfaceBinaryDispatchProof
open IRBuilderNavigationProof

/- A mathematical specification over existing native IR, not emitted data or
    a typing witness. Constructors and match children can nest arbitrarily. -/
mutual
  inductive Term (reference : Heap) where
    | scalar (expression : Expression)
    | unary (operation : Unary) (child : Term reference)
    | binary (operation : Binary) (left right : Term reference)
    | constructor (variant : ConstructorNameProof.Variant reference)
        (name : TypeNameProof.Named reference) (children : List (Term reference))
    | matchValue (result : IRTypeRefProof.Reference) (typeId : Nat)
        (scrutinee : Term reference) (arms : List (Arm reference))
  inductive Arm (reference : Heap) where
    | arm (pattern : MatchArmProof.Pattern reference)
        (names : List (SourceIdentifierProof.Name reference)) (body : Term reference)
end

def Term.atomic : Term reference → Bool
  | .scalar expression => SurfaceMatchProof.atom expression
  | .unary _ _ | .binary _ _ _ | .constructor _ _ _ | .matchValue _ _ _ _ => false

mutual
  def Term.output : Term reference → List UInt8
    | .scalar expression => expression.output
    | .unary operation child => operation.wrap child.output
    | .binary operation left right => binaryBytes operation left.output right.output
    | .constructor variant name children => ConstructorPayloadProof.output variant name (children.map Term.output)
    | .matchValue _ _ scrutinee arms => SurfaceMatchProof.bytes scrutinee.output scrutinee.atomic (arms.map Arm.toStep) true
  def Arm.toStep : Arm reference → MatchArmsProof.Arm reference
    | .arm pattern names body => ⟨pattern, names, body.output⟩
end

mutual
  def Represents (tree : Ready region { heap := reference }) (metadata : Metadata) : Term reference → Nat → Prop
    | .scalar expression, index => SurfaceExpressionTreeProof.Represents tree expression index (.fixed metadata)
    | .unary operation child, index => index < region.count ∧ region.events index = operation.event ∧
        Represents tree metadata child (index + 1)
    | .binary operation left right, index => index < region.count ∧ region.events index = operation.event ∧
        NonPointerInput operation tree index ∧ Represents tree metadata left (index + 1) ∧
        Represents tree metadata right (tree.ends (index + 1)).toNat
    | .constructor variant name children, index => index < region.count ∧
        region.events index = ConstructorPayloadProof.event variant.typeIndex variant.ordinal children.length ∧
        metadata.types = variant.table.value ∧ metadata.names = variant.name.catalog.value ∧
        metadata.names = name.path.name.catalog.value ∧ name.index = variant.typeIndex ∧
        ChildrenRepresent tree metadata children (index + 1)
    | .matchValue result typeId scrutinee arms, index => index < region.count ∧
        region.events index = IRShapeProof.matchEvent result typeId arms.length ∧ arms.length < 2 ^ 31 ∧
        Represents tree metadata scrutinee (index + 1) ∧
        ArmsRepresent tree metadata typeId arms (tree.ends (index + 1))

  def ChildrenRepresent (tree : Ready region { heap := reference }) (metadata : Metadata) :
      List (Term reference) → Nat → Prop
    | [], _ => True
    | child :: rest, index => Represents tree metadata child index ∧
        ChildrenRepresent tree metadata rest (tree.ends index).toNat

  def ArmRepresents (tree : Ready region { heap := reference }) (metadata : Metadata) (typeId : Nat) :
      Arm reference → Nat → Prop
    | .arm pattern names body, index => pattern.Matches metadata typeId ∧ index < region.count ∧
        region.events index = IRShapeProof.armEvent pattern.ordinal names.length ∧ names.length < 2 ^ 31 ∧
        MatchBindingsProof.Represents tree metadata.names metadata.unit names (index + 1) ∧
        Represents tree metadata body (MatchBindingsProof.bodyIndex tree names (index + 1))

  def ArmsRepresent (tree : Ready region { heap := reference }) (metadata : Metadata) (typeId : Nat) :
      List (Arm reference) → Int → Prop
    | [], _ => True
    | arm :: rest, index => 0 ≤ index ∧ ArmRepresents tree metadata typeId arm index.toNat ∧
        ArmsRepresent tree metadata typeId rest (tree.ends index.toNat)
end

theorem Represents.inside {tree : Ready region { heap := reference }} {term : Term reference}
    (represented : Represents tree metadata term index) : index < region.count := by
  cases term with
  | scalar expression => exact SurfaceExpressionTreeProof.Represents.inside represented
  | unary _ _ | binary _ _ _ | constructor _ _ _ | matchValue _ _ _ _ => exact represented.1

/-- The actual atom classifier depends only on the node, not recursive
    execution. Constructor and match cases derive their false selection. -/
theorem actualClassifier (tree : Ready region { heap := reference }) (term : Term reference)
    (represented : Represents tree metadata term index) : SurfaceMatchProof.Classifier tree index term.atomic := by
  intro current reads formed
  let live := tree.ofReads reads
  cases term with
  | scalar expression => exact SurfaceMatchProof.actualClassifier tree expression represented reads formed
  | unary operation child =>
      have read := live.eventReads index represented.1
      rw [represented.2.1] at read
      exact actualNonAtom operation.event live represented.1 read (by cases operation <;> rfl) formed
  | binary operation left right =>
      have read := live.eventReads index represented.1
      rw [represented.2.1] at read
      exact actualBinaryClassifier operation live represented.1 read formed
  | constructor variant name children =>
      have read := live.eventReads index represented.1
      rw [represented.2.1] at read
      exact actualNonAtom (ConstructorPayloadProof.event variant.typeIndex variant.ordinal children.length)
        live represented.1 read rfl formed
  | matchValue result typeId scrutinee arms =>
      have read := live.eventReads index represented.1
      rw [represented.2.1] at read
      exact actualNonAtom (IRShapeProof.matchEvent result typeId arms.length) live represented.1 read rfl formed

/-- Closed printing for arbitrary finite nesting. The term/arm/list motives
    discharge every internal child contract; native premises never assume runs. -/
theorem actualTreeWriter (tree : Ready region { heap := reference }) (term : Term reference)
    (represented : Represents tree metadata term index) :
    Writer Context.expressionCall reference tree.value index term.output (.fixed metadata) := by
  have closed := Term.rec
    (motive_1 := fun term => ∀ index, Represents tree metadata term index →
      Writer Context.expressionCall reference tree.value index term.output (.fixed metadata))
    (motive_2 := fun arm => ∀ typeId index, ArmRepresents tree metadata typeId arm index →
      (arm.toStep).Represents tree metadata typeId index ∧
      Writer Context.expressionCall reference tree.value
        (MatchBindingsProof.bodyIndex tree (arm.toStep).names (index + 1)) (arm.toStep).body (.fixed metadata))
    (motive_3 := fun children => ∀ index, ChildrenRepresent tree metadata children index →
      ConstructorPayloadProof.ChildWriters tree (.fixed metadata) (children.map Term.output) index)
    (motive_4 := fun arms => ∀ typeId index, ArmsRepresent tree metadata typeId arms index →
      MatchArmsProof.Represents tree metadata typeId (arms.map Arm.toStep) index ∧
      MatchArmsProof.BodyWriters tree metadata (arms.map Arm.toStep) index)
    (fun expression index input => by
      simp only [Term.output]
      exact SurfaceExpressionTreeProof.actualTreeWriter tree expression input)
    (fun operation child recurse index represented => by
      simp only [Term.output]
      obtain ⟨inside, parent, childInput⟩ := represented
      have helper : Writer Context.unaryCall reference tree.value index (operation.wrap child.output) (.fixed metadata) := by
        intro current context input representation nameContext room environment
        exact actualUnaryStep operation context input (tree.reheap (after := { current with heap := reference }) rfl)
          representation childInput.inside parent (recurse _ childInput) nameContext room environment
      intro current context input representation nameContext room environment
      exact actualUnaryDispatch operation context input (tree.reheap (after := { current with heap := reference }) rfl)
        representation inside parent helper nameContext room environment)
    (fun operation left right recurseLeft recurseRight index represented => by
      simp only [Term.output]
      obtain ⟨inside, parent, scalar, leftInput, rightInput⟩ := represented
      have helper : Writer Context.binaryCall reference tree.value index
          (binaryBytes operation left.output right.output) (.fixed metadata) := by
        intro current context input representation nameContext room environment
        exact actualBinaryStep operation context input (tree.reheap (after := { current with heap := reference }) rfl)
          representation inside scalar parent (recurseLeft _ leftInput) (recurseRight _ rightInput)
          nameContext room environment
      intro current context input representation nameContext room environment
      exact actualBinaryDispatch operation context input (tree.reheap (after := { current with heap := reference }) rfl)
        representation inside parent helper nameContext room environment)
    (fun variant name children recurse index represented => by
      simp only [Term.output]
      obtain ⟨inside, parent, types, names, typeNames, sameType, payloads⟩ := represented
      intro current context input representation nameContext room environment
      exact ConstructorPayloadProof.actualExpressionStep context input tree variant name
        (children.map Term.output) representation inside (by simpa only [List.length_map] using parent)
        (recurse _ payloads) nameContext ((congrArg Metadata.types nameContext).trans types)
        ((congrArg Metadata.names nameContext).trans names)
        ((congrArg Metadata.names nameContext).trans typeNames) sameType room environment)
    (fun result typeId scrutinee arms recurseScrutinee recurseArms index represented => by
      simp only [Term.output]
      obtain ⟨inside, event, fits, scrutineeRep, armsRep⟩ := represented
      obtain ⟨nativeArms, armWriters⟩ := recurseArms typeId _ armsRep
      let matching : SurfaceMatchProof.Match reference region := {
        tree, metadata, index, result, typeId, scrutinee := scrutinee.output, atomic := scrutinee.atomic,
        arms := arms.map Arm.toStep, inside,
        event := by simpa only [List.length_map] using event,
        fits := by simpa only [List.length_map] using fits,
        scrutineeInside := scrutineeRep.inside, armsRep := nativeArms }
      intro current context input representation nameContext room environment
      exact SurfaceMatchProof.actualExpressionStep matching context
        (actualClassifier tree scrutinee scrutineeRep) (recurseScrutinee _ scrutineeRep) armWriters
        input representation nameContext room environment)
    (fun pattern names body recurse typeId index represented => by
      obtain ⟨naming, inside, event, fits, bindings, bodyRep⟩ := represented
      simp only [Arm.toStep, MatchArmsProof.Arm.Represents]
      exact ⟨⟨naming, inside, event, fits, bindings⟩, recurse _ bodyRep⟩)
    (fun _ _ => True.intro)
    (fun child rest recurseChild recurseRest index represented =>
      ⟨recurseChild _ represented.1, recurseRest _ represented.2⟩)
    (fun _ _ _ => ⟨True.intro, True.intro⟩)
    (fun arm rest recurseArm recurseRest typeId index represented => by
      obtain ⟨nonnegative, armRep, restRep⟩ := represented
      obtain ⟨native, writer⟩ := recurseArm typeId _ armRep
      obtain ⟨natives, writers⟩ := recurseRest typeId _ restRep
      exact ⟨⟨nonnegative, native, natives⟩, ⟨writer, writers⟩⟩)
    term
  intro current context input representation nameContext room environment
  exact closed index represented context input representation nameContext room environment

#print axioms actualTreeWriter
#print axioms actualClassifier

end RecursiveExpressionProof
