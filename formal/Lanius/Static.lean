import Lanius.Core

namespace Lanius.Static

open Lanius

inductive Const where
  | literal (value : Nat)
  | parameter (id : ConstParameterId)
deriving DecidableEq, Repr

/-- Types before monomorphization retain generic parameters and nominal type
    arguments. `Core.Ty` deliberately contains neither. -/
inductive Ty where
  | unit
  | scalar (type : Core.ScalarTy)
  | parameter (id : TypeParameterId)
  | array (element : Ty) (length : Const)
  | slice (element : Ty)
  | reference (referent : Ty)
  | nominal (id : TypeId) (typeArguments : List Ty) (constArguments : List Const)

/-- A fully substituted type still retains nominal arguments until the
    monomorphizer assigns that instantiation a concrete core declaration. -/
inductive GroundTy where
  | unit
  | scalar (type : Core.ScalarTy)
  | array (element : GroundTy) (length : Nat)
  | slice (element : GroundTy)
  | reference (referent : GroundTy)
  | nominal (id : TypeId) (typeArguments : List GroundTy) (constArguments : List Nat)

mutual
  def GroundTy.toTy : GroundTy → Ty
    | .unit => .unit
    | .scalar type => .scalar type
    | .array element length => .array element.toTy (.literal length)
    | .slice element => .slice element.toTy
    | .reference referent => .reference referent.toTy
    | .nominal id typeArguments constArguments =>
        .nominal id (typeArguments.map GroundTy.toTy)
          (constArguments.map Const.literal)
end

structure Substitution where
  types : TypeParameterId → Option GroundTy := fun _ => none
  constants : ConstParameterId → Option Nat := fun _ => none

structure SymbolicSubstitution where
  types : TypeParameterId → Option Ty := fun _ => none
  constants : ConstParameterId → Option Const := fun _ => none

inductive GenericParameter where
  | typeParameter (parameter : TypeParameterId)
  | constParameter (parameter : ConstParameterId)

inductive SymbolicParametersBound (substitution : SymbolicSubstitution) :
    List GenericParameter → Prop where
  | nil : SymbolicParametersBound substitution []
  | typeParameter
      (found : substitution.types parameter = some type)
      (tail : SymbolicParametersBound substitution parameters) :
      SymbolicParametersBound substitution (.typeParameter parameter :: parameters)
  | constParameter
      (found : substitution.constants parameter = some value)
      (tail : SymbolicParametersBound substitution parameters) :
      SymbolicParametersBound substitution (.constParameter parameter :: parameters)

inductive ParametersBound (substitution : Substitution) :
    List GenericParameter → Prop where
  | nil : ParametersBound substitution []
  | typeParameter
      (found : substitution.types parameter = some type)
      (tail : ParametersBound substitution parameters) :
      ParametersBound substitution (.typeParameter parameter :: parameters)
  | constParameter
      (found : substitution.constants parameter = some value)
      (tail : ParametersBound substitution parameters) :
      ParametersBound substitution (.constParameter parameter :: parameters)

inductive NominalArgumentsBound (substitution : Substitution) :
    List GenericParameter → List GroundTy → List Nat → Prop where
  | nil : NominalArgumentsBound substitution [] [] []
  | typeParameter
      (found : substitution.types parameter = some argument)
      (tail : NominalArgumentsBound substitution parameters typeArguments constArguments) :
      NominalArgumentsBound substitution (.typeParameter parameter :: parameters)
        (argument :: typeArguments) constArguments
  | constParameter
      (found : substitution.constants parameter = some argument)
      (tail : NominalArgumentsBound substitution parameters typeArguments constArguments) :
      NominalArgumentsBound substitution (.constParameter parameter :: parameters)
        typeArguments (argument :: constArguments)

inductive SymbolicArgumentsBound (substitution : SymbolicSubstitution) :
    List GenericParameter → List Ty → List Const → Prop where
  | nil : SymbolicArgumentsBound substitution [] [] []
  | typeParameter
      (found : substitution.types parameter = some argument)
      (tail : SymbolicArgumentsBound substitution parameters typeArguments constArguments) :
      SymbolicArgumentsBound substitution (.typeParameter parameter :: parameters)
        (argument :: typeArguments) constArguments
  | constParameter
      (found : substitution.constants parameter = some argument)
      (tail : SymbolicArgumentsBound substitution parameters typeArguments constArguments) :
      SymbolicArgumentsBound substitution (.constParameter parameter :: parameters)
        typeArguments (argument :: constArguments)

theorem SymbolicArgumentsBound.parametersBound
    (bound : SymbolicArgumentsBound substitution parameters
      typeArguments constArguments) :
    SymbolicParametersBound substitution parameters := by
  induction bound with
  | nil => exact .nil
  | typeParameter found tail tailIH => exact .typeParameter found tailIH
  | constParameter found tail tailIH => exact .constParameter found tailIH

/-- Two bindings of the same ordered generic arguments agree at every declared
    type-parameter ID. They may differ outside the declaration's parameter
    domain, which is intentionally irrelevant to retained declaration types. -/
theorem SymbolicArgumentsBound.type_agrees
    (left : SymbolicArgumentsBound leftSubstitution parameters
      typeArguments constArguments)
    (right : SymbolicArgumentsBound rightSubstitution parameters
      typeArguments constArguments)
    (member : .typeParameter parameter ∈ parameters) :
    leftSubstitution.types parameter = rightSubstitution.types parameter := by
  induction left with
  | nil => simp at member
  | @typeParameter current argument tailParameters tailTypes tailConstants
      leftFound leftTail induction =>
      cases right with
      | typeParameter rightFound rightTail =>
          simp only [List.mem_cons] at member
          rcases member with same | inTail
          · cases same
            exact leftFound.trans rightFound.symm
          · exact induction rightTail inTail
  | @constParameter current argument tailParameters tailTypes tailConstants
      leftFound leftTail induction =>
      cases right with
      | constParameter rightFound rightTail =>
          simp only [List.mem_cons] at member
          rcases member with impossible | inTail
          · cases impossible
          · exact induction rightTail inTail

/-- The analogous functional dependency for declared const-parameter IDs. -/
theorem SymbolicArgumentsBound.const_agrees
    (left : SymbolicArgumentsBound leftSubstitution parameters
      typeArguments constArguments)
    (right : SymbolicArgumentsBound rightSubstitution parameters
      typeArguments constArguments)
    (member : .constParameter parameter ∈ parameters) :
    leftSubstitution.constants parameter =
      rightSubstitution.constants parameter := by
  induction left with
  | nil => simp at member
  | @typeParameter current argument tailParameters tailTypes tailConstants
      leftFound leftTail induction =>
      cases right with
      | typeParameter rightFound rightTail =>
          simp only [List.mem_cons] at member
          rcases member with impossible | inTail
          · cases impossible
          · exact induction rightTail inTail
  | @constParameter current argument tailParameters tailTypes tailConstants
      leftFound leftTail induction =>
      cases right with
      | constParameter rightFound rightTail =>
          simp only [List.mem_cons] at member
          rcases member with same | inTail
          · cases same
            exact leftFound.trans rightFound.symm
          · exact induction rightTail inTail

/-- Ordered generic arguments are an extensional projection of a substitution
    over the declared parameter domain. Agreement outside that domain is not
    required. -/
theorem SymbolicArgumentsBound.orderedArguments_unique_of_agreement
    (left : SymbolicArgumentsBound leftSubstitution parameters
      leftTypeArguments leftConstArguments)
    (right : SymbolicArgumentsBound rightSubstitution parameters
      rightTypeArguments rightConstArguments)
    (typeAgreement : ∀ parameter,
      .typeParameter parameter ∈ parameters →
        leftSubstitution.types parameter = rightSubstitution.types parameter)
    (constAgreement : ∀ parameter,
      .constParameter parameter ∈ parameters →
        leftSubstitution.constants parameter =
          rightSubstitution.constants parameter) :
    leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments := by
  induction left generalizing rightSubstitution rightTypeArguments
      rightConstArguments with
  | nil =>
      cases right
      exact ⟨rfl, rfl⟩
  | @typeParameter parameter leftArgument tailParameters leftTypeTail
      leftConstTail leftFound leftTail induction =>
      cases right with
      | typeParameter rightFound rightTail =>
          have headEquality : leftArgument = _ := Option.some.inj
            (leftFound.symm.trans
              ((typeAgreement parameter (by simp)).trans rightFound))
          cases headEquality
          have tailTypeAgreement : ∀ candidate,
              .typeParameter candidate ∈ tailParameters →
                leftSubstitution.types candidate =
                  rightSubstitution.types candidate := by
            intro candidate member
            exact typeAgreement candidate (by simp [member])
          have tailConstAgreement : ∀ candidate,
              .constParameter candidate ∈ tailParameters →
                leftSubstitution.constants candidate =
                  rightSubstitution.constants candidate := by
            intro candidate member
            exact constAgreement candidate (by simp [member])
          rcases induction rightTail tailTypeAgreement tailConstAgreement with
            ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | @constParameter parameter leftArgument tailParameters leftTypeTail
      leftConstTail leftFound leftTail induction =>
      cases right with
      | constParameter rightFound rightTail =>
          have headEquality : leftArgument = _ := Option.some.inj
            (leftFound.symm.trans
              ((constAgreement parameter (by simp)).trans rightFound))
          cases headEquality
          have tailTypeAgreement : ∀ candidate,
              .typeParameter candidate ∈ tailParameters →
                leftSubstitution.types candidate =
                  rightSubstitution.types candidate := by
            intro candidate member
            exact typeAgreement candidate (by simp [member])
          have tailConstAgreement : ∀ candidate,
              .constParameter candidate ∈ tailParameters →
                leftSubstitution.constants candidate =
                  rightSubstitution.constants candidate := by
            intro candidate member
            exact constAgreement candidate (by simp [member])
          rcases induction rightTail tailTypeAgreement tailConstAgreement with
            ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩

mutual
  def Ty.substitute (substitution : SymbolicSubstitution) : Ty → Option Ty
    | .unit => some .unit
    | .scalar type => some (.scalar type)
    | .parameter id => substitution.types id
    | .array element length => do
        let resolvedElement ← element.substitute substitution
        let resolvedLength ← length.substitute substitution
        pure (.array resolvedElement resolvedLength)
    | .slice element => element.substitute substitution |>.map Ty.slice
    | .reference referent => referent.substitute substitution |>.map Ty.reference
    | .nominal id typeArguments constArguments => do
        let resolvedTypes ← substituteTypes substitution typeArguments
        let resolvedConstants ← substituteConstants substitution constArguments
        pure (.nominal id resolvedTypes resolvedConstants)

  def Const.substitute (substitution : SymbolicSubstitution) : Const → Option Const
    | .literal value => some (.literal value)
    | .parameter id => substitution.constants id

  def substituteTypes
      (substitution : SymbolicSubstitution) : List Ty → Option (List Ty)
    | [] => some []
    | head :: tail => do
        let resolvedHead ← head.substitute substitution
        let resolvedTail ← substituteTypes substitution tail
        pure (resolvedHead :: resolvedTail)

  def substituteConstants
      (substitution : SymbolicSubstitution) : List Const → Option (List Const)
    | [] => some []
    | head :: tail => do
        let resolvedHead ← head.substitute substitution
        let resolvedTail ← substituteConstants substitution tail
        pure (resolvedHead :: resolvedTail)
end

mutual
  inductive TySymbolicallyMatches (substitution : SymbolicSubstitution) :
      Ty → Ty → Prop where
    | unit : TySymbolicallyMatches substitution .unit .unit
    | scalar : TySymbolicallyMatches substitution (.scalar type) (.scalar type)
    | parameter
        (found : substitution.types parameter = some actual) :
        TySymbolicallyMatches substitution (.parameter parameter) actual
    | array
        (element : TySymbolicallyMatches substitution patternElement actualElement)
        (length : ConstSymbolicallyMatches substitution patternLength actualLength) :
        TySymbolicallyMatches substitution (.array patternElement patternLength)
          (.array actualElement actualLength)
    | slice
        (element : TySymbolicallyMatches substitution patternElement actualElement) :
        TySymbolicallyMatches substitution (.slice patternElement) (.slice actualElement)
    | reference
        (referent : TySymbolicallyMatches substitution patternReferent actualReferent) :
        TySymbolicallyMatches substitution (.reference patternReferent)
          (.reference actualReferent)
    | nominal
        (types : TypesSymbolicallyMatch substitution patternTypes actualTypes)
        (constants : ConstsSymbolicallyMatch substitution
          patternConstants actualConstants) :
        TySymbolicallyMatches substitution
          (.nominal sourceType patternTypes patternConstants)
          (.nominal sourceType actualTypes actualConstants)

  inductive TypesSymbolicallyMatch (substitution : SymbolicSubstitution) :
      List Ty → List Ty → Prop where
    | nil : TypesSymbolicallyMatch substitution [] []
    | cons
        (head : TySymbolicallyMatches substitution pattern actual)
        (tail : TypesSymbolicallyMatch substitution patterns actuals) :
        TypesSymbolicallyMatch substitution (pattern :: patterns) (actual :: actuals)

  inductive ConstSymbolicallyMatches (substitution : SymbolicSubstitution) :
      Const → Const → Prop where
    | literal : ConstSymbolicallyMatches substitution (.literal value) (.literal value)
    | parameter
        (found : substitution.constants parameter = some actual) :
        ConstSymbolicallyMatches substitution (.parameter parameter) actual

  inductive ConstsSymbolicallyMatch (substitution : SymbolicSubstitution) :
      List Const → List Const → Prop where
    | nil : ConstsSymbolicallyMatch substitution [] []
    | cons
        (head : ConstSymbolicallyMatches substitution pattern actual)
        (tail : ConstsSymbolicallyMatch substitution patterns actuals) :
        ConstsSymbolicallyMatch substitution (pattern :: patterns) (actual :: actuals)
end

/- Symbolic matching is the relational graph of symbolic substitution. These
   lemmas let occurrence-indexed inference reuse the same substitution algebra
   as explicit generic arguments instead of assuming a second, unrelated
   instantiated signature. -/
mutual
  theorem TySymbolicallyMatches.substitutes
      (matched : TySymbolicallyMatches substitution pattern actual) :
      pattern.substitute substitution = some actual := by
    cases matched with
    | unit => rfl
    | scalar => rfl
    | parameter found => exact found
    | array element length =>
        simp [Ty.substitute, element.substitutes, length.substitutes]
    | slice element => simp [Ty.substitute, element.substitutes]
    | reference referent => simp [Ty.substitute, referent.substitutes]
    | nominal types constants =>
        simp [Ty.substitute, types.substitutes, constants.substitutes]

  theorem TypesSymbolicallyMatch.substitutes
      (matched : TypesSymbolicallyMatch substitution patterns actuals) :
      substituteTypes substitution patterns = some actuals := by
    cases matched with
    | nil => rfl
    | cons head tail =>
        simp [substituteTypes, head.substitutes, tail.substitutes]

  theorem ConstSymbolicallyMatches.substitutes
      (matched : ConstSymbolicallyMatches substitution pattern actual) :
      pattern.substitute substitution = some actual := by
    cases matched with
    | literal => rfl
    | parameter found => exact found

  theorem ConstsSymbolicallyMatch.substitutes
      (matched : ConstsSymbolicallyMatch substitution patterns actuals) :
      substituteConstants substitution patterns = some actuals := by
    cases matched with
    | nil => rfl
    | cons head tail =>
        simp [substituteConstants, head.substitutes, tail.substitutes]
end

def Const.instantiate (substitution : Substitution) : Const → Option Nat
  | .literal value => some value
  | .parameter id => substitution.constants id

mutual
  def Ty.instantiate (substitution : Substitution) : Ty → Option GroundTy
    | .unit => some .unit
    | .scalar type => some (.scalar type)
    | .parameter id => substitution.types id
    | .array element length => do
        let resolvedElement ← element.instantiate substitution
        let resolvedLength ← length.instantiate substitution
        pure (.array resolvedElement resolvedLength)
    | .slice element => element.instantiate substitution |>.map GroundTy.slice
    | .reference referent => referent.instantiate substitution |>.map GroundTy.reference
    | .nominal id typeArguments constArguments => do
        let resolvedTypes ← instantiateTypes substitution typeArguments
        let resolvedConstants ← instantiateConstants substitution constArguments
        pure (.nominal id resolvedTypes resolvedConstants)

  def instantiateTypes (substitution : Substitution) : List Ty → Option (List GroundTy)
    | [] => some []
    | head :: tail => do
        let resolvedHead ← head.instantiate substitution
        let resolvedTail ← instantiateTypes substitution tail
        pure (resolvedHead :: resolvedTail)

  def instantiateConstants (substitution : Substitution) : List Const → Option (List Nat)
    | [] => some []
    | head :: tail => do
        let resolvedHead ← head.instantiate substitution
        let resolvedTail ← instantiateConstants substitution tail
        pure (resolvedHead :: resolvedTail)
end

theorem instantiateTypes_replicate
    (substitution : Substitution) (type : Ty) (ground : GroundTy) (count : Nat)
    (typeGrounds : type.instantiate substitution = some ground) :
    instantiateTypes substitution (List.replicate count type) =
      some (List.replicate count ground) := by
  induction count with
  | zero => rfl
  | succ count ih =>
      rw [List.replicate_succ, instantiateTypes, typeGrounds, ih]
      simp [List.replicate_succ]

theorem instantiateConstants_literals
    (values : List Nat) (substitution : Substitution) :
    instantiateConstants substitution (values.map Const.literal) = some values := by
  induction values with
  | nil => rfl
  | cons head tail induction =>
      simp [instantiateConstants, Const.instantiate, induction]

mutual
  /-- Embedding a ground type back into symbolic syntax introduces no generic
      variables, so every substitution recovers the original ground type. -/
  theorem GroundTy.toTy_instantiate
      (type : GroundTy) (substitution : Substitution) :
      type.toTy.instantiate substitution = some type := by
    cases type with
    | unit => simp [GroundTy.toTy, Ty.instantiate]
    | scalar => simp [GroundTy.toTy, Ty.instantiate]
    | array element length =>
        simp [GroundTy.toTy, Ty.instantiate, Const.instantiate,
          GroundTy.toTy_instantiate element substitution]
    | slice element =>
        simp [GroundTy.toTy, Ty.instantiate,
          GroundTy.toTy_instantiate element substitution]
    | reference referent =>
        simp [GroundTy.toTy, Ty.instantiate,
          GroundTy.toTy_instantiate referent substitution]
    | nominal id typeArguments constArguments =>
        simp [GroundTy.toTy, Ty.instantiate,
          GroundTy.listToTy_instantiate typeArguments substitution,
          instantiateConstants_literals constArguments substitution]

  theorem GroundTy.listToTy_instantiate
      (types : List GroundTy) (substitution : Substitution) :
      instantiateTypes substitution (types.map GroundTy.toTy) = some types := by
    cases types with
    | nil => rfl
    | cons head tail =>
        simp [instantiateTypes, GroundTy.toTy_instantiate head substitution,
          GroundTy.listToTy_instantiate tail substitution]
end

/-- Compose a symbolic substitution with the ground substitution of its
    surrounding generic declaration. Each retained symbolic argument is
    instantiated through the outer substitution; an unbound or nonground
    argument remains unbound in the composed ground substitution. -/
def SymbolicSubstitution.composeGround
    (symbolic : SymbolicSubstitution) (outer : Substitution) : Substitution := {
  types := fun parameter =>
    (symbolic.types parameter).bind (Ty.instantiate outer)
  constants := fun parameter =>
    (symbolic.constants parameter).bind (Const.instantiate outer)
}

/- Successful symbolic substitution followed by successful grounding is a
   successful single instantiation under the composed substitution. The four
   mutually recursive forms are the reusable algebra needed by generic calls,
   constructors, fields, and trait requirements. -/
mutual
  theorem Ty.substitute_then_instantiate
      {type retained : Ty} {symbolic : SymbolicSubstitution}
      {outer : Substitution} {ground : GroundTy}
      (substituted : type.substitute symbolic = some retained)
      (grounded : retained.instantiate outer = some ground) :
      type.instantiate (symbolic.composeGround outer) = some ground := by
    cases type with
    | unit =>
        simp [Ty.substitute] at substituted
        subst retained
        simp [Ty.instantiate] at grounded ⊢
        exact grounded
    | scalar scalarType =>
        simp [Ty.substitute] at substituted
        subst retained
        simp [Ty.instantiate] at grounded ⊢
        exact grounded
    | parameter parameter =>
        change symbolic.types parameter = some retained at substituted
        change (symbolic.types parameter).bind (Ty.instantiate outer) = some ground
        rw [substituted]
        exact grounded
    | array element length =>
        cases elementFound : element.substitute symbolic with
        | none => simp [Ty.substitute, elementFound] at substituted
        | some retainedElement =>
            cases lengthFound : length.substitute symbolic with
            | none => simp [Ty.substitute, elementFound, lengthFound] at substituted
            | some retainedLength =>
                simp [Ty.substitute, elementFound, lengthFound] at substituted
                subst retained
                cases elementGrounded : retainedElement.instantiate outer with
                | none => simp [Ty.instantiate, elementGrounded] at grounded
                | some groundElement =>
                    cases lengthGrounded : retainedLength.instantiate outer with
                    | none =>
                        simp [Ty.instantiate, elementGrounded, lengthGrounded] at grounded
                    | some groundLength =>
                        simp [Ty.instantiate, elementGrounded, lengthGrounded] at grounded
                        subst ground
                        simp [Ty.instantiate,
                          Ty.substitute_then_instantiate elementFound elementGrounded,
                          Const.substitute_then_instantiate lengthFound lengthGrounded]
    | slice element =>
        cases elementFound : element.substitute symbolic with
        | none => simp [Ty.substitute, elementFound] at substituted
        | some retainedElement =>
            simp [Ty.substitute, elementFound] at substituted
            subst retained
            cases elementGrounded : retainedElement.instantiate outer with
            | none => simp [Ty.instantiate, elementGrounded] at grounded
            | some groundElement =>
                simp [Ty.instantiate, elementGrounded] at grounded
                subst ground
                simp [Ty.instantiate,
                  Ty.substitute_then_instantiate elementFound elementGrounded]
    | reference referent =>
        cases referentFound : referent.substitute symbolic with
        | none => simp [Ty.substitute, referentFound] at substituted
        | some retainedReferent =>
            simp [Ty.substitute, referentFound] at substituted
            subst retained
            cases referentGrounded : retainedReferent.instantiate outer with
            | none => simp [Ty.instantiate, referentGrounded] at grounded
            | some groundReferent =>
                simp [Ty.instantiate, referentGrounded] at grounded
                subst ground
                simp [Ty.instantiate,
                  Ty.substitute_then_instantiate referentFound referentGrounded]
    | nominal id typeArguments constArguments =>
        cases typesFound : substituteTypes symbolic typeArguments with
        | none => simp [Ty.substitute, typesFound] at substituted
        | some retainedTypes =>
            cases constantsFound : substituteConstants symbolic constArguments with
            | none => simp [Ty.substitute, typesFound, constantsFound] at substituted
            | some retainedConstants =>
                simp [Ty.substitute, typesFound, constantsFound] at substituted
                subst retained
                cases typesGrounded : instantiateTypes outer retainedTypes with
                | none => simp [Ty.instantiate, typesGrounded] at grounded
                | some groundTypes =>
                    cases constantsGrounded : instantiateConstants outer retainedConstants with
                    | none =>
                        simp [Ty.instantiate, typesGrounded, constantsGrounded] at grounded
                    | some groundConstants =>
                        simp [Ty.instantiate, typesGrounded, constantsGrounded] at grounded
                        subst ground
                        simp [Ty.instantiate,
                          substituteTypes_then_instantiate typesFound typesGrounded,
                          substituteConstants_then_instantiate constantsFound
                            constantsGrounded]

  theorem Const.substitute_then_instantiate
      {constant retained : Const} {symbolic : SymbolicSubstitution}
      {outer : Substitution} {ground : Nat}
      (substituted : constant.substitute symbolic = some retained)
      (grounded : retained.instantiate outer = some ground) :
      constant.instantiate (symbolic.composeGround outer) = some ground := by
    cases constant with
    | literal value =>
        simp [Const.substitute] at substituted
        subst retained
        simpa [Const.instantiate] using grounded
    | parameter parameter =>
        change symbolic.constants parameter = some retained at substituted
        change (symbolic.constants parameter).bind (Const.instantiate outer) =
          some ground
        rw [substituted]
        exact grounded

  theorem substituteTypes_then_instantiate
      {types retained : List Ty} {symbolic : SymbolicSubstitution}
      {outer : Substitution} {grounds : List GroundTy}
      (substituted : substituteTypes symbolic types = some retained)
      (grounded : instantiateTypes outer retained = some grounds) :
      instantiateTypes (symbolic.composeGround outer) types = some grounds := by
    cases types with
    | nil =>
        simp [substituteTypes] at substituted
        subst retained
        simpa [instantiateTypes] using grounded
    | cons head tail =>
        cases headFound : head.substitute symbolic with
        | none => simp [substituteTypes, headFound] at substituted
        | some retainedHead =>
            cases tailFound : substituteTypes symbolic tail with
            | none => simp [substituteTypes, headFound, tailFound] at substituted
            | some retainedTail =>
                simp [substituteTypes, headFound, tailFound] at substituted
                subst retained
                cases headGrounded : retainedHead.instantiate outer with
                | none => simp [instantiateTypes, headGrounded] at grounded
                | some groundHead =>
                    cases tailGrounded : instantiateTypes outer retainedTail with
                    | none => simp [instantiateTypes, headGrounded, tailGrounded] at grounded
                    | some groundTail =>
                        simp [instantiateTypes, headGrounded, tailGrounded] at grounded
                        subst grounds
                        simp [instantiateTypes,
                          Ty.substitute_then_instantiate headFound headGrounded,
                          substituteTypes_then_instantiate tailFound tailGrounded]

  theorem substituteConstants_then_instantiate
      {constants retained : List Const} {symbolic : SymbolicSubstitution}
      {outer : Substitution} {grounds : List Nat}
      (substituted : substituteConstants symbolic constants = some retained)
      (grounded : instantiateConstants outer retained = some grounds) :
      instantiateConstants (symbolic.composeGround outer) constants = some grounds := by
    cases constants with
    | nil =>
        simp [substituteConstants] at substituted
        subst retained
        simpa [instantiateConstants] using grounded
    | cons head tail =>
        cases headFound : head.substitute symbolic with
        | none => simp [substituteConstants, headFound] at substituted
        | some retainedHead =>
            cases tailFound : substituteConstants symbolic tail with
            | none =>
                simp [substituteConstants, headFound, tailFound] at substituted
            | some retainedTail =>
                simp [substituteConstants, headFound, tailFound] at substituted
                subst retained
                cases headGrounded : retainedHead.instantiate outer with
                | none => simp [instantiateConstants, headGrounded] at grounded
                | some groundHead =>
                    cases tailGrounded : instantiateConstants outer retainedTail with
                    | none =>
                        simp [instantiateConstants, headGrounded, tailGrounded] at grounded
                    | some groundTail =>
                        simp [instantiateConstants, headGrounded, tailGrounded] at grounded
                        subst grounds
                        simp [instantiateConstants,
                          Const.substitute_then_instantiate headFound headGrounded,
                          substituteConstants_then_instantiate tailFound tailGrounded]
end

/-- Binding nominal arguments symbolically and then grounding the retained
    argument lists is equivalent to binding the resulting ground arguments
    with the composed substitution. This is the generic-constructor analogue
    of `substituteTypes_then_instantiate`. -/
theorem SymbolicArgumentsBound.composeGround
    (bound : SymbolicArgumentsBound symbolic parameters
      symbolicTypes symbolicConstants)
    (typesGrounded : instantiateTypes outer symbolicTypes = some groundTypes)
    (constantsGrounded : instantiateConstants outer symbolicConstants =
      some groundConstants) :
    NominalArgumentsBound (symbolic.composeGround outer) parameters
      groundTypes groundConstants := by
  induction bound generalizing groundTypes groundConstants with
  | nil =>
      simp [instantiateTypes] at typesGrounded
      simp [instantiateConstants] at constantsGrounded
      subst groundTypes
      subst groundConstants
      exact .nil
  | @typeParameter parameter argument parameters typeArguments constArguments
      found tail tailIH =>
      cases argumentGrounded : argument.instantiate outer with
      | none =>
          simp [instantiateTypes, argumentGrounded] at typesGrounded
      | some groundArgument =>
          cases tailGrounded : instantiateTypes outer typeArguments with
          | none =>
              simp [instantiateTypes, argumentGrounded, tailGrounded]
                at typesGrounded
          | some groundTail =>
              simp [instantiateTypes, argumentGrounded, tailGrounded]
                at typesGrounded
              subst groundTypes
              apply NominalArgumentsBound.typeParameter
              · simpa [SymbolicSubstitution.composeGround, found] using
                  argumentGrounded
              · exact tailIH tailGrounded constantsGrounded
  | @constParameter parameter argument parameters typeArguments constArguments
      found tail tailIH =>
      cases argumentGrounded : argument.instantiate outer with
      | none =>
          simp [instantiateConstants, argumentGrounded] at constantsGrounded
      | some groundArgument =>
          cases tailGrounded : instantiateConstants outer constArguments with
          | none =>
              simp [instantiateConstants, argumentGrounded, tailGrounded]
                at constantsGrounded
          | some groundTail =>
              simp [instantiateConstants, argumentGrounded, tailGrounded]
                at constantsGrounded
              subst groundConstants
              apply NominalArgumentsBound.constParameter
              · simpa [SymbolicSubstitution.composeGround, found] using
                  argumentGrounded
              · exact tailIH typesGrounded tailGrounded

/-- Evidence that every symbolic argument assigned to the listed generic
    parameters becomes ground under the surrounding substitution. -/
inductive SymbolicParametersGround
    (outer : Substitution) (symbolic : SymbolicSubstitution) :
    List GenericParameter → Prop where
  | nil : SymbolicParametersGround outer symbolic []
  | typeParameter
      (symbolicFound : symbolic.types parameter = some symbolicType)
      (grounded : symbolicType.instantiate outer = some groundType)
      (tail : SymbolicParametersGround outer symbolic parameters) :
      SymbolicParametersGround outer symbolic
        (.typeParameter parameter :: parameters)
  | constParameter
      (symbolicFound : symbolic.constants parameter = some symbolicValue)
      (grounded : symbolicValue.instantiate outer = some groundValue)
      (tail : SymbolicParametersGround outer symbolic parameters) :
      SymbolicParametersGround outer symbolic
        (.constParameter parameter :: parameters)

theorem SymbolicParametersGround.parametersBound
    (grounded : SymbolicParametersGround outer symbolic parameters) :
    ParametersBound (symbolic.composeGround outer) parameters := by
  cases grounded with
  | nil => exact .nil
  | typeParameter symbolicFound groundFound tail =>
      apply ParametersBound.typeParameter
      · simpa [SymbolicSubstitution.composeGround, symbolicFound] using
          groundFound
      · exact tail.parametersBound
  | constParameter symbolicFound groundFound tail =>
      apply ParametersBound.constParameter
      · simpa [SymbolicSubstitution.composeGround, symbolicFound] using
          groundFound
      · exact tail.parametersBound

theorem SymbolicParametersGround.symbolicParametersBound
    (grounded : SymbolicParametersGround outer symbolic parameters) :
    SymbolicParametersBound symbolic parameters := by
  cases grounded with
  | nil => exact .nil
  | typeParameter symbolicFound groundFound tail =>
      exact .typeParameter symbolicFound tail.symbolicParametersBound
  | constParameter symbolicFound groundFound tail =>
      exact .constParameter symbolicFound tail.symbolicParametersBound

theorem SymbolicArgumentsBound.parametersGround
    (bound : SymbolicArgumentsBound symbolic parameters
      symbolicTypes symbolicConstants)
    (typesGrounded : instantiateTypes outer symbolicTypes = some groundTypes)
    (constantsGrounded : instantiateConstants outer symbolicConstants =
      some groundConstants) :
    SymbolicParametersGround outer symbolic parameters := by
  induction bound generalizing groundTypes groundConstants with
  | nil => exact .nil
  | @typeParameter parameter argument parameters typeArguments constArguments
      found tail tailIH =>
      cases argumentGrounded : argument.instantiate outer with
      | none => simp [instantiateTypes, argumentGrounded] at typesGrounded
      | some groundArgument =>
          cases tailGrounded : instantiateTypes outer typeArguments with
          | none =>
              simp [instantiateTypes, argumentGrounded, tailGrounded]
                at typesGrounded
          | some groundTail =>
              exact .typeParameter found argumentGrounded
                (tailIH tailGrounded constantsGrounded)
  | @constParameter parameter argument parameters typeArguments constArguments
      found tail tailIH =>
      cases argumentGrounded : argument.instantiate outer with
      | none => simp [instantiateConstants, argumentGrounded] at constantsGrounded
      | some groundArgument =>
          cases tailGrounded : instantiateConstants outer constArguments with
          | none =>
              simp [instantiateConstants, argumentGrounded, tailGrounded]
                at constantsGrounded
          | some groundTail =>
              exact .constParameter found argumentGrounded
                (tailIH typesGrounded tailGrounded)

mutual
  inductive TyMatches (substitution : Substitution) : Ty → GroundTy → Prop where
    | unit : TyMatches substitution .unit .unit
    | scalar : TyMatches substitution (.scalar type) (.scalar type)
    | parameter (parameterId : TypeParameterId) (type : GroundTy)
        (found : substitution.types parameterId = some type) :
        TyMatches substitution (.parameter parameterId) type
    | array
        (element : TyMatches substitution patternElement groundElement)
        (length : ConstMatches substitution patternLength groundLength) :
        TyMatches substitution (.array patternElement patternLength)
          (.array groundElement groundLength)
    | slice (element : TyMatches substitution patternElement groundElement) :
        TyMatches substitution (.slice patternElement) (.slice groundElement)
    | reference (referent : TyMatches substitution patternReferent groundReferent) :
        TyMatches substitution (.reference patternReferent) (.reference groundReferent)
    | nominal (typeId : TypeId)
        (typeArguments : TypesMatch substitution patternTypeArguments groundTypeArguments)
        (constArguments : ConstsMatch substitution patternConstArguments groundConstArguments) :
        TyMatches substitution (.nominal typeId patternTypeArguments patternConstArguments)
          (.nominal typeId groundTypeArguments groundConstArguments)

  inductive TypesMatch (substitution : Substitution) :
      List Ty → List GroundTy → Prop where
    | nil : TypesMatch substitution [] []
    | cons
        (head : TyMatches substitution pattern ground)
        (tail : TypesMatch substitution patterns grounds) :
        TypesMatch substitution (pattern :: patterns) (ground :: grounds)

  inductive ConstMatches (substitution : Substitution) : Const → Nat → Prop where
    | literal : ConstMatches substitution (.literal value) value
    | parameter (parameterId : ConstParameterId) (value : Nat)
        (found : substitution.constants parameterId = some value) :
        ConstMatches substitution (.parameter parameterId) value

  inductive ConstsMatch (substitution : Substitution) : List Const → List Nat → Prop where
    | nil : ConstsMatch substitution [] []
    | cons
        (head : ConstMatches substitution pattern ground)
        (tail : ConstsMatch substitution patterns grounds) :
        ConstsMatch substitution (pattern :: patterns) (ground :: grounds)
end

/- The relational matching judgments are evidence for the executable
   instantiation functions. -/
mutual
  theorem TyMatches.instantiates
      (matched : TyMatches substitution pattern ground) :
      pattern.instantiate substitution = some ground := by
    cases matched with
    | unit => rfl
    | scalar => rfl
    | parameter parameter type found => exact found
    | array element length =>
        simp [Ty.instantiate, TyMatches.instantiates element,
          ConstMatches.instantiates length]
    | slice element =>
        simp [Ty.instantiate, TyMatches.instantiates element]
    | reference referent =>
        simp [Ty.instantiate, TyMatches.instantiates referent]
    | nominal typeId types constants =>
        simp [Ty.instantiate, TypesMatch.instantiate types,
          ConstsMatch.instantiate constants]

  theorem ConstMatches.instantiates
      (matched : ConstMatches substitution pattern ground) :
      pattern.instantiate substitution = some ground := by
    cases matched with
    | literal => rfl
    | parameter parameter value found => exact found

  theorem TypesMatch.instantiate
      (matched : TypesMatch substitution patterns grounds) :
      instantiateTypes substitution patterns = some grounds := by
    cases matched with
    | nil => rfl
    | cons head tail =>
        simp [instantiateTypes, TyMatches.instantiates head,
          TypesMatch.instantiate tail]

  theorem ConstsMatch.instantiate
      (matched : ConstsMatch substitution patterns grounds) :
      instantiateConstants substitution patterns = some grounds := by
    cases matched with
    | nil => rfl
    | cons head tail =>
        simp [instantiateConstants, ConstMatches.instantiates head,
          ConstsMatch.instantiate tail]
end

/- Successful executable instantiation is also complete for the relational
   matching judgments. These converses let specialization proofs move from a
   retained occurrence witness back into the compositional matching algebra. -/
mutual
  theorem Ty.matchesOfInstantiate
      (grounded : pattern.instantiate substitution = some ground) :
      TyMatches substitution pattern ground := by
    cases pattern with
    | unit =>
        simp [Ty.instantiate] at grounded
        subst ground
        exact .unit
    | scalar type =>
        simp [Ty.instantiate] at grounded
        subst ground
        exact .scalar
    | parameter parameter => exact .parameter parameter ground grounded
    | array element length =>
        cases elementGrounded : element.instantiate substitution with
        | none => simp [Ty.instantiate, elementGrounded] at grounded
        | some groundElement =>
            cases lengthGrounded : length.instantiate substitution with
            | none =>
                simp [Ty.instantiate, elementGrounded, lengthGrounded] at grounded
            | some groundLength =>
                simp [Ty.instantiate, elementGrounded, lengthGrounded] at grounded
                subst ground
                exact .array (Ty.matchesOfInstantiate elementGrounded)
                  (Const.matchesOfInstantiate lengthGrounded)
    | slice element =>
        cases elementGrounded : element.instantiate substitution with
        | none => simp [Ty.instantiate, elementGrounded] at grounded
        | some groundElement =>
            simp [Ty.instantiate, elementGrounded] at grounded
            subst ground
            exact .slice (Ty.matchesOfInstantiate elementGrounded)
    | reference referent =>
        cases referentGrounded : referent.instantiate substitution with
        | none => simp [Ty.instantiate, referentGrounded] at grounded
        | some groundReferent =>
            simp [Ty.instantiate, referentGrounded] at grounded
            subst ground
            exact .reference (Ty.matchesOfInstantiate referentGrounded)
    | nominal typeId typeArguments constArguments =>
        cases typesGrounded : instantiateTypes substitution typeArguments with
        | none => simp [Ty.instantiate, typesGrounded] at grounded
        | some groundTypes =>
            cases constantsGrounded : instantiateConstants substitution constArguments with
            | none =>
                simp [Ty.instantiate, typesGrounded, constantsGrounded] at grounded
            | some groundConstants =>
                simp [Ty.instantiate, typesGrounded, constantsGrounded] at grounded
                subst ground
                exact .nominal typeId
                  (TypesMatch.ofInstantiate typesGrounded)
                  (ConstsMatch.ofInstantiate constantsGrounded)

  theorem Const.matchesOfInstantiate
      (grounded : pattern.instantiate substitution = some ground) :
      ConstMatches substitution pattern ground := by
    cases pattern with
    | literal value =>
        simp [Const.instantiate] at grounded
        subst ground
        exact .literal
    | parameter parameter => exact .parameter parameter ground grounded

  theorem TypesMatch.ofInstantiate
      (grounded : instantiateTypes substitution patterns = some grounds) :
      TypesMatch substitution patterns grounds := by
    cases patterns with
    | nil =>
        simp [instantiateTypes] at grounded
        subst grounds
        exact .nil
    | cons head tail =>
        cases headGrounded : head.instantiate substitution with
        | none => simp [instantiateTypes, headGrounded] at grounded
        | some groundHead =>
            cases tailGrounded : instantiateTypes substitution tail with
            | none =>
                simp [instantiateTypes, headGrounded, tailGrounded] at grounded
            | some groundTail =>
                simp [instantiateTypes, headGrounded, tailGrounded] at grounded
                subst grounds
                exact .cons (Ty.matchesOfInstantiate headGrounded)
                  (TypesMatch.ofInstantiate tailGrounded)

  theorem ConstsMatch.ofInstantiate
      (grounded : instantiateConstants substitution patterns = some grounds) :
      ConstsMatch substitution patterns grounds := by
    cases patterns with
    | nil =>
        simp [instantiateConstants] at grounded
        subst grounds
        exact .nil
    | cons head tail =>
        cases headGrounded : head.instantiate substitution with
        | none => simp [instantiateConstants, headGrounded] at grounded
        | some groundHead =>
            cases tailGrounded : instantiateConstants substitution tail with
            | none =>
                simp [instantiateConstants, headGrounded, tailGrounded] at grounded
            | some groundTail =>
                simp [instantiateConstants, headGrounded, tailGrounded] at grounded
                subst grounds
                exact .cons (Const.matchesOfInstantiate headGrounded)
                  (ConstsMatch.ofInstantiate tailGrounded)
end

/- Symbolic matching composes with grounding. This is the central algebraic
   step used when a generic call or constructor inference is specialized: a
   symbolic argument match followed by grounding is a valid direct ground
   match under the composed substitution. -/
mutual
  theorem TySymbolicallyMatches.composeGround
      (symbolicMatch : TySymbolicallyMatches symbolic pattern actual)
      (groundMatch : TyMatches outer actual ground) :
      TyMatches (symbolic.composeGround outer) pattern ground := by
    cases symbolicMatch with
    | unit => cases groundMatch; exact .unit
    | scalar => cases groundMatch; exact .scalar
    | parameter found =>
        exact .parameter _ _ (by
          simp [SymbolicSubstitution.composeGround, found,
            groundMatch.instantiates])
    | array element length =>
        cases groundMatch with
        | array groundElement groundLength =>
            exact .array
              (element.composeGround groundElement)
              (length.composeGround groundLength)
    | slice element =>
        cases groundMatch with
        | slice groundElement => exact .slice (element.composeGround groundElement)
    | reference referent =>
        cases groundMatch with
        | reference groundReferent =>
            exact .reference (referent.composeGround groundReferent)
    | nominal types constants =>
        cases groundMatch with
        | nominal typeId groundTypes groundConstants =>
            exact .nominal _
              (types.composeGround groundTypes)
              (constants.composeGround groundConstants)

  theorem TypesSymbolicallyMatch.composeGround
      (symbolicMatch : TypesSymbolicallyMatch symbolic patterns actuals)
      (groundMatch : TypesMatch outer actuals grounds) :
      TypesMatch (symbolic.composeGround outer) patterns grounds := by
    cases symbolicMatch with
    | nil => cases groundMatch; exact .nil
    | cons head tail =>
        cases groundMatch with
        | cons groundHead groundTail =>
            exact .cons (head.composeGround groundHead)
              (tail.composeGround groundTail)

  theorem ConstSymbolicallyMatches.composeGround
      (symbolicMatch : ConstSymbolicallyMatches symbolic pattern actual)
      (groundMatch : ConstMatches outer actual ground) :
      ConstMatches (symbolic.composeGround outer) pattern ground := by
    cases symbolicMatch with
    | literal => cases groundMatch; exact .literal
    | parameter found =>
        exact .parameter _ _ (by
          simp [SymbolicSubstitution.composeGround, found,
            groundMatch.instantiates])

  theorem ConstsSymbolicallyMatch.composeGround
      (symbolicMatch : ConstsSymbolicallyMatch symbolic patterns actuals)
      (groundMatch : ConstsMatch outer actuals grounds) :
      ConstsMatch (symbolic.composeGround outer) patterns grounds := by
    cases symbolicMatch with
    | nil => cases groundMatch; exact .nil
    | cons head tail =>
        cases groundMatch with
        | cons groundHead groundTail =>
            exact .cons (head.composeGround groundHead)
              (tail.composeGround groundTail)
end

inductive BindsTypeArguments (substitution : Substitution) :
    TypeParameterId → List GroundTy → Prop where
  | nil : BindsTypeArguments substitution start []
  | cons
      (found : substitution.types start = some type)
      (tail : BindsTypeArguments substitution (start + 1) types) :
      BindsTypeArguments substitution start (type :: types)

/-- This explicit input connects ground generic types to dense core type IDs. -/
structure Monomorphization where
  resolveNominal : TypeId → List GroundTy → List Nat → Option Core.Ty

mutual
  def GroundTy.toCore (monomorphization : Monomorphization) : GroundTy → Option Core.Ty
    | .unit => some .unit
    | .scalar type => some (.scalar type)
    | .array element length => do
        let coreElement ← element.toCore monomorphization
        pure (.array coreElement length)
    | .slice element => element.toCore monomorphization |>.map Core.Ty.slice
    | .reference referent => referent.toCore monomorphization |>.map Core.Ty.reference
    | .nominal id typeArguments constArguments =>
        monomorphization.resolveNominal id typeArguments constArguments

  def GroundTy.listToCore
      (monomorphization : Monomorphization) : List GroundTy → Option (List Core.Ty)
    | [] => some []
    | head :: tail => do
        let coreHead ← head.toCore monomorphization
        let coreTail ← listToCore monomorphization tail
        pure (coreHead :: coreTail)
end

structure TraitPattern where
  trait : TraitId
  receiver : Ty
  arguments : List Ty := []

structure TraitGoal where
  trait : TraitId
  receiver : GroundTy
  arguments : List GroundTy := []

def TraitPattern.substitute
    (pattern : TraitPattern)
    (substitution : SymbolicSubstitution) : Option TraitPattern := do
  let receiver ← pattern.receiver.substitute substitution
  let arguments ← substituteTypes substitution pattern.arguments
  pure { trait := pattern.trait, receiver, arguments }

def TraitPatternSymbolicallyMatches
    (substitution : SymbolicSubstitution)
    (pattern actual : TraitPattern) : Prop :=
  pattern.trait = actual.trait ∧
    TySymbolicallyMatches substitution pattern.receiver actual.receiver ∧
    TypesSymbolicallyMatch substitution pattern.arguments actual.arguments

def TraitPatternMatches
    (substitution : Substitution) (pattern : TraitPattern)
    (goal : TraitGoal) : Prop :=
  pattern.trait = goal.trait ∧
    TyMatches substitution pattern.receiver goal.receiver ∧
    TypesMatch substitution pattern.arguments goal.arguments

theorem TraitPatternSymbolicallyMatches.composeGround
    (symbolicMatch : TraitPatternSymbolicallyMatches symbolic pattern actual)
    (groundMatch : TraitPatternMatches outer actual goal) :
    TraitPatternMatches (symbolic.composeGround outer) pattern goal := by
  rcases symbolicMatch with ⟨symbolicTrait, symbolicReceiver,
    symbolicArguments⟩
  rcases groundMatch with ⟨groundTrait, groundReceiver, groundArguments⟩
  exact ⟨symbolicTrait.trans groundTrait,
    symbolicReceiver.composeGround groundReceiver,
    symbolicArguments.composeGround groundArguments⟩

inductive ReceiverMode where
  /-- No receiver parameter. The declaration is callable only through an
      associated type path. -/
  | none
  /-- A source `self` or typed `self: T` receiver. -/
  | value
  /-- A source `&self` receiver. -/
  | reference
  /-- An ordinary first parameter whose type is the implementation receiver.
      It can be supplied explicitly by an associated call or implicitly by
      member-call syntax. -/
  | explicit
deriving DecidableEq, Repr

structure TraitScheme where
  declaration : Nat
  trait : TraitId
  isPublic : Bool := false
  genericParameters : List GenericParameter := []
  requirements : List TraitPattern := []
  methodDeclarations : List Nat := []

inductive TraitMethodParameter where
  | named (type : Ty)
  | receiver (mode : ReceiverMode) (annotation : Option Ty := none)

structure TraitMethodContract where
  trait : TraitId
  declaration : Nat
  name : String
  isPublic : Bool := false
  parameters : List TraitMethodParameter := []
  returnType : Ty := .unit

inductive TraitMethodParametersSpecialize
    (substitution : SymbolicSubstitution) (receiver : Ty) :
    List TraitMethodParameter → List Ty → Prop where
  | nil : TraitMethodParametersSpecialize substitution receiver [] []
  | named
      (type : source.substitute substitution = some specialized)
      (tail : TraitMethodParametersSpecialize substitution receiver
        sourceTail specializedTail) :
      TraitMethodParametersSpecialize substitution receiver
        (.named source :: sourceTail) (specialized :: specializedTail)
  | receiverValue
      (tail : TraitMethodParametersSpecialize substitution receiver
        sourceTail specializedTail) :
      TraitMethodParametersSpecialize substitution receiver
        (.receiver .value none :: sourceTail) (receiver :: specializedTail)
  | receiverValueAnnotated
      (annotation : source.substitute substitution = some receiver)
      (tail : TraitMethodParametersSpecialize substitution receiver
        sourceTail specializedTail) :
      TraitMethodParametersSpecialize substitution receiver
        (.receiver .value (some source) :: sourceTail) (receiver :: specializedTail)
  | receiverReference
      (tail : TraitMethodParametersSpecialize substitution receiver
        sourceTail specializedTail) :
      TraitMethodParametersSpecialize substitution receiver
        (.receiver .reference none :: sourceTail)
        (.reference receiver :: specializedTail)
  | receiverReferenceAnnotated
      (annotation : source.substitute substitution = some receiver)
      (tail : TraitMethodParametersSpecialize substitution receiver
        sourceTail specializedTail) :
      TraitMethodParametersSpecialize substitution receiver
        (.receiver .reference (some source) :: sourceTail)
        (.reference receiver :: specializedTail)

inductive TraitMethodContractSpecializes
    (trait : TraitScheme)
    (pattern : TraitPattern)
    (contract : TraitMethodContract) : List Ty → Ty → Prop where
  | intro
      (substitution : SymbolicSubstitution)
      (traitIdentity : contract.trait = trait.trait)
      (patternIdentity : pattern.trait = trait.trait)
      (arguments : SymbolicArgumentsBound substitution trait.genericParameters
        pattern.arguments [])
      (parameters : TraitMethodParametersSpecialize substitution pattern.receiver
        contract.parameters specializedParameters)
      (returnType : contract.returnType.substitute substitution =
        some specializedReturnType) :
      TraitMethodContractSpecializes trait pattern contract
        specializedParameters specializedReturnType

inductive NominalKind where
  | structure
  | enumeration
deriving DecidableEq, Repr

structure NominalScheme where
  declaration : Nat
  type : TypeId
  kind : NominalKind
  isPublic : Bool := false
  genericParameters : List GenericParameter := []
  requirements : List TraitPattern := []
  memberDeclarations : List Nat := []

structure NominalInstance where
  declaration : Nat
  sourceType : TypeId
  kind : NominalKind
  typeArguments : List GroundTy := []
  constArguments : List Nat := []
  coreType : TypeId

def NominalInstance.coreTy (resolved : NominalInstance) : Core.Ty :=
  match resolved.kind with
  | .structure => .structure resolved.coreType
  | .enumeration => .enumeration resolved.coreType

def NominalInstanceMapped
    (monomorphization : Monomorphization) (resolved : NominalInstance) : Prop :=
  monomorphization.resolveNominal resolved.sourceType resolved.typeArguments
    resolved.constArguments = some resolved.coreTy

def NominalInstancesUnique (instances : List NominalInstance) : Prop :=
  ∀ left, left ∈ instances → ∀ right, right ∈ instances →
    left.sourceType = right.sourceType →
    left.typeArguments = right.typeArguments →
    left.constArguments = right.constArguments →
    left = right

def TraitPattern.instantiate
    (pattern : TraitPattern) (substitution : Substitution) : Option TraitGoal := do
  let receiver ← pattern.receiver.instantiate substitution
  let arguments ← instantiateTypes substitution pattern.arguments
  pure { trait := pattern.trait, receiver, arguments }

theorem TraitPatternMatches.instantiates
    (matched : TraitPatternMatches substitution pattern goal) :
    pattern.instantiate substitution = some goal := by
  rcases matched with ⟨trait, receiver, arguments⟩
  unfold TraitPattern.instantiate
  rw [receiver.instantiates, arguments.instantiate]
  simp [trait]

theorem TraitPattern.substitute_then_instantiate
    {pattern retained : TraitPattern} {symbolic : SymbolicSubstitution}
    {outer : Substitution} {goal : TraitGoal}
    (substituted : pattern.substitute symbolic = some retained)
    (grounded : retained.instantiate outer = some goal) :
    pattern.instantiate (symbolic.composeGround outer) = some goal := by
  unfold TraitPattern.substitute at substituted
  rcases Option.bind_eq_some_iff.mp substituted with
    ⟨retainedReceiver, receiverFound, argumentsContinuation⟩
  rcases Option.bind_eq_some_iff.mp argumentsContinuation with
    ⟨retainedArguments, argumentsFound, retainedResult⟩
  have retainedEquality :
      { trait := pattern.trait, receiver := retainedReceiver,
        arguments := retainedArguments } = retained :=
    Option.some.inj retainedResult
  subst retained
  unfold TraitPattern.instantiate at grounded
  rcases Option.bind_eq_some_iff.mp grounded with
    ⟨groundReceiver, receiverGrounded, groundArgumentsContinuation⟩
  rcases Option.bind_eq_some_iff.mp groundArgumentsContinuation with
    ⟨groundArguments, argumentsGrounded, groundResult⟩
  have goalEquality :
      { trait := pattern.trait, receiver := groundReceiver,
        arguments := groundArguments } = goal :=
    Option.some.inj groundResult
  subst goal
  unfold TraitPattern.instantiate
  rw [Ty.substitute_then_instantiate receiverFound receiverGrounded,
    substituteTypes_then_instantiate argumentsFound argumentsGrounded]
  rfl

structure ImplScheme where
  id : ImplId
  declaration : Nat := 0
  isPublic : Bool := false
  typeParameterCount : Nat := 0
  constParameterCount : Nat := 0
  genericParameters : List GenericParameter := []
  receiver : Ty
  implementedTrait : Option TraitPattern := none
  requirements : List TraitPattern := []
  methodDeclarations : List Nat := []

mutual
  /-- A symbolic trait goal may be supplied directly by the declaration's
      assumptions or proved by a declared implementation. Implementation
      requirements are resolved recursively, so concrete obligations do not
      need to be copied into every caller's `where` clause. -/
  inductive SymbolicSatisfies
      (implementations : List ImplScheme)
      (assumptions : List TraitPattern) : TraitPattern → Prop where
    | assumption
        (available : goal ∈ assumptions) :
        SymbolicSatisfies implementations assumptions goal
    | byImplementation
        (member : implementation ∈ implementations)
        (bound : SymbolicParametersBound substitution
          implementation.genericParameters)
        (implements : implementation.implementedTrait = some pattern)
        (header : TraitPatternSymbolicallyMatches substitution pattern goal)
        (requirements : SymbolicRequirementsSatisfied implementations assumptions
          substitution implementation.requirements) :
        SymbolicSatisfies implementations assumptions goal

  inductive SymbolicRequirementsSatisfied
      (implementations : List ImplScheme)
      (assumptions : List TraitPattern) :
      SymbolicSubstitution → List TraitPattern → Prop where
    | nil : SymbolicRequirementsSatisfied implementations assumptions
        substitution []
    | cons
        (specialized : requirement.substitute substitution = some goal)
        (satisfied : SymbolicSatisfies implementations assumptions goal)
        (tail : SymbolicRequirementsSatisfied implementations assumptions
          substitution requirements) :
        SymbolicRequirementsSatisfied implementations assumptions substitution
          (requirement :: requirements)
end

mutual
  /-- A trait goal is satisfied by an implementation whose header and every
      `where` requirement instantiate under one substitution. -/
  inductive Satisfies (implementations : List ImplScheme) : TraitGoal → Prop where
    | byImplementation
        (implementation : ImplScheme)
        (member : implementation ∈ implementations)
        (substitution : Substitution)
        (bound : ParametersBound substitution implementation.genericParameters)
        (pattern : TraitPattern)
        (implements : implementation.implementedTrait = some pattern)
        (header : pattern.instantiate substitution = some goal)
        (requirements : RequirementsSatisfied implementations substitution
          implementation.requirements) :
        Satisfies implementations goal

  inductive RequirementsSatisfied (implementations : List ImplScheme) :
      Substitution → List TraitPattern → Prop where
    | nil : RequirementsSatisfied implementations substitution []
    | cons
        (instantiated : requirement.instantiate substitution = some goal)
        (satisfied : Satisfies implementations goal)
        (tail : RequirementsSatisfied implementations substitution requirements) :
        RequirementsSatisfied implementations substitution (requirement :: requirements)
end

mutual
  /-- One well-scoped symbolic trait proof together with its ground meaning.
      Internal implementation substitutions carry explicit grounding evidence;
      this rules out silently choosing an unbound phantom generic parameter. -/
  inductive SymbolicSatisfiesGrounds
      (implementations : List ImplScheme)
      (assumptions : List TraitPattern) (outer : Substitution) :
      TraitPattern → TraitGoal → Prop where
    | assumption
        (available : symbolicGoal ∈ assumptions)
        (goalGrounds : TraitPatternMatches outer symbolicGoal groundGoal)
        (satisfied : Satisfies implementations groundGoal) :
        SymbolicSatisfiesGrounds implementations assumptions outer
          symbolicGoal groundGoal
    | byImplementation
        (member : implementation ∈ implementations)
        (parametersGround : SymbolicParametersGround outer substitution
          implementation.genericParameters)
        (implements : implementation.implementedTrait = some pattern)
        (header : TraitPatternSymbolicallyMatches substitution pattern symbolicGoal)
        (goalGrounds : TraitPatternMatches outer symbolicGoal groundGoal)
        (requirements : SymbolicRequirementsGround
          implementations assumptions outer substitution implementation.requirements) :
        SymbolicSatisfiesGrounds implementations assumptions outer
          symbolicGoal groundGoal

  /-- Every recursively discharged symbolic implementation requirement also
      has a ground goal and a ground satisfaction derivation. -/
  inductive SymbolicRequirementsGround
      (implementations : List ImplScheme)
      (assumptions : List TraitPattern) (outer : Substitution) :
      SymbolicSubstitution → List TraitPattern → Prop where
    | nil : SymbolicRequirementsGround implementations assumptions outer
        substitution []
    | cons
        (specialized : requirement.substitute substitution = some symbolicGoal)
        (goalGrounds : TraitPatternMatches outer symbolicGoal groundGoal)
        (satisfied : SymbolicSatisfiesGrounds implementations assumptions outer
          symbolicGoal groundGoal)
        (tail : SymbolicRequirementsGround implementations assumptions outer
          substitution requirements) :
        SymbolicRequirementsGround implementations assumptions outer substitution
          (requirement :: requirements)
end

theorem SymbolicSatisfiesGrounds.symbolic
    (grounded : SymbolicSatisfiesGrounds implementations assumptions outer
      symbolicGoal groundGoal) :
    SymbolicSatisfies implementations assumptions symbolicGoal := by
  refine SymbolicSatisfiesGrounds.rec
    (motive_1 := fun symbolicGoal _ _ =>
      SymbolicSatisfies implementations assumptions symbolicGoal)
    (motive_2 := fun substitution requirements _ =>
      SymbolicRequirementsSatisfied implementations assumptions substitution
        requirements)
    ?_ ?_ ?_ ?_ grounded
  · intro symbolicGoal groundGoal available goalGrounds satisfied
    exact .assumption available
  · intro implementation substitution pattern symbolicGoal groundGoal member
      parametersGround implements header goalGrounds requirements requirementsIH
    exact .byImplementation member parametersGround.symbolicParametersBound
      implements header requirementsIH
  · intro substitution
    exact .nil
  · intro symbolicGoal groundGoal substitution requirements requirement specialized
      goalGrounds satisfied tail satisfiedIH tailIH
    exact .cons specialized satisfiedIH tailIH

theorem SymbolicRequirementsGround.symbolic
    (grounded : SymbolicRequirementsGround implementations assumptions outer
      substitution requirements) :
    SymbolicRequirementsSatisfied implementations assumptions substitution
      requirements := by
  refine SymbolicRequirementsGround.rec
    (motive_1 := fun symbolicGoal _ _ =>
      SymbolicSatisfies implementations assumptions symbolicGoal)
    (motive_2 := fun substitution requirements _ =>
      SymbolicRequirementsSatisfied implementations assumptions substitution
        requirements)
    ?_ ?_ ?_ ?_ grounded
  · intro symbolicGoal groundGoal available goalGrounds satisfied
    exact .assumption available
  · intro implementation substitution pattern symbolicGoal groundGoal member
      parametersGround implements header goalGrounds requirements requirementsIH
    exact .byImplementation member parametersGround.symbolicParametersBound
      implements header requirementsIH
  · intro substitution
    exact .nil
  · intro symbolicGoal groundGoal substitution requirements requirement specialized
      goalGrounds satisfied tail satisfiedIH tailIH
    exact .cons specialized satisfiedIH tailIH

theorem SymbolicSatisfiesGrounds.ground
    (grounded : SymbolicSatisfiesGrounds implementations assumptions outer
      symbolicGoal groundGoal) :
    Satisfies implementations groundGoal := by
  refine SymbolicSatisfiesGrounds.rec
    (motive_1 := fun _ groundGoal _ => Satisfies implementations groundGoal)
    (motive_2 := fun substitution requirements _ =>
      RequirementsSatisfied implementations (substitution.composeGround outer)
        requirements)
    ?_ ?_ ?_ ?_ grounded
  · intro symbolicGoal groundGoal available goalGrounds satisfied
    exact satisfied
  · intro implementation substitution pattern symbolicGoal groundGoal member
      parametersGround implements header goalGrounds requirements requirementsIH
    exact .byImplementation _ member _ parametersGround.parametersBound _ implements
      (header.composeGround goalGrounds).instantiates requirementsIH
  · intro substitution
    exact .nil
  · intro symbolicGoal groundGoal substitution requirements requirement specialized
      goalGrounds satisfied tail satisfiedIH tailIH
    exact .cons
      (TraitPattern.substitute_then_instantiate specialized
        goalGrounds.instantiates)
      satisfiedIH tailIH

theorem SymbolicRequirementsGround.ground
    (grounded : SymbolicRequirementsGround implementations assumptions outer
      substitution requirements) :
    RequirementsSatisfied implementations (substitution.composeGround outer)
      requirements := by
  refine SymbolicRequirementsGround.rec
    (motive_1 := fun _ groundGoal _ => Satisfies implementations groundGoal)
    (motive_2 := fun substitution requirements _ =>
      RequirementsSatisfied implementations (substitution.composeGround outer)
        requirements)
    ?_ ?_ ?_ ?_ grounded
  · intro symbolicGoal groundGoal available goalGrounds satisfied
    exact satisfied
  · intro implementation substitution pattern symbolicGoal groundGoal member
      parametersGround implements header goalGrounds requirements requirementsIH
    exact .byImplementation _ member _ parametersGround.parametersBound _ implements
      (header.composeGround goalGrounds).instantiates requirementsIH
  · intro substitution
    exact .nil
  · intro symbolicGoal groundGoal substitution requirements requirement specialized
      goalGrounds satisfied tail satisfiedIH tailIH
    exact .cons
      (TraitPattern.substitute_then_instantiate specialized
        goalGrounds.instantiates)
      satisfiedIH tailIH

inductive ImplApplies
    (implementations : List ImplScheme) (implementation : ImplScheme) :
    TraitGoal → Prop where
  | intro
      (member : implementation ∈ implementations)
      (substitution : Substitution)
      (bound : ParametersBound substitution implementation.genericParameters)
      (pattern : TraitPattern)
      (implements : implementation.implementedTrait = some pattern)
      (header : pattern.instantiate substitution = some goal)
      (requirements : RequirementsSatisfied implementations substitution
        implementation.requirements) :
      ImplApplies implementations implementation goal

def TraitImplVisibilityMatches
    (trait : TraitScheme) (implementation : ImplScheme) : Prop :=
  implementation.implementedTrait.isSome ∧ implementation.isPublic = trait.isPublic

/-- Overlapping applicable implementations are ambiguous rather than acquiring
    an arbitrary source-order meaning. -/
def SelectsImpl
    (implementations : List ImplScheme) (goal : TraitGoal)
    (selected : ImplScheme) : Prop :=
  ImplApplies implementations selected goal ∧
    ∀ candidate : ImplScheme,
      ImplApplies implementations candidate goal → candidate.id = selected.id

/-- A coherent implementation table never has two distinct implementation
    identities applicable to the same ground trait goal. The quantification
    over `ImplApplies` includes each implementation's generic substitution and
    recursively discharged requirements, so this rejects overlap between
    concrete and generic headers as well as overlap between two generic
    headers. -/
def ImplementationsCoherent (implementations : List ImplScheme) : Prop :=
  ∀ (goal : TraitGoal) (left right : ImplScheme),
    ImplApplies implementations left goal →
    ImplApplies implementations right goal →
    left.id = right.id

/-- Under global coherence, any applicable implementation is selected; source
    order cannot influence trait resolution. -/
theorem ImplementationsCoherent.selects
    (coherent : ImplementationsCoherent implementations)
    (applies : ImplApplies implementations selected goal) :
    SelectsImpl implementations goal selected := by
  exact ⟨applies, fun candidate candidateApplies =>
    coherent goal candidate selected candidateApplies applies⟩

structure FunctionScheme where
  declaration : Nat
  genericParameters : List GenericParameter := []
  parameterTypes : List Ty := []
  returnType : Ty := .unit
  requirements : List TraitPattern := []

structure FunctionInstance where
  declaration : Nat
  function : FunctionId
  typeArguments : List GroundTy := []
  constArguments : List Nat := []
  parameterTypes : List GroundTy := []
  returnType : GroundTy

/-- The source declaration plus retained generic arguments is the semantic
    identity of one monomorphic function specialization. Parameter and return
    types are consequences of instantiating that declaration, not additional
    identity components. -/
def FunctionInstance.specializationKey
    (row : FunctionInstance) : Nat × List GroundTy × List Nat :=
  (row.declaration, row.typeArguments, row.constArguments)

def FunctionScheme.instantiateTypes
    (scheme : FunctionScheme) (function : FunctionId)
    (typeArguments : List GroundTy) (constArguments : List Nat)
    (substitution : Substitution) : Option FunctionInstance := do
  let parameterTypes ← Static.instantiateTypes substitution scheme.parameterTypes
  let returnType ← scheme.returnType.instantiate substitution
  pure {
    declaration := scheme.declaration
    function
    typeArguments
    constArguments
    parameterTypes
    returnType
  }

inductive FunctionInstantiates
    (implementations : List ImplScheme)
    (scheme : FunctionScheme) (substitution : Substitution)
    (resolved : FunctionInstance) : Prop where
  | intro
      (bound : ParametersBound substitution scheme.genericParameters)
      (arguments : NominalArgumentsBound substitution scheme.genericParameters
        resolved.typeArguments resolved.constArguments)
      (requirements : RequirementsSatisfied implementations substitution scheme.requirements)
      (types : scheme.instantiateTypes resolved.function resolved.typeArguments
        resolved.constArguments substitution = some resolved) :
      FunctionInstantiates implementations scheme substitution resolved

/-- Instantiation fixes the concrete parameter types recorded by the emitted
    specialization. -/
theorem FunctionInstantiates.parameterTypes
    (instantiated : FunctionInstantiates implementations scheme substitution
      resolved) :
    Static.instantiateTypes substitution scheme.parameterTypes =
      some resolved.parameterTypes := by
  cases instantiated with
  | intro bound arguments requirements types =>
      unfold FunctionScheme.instantiateTypes at types
      rcases Option.bind_eq_some_iff.mp types with
        ⟨parameterTypes, parameterTypesFound, returnContinuation⟩
      rcases Option.bind_eq_some_iff.mp returnContinuation with
        ⟨returnType, returnTypeFound, result⟩
      have instanceEquality := Option.some.inj result
      have parameterTypesEquality : parameterTypes = resolved.parameterTypes :=
        congrArg FunctionInstance.parameterTypes instanceEquality
      exact parameterTypesFound.trans (congrArg some parameterTypesEquality)

/-- Instantiation likewise fixes the specialization's concrete return type. -/
theorem FunctionInstantiates.returnType
    (instantiated : FunctionInstantiates implementations scheme substitution
      resolved) :
    scheme.returnType.instantiate substitution = some resolved.returnType := by
  cases instantiated with
  | intro bound arguments requirements types =>
      unfold FunctionScheme.instantiateTypes at types
      rcases Option.bind_eq_some_iff.mp types with
        ⟨parameterTypes, parameterTypesFound, returnContinuation⟩
      rcases Option.bind_eq_some_iff.mp returnContinuation with
        ⟨returnType, returnTypeFound, result⟩
      have instanceEquality := Option.some.inj result
      have returnTypeEquality : returnType = resolved.returnType :=
        congrArg FunctionInstance.returnType instanceEquality
      exact returnTypeFound.trans (congrArg some returnTypeEquality)

def FunctionScheme.applies
    (implementations : List ImplScheme) (instances : List FunctionInstance)
    (scheme : FunctionScheme)
    (argumentTypes : List GroundTy) (resolved : FunctionInstance) : Prop :=
  resolved ∈ instances ∧
    ∃ substitution,
      FunctionInstantiates implementations scheme substitution resolved ∧
      resolved.parameterTypes = argumentTypes

def ResolvesFunction
    (implementations : List ImplScheme)
    (schemes : List FunctionScheme) (instances : List FunctionInstance)
    (argumentTypes : List GroundTy)
    (selected : FunctionScheme) (resolved : FunctionInstance) : Prop :=
  selected ∈ schemes ∧ selected.applies implementations instances argumentTypes resolved ∧
    ∀ (candidate : FunctionScheme) (candidateInstance : FunctionInstance),
      candidate ∈ schemes →
      candidate.applies implementations instances argumentTypes candidateInstance →
      candidateInstance.function = resolved.function

/-- A method scheme is a source declaration. Generic schemes do not contain a
    core function ID because each monomorphic instance receives its own ID. -/
structure MethodScheme where
  name : String
  declaration : Nat
  moduleId : ModuleId := 0
  isPublic : Bool := false
  receiverMode : ReceiverMode
  receiverType : Ty
  argumentTypes : List Ty := []
  returnType : Ty := .unit
  genericParameters : List GenericParameter := []
  requirements : List TraitPattern := []

/-- Source parameter types visible at a type-qualified inherent-function call.
    An explicit typed receiver is an ordinary first source argument in this
    syntax, even though it is kept outside `argumentTypes` for member lookup. -/
def MethodScheme.associatedArgumentTypes? (scheme : MethodScheme) :
    Option (List Ty) :=
  match scheme.receiverMode with
  | .none => some scheme.argumentTypes
  | .explicit => some (scheme.receiverType :: scheme.argumentTypes)
  | .value | .reference => none

structure MethodInstance where
  declaration : Nat
  name : String
  function : FunctionId
  receiverMode : ReceiverMode
  receiverType : GroundTy
  typeArguments : List GroundTy := []
  constArguments : List Nat := []
  argumentTypes : List GroundTy := []
  returnType : GroundTy

/-- The ordinary source arguments of a type-qualified inherent-function call.
    Receiverless functions expose their complete stored argument vector.
    Explicit typed receivers are stored separately from the tail used by
    member lookup, but remain an ordinary first argument in `Type::function`
    syntax. `self` and `&self` functions are member-only. -/
def MethodInstance.associatedArgumentTypes? (row : MethodInstance) :
    Option (List GroundTy) :=
  match row.receiverMode with
  | .none => some row.argumentTypes
  | .explicit => some (row.receiverType :: row.argumentTypes)
  | .value | .reference => none

/-- A method specialization is additionally indexed by its ground receiver.
    This distinguishes specializations of one generic implementation across
    receiver types while retaining explicit type and const arguments. -/
def MethodInstance.specializationKey
    (row : MethodInstance) :
    Nat × GroundTy × List GroundTy × List Nat :=
  (row.declaration, row.receiverType, row.typeArguments, row.constArguments)

/-- Trait implementation bodies are emitted as core functions but are not
    candidates for inherent member-call lookup in the current language. -/
structure TraitImplementationMethodInstance where
  implementation : ImplId
  declaration : Nat
  function : FunctionId
  parameterTypes : List GroundTy := []
  returnType : GroundTy

def MethodScheme.instantiateTypes
    (scheme : MethodScheme) (function : FunctionId)
    (typeArguments : List GroundTy) (constArguments : List Nat)
    (substitution : Substitution) : Option MethodInstance := do
  let receiverType ← scheme.receiverType.instantiate substitution
  let argumentTypes ← Static.instantiateTypes substitution scheme.argumentTypes
  let returnType ← scheme.returnType.instantiate substitution
  pure {
    declaration := scheme.declaration
    name := scheme.name
    function
    receiverMode := scheme.receiverMode
    receiverType
    typeArguments
    constArguments
    argumentTypes
    returnType
  }

inductive MethodInstantiates
    (implementations : List ImplScheme) (scheme : MethodScheme)
    (substitution : Substitution) (resolved : MethodInstance) : Prop where
  | inherent
      (bound : ParametersBound substitution scheme.genericParameters)
      (arguments : NominalArgumentsBound substitution scheme.genericParameters
        resolved.typeArguments resolved.constArguments)
      (requirements : RequirementsSatisfied implementations substitution scheme.requirements)
      (types : scheme.instantiateTypes resolved.function resolved.typeArguments
        resolved.constArguments substitution = some resolved) :
      MethodInstantiates implementations scheme substitution resolved

/-- Every observable signature field of a method artifact is fixed by the
    successful instantiation equation. Keeping these facts together avoids
    re-running or postulating ground method inference at call sites. -/
theorem MethodInstantiates.signature
    (instantiated : MethodInstantiates implementations scheme substitution
      resolved) :
    scheme.receiverType.instantiate substitution = some resolved.receiverType ∧
      instantiateTypes substitution scheme.argumentTypes =
        some resolved.argumentTypes ∧
      scheme.returnType.instantiate substitution = some resolved.returnType ∧
      resolved.declaration = scheme.declaration ∧
      resolved.name = scheme.name ∧
      resolved.receiverMode = scheme.receiverMode := by
  cases instantiated with
  | inherent bound arguments requirements types =>
      unfold MethodScheme.instantiateTypes at types
      rcases Option.bind_eq_some_iff.mp types with
        ⟨receiverType, receiverTypeFound, receiverContinuation⟩
      rcases Option.bind_eq_some_iff.mp receiverContinuation with
        ⟨argumentTypes, argumentTypesFound, argumentContinuation⟩
      rcases Option.bind_eq_some_iff.mp argumentContinuation with
        ⟨returnType, returnTypeFound, result⟩
      have instanceEquality := Option.some.inj result
      constructor
      · exact receiverTypeFound.trans (congrArg some
          (congrArg MethodInstance.receiverType instanceEquality))
      constructor
      · exact argumentTypesFound.trans (congrArg some
          (congrArg MethodInstance.argumentTypes instanceEquality))
      constructor
      · exact returnTypeFound.trans (congrArg some
          (congrArg MethodInstance.returnType instanceEquality))
      constructor
      · exact (congrArg MethodInstance.declaration instanceEquality).symm
      constructor
      · exact (congrArg MethodInstance.name instanceEquality).symm
      · exact (congrArg MethodInstance.receiverMode instanceEquality).symm

def MethodScheme.applies
    (implementations : List ImplScheme) (instances : List MethodInstance)
    (scheme : MethodScheme)
    (receiver : GroundTy) (name : String) (arguments : List GroundTy)
    (resolved : MethodInstance) : Prop :=
  resolved ∈ instances ∧
    ∃ (substitution : Substitution),
      MethodInstantiates implementations scheme substitution resolved ∧
      resolved.receiverType = receiver ∧ resolved.name = name ∧
      resolved.argumentTypes = arguments

/-- Member syntax requires a receiver-bearing declaration. The underlying
    receiver/name index remains shared with associated functions so duplicate
    declarations cannot become legal merely by changing call syntax. -/
def MethodScheme.appliesMember
    (implementations : List ImplScheme) (instances : List MethodInstance)
    (scheme : MethodScheme)
    (receiver : GroundTy) (name : String) (arguments : List GroundTy)
    (resolved : MethodInstance) : Prop :=
  scheme.applies implementations instances receiver name arguments resolved ∧
    resolved.receiverMode ≠ .none

/-- Type-qualified associated syntax accepts receiverless functions and
    explicit typed receivers. Its source argument vector differs from member
    syntax only in the explicit-receiver case. -/
def MethodScheme.appliesAssociated
    (implementations : List ImplScheme) (instances : List MethodInstance)
    (scheme : MethodScheme)
    (receiver : GroundTy) (name : String) (arguments : List GroundTy)
    (resolved : MethodInstance) : Prop :=
  resolved ∈ instances ∧
    ∃ (substitution : Substitution),
      MethodInstantiates implementations scheme substitution resolved ∧
      resolved.receiverType = receiver ∧ resolved.name = name ∧
      resolved.associatedArgumentTypes? = some arguments

/-- A method is directly accessible either from its declaring module or from
    every module when declared `pub`. Visibility alone does not select an
    declaration: same-module applicable methods form a higher-priority tier
    than public methods imported from other modules. -/
def MethodScheme.visibleFrom
    (scheme : MethodScheme) (callSiteModule : ModuleId) : Prop :=
  scheme.moduleId = callSiteModule ∨ scheme.isPublic = true

/-- `scheme` lies in the method-lookup tier used at one call site. When any
    applicable same-module method exists, only same-module methods compete.
    Otherwise all accessible public methods compete. `applicable` deliberately
    remains abstract so symbolic and ground lookup share this policy. -/
def MethodScheme.preferredAt
    (methods : List MethodScheme) (callSiteModule : ModuleId)
    (applicable : MethodScheme → Prop) (scheme : MethodScheme) : Prop :=
  scheme.visibleFrom callSiteModule ∧
    (scheme.moduleId = callSiteModule ∨
      ¬ ∃ candidate,
        candidate ∈ methods ∧ candidate.moduleId = callSiteModule ∧
          applicable candidate)

def GroundMethodLookupApplicable
    (implementations : List ImplScheme) (instances : List MethodInstance)
    (receiver : GroundTy) (name : String)
    (scheme : MethodScheme) : Prop :=
  ∃ arguments resolved,
    scheme.applies implementations instances receiver name arguments resolved

/-- A member call resolves only if exactly one core function applies. -/
def ResolvesMethod
    (implementations : List ImplScheme) (methods : List MethodScheme)
    (instances : List MethodInstance)
    (callSiteModule : ModuleId)
    (receiver : GroundTy) (name : String) (arguments : List GroundTy)
    (selected : MethodScheme) (resolved : MethodInstance) : Prop :=
    selected ∈ methods ∧
    selected.appliesMember implementations instances receiver name arguments resolved ∧
    selected.preferredAt methods callSiteModule
      (GroundMethodLookupApplicable implementations instances receiver name) ∧
    ∀ (candidate : MethodScheme) (candidateInstance : MethodInstance),
      candidate ∈ methods →
      candidate.appliesMember implementations instances receiver name arguments candidateInstance →
      candidate.preferredAt methods callSiteModule
        (GroundMethodLookupApplicable implementations instances receiver name) →
      candidateInstance.function = resolved.function

/-- A type-qualified inherent-function call resolves through the same finite
    receiver/name declaration index as member syntax, but applies the
    associated-call argument convention above. -/
def ResolvesAssociatedMethod
    (implementations : List ImplScheme) (methods : List MethodScheme)
    (instances : List MethodInstance)
    (callSiteModule : ModuleId)
    (receiver : GroundTy) (name : String) (arguments : List GroundTy)
    (selected : MethodScheme) (resolved : MethodInstance) : Prop :=
    selected ∈ methods ∧
    selected.appliesAssociated implementations instances receiver name arguments resolved ∧
    selected.preferredAt methods callSiteModule
      (GroundMethodLookupApplicable implementations instances receiver name) ∧
    ∀ (candidate : MethodScheme) (candidateInstance : MethodInstance),
      candidate ∈ methods →
      candidate.appliesAssociated implementations instances receiver name arguments
        candidateInstance →
      candidate.preferredAt methods callSiteModule
        (GroundMethodLookupApplicable implementations instances receiver name) →
      candidateInstance.function = resolved.function

/-- A finite method table is coherent when the receiver/name lookup key selects
    one declaration before ordinary arguments are checked. Argument types are
    deliberately absent: the current compiler's method index does not support
    argument-list overloading, and exact/generic receiver-key overlap fails
    closed. -/
def MethodLookupCoherent
    (implementations : List ImplScheme) (methods : List MethodScheme)
    (instances : List MethodInstance) : Prop :=
  ∀ callSiteModule receiver name selected,
    selected ∈ methods →
    GroundMethodLookupApplicable implementations instances receiver name selected →
    selected.preferredAt methods callSiteModule
      (GroundMethodLookupApplicable implementations instances receiver name) →
    ∀ candidate,
      candidate ∈ methods →
      GroundMethodLookupApplicable implementations instances receiver name candidate →
      candidate.preferredAt methods callSiteModule
        (GroundMethodLookupApplicable implementations instances receiver name) →
      candidate = selected

end Lanius.Static
