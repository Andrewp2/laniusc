import Lanius.SurfaceElaboration

namespace Lanius.Compiler.FunctionInstanceCheck

open Lanius
open Lanius.SurfaceElaboration

/- The function table is a catalog, not a singleton.  A selected row therefore
   carries its own membership facts and is never recovered by list search. -/
structure Candidate (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy) where
  scheme : Static.FunctionScheme
  resolved : Static.FunctionInstance
  schemeMember : scheme ∈ context.functions
  instanceMember : resolved ∈ context.functionInstances
  substitution : Static.Substitution
  instantiated : Static.FunctionInstantiates context.implementations scheme
    substitution resolved
  parameterAgreement : resolved.parameterTypes = argumentTypes
  explicitArguments : ExplicitCallArgumentsGround context path
    scheme.genericParameters substitution

theorem Candidate.applies (candidate : Candidate context path argumentTypes) :
    DirectCallApplies context path candidate.scheme argumentTypes candidate.resolved :=
  ⟨candidate.instanceMember, candidate.substitution, candidate.instantiated,
    candidate.parameterAgreement, candidate.explicitArguments⟩

/- This is deliberately a relation on rows, rather than equality of whole
   scheme/instance structures.  It permits duplicate metadata rows and does
   not require a DecidableEq instance for either structure. -/
def AllApplicableSameFunctionId
    (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy)
    (scheme : Static.FunctionScheme) (resolved : Static.FunctionInstance) : Prop :=
  ∀ candidate candidateInstance,
    candidate ∈ context.functions →
    candidate.declaration = scheme.declaration →
    DirectCallApplies context path candidate argumentTypes candidateInstance →
    candidateInstance.function = resolved.function

structure Evidence (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy) where
  candidate : Candidate context path argumentTypes
  coherent : AllApplicableSameFunctionId context path argumentTypes
    candidate.scheme candidate.resolved

abbrev DirectCallEvidence := Evidence
abbrev Checked := Evidence
abbrev SelectedCandidate := Candidate
abbrev FunctionIdCoherence := AllApplicableSameFunctionId
abbrev allApplicableSameFunctionId := AllApplicableSameFunctionId

theorem Evidence.applies (evidence : Evidence context path argumentTypes) :
    DirectCallApplies context path evidence.candidate.scheme argumentTypes
      evidence.candidate.resolved :=
  evidence.candidate.applies

/- A Names.Resolves witness is the small piece of lookup evidence this layer
   needs.  Keeping this constructor here avoids making callers manufacture an
   intermediate `ResolvesGlobal` proof just to assemble a direct call. -/
theorem Evidence.resolvesDirectCall
    (evidence : Evidence context path argumentTypes)
    (notShadowed : GlobalPathNotShadowed context path)
    (reference : Names.Reference)
    (formed : Names.Reference.fromSurfacePath? .value path = some reference)
    (resolvedName : Names.Resolves context.names context.currentModule reference symbol)
    (declaration : evidence.candidate.scheme.declaration = symbol.declaration) :
    ResolvesDirectCall context path argumentTypes evidence.candidate.scheme
      evidence.candidate.resolved := by
  refine ⟨notShadowed, ⟨symbol, .intro reference formed resolvedName,
    evidence.candidate.schemeMember, declaration, evidence.applies, ?_⟩⟩
  intro candidate candidateInstance candidateMember candidateDeclaration applies
  apply evidence.coherent candidate candidateInstance candidateMember
  exact candidateDeclaration.trans declaration.symm
  exact applies

theorem Evidence.resolvesDirectCallOfGlobal
    (evidence : Evidence context path argumentTypes)
    (notShadowed : GlobalPathNotShadowed context path)
    (symbol : Names.Symbol)
    (resolvedName : ResolvesGlobal context .value path symbol)
    (declaration : evidence.candidate.scheme.declaration = symbol.declaration) :
    ResolvesDirectCall context path argumentTypes evidence.candidate.scheme
      evidence.candidate.resolved := by
  refine ⟨notShadowed, ⟨symbol, resolvedName, evidence.candidate.schemeMember,
    declaration, evidence.applies, ?_⟩⟩
  intro candidate candidateInstance candidateMember candidateDeclaration applies
  exact evidence.coherent candidate candidateInstance candidateMember
    (candidateDeclaration.trans declaration.symm) applies

/- `pathTypeArguments?` returns syntax trees, whose inductive type intentionally
   has no global equality instance.  Matching on the option is both executable
   and proof-producing, and is enough for the monomorphic direct-call subset. -/
def noExplicitArguments (path : Surface.Path) : Bool :=
  match pathTypeArguments? path with
  | some [] => true
  | some (_ :: _) | none => false

theorem noExplicitArguments_sound {path : Surface.Path}
    (accepted : noExplicitArguments path = true) :
    pathTypeArguments? path = some [] := by
  unfold noExplicitArguments at accepted
  cases found : pathTypeArguments? path with
  | none => simp [found] at accepted
  | some values =>
      cases values with
      | nil => simpa using found
      | cons head tail => simp [found] at accepted

theorem monomorphicExplicitArguments
    (context : Context) (path : Surface.Path)
    (substitution : Static.Substitution)
    {parameters : List Static.GenericParameter}
    (parametersEmpty : parameters = [])
    (noArguments : pathTypeArguments? path = some []) :
    ExplicitCallArgumentsGround context path parameters substitution := by
  cases parametersEmpty
  simp [ExplicitCallArgumentsGround, noArguments]

/- A small bespoke equality for the executable index checker.  In particular,
   it does not ask Lean to synthesize equality for FunctionScheme or
   FunctionInstance. -/
def groundTypeEq (left right : Static.GroundTy) : Bool :=
  match Static.GroundTy.decEq left right with
  | isTrue _ => true
  | isFalse _ => false

def groundTypeListEq (left right : List Static.GroundTy) : Bool :=
  match left, right with
  | [], [] => true
  | left :: leftTail, right :: rightTail =>
      groundTypeEq left right && groundTypeListEq leftTail rightTail
  | _, _ => false

theorem groundTypeEq_eq_true {left right : Static.GroundTy}
    (equal : groundTypeEq left right = true) : left = right := by
  unfold groundTypeEq at equal
  cases found : Static.GroundTy.decEq left right with
  | isTrue proof => exact proof
  | isFalse proof => simp [found] at equal

theorem groundTypeListEq_eq_true {left right : List Static.GroundTy}
    (equal : groundTypeListEq left right = true) : left = right := by
  induction left generalizing right with
  | nil => cases right <;> simp [groundTypeListEq] at equal ⊢
  | cons left leftTail induction =>
      cases right with
      | cons right rightTail =>
          simp only [groundTypeListEq, Bool.and_eq_true] at equal
          rw [groundTypeEq_eq_true equal.1, induction equal.2]
      | nil => simp [groundTypeListEq] at equal

theorem groundTypeEq_refl (type : Static.GroundTy) :
    groundTypeEq type type = true := by
  unfold groundTypeEq
  cases found : Static.GroundTy.decEq type type with
  | isTrue equal => rfl
  | isFalse unequal => exact False.elim (unequal rfl)

theorem groundTypeListEq_refl (types : List Static.GroundTy) :
    groundTypeListEq types types = true := by
  induction types with
  | nil => rfl
  | cons head tail induction =>
      simp [groundTypeListEq, groundTypeEq_refl head, induction]

def functionIdEq (left right : FunctionId) : Bool := decide (left = right)

def sameFunctionId := functionIdEq
def sameGroundTypes := groundTypeListEq

theorem functionIdEq_eq_true {left right : FunctionId}
    (equal : functionIdEq left right = true) : left = right :=
  of_decide_eq_true equal

theorem sameFunctionId_eq_true {left right : FunctionId}
    (equal : sameFunctionId left right = true) : left = right :=
  functionIdEq_eq_true equal

theorem FunctionInstantiates.declaration
    (instantiated : Static.FunctionInstantiates implementations scheme
      substitution resolved) :
    resolved.declaration = scheme.declaration := by
  cases instantiated with
  | intro bound arguments requirements types =>
      unfold Static.FunctionScheme.instantiateTypes at types
      rcases Option.bind_eq_some_iff.mp types with
        ⟨parameterTypes, parameterTypesFound, returnContinuation⟩
      rcases Option.bind_eq_some_iff.mp returnContinuation with
        ⟨returnType, returnTypeFound, result⟩
      have instanceEquality := Option.some.inj result
      exact (congrArg Static.FunctionInstance.declaration instanceEquality).symm

def sameInstanceKey (left right : Static.FunctionInstance) : Bool :=
  decide (left.declaration = right.declaration) &&
    groundTypeListEq left.parameterTypes right.parameterTypes

def coherentWithHead (head : Static.FunctionInstance)
    (tail : List Static.FunctionInstance) : Bool :=
  tail.all (fun candidate =>
    !sameInstanceKey head candidate ||
      sameFunctionId head.function candidate.function)

def instancesCoherent : List Static.FunctionInstance → Bool
  | [] => true
  | head :: tail => coherentWithHead head tail && instancesCoherent tail

theorem instancesCoherent_sound
    {instances : List Static.FunctionInstance}
    (coherent : instancesCoherent instances = true)
    {left right : Static.FunctionInstance}
    (leftMember : left ∈ instances) (rightMember : right ∈ instances)
    (declaration : left.declaration = right.declaration)
    (parameters : left.parameterTypes = right.parameterTypes) :
    left.function = right.function := by
  induction instances with
  | nil => simp at leftMember
  | cons head tail ih =>
      simp only [instancesCoherent, Bool.and_eq_true] at coherent
      simp only [List.mem_cons] at leftMember rightMember
      rcases leftMember with rfl | leftMember
      · rcases rightMember with rfl | rightMember
        · rfl
        · have all := List.all_eq_true.mp coherent.1 right rightMember
          simp only [coherentWithHead, Bool.or_eq_true, Bool.not_eq_true] at all
          have key : sameInstanceKey left right = true := by
            simp [sameInstanceKey, declaration, parameters, groundTypeListEq_refl]
          rcases all with notKey | function
          · simp [key] at notKey
          · exact sameFunctionId_eq_true function
      · rcases rightMember with rfl | rightMember
        · symm
          have all := List.all_eq_true.mp coherent.1 left leftMember
          simp only [coherentWithHead, Bool.or_eq_true, Bool.not_eq_true] at all
          have key : sameInstanceKey right left = true := by
            simp [sameInstanceKey, declaration, parameters, groundTypeListEq_refl]
          rcases all with notKey | function
          · simp [key] at notKey
          · exact sameFunctionId_eq_true function
        · exact ih coherent.2 leftMember rightMember

/- Shape checked by executable code when no explicit generic arguments are
   present.  The proof fields retain the exact rows, so arbitrary table order
   and duplicate declaration metadata are harmless. -/
structure IndexedShape (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy) (schemeIndex instanceIndex : Nat) where
  scheme : Static.FunctionScheme
  resolved : Static.FunctionInstance
  schemeFound : context.functions[schemeIndex]? = some scheme
  instanceFound : context.functionInstances[instanceIndex]? = some resolved
  monomorphic : scheme.genericParameters = []
  noArguments : pathTypeArguments? path = some []
  parameterAgreement : resolved.parameterTypes = argumentTypes

theorem IndexedShape.schemeMember
    (shape : IndexedShape context path argumentTypes schemeIndex instanceIndex) :
    shape.scheme ∈ context.functions :=
  List.mem_of_getElem? shape.schemeFound

theorem IndexedShape.instanceMember
    (shape : IndexedShape context path argumentTypes schemeIndex instanceIndex) :
    shape.resolved ∈ context.functionInstances :=
  List.mem_of_getElem? shape.instanceFound

def checkIndices (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy)
    (schemeIndex instanceIndex : Nat) : Bool :=
  match context.functions[schemeIndex]?, context.functionInstances[instanceIndex]? with
  | some scheme, some resolved =>
      match scheme.genericParameters with
      | [] => noExplicitArguments path &&
          groundTypeListEq resolved.parameterTypes argumentTypes
      | _ => false
  | _, _ => false

/- Public executable entry point for the index-oriented checker. -/
def check := checkIndices

def checkedIndices? (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy)
    (schemeIndex instanceIndex : Nat) : Option (IndexedShape context path argumentTypes
      schemeIndex instanceIndex) :=
  match schemeFound : context.functions[schemeIndex]?,
      instanceFound : context.functionInstances[instanceIndex]? with
  | some scheme, some resolved =>
      match parameters : scheme.genericParameters with
      | .nil =>
          if noArguments : noExplicitArguments path = true then
            if equal : groundTypeListEq resolved.parameterTypes argumentTypes = true then
              some {
                scheme := scheme
                resolved := resolved
                schemeFound := schemeFound
                instanceFound := instanceFound
                monomorphic := by simpa using parameters
                noArguments := noExplicitArguments_sound noArguments
                parameterAgreement := groundTypeListEq_eq_true equal }
            else none
          else none
      | .cons _ _ => none
  | _, _ => none

def Candidate.ofIndexed
    (shape : IndexedShape context path argumentTypes schemeIndex instanceIndex)
    (substitution : Static.Substitution)
    (instantiated : Static.FunctionInstantiates context.implementations
      shape.scheme substitution shape.resolved) : Candidate context path argumentTypes :=
  { scheme := shape.scheme
    resolved := shape.resolved
    schemeMember := List.mem_of_getElem? shape.schemeFound
    instanceMember := List.mem_of_getElem? shape.instanceFound
    substitution := substitution
    instantiated := instantiated
    parameterAgreement := shape.parameterAgreement
    explicitArguments := monomorphicExplicitArguments context path substitution
      shape.monomorphic shape.noArguments }

def functionInstanceEq (left right : Static.FunctionInstance) : Bool :=
  decide (left.declaration = right.declaration ∧ left.function = right.function ∧
    left.typeArguments = right.typeArguments ∧
    left.constArguments = right.constArguments ∧
    left.parameterTypes = right.parameterTypes ∧ left.returnType = right.returnType)

theorem functionInstanceEq_eq_true {left right : Static.FunctionInstance}
    (equal : functionInstanceEq left right = true) : left = right := by
  unfold functionInstanceEq at equal
  rcases of_decide_eq_true equal with ⟨declaration, function, typeArguments,
    constArguments, parameterTypes, returnType⟩
  cases left
  cases right
  simp_all

/- Reconstruct the instantiation certificate from the retained monomorphic
   scheme/instance fields.  The executable checker does not accept a proof
   supplied by its caller: it first checks the complete shape and the
   executable `instantiateTypes` result, then packages the corresponding
   kernel-checked relation. -/
def monomorphicInstantiation?
    (context : Context) (scheme : Static.FunctionScheme)
    (resolved : Static.FunctionInstance) :
    Option (ProofCache (Static.FunctionInstantiates context.implementations scheme {}
      resolved)) :=
  match scheme with
  | ⟨declaration, genericParameters, parameterTypes, returnType, requirements⟩ =>
      match resolved with
      | ⟨resolvedDeclaration, function, typeArguments, constArguments,
          resolvedParameterTypes, resolvedReturnType⟩ =>
          match genericParameters, requirements, typeArguments, constArguments with
          | [], [], [], [] =>
              let scheme : Static.FunctionScheme :=
                ⟨declaration, [], parameterTypes, returnType, []⟩
              let resolved : Static.FunctionInstance :=
                ⟨resolvedDeclaration, function, [], [], resolvedParameterTypes,
                  resolvedReturnType⟩
              match found : scheme.instantiateTypes resolved.function [] [] {} with
              | none => none
              | some instantiated =>
                  if equal : functionInstanceEq instantiated resolved = true then
                    let instanceEqual := functionInstanceEq_eq_true equal
                    some ⟨by
                      apply Static.FunctionInstantiates.intro .nil .nil .nil
                      simpa [instanceEqual] using found⟩
                  else none
          | _, _, _, _ => none

def candidateAt?
    (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy)
    (schemeIndex instanceIndex : Nat) :
    Option (Candidate context path argumentTypes) :=
  match checkedIndices? context path argumentTypes schemeIndex instanceIndex with
  | none => none
  | some shape =>
      match monomorphicInstantiation? context shape.scheme shape.resolved with
      | none => none
      | some instantiated => some (Candidate.ofIndexed shape {} instantiated.proof)

def indexPairs (context : Context) : List (Nat × Nat) :=
  (List.range context.functions.length).flatMap fun schemeIndex =>
    (List.range context.functionInstances.length).map fun instanceIndex =>
      (schemeIndex, instanceIndex)

def candidateSearch?
    (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy) :
    List (Nat × Nat) → Option (Candidate context path argumentTypes)
  | [] => none
  | (schemeIndex, instanceIndex) :: tail =>
      match candidateAt? context path argumentTypes schemeIndex instanceIndex with
      | some candidate => some candidate
      | none => candidateSearch? context path argumentTypes tail

def candidateSearchForDeclaration?
    (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy) (declaration : Nat) :
    List (Nat × Nat) → Option (Candidate context path argumentTypes)
  | [] => none
  | (schemeIndex, instanceIndex) :: tail =>
      match candidateAt? context path argumentTypes schemeIndex instanceIndex with
      | some candidate =>
          if candidate.scheme.declaration == declaration then
            some candidate
          else
            candidateSearchForDeclaration? context path argumentTypes declaration tail
      | none => candidateSearchForDeclaration? context path argumentTypes declaration tail

theorem Candidate.coherent
    {context : Context} {path : Surface.Path}
    {argumentTypes : List Static.GroundTy}
    (coherent : instancesCoherent context.functionInstances = true)
    (selected : Candidate context path argumentTypes) :
    AllApplicableSameFunctionId context path argumentTypes
      selected.scheme selected.resolved := by
  intro candidate candidateInstance candidateMember candidateDeclaration applies
  rcases applies with ⟨instanceMember, substitution, instantiated,
    parameterAgreement, explicitArguments⟩
  have selectedDeclaration : selected.resolved.declaration = selected.scheme.declaration :=
    FunctionInstantiates.declaration selected.instantiated
  have candidateInstanceDeclaration :
      candidateInstance.declaration = candidate.declaration :=
    FunctionInstantiates.declaration instantiated
  have declaration : candidateInstance.declaration = selected.resolved.declaration := by
    exact candidateInstanceDeclaration.trans
      (candidateDeclaration.trans selectedDeclaration.symm)
  have parameters : candidateInstance.parameterTypes = selected.resolved.parameterTypes := by
    exact parameterAgreement.trans selected.parameterAgreement.symm
  exact instancesCoherent_sound coherent instanceMember selected.instanceMember
    declaration parameters

def checked
    (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy) :
    Option (Evidence context path argumentTypes) :=
  if coherent : instancesCoherent context.functionInstances = true then
    match candidateSearch? context path argumentTypes (indexPairs context) with
    | none => none
    | some candidate => some { candidate := candidate, coherent := candidate.coherent coherent }
  else none

def checkedForDeclaration
    (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy) (declaration : Nat) :
    Option (Evidence context path argumentTypes) :=
  if coherent : instancesCoherent context.functionInstances = true then
    match candidateSearchForDeclaration? context path argumentTypes declaration
        (indexPairs context) with
    | none => none
    | some candidate => some { candidate := candidate, coherent := candidate.coherent coherent }
  else none

end Lanius.Compiler.FunctionInstanceCheck
