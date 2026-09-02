import Lanius.Elaboration
import Lanius.Names

namespace Lanius.SurfaceElaboration

open Lanius

/-- A proof stored as ordinary data so verified contexts can cache global
invariants without moving propositions out of `Prop`. -/
structure ProofCache (property : Prop) : Type where
  proof : property

/-- Lexical bindings are ordered from innermost to outermost. The relation
    below therefore gives shadowing a structural, rather than procedural,
    definition. -/
structure LocalBinding where
  name : Surface.Name
  id : VarId
  type : Static.GroundTy

inductive ResolvesLocal : List LocalBinding → Surface.Name → LocalBinding → Prop where
  | head : ResolvesLocal (binding :: outer) binding.name binding
  | tail (different : binding.name ≠ name)
      (resolved : ResolvesLocal outer name selected) :
      ResolvesLocal (binding :: outer) name selected

/-- Lexical lookup is functional: the nearest same-named binding is the only
    binding that can satisfy `ResolvesLocal`. -/
theorem ResolvesLocal.unique
    (left : ResolvesLocal locals name leftBinding)
    (right : ResolvesLocal locals name rightBinding) :
    leftBinding = rightBinding := by
  induction left generalizing rightBinding with
  | head =>
      cases right with
      | head => rfl
      | tail different _ => exact (different rfl).elim
  | tail different _ induction =>
      cases right with
      | head => exact (different rfl).elim
      | tail _ resolved => exact induction resolved

def NoLocalNamed (locals : List LocalBinding) (name : Surface.Name) : Prop :=
  ∀ binding, binding ∈ locals → binding.name ≠ name

structure ConstantEntry where
  declaration : Nat
  constant : ConstantId
  type : Static.GroundTy

structure FieldEntry where
  receiver : Static.GroundTy
  name : Surface.Name
  field : FieldId
  type : Static.GroundTy

structure TypeParameterBinding where
  name : Surface.Name
  parameter : TypeParameterId

structure ConstParameterBinding where
  name : Surface.Name
  parameter : ConstParameterId

inductive TypeAliasParameter where
  | typeParameter (name : Surface.Name) (parameter : TypeParameterId)
  | constParameter (name : Surface.Name) (parameter : ConstParameterId)

structure TypeAliasEntry where
  declaration : Nat
  moduleId : ModuleId
  parameters : List TypeAliasParameter := []
  requirements : List Static.TraitPattern := []
  target : Surface.TypeExpr

structure VariantEntry where
  declaration : Nat
  receiver : Static.GroundTy
  coreType : TypeId
  variant : VariantId
  payload : List Static.GroundTy := []

structure StructEntry where
  declaration : Nat
  receiver : Static.GroundTy
  coreType : TypeId
  fieldOrder : List FieldId := []

structure StructFieldScheme where
  name : Surface.Name
  field : FieldId
  type : Static.Ty

structure StructConstructorScheme where
  declaration : Nat
  sourceType : TypeId
  genericParameters : List Static.GenericParameter := []
  requirements : List Static.TraitPattern := []
  fields : List StructFieldScheme := []

structure VariantConstructorScheme where
  declaration : Nat
  nominalDeclaration : Nat
  sourceType : TypeId
  genericParameters : List Static.GenericParameter := []
  requirements : List Static.TraitPattern := []
  variant : VariantId
  payload : List Static.Ty := []

structure Context where
  target : Core.Target := .x86_64
  names : Names.Environment
  modulesHaveUniquePaths : Option (ProofCache (Names.ModulesHaveUniquePaths names)) := none
  symbolsAreUnique : Option (ProofCache (Names.SymbolsAreUnique names)) := none
  currentModule : ModuleId
  monomorphization : Static.Monomorphization
  implementations : List Static.ImplScheme := []
  traits : List Static.TraitScheme := []
  traitMethods : List Static.TraitMethodContract := []
  functions : List Static.FunctionScheme := []
  functionInstances : List Static.FunctionInstance := []
  methods : List Static.MethodScheme := []
  methodInstances : List Static.MethodInstance := []
  traitImplementationMethodInstances :
    List Static.TraitImplementationMethodInstance := []
  constants : List ConstantEntry := []
  fields : List FieldEntry := []
  typeParameters : List TypeParameterBinding := []
  constParameters : List ConstParameterBinding := []
  substitution : Static.Substitution := {}
  nominalSchemes : List Static.NominalScheme := []
  nominalInstances : List Static.NominalInstance := []
  typeAliases : List TypeAliasEntry := []
  variants : List VariantEntry := []
  structures : List StructEntry := []
  structConstructors : List StructConstructorScheme := []
  variantConstructors : List VariantConstructorScheme := []
  locals : List LocalBinding := []

/-- Enter the top-level scope of one source module. Global semantic tables and
    the target are shared across the source pack, while lexical and generic
    bindings belong to a declaration and must not leak between modules. -/
def Context.forModule (context : Context) (moduleId : ModuleId) : Context := {
  context with
  currentModule := moduleId
  typeParameters := []
  constParameters := []
  substitution := {}
  locals := []
}

def Context.bindLocal
    (context : Context) (name : Surface.Name) (id : VarId)
    (type : Static.GroundTy) : Context :=
  { context with locals := { name, id, type } :: context.locals }

def Context.coreLocals (context : Context) : Typing.Context := fun id => do
  let binding ← context.locals.find? (fun candidate => candidate.id == id)
  binding.type.toCore context.monomorphization

def Context.bindLocals (context : Context) (bindings : List LocalBinding) : Context :=
  bindings.foldr (fun binding result => { result with locals := binding :: result.locals }) context

@[simp] theorem Context.bindLocals_locals
    (context : Context) (bindings : List LocalBinding) :
    (context.bindLocals bindings).locals = bindings ++ context.locals := by
  induction bindings with
  | nil => rfl
  | cons head tail tailIH =>
      change head :: (context.bindLocals tail).locals =
        head :: (tail ++ context.locals)
      rw [tailIH]

def TypeAliasEntry.typeBindings (entry : TypeAliasEntry) : List TypeParameterBinding :=
  entry.parameters.filterMap fun
    | .typeParameter name parameter => some { name, parameter }
    | .constParameter _ _ => none

def TypeAliasEntry.constBindings (entry : TypeAliasEntry) : List ConstParameterBinding :=
  entry.parameters.filterMap fun
    | .typeParameter _ _ => none
    | .constParameter name parameter => some { name, parameter }

def Context.forTypeAlias
    (context : Context) (entry : TypeAliasEntry)
    (substitution : Static.Substitution) : Context := {
  context with
  currentModule := entry.moduleId
  typeParameters := entry.typeBindings
  constParameters := entry.constBindings
  substitution
  locals := []
}

def FreshLocalId (context : Context) (id : VarId) : Prop :=
  ∀ binding, binding ∈ context.locals → binding.id ≠ id

/-- The allocator invariant needed to construct statement lowering rather than
    merely postulate fresh IDs one declaration at a time. -/
def LocalIdsBelow (context : Context) (next : VarId) : Prop :=
  ∀ binding, binding ∈ context.locals → binding.id < next

/-- Canonical first local ID for expression-internal binders such as match
    patterns. It is derived from the visible lexical context, eliminating an
    otherwise existential allocation choice from expression elaboration. -/
def localIdCeiling : List LocalBinding → VarId
  | [] => 0
  | binding :: tail => max (binding.id + 1) (localIdCeiling tail)

def Context.nextExpressionLocalId (context : Context) : VarId :=
  localIdCeiling context.locals

theorem localId_lt_ceiling
    (member : binding ∈ bindings) : binding.id < localIdCeiling bindings := by
  induction bindings with
  | nil => simp at member
  | cons head tail induction =>
      simp only [List.mem_cons] at member
      simp only [localIdCeiling]
      rcases member with rfl | member
      · exact Nat.lt_of_lt_of_le (Nat.lt_succ_self _) (Nat.le_max_left _ _)
      · exact Nat.lt_of_lt_of_le (induction member) (Nat.le_max_right _ _)

theorem Context.localIdsBelow_nextExpressionLocalId (context : Context) :
    LocalIdsBelow context context.nextExpressionLocalId := by
  intro binding member
  exact localId_lt_ceiling member

theorem LocalIdsBelow.fresh
    (bounded : LocalIdsBelow context next) : FreshLocalId context next := by
  intro binding member
  exact Nat.ne_of_lt (bounded binding member)

theorem LocalIdsBelow.mono
    (bounded : LocalIdsBelow context next) (increases : next ≤ later) :
    LocalIdsBelow context later := by
  intro binding member
  exact Nat.lt_of_lt_of_le (bounded binding member) increases

theorem LocalIdsBelow.bindLocal
    (bounded : LocalIdsBelow context next)
    (name : Surface.Name) (type : Static.GroundTy) :
    LocalIdsBelow (context.bindLocal name next type) (next + 1) := by
  intro binding member
  simp only [Context.bindLocal, List.mem_cons] at member
  rcases member with rfl | member
  · exact Nat.lt_succ_self next
  · exact Nat.lt_succ_of_lt (bounded binding member)

def PatternBindingsFresh (context : Context) (bindings : List LocalBinding) : Prop :=
  (∀ binding, binding ∈ bindings → FreshLocalId context binding.id) ∧
    bindings.Pairwise fun left right =>
      left.id ≠ right.id ∧ left.name ≠ right.name

def singleNamePath? : Surface.Path → Option Surface.Name
  | { segments := [.mk name []] } => some name
  | _ => none

def unqualifiedPathName? : Surface.Path → Option Surface.Name
  | { segments := [.mk name _] } => some name
  | _ => none

theorem singleNamePath_unqualified
    (single : singleNamePath? path = some name) :
    unqualifiedPathName? path = some name := by
  cases path with
  | mk segments =>
      cases segments with
      | nil => simp [singleNamePath?] at single
      | cons head tail =>
          cases tail with
          | nil =>
              cases head with
              | mk segmentName arguments =>
                  cases arguments with
                  | nil =>
                      simp [singleNamePath?] at single
                      subst segmentName
                      simp [unqualifiedPathName?]
                  | cons argument arguments =>
                      simp [singleNamePath?] at single
          | cons second rest => simp [singleNamePath?] at single

theorem builtinTypePath_eq_of_single
    (single : singleNamePath? path = some name)
    (found : Elaboration.builtinScalar? name = some scalar) :
    Elaboration.builtinTypePath? path = some (.scalar scalar) := by
  cases path with
  | mk segments =>
      cases segments with
      | nil => simp [singleNamePath?] at single
      | cons head tail =>
          cases tail with
          | nil =>
              cases head with
              | mk segmentName arguments =>
                  cases arguments with
                  | nil =>
                      simp [singleNamePath?] at single
                      subst segmentName
                      simpa [Elaboration.builtinTypePath?] using found
                  | cons argument arguments =>
                      simp [singleNamePath?] at single
          | cons second rest => simp [singleNamePath?] at single

def pathTypeArguments? (path : Surface.Path) : Option (List Surface.TypeExpr) :=
  path.segments.getLast?.map fun
    | .mk _ arguments => arguments

def pathLeafName? (path : Surface.Path) : Option Surface.Name :=
  path.segments.getLast?.map fun
    | .mk name _ => name

/-- Canonically split `TypePath::function` call syntax. At least one segment
    must remain for the owner type, and the function leaf cannot carry generic
    arguments because current inherent functions reject method-local generic
    parameters. Generic arguments on the owner type remain intact. -/
def associatedFunctionPath? (path : Surface.Path) :
    Option (Surface.Path × Surface.Name) :=
  match path.segments.reverse with
  | .mk name [] :: ownerLast :: ownerPrefixReversed =>
      some ({ segments := (ownerLast :: ownerPrefixReversed).reverse }, name)
  | _ => none

/-- Lexical locals can shadow only an unqualified global value. A qualified
    path bypasses the lexical name while still passing ordinary module and
    visibility resolution. -/
def GlobalPathNotShadowed (context : Context) (path : Surface.Path) : Prop :=
  match unqualifiedPathName? path with
  | some name => NoLocalNamed context.locals name
  | none => True

inductive BuiltinIntrinsic where
  | printI32
  | assert
  | i32ArrayDataPtr
deriving DecidableEq, Repr

def builtinIntrinsic? (path : Surface.Path) : Option BuiltinIntrinsic :=
  match pathLeafName? path with
  | some "print" => some .printI32
  | some "print_i32" => some .printI32
  | some "assert" => some .assert
  | some "i32_array_data_ptr" => some .i32ArrayDataPtr
  | _ => none

/-- Intrinsic recognition and the explicit non-intrinsic call guard are
    disjoint independently of the selected global declaration category. -/
theorem builtinIntrinsic_some_excludes_none
    (found : builtinIntrinsic? path = some intrinsic)
    (absent : builtinIntrinsic? path = none) : False := by
  rw [absent] at found
  contradiction

inductive ResolvesTypeParameter :
    List TypeParameterBinding → Surface.Name → TypeParameterBinding → Prop where
  | head : ResolvesTypeParameter (binding :: outer) binding.name binding
  | tail (different : binding.name ≠ name)
      (resolved : ResolvesTypeParameter outer name selected) :
      ResolvesTypeParameter (binding :: outer) name selected

inductive ResolvesConstParameter :
    List ConstParameterBinding → Surface.Name → ConstParameterBinding → Prop where
  | head : ResolvesConstParameter (binding :: outer) binding.name binding
  | tail (different : binding.name ≠ name)
      (resolved : ResolvesConstParameter outer name selected) :
      ResolvesConstParameter (binding :: outer) name selected

theorem ResolvesTypeParameter.unique
    (left : ResolvesTypeParameter bindings name leftBinding)
    (right : ResolvesTypeParameter bindings name rightBinding) :
    leftBinding = rightBinding := by
  induction left generalizing rightBinding with
  | head =>
      cases right with
      | head => rfl
      | tail different _ => exact (different rfl).elim
  | tail different _ induction =>
      cases right with
      | head => exact (different rfl).elim
      | tail _ resolved => exact induction resolved

theorem ResolvesConstParameter.unique
    (left : ResolvesConstParameter bindings name leftBinding)
    (right : ResolvesConstParameter bindings name rightBinding) :
    leftBinding = rightBinding := by
  induction left generalizing rightBinding with
  | head =>
      cases right with
      | head => rfl
      | tail different _ => exact (different rfl).elim
  | tail different _ induction =>
      cases right with
      | head => exact (different rfl).elim
      | tail _ resolved => exact induction resolved

/-- Qualified type paths bypass generic parameters.  An unqualified global
    type path is admissible only when no in-scope type parameter has that name.
    Together with the builtin guard on the global rules, this makes primitive,
    generic, and global type lookup priorities explicit. -/
def GlobalTypePathNotShadowed
    (context : Context) (path : Surface.Path) : Prop :=
  ∀ name binding,
    singleNamePath? path = some name →
      ¬ ResolvesTypeParameter context.typeParameters name binding

theorem ResolvesTypeParameter.member
    (resolved : ResolvesTypeParameter bindings name selected) :
    selected ∈ bindings := by
  induction resolved with
  | head => simp
  | tail different resolved induction => simp [induction]

theorem ResolvesConstParameter.member
    (resolved : ResolvesConstParameter bindings name selected) :
    selected ∈ bindings := by
  induction resolved with
  | head => simp
  | tail different resolved induction => simp [induction]

inductive ResolvesGlobal
    (context : Context) (lookupNamespace : Names.LookupNamespace) :
    Surface.Path → Names.Symbol → Prop where
  | intro
      (reference : Names.Reference)
      (formed : Names.Reference.fromSurfacePath? lookupNamespace path = some reference)
      (resolved : Names.Resolves context.names context.currentModule reference symbol) :
      ResolvesGlobal context lookupNamespace path symbol

/-- Resolving one source path in one namespace determines its declaration.
    The returned symbol may carry redundant presentation metadata, but name
    resolution cannot associate the same reference with two declarations. -/
theorem ResolvesGlobal.declaration_unique
    (leftResolved : ResolvesGlobal context lookupNamespace path left)
    (rightResolved : ResolvesGlobal context lookupNamespace path right) :
    left.declaration = right.declaration := by
  cases leftResolved with
  | intro leftReference leftFormed leftNameResolved =>
      cases rightResolved with
      | intro rightReference rightFormed rightNameResolved =>
          have referenceEquality : leftReference = rightReference :=
            Option.some.inj (leftFormed.symm.trans rightFormed)
          subst rightReference
          exact (leftNameResolved.2 right rightNameResolved.1 |>.2).symm

inductive ResolvesConstant (context : Context) :
    Surface.Path → ConstantEntry → Prop where
  | intro
      (notShadowed : GlobalPathNotShadowed context path)
      (symbol : Names.Symbol)
      (resolved : ResolvesGlobal context .value path symbol)
      (member : entry ∈ context.constants)
      (declaration : entry.declaration = symbol.declaration) :
      ResolvesConstant context path entry

mutual
  /-- Type annotations are resolved after selecting the current generic
      substitution. Generic source names never leak into monomorphic core. -/
  inductive TypeGrounds :
      Context → Surface.TypeExpr → Static.GroundTy → Prop where
    | builtin
        (single : singleNamePath? { segments } = some name)
        (found : Elaboration.builtinScalar? name = some scalar) :
        TypeGrounds context (.path segments) (.scalar scalar)
    | parameter
        (single : singleNamePath? { segments } = some name)
        (notBuiltin : Elaboration.builtinTypePath? { segments } = none)
        (resolved : ResolvesTypeParameter context.typeParameters name binding)
        (substituted : context.substitution.types binding.parameter = some type) :
        TypeGrounds context (.path segments) type
    | nominal
        (symbol : Names.Symbol)
        (notBuiltin : Elaboration.builtinTypePath? { segments } = none)
        (notShadowed : GlobalTypePathNotShadowed context { segments })
        (resolved : ResolvesGlobal context .type { segments } symbol)
        (member : scheme ∈ context.nominalSchemes)
        (declaration : scheme.declaration = symbol.declaration)
        (argumentsFound : pathTypeArguments? { segments } = some surfaceArguments)
        (arguments : NominalArgumentsGround context scheme.genericParameters
          surfaceArguments groundTypeArguments groundConstArguments) :
        TypeGrounds context (.path segments)
          (.nominal scheme.type groundTypeArguments groundConstArguments)
    | typeAlias
        (symbol : Names.Symbol)
        (notBuiltin : Elaboration.builtinTypePath? { segments } = none)
        (notShadowed : GlobalTypePathNotShadowed context { segments })
        (resolved : ResolvesGlobal context .type { segments } symbol)
        (member : entry ∈ context.typeAliases)
        (declaration : entry.declaration = symbol.declaration)
        (argumentsFound : pathTypeArguments? { segments } = some surfaceArguments)
        (substitution : Static.Substitution)
        (arguments : TypeAliasArgumentsGround context substitution
          entry.parameters surfaceArguments)
        (requirements : Static.RequirementsSatisfied context.implementations
          substitution entry.requirements)
        (target : TypeGrounds (context.forTypeAlias entry substitution)
          entry.target groundType) :
        TypeGrounds context (.path segments) groundType
    | array
        (element : TypeGrounds context surfaceElement groundElement)
        (length : ArrayLengthGrounds context surfaceLength groundLength) :
        TypeGrounds context (.array surfaceElement surfaceLength)
          (.array groundElement groundLength)
    | slice (element : TypeGrounds context surfaceElement groundElement) :
        TypeGrounds context (.slice surfaceElement) (.slice groundElement)
    | reference (referent : TypeGrounds context surfaceReferent groundReferent) :
        TypeGrounds context (.reference surfaceReferent) (.reference groundReferent)

  inductive TypesGround :
      Context → List Surface.TypeExpr → List Static.GroundTy → Prop where
    | nil : TypesGround context [] []
    | cons
        (head : TypeGrounds context surfaceHead groundHead)
        (tail : TypesGround context surfaceTail groundTail) :
        TypesGround context (surfaceHead :: surfaceTail) (groundHead :: groundTail)

  inductive ArrayLengthGrounds :
      Context → Surface.ArrayLength → Nat → Prop where
    | literal : ArrayLengthGrounds context (.literal length) length
    | parameter
        (resolved : ResolvesConstParameter context.constParameters name binding)
        (substituted : context.substitution.constants binding.parameter = some length) :
        ArrayLengthGrounds context (.parameter name) length

  /-- Const generic arguments currently use identifier syntax in the grammar.
      Their meaning is selected by the alias parameter kind, not by treating a
      value name as a type. -/
  inductive ConstTypeArgumentGrounds :
      Context → Surface.TypeExpr → Nat → Prop where
    | parameter
        (single : singleNamePath? { segments } = some name)
        (resolved : ResolvesConstParameter context.constParameters name binding)
        (substituted : context.substitution.constants binding.parameter = some value) :
        ConstTypeArgumentGrounds context (.path segments) value

  inductive TypeAliasArgumentsGround :
      Context → Static.Substitution → List TypeAliasParameter →
        List Surface.TypeExpr → Prop where
    | nil : TypeAliasArgumentsGround context substitution [] []
    | typeParameter
        (argument : TypeGrounds context surfaceArgument groundArgument)
        (bound : substitution.types parameter = some groundArgument)
        (tail : TypeAliasArgumentsGround context substitution parameters surfaceArguments) :
        TypeAliasArgumentsGround context substitution
          (.typeParameter name parameter :: parameters)
          (surfaceArgument :: surfaceArguments)
    | constParameter
        (argument : ConstTypeArgumentGrounds context surfaceArgument value)
        (bound : substitution.constants parameter = some value)
        (tail : TypeAliasArgumentsGround context substitution parameters surfaceArguments) :
      TypeAliasArgumentsGround context substitution
          (.constParameter name parameter :: parameters)
          (surfaceArgument :: surfaceArguments)

  inductive GenericArgumentsGround :
      Context → Static.Substitution → List Static.GenericParameter →
        List Surface.TypeExpr → Prop where
    | nil : GenericArgumentsGround context substitution [] []
    | typeParameter
        (argument : TypeGrounds context surfaceArgument groundArgument)
        (bound : substitution.types parameter = some groundArgument)
        (tail : GenericArgumentsGround context substitution parameters surfaceArguments) :
        GenericArgumentsGround context substitution
          (.typeParameter parameter :: parameters)
          (surfaceArgument :: surfaceArguments)
    | constParameter
        (argument : ConstTypeArgumentGrounds context surfaceArgument value)
        (bound : substitution.constants parameter = some value)
        (tail : GenericArgumentsGround context substitution parameters surfaceArguments) :
        GenericArgumentsGround context substitution
          (.constParameter parameter :: parameters)
          (surfaceArgument :: surfaceArguments)

  inductive NominalArgumentsGround :
      Context → List Static.GenericParameter → List Surface.TypeExpr →
        List Static.GroundTy → List Nat → Prop where
    | nil : NominalArgumentsGround context [] [] [] []
    | typeParameter
        (argument : TypeGrounds context surfaceArgument groundArgument)
        (tail : NominalArgumentsGround context parameters surfaceArguments
          groundArguments groundConstants) :
        NominalArgumentsGround context
          (.typeParameter parameter :: parameters)
          (surfaceArgument :: surfaceArguments)
          (groundArgument :: groundArguments) groundConstants
    | constParameter
        (argument : ConstTypeArgumentGrounds context surfaceArgument value)
        (tail : NominalArgumentsGround context parameters surfaceArguments
          groundArguments groundConstants) :
        NominalArgumentsGround context
          (.constParameter parameter :: parameters)
          (surfaceArgument :: surfaceArguments)
          groundArguments (value :: groundConstants)
end

def ExplicitCallArgumentsGround
    (context : Context) (path : Surface.Path)
    (parameters : List Static.GenericParameter)
    (substitution : Static.Substitution) : Prop :=
  match pathTypeArguments? path with
  | none => False
  | some [] => True
  | some arguments =>
      GenericArgumentsGround context substitution parameters arguments

def DirectCallApplies
    (context : Context) (path : Surface.Path)
    (scheme : Static.FunctionScheme)
    (argumentTypes : List Static.GroundTy)
    (resolved : Static.FunctionInstance) : Prop :=
  resolved ∈ context.functionInstances ∧
    ∃ substitution,
      Static.FunctionInstantiates context.implementations scheme substitution resolved ∧
      resolved.parameterTypes = argumentTypes ∧
      ExplicitCallArgumentsGround context path scheme.genericParameters substitution

/-- A direct call first resolves its source declaration, then selects exactly
    one monomorphic function instance for the argument types. -/
def ResolvesDirectCall
    (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy)
    (selected : Static.FunctionScheme)
    (resolved : Static.FunctionInstance) : Prop :=
  GlobalPathNotShadowed context path ∧ ∃ symbol,
    ResolvesGlobal context .value path symbol ∧
    selected ∈ context.functions ∧
    selected.declaration = symbol.declaration ∧
    DirectCallApplies context path selected argumentTypes resolved ∧
    ∀ candidate candidateInstance,
      candidate ∈ context.functions →
      candidate.declaration = symbol.declaration →
      DirectCallApplies context path candidate argumentTypes candidateInstance →
      candidateInstance.function = resolved.function

/-- Field selection is defined by receiver type and source name. Duplicate
    field metadata cannot silently acquire source-order meaning. -/
def SelectsField
    (context : Context) (receiver : Static.GroundTy)
    (name : Surface.Name) (selected : FieldEntry) : Prop :=
  selected ∈ context.fields ∧ selected.receiver = receiver ∧ selected.name = name ∧
    ∀ candidate,
      candidate ∈ context.fields → candidate.receiver = receiver → candidate.name = name →
      candidate.field = selected.field ∧ candidate.type = selected.type

/-- Agreement on duplicate field rows makes lookup functional at the complete
    record level, rather than merely at the emitted field ID. -/
theorem SelectsField.unique
    (leftSelected : SelectsField context receiver name left)
    (rightSelected : SelectsField context receiver name right) :
    left = right := by
  rcases leftSelected with
    ⟨leftMember, leftReceiver, leftName, leftAgrees⟩
  rcases rightSelected with
    ⟨rightMember, rightReceiver, rightName, _rightAgrees⟩
  have fieldsAgree := leftAgrees right rightMember rightReceiver rightName
  cases left
  cases right
  simp_all

def SelectsVariant
    (context : Context) (receiver : Static.GroundTy)
    (path : Surface.Path) (selected : VariantEntry) : Prop :=
  GlobalPathNotShadowed context path ∧ ∃ symbol,
    ResolvesGlobal context .value path symbol ∧
    selected ∈ context.variants ∧
    selected.declaration = symbol.declaration ∧
    selected.receiver = receiver ∧
    ∀ candidate,
      candidate ∈ context.variants →
      candidate.declaration = symbol.declaration →
      candidate.receiver = receiver →
      candidate.coreType = selected.coreType ∧
        candidate.variant = selected.variant ∧
        candidate.payload = selected.payload

/-- Source-level struct lookup selects symbolic declaration metadata. It does
    not inspect the set of monomorphic artifacts retained for the current job. -/
def SelectsStructConstructor
    (context : Context) (path : Surface.Path)
    (selected : StructConstructorScheme) : Prop :=
  ∃ symbol,
    ResolvesGlobal context .type path symbol ∧
    selected ∈ context.structConstructors ∧
    selected.declaration = symbol.declaration ∧
    ∀ candidate,
      candidate ∈ context.structConstructors →
      candidate.declaration = symbol.declaration →
      candidate.sourceType = selected.sourceType ∧
        candidate.genericParameters = selected.genericParameters ∧
        candidate.requirements = selected.requirements ∧
        candidate.fields = selected.fields

theorem SelectsStructConstructor.member
    (selected : SelectsStructConstructor context path constructor) :
    constructor ∈ context.structConstructors := by
  obtain ⟨_symbol, _resolved, member, _declaration, _unique⟩ := selected
  exact member

/-- Variant paths live in the value namespace. Their symbolic payload belongs
    to the source enum declaration and is independent of monomorphization. -/
def SelectsVariantConstructor
    (context : Context) (path : Surface.Path)
    (selected : VariantConstructorScheme) : Prop :=
  GlobalPathNotShadowed context path ∧ ∃ symbol,
    ResolvesGlobal context .value path symbol ∧
    selected ∈ context.variantConstructors ∧
    selected.declaration = symbol.declaration ∧
    ∀ candidate,
      candidate ∈ context.variantConstructors →
      candidate.declaration = symbol.declaration →
      candidate.nominalDeclaration = selected.nominalDeclaration ∧
        candidate.sourceType = selected.sourceType ∧
        candidate.genericParameters = selected.genericParameters ∧
        candidate.requirements = selected.requirements ∧
        candidate.variant = selected.variant ∧
        candidate.payload = selected.payload

theorem SelectsVariantConstructor.member
    (selected : SelectsVariantConstructor context path constructor) :
    constructor ∈ context.variantConstructors := by
  obtain ⟨_notShadowed, _symbol, _resolved, member, _declaration, _unique⟩ :=
    selected
  exact member

def PathHasNoGenericArguments (path : Surface.Path) : Prop :=
  pathTypeArguments? path = some []

def ExplicitNominalArgumentsGround
    (context : Context) (path : Surface.Path)
    (parameters : List Static.GenericParameter)
    (substitution : Static.Substitution) : Prop :=
  ∃ head tail,
    pathTypeArguments? path = some (head :: tail) ∧
      GenericArgumentsGround context substitution parameters (head :: tail)

def NominalPathArgumentsCompatible
    (context : Context) (path : Surface.Path)
    (parameters : List Static.GenericParameter)
    (substitution : Static.Substitution) : Prop :=
  PathHasNoGenericArguments path ∨
    ExplicitNominalArgumentsGround context path parameters substitution

/-- Connect symbolic source construction to exactly one emitted nominal
    artifact. The substitution determines every generic parameter before the
    artifact table is consulted. -/
def NominalConstructorInstantiates
    (context : Context) (declaration : Nat) (sourceType : TypeId)
    (kind : Static.NominalKind)
    (parameters : List Static.GenericParameter)
    (requirements : List Static.TraitPattern)
    (substitution : Static.Substitution)
    (resolved : Static.NominalInstance) : Prop :=
  resolved ∈ context.nominalInstances ∧
    resolved.declaration = declaration ∧
    resolved.sourceType = sourceType ∧
    resolved.kind = kind ∧
    Static.NominalArgumentsBound substitution parameters
      resolved.typeArguments resolved.constArguments ∧
    Static.RequirementsSatisfied context.implementations substitution requirements ∧
    ∀ candidate,
      candidate ∈ context.nominalInstances →
      candidate.sourceType = sourceType →
      candidate.typeArguments = resolved.typeArguments →
      candidate.constArguments = resolved.constArguments →
      candidate.coreType = resolved.coreType

inductive TyMentionsTypeParameter (parameter : TypeParameterId) :
    Static.Ty → Prop where
  | parameter : TyMentionsTypeParameter parameter (.parameter parameter)
  | array (element : TyMentionsTypeParameter parameter type) :
      TyMentionsTypeParameter parameter (.array type length)
  | slice (element : TyMentionsTypeParameter parameter type) :
      TyMentionsTypeParameter parameter (.slice type)
  | reference (referent : TyMentionsTypeParameter parameter type) :
      TyMentionsTypeParameter parameter (.reference type)
  | nominal
      (member : type ∈ typeArguments)
      (argument : TyMentionsTypeParameter parameter type) :
      TyMentionsTypeParameter parameter
        (.nominal sourceType typeArguments constArguments)

inductive TyMentionsConstParameter (parameter : ConstParameterId) :
    Static.Ty → Prop where
  | arrayLength : TyMentionsConstParameter parameter
      (.array element (.parameter parameter))
  | arrayElement (element : TyMentionsConstParameter parameter type) :
      TyMentionsConstParameter parameter (.array type length)
  | slice (element : TyMentionsConstParameter parameter type) :
      TyMentionsConstParameter parameter (.slice type)
  | reference (referent : TyMentionsConstParameter parameter type) :
      TyMentionsConstParameter parameter (.reference type)
  | nominalType
      (member : type ∈ typeArguments)
      (argument : TyMentionsConstParameter parameter type) :
      TyMentionsConstParameter parameter
        (.nominal sourceType typeArguments constArguments)
  | nominalConst
      (member : .parameter parameter ∈ constArguments) :
      TyMentionsConstParameter parameter
        (.nominal sourceType typeArguments constArguments)

/-- Inference is permitted only when every declared generic parameter occurs
    in an observed member type. This rules out arbitrary witnesses for phantom
    or otherwise unconstrained parameters. -/
def TypesDetermineGenericParameters
    (types : List Static.Ty) (parameters : List Static.GenericParameter) : Prop :=
  ∀ parameter, parameter ∈ parameters →
    match parameter with
    | .typeParameter id =>
        ∃ type, type ∈ types ∧ TyMentionsTypeParameter id type
    | .constParameter id =>
        ∃ type, type ∈ types ∧ TyMentionsConstParameter id type

/-- Two matches of the same type list expose matching derivations at the same
    occurrence. Membership alone is insufficient when a pattern is repeated;
    traversing both derivations together preserves the occurrence index. -/
theorem typesSymbolicallyMatch_aligned_member
    (left : Static.TypesSymbolicallyMatch leftSubstitution patterns actuals)
    (right : Static.TypesSymbolicallyMatch rightSubstitution patterns actuals)
    (member : pattern ∈ patterns) :
    ∃ actual,
      Static.TySymbolicallyMatches leftSubstitution pattern actual ∧
      Static.TySymbolicallyMatches rightSubstitution pattern actual := by
  induction patterns generalizing actuals pattern with
  | nil => simp at member
  | cons patternHead patternTail induction =>
      cases left with
      | cons leftHead leftTail =>
      cases right with
      | cons rightHead rightTail =>
          simp only [List.mem_cons] at member
          rcases member with rfl | member
          · exact ⟨_, leftHead, rightHead⟩
          · exact induction leftTail rightTail member

/-- Constant-list matching has the same occurrence-preserving projection. -/
theorem constsSymbolicallyMatch_aligned_member
    (left : Static.ConstsSymbolicallyMatch leftSubstitution patterns actuals)
    (right : Static.ConstsSymbolicallyMatch rightSubstitution patterns actuals)
    (member : pattern ∈ patterns) :
    ∃ actual,
      Static.ConstSymbolicallyMatches leftSubstitution pattern actual ∧
      Static.ConstSymbolicallyMatches rightSubstitution pattern actual := by
  induction patterns generalizing actuals pattern with
  | nil => simp at member
  | cons patternHead patternTail induction =>
      cases left with
      | cons leftHead leftTail =>
      cases right with
      | cons rightHead rightTail =>
          simp only [List.mem_cons] at member
          rcases member with rfl | member
          · exact ⟨_, leftHead, rightHead⟩
          · exact induction leftTail rightTail member

/-- If a pattern contains a type parameter, matching that pattern against one
    actual type fixes the substitution at that parameter. -/
theorem TyMentionsTypeParameter.substitution_agrees
    (mentioned : TyMentionsTypeParameter parameterId pattern)
    (left : Static.TySymbolicallyMatches leftSubstitution pattern actual)
    (right : Static.TySymbolicallyMatches rightSubstitution pattern actual) :
    leftSubstitution.types parameterId =
      rightSubstitution.types parameterId := by
  induction mentioned generalizing actual with
  | parameter =>
      cases left with
      | parameter leftFound =>
          cases right with
          | parameter rightFound => exact leftFound.trans rightFound.symm
  | array element induction =>
      cases left with
      | array leftElement _ =>
          cases right with
          | array rightElement _ => exact induction leftElement rightElement
  | slice element induction =>
      cases left with
      | slice leftElement =>
          cases right with
          | slice rightElement => exact induction leftElement rightElement
  | reference referent induction =>
      cases left with
      | reference leftReferent =>
          cases right with
          | reference rightReferent => exact induction leftReferent rightReferent
  | nominal member argument induction =>
      cases left with
      | nominal leftTypes _ =>
          cases right with
          | nominal rightTypes _ =>
              obtain ⟨_, leftArgument, rightArgument⟩ :=
                typesSymbolicallyMatch_aligned_member leftTypes rightTypes member
              exact induction leftArgument rightArgument

/-- The analogous occurrence theorem for const parameters nested in a type. -/
theorem TyMentionsConstParameter.substitution_agrees
    (mentioned : TyMentionsConstParameter parameterId pattern)
    (left : Static.TySymbolicallyMatches leftSubstitution pattern actual)
    (right : Static.TySymbolicallyMatches rightSubstitution pattern actual) :
    leftSubstitution.constants parameterId =
      rightSubstitution.constants parameterId := by
  induction mentioned generalizing actual with
  | arrayLength =>
      cases left with
      | array _ leftLength =>
          cases right with
          | array _ rightLength =>
              cases leftLength with
              | parameter leftFound =>
                  cases rightLength with
                  | parameter rightFound =>
                      exact leftFound.trans rightFound.symm
  | arrayElement element induction =>
      cases left with
      | array leftElement _ =>
          cases right with
          | array rightElement _ => exact induction leftElement rightElement
  | slice element induction =>
      cases left with
      | slice leftElement =>
          cases right with
          | slice rightElement => exact induction leftElement rightElement
  | reference referent induction =>
      cases left with
      | reference leftReferent =>
          cases right with
          | reference rightReferent => exact induction leftReferent rightReferent
  | nominalType member argument induction =>
      cases left with
      | nominal leftTypes _ =>
          cases right with
          | nominal rightTypes _ =>
              obtain ⟨_, leftArgument, rightArgument⟩ :=
                typesSymbolicallyMatch_aligned_member leftTypes rightTypes member
              exact induction leftArgument rightArgument
  | nominalConst member =>
      cases left with
      | nominal _ leftConstants =>
          cases right with
          | nominal _ rightConstants =>
              obtain ⟨_, leftArgument, rightArgument⟩ :=
                constsSymbolicallyMatch_aligned_member leftConstants
                  rightConstants member
              cases leftArgument with
              | parameter leftFound =>
                  cases rightArgument with
                  | parameter rightFound =>
                      exact leftFound.trans rightFound.symm

/-- Matching the same observed types under two substitutions makes them agree
    at every declared parameter that the constructor types determine. -/
theorem TypesDetermineGenericParameters.type_agrees
    (determined : TypesDetermineGenericParameters patterns parameters)
    (left : Static.TypesSymbolicallyMatch leftSubstitution patterns actuals)
    (right : Static.TypesSymbolicallyMatch rightSubstitution patterns actuals)
    (member : .typeParameter parameter ∈ parameters) :
    leftSubstitution.types parameter = rightSubstitution.types parameter := by
  obtain ⟨pattern, patternMember, mentioned⟩ :=
    determined (.typeParameter parameter) member
  obtain ⟨_, leftPattern, rightPattern⟩ :=
    typesSymbolicallyMatch_aligned_member left right patternMember
  exact mentioned.substitution_agrees leftPattern rightPattern

theorem TypesDetermineGenericParameters.const_agrees
    (determined : TypesDetermineGenericParameters patterns parameters)
    (left : Static.TypesSymbolicallyMatch leftSubstitution patterns actuals)
    (right : Static.TypesSymbolicallyMatch rightSubstitution patterns actuals)
    (member : .constParameter parameter ∈ parameters) :
    leftSubstitution.constants parameter =
      rightSubstitution.constants parameter := by
  obtain ⟨pattern, patternMember, mentioned⟩ :=
    determined (.constParameter parameter) member
  obtain ⟨_, leftPattern, rightPattern⟩ :=
    typesSymbolicallyMatch_aligned_member left right patternMember
  exact mentioned.substitution_agrees leftPattern rightPattern

/-- Once constructor patterns determine every declared generic parameter,
    matching the same observed types fixes the ordered generic argument
    vectors. Substitution maps may still differ outside the constructor's
    parameter domain. -/
theorem symbolicArgumentsBound_orderedArguments_unique_of_determined
    (determined : TypesDetermineGenericParameters patterns parameters)
    (leftMatches : Static.TypesSymbolicallyMatch leftSubstitution patterns actuals)
    (rightMatches : Static.TypesSymbolicallyMatch rightSubstitution patterns actuals)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution parameters
      leftTypeArguments leftConstArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution parameters
      rightTypeArguments rightConstArguments) :
    leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments := by
  exact leftBound.orderedArguments_unique_of_agreement rightBound
    (fun parameter member =>
      determined.type_agrees leftMatches rightMatches member)
    (fun parameter member =>
      determined.const_agrees leftMatches rightMatches member)

inductive RemovesNamedField (name : Surface.Name) :
    List (Surface.Name × Surface.Expr) → Surface.Expr →
      List (Surface.Name × Surface.Expr) → Prop where
  | head : RemovesNamedField name ((name, value) :: tail) value tail
  | tail
      (different : other ≠ name)
      (removed : RemovesNamedField name tail value remainder) :
      RemovesNamedField name ((other, head) :: tail) value ((other, head) :: remainder)

/-- Named-field removal follows the first matching source field and is
    functional in both the selected value and remainder. -/
theorem RemovesNamedField.unique
    (left : RemovesNamedField name fields leftValue leftRemainder)
    (right : RemovesNamedField name fields rightValue rightRemainder) :
    leftValue = rightValue ∧ leftRemainder = rightRemainder := by
  induction left generalizing rightValue rightRemainder with
  | head =>
      cases right with
      | head => exact ⟨rfl, rfl⟩
      | tail different _ => exact (different rfl).elim
  | tail different _ induction =>
      cases right with
      | head => exact (different rfl).elim
      | tail _ removed =>
          rcases induction removed with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩

theorem RemovesNamedField.selected_mem
    (removed : RemovesNamedField name fields value remainder) :
    (name, value) ∈ fields := by
  induction removed with
  | head => simp
  | tail _ _ induction => simp [induction]

theorem RemovesNamedField.remainder_subset
    (removed : RemovesNamedField name fields value remainder) :
    ∀ entry, entry ∈ remainder → entry ∈ fields := by
  induction removed with
  | head =>
      intro entry member
      exact by simp [member]
  | tail _ _ induction =>
      intro entry member
      simp only [List.mem_cons] at member ⊢
      rcases member with rfl | member
      · exact Or.inl rfl
      · exact Or.inr (induction entry member)

def NoGlobalValueResolution (context : Context) (path : Surface.Path) : Prop :=
  ∀ symbol, ¬ ResolvesGlobal context .value path symbol

def lowerUnaryOp : Surface.UnaryOp → Core.UnaryOp
  | .positive => .positive
  | .negative => .negate
  | .logicalNot => .logicalNot

def lowerBinaryOp : Surface.BinaryOp → Core.BinaryOp
  | .logicalOr => .logicalOr
  | .logicalAnd => .logicalAnd
  | .bitOr => .bitOr
  | .bitXor => .bitXor
  | .bitAnd => .bitAnd
  | .equal => .equal
  | .notEqual => .notEqual
  | .less => .less
  | .greater => .greater
  | .lessEqual => .lessEqual
  | .greaterEqual => .greaterEqual
  | .shiftLeft => .shiftLeft
  | .shiftRight => .shiftRight
  | .add => .add
  | .subtract => .subtract
  | .multiply => .multiply
  | .divide => .divide
  | .remainder => .remainder

def lowerAssignOp : Surface.AssignOp → Core.AssignOp
  | .set => .set
  | .add => .add
  | .subtract => .subtract
  | .multiply => .multiply
  | .divide => .divide
  | .remainder => .remainder
  | .bitXor => .bitXor
  | .shiftLeft => .shiftLeft
  | .shiftRight => .shiftRight
  | .bitAnd => .bitAnd
  | .bitOr => .bitOr

/-- A direct expected-type literal rule is available for this scalar target.
    This is deliberately about applicability, rather than syntax alone: a
    character literal checked as `i32`, for example, has no direct `i32`
    literal rule and may still use the ordinary `char`-to-`i32` scalar cast. -/
def ContextualScalarLiteralApplies
    (target : Core.Target) (surface : Surface.Expr)
    (targetType : Core.ScalarTy) : Prop :=
  match surface with
  | .literal literal =>
      ∃ core, Elaboration.LiteralElaborates target literal (.scalar targetType) core
  | .unary .negative (.literal (.integer text)) =>
      (∃ coreOperand,
        Elaboration.LiteralElaborates target (.integer text)
          (.scalar targetType) coreOperand ∧
        Typing.UnaryOpHasType (lowerUnaryOp .negative) (.scalar targetType)
          (.scalar targetType)) ∨
      (∃ signedType core,
        targetType = .signed signedType ∧
        Elaboration.SignedMinimumLiteralElaborates target
          text signedType core)
  | .unary op (.literal literal) =>
      ∃ coreOperand,
        Elaboration.LiteralElaborates target literal (.scalar targetType) coreOperand ∧
        Typing.UnaryOpHasType (lowerUnaryOp op) (.scalar targetType)
          (.scalar targetType)
  | _ => False

mutual
  /-- Relational surface lowering carries the inferred ground type. A separate
      `Typing.ExprHasType` derivation checks the resulting core term, keeping
      name/type inference distinct from core soundness. -/
  inductive ExprLowers :
      Context → Surface.Expr → Static.GroundTy → Core.Expr → Prop where
    | literal
        (lowered : Elaboration.LiteralElaborates context.target literal
          (Elaboration.literalDefaultType literal) expression)
        (grounded : groundType.toCore context.monomorphization =
          some (Elaboration.literalDefaultType literal)) :
        ExprLowers context (.literal literal) groundType expression
    | signedMinimumLiteral
        (lowered : Elaboration.SignedMinimumLiteralElaborates
          context.target text .i32 expression)
        (grounded : groundType.toCore context.monomorphization =
          some (.scalar (.signed .i32))) :
        ExprLowers context
          (.unary .negative (.literal (.integer text))) groundType expression
    | local
        (name : Surface.Name)
        (single : singleNamePath? path = some name)
        (resolved : ResolvesLocal context.locals name binding) :
        ExprLowers context (.path path) binding.type (.local binding.id)
    | selfValue
        (resolved : ResolvesLocal context.locals "self" binding) :
        ExprLowers context .selfValue binding.type (.local binding.id)
    | constant
        (resolved : ResolvesConstant context path entry) :
        ExprLowers context (.path path) entry.type (.constant entry.constant)
    | array
        (head : ExprLowers context surfaceHead elementType coreHead)
        (tail : ExprsCheck context surfaceTail
          (List.replicate surfaceTail.length elementType) coreTail)
        (elementCore : elementType.toCore context.monomorphization = some coreElementType) :
        ExprLowers context (.array (surfaceHead :: surfaceTail))
          (.array elementType (surfaceHead :: surfaceTail).length)
          (.array coreElementType (coreHead :: coreTail))
    /-- Explicit type arguments determine the nominal substitution before field
        expressions are checked. This permits contextual literals without
        making instance-table contents participate in inference. -/
    | structValueExplicit
        (selected : SelectsStructConstructor context path scheme)
        (arguments : ExplicitNominalArgumentsGround context path
          scheme.genericParameters substitution)
        (instantiated : NominalConstructorInstantiates context scheme.declaration
          scheme.sourceType .structure scheme.genericParameters scheme.requirements
          substitution resolved)
        (fields : StructSchemeFieldsCheck context substitution scheme.fields
          surfaceFields coreFields) :
        ExprLowers context (.structValue path surfaceFields)
          (.nominal scheme.sourceType resolved.typeArguments resolved.constArguments)
          (.structValue resolved.coreType coreFields)
    /-- Without explicit type arguments, a generic struct infers one complete
        substitution from the independently inferred field-expression types. -/
    | structValueInferred
        (selected : SelectsStructConstructor context path scheme)
        (implicitArguments : PathHasNoGenericArguments path)
        (generic : scheme.genericParameters ≠ [])
        (determined : TypesDetermineGenericParameters
          (scheme.fields.map fun field => field.type) scheme.genericParameters)
        (fields : StructSchemeFieldsInfer context substitution scheme.fields
          surfaceFields coreFields)
        (instantiated : NominalConstructorInstantiates context scheme.declaration
          scheme.sourceType .structure scheme.genericParameters scheme.requirements
          substitution resolved) :
        ExprLowers context (.structValue path surfaceFields)
          (.nominal scheme.sourceType resolved.typeArguments resolved.constArguments)
          (.structValue resolved.coreType coreFields)
    /-- Nongeneric struct members are ordinary contextual checking sites. -/
    | structValueNongeneric
        (selected : SelectsStructConstructor context path scheme)
        (implicitArguments : PathHasNoGenericArguments path)
        (nongeneric : scheme.genericParameters = [])
        (instantiated : NominalConstructorInstantiates context scheme.declaration
          scheme.sourceType .structure scheme.genericParameters scheme.requirements
          substitution resolved)
        (fields : StructSchemeFieldsCheck context substitution scheme.fields
          surfaceFields coreFields) :
        ExprLowers context (.structValue path surfaceFields)
          (.nominal scheme.sourceType resolved.typeArguments resolved.constArguments)
          (.structValue resolved.coreType coreFields)
    | unary
        (operand : ExprLowers context surfaceOperand inputGround coreOperand)
        (inputCore : inputGround.toCore context.monomorphization = some inputType)
        (outputCore : outputGround.toCore context.monomorphization = some outputType)
        (typed : Typing.UnaryOpHasType (lowerUnaryOp op) inputType outputType) :
        ExprLowers context (.unary op surfaceOperand) outputGround
          (.unary (lowerUnaryOp op) coreOperand)
    | binary
        (left : ExprLowers context surfaceLeft leftGround coreLeft)
        (right : ExprLowers context surfaceRight rightGround coreRight)
        (leftCore : leftGround.toCore context.monomorphization = some leftType)
        (rightCore : rightGround.toCore context.monomorphization = some rightType)
        (outputCore : outputGround.toCore context.monomorphization = some outputType)
        (typed : Typing.BinaryOpHasType (lowerBinaryOp op)
          leftType rightType outputType) :
        ExprLowers context (.binary op surfaceLeft surfaceRight) outputGround
          (.binary (lowerBinaryOp op) coreLeft coreRight)
    /-- The integer token `0` may be checked as a null pointer when the other
        operand has already fixed the binary operation's domain to pointers.
        It does not infer pointer type in isolation. -/
    | binaryNullPointerRight
        (left : ExprLowers context surfaceLeft (.scalar .rawPtr) coreLeft)
        (null : Elaboration.LiteralElaborates context.target
          (.integer text) (.scalar .rawPtr) coreRight)
        (outputCore : outputGround.toCore context.monomorphization = some outputType)
        (typed : Typing.BinaryOpHasType (lowerBinaryOp op)
          (.scalar .rawPtr) (.scalar .rawPtr) outputType) :
        ExprLowers context
          (.binary op surfaceLeft (.literal (.integer text))) outputGround
          (.binary (lowerBinaryOp op) coreLeft coreRight)
    | binaryNullPointerLeft
        (null : Elaboration.LiteralElaborates context.target
          (.integer text) (.scalar .rawPtr) coreLeft)
        (right : ExprLowers context surfaceRight (.scalar .rawPtr) coreRight)
        (outputCore : outputGround.toCore context.monomorphization = some outputType)
        (typed : Typing.BinaryOpHasType (lowerBinaryOp op)
          (.scalar .rawPtr) (.scalar .rawPtr) outputType) :
        ExprLowers context
          (.binary op (.literal (.integer text)) surfaceRight) outputGround
          (.binary (lowerBinaryOp op) coreLeft coreRight)
    /-- For mixed scalar operands the left operand fixes the operation domain,
        matching the current compiler's result-type propagation. The right
        operand must have one direct, nonidentity conversion into that domain. -/
    | binaryRightCast
        (left : ExprLowers context surfaceLeft (.scalar leftType) coreLeft)
        (right : ExprLowers context surfaceRight (.scalar rightType) coreRight)
        (different : rightType ≠ leftType)
        (notPreferred : ¬ Typing.RightDominatesBinary leftType rightType)
        (conversion : Typing.ScalarCast rightType leftType)
        (outputCore : outputGround.toCore context.monomorphization = some outputType)
        (typed : Typing.BinaryOpHasType (lowerBinaryOp op)
          (.scalar leftType) (.scalar leftType) outputType) :
        ExprLowers context (.binary op surfaceLeft surfaceRight) outputGround
          (.binary (lowerBinaryOp op) coreLeft (.cast leftType coreRight))
    /-- A widening floating type on the right overrides the normal left-domain
        rule. The left operand is explicitly promoted before the core binary
        operation. -/
    | binaryLeftCast
        (left : ExprLowers context surfaceLeft (.scalar leftType) coreLeft)
        (right : ExprLowers context surfaceRight (.scalar rightType) coreRight)
        (preferred : Typing.RightDominatesBinary leftType rightType)
        (conversion : Typing.ScalarCast leftType rightType)
        (outputCore : outputGround.toCore context.monomorphization = some outputType)
        (typed : Typing.BinaryOpHasType (lowerBinaryOp op)
          (.scalar rightType) (.scalar rightType) outputType) :
        ExprLowers context (.binary op surfaceLeft surfaceRight) outputGround
          (.binary (lowerBinaryOp op) (.cast rightType coreLeft) coreRight)
    | assign
        (place : PlaceLowers context surfacePlace placeType corePlace)
        (value : ExprChecks context surfaceValue placeType coreValue)
        (coreType : placeType.toCore context.monomorphization = some type)
        (typed : Typing.AssignOpHasType (lowerAssignOp op) type) :
        ExprLowers context (.assign op surfacePlace surfaceValue) .unit
          (.assign (lowerAssignOp op) corePlace coreValue)
    | printI32
        (callee : surfaceCallee = .path path)
        (builtin : builtinIntrinsic? path = some .printI32)
        (argument : ExprChecks context surfaceArgument
          (.scalar (.signed .i32)) coreArgument) :
        ExprLowers context (.call surfaceCallee [surfaceArgument]) .unit
          (.intrinsic .printI32 coreArgument)
    | assert
        (callee : surfaceCallee = .path path)
        (builtin : builtinIntrinsic? path = some .assert)
        (argument : ExprChecks context surfaceArgument (.scalar .bool) coreArgument) :
        ExprLowers context (.call surfaceCallee [surfaceArgument]) .unit
          (.intrinsic .assert coreArgument)
    | i32ArrayDataPtr
        (callee : surfaceCallee = .path path)
        (builtin : builtinIntrinsic? path = some .i32ArrayDataPtr)
        (argument : ExprChecks context surfaceArgument
          (.array (.scalar (.signed .i32)) length) coreArray) :
        ExprLowers context (.call surfaceCallee [surfaceArgument])
          (.scalar .rawPtr) (.i32ArrayDataPtr coreArray)
    | directCall
        (arguments : ExprsCheck context surfaceArguments argumentTypes coreArguments)
        (resolved : ResolvesDirectCall context path argumentTypes scheme resolvedInstance)
        (notIntrinsic : builtinIntrinsic? path = none)
        (callee : surfaceCallee = .path path) :
        ExprLowers context (.call surfaceCallee surfaceArguments) resolvedInstance.returnType
          (.call resolvedInstance.function coreArguments)
    | associatedCall
        (split : associatedFunctionPath? path = some (ownerPath, name))
        (owner : TypeGrounds context (.path ownerPath.segments) receiverType)
        (arguments : ExprsCheck context surfaceArguments argumentTypes coreArguments)
        (lowered : Elaboration.AssociatedCallLowers context.implementations
          context.methods context.methodInstances context.currentModule receiverType
          name coreArguments argumentTypes resultType coreCall) :
        ExprLowers context (.call (.path path) surfaceArguments) resultType coreCall
    | variantCallExplicit
        (selected : SelectsVariantConstructor context path scheme)
        (notIntrinsic : builtinIntrinsic? path = none)
        (argumentsGround : ExplicitNominalArgumentsGround context path
          scheme.genericParameters substitution)
        (instantiated : NominalConstructorInstantiates context scheme.nominalDeclaration
          scheme.sourceType .enumeration scheme.genericParameters scheme.requirements
          substitution resolved)
        (arguments : SymbolicExprsCheck context substitution surfaceArguments
          scheme.payload coreArguments) :
        ExprLowers context (.call (.path path) surfaceArguments)
          (.nominal scheme.sourceType resolved.typeArguments resolved.constArguments)
          (.enumValue resolved.coreType scheme.variant coreArguments)
    | variantCallInferred
        (selected : SelectsVariantConstructor context path scheme)
        (notIntrinsic : builtinIntrinsic? path = none)
        (implicitArguments : PathHasNoGenericArguments path)
        (generic : scheme.genericParameters ≠ [])
        (determined : TypesDetermineGenericParameters scheme.payload
          scheme.genericParameters)
        (arguments : SymbolicExprsInfer context substitution surfaceArguments
          scheme.payload coreArguments)
        (instantiated : NominalConstructorInstantiates context scheme.nominalDeclaration
          scheme.sourceType .enumeration scheme.genericParameters scheme.requirements
          substitution resolved) :
        ExprLowers context (.call (.path path) surfaceArguments)
          (.nominal scheme.sourceType resolved.typeArguments resolved.constArguments)
          (.enumValue resolved.coreType scheme.variant coreArguments)
    | variantCallNongeneric
        (selected : SelectsVariantConstructor context path scheme)
        (notIntrinsic : builtinIntrinsic? path = none)
        (implicitArguments : PathHasNoGenericArguments path)
        (nongeneric : scheme.genericParameters = [])
        (instantiated : NominalConstructorInstantiates context scheme.nominalDeclaration
          scheme.sourceType .enumeration scheme.genericParameters scheme.requirements
          substitution resolved)
        (arguments : SymbolicExprsCheck context substitution surfaceArguments
          scheme.payload coreArguments) :
        ExprLowers context (.call (.path path) surfaceArguments)
          (.nominal scheme.sourceType resolved.typeArguments resolved.constArguments)
          (.enumValue resolved.coreType scheme.variant coreArguments)
    | methodCall
        (receiver : ExprLowers context surfaceReceiver sourceReceiverType sourceReceiver)
        (receiverBase : Elaboration.MemberBaseLowers context.monomorphization
          sourceReceiverType sourceReceiver receiverType coreReceiver)
        (arguments : ExprsCheck context surfaceArguments argumentTypes coreArguments)
        (lowered : Elaboration.MethodCallLowers context.implementations context.methods
          context.methodInstances context.currentModule context.monomorphization
          coreReceiver receiverType name coreArguments argumentTypes resultType coreCall) :
        ExprLowers context (.call (.member surfaceReceiver name) surfaceArguments)
          resultType coreCall
    | indexArray
        (base : ExprLowers context surfaceBase (.array elementType length) coreBase)
        (index : ExprLowers context surfaceIndex indexGround coreIndex)
        (indexCore : indexGround.toCore context.monomorphization = some indexType)
        (integer : Typing.IntegerTy indexType) :
        ExprLowers context (.index surfaceBase surfaceIndex) elementType
          (.index coreBase coreIndex)
    | indexSlice
        (base : ExprLowers context surfaceBase (.slice elementType) coreBase)
        (index : ExprLowers context surfaceIndex indexGround coreIndex)
        (indexCore : indexGround.toCore context.monomorphization = some indexType)
        (integer : Typing.IntegerTy indexType) :
        ExprLowers context (.index surfaceBase surfaceIndex) elementType
          (.index coreBase coreIndex)
    | field
        (base : ExprLowers context surfaceBase sourceReceiverType sourceBase)
        (memberBase : Elaboration.MemberBaseLowers context.monomorphization
          sourceReceiverType sourceBase receiverType coreBase)
        (selected : SelectsField context receiverType name entry) :
        ExprLowers context (.member surfaceBase name) entry.type
          (.field coreBase entry.field)
    | matchValue
        (scrutinee : ExprLowers context surfaceScrutinee scrutineeType coreScrutinee)
        (arms : MatchArmsInfer context scrutineeType resultType
          surfaceArms coreArms) :
        ExprLowers context (.matchValue surfaceScrutinee surfaceArms) resultType
          (.matchValue coreScrutinee coreArms)

  inductive ExprsLower :
      Context → List Surface.Expr → List Static.GroundTy → List Core.Expr → Prop where
    | nil : ExprsLower context [] [] []
    | cons
        (head : ExprLowers context surfaceHead type coreHead)
        (tail : ExprsLower context surfaceTail types coreTail) :
        ExprsLower context (surfaceHead :: surfaceTail) (type :: types)
          (coreHead :: coreTail)

  /-- Checking against an expected type is the sole source-level coercion
      boundary. A scalar expression may receive at most one explicit core
      cast; the premise itself must infer without another contextual cast. -/
  inductive ExprChecks :
      Context → Surface.Expr → Static.GroundTy → Core.Expr → Prop where
    | exact
        (lowered : ExprLowers context surfaceExpression type coreExpression) :
        ExprChecks context surfaceExpression type coreExpression
    | literal
        (coreType : Core.Ty)
        (lowered : Elaboration.LiteralElaborates
          context.target literal coreType coreExpression)
        (grounded : type.toCore context.monomorphization = some coreType) :
        ExprChecks context (.literal literal) type coreExpression
    | signedMinimumLiteral
        (lowered : Elaboration.SignedMinimumLiteralElaborates
          context.target text signedType coreExpression)
        (grounded : type.toCore context.monomorphization =
          some (.scalar (.signed signedType))) :
        ExprChecks context (.unary .negative (.literal (.integer text)))
          type coreExpression
    | unaryLiteral
        (lowered : Elaboration.LiteralElaborates
          context.target literal coreType coreOperand)
        (grounded : type.toCore context.monomorphization = some coreType)
        (typed : Typing.UnaryOpHasType (lowerUnaryOp op) coreType coreType) :
        ExprChecks context (.unary op (.literal literal)) type
          (.unary (lowerUnaryOp op) coreOperand)
    | array
        (elements : ExprsCheck context surfaceElements
          (List.replicate surfaceElements.length elementType) coreElements)
        (elementCore : elementType.toCore context.monomorphization = some coreElementType) :
        ExprChecks context (.array surfaceElements)
          (.array elementType surfaceElements.length)
          (.array coreElementType coreElements)
    /-- An expected nominal type determines a struct's generic substitution;
        explicit path arguments, when present, must agree with it. -/
    | structValue
        (selected : SelectsStructConstructor context path scheme)
        (pathArguments : NominalPathArgumentsCompatible context path
          scheme.genericParameters substitution)
        (instantiated : NominalConstructorInstantiates context scheme.declaration
          scheme.sourceType .structure scheme.genericParameters scheme.requirements
          substitution resolved)
        (expected : type =
          .nominal scheme.sourceType resolved.typeArguments resolved.constArguments)
        (fields : StructSchemeFieldsCheck context substitution scheme.fields
          surfaceFields coreFields) :
        ExprChecks context (.structValue path surfaceFields) type
          (.structValue resolved.coreType coreFields)
    /-- Context similarly fixes a generic enum constructor before its payload
        expressions are checked. -/
    | variantCall
        (selected : SelectsVariantConstructor context path scheme)
        (notIntrinsic : builtinIntrinsic? path = none)
        (pathArguments : NominalPathArgumentsCompatible context path
          scheme.genericParameters substitution)
        (instantiated : NominalConstructorInstantiates context scheme.nominalDeclaration
          scheme.sourceType .enumeration scheme.genericParameters scheme.requirements
          substitution resolved)
        (expected : type =
          .nominal scheme.sourceType resolved.typeArguments resolved.constArguments)
        (arguments : SymbolicExprsCheck context substitution surfaceArguments
          scheme.payload coreArguments) :
        ExprChecks context (.call (.path path) surfaceArguments) type
          (.enumValue resolved.coreType scheme.variant coreArguments)
    | scalarCast
        (lowered : ExprLowers context surfaceExpression
          (.scalar sourceType) coreExpression)
        (notContextualLiteral : ¬ ContextualScalarLiteralApplies context.target
          surfaceExpression targetType)
        (different : sourceType ≠ targetType)
        (conversion : Typing.ScalarCast sourceType targetType) :
        ExprChecks context surfaceExpression (.scalar targetType)
          (.cast targetType coreExpression)
    | arrayToSlice
        (array : ExprLowers context surfaceExpression
          (.array elementType length) coreArray)
        (coreElement : elementType.toCore context.monomorphization = some coreElementType) :
        ExprChecks context surfaceExpression (.slice elementType)
          (.arrayToSlice coreElementType coreArray)

  inductive ExprsCheck :
      Context → List Surface.Expr → List Static.GroundTy → List Core.Expr → Prop where
    | nil : ExprsCheck context [] [] []
    | cons
        (head : ExprChecks context surfaceHead type coreHead)
        (tail : ExprsCheck context surfaceTail types coreTail) :
        ExprsCheck context (surfaceHead :: surfaceTail) (type :: types)
          (coreHead :: coreTail)

  inductive PlaceLowers :
      Context → Surface.Expr → Static.GroundTy → Core.Place → Prop where
    | local
        (name : Surface.Name)
        (single : singleNamePath? path = some name)
        (resolved : ResolvesLocal context.locals name binding) :
        PlaceLowers context (.path path) binding.type (.local binding.id)
    | selfValue
        (resolved : ResolvesLocal context.locals "self" binding) :
        PlaceLowers context .selfValue binding.type (.local binding.id)
    | field
        (base : PlaceLowers context surfaceBase receiverType coreBase)
        (selected : SelectsField context receiverType name entry) :
        PlaceLowers context (.member surfaceBase name) entry.type
          (.field coreBase entry.field)
    | indexArray
        (base : PlaceLowers context surfaceBase (.array elementType length) coreBase)
        (index : ExprLowers context surfaceIndex indexGround coreIndex)
        (indexCore : indexGround.toCore context.monomorphization = some indexType)
        (integer : Typing.IntegerTy indexType) :
        PlaceLowers context (.index surfaceBase surfaceIndex) elementType
          (.index coreBase coreIndex)
    | indexSlice
        (base : PlaceLowers context surfaceBase (.slice elementType) coreBase)
        (index : ExprLowers context surfaceIndex indexGround coreIndex)
        (indexCore : indexGround.toCore context.monomorphization = some indexType)
        (integer : Typing.IntegerTy indexType) :
        PlaceLowers context (.index surfaceBase surfaceIndex) elementType
          (.index coreBase coreIndex)

  inductive PatternLowers :
      Context → Static.GroundTy → Surface.Pattern → Core.Pattern →
        List LocalBinding → Prop where
    | wildcard : PatternLowers context type .wildcard .wildcard []
    | bind
        (single : singleNamePath? path = some name)
        (notVariant : NoGlobalValueResolution context path)
        (id : VarId)
        (fresh : FreshLocalId context id) :
        PatternLowers context type (.path path []) (.bind id) [{ name, id, type }]
    | integer
        (coreType : type.toCore context.monomorphization = some loweredType)
        (literal : Elaboration.LiteralElaborates context.target (.integer text)
          loweredType (.value value)) :
        PatternLowers context type (.integer text) (.literal value) []
    | boolean : PatternLowers context (.scalar .bool) (.boolean value)
        (.literal (.boolean value)) []
    | variant
        (selected : SelectsVariant context receiver path entry)
        (payload : PatternsLower context entry.payload surfacePayload corePayload bindings)
        (fresh : PatternBindingsFresh context bindings) :
        PatternLowers context receiver (.path path surfacePayload)
          (.enumVariant entry.coreType entry.variant corePayload) bindings

  inductive PatternsLower :
      Context → List Static.GroundTy → List Surface.Pattern →
        List Core.Pattern → List LocalBinding → Prop where
    | nil : PatternsLower context [] [] [] []
    | cons
        (head : PatternLowers context headType surfaceHead coreHead headBindings)
        (tail : PatternsLower context tailTypes surfaceTail coreTail tailBindings) :
        PatternsLower context (headType :: tailTypes) (surfaceHead :: surfaceTail)
          (coreHead :: coreTail) (headBindings ++ tailBindings)

  inductive MatchArmsLower :
      Context → Static.GroundTy → Static.GroundTy →
        List (Surface.Pattern × Surface.Expr) →
        List (Core.Pattern × Core.Expr) → Prop where
    | nil : MatchArmsLower context scrutineeType resultType [] []
    | cons
        (pattern : PatternLowers context scrutineeType
          surfacePattern corePattern bindings)
        (body : ExprChecks (context.bindLocals bindings)
          surfaceBody resultType coreBody)
        (tail : MatchArmsLower context scrutineeType resultType surfaceTail coreTail) :
        MatchArmsLower context scrutineeType resultType
          ((surfacePattern, surfaceBody) :: surfaceTail)
          ((corePattern, coreBody) :: coreTail)

  /-- A match expression obtains its result type from its first arm. Remaining
      arms are checked against that type, retaining ordinary contextual
      literals and scalar conversions without leaving the result existential. -/
  inductive MatchArmsInfer :
      Context → Static.GroundTy → Static.GroundTy →
        List (Surface.Pattern × Surface.Expr) →
        List (Core.Pattern × Core.Expr) → Prop where
    | cons
        (pattern : PatternLowers context scrutineeType
          surfacePattern corePattern bindings)
        (body : ExprLowers (context.bindLocals bindings)
          surfaceBody resultType coreBody)
        (tail : MatchArmsLower context scrutineeType resultType surfaceTail coreTail) :
        MatchArmsInfer context scrutineeType resultType
          ((surfacePattern, surfaceBody) :: surfaceTail)
          ((corePattern, coreBody) :: coreTail)

  /-- Symbolic member types are instantiated first, then used as contextual
      checking types. -/
  inductive StructSchemeFieldsCheck :
      Context → Static.Substitution → List StructFieldScheme →
        List (Surface.Name × Surface.Expr) → List Core.Expr → Prop where
    | nil : StructSchemeFieldsCheck context substitution [] [] []
    | cons
        (removed : RemovesNamedField field.name surfaceFields surfaceValue remainder)
        (instantiated : field.type.instantiate substitution = some groundType)
        (value : ExprChecks context surfaceValue groundType coreValue)
        (tail : StructSchemeFieldsCheck context substitution fieldTail remainder coreTail) :
        StructSchemeFieldsCheck context substitution (field :: fieldTail)
          surfaceFields (coreValue :: coreTail)

  /-- Inference observes field-expression types before matching them against
      symbolic member types. All generic parameters must subsequently be bound
      by `NominalConstructorInstantiates`. -/
  inductive StructSchemeFieldsInfer :
      Context → Static.Substitution → List StructFieldScheme →
        List (Surface.Name × Surface.Expr) → List Core.Expr → Prop where
    | nil : StructSchemeFieldsInfer context substitution [] [] []
    | cons
        (removed : RemovesNamedField field.name surfaceFields surfaceValue remainder)
        (value : ExprLowers context surfaceValue groundType coreValue)
        (typeMatches : Static.TyMatches substitution field.type groundType)
        (tail : StructSchemeFieldsInfer context substitution fieldTail remainder coreTail) :
        StructSchemeFieldsInfer context substitution (field :: fieldTail)
          surfaceFields (coreValue :: coreTail)

  inductive SymbolicExprsCheck :
      Context → Static.Substitution → List Surface.Expr →
        List Static.Ty → List Core.Expr → Prop where
    | nil : SymbolicExprsCheck context substitution [] [] []
    | cons
        (instantiated : symbolicType.instantiate substitution = some groundType)
        (head : ExprChecks context surfaceHead groundType coreHead)
        (tail : SymbolicExprsCheck context substitution surfaceTail symbolicTail coreTail) :
        SymbolicExprsCheck context substitution (surfaceHead :: surfaceTail)
          (symbolicType :: symbolicTail) (coreHead :: coreTail)

  inductive SymbolicExprsInfer :
      Context → Static.Substitution → List Surface.Expr →
        List Static.Ty → List Core.Expr → Prop where
    | nil : SymbolicExprsInfer context substitution [] [] []
    | cons
        (head : ExprLowers context surfaceHead groundType coreHead)
        (typeMatches : Static.TyMatches substitution symbolicType groundType)
        (tail : SymbolicExprsInfer context substitution surfaceTail symbolicTail coreTail) :
        SymbolicExprsInfer context substitution (surfaceHead :: surfaceTail)
          (symbolicType :: symbolicTail) (coreHead :: coreTail)
end

inductive RangeBoundLowers (context : Context) :
    Surface.RangeBound → Core.Expr → Prop where
  | integer
      (lowered : ExprChecks context (.literal (.integer text))
        (.scalar (.signed .i32)) expression) :
      RangeBoundLowers context (.integer text) expression
  | postfix
      (formed : Surface.RangeBoundPostfix surfaceExpression)
      (lowered : ExprChecks context surfaceExpression
        (.scalar (.signed .i32)) expression) :
      RangeBoundLowers context (.postfix surfaceExpression) expression

inductive RangeLowers (context : Context) :
    Surface.RangeKind → Option Surface.RangeBound → Option Surface.RangeBound →
      Core.Expr → Option Core.Expr → Bool → Prop where
  | full : RangeLowers context .full none none
      (.value (.signed .i32 0)) none false
  | from (start : RangeBoundLowers context surfaceStart coreStart) :
      RangeLowers context .from (some surfaceStart) none coreStart none false
  | toExclusive (stop : RangeBoundLowers context surfaceStop coreStop) :
      RangeLowers context .toExclusive none (some surfaceStop)
        (.value (.signed .i32 0)) (some coreStop) false
  | toInclusive (stop : RangeBoundLowers context surfaceStop coreStop) :
      RangeLowers context .toInclusive none (some surfaceStop)
        (.value (.signed .i32 0)) (some coreStop) true
  | exclusive
      (start : RangeBoundLowers context surfaceStart coreStart)
      (stop : RangeBoundLowers context surfaceStop coreStop) :
      RangeLowers context .exclusive (some surfaceStart) (some surfaceStop)
        coreStart (some coreStop) false
  | inclusive
      (start : RangeBoundLowers context surfaceStart coreStart)
      (stop : RangeBoundLowers context surfaceStop coreStop) :
      RangeLowers context .inclusive (some surfaceStart) (some surfaceStop)
        coreStart (some coreStop) true

def coreRangeTypePath : Surface.Path := {
  segments := [.mk "core" [], .mk "range" [], .mk "Range" []]
}

def coreRangeInclusiveTypePath : Surface.Path := {
  segments := [.mk "core" [], .mk "range" [], .mk "RangeInclusive" []]
}

/-- The current compiler recognizes the standard-library `Range<i32>` and
    `RangeInclusive<i32>` nominal identities when a `for` iterable is a path.
    It reads their declaration-order `start` and `end` fields once and then
    uses the ordinary core range loop. Keeping the canonical type selection and
    field lookup in this judgment prevents unrelated two-field structs from
    acquiring range semantics. -/
inductive NamedRangeLowers (context : Context) (path : Surface.Path) :
    Core.Expr → Core.Expr → Bool → Prop where
  | exclusive
      (constructor : StructConstructorScheme)
      (selected : SelectsStructConstructor context coreRangeTypePath constructor)
      (iterable : ExprLowers context (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        coreIterable)
      (startField endField : FieldEntry)
      (startSelected : SelectsField context
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "start" startField)
      (endSelected : SelectsField context
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "end" endField)
      (startType : startField.type = .scalar (.signed .i32))
      (endType : endField.type = .scalar (.signed .i32)) :
      NamedRangeLowers context path (.field coreIterable startField.field)
        (.field coreIterable endField.field) false
  | inclusive
      (constructor : StructConstructorScheme)
      (selected : SelectsStructConstructor context coreRangeInclusiveTypePath
        constructor)
      (iterable : ExprLowers context (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        coreIterable)
      (startField endField : FieldEntry)
      (startSelected : SelectsField context
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "start" startField)
      (endSelected : SelectsField context
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "end" endField)
      (startType : startField.type = .scalar (.signed .i32))
      (endType : endField.type = .scalar (.signed .i32)) :
      NamedRangeLowers context path (.field coreIterable startField.field)
        (.field coreIterable endField.field) true

/-- A statement list is lowered with an explicit fresh-ID supply. `let` wraps
    the remaining list, exactly matching lexical scope in `Core.Stmt`; branch
    locals do not escape, while the maximum consumed ID is carried forward. -/
inductive StmtsLower :
    Context → VarId → List Surface.Stmt → Core.Stmt → VarId → Prop where
  | nil : StmtsLower context next [] .skip next
  | expression
      (head : ExprLowers context surfaceExpression type coreExpression)
      (tail : StmtsLower context next surfaceTail coreTail final) :
      StmtsLower context next (.expression surfaceExpression :: surfaceTail)
        (.sequence (.expression coreExpression) coreTail) final
  | letInferred
      (fresh : FreshLocalId context next)
      (initializer : ExprLowers context surfaceInitializer type coreInitializer)
      (coreType : type.toCore context.monomorphization = some loweredType)
      (tail : StmtsLower (context.bindLocal name next type) (next + 1)
        surfaceTail coreTail final) :
      StmtsLower context next
        (.letLocal name none (some surfaceInitializer) :: surfaceTail)
        (.letLocal next loweredType coreInitializer coreTail) final
  | letAnnotated
      (fresh : FreshLocalId context next)
      (annotation : TypeGrounds context surfaceType type)
      (initializer : ExprChecks context surfaceInitializer type coreInitializer)
      (coreType : type.toCore context.monomorphization = some loweredType)
      (tail : StmtsLower (context.bindLocal name next type) (next + 1)
        surfaceTail coreTail final) :
      StmtsLower context next
        (.letLocal name (some surfaceType) (some surfaceInitializer) :: surfaceTail)
        (.letLocal next loweredType coreInitializer coreTail) final
  | letUninitialized
      (fresh : FreshLocalId context next)
      (annotation : TypeGrounds context surfaceType type)
      (coreType : type.toCore context.monomorphization = some loweredType)
      (tail : StmtsLower (context.bindLocal name next type) (next + 1)
        surfaceTail coreTail final) :
      StmtsLower context next
        (.letLocal name (some surfaceType) none :: surfaceTail)
        (.letUninitialized next loweredType coreTail) final
  | returnUnit
      (tail : StmtsLower context next surfaceTail coreTail final) :
      StmtsLower context next (.returnValue none :: surfaceTail)
        (.sequence (.returnValue none) coreTail) final
  | returnValue
      (value : ExprChecks context surfaceValue type coreValue)
      (tail : StmtsLower context next surfaceTail coreTail final) :
      StmtsLower context next (.returnValue (some surfaceValue) :: surfaceTail)
        (.sequence (.returnValue (some coreValue)) coreTail) final
  | ifThenElse
      (condition : ExprChecks context surfaceCondition
        (.scalar .bool) coreCondition)
      (thenBody : StmtsLower context next surfaceThen coreThen thenNext)
      (elseBody : StmtsLower context next surfaceElse coreElse elseNext)
      (tail : StmtsLower context (Nat.max thenNext elseNext)
        surfaceTail coreTail final) :
      StmtsLower context next
        (.ifThenElse surfaceCondition surfaceThen surfaceElse :: surfaceTail)
        (.sequence (.ifThenElse coreCondition coreThen coreElse) coreTail) final
  | whileLoop
      (condition : ExprChecks context surfaceCondition
        (.scalar .bool) coreCondition)
      (body : StmtsLower context next surfaceBody coreBody bodyNext)
      (tail : StmtsLower context bodyNext surfaceTail coreTail final) :
      StmtsLower context next (.whileLoop surfaceCondition surfaceBody :: surfaceTail)
        (.sequence (.whileLoop coreCondition coreBody) coreTail) final
  | forArray
      (fresh : FreshLocalId context next)
      (iterable : ExprLowers context (.path path)
        (.array elementType length) coreIterable)
      (body : StmtsLower (context.bindLocal name next elementType) (next + 1)
        surfaceBody coreBody bodyNext)
      (tail : StmtsLower context bodyNext surfaceTail coreTail final) :
      StmtsLower context next
        (.forLoop name (.path path) surfaceBody :: surfaceTail)
        (.sequence (.forValues next coreIterable coreBody) coreTail) final
  | forSlice
      (fresh : FreshLocalId context next)
      (iterable : ExprLowers context (.path path)
        (.slice elementType) coreIterable)
      (body : StmtsLower (context.bindLocal name next elementType) (next + 1)
        surfaceBody coreBody bodyNext)
      (tail : StmtsLower context bodyNext surfaceTail coreTail final) :
      StmtsLower context next
        (.forLoop name (.path path) surfaceBody :: surfaceTail)
        (.sequence (.forValues next coreIterable coreBody) coreTail) final
  | forNamedRange
      (fresh : FreshLocalId context next)
      (range : NamedRangeLowers context path coreStart coreStop inclusive)
      (body : StmtsLower
        (context.bindLocal name next (.scalar (.signed .i32))) (next + 1)
        surfaceBody coreBody bodyNext)
      (tail : StmtsLower context bodyNext surfaceTail coreTail final) :
      StmtsLower context next
        (.forLoop name (.path path) surfaceBody :: surfaceTail)
        (.sequence (.forRange next coreStart (some coreStop) inclusive coreBody)
          coreTail) final
  | forRange
      (fresh : FreshLocalId context next)
      (range : RangeLowers context kind surfaceStart surfaceStop coreStart coreStop inclusive)
      (body : StmtsLower
        (context.bindLocal name next (.scalar (.signed .i32))) (next + 1)
        surfaceBody coreBody bodyNext)
      (tail : StmtsLower context bodyNext surfaceTail coreTail final) :
      StmtsLower context next
        (.forLoop name (.range kind surfaceStart surfaceStop) surfaceBody :: surfaceTail)
        (.sequence (.forRange next coreStart coreStop inclusive coreBody) coreTail) final
  | breakLoop
      (tail : StmtsLower context next surfaceTail coreTail final) :
      StmtsLower context next (.breakLoop :: surfaceTail)
        (.sequence .breakLoop coreTail) final
  | continueLoop
      (tail : StmtsLower context next surfaceTail coreTail final) :
      StmtsLower context next (.continueLoop :: surfaceTail)
        (.sequence .continueLoop coreTail) final
  | block
      (body : StmtsLower context next surfaceBody coreBody bodyNext)
      (tail : StmtsLower context bodyNext surfaceTail coreTail final) :
      StmtsLower context next (.block surfaceBody :: surfaceTail)
        (.sequence coreBody coreTail) final

/-- This is the checked surface-to-core boundary: lowering resolves names and
    inference, while the ordinary core typing judgment independently validates
    the term against the selected program. -/
structure TypedExprLowering
    (program : Core.Program) (context : Context)
    (surface : Surface.Expr) where
  groundType : Static.GroundTy
  coreType : Core.Ty
  core : Core.Expr
  lowers : ExprLowers context surface groundType core
  grounded : groundType.toCore context.monomorphization = some coreType
  target : program.target = context.target
  typed : Typing.ExprHasType program context.coreLocals core coreType

structure TypedStmtsLowering
    (program : Core.Program) (context : Context) (returnType : Core.Ty)
    (inLoop : Bool) (next : VarId) (surface : List Surface.Stmt) where
  core : Core.Stmt
  finalNext : VarId
  lowers : StmtsLower context next surface core finalNext
  target : program.target = context.target
  typed : Typing.StmtHasType program returnType context.coreLocals inLoop core

end Lanius.SurfaceElaboration
